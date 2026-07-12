#define _GNU_SOURCE
#define MA_NO_DEVICE_IO
#define MA_NO_RESOURCE_MANAGER
#define MA_IMPLEMENTATION

#include "miniaudio.h"

#include <ctype.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <linux/input.h>
#include <math.h>
#include <pthread.h>
#include <setjmp.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/poll.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>

#include <jpeglib.h>
#include <png.h>

#ifdef PLUMOS_MUSIC_ENABLE_ALSA
#include <alsa/asoundlib.h>
#endif

#ifdef PLUMOS_MUSIC_ENABLE_FFMPEG
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/channel_layout.h>
#include <libavutil/error.h>
#include <libavutil/rational.h>
#include <libavutil/samplefmt.h>
#include <libswresample/swresample.h>
#endif

#if defined(__has_include)
#if __has_include(<sys/soundcard.h>)
#include <sys/soundcard.h>
#define PLUMOS_MUSIC_HAS_OSS 1
#endif
#endif

#include "plumos_music_v90s_renderer.h"

#ifndef PATH_MAX
#define PATH_MAX 4096
#endif

#define MUSIC_MAX_TRACKS 2048
#define MUSIC_NAME_MAX 256
#define MUSIC_OUTPUT_RATE 48000
#define MUSIC_OUTPUT_CHANNELS 2
#define MUSIC_AUDIO_CHUNK_FRAMES 768
#define MUSIC_LIST_ROWS 7
#define MUSIC_ABS_AXIS_DEADZONE 512
#define MUSIC_BOTTOM_PANEL_HEIGHT 154.0f
#define MUSIC_ART_MAX_BYTES (6u * 1024u * 1024u)
#define MUSIC_ART_MAX_DIMENSION 2048

struct music_track {
  char path[PATH_MAX];
  char name[MUSIC_NAME_MAX];
};

struct album_art {
  unsigned char *rgba;
  int width;
  int height;
  unsigned int generation;
  char status[64];
};

struct album_art_texture {
  unsigned char *rgba;
  int width;
  int height;
  unsigned int generation;
};

struct eq_preset {
  const char *name;
  float low;
  float mid;
  float high;
};

static const struct eq_preset k_eq_presets[] = {
    {"Flat", 1.00f, 1.00f, 1.00f},
    {"Bass", 1.35f, 0.98f, 0.94f},
    {"Treble", 0.92f, 1.00f, 1.28f},
    {"Vocal", 0.88f, 1.22f, 1.05f},
    {"Soft", 0.96f, 0.94f, 0.88f},
};

struct audio_filter {
  float low_state[MUSIC_OUTPUT_CHANNELS];
  float high_lp_state[MUSIC_OUTPUT_CHANNELS];
  int initialized;
};

struct music_audio_output {
  int fd;
#ifdef PLUMOS_MUSIC_ENABLE_ALSA
  snd_pcm_t *alsa;
#endif
};

enum music_decoder_kind {
  MUSIC_DECODER_NONE = 0,
  MUSIC_DECODER_MINIAUDIO,
  MUSIC_DECODER_FFMPEG,
};

#ifdef PLUMOS_MUSIC_ENABLE_FFMPEG
struct ffmpeg_audio_decoder {
  AVFormatContext *format;
  AVCodecContext *codec;
  SwrContext *swr;
  AVPacket *packet;
  AVFrame *frame;
  int stream_index;
  float *pending;
  ma_uint64 pending_frames;
  ma_uint64 pending_pos;
  int eof_sent;
  ma_uint64 length_frames;
};
#endif

struct player_state {
  struct music_track tracks[MUSIC_MAX_TRACKS];
  int track_count;
  int selected;
  int current;
  int scroll;

  pthread_mutex_t lock;
  pthread_t audio_thread;
  int audio_thread_started;
  volatile int running;
  volatile int fast_exit_requested;

  ma_decoder decoder;
#ifdef PLUMOS_MUSIC_ENABLE_FFMPEG
  struct ffmpeg_audio_decoder ffmpeg_decoder;
#endif
  enum music_decoder_kind decoder_kind;
  int decoder_ready;
  int playing;
  int paused;
  ma_uint64 position_frames;
  ma_uint64 length_frames;
  int seek_delta_seconds;
  int eq_index;
  float volume;
  char status[192];
  char audio_status[128];
  char input_status[128];
  struct album_art art;
};

static long long monotonic_ms(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (long long)ts.tv_sec * 1000LL + ts.tv_nsec / 1000000LL;
}

static long long parse_env_ms(const char *name) {
  const char *value = getenv(name);
  char *end = NULL;
  long long parsed;
  if (!value || !value[0]) {
    return 0;
  }
  errno = 0;
  parsed = strtoll(value, &end, 10);
  if (errno != 0 || end == value || parsed < 0) {
    return 0;
  }
  return parsed;
}

static int lower_audio_extension(const char *name, char *out, size_t out_size) {
  const char *dot = strrchr(name, '.');
  size_t i;
  if (!out || out_size == 0) {
    return 0;
  }
  out[0] = '\0';
  if (!dot || dot[1] == '\0') {
    return 0;
  }
  dot++;
  for (i = 0; i + 1 < out_size && dot[i]; i++) {
    out[i] = (char)tolower((unsigned char)dot[i]);
  }
  out[i] = '\0';
  return out[0] != '\0';
}

static int is_miniaudio_preferred_audio_ext(const char *name) {
  char ext[16];
  if (!lower_audio_extension(name, ext, sizeof(ext))) {
    return 0;
  }
  return strcmp(ext, "mp3") == 0 || strcmp(ext, "flac") == 0 ||
         strcmp(ext, "wav") == 0;
}

static int str_ends_with_audio_ext(const char *name) {
  static const char *const exts[] = {
      "mp3",  "flac", "wav",  "m4a", "m4b", "mp4", "aac",
      "ogg",  "oga",  "opus", "wma", "aiff", "aif", "aifc",
      "au",   "snd",  "caf",  "ac3", "wv",  "ape", "mpc",
      "tta",  "mka",  "webm", "3gp", "3g2", "amr", "ra",
      "rm",   "dts",  "oma",  "adx", "dsf", "dff", "mod",
      "xm",   "s3m",  "it",   "mptm", "669", "amf", "ams",
      "dbm",  "dmf",  "dsm",  "far", "mdl", "med", "mtm",
      "okt",  "ptm",  "stm",  "ult", "umx", "wow", "vgm",
      "vgz",  "spc",  "nsf",  "gbs", "gym", "hes", "sap",
      "ay",   "kss",
  };
  char ext[16];
  size_t i;
  if (!lower_audio_extension(name, ext, sizeof(ext))) {
    return 0;
  }
  for (i = 0; i < sizeof(exts) / sizeof(exts[0]); i++) {
    if (strcmp(ext, exts[i]) == 0) {
      return 1;
    }
  }
  return 0;
}

static const char *base_name(const char *path) {
  const char *slash = strrchr(path, '/');
  return slash ? slash + 1 : path;
}

static void strip_audio_extension(const char *in, char *out, size_t out_size) {
  const char *name = base_name(in);
  const char *dot = strrchr(name, '.');
  size_t len;
  if (!out || out_size == 0) {
    return;
  }
  if (!dot || dot == name) {
    snprintf(out, out_size, "%s", name);
    return;
  }
  len = (size_t)(dot - name);
  if (len >= out_size) {
    len = out_size - 1;
  }
  memcpy(out, name, len);
  out[len] = '\0';
}

static int add_track(struct player_state *state, const char *path) {
  struct music_track *track;
  if (!state || !path || state->track_count >= MUSIC_MAX_TRACKS) {
    return 0;
  }
  track = &state->tracks[state->track_count++];
  snprintf(track->path, sizeof(track->path), "%s", path);
  strip_audio_extension(path, track->name, sizeof(track->name));
  return 1;
}

static void scan_dir_recursive(struct player_state *state, const char *dir, int depth) {
  DIR *d;
  struct dirent *ent;
  if (!state || !dir || depth > 8 || state->track_count >= MUSIC_MAX_TRACKS) {
    return;
  }
  d = opendir(dir);
  if (!d) {
    return;
  }
  while ((ent = readdir(d)) != NULL) {
    char path[PATH_MAX];
    struct stat st;
    if (strcmp(ent->d_name, ".") == 0 || strcmp(ent->d_name, "..") == 0 ||
        ent->d_name[0] == '.') {
      continue;
    }
    if (snprintf(path, sizeof(path), "%s/%s", dir, ent->d_name) >= (int)sizeof(path)) {
      continue;
    }
    if (stat(path, &st) != 0) {
      continue;
    }
    if (S_ISDIR(st.st_mode)) {
      scan_dir_recursive(state, path, depth + 1);
    } else if (S_ISREG(st.st_mode) && str_ends_with_audio_ext(ent->d_name)) {
      add_track(state, path);
    }
  }
  closedir(d);
}

static int track_compare(const void *a, const void *b) {
  const struct music_track *ta = (const struct music_track *)a;
  const struct music_track *tb = (const struct music_track *)b;
  int r = strcasecmp(ta->name, tb->name);
  if (r != 0) {
    return r;
  }
  return strcasecmp(ta->path, tb->path);
}

static void scan_music(struct player_state *state) {
  const char *root = getenv("PLUMOS_ROOT");
  const char *relative_roots[] = {
      "music",
      "MUSIC",
      "roms/music",
      "roms/MUSIC",
      "roms/Music",
  };
  const char *sd2_roots[] = {
      "/run/plumos/sd2/music",
      "/run/plumos/sd2/MUSIC",
      "/run/plumos/sd2/Music",
      "/run/plumos/sd2/roms/music",
      "/run/plumos/sd2/roms/MUSIC",
      "/run/plumos/sd2/roms/Music",
  };
  size_t i;
  char path[PATH_MAX];
  if (!root || !root[0]) {
    root = "/mnt/plumos";
  }
  state->track_count = 0;
  for (i = 0; i < sizeof(relative_roots) / sizeof(relative_roots[0]); i++) {
    int before = state->track_count;
    if (snprintf(path, sizeof(path), "%s/%s", root, relative_roots[i]) >=
        (int)sizeof(path)) {
      continue;
    }
    scan_dir_recursive(state, path, 0);
    fprintf(stderr, "scan root=%s tracks=%d\n", path,
            state->track_count - before);
  }
  for (i = 0; i < sizeof(sd2_roots) / sizeof(sd2_roots[0]); i++) {
    int before = state->track_count;
    scan_dir_recursive(state, sd2_roots[i], 0);
    fprintf(stderr, "scan root=%s tracks=%d\n", sd2_roots[i],
            state->track_count - before);
  }
  fprintf(stderr, "scan total tracks=%d\n", state->track_count);
  if (state->track_count > 1) {
    qsort(state->tracks, (size_t)state->track_count, sizeof(state->tracks[0]),
          track_compare);
  }
  state->selected = 0;
  state->current = -1;
  state->scroll = 0;
}

static void set_status_locked(struct player_state *state, const char *status) {
  snprintf(state->status, sizeof(state->status), "%s", status ? status : "");
}

static void set_audio_status_locked(struct player_state *state, const char *status) {
  snprintf(state->audio_status, sizeof(state->audio_status), "%s", status ? status : "");
}

static void set_input_status_locked(struct player_state *state, const char *status) {
  snprintf(state->input_status, sizeof(state->input_status), "%s", status ? status : "");
}

