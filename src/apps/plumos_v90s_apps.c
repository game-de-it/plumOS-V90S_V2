#include <ctype.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <linux/input.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#include "../frontend/plumos_fbdev_renderer.h"

#ifndef PATH_MAX
#define PATH_MAX 4096
#endif

#ifndef BTN_DPAD_UP
#define BTN_DPAD_UP 0x220
#endif
#ifndef BTN_DPAD_DOWN
#define BTN_DPAD_DOWN 0x221
#endif
#ifndef BTN_DPAD_LEFT
#define BTN_DPAD_LEFT 0x222
#endif
#ifndef BTN_DPAD_RIGHT
#define BTN_DPAD_RIGHT 0x223
#endif
#ifndef BTN_SOUTH
#define BTN_SOUTH 0x130
#endif
#ifndef BTN_EAST
#define BTN_EAST 0x131
#endif
#ifndef BTN_NORTH
#define BTN_NORTH 0x133
#endif
#ifndef BTN_WEST
#define BTN_WEST 0x134
#endif
#ifndef BTN_SELECT
#define BTN_SELECT 0x13a
#endif
#ifndef BTN_START
#define BTN_START 0x13b
#endif
#ifndef BTN_MODE
#define BTN_MODE 0x13c
#endif
#ifndef KEY_SELECT
#define KEY_SELECT 0x161
#endif

#define APP_MAX_ITEMS 512
#define APP_NAME_MAX 256
#define APP_ROWS 10

enum app_mode {
  APP_FILE_MANAGER = 0,
  APP_MUSIC_PLAYER = 1,
};

enum app_action {
  ACTION_NONE = 0,
  ACTION_UP,
  ACTION_DOWN,
  ACTION_LEFT,
  ACTION_RIGHT,
  ACTION_A,
  ACTION_B,
  ACTION_START,
  ACTION_SELECT,
  ACTION_QUIT,
};

struct app_item {
  char name[APP_NAME_MAX];
  char path[PATH_MAX];
  char detail[96];
  int is_dir;
  int playable;
};

struct app_state {
  enum app_mode mode;
  struct plumos_fbdev_renderer fb;
  int renderer_ready;
  int input_fd;
  int stdin_flags;
  struct app_item items[APP_MAX_ITEMS];
  size_t item_count;
  size_t cursor;
  size_t scroll;
  char cwd[PATH_MAX];
  char plumos_root[PATH_MAX];
  char status[256];
  pid_t player_pid;
  long long exit_after_ms;
  long long start_ms;
};

static volatile sig_atomic_t g_exit_requested = 0;

static void on_signal(int sig) {
  (void)sig;
  g_exit_requested = 1;
}

static long long now_ms(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (long long)ts.tv_sec * 1000LL + ts.tv_nsec / 1000000LL;
}

static int copy_string(char *dst, size_t dst_size, const char *src) {
  size_t len;
  if (!dst || dst_size == 0) {
    return 0;
  }
  if (!src) {
    src = "";
  }
  len = strlen(src);
  if (len >= dst_size) {
    len = dst_size - 1;
  }
  memcpy(dst, src, len);
  dst[len] = '\0';
  return src[len] == '\0';
}

static int join_path(char *dst, size_t dst_size, const char *a, const char *b) {
  size_t alen;
  if (!a || !a[0]) {
    a = "/";
  }
  if (!b) {
    b = "";
  }
  alen = strlen(a);
  if (alen > 1 && a[alen - 1] == '/') {
    return snprintf(dst, dst_size, "%s%s", a, b) > 0 &&
           strlen(dst) < dst_size;
  }
  return snprintf(dst, dst_size, "%s/%s", a, b) > 0 &&
         strlen(dst) < dst_size;
}

static int path_parent(char *path) {
  char *slash;
  if (!path || strcmp(path, "/") == 0) {
    return 0;
  }
  slash = strrchr(path, '/');
  if (!slash) {
    return 0;
  }
  if (slash == path) {
    path[1] = '\0';
  } else {
    *slash = '\0';
  }
  return 1;
}

static const char *base_name(const char *path) {
  const char *slash;
  if (!path) {
    return "";
  }
  slash = strrchr(path, '/');
  return slash ? slash + 1 : path;
}

