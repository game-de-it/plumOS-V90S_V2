#ifndef PLUMOS_FBDEV_RENDERER_H
#define PLUMOS_FBDEV_RENDERER_H

#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <linux/fb.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

#ifdef PLUMOS_FBDEV_ENABLE_PNG
#include <png.h>
#endif

#ifndef PLUMOS_FBDEV_RENDER_LINE_MAX
#define PLUMOS_FBDEV_RENDER_LINE_MAX 512
#endif

#ifndef PLUMOS_FBDEV_SETTING_FLASH_MARKER
#define PLUMOS_FBDEV_SETTING_FLASH_MARKER "@{F:"
#endif

#ifndef PLUMOS_FBDEV_RENDERER_GLYPHS_ONLY
struct plumos_fbdev_renderer {
  int fd;
  unsigned char *mem;
  size_t map_size;
  int bytes_per_pixel;
  int rotation_180;
  long active_offset;
  long visible_offset;
  long frame_bytes;
  uint32_t visible_yoffset;
  uint32_t draw_yoffset;
  int double_buffer;
  struct fb_var_screeninfo var;
  struct fb_fix_screeninfo fix;
};

static uint32_t plumos_fbdev_scale_channel(uint8_t value, uint32_t length,
                                           uint32_t offset) {
  uint32_t max_value;
  if (length == 0) {
    return 0;
  }
  if (length >= 8) {
    return ((uint32_t)value) << offset;
  }
  max_value = (1U << length) - 1U;
  return (((uint32_t)value * max_value + 127U) / 255U) << offset;
}

static uint32_t plumos_fbdev_pack_color(const struct plumos_fbdev_renderer *r,
                                        uint8_t red, uint8_t green, uint8_t blue) {
  uint32_t color = 0;
  color |= plumos_fbdev_scale_channel(red, r->var.red.length, r->var.red.offset);
  color |= plumos_fbdev_scale_channel(green, r->var.green.length, r->var.green.offset);
  color |= plumos_fbdev_scale_channel(blue, r->var.blue.length, r->var.blue.offset);
  if (r->var.transp.length) {
    color |= plumos_fbdev_scale_channel(255, r->var.transp.length, r->var.transp.offset);
  }
  return color;
}

static void plumos_fbdev_put_pixel(struct plumos_fbdev_renderer *r, int x, int y,
                                   uint32_t color) {
  long offset;
  unsigned char *p;

  if (!r || !r->mem || x < 0 || y < 0 || x >= (int)r->var.xres ||
      y >= (int)r->var.yres) {
    return;
  }
  if (r->rotation_180) {
    x = (int)r->var.xres - 1 - x;
    y = (int)r->var.yres - 1 - y;
  }
  offset = r->active_offset + (long)y * (long)r->fix.line_length +
           (long)x * (long)r->bytes_per_pixel;
  if (offset < 0 || offset + r->bytes_per_pixel > (long)r->map_size) {
    return;
  }
  p = r->mem + offset;
  if (r->bytes_per_pixel == 4) {
    p[0] = (unsigned char)(color & 0xffU);
    p[1] = (unsigned char)((color >> 8) & 0xffU);
    p[2] = (unsigned char)((color >> 16) & 0xffU);
    p[3] = (unsigned char)((color >> 24) & 0xffU);
  } else if (r->bytes_per_pixel == 3) {
    p[0] = (unsigned char)(color & 0xffU);
    p[1] = (unsigned char)((color >> 8) & 0xffU);
    p[2] = (unsigned char)((color >> 16) & 0xffU);
  } else if (r->bytes_per_pixel == 2) {
    p[0] = (unsigned char)(color & 0xffU);
    p[1] = (unsigned char)((color >> 8) & 0xffU);
  }
}

static void plumos_fbdev_fill_rect(struct plumos_fbdev_renderer *r, int x, int y,
                                   int w, int h, uint32_t color) {
  int yy;
  int xx;
  if (w <= 0 || h <= 0) {
    return;
  }
  for (yy = y; yy < y + h; yy++) {
    for (xx = x; xx < x + w; xx++) {
      plumos_fbdev_put_pixel(r, xx, yy, color);
    }
  }
}

static int plumos_fbdev_frame_offset_valid(const struct plumos_fbdev_renderer *r,
                                           long offset) {
  return r && offset >= 0 && r->frame_bytes > 0 &&
         offset + r->frame_bytes <= (long)r->map_size;
}

static long plumos_fbdev_yoffset_to_offset(const struct plumos_fbdev_renderer *r,
                                           uint32_t yoffset) {
  if (!r) {
    return -1;
  }
  return (long)yoffset * (long)r->fix.line_length;
}

static void plumos_fbdev_wait_vsync(struct plumos_fbdev_renderer *r) {
#ifdef FBIO_WAITFORVSYNC
  int arg = 0;

  if (r && r->fd >= 0) {
    (void)ioctl(r->fd, FBIO_WAITFORVSYNC, &arg);
  }
#else
  (void)r;
#endif
}

static int plumos_fbdev_present(struct plumos_fbdev_renderer *r) {
  struct fb_var_screeninfo next_var;
  uint32_t next_draw_yoffset;
  long next_draw_offset;

  if (!r || !r->mem) {
    return 0;
  }
  if (!r->double_buffer) {
    return 1;
  }

  next_var = r->var;
  next_var.xoffset = 0;
  next_var.yoffset = r->draw_yoffset;
#ifdef FB_ACTIVATE_VBL
  next_var.activate = FB_ACTIVATE_VBL;
#endif

  plumos_fbdev_wait_vsync(r);
  if (ioctl(r->fd, FBIOPAN_DISPLAY, &next_var) != 0) {
    if (plumos_fbdev_frame_offset_valid(r, r->visible_offset) &&
        r->visible_offset != r->active_offset) {
      memcpy(r->mem + r->visible_offset, r->mem + r->active_offset,
             (size_t)r->frame_bytes);
      r->active_offset = r->visible_offset;
    }
    r->double_buffer = 0;
    return 0;
  }

  r->var = next_var;
  r->visible_yoffset = r->draw_yoffset;
  r->visible_offset = r->active_offset;
  next_draw_yoffset = r->visible_yoffset == 0 ? r->var.yres : 0;
  next_draw_offset = plumos_fbdev_yoffset_to_offset(r, next_draw_yoffset);
  if (!plumos_fbdev_frame_offset_valid(r, next_draw_offset) ||
      next_draw_yoffset + r->var.yres > r->var.yres_virtual) {
    r->double_buffer = 0;
    r->active_offset = r->visible_offset;
    r->draw_yoffset = r->visible_yoffset;
    return 1;
  }
  r->draw_yoffset = next_draw_yoffset;
  r->active_offset = next_draw_offset;
  return 1;
}

#ifdef PLUMOS_FBDEV_ENABLE_PNG
static int plumos_fbdev_path_has_png_ext(const char *path) {
  const char *ext;

  if (!path || !path[0]) {
    return 0;
  }
  ext = strrchr(path, '.');
  return ext && strlen(ext) == 4 && tolower((unsigned char)ext[1]) == 'p' &&
         tolower((unsigned char)ext[2]) == 'n' &&
         tolower((unsigned char)ext[3]) == 'g' && ext[4] == '\0';
}