static unsigned int read_u24_be(const unsigned char *p) {
  return ((unsigned int)p[0] << 16) | ((unsigned int)p[1] << 8) | (unsigned int)p[2];
}

static unsigned int read_u32_be(const unsigned char *p) {
  return ((unsigned int)p[0] << 24) | ((unsigned int)p[1] << 16) |
         ((unsigned int)p[2] << 8) | (unsigned int)p[3];
}

static unsigned int read_syncsafe32(const unsigned char *p) {
  return ((unsigned int)(p[0] & 0x7f) << 21) | ((unsigned int)(p[1] & 0x7f) << 14) |
         ((unsigned int)(p[2] & 0x7f) << 7) | (unsigned int)(p[3] & 0x7f);
}

static void album_art_replace_locked(struct player_state *state, unsigned char *rgba,
                                     int width, int height, const char *status) {
  free(state->art.rgba);
  state->art.rgba = rgba;
  state->art.width = width;
  state->art.height = height;
  state->art.generation++;
  snprintf(state->art.status, sizeof(state->art.status), "%s",
           status && status[0] ? status : (rgba ? "cover art" : "no art"));
}

static int id3_load_tag(const char *path, unsigned char **tag_out, size_t *tag_size_out,
                        int *version_out, int *flags_out) {
  FILE *f;
  unsigned char header[10];
  unsigned int tag_size;
  unsigned char *tag;

  *tag_out = NULL;
  *tag_size_out = 0;
  *version_out = 0;
  *flags_out = 0;
  f = fopen(path, "rb");
  if (!f) {
    return 0;
  }
  if (fread(header, 1, sizeof(header), f) != sizeof(header)) {
    fclose(f);
    return 0;
  }
  if (memcmp(header, "ID3", 3) != 0 || header[3] < 2 || header[3] > 4) {
    fclose(f);
    return 0;
  }
  tag_size = read_syncsafe32(header + 6);
  if (tag_size == 0 || tag_size > MUSIC_ART_MAX_BYTES) {
    fclose(f);
    return 0;
  }
  tag = (unsigned char *)malloc(tag_size);
  if (!tag) {
    fclose(f);
    return 0;
  }
  if (fread(tag, 1, tag_size, f) != tag_size) {
    free(tag);
    fclose(f);
    return 0;
  }
  fclose(f);
  *tag_out = tag;
  *tag_size_out = tag_size;
  *version_out = header[3];
  *flags_out = header[5];
  return 1;
}

static unsigned char *id3_unsync_copy(const unsigned char *data, size_t size,
                                      size_t *out_size) {
  unsigned char *out;
  size_t i;
  size_t pos = 0;
  if (!data || !out_size) {
    return NULL;
  }
  out = (unsigned char *)malloc(size ? size : 1);
  if (!out) {
    return NULL;
  }
  for (i = 0; i < size; i++) {
    out[pos++] = data[i];
    if (data[i] == 0xff && i + 1 < size && data[i + 1] == 0x00) {
      i++;
    }
  }
  *out_size = pos;
  return out;
}

static size_t id3_skip_apic_description(const unsigned char *data, size_t size,
                                        size_t pos, unsigned char encoding) {
  if (encoding == 1 || encoding == 2) {
    while (pos + 1 < size) {
      if (data[pos] == 0x00 && data[pos + 1] == 0x00) {
        return pos + 2;
      }
      pos += 2;
    }
    return size;
  }
  while (pos < size) {
    if (data[pos] == 0x00) {
      return pos + 1;
    }
    pos++;
  }
  return size;
}

static int id3_apic_payload(const unsigned char *frame, size_t frame_size,
                            const unsigned char **image_out, size_t *image_size_out,
                            char *mime_out, size_t mime_out_size) {
  unsigned char encoding;
  size_t pos = 1;
  size_t mime_start;
  size_t mime_len;

  if (!frame || frame_size < 5 || !image_out || !image_size_out) {
    return 0;
  }
  *image_out = NULL;
  *image_size_out = 0;
  if (mime_out && mime_out_size > 0) {
    mime_out[0] = '\0';
  }
  encoding = frame[0];
  mime_start = pos;
  while (pos < frame_size && frame[pos] != 0x00) {
    pos++;
  }
  if (pos >= frame_size) {
    return 0;
  }
  mime_len = pos - mime_start;
  if (mime_out && mime_out_size > 0) {
    size_t copy_len = mime_len;
    if (copy_len >= mime_out_size) {
      copy_len = mime_out_size - 1;
    }
    memcpy(mime_out, frame + mime_start, copy_len);
    mime_out[copy_len] = '\0';
  }
  pos++;
  if (pos >= frame_size) {
    return 0;
  }
  pos++; /* picture type */
  pos = id3_skip_apic_description(frame, frame_size, pos, encoding);
  if (pos >= frame_size || frame_size - pos < 16) {
    return 0;
  }
  *image_out = frame + pos;
  *image_size_out = frame_size - pos;
  return 1;
}

static int id3_pic_payload_v22(const unsigned char *frame, size_t frame_size,
                               const unsigned char **image_out,
                               size_t *image_size_out, char *mime_out,
                               size_t mime_out_size) {
  unsigned char encoding;
  size_t pos = 5;
  if (!frame || frame_size < 8 || !image_out || !image_size_out) {
    return 0;
  }
  *image_out = NULL;
  *image_size_out = 0;
  encoding = frame[0];
  if (mime_out && mime_out_size > 0) {
    snprintf(mime_out, mime_out_size, "%.3s", (const char *)(frame + 1));
  }
  pos = id3_skip_apic_description(frame, frame_size, pos, encoding);
  if (pos >= frame_size || frame_size - pos < 16) {
    return 0;
  }
  *image_out = frame + pos;
  *image_size_out = frame_size - pos;
  return 1;
}

static int id3_extract_apic_image(const char *path, unsigned char **image_out,
                                  size_t *image_size_out, char *mime_out,
                                  size_t mime_out_size) {
  unsigned char *tag = NULL;
  unsigned char *work = NULL;
  unsigned char *copy = NULL;
  size_t tag_size = 0;
  size_t work_size = 0;
  size_t pos = 0;
  int version = 0;
  int flags = 0;
  int ok = 0;

  *image_out = NULL;
  *image_size_out = 0;
  if (mime_out && mime_out_size > 0) {
    mime_out[0] = '\0';
  }
  if (!id3_load_tag(path, &tag, &tag_size, &version, &flags)) {
    return 0;
  }
  work = tag;
  work_size = tag_size;
  if ((flags & 0x80) != 0) {
    work = id3_unsync_copy(tag, tag_size, &work_size);
    if (!work) {
      goto done;
    }
  }

  if ((flags & 0x40) != 0 && work_size >= 4) {
    if (version == 3) {
      unsigned int ext_size = read_u32_be(work);
      if ((size_t)ext_size + 4u < work_size) {
        pos = (size_t)ext_size + 4u;
      }
    } else if (version == 4) {
      unsigned int ext_size = read_syncsafe32(work);
      if (ext_size < work_size) {
        pos = ext_size;
      }
    }
  }

  while (pos + (version == 2 ? 6u : 10u) <= work_size) {
    char id[5] = {0, 0, 0, 0, 0};
    unsigned int frame_size;
    const unsigned char *payload;
    const unsigned char *image = NULL;
    size_t image_size = 0;
    int is_art = 0;

    if (version == 2) {
      if (work[pos] == 0 || work[pos + 1] == 0 || work[pos + 2] == 0) {
        break;
      }
      memcpy(id, work + pos, 3);
      frame_size = read_u24_be(work + pos + 3);
      pos += 6;
      payload = work + pos;
      is_art = strcmp(id, "PIC") == 0;
    } else {
      if (work[pos] == 0 || work[pos + 1] == 0 || work[pos + 2] == 0 ||
          work[pos + 3] == 0) {
        break;
      }
      memcpy(id, work + pos, 4);
      frame_size = version == 4 ? read_syncsafe32(work + pos + 4) :
                                  read_u32_be(work + pos + 4);
      pos += 10;
      payload = work + pos;
      is_art = strcmp(id, "APIC") == 0;
    }
    if (frame_size == 0 || (size_t)frame_size > work_size - pos) {
      break;
    }
    if (is_art) {
      if ((version == 2 && id3_pic_payload_v22(payload, frame_size, &image,
                                               &image_size, mime_out,
                                               mime_out_size)) ||
          (version != 2 && id3_apic_payload(payload, frame_size, &image,
                                            &image_size, mime_out,
                                            mime_out_size))) {
        if (image_size > 0 && image_size <= MUSIC_ART_MAX_BYTES) {
          copy = (unsigned char *)malloc(image_size);
          if (copy) {
            memcpy(copy, image, image_size);
            *image_out = copy;
            *image_size_out = image_size;
            copy = NULL;
            ok = 1;
            goto done;
          }
        }
      }
    }
    pos += frame_size;
  }

done:
  free(copy);
  if (work != tag) {
    free(work);
  }
  free(tag);
  return ok;
}

struct jpeg_error_state {
  struct jpeg_error_mgr pub;
  jmp_buf jump;
};

static void jpeg_error_exit_to_jump(j_common_ptr cinfo) {
  struct jpeg_error_state *state = (struct jpeg_error_state *)cinfo->err;
  longjmp(state->jump, 1);
}

static int decode_jpeg_rgba(const unsigned char *data, size_t size,
                            unsigned char **rgba_out, int *width_out,
                            int *height_out) {
  struct jpeg_decompress_struct cinfo;
  struct jpeg_error_state jerr;
  unsigned char *rgba = NULL;
  JSAMPARRAY row = NULL;
  int width;
  int height;
  int ok = 0;

  *rgba_out = NULL;
  *width_out = 0;
  *height_out = 0;
  memset(&cinfo, 0, sizeof(cinfo));
  cinfo.err = jpeg_std_error(&jerr.pub);
  jerr.pub.error_exit = jpeg_error_exit_to_jump;
  if (setjmp(jerr.jump)) {
    goto done;
  }
  jpeg_create_decompress(&cinfo);
  jpeg_mem_src(&cinfo, data, (unsigned long)size);
  jpeg_read_header(&cinfo, TRUE);
  cinfo.out_color_space = JCS_RGB;
  jpeg_start_decompress(&cinfo);
  width = (int)cinfo.output_width;
  height = (int)cinfo.output_height;
  if (width <= 0 || height <= 0 || width > MUSIC_ART_MAX_DIMENSION ||
      height > MUSIC_ART_MAX_DIMENSION || cinfo.output_components != 3) {
    goto done;
  }
  rgba = (unsigned char *)malloc((size_t)width * (size_t)height * 4u);
  row = (*cinfo.mem->alloc_sarray)((j_common_ptr)&cinfo, JPOOL_IMAGE,
                                   (JDIMENSION)width * 3u, 1);
  if (!rgba || !row) {
    goto done;
  }
  while (cinfo.output_scanline < cinfo.output_height) {
    JDIMENSION y = cinfo.output_scanline;
    int x;
    jpeg_read_scanlines(&cinfo, row, 1);
    for (x = 0; x < width; x++) {
      size_t src = (size_t)x * 3u;
      size_t dst = ((size_t)y * (size_t)width + (size_t)x) * 4u;
      rgba[dst] = row[0][src];
      rgba[dst + 1u] = row[0][src + 1u];
      rgba[dst + 2u] = row[0][src + 2u];
      rgba[dst + 3u] = 0xff;
    }
  }
  jpeg_finish_decompress(&cinfo);
  *rgba_out = rgba;
  *width_out = width;
  *height_out = height;
  rgba = NULL;
  ok = 1;

done:
  jpeg_destroy_decompress(&cinfo);
  free(rgba);
  return ok;
}