static int has_audio_ext(const char *name) {
  const char *dot = strrchr(name, '.');
  char ext[16];
  size_t i;
  if (!dot || !dot[1]) {
    return 0;
  }
  dot++;
  for (i = 0; i + 1 < sizeof(ext) && dot[i]; i++) {
    ext[i] = (char)tolower((unsigned char)dot[i]);
  }
  ext[i] = '\0';
  return strcmp(ext, "wav") == 0 || strcmp(ext, "wave") == 0 ||
         strcmp(ext, "mp3") == 0 || strcmp(ext, "flac") == 0 ||
         strcmp(ext, "ogg") == 0 || strcmp(ext, "m4a") == 0;
}

static int is_wav_ext(const char *name) {
  const char *dot = strrchr(name, '.');
  char ext[8];
  size_t i;
  if (!dot || !dot[1]) {
    return 0;
  }
  dot++;
  for (i = 0; i + 1 < sizeof(ext) && dot[i]; i++) {
    ext[i] = (char)tolower((unsigned char)dot[i]);
  }
  ext[i] = '\0';
  return strcmp(ext, "wav") == 0 || strcmp(ext, "wave") == 0;
}

static int cmp_items(const void *a, const void *b) {
  const struct app_item *ia = (const struct app_item *)a;
  const struct app_item *ib = (const struct app_item *)b;
  if (ia->is_dir != ib->is_dir) {
    return ib->is_dir - ia->is_dir;
  }
  return strcasecmp(ia->name, ib->name);
}

static void add_item(struct app_state *app, const char *name, const char *path,
                     const char *detail, int is_dir, int playable) {
  struct app_item *item;
  if (!app || app->item_count >= APP_MAX_ITEMS) {
    return;
  }
  item = &app->items[app->item_count++];
  copy_string(item->name, sizeof(item->name), name);
  copy_string(item->path, sizeof(item->path), path);
  copy_string(item->detail, sizeof(item->detail), detail);
  item->is_dir = is_dir;
  item->playable = playable;
}

static void load_file_items(struct app_state *app) {
  DIR *dir;
  struct dirent *de;
  struct stat st;
  char path[PATH_MAX];

  app->item_count = 0;
  app->cursor = 0;
  app->scroll = 0;
  dir = opendir(app->cwd);
  if (!dir) {
    snprintf(app->status, sizeof(app->status), "cannot open: %s", strerror(errno));
    return;
  }
  if (strcmp(app->cwd, "/") != 0) {
    add_item(app, "..", app->cwd, "parent", 1, 0);
  }
  while ((de = readdir(dir))) {
    if (strcmp(de->d_name, ".") == 0 || strcmp(de->d_name, "..") == 0) {
      continue;
    }
    if (!join_path(path, sizeof(path), app->cwd, de->d_name)) {
      continue;
    }
    if (stat(path, &st) != 0) {
      continue;
    }
    if (S_ISDIR(st.st_mode)) {
      add_item(app, de->d_name, path, "dir", 1, 0);
    } else if (S_ISREG(st.st_mode)) {
      char detail[96];
      snprintf(detail, sizeof(detail), "%lld bytes", (long long)st.st_size);
      add_item(app, de->d_name, path, detail, 0, 0);
    }
  }
  closedir(dir);
  if (app->item_count > 1) {
    size_t offset = strcmp(app->items[0].name, "..") == 0 ? 1 : 0;
    qsort(app->items + offset, app->item_count - offset, sizeof(app->items[0]),
          cmp_items);
  }
  snprintf(app->status, sizeof(app->status), "%zu items", app->item_count);
}

static void scan_music_dir(struct app_state *app, const char *root, int depth) {
  DIR *dir;
  struct dirent *de;
  struct stat st;
  char path[PATH_MAX];

  if (depth > 3 || app->item_count >= APP_MAX_ITEMS) {
    return;
  }
  dir = opendir(root);
  if (!dir) {
    return;
  }
  while ((de = readdir(dir)) && app->item_count < APP_MAX_ITEMS) {
    if (strcmp(de->d_name, ".") == 0 || strcmp(de->d_name, "..") == 0) {
      continue;
    }
    if (!join_path(path, sizeof(path), root, de->d_name)) {
      continue;
    }
    if (stat(path, &st) != 0) {
      continue;
    }
    if (S_ISDIR(st.st_mode)) {
      scan_music_dir(app, path, depth + 1);
    } else if (S_ISREG(st.st_mode) && has_audio_ext(de->d_name)) {
      add_item(app, de->d_name, path, is_wav_ext(de->d_name) ? "WAV" : "unsupported",
               0, is_wav_ext(de->d_name));
    }
  }
  closedir(dir);
}

