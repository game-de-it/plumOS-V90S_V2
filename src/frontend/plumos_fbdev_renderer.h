#ifndef PLUMOS_FBDEV_RENDERER_H
#define PLUMOS_FBDEV_RENDERER_H

#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <linux/fb.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <strings.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <unistd.h>

#ifndef PLUMOS_FBDEV_RENDER_LINE_MAX
#define PLUMOS_FBDEV_RENDER_LINE_MAX 512
#endif

#ifndef PLUMOS_FBDEV_RENDERER_GLYPHS_ONLY
struct plumos_fbdev_renderer {
  int fd;
  unsigned char *mem;
  size_t map_size;
  int bytes_per_pixel;
  int rotation_180;
  long active_offset;
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

static const char *plumos_fbdev_ltrim(const char *s) {
  while (s && *s && isspace((unsigned char)*s)) {
    s++;
  }
  return s ? s : "";
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

static void plumos_fbdev_draw_text_right(struct plumos_fbdev_renderer *r, int x,
                                         int y, int right, const char *text,
                                         int scale, uint32_t color) {
  int width = plumos_fbdev_text_width(text, scale);
  int draw_x = right - width;
  if (draw_x < x) {
    draw_x = x;
  }
  plumos_fbdev_draw_text(r, draw_x, y, text, scale, color, right);
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

static void plumos_fbdev_draw_frame(struct plumos_fbdev_renderer *r, int x, int y,
                                    int w, int h, int thickness, uint32_t color) {
  int t;
  if (thickness <= 0) {
    thickness = 1;
  }
  for (t = 0; t < thickness; t++) {
    plumos_fbdev_fill_rect(r, x + t, y + t, w - t * 2, 1, color);
    plumos_fbdev_fill_rect(r, x + t, y + h - 1 - t, w - t * 2, 1, color);
    plumos_fbdev_fill_rect(r, x + t, y + t, 1, h - t * 2, color);
    plumos_fbdev_fill_rect(r, x + w - 1 - t, y + t, 1, h - t * 2, color);
  }
}

static void plumos_fbdev_draw_shell(struct plumos_fbdev_renderer *r,
                                    const struct plumos_fbdev_palette *p) {
  int w = (int)r->var.xres;
  int h = (int)r->var.yres;
  plumos_fbdev_fill_rect(r, 0, 0, w, h, p->background);
  plumos_fbdev_fill_rect(r, 0, 0, w, 52, p->panel_inner);
  plumos_fbdev_fill_rect(r, 0, 51, w, 2, p->accent);
  plumos_fbdev_fill_rect(r, 0, h - 32, w, 32, p->panel_inner);
  plumos_fbdev_fill_rect(r, 0, h - 33, w, 1, p->line);
  plumos_fbdev_draw_text(r, 24, 15, "plumOS", 3, p->foreground, w - 24);
  plumos_fbdev_draw_text_right(r, 24, 21, w - 24, "V90S", 2, p->muted);
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

static void plumos_fbdev_draw_top_tile(struct plumos_fbdev_renderer *r,
                                       const struct plumos_fbdev_palette *p,
                                       const struct plumos_fbdev_entry *entry,
                                       int x, int y, int w, int h) {
  uint32_t fill = entry->selected ? p->selection_background : p->panel;
  uint32_t outline = entry->selected ? p->accent : p->line;
  uint32_t title_color = entry->selected ? p->selection_foreground : p->foreground;
  int icon_w = w / 2;
  int icon_x = x + (w - icon_w) / 2;
  int icon_y = y + 26;
  int title_scale = w >= 150 ? 3 : 2;
  char badge[8];

  plumos_fbdev_entry_badge(badge, sizeof(badge), entry->title);
  plumos_fbdev_fill_rect(r, x, y, w, h, fill);
  plumos_fbdev_draw_frame(r, x, y, w, h, entry->selected ? 3 : 1, outline);
  plumos_fbdev_fill_rect(r, icon_x, icon_y, icon_w, 54, p->media_panel);
  plumos_fbdev_draw_frame(r, icon_x, icon_y, icon_w, 54, 1, p->line);
  plumos_fbdev_draw_text_center(r, icon_x, icon_y + 15, icon_w, badge,
                                3, entry->selected ? p->selection_foreground : p->accent);
  plumos_fbdev_draw_text_center(r, x + 8, y + h - 52, w - 16, entry->title,
                                title_scale, title_color);
  if (entry->detail[0]) {
    plumos_fbdev_draw_text_center(r, x + 12, y + h - 24, w - 24, entry->detail,
                                  1, p->muted);
  }
}

static int plumos_fbdev_render_top(struct plumos_fbdev_renderer *r,
                                   char lines[][PLUMOS_FBDEV_RENDER_LINE_MAX],
                                   size_t line_count,
                                   const struct plumos_fbdev_palette *p) {
  struct plumos_fbdev_entry entries[12];
  size_t count;
  size_t i;
  int w = (int)r->var.xres;
  int cols;
  int rows;
  int pad = w >= 640 ? 24 : 12;
  int gap = w >= 640 ? 14 : 8;
  int top_y = 92;
  int tile_h;
  int tile_w;

  count = plumos_fbdev_collect_graphic_entries(lines, line_count, entries,
                                               sizeof(entries) / sizeof(entries[0]));
  if (count == 0) {
    memset(&entries[0], 0, sizeof(entries[0]));
    entries[0].selected = 1;
    plumos_fbdev_copy_text(entries[0].title, sizeof(entries[0].title), "No Systems");
    count = 1;
  }
  if (count <= 2) {
    cols = (int)count;
  } else {
    cols = 3;
  }
  if (cols < 1) {
    cols = 1;
  }
  rows = (int)((count + (size_t)cols - 1) / (size_t)cols);
  if (rows > 2) {
    rows = 2;
  }
  tile_w = (w - pad * 2 - gap * (cols - 1)) / cols;
  tile_h = rows > 1 ? 126 : 236;

  plumos_fbdev_draw_shell(r, p);
  plumos_fbdev_draw_text(r, pad, 64, "SYSTEMS", 3, p->foreground, w - pad);
  plumos_fbdev_draw_text_right(r, pad, 72, w - pad, "LIBRARY", 2, p->muted);

  for (i = 0; i < count && i < 6; i++) {
    int col = (int)i % cols;
    int row = (int)i / cols;
    int x = pad + col * (tile_w + gap);
    int y = top_y + row * (tile_h + gap);
    plumos_fbdev_draw_top_tile(r, p, &entries[i], x, y, tile_w, tile_h);
  }
  plumos_fbdev_draw_status(r, p, lines, line_count);
  return 1;
}

static void plumos_fbdev_draw_rom_preview(struct plumos_fbdev_renderer *r,
                                          const struct plumos_fbdev_palette *p,
                                          const struct plumos_fbdev_entry *entry,
                                          const char *system_title,
                                          int x, int y, int w, int h) {
  plumos_fbdev_fill_rect(r, x, y, w, h, p->media_panel);
  plumos_fbdev_draw_frame(r, x, y, w, h, 1, p->line);
  plumos_fbdev_fill_rect(r, x + 18, y + 20, w - 36, h / 2, p->panel_inner);
  plumos_fbdev_draw_frame(r, x + 18, y + 20, w - 36, h / 2, 1, p->line);
  plumos_fbdev_draw_text_center(r, x + 18, y + 20 + h / 4 - 10, w - 36,
                                "NO IMAGE", 2, p->muted);
  if (entry) {
    plumos_fbdev_draw_text(r, x + 18, y + h - 70, entry->title, 2, p->foreground,
                           x + w - 18);
    if (entry->detail[0]) {
      plumos_fbdev_draw_text(r, x + 18, y + h - 42, entry->detail, 1, p->muted,
                             x + w - 18);
    }
  }
  if (system_title && system_title[0]) {
    plumos_fbdev_draw_text(r, x + 18, y + h - 22, system_title, 1, p->accent,
                           x + w - 18);
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
  int pad = w >= 640 ? 24 : 12;
  int list_x = pad;
  int list_y = 88;
  int list_w = (w * 58) / 100;
  int row_h = 30;
  int preview_x = list_x + list_w + 16;
  int preview_w = w - preview_x - pad;

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

  plumos_fbdev_draw_shell(r, p);
  plumos_fbdev_draw_text(r, pad, 64, title, 2, p->foreground, w - pad);
  plumos_fbdev_fill_rect(r, list_x, list_y, list_w, h - list_y - 52, p->panel);
  plumos_fbdev_draw_frame(r, list_x, list_y, list_w, h - list_y - 52, 1, p->line);

  for (i = 0; i < count; i++) {
    int y = list_y + 12 + (int)i * row_h;
    int row_x = list_x + 10;
    int row_w = list_w - 20;
    uint32_t fg = entries[i].selected ? p->selection_foreground : p->foreground;
    if (y + row_h > h - 54) {
      break;
    }
    if (entries[i].selected) {
      plumos_fbdev_fill_rect(r, row_x, y - 4, row_w, row_h - 2,
                             p->selection_background);
      plumos_fbdev_fill_rect(r, row_x, y - 4, 4, row_h - 2, p->accent);
    }
    plumos_fbdev_draw_text(r, row_x + 12, y + 3, entries[i].title, 2, fg,
                           row_x + row_w - 8);
  }

  plumos_fbdev_draw_rom_preview(r, p, selected, title, preview_x, list_y,
                                preview_w, h - list_y - 52);
  plumos_fbdev_draw_status(r, p, lines, line_count);
  return 1;
}

static int plumos_fbdev_is_hidden_line(const char *line) {
  if (!line || !line[0]) {
    return 1;
  }
  if (strncmp(line, "graphic_", 8) == 0 ||
      strncmp(line, "entries=", 8) == 0 ||
      strncmp(line, "system=", 7) == 0 ||
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
  int pad = w >= 640 ? 24 : 12;
  int list_y = 90;
  int row_h = 28;

  memset(selected, 0, sizeof(selected));
  plumos_fbdev_screen_title(title, sizeof(title), lines, line_count);
  for (i = 1; i < line_count && item_count < 18; i++) {
    const char *line = plumos_fbdev_ltrim(lines[i]);
    int is_selected = 0;
    if (plumos_fbdev_is_hidden_line(line)) {
      continue;
    }
    if (line[0] == '>') {
      is_selected = 1;
      line++;
      line = plumos_fbdev_ltrim(line);
    }
    plumos_fbdev_copy_text(items[item_count], sizeof(items[item_count]), line);
    selected[item_count] = is_selected;
    item_count++;
  }
  if (item_count == 0) {
    plumos_fbdev_copy_text(items[0], sizeof(items[0]), "Ready");
    selected[0] = 1;
    item_count = 1;
  }

  plumos_fbdev_draw_shell(r, p);
  plumos_fbdev_draw_text(r, pad, 64, title, 2, p->foreground, w - pad);
  plumos_fbdev_fill_rect(r, pad, list_y, w - pad * 2, h - list_y - 52, p->panel);
  plumos_fbdev_draw_frame(r, pad, list_y, w - pad * 2, h - list_y - 52, 1, p->line);
  for (i = 0; i < item_count; i++) {
    int y = list_y + 12 + (int)i * row_h;
    uint32_t fg = selected[i] ? p->selection_foreground : p->foreground;
    if (y + row_h > h - 54) {
      break;
    }
    if (selected[i]) {
      plumos_fbdev_fill_rect(r, pad + 10, y - 4, w - pad * 2 - 20, row_h - 2,
                             p->selection_background);
      plumos_fbdev_fill_rect(r, pad + 10, y - 4, 4, row_h - 2, p->accent);
    }
    plumos_fbdev_draw_text(r, pad + 28, y + 3, items[i], 2, fg, w - pad - 24);
  }
  plumos_fbdev_draw_status(r, p, lines, line_count);
  return 1;
}

static int plumos_fbdev_renderer_init(struct plumos_fbdev_renderer *r,
                                      const char *fb_path, char *error,
                                      size_t error_size) {
  long map_size;
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
  r->active_offset = (long)r->var.yoffset * (long)r->fix.line_length +
                     (long)r->var.xoffset * (long)r->bytes_per_pixel;
  if (map_size <= 0 || r->active_offset < 0 ||
      r->active_offset + (long)r->fix.line_length * (long)r->var.yres > map_size) {
    snprintf(error, error_size, "invalid fb active page");
    close(r->fd);
    r->fd = -1;
    return 0;
  }
  r->map_size = (size_t)map_size;
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
  if (mode && strcmp(mode, "top") == 0) {
    ok = plumos_fbdev_render_top(r, lines, line_count, &palette);
  } else if (mode && (strcmp(mode, "roms") == 0 ||
                      strcmp(mode, "favorites") == 0 ||
                      strcmp(mode, "recent") == 0 ||
                      strcmp(mode, "gallery") == 0)) {
    ok = plumos_fbdev_render_roms(r, lines, line_count, &palette);
  } else {
    ok = plumos_fbdev_render_generic(r, lines, line_count, &palette);
  }
  msync(r->mem, r->map_size, MS_SYNC);
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