struct png_memory_reader {
  const unsigned char *data;
  size_t size;
  size_t offset;
};

static void png_memory_read(png_structp png, png_bytep out, png_size_t bytes) {
  struct png_memory_reader *reader =
      (struct png_memory_reader *)png_get_io_ptr(png);
  if (!reader || bytes > reader->size - reader->offset) {
    png_error(png, "read past end");
    return;
  }
  memcpy(out, reader->data + reader->offset, bytes);
  reader->offset += bytes;
}

static int decode_png_rgba_memory(const unsigned char *data, size_t size,
                                  unsigned char **rgba_out, int *width_out,
                                  int *height_out) {
  struct png_memory_reader reader;
  png_structp png = NULL;
  png_infop info = NULL;
  png_bytep *rows = NULL;
  png_bytep pixels = NULL;
  png_uint_32 width;
  png_uint_32 height;
  int bit_depth;
  int color_type;
  size_t row_bytes;
  png_uint_32 y;
  int ok = 0;

  *rgba_out = NULL;
  *width_out = 0;
  *height_out = 0;
  if (!data || size < 8 || png_sig_cmp((png_bytep)data, 0, 8) != 0) {
    return 0;
  }
  png = png_create_read_struct(PNG_LIBPNG_VER_STRING, NULL, NULL, NULL);
  if (!png) {
    return 0;
  }
  info = png_create_info_struct(png);
  if (!info) {
    png_destroy_read_struct(&png, NULL, NULL);
    return 0;
  }
  if (setjmp(png_jmpbuf(png))) {
    goto done;
  }
  reader.data = data;
  reader.size = size;
  reader.offset = 0;
  png_set_read_fn(png, &reader, png_memory_read);
  png_read_info(png, info);
  png_get_IHDR(png, info, &width, &height, &bit_depth, &color_type, NULL, NULL,
               NULL);
  if (width == 0 || height == 0 || width > MUSIC_ART_MAX_DIMENSION ||
      height > MUSIC_ART_MAX_DIMENSION) {
    goto done;
  }
  if (bit_depth == 16) {
    png_set_strip_16(png);
  }
  if (color_type == PNG_COLOR_TYPE_PALETTE) {
    png_set_palette_to_rgb(png);
  }
  if (color_type == PNG_COLOR_TYPE_GRAY && bit_depth < 8) {
    png_set_expand_gray_1_2_4_to_8(png);
  }
  if (png_get_valid(png, info, PNG_INFO_tRNS)) {
    png_set_tRNS_to_alpha(png);
  }
  if (color_type == PNG_COLOR_TYPE_GRAY || color_type == PNG_COLOR_TYPE_GRAY_ALPHA) {
    png_set_gray_to_rgb(png);
  }
  if ((color_type & PNG_COLOR_MASK_ALPHA) == 0) {
    png_set_filler(png, 0xff, PNG_FILLER_AFTER);
  }
  (void)png_set_interlace_handling(png);
  png_read_update_info(png, info);
  row_bytes = png_get_rowbytes(png, info);
  if (row_bytes != (size_t)width * 4u) {
    goto done;
  }
  pixels = (png_bytep)malloc(row_bytes * (size_t)height);
  rows = (png_bytep *)malloc(sizeof(png_bytep) * (size_t)height);
  if (!pixels || !rows) {
    goto done;
  }
  for (y = 0; y < height; y++) {
    rows[y] = pixels + row_bytes * (size_t)y;
  }
  png_read_image(png, rows);
  png_read_end(png, NULL);
  *rgba_out = pixels;
  *width_out = (int)width;
  *height_out = (int)height;
  pixels = NULL;
  ok = 1;

done:
  free(rows);
  free(pixels);
  png_destroy_read_struct(&png, &info, NULL);
  return ok;
}

static int decode_album_art_rgba(const unsigned char *data, size_t size,
                                 unsigned char **rgba_out, int *width_out,
                                 int *height_out) {
  if (size >= 8 && png_sig_cmp((png_bytep)data, 0, 8) == 0) {
    return decode_png_rgba_memory(data, size, rgba_out, width_out, height_out);
  }
  if (size >= 3 && data[0] == 0xff && data[1] == 0xd8 && data[2] == 0xff) {
    return decode_jpeg_rgba(data, size, rgba_out, width_out, height_out);
  }
  return decode_jpeg_rgba(data, size, rgba_out, width_out, height_out) ||
         decode_png_rgba_memory(data, size, rgba_out, width_out, height_out);
}

#ifdef PLUMOS_MUSIC_ENABLE_FFMPEG
static int ffmpeg_extract_attached_art(const char *path, unsigned char **image_out,
                                       size_t *image_size_out) {
  AVFormatContext *format = NULL;
  int ret;
  unsigned int i;
  int ok = 0;

  *image_out = NULL;
  *image_size_out = 0;
  av_log_set_level(AV_LOG_QUIET);
  ret = avformat_open_input(&format, path, NULL, NULL);
  if (ret < 0) {
    return 0;
  }
  ret = avformat_find_stream_info(format, NULL);
  if (ret < 0) {
    goto done;
  }
  for (i = 0; i < format->nb_streams; i++) {
    AVStream *stream = format->streams[i];
    AVPacket *pic = &stream->attached_pic;
    unsigned char *copy;
    if ((stream->disposition & AV_DISPOSITION_ATTACHED_PIC) == 0 ||
        pic->size <= 0 || !pic->data || (size_t)pic->size > MUSIC_ART_MAX_BYTES) {
      continue;
    }
    copy = (unsigned char *)malloc((size_t)pic->size);
    if (!copy) {
      break;
    }
    memcpy(copy, pic->data, (size_t)pic->size);
    *image_out = copy;
    *image_size_out = (size_t)pic->size;
    ok = 1;
    break;
  }

done:
  avformat_close_input(&format);
  return ok;
}
#endif

static void load_album_art_locked(struct player_state *state, const char *path) {
  unsigned char *image = NULL;
  size_t image_size = 0;
  unsigned char *rgba = NULL;
  int width = 0;
  int height = 0;
  char mime[48];
  int found = 0;

  album_art_replace_locked(state, NULL, 0, 0, "no art");
  if (!path || !str_ends_with_audio_ext(path)) {
    return;
  }
  found = id3_extract_apic_image(path, &image, &image_size, mime, sizeof(mime));
#ifdef PLUMOS_MUSIC_ENABLE_FFMPEG
  if (!found) {
    found = ffmpeg_extract_attached_art(path, &image, &image_size);
  }
#endif
  if (!found) {
    return;
  }
  if (decode_album_art_rgba(image, image_size, &rgba, &width, &height)) {
    album_art_replace_locked(state, rgba, width, height, "cover art");
    rgba = NULL;
  } else {
    album_art_replace_locked(state, NULL, 0, 0, "art decode failed");
  }
  free(rgba);
  free(image);
}

#ifdef PLUMOS_MUSIC_ENABLE_FFMPEG
static void ffmpeg_error_message(int code, char *out, size_t out_size) {
  if (!out || out_size == 0) {
    return;
  }
  if (av_strerror(code, out, out_size) < 0) {
    snprintf(out, out_size, "ffmpeg error %d", code);
  }
}

static ma_uint64 ffmpeg_length_in_output_frames(AVFormatContext *format,
                                                int stream_index) {
  AVStream *stream;
  int64_t frames = 0;
  if (!format || stream_index < 0 || stream_index >= (int)format->nb_streams) {
    return 0;
  }
  stream = format->streams[stream_index];
  if (stream->duration > 0 && stream->duration != AV_NOPTS_VALUE) {
    frames = av_rescale_q(stream->duration, stream->time_base,
                          (AVRational){1, MUSIC_OUTPUT_RATE});
  } else if (format->duration > 0 && format->duration != AV_NOPTS_VALUE) {
    frames = av_rescale_q(format->duration, AV_TIME_BASE_Q,
                          (AVRational){1, MUSIC_OUTPUT_RATE});
  }
  return frames > 0 ? (ma_uint64)frames : 0;
}

static void ffmpeg_decoder_clear_pending(struct ffmpeg_audio_decoder *decoder) {
  if (!decoder) {
    return;
  }
  free(decoder->pending);
  decoder->pending = NULL;
  decoder->pending_frames = 0;
  decoder->pending_pos = 0;
}

static void ffmpeg_decoder_close(struct ffmpeg_audio_decoder *decoder) {
  if (!decoder) {
    return;
  }
  ffmpeg_decoder_clear_pending(decoder);
  if (decoder->frame) {
    av_frame_free(&decoder->frame);
  }
  if (decoder->packet) {
    av_packet_free(&decoder->packet);
  }
  if (decoder->swr) {
    swr_free(&decoder->swr);
  }
  if (decoder->codec) {
    avcodec_free_context(&decoder->codec);
  }
  if (decoder->format) {
    avformat_close_input(&decoder->format);
  }
  memset(decoder, 0, sizeof(*decoder));
  decoder->stream_index = -1;
}

static int ffmpeg_decoder_open(const char *path, struct ffmpeg_audio_decoder *decoder,
                               ma_uint64 *length_out, char *err, size_t err_size) {
  const AVCodec *codec = NULL;
  AVStream *stream = NULL;
  AVChannelLayout out_layout;
  AVChannelLayout in_layout;
  int ret;

  if (length_out) {
    *length_out = 0;
  }
  if (!path || !decoder) {
    return 0;
  }
  memset(decoder, 0, sizeof(*decoder));
  decoder->stream_index = -1;
  av_log_set_level(AV_LOG_QUIET);

  ret = avformat_open_input(&decoder->format, path, NULL, NULL);
  if (ret < 0) {
    if (err) {
      ffmpeg_error_message(ret, err, err_size);
    }
    goto fail;
  }
  ret = avformat_find_stream_info(decoder->format, NULL);
  if (ret < 0) {
    if (err) {
      ffmpeg_error_message(ret, err, err_size);
    }
    goto fail;
  }
  ret = av_find_best_stream(decoder->format, AVMEDIA_TYPE_AUDIO, -1, -1, &codec, 0);
  if (ret < 0 || !codec) {
    if (err) {
      snprintf(err, err_size, "no audio stream");
    }
    goto fail;
  }
  decoder->stream_index = ret;
  stream = decoder->format->streams[decoder->stream_index];
  decoder->codec = avcodec_alloc_context3(codec);
  if (!decoder->codec) {
    if (err) {
      snprintf(err, err_size, "codec allocation failed");
    }
    goto fail;
  }
  ret = avcodec_parameters_to_context(decoder->codec, stream->codecpar);
  if (ret < 0) {
    if (err) {
      ffmpeg_error_message(ret, err, err_size);
    }
    goto fail;
  }
  ret = avcodec_open2(decoder->codec, codec, NULL);
  if (ret < 0) {
    if (err) {
      ffmpeg_error_message(ret, err, err_size);
    }
    goto fail;
  }
  if (decoder->codec->sample_rate <= 0) {
    if (err) {
      snprintf(err, err_size, "invalid sample rate");
    }
    goto fail;
  }

  memset(&out_layout, 0, sizeof(out_layout));
  memset(&in_layout, 0, sizeof(in_layout));
  av_channel_layout_default(&out_layout, MUSIC_OUTPUT_CHANNELS);
  if (decoder->codec->ch_layout.nb_channels > 0) {
    if (av_channel_layout_copy(&in_layout, &decoder->codec->ch_layout) < 0) {
      av_channel_layout_default(&in_layout, decoder->codec->ch_layout.nb_channels);
    }
  } else {
    av_channel_layout_default(&in_layout, MUSIC_OUTPUT_CHANNELS);
  }
  ret = swr_alloc_set_opts2(&decoder->swr, &out_layout, AV_SAMPLE_FMT_FLT,
                            MUSIC_OUTPUT_RATE, &in_layout, decoder->codec->sample_fmt,
                            decoder->codec->sample_rate, 0, NULL);
  av_channel_layout_uninit(&out_layout);
  av_channel_layout_uninit(&in_layout);
  if (ret < 0 || !decoder->swr) {
    if (err) {
      ffmpeg_error_message(ret, err, err_size);
    }
    goto fail;
  }
  ret = swr_init(decoder->swr);
  if (ret < 0) {
    if (err) {
      ffmpeg_error_message(ret, err, err_size);
    }
    goto fail;
  }

  decoder->packet = av_packet_alloc();
  decoder->frame = av_frame_alloc();
  if (!decoder->packet || !decoder->frame) {
    if (err) {
      snprintf(err, err_size, "packet/frame allocation failed");
    }
    goto fail;
  }
  decoder->length_frames =
      ffmpeg_length_in_output_frames(decoder->format, decoder->stream_index);
  if (length_out) {
    *length_out = decoder->length_frames;
  }
  return 1;

fail:
  ffmpeg_decoder_close(decoder);
  return 0;
}