static void load_music_items(struct app_state *app) {
  char root[PATH_MAX];
  static const char *roots[] = {
      "music", "MUSIC", "roms/music", "roms/MUSIC",
  };
  static const char *sd2_roots[] = {
      "/run/plumos/sd2/music", "/run/plumos/sd2/MUSIC",
      "/run/plumos/sd2/roms/music", "/run/plumos/sd2/roms/MUSIC",
  };
  size_t i;

  app->item_count = 0;
  app->cursor = 0;
  app->scroll = 0;
  for (i = 0; i < sizeof(roots) / sizeof(roots[0]); i++) {
    if (join_path(root, sizeof(root), app->plumos_root, roots[i])) {
      scan_music_dir(app, root, 0);
    }
  }
  for (i = 0; i < sizeof(sd2_roots) / sizeof(sd2_roots[0]); i++) {
    scan_music_dir(app, sd2_roots[i], 0);
  }
  if (app->item_count > 1) {
    qsort(app->items, app->item_count, sizeof(app->items[0]), cmp_items);
  }
  snprintf(app->status, sizeof(app->status), "%zu tracks", app->item_count);
}

static int discover_named_input_event(char *out, size_t out_size, const char *name) {
  FILE *f;
  char line[512];
  int in_target = 0;

  f = fopen("/proc/bus/input/devices", "rb");
  if (!f) {
    return 0;
  }
  while (fgets(line, sizeof(line), f)) {
    if (line[0] == '\n') {
      in_target = 0;
      continue;
    }
    if (strstr(line, "Name=\"") && strstr(line, name)) {
      in_target = 1;
      continue;
    }
    if (in_target && strstr(line, "Handlers=")) {
      char *event = strstr(line, "event");
      char dev[64];
      size_t i = 0;
      if (!event) {
        continue;
      }
      while (event[i] && !isspace((unsigned char)event[i]) && i + 1 < sizeof(dev)) {
        dev[i] = event[i];
        i++;
      }
      dev[i] = '\0';
      fclose(f);
      return join_path(out, out_size, "/dev/input", dev);
    }
  }
  fclose(f);
  return 0;
}

static int discover_input_event(char *out, size_t out_size) {
  static const char *names[] = {
      "adc_gamepad", "adc gamepad", "sunxi-keyboard", "soc:gpio_keys", "gpio-keys",
  };
  size_t i;
  const char *env = getenv("PLUMOS_INPUT_EVENT");
  if (env && env[0]) {
    return copy_string(out, out_size, env);
  }
  for (i = 0; i < sizeof(names) / sizeof(names[0]); i++) {
    if (discover_named_input_event(out, out_size, names[i])) {
      return 1;
    }
  }
  return copy_string(out, out_size, "/dev/input/event0");
}

static enum app_action action_from_key(unsigned int code) {
  switch (code) {
  case KEY_UP:
  case BTN_DPAD_UP:
    return ACTION_UP;
  case KEY_DOWN:
  case BTN_DPAD_DOWN:
    return ACTION_DOWN;
  case KEY_LEFT:
  case BTN_DPAD_LEFT:
    return ACTION_LEFT;
  case KEY_RIGHT:
  case BTN_DPAD_RIGHT:
    return ACTION_RIGHT;
  case KEY_SPACE:
  case KEY_Z:
  case BTN_SOUTH:
  case 7:
    return ACTION_A;
  case KEY_LEFTCTRL:
  case BTN_EAST:
  case 9:
    return ACTION_B;
  case KEY_ENTER:
  case KEY_MENU:
  case KEY_HOME:
  case BTN_START:
  case BTN_MODE:
  case 10:
    return ACTION_START;
  case KEY_RIGHTCTRL:
  case KEY_SELECT:
  case BTN_SELECT:
    return ACTION_SELECT;
  case KEY_Q:
  case KEY_ESC:
    return ACTION_QUIT;
  default:
    return ACTION_NONE;
  }
}

static enum app_action action_from_stdin(int ch) {
  switch (ch) {
  case 'w':
  case 'W':
    return ACTION_UP;
  case 's':
  case 'S':
    return ACTION_DOWN;
  case 'a':
  case 'A':
    return ACTION_LEFT;
  case 'd':
  case 'D':
    return ACTION_RIGHT;
  case 'e':
  case 'E':
  case ' ':
  case '\n':
    return ACTION_A;
  case 'b':
  case 'B':
    return ACTION_B;
  case 'm':
  case 'M':
    return ACTION_START;
  case 'q':
  case 'Q':
    return ACTION_QUIT;
  default:
    return ACTION_NONE;
  }
}

