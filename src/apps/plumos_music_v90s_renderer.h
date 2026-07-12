#ifndef PLUMOS_MUSIC_V90S_RENDERER_H
#define PLUMOS_MUSIC_V90S_RENDERER_H

#include "../frontend/plumos_fbdev_renderer.h"

/*
 * The MMF music player is renderer-agnostic enough that it only needs a small
 * compatibility layer. Keep the original renderer names in the imported source
 * and map them to the V90S fbdev renderer here.
 */
#define plumos_mmf_gfx_renderer plumos_fbdev_renderer
#define plumos_mmf_gfx_renderer_init plumos_fbdev_renderer_init
#define plumos_mmf_gfx_renderer_set_rotation plumos_fbdev_renderer_set_rotation
#define plumos_mmf_gfx_renderer_load_font plumos_fbdev_renderer_load_font
#define plumos_mmf_gfx_renderer_load_fallback_font \
  plumos_fbdev_renderer_load_fallback_font
#define plumos_mmf_gfx_renderer_shutdown plumos_fbdev_renderer_shutdown
#define plumos_mmf_gfx_rgb_color plumos_fbdev_pack_color
#define plumos_mmf_gfx_fill_rect plumos_fbdev_fill_rect

static void plumos_mmf_gfx_text_limited(struct plumos_fbdev_renderer *r,
                                        const char *text, int x, int y,
                                        int scale, uint32_t color, int max_x) {
#ifdef PLUMOS_FBDEV_ENABLE_FREETYPE
  plumos_fbdev_draw_text_font(r, x, y, text ? text : "", scale, 1, color, max_x);
#else
  plumos_fbdev_draw_text(r, x, y, text ? text : "", scale, color, max_x);
#endif
}

static void plumos_mmf_gfx_blend_rgba(struct plumos_fbdev_renderer *r, int x,
                                      int y, unsigned char red,
                                      unsigned char green, unsigned char blue,
                                      unsigned char alpha) {
  if (alpha < 128) {
    return;
  }
  plumos_fbdev_put_pixel(r, x, y, plumos_fbdev_pack_color(r, red, green, blue));
}

static int plumos_mmf_gfx_present(struct plumos_fbdev_renderer *r) {
  if (r && r->mem) {
    msync(r->mem, r->map_size, MS_ASYNC);
  }
  return plumos_fbdev_present(r);
}

#endif