static int ffmpeg_decoder_store_frame(struct ffmpeg_audio_decoder *decoder) {
  int64_t delay;
  int out_count;
  int got;
  float *buffer;
  uint8_t *out_planes[1];
  const uint8_t **in_planes;

  if (!decoder || !decoder->frame || decoder->frame->nb_samples <= 0) {
    return 0;
  }
  delay = swr_get_delay(decoder->swr, decoder->codec->sample_rate);
  out_count = (int)av_rescale_rnd(delay + decoder->frame->nb_samples,
                                  MUSIC_OUTPUT_RATE,
                                  decoder->codec->sample_rate, AV_ROUND_UP);
  if (out_count <= 0 || out_count > MUSIC_OUTPUT_RATE * 30) {
    return -1;
  }
  buffer = (float *)malloc((size_t)out_count * MUSIC_OUTPUT_CHANNELS * sizeof(float));
  if (!buffer) {
    return -1;
  }
  out_planes[0] = (uint8_t *)buffer;
  in_planes = (const uint8_t **)decoder->frame->extended_data;
  got = swr_convert(decoder->swr, out_planes, out_count, in_planes,
                    decoder->frame->nb_samples);
  if (got <= 0) {
    free(buffer);
    return got == 0 ? 0 : -1;
  }
  ffmpeg_decoder_clear_pending(decoder);
  decoder->pending = buffer;
  decoder->pending_frames = (ma_uint64)got;
  decoder->pending_pos = 0;
  return 1;
}

static int ffmpeg_decoder_decode_more(struct ffmpeg_audio_decoder *decoder) {
  int ret;
  if (!decoder || !decoder->codec || !decoder->format || !decoder->swr) {
    return -1;
  }
  while (1) {
    ret = avcodec_receive_frame(decoder->codec, decoder->frame);
    if (ret == 0) {
      int stored = ffmpeg_decoder_store_frame(decoder);
      av_frame_unref(decoder->frame);
      if (stored > 0) {
        return 1;
      }
      if (stored < 0) {
        return -1;
      }
      continue;
    }
    if (ret == AVERROR_EOF) {
      return 0;
    }
    if (ret != AVERROR(EAGAIN)) {
      return -1;
    }
    if (decoder->eof_sent) {
      return 0;
    }
    while ((ret = av_read_frame(decoder->format, decoder->packet)) >= 0) {
      if (decoder->packet->stream_index == decoder->stream_index) {
        ret = avcodec_send_packet(decoder->codec, decoder->packet);
        av_packet_unref(decoder->packet);
        if (ret < 0 && ret != AVERROR(EAGAIN)) {
          return -1;
        }
        break;
      }
      av_packet_unref(decoder->packet);
    }
    if (ret < 0) {
      avcodec_send_packet(decoder->codec, NULL);
      decoder->eof_sent = 1;
    }
  }
}

static int ffmpeg_decoder_read_pcm_frames(struct ffmpeg_audio_decoder *decoder,
                                          float *out, ma_uint64 frame_count,
                                          ma_uint64 *frames_read) {
  ma_uint64 written = 0;
  if (frames_read) {
    *frames_read = 0;
  }
  if (!decoder || !out || frame_count == 0) {
    return 0;
  }
  while (written < frame_count) {
    ma_uint64 available = decoder->pending_frames > decoder->pending_pos ?
                              decoder->pending_frames - decoder->pending_pos :
                              0;
    if (available > 0) {
      ma_uint64 to_copy = frame_count - written;
      if (to_copy > available) {
        to_copy = available;
      }
      memcpy(out + (size_t)written * MUSIC_OUTPUT_CHANNELS,
             decoder->pending + (size_t)decoder->pending_pos * MUSIC_OUTPUT_CHANNELS,
             (size_t)to_copy * MUSIC_OUTPUT_CHANNELS * sizeof(float));
      decoder->pending_pos += to_copy;
      written += to_copy;
      if (decoder->pending_pos >= decoder->pending_frames) {
        ffmpeg_decoder_clear_pending(decoder);
      }
      continue;
    }
    if (ffmpeg_decoder_decode_more(decoder) <= 0) {
      break;
    }
  }
  if (frames_read) {
    *frames_read = written;
  }
  return 1;
}

static int ffmpeg_decoder_seek_to_pcm_frame(struct ffmpeg_audio_decoder *decoder,
                                            ma_uint64 target_frame) {
  AVStream *stream;
  int64_t timestamp;
  int ret;
  if (!decoder || !decoder->format || !decoder->codec ||
      decoder->stream_index < 0 ||
      decoder->stream_index >= (int)decoder->format->nb_streams) {
    return 0;
  }
  stream = decoder->format->streams[decoder->stream_index];
  timestamp = av_rescale_q((int64_t)target_frame,
                           (AVRational){1, MUSIC_OUTPUT_RATE}, stream->time_base);
  ret = av_seek_frame(decoder->format, decoder->stream_index, timestamp,
                      AVSEEK_FLAG_BACKWARD);
  if (ret < 0) {
    ret = avformat_seek_file(decoder->format, decoder->stream_index, INT64_MIN,
                             timestamp, INT64_MAX, 0);
  }
  if (ret < 0) {
    return 0;
  }
  avcodec_flush_buffers(decoder->codec);
  if (decoder->swr) {
    swr_close(decoder->swr);
    swr_init(decoder->swr);
  }
  decoder->eof_sent = 0;
  ffmpeg_decoder_clear_pending(decoder);
  return 1;
}
#endif

static int open_miniaudio_decoder_locked(struct player_state *state, const char *path,
                                         ma_uint64 *length_out) {
  ma_decoder_config config;
  ma_result result;
  ma_uint64 length = 0;
  if (length_out) {
    *length_out = 0;
  }
  config = ma_decoder_config_init(ma_format_f32, MUSIC_OUTPUT_CHANNELS,
                                  MUSIC_OUTPUT_RATE);
  result = ma_decoder_init_file(path, &config, &state->decoder);
  if (result != MA_SUCCESS) {
    return 0;
  }
  if (ma_decoder_get_length_in_pcm_frames(&state->decoder, &length) != MA_SUCCESS) {
    length = 0;
  }
  state->decoder_kind = MUSIC_DECODER_MINIAUDIO;
  state->decoder_ready = 1;
  if (length_out) {
    *length_out = length;
  }
  return 1;
}

static int music_decoder_read_pcm_frames_locked(struct player_state *state, float *out,
                                                ma_uint64 frame_count,
                                                ma_uint64 *frames_read) {
  if (!state || !state->decoder_ready) {
    if (frames_read) {
      *frames_read = 0;
    }
    return 0;
  }
  if (state->decoder_kind == MUSIC_DECODER_MINIAUDIO) {
    return ma_decoder_read_pcm_frames(&state->decoder, out, frame_count,
                                      frames_read) == MA_SUCCESS;
  }
#ifdef PLUMOS_MUSIC_ENABLE_FFMPEG
  if (state->decoder_kind == MUSIC_DECODER_FFMPEG) {
    return ffmpeg_decoder_read_pcm_frames(&state->ffmpeg_decoder, out, frame_count,
                                          frames_read);
  }
#endif
  if (frames_read) {
    *frames_read = 0;
  }
  return 0;
}

static int music_decoder_seek_to_pcm_frame_locked(struct player_state *state,
                                                  ma_uint64 frame) {
  if (!state || !state->decoder_ready) {
    return 0;
  }
  if (state->decoder_kind == MUSIC_DECODER_MINIAUDIO) {
    return ma_decoder_seek_to_pcm_frame(&state->decoder, frame) == MA_SUCCESS;
  }
#ifdef PLUMOS_MUSIC_ENABLE_FFMPEG
  if (state->decoder_kind == MUSIC_DECODER_FFMPEG) {
    return ffmpeg_decoder_seek_to_pcm_frame(&state->ffmpeg_decoder, frame);
  }
#endif
  return 0;
}

static void unload_decoder_locked(struct player_state *state) {
  if (state->decoder_ready && state->decoder_kind == MUSIC_DECODER_MINIAUDIO) {
    ma_decoder_uninit(&state->decoder);
  }
#ifdef PLUMOS_MUSIC_ENABLE_FFMPEG
  if (state->decoder_ready && state->decoder_kind == MUSIC_DECODER_FFMPEG) {
    ffmpeg_decoder_close(&state->ffmpeg_decoder);
  }
#endif
  state->decoder_kind = MUSIC_DECODER_NONE;
  state->decoder_ready = 0;
  state->playing = 0;
  state->paused = 0;
  state->position_frames = 0;
  state->length_frames = 0;
  state->seek_delta_seconds = 0;
  album_art_replace_locked(state, NULL, 0, 0, "no art");
}