static enum app_action poll_action(struct app_state *app) {
  struct pollfd pfds[2];
  int nfds = 0;
  int rc;

  if (app->input_fd >= 0) {
    pfds[nfds].fd = app->input_fd;
    pfds[nfds].events = POLLIN;
    pfds[nfds].revents = 0;
    nfds++;
  }
  pfds[nfds].fd = STDIN_FILENO;
  pfds[nfds].events = POLLIN;
  pfds[nfds].revents = 0;
  nfds++;
  rc = poll(pfds, nfds, 100);
  if (rc <= 0) {
    return ACTION_NONE;
  }
  if (app->input_fd >= 0 && (pfds[0].revents & POLLIN)) {
    struct input_event ev;
    while (read(app->input_fd, &ev, sizeof(ev)) == (ssize_t)sizeof(ev)) {
      if (ev.type == EV_KEY && ev.value == 1) {
        enum app_action action = action_from_key(ev.code);
        if (action != ACTION_NONE) {
          return action;
        }
      } else if (ev.type == EV_ABS) {
        if ((ev.code == ABS_X || ev.code == ABS_HAT0X) && ev.value < 0) {
          return ACTION_LEFT;
        }
        if ((ev.code == ABS_X || ev.code == ABS_HAT0X) && ev.value > 0) {
          return ACTION_RIGHT;
        }
        if ((ev.code == ABS_Y || ev.code == ABS_HAT0Y) && ev.value < 0) {
          return ACTION_UP;
        }
        if ((ev.code == ABS_Y || ev.code == ABS_HAT0Y) && ev.value > 0) {
          return ACTION_DOWN;
        }
      }
    }
  }
  if (pfds[nfds - 1].revents & POLLIN) {
    int ch = getchar();
    if (ch != EOF) {
      return action_from_stdin(ch);
    }
  }
  return ACTION_NONE;
}

static uint32_t rgb(struct app_state *app, uint8_t r, uint8_t g, uint8_t b) {
  return plumos_fbdev_pack_color(&app->fb, r, g, b);
}

static void draw_text(struct app_state *app, int x, int y, const char *text, int scale,
                      uint32_t color, int max_x) {
#ifdef PLUMOS_FBDEV_ENABLE_FREETYPE
  plumos_fbdev_draw_text_font(&app->fb, x, y, text, scale, 1, color, max_x);
#else
  plumos_fbdev_draw_text(&app->fb, x, y, text, scale, color, max_x);
#endif
}

static void draw_app(struct app_state *app) {
  int w = (int)app->fb.var.xres;
  int h = (int)app->fb.var.yres;
  uint32_t bg = rgb(app, 5, 10, 13);
  uint32_t panel = rgb(app, 20, 32, 36);
  uint32_t line = rgb(app, 45, 73, 78);
  uint32_t text = rgb(app, 213, 241, 238);
  uint32_t muted = rgb(app, 142, 187, 184);
  uint32_t accent = app->mode == APP_FILE_MANAGER ? rgb(app, 255, 143, 10)
                                                   : rgb(app, 93, 190, 255);
  const char *title = app->mode == APP_FILE_MANAGER ? "PLUMOS FILE MANAGER"
                                                     : "PLUMOS MUSIC PLAYER";
  const char *footer = app->mode == APP_FILE_MANAGER
                           ? "A OPEN   B BACK/EXIT   START EXIT"
                           : "A PLAY WAV   SELECT REFRESH   B/START EXIT";
  size_t i;

  plumos_fbdev_fill_rect(&app->fb, 0, 0, w, h, bg);
  plumos_fbdev_fill_rect(&app->fb, 0, 0, w, 40, panel);
  plumos_fbdev_fill_rect(&app->fb, 0, 39, w, 2, line);
  plumos_fbdev_fill_rect(&app->fb, 0, 0, 5, h, accent);
  draw_text(app, 14, 12, title, 2, text, w - 8);
  draw_text(app, 14, 52, app->mode == APP_FILE_MANAGER ? app->cwd : "Music roots: /mnt/plumos/music, SD2 music",
            2, muted, w - 8);

  if (app->item_count == 0) {
    draw_text(app, 36, 150,
              app->mode == APP_FILE_MANAGER ? "No files" : "No supported music files",
              3, muted, w - 36);
  }

  if (app->cursor < app->scroll) {
    app->scroll = app->cursor;
  }
  if (app->cursor >= app->scroll + APP_ROWS) {
    app->scroll = app->cursor - APP_ROWS + 1;
  }

  for (i = 0; i < APP_ROWS && app->scroll + i < app->item_count; i++) {
    size_t idx = app->scroll + i;
    int y = 88 + (int)i * 32;
    struct app_item *item = &app->items[idx];
    if (idx == app->cursor) {
      plumos_fbdev_fill_rect(&app->fb, 12, y - 7, w - 24, 29, accent);
      draw_text(app, 24, y, ">", 2, bg, w - 8);
      draw_text(app, 54, y, item->name, 2, bg, w - 150);
      draw_text(app, w - 132, y, item->is_dir ? "DIR" : item->detail, 2, bg, w - 8);
    } else {
      draw_text(app, 24, y, item->is_dir ? "+" : " ", 2, muted, w - 8);
      draw_text(app, 54, y, item->name, 2, text, w - 150);
      draw_text(app, w - 132, y, item->is_dir ? "DIR" : item->detail, 2, muted, w - 8);
    }
  }

  plumos_fbdev_fill_rect(&app->fb, 0, h - 74, w, 74, panel);
  plumos_fbdev_fill_rect(&app->fb, 0, h - 76, w, 2, line);
  draw_text(app, 14, h - 56, footer, 2, muted, w - 8);
  draw_text(app, 14, h - 34, app->status, 2, text, w - 8);
  msync(app->fb.mem, app->fb.map_size, MS_ASYNC);
  plumos_fbdev_present(&app->fb);
}