#if defined(__GNUC__)
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wclobbered"
#endif
static int plumos_fbdev_load_png_rgba(const char *path,
                                      unsigned char **pixels_out,
                                      int *width_out, int *height_out) {
  FILE *f;
  png_structp png = NULL;
  png_infop info = NULL;
  png_bytep *rows = NULL;
  png_bytep pixels = NULL;
  png_uint_32 width;
  png_uint_32 height;
  int bit_depth;
  int color_type;
  int interlace_type;
  size_t row_bytes;
  png_uint_32 y;
  int ok = 0;

  if (!path || !pixels_out || !width_out || !height_out ||
      !plumos_fbdev_path_has_png_ext(path)) {
    return 0;
  }
  *pixels_out = NULL;
  *width_out = 0;
  *height_out = 0;
  f = fopen(path, "rb");
  if (!f) {
    return 0;
  }
  png = png_create_read_struct(PNG_LIBPNG_VER_STRING, NULL, NULL, NULL);
  if (!png) {
    fclose(f);
    return 0;
  }
  info = png_create_info_struct(png);
  if (!info) {
    png_destroy_read_struct(&png, NULL, NULL);
    fclose(f);
    return 0;
  }
  if (setjmp(png_jmpbuf(png))) {
    goto done;
  }
  png_init_io(png, f);
  png_read_info(png, info);
  png_get_IHDR(png, info, &width, &height, &bit_depth, &color_type,
               &interlace_type, NULL, NULL);
  if (width == 0 || height == 0 || width > 2048 || height > 2048) {
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
  if (color_type == PNG_COLOR_TYPE_GRAY ||
      color_type == PNG_COLOR_TYPE_GRAY_ALPHA) {
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
  *pixels_out = pixels;
  *width_out = (int)width;
  *height_out = (int)height;
  pixels = NULL;
  ok = 1;

done:
  free(rows);
  free(pixels);
  png_destroy_read_struct(&png, &info, NULL);
  fclose(f);
  return ok;
}
#if defined(__GNUC__)
#pragma GCC diagnostic pop
#endif

static int plumos_fbdev_draw_png_contain(struct plumos_fbdev_renderer *r,
                                         const char *path, int x, int y,
                                         int box_w, int box_h) {
  unsigned char *pixels = NULL;
  int image_w = 0;
  int image_h = 0;
  int draw_w;
  int draw_h;
  int draw_x;
  int draw_y;
  int dx;
  int dy;

  if (!r || !path || !path[0] || box_w <= 0 || box_h <= 0 ||
      !plumos_fbdev_load_png_rgba(path, &pixels, &image_w, &image_h) ||
      image_w <= 0 || image_h <= 0) {
    free(pixels);
    return 0;
  }

  draw_w = box_w;
  draw_h = (int)((long)image_h * (long)box_w / (long)image_w);
  if (draw_h > box_h) {
    draw_h = box_h;
    draw_w = (int)((long)image_w * (long)box_h / (long)image_h);
  }
  if (draw_w <= 0 || draw_h <= 0) {
    free(pixels);
    return 0;
  }
  draw_x = x + (box_w - draw_w) / 2;
  draw_y = y + (box_h - draw_h) / 2;

  for (dy = 0; dy < draw_h; dy++) {
    int sy = (int)((long)dy * (long)image_h / (long)draw_h);
    if (sy >= image_h) {
      sy = image_h - 1;
    }
    for (dx = 0; dx < draw_w; dx++) {
      int sx = (int)((long)dx * (long)image_w / (long)draw_w);
      const unsigned char *rgba;
      if (sx >= image_w) {
        sx = image_w - 1;
      }
      rgba = pixels + ((size_t)sy * (size_t)image_w + (size_t)sx) * 4U;
      if (rgba[3] < 128) {
        continue;
      }
      plumos_fbdev_put_pixel(r, draw_x + dx, draw_y + dy,
                             plumos_fbdev_pack_color(r, rgba[0], rgba[1], rgba[2]));
    }
  }

  free(pixels);
  return 1;
}
#endif

#endif

static const uint8_t *plumos_fbdev_glyph_for(char c) {
  static const uint8_t blank[7] = {0, 0, 0, 0, 0, 0, 0};
  static const uint8_t box[7] = {31, 17, 21, 17, 21, 17, 31};
  static const uint8_t glyph_0[7] = {14, 17, 19, 21, 25, 17, 14};
  static const uint8_t glyph_1[7] = {4, 12, 4, 4, 4, 4, 14};
  static const uint8_t glyph_2[7] = {14, 17, 1, 2, 4, 8, 31};
  static const uint8_t glyph_3[7] = {30, 1, 1, 14, 1, 1, 30};
  static const uint8_t glyph_4[7] = {2, 6, 10, 18, 31, 2, 2};
  static const uint8_t glyph_5[7] = {31, 16, 30, 1, 1, 17, 14};
  static const uint8_t glyph_6[7] = {6, 8, 16, 30, 17, 17, 14};
  static const uint8_t glyph_7[7] = {31, 1, 2, 4, 8, 8, 8};
  static const uint8_t glyph_8[7] = {14, 17, 17, 14, 17, 17, 14};
  static const uint8_t glyph_9[7] = {14, 17, 17, 15, 1, 2, 12};
  static const uint8_t glyph_a[7] = {14, 17, 17, 31, 17, 17, 17};
  static const uint8_t glyph_b[7] = {30, 17, 17, 30, 17, 17, 30};
  static const uint8_t glyph_c[7] = {14, 17, 16, 16, 16, 17, 14};
  static const uint8_t glyph_d[7] = {30, 17, 17, 17, 17, 17, 30};
  static const uint8_t glyph_e[7] = {31, 16, 16, 30, 16, 16, 31};
  static const uint8_t glyph_f[7] = {31, 16, 16, 30, 16, 16, 16};
  static const uint8_t glyph_g[7] = {14, 17, 16, 23, 17, 17, 15};
  static const uint8_t glyph_h[7] = {17, 17, 17, 31, 17, 17, 17};
  static const uint8_t glyph_i[7] = {14, 4, 4, 4, 4, 4, 14};
  static const uint8_t glyph_j[7] = {1, 1, 1, 1, 17, 17, 14};
  static const uint8_t glyph_k[7] = {17, 18, 20, 24, 20, 18, 17};
  static const uint8_t glyph_l[7] = {16, 16, 16, 16, 16, 16, 31};
  static const uint8_t glyph_m[7] = {17, 27, 21, 21, 17, 17, 17};
  static const uint8_t glyph_n[7] = {17, 25, 21, 19, 17, 17, 17};
  static const uint8_t glyph_o[7] = {14, 17, 17, 17, 17, 17, 14};
  static const uint8_t glyph_p[7] = {30, 17, 17, 30, 16, 16, 16};
  static const uint8_t glyph_q[7] = {14, 17, 17, 17, 21, 18, 13};
  static const uint8_t glyph_r[7] = {30, 17, 17, 30, 20, 18, 17};
  static const uint8_t glyph_s[7] = {15, 16, 16, 14, 1, 1, 30};
  static const uint8_t glyph_t[7] = {31, 4, 4, 4, 4, 4, 4};
  static const uint8_t glyph_u[7] = {17, 17, 17, 17, 17, 17, 14};
  static const uint8_t glyph_v[7] = {17, 17, 17, 17, 17, 10, 4};
  static const uint8_t glyph_w[7] = {17, 17, 17, 21, 21, 21, 10};
  static const uint8_t glyph_x[7] = {17, 17, 10, 4, 10, 17, 17};
  static const uint8_t glyph_y[7] = {17, 17, 10, 4, 4, 4, 4};
  static const uint8_t glyph_z[7] = {31, 1, 2, 4, 8, 16, 31};
  static const uint8_t dash[7] = {0, 0, 0, 31, 0, 0, 0};
  static const uint8_t colon[7] = {0, 4, 4, 0, 4, 4, 0};
  static const uint8_t slash[7] = {1, 1, 2, 4, 8, 16, 16};
  static const uint8_t dot[7] = {0, 0, 0, 0, 0, 12, 12};
  static const uint8_t comma[7] = {0, 0, 0, 0, 0, 4, 8};
  static const uint8_t at[7] = {14, 17, 23, 21, 23, 16, 14};
  static const uint8_t hash[7] = {10, 31, 10, 10, 31, 10, 0};
  static const uint8_t percent[7] = {17, 2, 4, 8, 17, 0, 0};
  static const uint8_t tilde[7] = {0, 0, 8, 21, 2, 0, 0};
  static const uint8_t eq[7] = {0, 0, 31, 0, 31, 0, 0};
  static const uint8_t gt[7] = {16, 8, 4, 2, 4, 8, 16};
  static const uint8_t lt[7] = {1, 2, 4, 8, 4, 2, 1};
  static const uint8_t under[7] = {0, 0, 0, 0, 0, 0, 31};
  static const uint8_t pipe[7] = {4, 4, 4, 4, 4, 4, 4};
  static const uint8_t plus[7] = {0, 4, 4, 31, 4, 4, 0};
  static const uint8_t star[7] = {0, 21, 14, 31, 14, 21, 0};
  static const uint8_t bang[7] = {4, 4, 4, 4, 4, 0, 4};
  static const uint8_t quest[7] = {14, 17, 1, 2, 4, 0, 4};
  static const uint8_t lpar[7] = {2, 4, 8, 8, 8, 4, 2};
  static const uint8_t rpar[7] = {8, 4, 2, 2, 2, 4, 8};
  static const uint8_t lbr[7] = {14, 8, 8, 8, 8, 8, 14};
  static const uint8_t rbr[7] = {14, 2, 2, 2, 2, 2, 14};

  if (c >= 'a' && c <= 'z') {
    c = (char)(c - 'a' + 'A');
  }
  switch (c) {
  case ' ': return blank;
  case '0': return glyph_0;
  case '1': return glyph_1;
  case '2': return glyph_2;
  case '3': return glyph_3;
  case '4': return glyph_4;
  case '5': return glyph_5;
  case '6': return glyph_6;
  case '7': return glyph_7;
  case '8': return glyph_8;
  case '9': return glyph_9;
  case 'A': return glyph_a;
  case 'B': return glyph_b;
  case 'C': return glyph_c;
  case 'D': return glyph_d;
  case 'E': return glyph_e;
  case 'F': return glyph_f;
  case 'G': return glyph_g;
  case 'H': return glyph_h;
  case 'I': return glyph_i;
  case 'J': return glyph_j;
  case 'K': return glyph_k;
  case 'L': return glyph_l;
  case 'M': return glyph_m;
  case 'N': return glyph_n;
  case 'O': return glyph_o;
  case 'P': return glyph_p;
  case 'Q': return glyph_q;
  case 'R': return glyph_r;
  case 'S': return glyph_s;
  case 'T': return glyph_t;
  case 'U': return glyph_u;
  case 'V': return glyph_v;
  case 'W': return glyph_w;
  case 'X': return glyph_x;
  case 'Y': return glyph_y;
  case 'Z': return glyph_z;
  case '-': return dash;
  case ':': return colon;
  case '/':
  case '\\': return slash;
  case '.': return dot;
  case ',': return comma;
  case '@': return at;
  case '#': return hash;
  case '%': return percent;
  case '~': return tilde;
  case '=': return eq;
  case '>': return gt;
  case '<': return lt;
  case '_': return under;
  case '|': return pipe;
  case '+': return plus;
  case '*': return star;
  case '!': return bang;
  case '?': return quest;
  case '(':
  case '{': return lpar;
  case ')':
  case '}': return rpar;
  case '[': return lbr;
  case ']': return rbr;
  default: return box;
  }
}

#ifndef PLUMOS_FBDEV_RENDERER_GLYPHS_ONLY
static void plumos_fbdev_draw_char(struct plumos_fbdev_renderer *r, int x, int y,
                                   char c, int scale, uint32_t color) {
  const uint8_t *g = plumos_fbdev_glyph_for(c);
  int row;
  int col;
  for (row = 0; row < 7; row++) {
    for (col = 0; col < 5; col++) {
      if (g[row] & (1U << (4 - col))) {
        plumos_fbdev_fill_rect(r, x + col * scale, y + row * scale, scale, scale,
                               color);
      }
    }
  }
}

static void plumos_fbdev_draw_text(struct plumos_fbdev_renderer *r, int x, int y,
                                   const char *text, int scale, uint32_t color,
                                   int max_width) {
  int pen = x;
  int advance = 6 * scale;
  const char *p;

  for (p = text; p && *p && pen + advance <= max_width; p++) {
    plumos_fbdev_draw_char(r, pen, y, *p, scale, color);
    pen += advance;
  }
}

struct plumos_fbdev_palette {
  uint32_t background;
  uint32_t foreground;
  uint32_t muted;
  uint32_t accent;
  uint32_t panel;
  uint32_t panel_inner;
  uint32_t media_panel;
  uint32_t selection_background;
  uint32_t selection_foreground;
  uint32_t danger;
  uint32_t line;
};

struct plumos_fbdev_entry {
  int selected;
  char title[160];
  char detail[224];
  char media[224];
};

struct plumos_fbdev_motion {
  char top_layout[32];
};

static const char *plumos_fbdev_ltrim(const char *s) {
  while (s && *s && isspace((unsigned char)*s)) {
    s++;
  }
  return s ? s : "";
}

static void plumos_fbdev_trim_right(char *s) {
  size_t len;
  if (!s) {
    return;
  }
  len = strlen(s);
  while (len > 0 && isspace((unsigned char)s[len - 1])) {
    s[--len] = '\0';
  }
}

static int plumos_fbdev_text_width(const char *text, int scale) {
  int width = 0;
  const char *p;
  if (scale <= 0) {
    scale = 1;
  }
  for (p = text; p && *p; p++) {
    width += 6 * scale;
  }
  return width;
}

static void plumos_fbdev_copy_range(char *out, size_t out_size,
                                    const char *start, const char *end) {
  size_t len;
  if (!out || out_size == 0) {
    return;
  }
  out[0] = '\0';
  if (!start) {
    return;
  }
  if (!end) {
    end = start + strlen(start);
  }
  while (start < end && isspace((unsigned char)*start)) {
    start++;
  }
  while (end > start && isspace((unsigned char)*(end - 1))) {
    end--;
  }
  len = (size_t)(end - start);
  if (len >= out_size) {
    len = out_size - 1;
  }
  memcpy(out, start, len);
  out[len] = '\0';
}

static void plumos_fbdev_copy_text(char *out, size_t out_size, const char *text) {
  plumos_fbdev_copy_range(out, out_size, text, text ? text + strlen(text) : NULL);
}

static int plumos_fbdev_split_setting_control(const char *in, char *label,
                                              size_t label_size, char *control,
                                              size_t control_size) {
  const char *choice;
  char *marker;

  if (!in || !label || label_size == 0 || !control || control_size == 0) {
    return 0;
  }
  label[0] = '\0';
  control[0] = '\0';

  if ((strncmp(in, "[x] ", 4) == 0 || strncmp(in, "[ ] ", 4) == 0) && in[4]) {
    plumos_fbdev_copy_range(control, control_size, in, in + 3);
    plumos_fbdev_copy_text(label, label_size, in + 4);
    return label[0] != '\0' && control[0] != '\0';
  }

  choice = strstr(in, " < ");
  if (!choice || !strstr(choice + 1, " >")) {
    return 0;
  }
  plumos_fbdev_copy_range(label, label_size, in, choice);
  plumos_fbdev_copy_text(control, control_size, choice + 1);
  marker = strstr(control, PLUMOS_FBDEV_SETTING_FLASH_MARKER);
  if (marker) {
    *marker = '\0';
  }
  plumos_fbdev_trim_right(control);
  return label[0] != '\0' && control[0] != '\0';
}

static int plumos_fbdev_hex_digit(char c) {
  if (c >= '0' && c <= '9') {
    return c - '0';
  }
  if (c >= 'a' && c <= 'f') {
    return c - 'a' + 10;
  }
  if (c >= 'A' && c <= 'F') {
    return c - 'A' + 10;
  }
  return -1;
}

static int plumos_fbdev_parse_hex_rgb(const char *value,
                                      uint8_t *red, uint8_t *green,
                                      uint8_t *blue) {
  int digits[6];
  int i;

  if (!value || value[0] != '#') {
    return 0;
  }
  for (i = 0; i < 6; i++) {
    digits[i] = plumos_fbdev_hex_digit(value[i + 1]);
    if (digits[i] < 0) {
      return 0;
    }
  }
  if (value[7] != '\0' && !isspace((unsigned char)value[7])) {
    return 0;
  }
  *red = (uint8_t)((digits[0] << 4) | digits[1]);
  *green = (uint8_t)((digits[2] << 4) | digits[3]);
  *blue = (uint8_t)((digits[4] << 4) | digits[5]);
  return 1;
}

static uint32_t plumos_fbdev_color_from_hex(struct plumos_fbdev_renderer *r,
                                            const char *value, uint32_t fallback) {
  uint8_t red;
  uint8_t green;
  uint8_t blue;

  if (!plumos_fbdev_parse_hex_rgb(value, &red, &green, &blue)) {
    return fallback;
  }
  return plumos_fbdev_pack_color(r, red, green, blue);
}

static void plumos_fbdev_palette_init(struct plumos_fbdev_renderer *r,
                                      struct plumos_fbdev_palette *p) {
  p->background = plumos_fbdev_pack_color(r, 5, 8, 10);
  p->foreground = plumos_fbdev_pack_color(r, 232, 242, 238);
  p->muted = plumos_fbdev_pack_color(r, 137, 160, 166);
  p->accent = plumos_fbdev_pack_color(r, 255, 132, 13);
  p->panel = plumos_fbdev_pack_color(r, 22, 31, 34);
  p->panel_inner = plumos_fbdev_pack_color(r, 7, 12, 13);
  p->media_panel = plumos_fbdev_pack_color(r, 25, 38, 42);
  p->selection_background = plumos_fbdev_pack_color(r, 35, 58, 51);
  p->selection_foreground = plumos_fbdev_pack_color(r, 255, 230, 122);
  p->danger = plumos_fbdev_pack_color(r, 255, 50, 36);
  p->line = plumos_fbdev_pack_color(r, 67, 88, 91);
}

static void plumos_fbdev_palette_apply(struct plumos_fbdev_renderer *r,
                                       struct plumos_fbdev_palette *p,
                                       const char *key, const char *value) {
  if (!key || !value) {
    return;
  }
  if (strcmp(key, "background") == 0) {
    p->background = plumos_fbdev_color_from_hex(r, value, p->background);
  } else if (strcmp(key, "foreground") == 0) {
    p->foreground = plumos_fbdev_color_from_hex(r, value, p->foreground);
  } else if (strcmp(key, "muted") == 0) {
    p->muted = plumos_fbdev_color_from_hex(r, value, p->muted);
  } else if (strcmp(key, "accent") == 0) {
    p->accent = plumos_fbdev_color_from_hex(r, value, p->accent);
  } else if (strcmp(key, "panel") == 0) {
    p->panel = plumos_fbdev_color_from_hex(r, value, p->panel);
  } else if (strcmp(key, "panel_inner") == 0) {
    p->panel_inner = plumos_fbdev_color_from_hex(r, value, p->panel_inner);
  } else if (strcmp(key, "media_panel") == 0) {
    p->media_panel = plumos_fbdev_color_from_hex(r, value, p->media_panel);
  } else if (strcmp(key, "selection_background") == 0) {
    p->selection_background =
        plumos_fbdev_color_from_hex(r, value, p->selection_background);
  } else if (strcmp(key, "selection_foreground") == 0) {
    p->selection_foreground =
        plumos_fbdev_color_from_hex(r, value, p->selection_foreground);
  } else if (strcmp(key, "danger") == 0) {
    p->danger = plumos_fbdev_color_from_hex(r, value, p->danger);
  }
}

static void plumos_fbdev_load_palette(struct plumos_fbdev_renderer *r,
                                      struct plumos_fbdev_palette *p,
                                      char lines[][PLUMOS_FBDEV_RENDER_LINE_MAX],
                                      size_t line_count) {
  size_t i;

  plumos_fbdev_palette_init(r, p);
  for (i = 0; i < line_count; i++) {
    const char *line = plumos_fbdev_ltrim(lines[i]);
    const char *key;
    const char *value;
    const char *tab;
    char key_buf[64];
    char value_buf[64];

    if (strncmp(line, "graphic_theme_color\t", 20) != 0) {
      continue;
    }
    key = line + 20;
    tab = strchr(key, '\t');
    if (!tab) {
      continue;
    }
    value = tab + 1;
    plumos_fbdev_copy_range(key_buf, sizeof(key_buf), key, tab);
    plumos_fbdev_copy_text(value_buf, sizeof(value_buf), value);
    plumos_fbdev_palette_apply(r, p, key_buf, value_buf);
  }
}

static void plumos_fbdev_load_motion(struct plumos_fbdev_motion *motion,
                                     char lines[][PLUMOS_FBDEV_RENDER_LINE_MAX],
                                     size_t line_count) {
  size_t i;

  if (!motion) {
    return;
  }
  memset(motion, 0, sizeof(*motion));
  plumos_fbdev_copy_text(motion->top_layout, sizeof(motion->top_layout),
                         "tile_grid");
  for (i = 0; i < line_count; i++) {
    const char *line = plumos_fbdev_ltrim(lines[i]);
    const char *key;
    const char *value;
    const char *tab;
    char key_buf[64];
    char value_buf[64];

    if (strncmp(line, "graphic_theme_motion\t", 21) != 0) {
      continue;
    }
    key = line + 21;
    tab = strchr(key, '\t');
    if (!tab) {
      continue;
    }
    value = tab + 1;
    plumos_fbdev_copy_range(key_buf, sizeof(key_buf), key, tab);
    plumos_fbdev_copy_text(value_buf, sizeof(value_buf), value);
    if (strcmp(key_buf, "top_layout") == 0 &&
        (strcmp(value_buf, "tile_grid") == 0 ||
         strcmp(value_buf, "tile_strip") == 0)) {
      plumos_fbdev_copy_text(motion->top_layout, sizeof(motion->top_layout),
                             value_buf);
    }
  }
}

static void plumos_fbdev_draw_text_center(struct plumos_fbdev_renderer *r, int x,
                                          int y, int w, const char *text,
                                          int scale, uint32_t color) {
  int width = plumos_fbdev_text_width(text, scale);
  int draw_x = x + (w - width) / 2;
  if (draw_x < x) {
    draw_x = x;
  }
  plumos_fbdev_draw_text(r, draw_x, y, text, scale, color, x + w);
}

static void plumos_fbdev_time_label(char *out, size_t out_size) {
  time_t now;
  struct tm tm_now;

  if (!out || out_size == 0) {
    return;
  }
  now = time(NULL);
  if (now == (time_t)-1 || !localtime_r(&now, &tm_now)) {
    plumos_fbdev_copy_text(out, out_size, "--:--");
    return;
  }
  snprintf(out, out_size, "%02d:%02d", tm_now.tm_hour, tm_now.tm_min);
}

static int plumos_fbdev_read_first_line(const char *path, char *out,
                                        size_t out_size);

static void plumos_fbdev_wifi_label(char *out, size_t out_size) {
  FILE *f;
  char line[256];
  char value[32];
  int linked = 0;

  if (!out || out_size == 0) {
    return;
  }
  if (plumos_fbdev_read_first_line("/sys/class/net/wlan0/carrier", value,
                                   sizeof(value)) &&
      strcmp(value, "1") == 0) {
    linked = 1;
  }
  if (!linked &&
      plumos_fbdev_read_first_line("/sys/class/net/wlan0/operstate", value,
                                   sizeof(value)) &&
      strcmp(value, "up") == 0) {
    linked = 1;
  }
  f = fopen("/proc/net/wireless", "r");
  if (f) {
    while (fgets(line, sizeof(line), f)) {
      unsigned int status = 0;
      float quality = 0.0f;
      if (sscanf(line, " wlan0: %x %f", &status, &quality) == 2 &&
          quality > 0.0f) {
        linked = 1;
        break;
      }
    }
    fclose(f);
  }
  plumos_fbdev_copy_text(out, out_size, linked ? "WIFI" : "NO WIFI");
}

static int plumos_fbdev_read_first_line(const char *path, char *out,
                                        size_t out_size) {
  FILE *f;
  char *newline;

  if (!path || !out || out_size == 0) {
    return 0;
  }
  out[0] = '\0';
  f = fopen(path, "r");
  if (!f) {
    return 0;
  }
  if (!fgets(out, (int)out_size, f)) {
    fclose(f);
    out[0] = '\0';
    return 0;
  }
  fclose(f);
  newline = strchr(out, '\n');
  if (newline) {
    *newline = '\0';
  }
  return out[0] != '\0';
}

static void plumos_fbdev_battery_label(char *out, size_t out_size) {
  char capacity[32];
  char status[32];
  const char *prefix = "BAT";

  if (!out || out_size == 0) {
    return;
  }
  if (!plumos_fbdev_read_first_line("/sys/class/power_supply/battery/capacity",
                                    capacity, sizeof(capacity))) {
    plumos_fbdev_copy_text(out, out_size, "BAT --");
    return;
  }
  if (plumos_fbdev_read_first_line("/sys/class/power_supply/battery/status",
                                   status, sizeof(status)) &&
      (strcmp(status, "Charging") == 0 || strcmp(status, "Full") == 0)) {
    prefix = "CHG";
  }
  snprintf(out, out_size, "%s %.3s", prefix, capacity);
}

static void plumos_fbdev_draw_graphic_top_bar(
    struct plumos_fbdev_renderer *r, const struct plumos_fbdev_palette *p,
    const char *title) {
  char time_label[16];
  char wifi_label[16];
  char battery_label[24];
  char right[80];
  int w = (int)r->var.xres;
  int right_width;
  int title_max_x;

  plumos_fbdev_time_label(time_label, sizeof(time_label));
  plumos_fbdev_wifi_label(wifi_label, sizeof(wifi_label));
  plumos_fbdev_battery_label(battery_label, sizeof(battery_label));
  snprintf(right, sizeof(right), "%s  %s  %s", time_label, wifi_label,
           battery_label);
  right_width = plumos_fbdev_text_width(right, 2);
  title_max_x = w - 28 - right_width;
  if (title_max_x < 96) {
    title_max_x = w - 16;
  }

  plumos_fbdev_fill_rect(r, 0, 0, w, (int)r->var.yres, p->background);
  plumos_fbdev_fill_rect(r, 0, 0, w, 40, p->panel_inner);
  plumos_fbdev_fill_rect(r, 0, 40, w, 2, p->panel);
  plumos_fbdev_fill_rect(r, 0, 0, 5, (int)r->var.yres, p->accent);
  plumos_fbdev_draw_text(r, 16, 12,
                         title && title[0] ? title : "PLUMOS V90S GUI", 2,
                         p->foreground, title_max_x);
  plumos_fbdev_draw_text(r, w - 14 - right_width, 12, right, 2, p->muted,
                         w - 12);
}

static void plumos_fbdev_draw_tty_top_bar(struct plumos_fbdev_renderer *r) {
  char time_label[16];
  char wifi_label[16];
  char battery_label[24];
  char right[80];
  int w = (int)r->var.xres;
  int right_width;
  uint32_t bg = plumos_fbdev_pack_color(r, 0, 5, 4);
  uint32_t border = plumos_fbdev_pack_color(r, 31, 82, 56);
  uint32_t prompt = plumos_fbdev_pack_color(r, 158, 255, 199);
  uint32_t muted = plumos_fbdev_pack_color(r, 179, 235, 219);

  plumos_fbdev_time_label(time_label, sizeof(time_label));
  plumos_fbdev_wifi_label(wifi_label, sizeof(wifi_label));
  plumos_fbdev_battery_label(battery_label, sizeof(battery_label));
  snprintf(right, sizeof(right), "%s  %s  %s", time_label, wifi_label,
           battery_label);
  right_width = plumos_fbdev_text_width(right, 2);

  plumos_fbdev_fill_rect(r, 0, 0, w, 34, bg);
  plumos_fbdev_fill_rect(r, 0, 34, w, 2, border);
  plumos_fbdev_draw_text(r, 14, 10, "PLUMOS V90S TTY1", 2, prompt, w - 8);
  plumos_fbdev_draw_text(r, w - 14 - right_width, 10, right, 2, muted, w - 8);
}

static const char *plumos_fbdev_find_value(
    char lines[][PLUMOS_FBDEV_RENDER_LINE_MAX], size_t line_count,
    const char *prefix) {
  size_t i;
  size_t prefix_len = strlen(prefix);

  for (i = 0; i < line_count; i++) {
    const char *line = plumos_fbdev_ltrim(lines[i]);
    if (strncmp(line, prefix, prefix_len) == 0) {
      return line + prefix_len;
    }
  }
  return NULL;
}

static void plumos_fbdev_screen_title(char *out, size_t out_size,
                                      char lines[][PLUMOS_FBDEV_RENDER_LINE_MAX],
                                      size_t line_count) {
  const char *line;
  const char *title;

  if (!out || out_size == 0) {
    return;
  }
  out[0] = '\0';
  if (line_count == 0) {
    plumos_fbdev_copy_text(out, out_size, "plumOS");
    return;
  }
  line = plumos_fbdev_ltrim(lines[0]);
  title = strstr(line, " - ");
  if (title) {
    title += 3;
  } else {
    title = line;
  }
  plumos_fbdev_copy_text(out, out_size, title);
  if (!out[0]) {
    plumos_fbdev_copy_text(out, out_size, "plumOS");
  }
}

static int plumos_fbdev_title_is_settings_family(const char *title) {
  return title && (strstr(title, "START") || strstr(title, "Apps") ||
                   strstr(title, "APPS") || strstr(title, "Settings") ||
                   strstr(title, "SETTINGS") || strstr(title, "HELP") ||
                   strstr(title, "Thumbnail Results") ||
                   strstr(title, "Scraping") ||
                   strstr(title, "Network") || strstr(title, "NETWORK"));
}

static int plumos_fbdev_has_prefixed_line(
    char lines[][PLUMOS_FBDEV_RENDER_LINE_MAX], size_t line_count,
    const char *prefix) {
  size_t i;
  size_t prefix_len = prefix ? strlen(prefix) : 0;

  if (!prefix || prefix_len == 0) {
    return 0;
  }
  for (i = 0; i < line_count; i++) {
    const char *line = plumos_fbdev_ltrim(lines[i]);
    if (strncmp(line, prefix, prefix_len) == 0) {
      return 1;
    }
  }
  return 0;
}

static int plumos_fbdev_entry_head(const char *line, int *selected,
                                   char *number, size_t number_size,
                                   const char **rest) {
  const char *p = line;
  size_t n = 0;

  if (selected) {
    *selected = 0;
  }
  if (number && number_size > 0) {
    number[0] = '\0';
  }
  if (rest) {
    *rest = "";
  }
  if (!line || !rest) {
    return 0;
  }
  if (*p == '>') {
    if (selected) {
      *selected = 1;
    }
    p++;
  }
  while (*p == ' ') {
    p++;
  }
  while (isdigit((unsigned char)*p) && number && n + 1 < number_size) {
    number[n++] = *p++;
  }
  if (number && number_size > 0) {
    number[n] = '\0';
  }
  while (isdigit((unsigned char)*p)) {
    p++;
  }
  while (*p == ' ') {
    p++;
  }
  *rest = p;
  return number && number[0] && *p;
}

static void plumos_fbdev_compact_menu_entry(const char *line, char *out,
                                            size_t out_size, int *selected) {
  char number[16];
  const char *rest;

  if (!out || out_size == 0) {
    return;
  }
  out[0] = '\0';
  if (!plumos_fbdev_entry_head(line, selected, number, sizeof(number), &rest)) {
    plumos_fbdev_copy_text(out, out_size, line);
    return;
  }
  plumos_fbdev_copy_text(out, out_size, rest);
}

static int plumos_fbdev_parse_graphic_entry(const char *line, const char *prefix,
                                            struct plumos_fbdev_entry *entry) {
  const char *p;
  const char *next;
  size_t prefix_len;

  if (!line || !prefix || !entry) {
    return 0;
  }
  prefix_len = strlen(prefix);
  if (strncmp(line, prefix, prefix_len) != 0 || line[prefix_len] != '\t') {
    return 0;
  }
  memset(entry, 0, sizeof(*entry));
  p = line + prefix_len + 1;
  entry->selected = (*p == '1');
  next = strchr(p, '\t');
  if (!next) {
    return 0;
  }
  p = next + 1;
  next = strchr(p, '\t');
  plumos_fbdev_copy_range(entry->title, sizeof(entry->title), p, next);
  if (next) {
    p = next + 1;
    next = strchr(p, '\t');
    plumos_fbdev_copy_range(entry->detail, sizeof(entry->detail), p, next);
  }
  if (next) {
    p = next + 1;
    next = strchr(p, '\t');
    plumos_fbdev_copy_range(entry->media, sizeof(entry->media), p, next);
  }
  if (!entry->title[0]) {
    plumos_fbdev_copy_text(entry->title, sizeof(entry->title), "Untitled");
  }
  return 1;
}

static size_t plumos_fbdev_collect_graphic_entries(
    char lines[][PLUMOS_FBDEV_RENDER_LINE_MAX], size_t line_count,
    struct plumos_fbdev_entry *entries, size_t max_entries) {
  size_t i;
  size_t count = 0;

  if (!entries || max_entries == 0) {
    return 0;
  }
  for (i = 0; i < line_count && count < max_entries; i++) {
    const char *line = plumos_fbdev_ltrim(lines[i]);
    if (plumos_fbdev_parse_graphic_entry(line, "graphic_entry", &entries[count])) {
      count++;
    }
  }
  return count;
}

static const struct plumos_fbdev_entry *plumos_fbdev_selected_entry(
    const struct plumos_fbdev_entry *entries, size_t count) {
  size_t i;
  for (i = 0; i < count; i++) {
    if (entries[i].selected) {
      return &entries[i];
    }
  }
  return count ? &entries[0] : NULL;
}

static void plumos_fbdev_draw_status(struct plumos_fbdev_renderer *r,
                                     const struct plumos_fbdev_palette *p,
                                     char lines[][PLUMOS_FBDEV_RENDER_LINE_MAX],
                                     size_t line_count) {
  const char *status = plumos_fbdev_find_value(lines, line_count, "status:");
  char status_buf[180];
  int w = (int)r->var.xres;
  int h = (int)r->var.yres;

  if (!status) {
    return;
  }
  plumos_fbdev_copy_text(status_buf, sizeof(status_buf), status);
  if (status_buf[0]) {
    plumos_fbdev_draw_text(r, 24, h - 22, status_buf, 2, p->muted, w - 24);
  }
}

static int plumos_fbdev_render_top_refresh_running(
    struct plumos_fbdev_renderer *r,
    const struct plumos_fbdev_palette *p) {
  const char *line1 = "REFRESH TOP";
  const char *line2 = "PLEASE WAIT";
  const char *line3 = "SCANNING SYSTEMS";
  const char *line4 = "RELOADING TOP LIST";
  int w = (int)r->var.xres;
  int h = (int)r->var.yres;
  int y1 = h / 2 - 112;
  int y2 = y1 + 64;
  int y3 = y2 + 76;
  int y4 = y3 + 34;
  uint32_t blue = plumos_fbdev_pack_color(r, 56, 148, 255);
  uint32_t yellow = plumos_fbdev_pack_color(r, 255, 219, 71);
  uint32_t text_color = plumos_fbdev_pack_color(r, 198, 240, 230);

  plumos_fbdev_fill_rect(r, 0, 0, w, h, p->background);
  plumos_fbdev_draw_tty_top_bar(r);
  plumos_fbdev_fill_rect(r, 0, 0, 7, h, blue);
  plumos_fbdev_draw_text_center(r, 0, y1, w, line1, 4, blue);
  plumos_fbdev_draw_text_center(r, 0, y2, w, line2, 4, yellow);
  plumos_fbdev_draw_text_center(r, 0, y3, w, line3, 2, text_color);
  plumos_fbdev_draw_text_center(r, 0, y4, w, line4, 2, text_color);
  return 1;
}

static void plumos_fbdev_entry_badge(char *out, size_t out_size,
                                     const char *title) {
  size_t pos = 0;
  const char *p;

  if (!out || out_size == 0) {
    return;
  }
  out[0] = '\0';
  if (!title || !title[0]) {
    plumos_fbdev_copy_text(out, out_size, "OS");
    return;
  }
  if (title[0] == '*') {
    plumos_fbdev_copy_text(out, out_size, "*");
    return;
  }
  if (strcasecmp(title, "favorites") == 0) {
    plumos_fbdev_copy_text(out, out_size, "FAV");
    return;
  }
  if (strcasecmp(title, "recent") == 0) {
    plumos_fbdev_copy_text(out, out_size, "REC");
    return;
  }
  for (p = title; *p && pos + 1 < out_size && pos < 3; p++) {
    if (isalnum((unsigned char)*p)) {
      out[pos++] = (char)toupper((unsigned char)*p);
    }
  }
  out[pos] = '\0';
  if (!out[0]) {
    plumos_fbdev_copy_text(out, out_size, "OS");
  }
}

static void plumos_fbdev_graphic_top_layout_metrics(
    struct plumos_fbdev_renderer *r, const struct plumos_fbdev_motion *motion,
    int *columns_out, int *rows_out, int *grid_x_out, int *grid_y_out,
    int *tile_size_out, int *gap_out) {
  int strip = motion && strcmp(motion->top_layout, "tile_strip") == 0;
  int columns = strip ? 2 : 3;
  int rows = strip ? 1 : 2;
  int horizontal_margin = strip ? 32 : 22;
  int grid_y = strip ? 116 : 70;
  int bottom_margin = strip ? 42 : 18;
  int gap = strip ? 16 : 10;
  int width_limited;
  int height_limited;
  int tile_size;
  int grid_width;
  int grid_x;

  width_limited = ((int)r->var.xres - horizontal_margin * 2 -
                   gap * (columns - 1)) /
                  columns;
  height_limited = ((int)r->var.yres - grid_y - bottom_margin -
                    gap * (rows - 1)) /
                   rows;
  tile_size = width_limited < height_limited ? width_limited : height_limited;
  if (strip && tile_size > 260) {
    tile_size = 260;
  }
  if (tile_size < 72) {
    tile_size = 72;
  }
  grid_width = tile_size * columns + gap * (columns - 1);
  grid_x = ((int)r->var.xres - grid_width) / 2;
  if (grid_x < 8) {
    grid_x = 8;
  }
  if (columns_out) {
    *columns_out = columns;
  }
  if (rows_out) {
    *rows_out = rows;
  }
  if (grid_x_out) {
    *grid_x_out = grid_x;
  }
  if (grid_y_out) {
    *grid_y_out = grid_y;
  }
  if (tile_size_out) {
    *tile_size_out = tile_size;
  }
  if (gap_out) {
    *gap_out = gap;
  }
}

static void plumos_fbdev_draw_top_tile(struct plumos_fbdev_renderer *r,
                                       const struct plumos_fbdev_palette *p,
                                       const struct plumos_fbdev_entry *entry,
                                       int x, int y, int w, int h) {
  uint32_t fill = entry->selected ? p->selection_background : p->panel_inner;
  uint32_t outline = entry->selected ? p->accent : p->panel;
  uint32_t title_color = entry->selected ? p->selection_foreground : p->foreground;
  int media_x = x + 14;
  int media_y = y + 14;
  int title_y = y + h - 58;
  int detail_y = y + h - 30;
  int media_w = w - 28;
  int media_h = title_y - media_y - 10;
  int title_scale = 2;
  int logo_drawn = 0;
  char badge[8];

  plumos_fbdev_entry_badge(badge, sizeof(badge), entry->title);
  if (media_h < 24) {
    media_h = 24;
  }
  plumos_fbdev_fill_rect(r, x, y, w, h, outline);
  plumos_fbdev_fill_rect(r, x + (entry->selected ? 4 : 2),
                         y + (entry->selected ? 4 : 2),
                         w - (entry->selected ? 8 : 4),
                         h - (entry->selected ? 8 : 4), fill);
  plumos_fbdev_fill_rect(r, media_x, media_y, media_w, media_h,
                         entry->selected ? p->selection_background
                                         : p->media_panel);
#ifdef PLUMOS_FBDEV_ENABLE_PNG
  if (entry->media[0]) {
    logo_drawn = plumos_fbdev_draw_png_contain(r, entry->media, media_x + 4,
                                               media_y + 4, media_w - 8,
                                               media_h - 8);
  }
#endif
  if (!logo_drawn) {
    plumos_fbdev_draw_text_center(
        r, media_x, media_y + (media_h - 28) / 2, media_w, badge, 4,
        entry->selected ? p->selection_foreground : p->foreground);
  }
  plumos_fbdev_draw_text(r, x + 12, title_y, entry->title, title_scale,
                         title_color, x + w - 12);
  if (entry->detail[0]) {
    plumos_fbdev_draw_text(r, x + 12, detail_y, entry->detail, 2, p->muted,
                           x + w - 12);
  }
}

static int plumos_fbdev_render_top(struct plumos_fbdev_renderer *r,
                                   char lines[][PLUMOS_FBDEV_RENDER_LINE_MAX],
                                   size_t line_count,
                                   const struct plumos_fbdev_palette *p) {
  struct plumos_fbdev_entry entries[12];
  struct plumos_fbdev_motion motion;
  size_t count;
  size_t i;
  int cols;
  int rows;
  int grid_x;
  int grid_y;
  int tile_size;
  int gap;

  count = plumos_fbdev_collect_graphic_entries(lines, line_count, entries,
                                               sizeof(entries) / sizeof(entries[0]));
  if (count == 0) {
    memset(&entries[0], 0, sizeof(entries[0]));
    entries[0].selected = 1;
    plumos_fbdev_copy_text(entries[0].title, sizeof(entries[0].title), "No Systems");
    count = 1;
  }
  plumos_fbdev_load_motion(&motion, lines, line_count);
  plumos_fbdev_graphic_top_layout_metrics(r, &motion, &cols, &rows, &grid_x,
                                          &grid_y, &tile_size, &gap);

  plumos_fbdev_draw_graphic_top_bar(r, p, "PLUMOS V90S GUI");

  for (i = 0; i < count && i < 6; i++) {
    int col = (int)i % cols;
    int row = (int)i / cols;
    int x = grid_x + col * (tile_size + gap);
    int y = grid_y + row * (tile_size + gap);
    if (row >= rows) {
      break;
    }
    plumos_fbdev_draw_top_tile(r, p, &entries[i], x, y, tile_size, tile_size);
  }
  plumos_fbdev_draw_status(r, p, lines, line_count);
  return 1;
}

static void plumos_fbdev_draw_rom_preview(struct plumos_fbdev_renderer *r,
                                          const struct plumos_fbdev_palette *p,
                                          const struct plumos_fbdev_entry *entry,
                                          int x, int y, int w, int h) {
  int media_x = x + 16;
  int media_y = y + 18;
  int media_w = w - 32;
  int media_h = 156;
  int thumbnail_drawn = 0;
  char badge[8];

  plumos_fbdev_fill_rect(r, x, y, w, h, p->panel);
  plumos_fbdev_fill_rect(r, x + 3, y + 3, w - 6, h - 6, p->panel_inner);
  plumos_fbdev_fill_rect(r, media_x, media_y, media_w, media_h,
                         p->media_panel);
  if (entry && entry->media[0]) {
#ifdef PLUMOS_FBDEV_ENABLE_PNG
    thumbnail_drawn =
        plumos_fbdev_draw_png_contain(r, entry->media, media_x, media_y,
                                      media_w, media_h);
#endif
  }
  if (entry) {
    if (!thumbnail_drawn) {
      plumos_fbdev_entry_badge(badge, sizeof(badge), entry->title);
      plumos_fbdev_draw_text_center(r, media_x, media_y + 58, media_w, badge, 4,
                                    p->foreground);
    }
    plumos_fbdev_draw_text(r, x + 16, y + 200, entry->title, 2, p->foreground,
                           x + w - 16);
    if (entry->detail[0]) {
      plumos_fbdev_draw_text(r, x + 16, y + 232, entry->detail, 2, p->muted,
                             x + w - 16);
    }
  } else {
    plumos_fbdev_draw_text_center(r, media_x, media_y + 58, media_w, "NO ART",
                                  3, p->muted);
  }
}

static int plumos_fbdev_render_roms(struct plumos_fbdev_renderer *r,
                                    char lines[][PLUMOS_FBDEV_RENDER_LINE_MAX],
                                    size_t line_count,
                                    const struct plumos_fbdev_palette *p) {
  struct plumos_fbdev_entry entries[14];
  const struct plumos_fbdev_entry *selected;
  const char *system_value;
  char title[160];
  size_t count;
  size_t i;
  int w = (int)r->var.xres;
  int h = (int)r->var.yres;
  int list_x = 18;
  int list_y = 70;
  int list_w = w > 680 ? 360 : w / 2 - 28;
  int row_h = 38;
  int preview_x = list_x + list_w + 16;
  int preview_y = 72;
  int preview_w = w - preview_x - 16;
  int preview_h = h - preview_y - 16;

  if (list_w < 190) {
    list_w = 190;
  }
  if (preview_w < 160) {
    preview_w = 160;
  }

  system_value = plumos_fbdev_find_value(lines, line_count, "graphic_system=");
  if (system_value && system_value[0]) {
    plumos_fbdev_copy_text(title, sizeof(title), system_value);
  } else {
    plumos_fbdev_screen_title(title, sizeof(title), lines, line_count);
  }

  count = plumos_fbdev_collect_graphic_entries(lines, line_count, entries,
                                               sizeof(entries) / sizeof(entries[0]));
  if (count == 0) {
    memset(&entries[0], 0, sizeof(entries[0]));
    entries[0].selected = 1;
    plumos_fbdev_copy_text(entries[0].title, sizeof(entries[0].title), "No Entries");
    count = 1;
  }
  selected = plumos_fbdev_selected_entry(entries, count);

  plumos_fbdev_draw_graphic_top_bar(r, p, title);

  for (i = 0; i < count; i++) {
    int y = list_y + (int)i * row_h;
    int name_x = list_x + 24;
    int name_right_x = list_x + list_w - 10;
    uint32_t fg = entries[i].selected ? p->selection_foreground : p->foreground;
    if (y + row_h > h - 20) {
      break;
    }
    if (entries[i].selected) {
      plumos_fbdev_fill_rect(r, list_x - 6, y - 7, list_w, row_h - 4,
                             p->selection_background);
    }
    plumos_fbdev_draw_text(r, list_x, y + 3, entries[i].selected ? ">" : " ",
                           2, fg, name_right_x);
    plumos_fbdev_draw_text(r, name_x, y, entries[i].title, 2, fg,
                           name_right_x);
  }

  plumos_fbdev_draw_rom_preview(r, p, selected, preview_x, preview_y,
                                preview_w, preview_h);
  return 1;
}

static int plumos_fbdev_is_hidden_line(const char *line) {
  if (!line || !line[0]) {
    return 1;
  }
  if (strncmp(line, "graphic_", 8) == 0 ||
      strncmp(line, "entries=", 8) == 0 ||
      strncmp(line, "system=", 7) == 0 ||
      strncmp(line, "target=", 7) == 0 ||
      strncmp(line, "profile=", 8) == 0 ||
      strncmp(line, "source:", 7) == 0 ||
      strncmp(line, "menu_screen=", 12) == 0 ||
      strncmp(line, "settings_screen=", 16) == 0 ||
      strncmp(line, "scraping_screen=", 16) == 0 ||
      strncmp(line, "thumbnail_results_screen=", 25) == 0 ||
      strncmp(line, "thumbnail_running", 17) == 0 ||
      strncmp(line, "top_refresh_running=", 20) == 0 ||
      strncmp(line, "usb_disk_starting=", 18) == 0 ||
      strncmp(line, "brightness_test=", 16) == 0 ||
      strncmp(line, "wifi_keyboard_cursor=", 21) == 0 ||
      strncmp(line, "wifi_password=", 14) == 0 ||
      strncmp(line, "prompt_path=", 12) == 0 ||
      strncmp(line, "footer", 6) == 0 ||
      strncmp(line, "status:", 7) == 0) {
    return 1;
  }
  if (strstr(line, "A:") || strstr(line, "LEFT/RIGHT:") || strstr(line, "Q: quit")) {
    return 1;
  }
  return 0;
}

static int plumos_fbdev_render_generic(struct plumos_fbdev_renderer *r,
                                       char lines[][PLUMOS_FBDEV_RENDER_LINE_MAX],
                                       size_t line_count,
                                       const struct plumos_fbdev_palette *p) {
  char title[128];
  char items[18][160];
  int selected[18];
  size_t item_count = 0;
  size_t i;
  int w = (int)r->var.xres;
  int h = (int)r->var.yres;
  int settings_family;
  int settings_page;
  int entry_scale;
  int line_height;
  int cursor_x;
  int name_x;
  int right_x;
  int cell_width;
  int y;
  uint32_t accent;
  const char *footer1;
  const char *footer2;

  memset(selected, 0, sizeof(selected));
  plumos_fbdev_screen_title(title, sizeof(title), lines, line_count);
  settings_page = plumos_fbdev_has_prefixed_line(lines, line_count,
                                                 "settings_screen=1");
  settings_family = plumos_fbdev_title_is_settings_family(title) ||
                    plumos_fbdev_has_prefixed_line(lines, line_count,
                                                   "menu_screen=1") ||
                    settings_page;
  entry_scale = 2;
  line_height = entry_scale * 12;
  cursor_x = settings_family ? 12 : 18;
  name_x = cursor_x + (settings_family ? 18 : 24);
  right_x = w - 14;
  cell_width = 6 * entry_scale;
  accent = settings_family ? plumos_fbdev_pack_color(r, 56, 148, 255)
                           : p->accent;
  footer1 = plumos_fbdev_find_value(lines, line_count, "footer1=");
  footer2 = plumos_fbdev_find_value(lines, line_count, "footer2=");

  for (i = 1; i < line_count && item_count < 18; i++) {
    const char *line = plumos_fbdev_ltrim(lines[i]);
    int is_selected = 0;
    if (plumos_fbdev_is_hidden_line(line)) {
      continue;
    }
    plumos_fbdev_compact_menu_entry(line, items[item_count],
                                    sizeof(items[item_count]), &is_selected);
    selected[item_count] = is_selected;
    item_count++;
  }
  if (item_count == 0) {
    plumos_fbdev_copy_text(items[0], sizeof(items[0]), "Ready");
    selected[0] = 1;
    item_count = 1;
  }

  plumos_fbdev_fill_rect(r, 0, 0, w, h, p->background);
  plumos_fbdev_draw_tty_top_bar(r);
  plumos_fbdev_fill_rect(r, 0, 0, 5, h, accent);
  plumos_fbdev_draw_text(r, 14, 48, title, 2, p->muted, w - 8);
  y = settings_family ? 82 : 104;

  for (i = 0; i < item_count; i++) {
    uint32_t fg = selected[i] ? p->selection_foreground : p->foreground;
    if (y > h - 34) {
      break;
    }
    if (selected[i]) {
      plumos_fbdev_fill_rect(r, 10, y - 7, w - 20,
                             entry_scale * 7 + 10,
                             p->selection_background);
    }
    plumos_fbdev_draw_text(r, cursor_x, y, selected[i] ? ">" : " ",
                           entry_scale, fg, w - 8);
    if (settings_page) {
      char setting_label[160];
      char setting_control[80];
      int control_width;
      int control_x;

      if (plumos_fbdev_split_setting_control(items[i], setting_label,
                                             sizeof(setting_label),
                                             setting_control,
                                             sizeof(setting_control))) {
        control_width = plumos_fbdev_text_width(setting_control, entry_scale);
        control_x = right_x - control_width;
        if (control_x < name_x + 6 * cell_width) {
          control_x = name_x + 6 * cell_width;
        }
        plumos_fbdev_draw_text(r, name_x, y, setting_label, entry_scale, fg,
                               control_x - cell_width);
        plumos_fbdev_draw_text(r, control_x, y, setting_control, entry_scale, fg,
                               right_x);
      } else {
        plumos_fbdev_draw_text(r, name_x, y, items[i], entry_scale, fg, w - 8);
      }
    } else {
      plumos_fbdev_draw_text(r, name_x, y, items[i], entry_scale, fg, w - 8);
    }
    y += line_height;
  }
  if ((footer1 && footer1[0]) || (footer2 && footer2[0])) {
    plumos_fbdev_fill_rect(r, 0, h - 74, w, 74, p->panel_inner);
    plumos_fbdev_fill_rect(r, 0, h - 76, w, 2, p->panel);
    if (footer1 && footer1[0]) {
      plumos_fbdev_draw_text(r, 14, h - 56, footer1, 2, p->muted, w - 8);
    }
    if (footer2 && footer2[0]) {
      plumos_fbdev_draw_text(r, 14, h - 34, footer2, 2, p->muted, w - 8);
    }
  }
  return 1;
}

static int plumos_fbdev_renderer_init(struct plumos_fbdev_renderer *r,
                                      const char *fb_path, char *error,
                                      size_t error_size) {
  long map_size;
  long visible_offset;
  long draw_offset;
  const char *double_buffer_env;
  const char *path = fb_path && fb_path[0] ? fb_path : "/dev/fb0";

  if (!r) {
    return 0;
  }
  memset(r, 0, sizeof(*r));
  r->fd = -1;
  r->fd = open(path, O_RDWR);
  if (r->fd < 0) {
    snprintf(error, error_size, "open %.180s: %.60s", path, strerror(errno));
    return 0;
  }
  if (ioctl(r->fd, FBIOGET_VSCREENINFO, &r->var) != 0 ||
      ioctl(r->fd, FBIOGET_FSCREENINFO, &r->fix) != 0) {
    snprintf(error, error_size, "framebuffer ioctl: %s", strerror(errno));
    close(r->fd);
    r->fd = -1;
    return 0;
  }
  r->bytes_per_pixel = (int)((r->var.bits_per_pixel + 7U) / 8U);
  if (!(r->bytes_per_pixel == 2 || r->bytes_per_pixel == 3 ||
        r->bytes_per_pixel == 4) ||
      r->fix.line_length == 0 || r->var.xres == 0 || r->var.yres == 0) {
    snprintf(error, error_size, "unsupported fb bpp=%u line=%u xres=%u yres=%u",
             r->var.bits_per_pixel, r->fix.line_length, r->var.xres, r->var.yres);
    close(r->fd);
    r->fd = -1;
    return 0;
  }
  map_size = r->fix.smem_len ? (long)r->fix.smem_len
                             : (long)r->fix.line_length * (long)r->var.yres_virtual;
  r->frame_bytes = (long)r->fix.line_length * (long)r->var.yres;
  r->visible_yoffset = r->var.yoffset;
  visible_offset = (long)r->visible_yoffset * (long)r->fix.line_length +
                   (long)r->var.xoffset * (long)r->bytes_per_pixel;
  r->visible_offset = visible_offset;
  r->active_offset = visible_offset;
  r->draw_yoffset = r->visible_yoffset;
  if (map_size <= 0 || r->visible_offset < 0 ||
      r->visible_offset + r->frame_bytes > map_size) {
    snprintf(error, error_size, "invalid fb active page");
    close(r->fd);
    r->fd = -1;
    return 0;
  }
  r->map_size = (size_t)map_size;
  double_buffer_env = getenv("PLUMOS_FBDEV_DOUBLE_BUFFER");
  if ((!double_buffer_env || strcmp(double_buffer_env, "0") != 0) &&
      r->var.yres_virtual >= r->var.yres * 2U &&
      r->var.yoffset + r->var.yres <= r->var.yres_virtual) {
    r->draw_yoffset = r->var.yoffset < r->var.yres ? r->var.yres : 0;
    draw_offset = plumos_fbdev_yoffset_to_offset(r, r->draw_yoffset);
    if (plumos_fbdev_frame_offset_valid(r, draw_offset) &&
        r->draw_yoffset + r->var.yres <= r->var.yres_virtual) {
      r->active_offset = draw_offset;
      r->double_buffer = 1;
    } else {
      r->draw_yoffset = r->visible_yoffset;
    }
  }
  r->mem = mmap(NULL, r->map_size, PROT_READ | PROT_WRITE, MAP_SHARED, r->fd, 0);
  if (r->mem == MAP_FAILED) {
    r->mem = NULL;
    snprintf(error, error_size, "mmap framebuffer: %s", strerror(errno));
    close(r->fd);
    r->fd = -1;
    return 0;
  }
  return 1;
}

static void plumos_fbdev_renderer_set_rotation(struct plumos_fbdev_renderer *r,
                                               const char *rotation) {
  if (!r) {
    return;
  }
  r->rotation_180 = rotation &&
                    (strcmp(rotation, "180") == 0 ||
                     strcmp(rotation, "rotate180") == 0 ||
                     strcmp(rotation, "inverted") == 0);
}

static int plumos_fbdev_render_lines(struct plumos_fbdev_renderer *r,
                                     char lines[][PLUMOS_FBDEV_RENDER_LINE_MAX],
                                     size_t line_count) {
  struct plumos_fbdev_palette palette;
  const char *mode;
  int ok;

  if (!r || !r->mem) {
    return 0;
  }
  plumos_fbdev_load_palette(r, &palette, lines, line_count);
  mode = plumos_fbdev_find_value(lines, line_count, "graphic_mode=");
  if (plumos_fbdev_has_prefixed_line(lines, line_count,
                                     "top_refresh_running=1")) {
    ok = plumos_fbdev_render_top_refresh_running(r, &palette);
  } else if (mode && strcmp(mode, "top") == 0) {
    ok = plumos_fbdev_render_top(r, lines, line_count, &palette);
  } else if (mode && (strcmp(mode, "roms") == 0 ||
                      strcmp(mode, "favorites") == 0 ||
                      strcmp(mode, "recent") == 0 ||
                      strcmp(mode, "gallery") == 0)) {
    ok = plumos_fbdev_render_roms(r, lines, line_count, &palette);
  } else {
    ok = plumos_fbdev_render_generic(r, lines, line_count, &palette);
  }
  msync(r->mem, r->map_size, MS_ASYNC);
  if (ok) {
    plumos_fbdev_present(r);
  }
  return ok;
}

static void plumos_fbdev_renderer_reset_marquee(struct plumos_fbdev_renderer *r) {
  (void)r;
}

static void plumos_fbdev_renderer_shutdown(struct plumos_fbdev_renderer *r) {
  if (!r) {
    return;
  }
  if (r->mem) {
    munmap(r->mem, r->map_size);
    r->mem = NULL;
  }
  if (r->fd >= 0) {
    close(r->fd);
    r->fd = -1;
  }
}

#endif

#endif