static int load_track_locked(struct player_state *state, int index, const char *reason) {
  ma_uint64 length = 0;
  int loaded = 0;
#ifdef PLUMOS_MUSIC_ENABLE_FFMPEG
  char ffmpeg_error[96] = "";
#endif
  if (!state || index < 0 || index >= state->track_count) {
    return 0;
  }
  unload_decoder_locked(state);

  if (is_miniaudio_preferred_audio_ext(state->tracks[index].path)) {
    loaded = open_miniaudio_decoder_locked(state, state->tracks[index].path, &length);
  }
#ifdef PLUMOS_MUSIC_ENABLE_FFMPEG
  if (!loaded) {
    loaded = ffmpeg_decoder_open(state->tracks[index].path, &state->ffmpeg_decoder,
                                 &length, ffmpeg_error, sizeof(ffmpeg_error));
    if (loaded) {
      state->decoder_kind = MUSIC_DECODER_FFMPEG;
      state->decoder_ready = 1;
    }
  }
#endif
  if (!loaded && !is_miniaudio_preferred_audio_ext(state->tracks[index].path)) {
    loaded = open_miniaudio_decoder_locked(state, state->tracks[index].path, &length);
  }
  if (!loaded) {
    char msg[192];
#ifdef PLUMOS_MUSIC_ENABLE_FFMPEG
    if (ffmpeg_error[0]) {
      snprintf(msg, sizeof(msg), "Cannot play: %s (%s)", state->tracks[index].name,
               ffmpeg_error);
    } else
#endif
    {
      snprintf(msg, sizeof(msg), "Cannot play: %s", state->tracks[index].name);
    }
    set_status_locked(state, msg);
    return 0;
  }
  state->current = index;
  state->selected = index;
  state->playing = 1;
  state->paused = 0;
  state->position_frames = 0;
  state->length_frames = length;
  state->seek_delta_seconds = 0;
  load_album_art_locked(state, state->tracks[index].path);
  if (reason && reason[0]) {
    char msg[192];
    snprintf(msg, sizeof(msg), "%s: %s", reason, state->tracks[index].name);
    set_status_locked(state, msg);
  } else {
    set_status_locked(state, state->tracks[index].name);
  }
  fprintf(stderr, "track loaded index=%d decoder=%s length_frames=%llu\n", index,
          state->decoder_kind == MUSIC_DECODER_MINIAUDIO ? "miniaudio" :
#ifdef PLUMOS_MUSIC_ENABLE_FFMPEG
          state->decoder_kind == MUSIC_DECODER_FFMPEG ? "ffmpeg" :
#endif
          "unknown",
          (unsigned long long)state->length_frames);
  return 1;
}

static void toggle_play_selected(struct player_state *state) {
  pthread_mutex_lock(&state->lock);
  if (state->decoder_ready && state->selected == state->current) {
    state->paused = !state->paused;
    set_status_locked(state, state->paused ? "Paused" : "Playing");
  } else if (state->track_count > 0) {
    load_track_locked(state, state->selected, "Playing");
  }
  pthread_mutex_unlock(&state->lock);
}

static void play_relative(struct player_state *state, int delta) {
  pthread_mutex_lock(&state->lock);
  if (state->track_count > 0) {
    int base = state->current >= 0 ? state->current : state->selected;
    int next = base + delta;
    if (next < 0) {
      next = state->track_count - 1;
    } else if (next >= state->track_count) {
      next = 0;
    }
    load_track_locked(state, next, "Playing");
  }
  pthread_mutex_unlock(&state->lock);
}

static void request_seek(struct player_state *state, int seconds) {
  pthread_mutex_lock(&state->lock);
  if (state->decoder_ready) {
    state->seek_delta_seconds += seconds;
    set_status_locked(state, seconds >= 0 ? "+5 seconds" : "-5 seconds");
  }
  pthread_mutex_unlock(&state->lock);
}

static void adjust_volume(struct player_state *state, float delta) {
  pthread_mutex_lock(&state->lock);
  state->volume += delta;
  if (state->volume < 0.0f) {
    state->volume = 0.0f;
  } else if (state->volume > 1.0f) {
    state->volume = 1.0f;
  }
  set_status_locked(state, "Volume changed");
  fprintf(stderr, "app volume=%d\n", (int)lrintf(state->volume * 100.0f));
  pthread_mutex_unlock(&state->lock);
}

static void cycle_eq(struct player_state *state) {
  pthread_mutex_lock(&state->lock);
  state->eq_index =
      (state->eq_index + 1) % (int)(sizeof(k_eq_presets) / sizeof(k_eq_presets[0]));
  set_status_locked(state, k_eq_presets[state->eq_index].name);
  pthread_mutex_unlock(&state->lock);
}

static int write_full(int fd, const void *data, size_t size) {
  const unsigned char *p = (const unsigned char *)data;
  size_t pos = 0;
  while (pos < size) {
    ssize_t n = write(fd, p + pos, size - pos);
    if (n < 0) {
      if (errno == EINTR) {
        continue;
      }
      return 0;
    }
    if (n == 0) {
      return 0;
    }
    pos += (size_t)n;
  }
  return 1;
}

static float clampf(float value, float lo, float hi) {
  if (value < lo) {
    return lo;
  }
  if (value > hi) {
    return hi;
  }
  return value;
}

static void reset_filter(struct audio_filter *filter) {
  memset(filter, 0, sizeof(*filter));
}

static void apply_eq_and_convert(const float *in, int16_t *out, ma_uint64 frames,
                                 const struct eq_preset *eq, float volume,
                                 struct audio_filter *filter) {
  const float low_alpha = 0.0277f;  /* roughly 200 Hz at 44.1 kHz */
  const float high_alpha = 0.3628f; /* roughly 4 kHz at 44.1 kHz */
  ma_uint64 i;
  int ch;
  if (!filter->initialized) {
    for (ch = 0; ch < MUSIC_OUTPUT_CHANNELS; ch++) {
      filter->low_state[ch] = 0.0f;
      filter->high_lp_state[ch] = 0.0f;
    }
    filter->initialized = 1;
  }
  for (i = 0; i < frames; i++) {
    for (ch = 0; ch < MUSIC_OUTPUT_CHANNELS; ch++) {
      size_t idx = (size_t)i * MUSIC_OUTPUT_CHANNELS + (size_t)ch;
      float x = in[idx];
      float low;
      float high_lp;
      float high;
      float mid;
      float y;
      filter->low_state[ch] += low_alpha * (x - filter->low_state[ch]);
      filter->high_lp_state[ch] += high_alpha * (x - filter->high_lp_state[ch]);
      low = filter->low_state[ch];
      high_lp = filter->high_lp_state[ch];
      high = x - high_lp;
      mid = x - low - high;
      y = (low * eq->low + mid * eq->mid + high * eq->high) * volume;
      y = clampf(y, -1.0f, 1.0f);
      out[idx] = (int16_t)lrintf(y * 32767.0f);
    }
  }
}

static void handle_seek_locked(struct player_state *state, struct audio_filter *filter) {
  ma_int64 target;
  ma_int64 delta;
  if (state->seek_delta_seconds == 0 || !state->decoder_ready) {
    return;
  }
  delta = (ma_int64)state->seek_delta_seconds * MUSIC_OUTPUT_RATE;
  target = (ma_int64)state->position_frames + delta;
  if (target < 0) {
    target = 0;
  }
  if (state->length_frames > 0 && (ma_uint64)target > state->length_frames) {
    target = (ma_int64)state->length_frames;
  }
  if (music_decoder_seek_to_pcm_frame_locked(state, (ma_uint64)target)) {
    state->position_frames = (ma_uint64)target;
    reset_filter(filter);
  }
  state->seek_delta_seconds = 0;
}

static int open_configured_dsp(struct player_state *state) {
  int fd = open("/dev/dsp", O_WRONLY);
  if (fd < 0) {
    pthread_mutex_lock(&state->lock);
    set_audio_status_locked(state, "audio: /dev/dsp open failed");
    pthread_mutex_unlock(&state->lock);
    fprintf(stderr, "audio open failed path=/dev/dsp errno=%d %s\n", errno,
            strerror(errno));
    return -1;
  }
  fprintf(stderr, "audio open fd=%d path=/dev/dsp\n", fd);
#if defined(PLUMOS_MUSIC_HAS_OSS)
  {
    int format = AFMT_S16_LE;
    int channels = MUSIC_OUTPUT_CHANNELS;
    int speed = MUSIC_OUTPUT_RATE;
    if (ioctl(fd, SNDCTL_DSP_SETFMT, &format) != 0 ||
        ioctl(fd, SNDCTL_DSP_CHANNELS, &channels) != 0 ||
        ioctl(fd, SNDCTL_DSP_SPEED, &speed) != 0) {
      pthread_mutex_lock(&state->lock);
      set_audio_status_locked(state, "audio: OSS setup failed");
      pthread_mutex_unlock(&state->lock);
      fprintf(stderr, "audio oss setup failed fd=%d errno=%d %s\n", fd, errno,
              strerror(errno));
    } else {
      pthread_mutex_lock(&state->lock);
      set_audio_status_locked(state, "audio: /dev/dsp 48k stereo");
      pthread_mutex_unlock(&state->lock);
      fprintf(stderr, "audio oss setup ok fd=%d rate=%d channels=%d\n", fd, speed,
              channels);
    }
  }
#else
  pthread_mutex_lock(&state->lock);
  set_audio_status_locked(state, "audio: OSS headers unavailable");
  pthread_mutex_unlock(&state->lock);
#endif
  return fd;
}

static void music_audio_output_close(struct music_audio_output *out) {
  if (!out) {
    return;
  }
#ifdef PLUMOS_MUSIC_ENABLE_ALSA
  if (out->alsa) {
    snd_pcm_drain(out->alsa);
    snd_pcm_close(out->alsa);
    out->alsa = NULL;
  }
#endif
  if (out->fd >= 0) {
    close(out->fd);
    out->fd = -1;
  }
}

static int music_audio_output_ready(const struct music_audio_output *out) {
  if (!out) {
    return 0;
  }
#ifdef PLUMOS_MUSIC_ENABLE_ALSA
  if (out->alsa) {
    return 1;
  }
#endif
  return out->fd >= 0;
}

#ifdef PLUMOS_MUSIC_ENABLE_ALSA
static int open_configured_alsa(struct player_state *state,
                                struct music_audio_output *out) {
  const char *device = getenv("PLUMOS_MUSIC_ALSA_DEVICE");
  unsigned int latency_us = 100000;
  long long configured_latency;
  int rc;

  if (!device || !device[0]) {
    device = getenv("PLUMOS_MUSIC_PLAYER_AUDIO_DEVICE");
  }
  if (!device || !device[0]) {
    device = "hw:0,0";
  }
  configured_latency = parse_env_ms("PLUMOS_MUSIC_ALSA_LATENCY_US");
  if (configured_latency > 0 && configured_latency <= 1000000) {
    latency_us = (unsigned int)configured_latency;
  }
  rc = snd_pcm_open(&out->alsa, device, SND_PCM_STREAM_PLAYBACK, 0);
  if (rc < 0) {
    pthread_mutex_lock(&state->lock);
    set_audio_status_locked(state, "audio: ALSA open failed");
    pthread_mutex_unlock(&state->lock);
    fprintf(stderr, "audio alsa open failed device=%s rc=%d %s\n", device, rc,
            snd_strerror(rc));
    out->alsa = NULL;
    return 0;
  }
  rc = snd_pcm_set_params(out->alsa, SND_PCM_FORMAT_S16_LE,
                          SND_PCM_ACCESS_RW_INTERLEAVED, MUSIC_OUTPUT_CHANNELS,
                          MUSIC_OUTPUT_RATE, 1, latency_us);
  if (rc < 0) {
    snd_pcm_close(out->alsa);
    out->alsa = NULL;
    pthread_mutex_lock(&state->lock);
    set_audio_status_locked(state, "audio: ALSA setup failed");
    pthread_mutex_unlock(&state->lock);
    fprintf(stderr, "audio alsa setup failed device=%s rc=%d %s\n", device, rc,
            snd_strerror(rc));
    return 0;
  }
  pthread_mutex_lock(&state->lock);
  set_audio_status_locked(state, "audio: ALSA hw:0,0 48k stereo");
  pthread_mutex_unlock(&state->lock);
  fprintf(stderr, "audio alsa setup ok device=%s rate=%d channels=%d\n", device,
          MUSIC_OUTPUT_RATE, MUSIC_OUTPUT_CHANNELS);
  return 1;
}
#endif