static void stop_player(struct app_state *app) {
  if (app->player_pid > 0) {
    kill(app->player_pid, SIGTERM);
    waitpid(app->player_pid, NULL, 0);
    app->player_pid = 0;
  }
}

static void play_selected(struct app_state *app) {
  const char *device = getenv("PLUMOS_MUSIC_PLAYER_AUDIO_DEVICE");
  struct app_item *item;
  pid_t pid;

  if (app->item_count == 0 || app->cursor >= app->item_count) {
    return;
  }
  item = &app->items[app->cursor];
  if (!item->playable) {
    snprintf(app->status, sizeof(app->status), "WAV playback only for now: %s",
             item->name);
    return;
  }
  stop_player(app);
  pid = fork();
  if (pid == 0) {
    int fd = open("/dev/null", O_RDONLY);
    if (fd >= 0) {
      dup2(fd, STDIN_FILENO);
      close(fd);
    }
    execlp("aplay", "aplay", "-D", device && device[0] ? device : "hw:0,0",
           item->path, (char *)NULL);
    _exit(127);
  }
  if (pid < 0) {
    snprintf(app->status, sizeof(app->status), "play failed: %s", strerror(errno));
    return;
  }
  app->player_pid = pid;
  snprintf(app->status, sizeof(app->status), "playing %s", item->name);
}

static void handle_action(struct app_state *app, enum app_action action) {
  struct app_item *item;
  if (action == ACTION_NONE) {
    return;
  }
  if (action == ACTION_QUIT || action == ACTION_START) {
    g_exit_requested = 1;
    return;
  }
  if (action == ACTION_UP) {
    if (app->cursor > 0) {
      app->cursor--;
    }
    return;
  }
  if (action == ACTION_DOWN) {
    if (app->cursor + 1 < app->item_count) {
      app->cursor++;
    }
    return;
  }
  if (action == ACTION_SELECT && app->mode == APP_MUSIC_PLAYER) {
    load_music_items(app);
    return;
  }
  if (app->mode == APP_FILE_MANAGER) {
    if (action == ACTION_B) {
      if (!path_parent(app->cwd)) {
        g_exit_requested = 1;
      } else {
        load_file_items(app);
      }
      return;
    }
    if (action == ACTION_A && app->item_count > 0 && app->cursor < app->item_count) {
      item = &app->items[app->cursor];
      if (strcmp(item->name, "..") == 0) {
        path_parent(app->cwd);
        load_file_items(app);
      } else if (item->is_dir) {
        copy_string(app->cwd, sizeof(app->cwd), item->path);
        load_file_items(app);
      } else {
        snprintf(app->status, sizeof(app->status), "%s", item->detail);
      }
    }
  } else {
    if (action == ACTION_B) {
      g_exit_requested = 1;
      return;
    }
    if (action == ACTION_A) {
      play_selected(app);
    }
  }
}

