#ifndef PLUMOS_PICOARCH_V90S_FBDEV_H
#define PLUMOS_PICOARCH_V90S_FBDEV_H

#include <fcntl.h>
#include <linux/fb.h>
#include <stdint.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <unistd.h>

static int v90s_fb_fd = -1;
static uint8_t *v90s_fb_map;
static size_t v90s_fb_size;
static struct fb_fix_screeninfo v90s_fb_fix;
static struct fb_var_screeninfo v90s_fb_var;
static uint32_t v90s_fb_draw_yoffset;
static int v90s_fb_double_buffer;

static int v90s_fb_init(void)
{
	v90s_fb_fd = open("/dev/fb0", O_RDWR);
	if (v90s_fb_fd < 0 ||
	    ioctl(v90s_fb_fd, FBIOGET_FSCREENINFO, &v90s_fb_fix) < 0 ||
	    ioctl(v90s_fb_fd, FBIOGET_VSCREENINFO, &v90s_fb_var) < 0 ||
	    v90s_fb_var.bits_per_pixel != 32 ||
	    v90s_fb_var.xres < SCREEN_WIDTH ||
	    v90s_fb_var.yres < SCREEN_HEIGHT ||
	    v90s_fb_fix.line_length < (v90s_fb_var.xoffset + SCREEN_WIDTH) * 4) {
		return -1;
	}
	v90s_fb_size = v90s_fb_fix.smem_len
	                 ? v90s_fb_fix.smem_len
	                 : (size_t)v90s_fb_fix.line_length * v90s_fb_var.yres_virtual;
	if (v90s_fb_size < (size_t)v90s_fb_fix.line_length *
	                    (v90s_fb_var.yoffset + SCREEN_HEIGHT)) {
		return -1;
	}
	v90s_fb_map = mmap(NULL, v90s_fb_size, PROT_READ | PROT_WRITE,
	                   MAP_SHARED, v90s_fb_fd, 0);
	if (v90s_fb_map == MAP_FAILED) {
		return -1;
	}
	v90s_fb_double_buffer = v90s_fb_var.yres_virtual >= v90s_fb_var.yres * 2;
	v90s_fb_draw_yoffset = v90s_fb_double_buffer &&
	                       v90s_fb_var.yoffset < v90s_fb_var.yres
	                         ? v90s_fb_var.yres : 0;
	return 0;
}

static void v90s_fb_present(const SDL_Surface *surface)
{
	unsigned y;

	if (!v90s_fb_map || !surface) {
		return;
	}
	for (y = 0; y < SCREEN_HEIGHT; y++) {
		const uint16_t *src = (const uint16_t *)
			((const uint8_t *)surface->pixels + y * surface->pitch);
		uint32_t *dst = (uint32_t *)(v90s_fb_map +
			(v90s_fb_draw_yoffset + y) * v90s_fb_fix.line_length +
			v90s_fb_var.xoffset * 4);
		unsigned x;

		for (x = 0; x < SCREEN_WIDTH; x++) {
			uint16_t p = src[x];
			uint32_t r = (p >> 11) & 0x1f;
			uint32_t g = (p >> 5) & 0x3f;
			uint32_t b = p & 0x1f;

			dst[x] = 0xff000000u | ((r << 3 | r >> 2) << 16) |
			         ((g << 2 | g >> 4) << 8) | (b << 3 | b >> 2);
		}
	}
	if (v90s_fb_double_buffer) {
		struct fb_var_screeninfo next = v90s_fb_var;
#ifdef FBIO_WAITFORVSYNC
		int arg = 0;
		(void)ioctl(v90s_fb_fd, FBIO_WAITFORVSYNC, &arg);
#endif
		next.xoffset = 0;
		next.yoffset = v90s_fb_draw_yoffset;
#ifdef FB_ACTIVATE_VBL
		next.activate = FB_ACTIVATE_VBL;
#endif
		if (ioctl(v90s_fb_fd, FBIOPAN_DISPLAY, &next) == 0) {
			v90s_fb_var = next;
			v90s_fb_draw_yoffset = next.yoffset == 0 ? next.yres : 0;
		} else {
			v90s_fb_double_buffer = 0;
			v90s_fb_draw_yoffset = v90s_fb_var.yoffset;
		}
	}
}

static void v90s_fb_finish(void)
{
	if (v90s_fb_map && v90s_fb_map != MAP_FAILED) {
		munmap(v90s_fb_map, v90s_fb_size);
	}
	if (v90s_fb_fd >= 0) {
		close(v90s_fb_fd);
	}
	v90s_fb_map = NULL;
	v90s_fb_fd = -1;
}

#endif