static struct music_audio_output open_configured_audio(struct player_state *state) {
  struct music_audio_output out;
  out.fd = -1;
#ifdef PLUMOS_MUSIC_ENABLE_ALSA
  out.alsa = NULL;
  if (open_configured_alsa(state, &out)) {
    return out;
  }
#endif
  out.fd = open_configured_dsp(state);
  return out;
}

static int music_audio_output_write(struct music_audio_output *out,
                                    const int16_t *data, ma_uint64 frames) {
  if (!out || !data || frames == 0) {
    return 1;
  }
#ifdef PLUMOS_MUSIC_ENABLE_ALSA
  if (out->alsa) {
    ma_uint64 pos = 0;
    while (pos < frames) {
      snd_pcm_sframes_t rc =
          snd_pcm_writei(out->alsa,
                         data + (size_t)pos * MUSIC_OUTPUT_CHANNELS,
                         (snd_pcm_uframes_t)(frames - pos));
      if (rc == -EPIPE) {
        snd_pcm_prepare(out->alsa);
        continue;
      }
      if (rc < 0) {
        rc = snd_pcm_recover(out->alsa, (int)rc, 1);
        if (rc < 0) {
          fprintf(stderr, "audio alsa write failed rc=%ld %s\n", (long)rc,
                  snd_strerror((int)rc));
          return 0;
        }
        continue;
      }
      if (rc == 0) {
        return 0;
      }
      pos += (ma_uint64)rc;
    }
    return 1;
  }
#endif
  if (out->fd >= 0) {
    return write_full(out->fd, data,
                      (size_t)frames * MUSIC_OUTPUT_CHANNELS * sizeof(data[0]));
  }
  return 0;
}

static void *audio_thread_main(void *arg) {
  struct player_state *state = (struct player_state *)arg;
  struct audio_filter filter;
  float pcm[MUSIC_AUDIO_CHUNK_FRAMES * MUSIC_OUTPUT_CHANNELS];
  int16_t out[MUSIC_AUDIO_CHUNK_FRAMES * MUSIC_OUTPUT_CHANNELS];
  struct music_audio_output audio = open_configured_audio(state);
  int wrote_audio_once = 0;
  reset_filter(&filter);
  while (state->running) {
    ma_uint64 frames_read = 0;
    int should_sleep = 0;
    int ended = 0;
    int eq_index;
    float volume;

    pthread_mutex_lock(&state->lock);
    if (state->decoder_ready && state->playing && !state->paused) {
      handle_seek_locked(state, &filter);
      eq_index = state->eq_index;
      volume = state->volume;
      if (music_decoder_read_pcm_frames_locked(state, pcm, MUSIC_AUDIO_CHUNK_FRAMES,
                                               &frames_read) &&
          frames_read > 0) {
        state->position_frames += frames_read;
      } else {
        ended = 1;
      }
    } else {
      should_sleep = 1;
      eq_index = state->eq_index;
      volume = state->volume;
    }

    if (ended) {
      int next = state->current + 1;
      if (next >= 0 && next < state->track_count) {
        load_track_locked(state, next, "Playing");
        reset_filter(&filter);
      } else {
        unload_decoder_locked(state);
        set_status_locked(state, "Finished");
      }
    }
    pthread_mutex_unlock(&state->lock);

    if (frames_read > 0 && music_audio_output_ready(&audio)) {
      apply_eq_and_convert(pcm, out, frames_read, &k_eq_presets[eq_index], volume,
                           &filter);
      if (!music_audio_output_write(&audio, out, frames_read)) {
        fprintf(stderr, "audio write failed errno=%d %s\n", errno, strerror(errno));
        music_audio_output_close(&audio);
        pthread_mutex_lock(&state->lock);
        set_audio_status_locked(state, "audio: write failed");
        pthread_mutex_unlock(&state->lock);
      } else if (!wrote_audio_once) {
        fprintf(stderr, "audio write ok frames=%llu bytes=%llu\n",
                (unsigned long long)frames_read,
                (unsigned long long)(frames_read * MUSIC_OUTPUT_CHANNELS * sizeof(out[0])));
        wrote_audio_once = 1;
      }
    } else if (should_sleep || !music_audio_output_ready(&audio)) {
      usleep(10000);
      if (!music_audio_output_ready(&audio)) {
        audio = open_configured_audio(state);
        if (!music_audio_output_ready(&audio)) {
          usleep(250000);
        }
      }
    }
  }
  music_audio_output_close(&audio);
  return NULL;
}

static int read_trimmed_file(const char *path, char *out, size_t out_size) {
  int fd;
  ssize_t n;
  if (!out || out_size == 0) {
    return 0;
  }
  out[0] = '\0';
  fd = open(path, O_RDONLY);
  if (fd < 0) {
    return 0;
  }
  n = read(fd, out, out_size - 1);
  close(fd);
  if (n <= 0) {
    return 0;
  }
  out[n] = '\0';
  while (n > 0 && (out[n - 1] == '\n' || out[n - 1] == '\r' || out[n - 1] == ' ')) {
    out[--n] = '\0';
  }
  return 1;
}

static int input_name_matches_mmf_gamepad(const char *name) {
  return name && (strcmp(name, "soc:gpio_keys") == 0 ||
                  strcmp(name, "gpio-keys") == 0 ||
                  strcmp(name, "gpio-keys-polled") == 0);
}

static int input_name_matches_a30_gamepad(const char *name) {
  return name && strstr(name, "plumOS A30 Gamepad") != NULL;
}

static int input_name_matches_v90s_gamepad(const char *name) {
  return name && (strstr(name, "adc_gamepad") != NULL ||
                  strstr(name, "adc gamepad") != NULL ||
                  strstr(name, "plumOS V90S") != NULL);
}

static int input_name_matches_v90s_fallback(const char *name) {
  return name && (strstr(name, "sunxi-keyboard") != NULL ||
                  strstr(name, "gpio-keys") != NULL);
}

static int input_device_name_from_event_path(const char *event_path, char *out,
                                             size_t out_size) {
  const char *base;
  char sys_path[128];
  if (!event_path || !out || out_size == 0) {
    return 0;
  }
  out[0] = '\0';
  base = strrchr(event_path, '/');
  base = base ? base + 1 : event_path;
  if (strncmp(base, "event", 5) != 0) {
    return 0;
  }
  snprintf(sys_path, sizeof(sys_path), "/sys/class/input/%s/device/name", base);
  return read_trimmed_file(sys_path, out, out_size);
}

static int find_gamepad_event(char *out, size_t out_size, char *name_out,
                              size_t name_out_size) {
  int i;
  const char *override = getenv("PLUMOS_MUSIC_INPUT_EVENT");
  if (name_out && name_out_size > 0) {
    name_out[0] = '\0';
  }
  if (override && override[0]) {
    snprintf(out, out_size, "%s", override);
    input_device_name_from_event_path(out, name_out, name_out_size);
    return 1;
  }
  for (i = 0; i < 32; i++) {
    char path[128];
    char name[128];
    snprintf(path, sizeof(path), "/sys/class/input/event%d/device/name", i);
    if (read_trimmed_file(path, name, sizeof(name)) &&
        input_name_matches_v90s_gamepad(name)) {
      snprintf(out, out_size, "/dev/input/event%d", i);
      if (name_out && name_out_size > 0) {
        snprintf(name_out, name_out_size, "%s", name);
      }
      return 1;
    }
  }
  for (i = 0; i < 32; i++) {
    char path[128];
    char name[128];
    snprintf(path, sizeof(path), "/sys/class/input/event%d/device/name", i);
    if (read_trimmed_file(path, name, sizeof(name)) &&
        input_name_matches_a30_gamepad(name)) {
      snprintf(out, out_size, "/dev/input/event%d", i);
      if (name_out && name_out_size > 0) {
        snprintf(name_out, name_out_size, "%s", name);
      }
      return 1;
    }
  }
  for (i = 0; i < 32; i++) {
    char path[128];
    char name[128];
    snprintf(path, sizeof(path), "/sys/class/input/event%d/device/name", i);
    if (read_trimmed_file(path, name, sizeof(name)) &&
        input_name_matches_mmf_gamepad(name)) {
      snprintf(out, out_size, "/dev/input/event%d", i);
      if (name_out && name_out_size > 0) {
        snprintf(name_out, name_out_size, "%s", name);
      }
      return 1;
    }
  }
  for (i = 0; i < 32; i++) {
    char path[128];
    char name[128];
    snprintf(path, sizeof(path), "/sys/class/input/event%d/device/name", i);
    if (read_trimmed_file(path, name, sizeof(name)) &&
        input_name_matches_v90s_fallback(name)) {
      snprintf(out, out_size, "/dev/input/event%d", i);
      if (name_out && name_out_size > 0) {
        snprintf(name_out, name_out_size, "%s", name);
      }
      return 1;
    }
  }
  return 0;
}

static const char *key_code_name(unsigned short code) {
  switch (code) {
  case KEY_UP:
    return "KEY_UP";
  case KEY_DOWN:
    return "KEY_DOWN";
  case KEY_LEFT:
    return "KEY_LEFT";
  case KEY_RIGHT:
    return "KEY_RIGHT";
  case KEY_SPACE:
    return "KEY_SPACE/A";
  case KEY_LEFTCTRL:
    return "KEY_LEFTCTRL/B";
  case KEY_LEFTSHIFT:
    return "KEY_LEFTSHIFT/X";
  case KEY_LEFTALT:
    return "KEY_LEFTALT/Y";
  case KEY_ENTER:
    return "KEY_ENTER/START";
  case KEY_RIGHTCTRL:
    return "KEY_RIGHTCTRL/SELECT";
  case KEY_ESC:
    return "KEY_ESC/FUNCTION";
  case KEY_TAB:
    return "KEY_TAB/L(raw)";
  case KEY_BACKSPACE:
    return "KEY_BACKSPACE/R(raw)";
  case KEY_E:
    return "KEY_E/L(raw)";
  case KEY_T:
    return "KEY_T/R(raw)";
  case KEY_VOLUMEDOWN:
    return "KEY_VOLUMEDOWN";
  case KEY_VOLUMEUP:
    return "KEY_VOLUMEUP";
  case BTN_A:
    return "BTN_A";
  case BTN_B:
    return "BTN_B";
  case BTN_X:
    return "BTN_X";
  case BTN_Y:
    return "BTN_Y";
  case BTN_START:
    return "BTN_START";
  case BTN_SELECT:
    return "BTN_SELECT";
  case BTN_MODE:
    return "BTN_MODE";
  case BTN_TL:
    return "BTN_TL";
  case BTN_TR:
    return "BTN_TR";
  default:
    return "unknown";
  }
}