static long long env_ms(const char *name) {
  const char *value = getenv(name);
  char *end = NULL;
  long long parsed;
  if (!value || !value[0]) {
    return 0;
  }
  errno = 0;
  parsed = strtoll(value, &end, 10);
  if (errno || end == value || parsed < 0) {
    return 0;
  }
  return parsed;
}

static void init_stdio(void) {
  int flags = fcntl(STDIN_FILENO, F_GETFL, 0);
  if (flags >= 0) {
    fcntl(STDIN_FILENO, F_SETFL, flags | O_NONBLOCK);
  }
}

static int init_app(struct app_state *app, int argc, char **argv) {
  char error[256];
  char input_path[PATH_MAX];
  const char *root;
  const char *fb;
  const char *font;
  const char *fallback_font;
  const char *name = argv && argv[0] ? base_name(argv[0]) : "";

  memset(app, 0, sizeof(*app));
  app->input_fd = -1;
  app->player_pid = 0;
  app->mode = strstr(name, "music") ? APP_MUSIC_PLAYER : APP_FILE_MANAGER;
  root = getenv("PLUMOS_ROOT");
  copy_string(app->plumos_root, sizeof(app->plumos_root),
              root && root[0] ? root : "/mnt/plumos");
  if (app->mode == APP_FILE_MANAGER) {
    const char *start = argc > 1 && argv[1] && argv[1][0] ? argv[1] : app->plumos_root;
    copy_string(app->cwd, sizeof(app->cwd), start);
  }
  app->exit_after_ms = env_ms("PLUMOS_APP_EXIT_AFTER_MS");
  app->start_ms = now_ms();

  fb = getenv("PLUMOS_FB");
  error[0] = '\0';
  if (!plumos_fbdev_renderer_init(&app->fb, fb && fb[0] ? fb : "/dev/fb0",
                                  error, sizeof(error))) {
    fprintf(stderr, "fbdev init failed: %s\n", error);
    return 0;
  }
  app->renderer_ready = 1;
  plumos_fbdev_renderer_set_rotation(&app->fb, getenv("PLUMOS_FBDEV_ROTATION"));
  plumos_fbdev_renderer_reset_marquee(&app->fb);
#ifdef PLUMOS_FBDEV_ENABLE_FREETYPE
  font = getenv("PLUMOS_MALI_FONT");
  fallback_font = getenv("PLUMOS_MALI_FALLBACK_FONT");
  if (!font || !font[0]) {
    static char default_font[PATH_MAX];
    join_path(default_font, sizeof(default_font), app->plumos_root, "fonts/default.otf");
    font = default_font;
  }
  if (!fallback_font || !fallback_font[0]) {
    static char default_fallback[PATH_MAX];
    join_path(default_fallback, sizeof(default_fallback), app->plumos_root,
              "fonts/cjk-fallback.ttc");
    fallback_font = default_fallback;
  }
  error[0] = '\0';
  plumos_fbdev_renderer_load_font(&app->fb, font, error, sizeof(error));
  error[0] = '\0';
  plumos_fbdev_renderer_load_fallback_font(&app->fb, fallback_font, error,
                                           sizeof(error));
#endif
  if (discover_input_event(input_path, sizeof(input_path))) {
    app->input_fd = open(input_path, O_RDONLY | O_NONBLOCK);
  }
  init_stdio();
  if (app->mode == APP_FILE_MANAGER) {
    load_file_items(app);
  } else {
    load_music_items(app);
  }
  return 1;
}

static void shutdown_app(struct app_state *app) {
  stop_player(app);
  if (app->input_fd >= 0) {
    close(app->input_fd);
    app->input_fd = -1;
  }
  if (app->renderer_ready) {
    plumos_fbdev_renderer_shutdown(&app->fb);
    app->renderer_ready = 0;
  }
}

int main(int argc, char **argv) {
  struct app_state app;

  signal(SIGINT, on_signal);
  signal(SIGTERM, on_signal);
  if (!init_app(&app, argc, argv)) {
    return 1;
  }
  while (!g_exit_requested) {
    enum app_action action;
    draw_app(&app);
    if (app.exit_after_ms > 0 && now_ms() - app.start_ms >= app.exit_after_ms) {
      break;
    }
    action = poll_action(&app);
    handle_action(&app, action);
  }
  shutdown_app(&app);
  return 0;
}
