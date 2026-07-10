#ifndef PLUMOS_FBDEV_RENDERER_H
#define PLUMOS_FBDEV_RENDERER_H

#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <linux/fb.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
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
  uint32_t bg;
  uint32_t panel;
  uint32_t accent;
  uint32_t text;
  uint32_t dim;
  uint32_t selected_bg;
  int w;
  int h;
  int scale = 2;
  int margin_x = 24;
  int margin_y = 22;
  int line_h;
  int max_y;
  size_t i;

  if (!r || !r->mem) {
    return 0;
  }
  w = (int)r->var.xres;
  h = (int)r->var.yres;
  if (w < 360 || h < 240) {
    scale = 1;
    margin_x = 10;
    margin_y = 10;
  }
  line_h = 9 * scale;
  max_y = h - margin_y;

  bg = plumos_fbdev_pack_color(r, 7, 10, 14);
  panel = plumos_fbdev_pack_color(r, 15, 22, 30);
  accent = plumos_fbdev_pack_color(r, 40, 194, 124);
  text = plumos_fbdev_pack_color(r, 227, 235, 241);
  dim = plumos_fbdev_pack_color(r, 126, 148, 163);
  selected_bg = plumos_fbdev_pack_color(r, 34, 53, 70);

  plumos_fbdev_fill_rect(r, 0, 0, w, h, bg);
  plumos_fbdev_fill_rect(r, 0, 0, 8, h, accent);
  plumos_fbdev_fill_rect(r, margin_x - 8, margin_y - 10,
                         w - (margin_x * 2) + 16, h - (margin_y * 2) + 20,
                         panel);
  plumos_fbdev_fill_rect(r, margin_x - 8, margin_y - 10,
                         w - (margin_x * 2) + 16, 3, accent);

  for (i = 0; i < line_count; i++) {
    int y = margin_y + (int)i * line_h;
    uint32_t color = i == 0 ? accent : text;
    const char *line = lines[i];
    while (*line && isspace((unsigned char)*line)) {
      line++;
    }
    if (y + 7 * scale > max_y) {
      break;
    }
    if (line[0] == '>') {
      plumos_fbdev_fill_rect(r, margin_x - 4, y - 2, w - (margin_x * 2) + 8,
                             line_h, selected_bg);
      color = accent;
    } else if (line[0] == '\0' || strncmp(line, "footer", 6) == 0 ||
               strncmp(line, "status:", 7) == 0) {
      color = dim;
    }
    plumos_fbdev_draw_text(r, margin_x, y, lines[i], scale, color, w - margin_x);
  }
  msync(r->mem, r->map_size, MS_SYNC);
  return 1;
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