static void select_delta(struct player_state *state, int delta) {
  pthread_mutex_lock(&state->lock);
  if (state->track_count > 0) {
    state->selected += delta;
    if (state->selected < 0) {
      state->selected = state->track_count - 1;
    } else if (state->selected >= state->track_count) {
      state->selected = 0;
    }
    if (state->selected < state->scroll) {
      state->scroll = state->selected;
    } else if (state->selected >= state->scroll + MUSIC_LIST_ROWS) {
      state->scroll = state->selected - MUSIC_LIST_ROWS + 1;
    }
    if (state->scroll < 0) {
      state->scroll = 0;
    }
  }
  pthread_mutex_unlock(&state->lock);
}

static void request_fast_exit(struct player_state *state) {
  state->fast_exit_requested = 1;
  state->running = 0;
}

static void handle_key_press(struct player_state *state, unsigned short code, int repeat) {
  switch (code) {
  case KEY_UP:
    select_delta(state, -1);
    break;
  case KEY_DOWN:
    select_delta(state, 1);
    break;
  case KEY_LEFT:
    request_seek(state, -5);
    break;
  case KEY_RIGHT:
    request_seek(state, 5);
    break;
  case KEY_SPACE:
  case KEY_ENTER:
  case BTN_A:
  case BTN_START:
    if (repeat) {
      break;
    }
    toggle_play_selected(state);
    break;
  case KEY_LEFTCTRL:
  case KEY_ESC:
  case BTN_B:
  case BTN_MODE:
    if (repeat) {
      break;
    }
    request_fast_exit(state);
    break;
  case KEY_LEFTSHIFT:
  case BTN_X:
    if (repeat) {
      break;
    }
    play_relative(state, -1);
    break;
  case KEY_LEFTALT:
  case BTN_Y:
    if (repeat) {
      break;
    }
    play_relative(state, 1);
    break;
  case KEY_RIGHTCTRL:
  case BTN_SELECT:
    if (repeat) {
      break;
    }
    cycle_eq(state);
    break;
  case KEY_TAB:
  case KEY_E:
  case BTN_TL:
    adjust_volume(state, -0.05f);
    break;
  case KEY_BACKSPACE:
  case KEY_T:
  case BTN_TR:
    adjust_volume(state, 0.05f);
    break;
  default:
    break;
  }
}

static void process_input_event(struct player_state *state, const struct input_event *ev) {
  if (!state || !ev) {
    return;
  }
  if (ev->type == EV_KEY) {
    if (ev->value == 1 || ev->value == 2) {
      fprintf(stderr, "input key code=%u name=%s value=%d\n", ev->code,
              key_code_name(ev->code), ev->value);
      handle_key_press(state, ev->code, ev->value == 2);
    }
  } else if (ev->type == EV_ABS) {
    if (ev->code == ABS_Y) {
      if (ev->value <= -MUSIC_ABS_AXIS_DEADZONE) {
        select_delta(state, -1);
      } else if (ev->value >= MUSIC_ABS_AXIS_DEADZONE) {
        select_delta(state, 1);
      }
    } else if (ev->code == ABS_X) {
      if (ev->value <= -MUSIC_ABS_AXIS_DEADZONE) {
        request_seek(state, -5);
      } else if (ev->value >= MUSIC_ABS_AXIS_DEADZONE) {
        request_seek(state, 5);
      }
    } else if (ev->code == ABS_HAT0Y) {
      if (ev->value < 0) {
        select_delta(state, -1);
      } else if (ev->value > 0) {
        select_delta(state, 1);
      }
    } else if (ev->code == ABS_HAT0X) {
      if (ev->value < 0) {
        request_seek(state, -5);
      } else if (ev->value > 0) {
        request_seek(state, 5);
      }
    }
  }
}

static void drain_input_fd(int fd) {
  struct input_event ev;
  if (fd < 0) {
    return;
  }
  while (read(fd, &ev, sizeof(ev)) == (ssize_t)sizeof(ev)) {
  }
}

static int open_input_event(struct player_state *state, const char *event_path,
                            const char *event_name) {
  int fd;
  fd = open(event_path, O_RDONLY | O_NONBLOCK);
  if (fd >= 0) {
    char msg[128];
    fcntl(fd, F_SETFD, FD_CLOEXEC);
    drain_input_fd(fd);
    snprintf(msg, sizeof(msg), "input: %s%s%s", event_path,
             event_name && event_name[0] ? " " : "",
             event_name && event_name[0] ? event_name : "");
    pthread_mutex_lock(&state->lock);
    set_input_status_locked(state, msg);
    pthread_mutex_unlock(&state->lock);
    fprintf(stderr, "input opened path=%s name=%s\n", event_path,
            event_name && event_name[0] ? event_name : "-");
  } else {
    char msg[128];
    snprintf(msg, sizeof(msg), "input open failed: %s", strerror(errno));
    pthread_mutex_lock(&state->lock);
    set_input_status_locked(state, msg);
    pthread_mutex_unlock(&state->lock);
    fprintf(stderr, "input open failed path=%s errno=%d %s\n", event_path, errno,
            strerror(errno));
  }
  return fd;
}

static void format_time(char *out, size_t out_size, ma_uint64 frames) {
  unsigned long seconds = (unsigned long)(frames / MUSIC_OUTPUT_RATE);
  unsigned long min = seconds / 60UL;
  unsigned long sec = seconds % 60UL;
  snprintf(out, out_size, "%lu:%02lu", min, sec);
}

static int clamp_color_channel(float value) {
  int out = (int)lrintf(value * 255.0f);
  if (out < 0) {
    return 0;
  }
  if (out > 255) {
    return 255;
  }
  return out;
}

static uint32_t music_color(struct plumos_mmf_gfx_renderer *renderer, float r, float g,
                            float b) {
  return plumos_mmf_gfx_rgb_color(renderer, (uint8_t)clamp_color_channel(r),
                                  (uint8_t)clamp_color_channel(g),
                                  (uint8_t)clamp_color_channel(b));
}

static int float_to_int(float value) {
  return (int)lrintf(value);
}

static void draw_rect(struct plumos_mmf_gfx_renderer *renderer, float x, float y,
                             float w, float h, float r, float g, float b, float a) {
  (void)a;
  plumos_mmf_gfx_fill_rect(renderer, float_to_int(x), float_to_int(y),
                           float_to_int(w), float_to_int(h),
                           music_color(renderer, r, g, b));
}

static void draw_text_ft(struct plumos_mmf_gfx_renderer *renderer, const char *text, float x,
                         float y, int scale, float max_x, float r, float g, float b,
                         float a) {
  (void)a;
  plumos_mmf_gfx_text_limited(renderer, text ? text : "", float_to_int(x),
                              float_to_int(y), scale, music_color(renderer, r, g, b),
                              float_to_int(max_x));
}

static void draw_progress(struct plumos_mmf_gfx_renderer *renderer, float x, float y, float w,
                          float h, ma_uint64 pos, ma_uint64 len) {
  float ratio = 0.0f;
  draw_rect(renderer, x, y, w, h, 0.13f, 0.14f, 0.17f, 1.0f);
  if (len > 0 && pos <= len) {
    ratio = (float)((double)pos / (double)len);
  } else if (len > 0) {
    ratio = 1.0f;
  }
  if (ratio > 0.0f) {
    draw_rect(renderer, x, y, w * ratio, h, 0.95f, 0.48f, 0.10f, 1.0f);
  }
}

static void draw_border(struct plumos_mmf_gfx_renderer *renderer, float x, float y, float w,
                        float h, float r, float g, float b, float a) {
  draw_rect(renderer, x, y, w, 2.0f, r, g, b, a);
  draw_rect(renderer, x, y + h - 2.0f, w, 2.0f, r, g, b, a);
  draw_rect(renderer, x, y, 2.0f, h, r, g, b, a);
  draw_rect(renderer, x + w - 2.0f, y, 2.0f, h, r, g, b, a);
}

static void album_art_texture_delete(struct plumos_mmf_gfx_renderer *renderer,
                                     struct album_art_texture *texture) {
  (void)renderer;
  if (texture) {
    free(texture->rgba);
    texture->rgba = NULL;
    texture->width = 0;
    texture->height = 0;
  }
}

static void album_art_texture_upload(struct plumos_mmf_gfx_renderer *renderer,
                                     struct album_art_texture *texture,
                                     const unsigned char *rgba, int width, int height,
                                     unsigned int generation) {
  size_t size;
  if (!texture || texture->generation == generation) {
    return;
  }
  album_art_texture_delete(renderer, texture);
  texture->generation = generation;
  if (!rgba || width <= 0 || height <= 0) {
    return;
  }
  size = (size_t)width * (size_t)height * 4u;
  texture->rgba = (unsigned char *)malloc(size);
  if (!texture->rgba) {
    return;
  }
  memcpy(texture->rgba, rgba, size);
  texture->width = width;
  texture->height = height;
}

static int draw_album_art_texture(struct plumos_mmf_gfx_renderer *renderer,
                                  const struct album_art_texture *texture, float x,
                                  float y, float w, float h) {
  float image_aspect;
  float target_aspect;
  float draw_w;
  float draw_h;
  float draw_x;
  float draw_y;
  int dst_x;
  int dst_y;
  int dst_w;
  int dst_h;
  int yy;
  int xx;

  if (!renderer || !texture || !texture->rgba || texture->width <= 0 ||
      texture->height <= 0 || w <= 0.0f || h <= 0.0f) {
    return 0;
  }
  image_aspect = (float)texture->width / (float)texture->height;
  target_aspect = w / h;
  draw_w = w;
  draw_h = h;
  if (image_aspect > target_aspect) {
    draw_h = w / image_aspect;
  } else {
    draw_w = h * image_aspect;
  }
  draw_x = x + (w - draw_w) * 0.5f;
  draw_y = y + (h - draw_h) * 0.5f;
  dst_x = float_to_int(draw_x);
  dst_y = float_to_int(draw_y);
  dst_w = float_to_int(draw_w);
  dst_h = float_to_int(draw_h);
  if (dst_w <= 0 || dst_h <= 0) {
    return 0;
  }
  for (yy = 0; yy < dst_h; yy++) {
    int sy = (int)((long long)yy * texture->height / dst_h);
    for (xx = 0; xx < dst_w; xx++) {
      int sx = (int)((long long)xx * texture->width / dst_w);
      const unsigned char *p =
          texture->rgba + ((size_t)sy * (size_t)texture->width + (size_t)sx) * 4u;
      plumos_mmf_gfx_blend_rgba(renderer, dst_x + xx, dst_y + yy, p[0], p[1],
                                p[2], p[3]);
    }
  }
  return 1;
}

static void render_player(struct plumos_mmf_gfx_renderer *renderer, struct player_state *state,
                          struct album_art_texture *art_texture) {
  int track_count;
  int selected;
  int current;
  int scroll;
  int playing;
  int paused;
  int eq_index;
  int volume_percent;
  ma_uint64 pos;
  ma_uint64 len;
  unsigned int art_generation;
  int art_width;
  int art_height;
  char art_status[64];
  char current_name[MUSIC_NAME_MAX];
  char status[192];
  char audio_status[128];
  char input_status[128];
  char time_text[64];
  int i;

  pthread_mutex_lock(&state->lock);
  track_count = state->track_count;
  selected = state->selected;
  current = state->current;
  scroll = state->scroll;
  playing = state->playing;
  paused = state->paused;
  eq_index = state->eq_index;
  volume_percent = (int)lrintf(state->volume * 100.0f);
  pos = state->position_frames;
  len = state->length_frames;
  snprintf(current_name, sizeof(current_name), "%s",
           current >= 0 && current < state->track_count ? state->tracks[current].name : "-");
  snprintf(status, sizeof(status), "%s", state->status);
  snprintf(audio_status, sizeof(audio_status), "%s", state->audio_status);
  snprintf(input_status, sizeof(input_status), "%s", state->input_status);
  art_generation = state->art.generation;
  art_width = state->art.width;
  art_height = state->art.height;
  snprintf(art_status, sizeof(art_status), "%s", state->art.status);
  album_art_texture_upload(renderer, art_texture, state->art.rgba, state->art.width,
                           state->art.height, state->art.generation);
  pthread_mutex_unlock(&state->lock);

  draw_rect(renderer, 0.0f, 0.0f, (float)renderer->var.xres,
                   (float)renderer->var.yres, 0.030f, 0.034f, 0.042f, 1.0f);

  draw_rect(renderer, 0.0f, 0.0f, (float)renderer->var.xres, 44.0f, 0.06f,
                   0.07f, 0.09f, 1.0f);
  draw_rect(renderer, 0.0f, 44.0f, (float)renderer->var.xres, 3.0f, 0.95f, 0.48f,
                   0.10f, 1.0f);
  draw_text_ft(renderer, "plumOS Music Player", 16.0f, 12.0f, 2,
               (float)renderer->var.xres - 16.0f, 0.95f, 0.96f, 0.98f, 1.0f);

  if (track_count <= 0) {
    draw_text_ft(renderer, "No music found", 24.0f, 95.0f, 3,
                 (float)renderer->var.xres - 24.0f, 0.95f, 0.96f, 0.98f, 1.0f);
    draw_text_ft(renderer, "Place MP3 / FLAC / WAV files in /mnt/plumos/music", 24.0f,
                 150.0f, 2, (float)renderer->var.xres - 24.0f, 0.70f, 0.75f, 0.82f,
                 1.0f);
  } else {
    float art_size = 132.0f;
    float art_x = (float)renderer->var.xres - art_size - 16.0f;
    float art_y = 62.0f;
    float list_w = art_x - 24.0f;
    float y = 62.0f;
    if (list_w < 300.0f) {
      list_w = (float)renderer->var.xres - 24.0f;
      art_size = 0.0f;
    }
    for (i = 0; i < MUSIC_LIST_ROWS; i++) {
      int idx = scroll + i;
      char line[MUSIC_NAME_MAX + 16];
      float row_y = y + (float)i * 34.0f;
      float bg_r = idx == selected ? 0.18f : 0.06f;
      float bg_g = idx == selected ? 0.18f : 0.07f;
      float bg_b = idx == selected ? 0.21f : 0.09f;
      if (idx >= track_count) {
        break;
      }
      draw_rect(renderer, 12.0f, row_y, list_w, 29.0f, bg_r, bg_g, bg_b,
                       1.0f);
      if (idx == current && playing && !paused) {
        snprintf(line, sizeof(line), "> %s", state->tracks[idx].name);
      } else if (idx == current && paused) {
        snprintf(line, sizeof(line), "|| %s", state->tracks[idx].name);
      } else {
        snprintf(line, sizeof(line), "  %s", state->tracks[idx].name);
      }
      draw_text_ft(renderer, line, 22.0f, row_y + 7.0f, 2,
                   12.0f + list_w - 8.0f, 0.90f, 0.92f, 0.95f, 1.0f);
    }
    if (art_size > 0.0f) {
      draw_rect(renderer, art_x, art_y, art_size, art_size, 0.035f, 0.039f,
                       0.050f, 1.0f);
      draw_border(renderer, art_x, art_y, art_size, art_size, 0.18f, 0.20f, 0.25f,
                  1.0f);
      if (art_texture && art_texture->rgba && art_generation == art_texture->generation &&
          art_width > 0 && art_height > 0) {
        draw_album_art_texture(renderer, art_texture, art_x + 6.0f, art_y + 6.0f,
                               art_size - 12.0f, art_size - 12.0f);
      } else {
        draw_text_ft(renderer, art_status[0] && strcmp(art_status, "cover art") != 0 ?
                                   art_status : "NO ART",
                     art_x + 18.0f, art_y + 56.0f, 2, art_x + art_size - 12.0f,
                     0.48f, 0.54f, 0.62f, 1.0f);
      }
    }
  }

  {
    float panel_y = (float)renderer->var.yres - MUSIC_BOTTOM_PANEL_HEIGHT;
    draw_rect(renderer, 0.0f, panel_y, (float)renderer->var.xres,
                     MUSIC_BOTTOM_PANEL_HEIGHT, 0.045f, 0.050f, 0.062f, 1.0f);
    draw_text_ft(renderer, current_name, 16.0f, panel_y + 14.0f, 2,
               (float)renderer->var.xres - 16.0f, 1.0f, 1.0f, 1.0f, 1.0f);
    draw_progress(renderer, 16.0f, panel_y + 52.0f,
                (float)renderer->var.xres - 32.0f, 10.0f, pos, len);
    {
      char t1[24];
      char t2[24];
      format_time(t1, sizeof(t1), pos);
      format_time(t2, sizeof(t2), len);
      snprintf(time_text, sizeof(time_text), "%s / %s   EQ:%s   VOL:%d%%", t1, t2,
               k_eq_presets[eq_index].name, volume_percent);
    }
    draw_text_ft(renderer, time_text, 16.0f, panel_y + 70.0f, 2,
               (float)renderer->var.xres - 16.0f, 0.78f, 0.83f, 0.90f, 1.0f);
    draw_text_ft(renderer, status[0] ? status : (input_status[0] ? input_status : audio_status), 16.0f,
               panel_y + 94.0f, 2, (float)renderer->var.xres - 16.0f,
               0.95f, 0.65f, 0.28f, 1.0f);
    draw_text_ft(renderer, "A Play/Pause   B Exit   Left/Right 5s", 16.0f,
                 panel_y + 110.0f, 2, (float)renderer->var.xres - 16.0f, 0.62f,
                 0.68f, 0.75f, 1.0f);
    draw_text_ft(renderer, "X/Y Track   SELECT EQ   L/R Volume", 16.0f,
                 panel_y + 130.0f, 2, (float)renderer->var.xres - 16.0f, 0.62f,
                 0.68f, 0.75f, 1.0f);
  }

  plumos_mmf_gfx_present(renderer);
}

static int init_renderer(struct plumos_mmf_gfx_renderer *renderer) {
  char err[256];
  const char *fb = getenv("PLUMOS_FB");
  const char *rotation = getenv("PLUMOS_MUSIC_ROTATION");
  const char *font = getenv("PLUMOS_MUSIC_FONT");
  const char *fallback = getenv("PLUMOS_MUSIC_FALLBACK_FONT");
  if (!rotation || !rotation[0]) {
    rotation = "none";
  }
  if (!font || !font[0]) {
    font = "/mnt/plumos/fonts/default.otf";
  }
  if (!fallback || !fallback[0]) {
    fallback = "/mnt/plumos/fonts/cjk-fallback.ttc";
  }
  if (!plumos_mmf_gfx_renderer_init(renderer, fb && fb[0] ? fb : "/dev/fb0",
                                    err, sizeof(err))) {
    fprintf(stderr, "renderer init failed: %s\n", err);
    return 0;
  }
  plumos_mmf_gfx_renderer_set_rotation(renderer, rotation);
  if (!plumos_mmf_gfx_renderer_load_font(renderer, font, err, sizeof(err))) {
    fprintf(stderr, "font load failed: %s\n", err);
  }
  if (!plumos_mmf_gfx_renderer_load_fallback_font(renderer, fallback, err, sizeof(err))) {
    fprintf(stderr, "fallback font load failed: %s\n", err);
  }
  return 1;
}

int main(void) {
  static struct player_state state;
  struct plumos_mmf_gfx_renderer renderer;
  struct album_art_texture art_texture;
  int input_fd = -1;
  long long last_input_scan = 0;
  long long start_ms = monotonic_ms();
  long long exit_after_ms = parse_env_ms("PLUMOS_MUSIC_EXIT_AFTER_MS");
  if (exit_after_ms == 0) {
    exit_after_ms = parse_env_ms("PLUMOS_APP_EXIT_AFTER_MS");
  }

  memset(&state, 0, sizeof(state));
  memset(&art_texture, 0, sizeof(art_texture));
  state.running = 1;
  state.current = -1;
  state.volume = 0.80f;
  pthread_mutex_init(&state.lock, NULL);
  scan_music(&state);
  snprintf(state.status, sizeof(state.status), "%d tracks", state.track_count);
  if (getenv("PLUMOS_MUSIC_AUTOPLAY") && state.track_count > 0) {
    pthread_mutex_lock(&state.lock);
    load_track_locked(&state, 0, "Playing");
    pthread_mutex_unlock(&state.lock);
  }

  if (!init_renderer(&renderer)) {
    pthread_mutex_destroy(&state.lock);
    return 1;
  }
  if (pthread_create(&state.audio_thread, NULL, audio_thread_main, &state) == 0) {
    state.audio_thread_started = 1;
  } else {
    pthread_mutex_lock(&state.lock);
    set_audio_status_locked(&state, "audio thread failed");
    pthread_mutex_unlock(&state.lock);
  }

  while (state.running) {
    struct pollfd pfd;
    if (exit_after_ms > 0 && monotonic_ms() - start_ms >= exit_after_ms) {
      state.running = 0;
      break;
    }
    if (input_fd < 0 && monotonic_ms() - last_input_scan > 1000) {
      char event_path[64];
      char event_name[128];
      last_input_scan = monotonic_ms();
      if (find_gamepad_event(event_path, sizeof(event_path), event_name,
                             sizeof(event_name))) {
        input_fd = open_input_event(&state, event_path, event_name);
      } else {
        pthread_mutex_lock(&state.lock);
        set_input_status_locked(&state, "input: no gamepad event");
        pthread_mutex_unlock(&state.lock);
      }
    }
    if (input_fd >= 0) {
      pfd.fd = input_fd;
      pfd.events = POLLIN;
      if (poll(&pfd, 1, 10) > 0 && (pfd.revents & POLLIN)) {
        struct input_event ev;
        while (read(input_fd, &ev, sizeof(ev)) == (ssize_t)sizeof(ev)) {
          process_input_event(&state, &ev);
        }
      }
    } else {
      usleep(10000);
    }
    render_player(&renderer, &state, &art_texture);
    usleep(35000);
  }

  state.running = 0;
  if (state.fast_exit_requested) {
    fprintf(stderr, "fast exit requested by input\n");
    if (input_fd >= 0) {
      close(input_fd);
    }
    album_art_texture_delete(&renderer, &art_texture);
    plumos_mmf_gfx_renderer_shutdown(&renderer);
    _exit(0);
  }
  if (state.audio_thread_started) {
    pthread_join(state.audio_thread, NULL);
  }
  pthread_mutex_lock(&state.lock);
  unload_decoder_locked(&state);
  pthread_mutex_unlock(&state.lock);
  if (input_fd >= 0) {
    close(input_fd);
  }
  album_art_texture_delete(&renderer, &art_texture);
  plumos_mmf_gfx_renderer_shutdown(&renderer);
  pthread_mutex_destroy(&state.lock);
  return 0;
}
