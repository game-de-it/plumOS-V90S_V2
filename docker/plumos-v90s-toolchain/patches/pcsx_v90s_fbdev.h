#ifndef PLUMOS_PCSX_V90S_FBDEV_H
#define PLUMOS_PCSX_V90S_FBDEV_H

#include <fcntl.h>
#include <linux/fb.h>
#include <pthread.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <unistd.h>

struct v90s_pcsx_frame {
	uint16_t *pixels;
	unsigned width;
	unsigned height;
	unsigned pitch;
};

static int v90s_pcsx_fb_fd = -1;
static uint8_t *v90s_pcsx_fb_map;
static size_t v90s_pcsx_fb_size;
static struct fb_fix_screeninfo v90s_pcsx_fb_fix;
static struct fb_var_screeninfo v90s_pcsx_fb_var;
static uint32_t v90s_pcsx_fb_draw_yoffset;
static int v90s_pcsx_fb_double_buffer;
static pthread_t v90s_pcsx_fb_thread;
static pthread_mutex_t v90s_pcsx_fb_mutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t v90s_pcsx_fb_cond = PTHREAD_COND_INITIALIZER;
static struct v90s_pcsx_frame v90s_pcsx_fb_frames[2];
static size_t v90s_pcsx_fb_frame_capacity;
static int v90s_pcsx_fb_thread_started;
static int v90s_pcsx_fb_thread_stop;
static int v90s_pcsx_fb_active = -1;
static int v90s_pcsx_fb_pending = -1;

static void v90s_pcsx_fb_present_pixels(const struct v90s_pcsx_frame *frame)
{
	unsigned dst_y;

	if (!v90s_pcsx_fb_map || !frame || !frame->pixels ||
	    !frame->width || !frame->height)
		return;
	for (dst_y = 0; dst_y < v90s_pcsx_fb_var.yres; dst_y++) {
		unsigned src_y = dst_y * frame->height / v90s_pcsx_fb_var.yres;
		const uint16_t *src = frame->pixels + src_y * frame->pitch;
		uint32_t *dst = (uint32_t *)(v90s_pcsx_fb_map +
			(v90s_pcsx_fb_draw_yoffset + dst_y) * v90s_pcsx_fb_fix.line_length +
			v90s_pcsx_fb_var.xoffset * 4);
		unsigned dst_x;

		for (dst_x = 0; dst_x < v90s_pcsx_fb_var.xres; dst_x++) {
			uint16_t p = src[dst_x * frame->width / v90s_pcsx_fb_var.xres];
			uint32_t r = (p >> 11) & 0x1f;
			uint32_t g = (p >> 5) & 0x3f;
			uint32_t b = p & 0x1f;

			dst[dst_x] = 0xff000000u |
				((r << 3 | r >> 2) << 16) |
				((g << 2 | g >> 4) << 8) |
				(b << 3 | b >> 2);
		}
	}
	if (v90s_pcsx_fb_double_buffer) {
		struct fb_var_screeninfo next = v90s_pcsx_fb_var;

		next.xoffset = 0;
		next.yoffset = v90s_pcsx_fb_draw_yoffset;
		next.activate = FB_ACTIVATE_NOW;
		if (ioctl(v90s_pcsx_fb_fd, FBIOPAN_DISPLAY, &next) == 0) {
			v90s_pcsx_fb_var = next;
			v90s_pcsx_fb_draw_yoffset =
				next.yoffset == 0 ? next.yres : 0;
		} else {
			v90s_pcsx_fb_double_buffer = 0;
			v90s_pcsx_fb_draw_yoffset = v90s_pcsx_fb_var.yoffset;
		}
	}
}

static void *v90s_pcsx_fb_present_thread(void *unused)
{
	(void)unused;
	for (;;) {
		int frame;

		pthread_mutex_lock(&v90s_pcsx_fb_mutex);
		while (v90s_pcsx_fb_pending < 0 && !v90s_pcsx_fb_thread_stop)
			pthread_cond_wait(&v90s_pcsx_fb_cond, &v90s_pcsx_fb_mutex);
		if (v90s_pcsx_fb_thread_stop) {
			pthread_mutex_unlock(&v90s_pcsx_fb_mutex);
			break;
		}
		frame = v90s_pcsx_fb_pending;
		v90s_pcsx_fb_pending = -1;
		v90s_pcsx_fb_active = frame;
		pthread_mutex_unlock(&v90s_pcsx_fb_mutex);

		v90s_pcsx_fb_present_pixels(&v90s_pcsx_fb_frames[frame]);

		pthread_mutex_lock(&v90s_pcsx_fb_mutex);
		v90s_pcsx_fb_active = -1;
		pthread_mutex_unlock(&v90s_pcsx_fb_mutex);
	}
	return NULL;
}

static int v90s_pcsx_fb_init(void)
{
	size_t frame_capacity;
	int index;

	v90s_pcsx_fb_fd = open("/dev/fb0", O_RDWR);
	if (v90s_pcsx_fb_fd < 0 ||
	    ioctl(v90s_pcsx_fb_fd, FBIOGET_FSCREENINFO, &v90s_pcsx_fb_fix) < 0 ||
	    ioctl(v90s_pcsx_fb_fd, FBIOGET_VSCREENINFO, &v90s_pcsx_fb_var) < 0 ||
	    v90s_pcsx_fb_var.bits_per_pixel != 32 ||
	    !v90s_pcsx_fb_var.xres || !v90s_pcsx_fb_var.yres ||
	    v90s_pcsx_fb_fix.line_length <
		(v90s_pcsx_fb_var.xoffset + v90s_pcsx_fb_var.xres) * 4)
		return -1;
	v90s_pcsx_fb_size = v90s_pcsx_fb_fix.smem_len
		? v90s_pcsx_fb_fix.smem_len
		: (size_t)v90s_pcsx_fb_fix.line_length *
		  v90s_pcsx_fb_var.yres_virtual;
	if (v90s_pcsx_fb_size < (size_t)v90s_pcsx_fb_fix.line_length *
	    (v90s_pcsx_fb_var.yoffset + v90s_pcsx_fb_var.yres))
		return -1;
	v90s_pcsx_fb_map = mmap(NULL, v90s_pcsx_fb_size, PROT_READ | PROT_WRITE,
		MAP_SHARED, v90s_pcsx_fb_fd, 0);
	if (v90s_pcsx_fb_map == MAP_FAILED) {
		v90s_pcsx_fb_map = NULL;
		return -1;
	}
	v90s_pcsx_fb_double_buffer =
		v90s_pcsx_fb_var.yres_virtual >= v90s_pcsx_fb_var.yres * 2;
	v90s_pcsx_fb_draw_yoffset = v90s_pcsx_fb_double_buffer &&
		v90s_pcsx_fb_var.yoffset < v90s_pcsx_fb_var.yres
		? v90s_pcsx_fb_var.yres : 0;
	frame_capacity = (size_t)v90s_pcsx_fb_var.xres * v90s_pcsx_fb_var.yres;
	v90s_pcsx_fb_frame_capacity = frame_capacity;
	for (index = 0; index < 2; index++) {
		v90s_pcsx_fb_frames[index].pixels =
			malloc(frame_capacity * sizeof(uint16_t));
		if (!v90s_pcsx_fb_frames[index].pixels)
			return -1;
	}
	if (pthread_create(&v90s_pcsx_fb_thread, NULL,
	    v90s_pcsx_fb_present_thread, NULL) != 0)
		return -1;
	v90s_pcsx_fb_thread_started = 1;
	return 0;
}

static void v90s_pcsx_fb_present(const SDL_Surface *surface)
{
	struct v90s_pcsx_frame *dst;
	unsigned width;
	unsigned height;
	unsigned y;
	int frame;

	if (!surface || !surface->pixels || !v90s_pcsx_fb_thread_started ||
	    !surface->format || surface->format->BitsPerPixel != 16)
		return;
	width = (unsigned)surface->w;
	height = (unsigned)surface->h;
	if (!width || !height ||
	    (size_t)width * height > v90s_pcsx_fb_frame_capacity)
		return;
	pthread_mutex_lock(&v90s_pcsx_fb_mutex);
	frame = v90s_pcsx_fb_active == 0 ? 1 : 0;
	if (v90s_pcsx_fb_active < 0 && v90s_pcsx_fb_pending >= 0)
		frame = v90s_pcsx_fb_pending;
	dst = &v90s_pcsx_fb_frames[frame];
	for (y = 0; y < height; y++)
		memcpy(dst->pixels + (size_t)y * width,
			(const uint8_t *)surface->pixels + y * surface->pitch,
			width * sizeof(uint16_t));
	dst->width = width;
	dst->height = height;
	dst->pitch = width;
	v90s_pcsx_fb_pending = frame;
	pthread_cond_signal(&v90s_pcsx_fb_cond);
	pthread_mutex_unlock(&v90s_pcsx_fb_mutex);
}

static void v90s_pcsx_fb_finish(void)
{
	int index;

	if (v90s_pcsx_fb_thread_started) {
		pthread_mutex_lock(&v90s_pcsx_fb_mutex);
		v90s_pcsx_fb_thread_stop = 1;
		pthread_cond_signal(&v90s_pcsx_fb_cond);
		pthread_mutex_unlock(&v90s_pcsx_fb_mutex);
		pthread_join(v90s_pcsx_fb_thread, NULL);
		v90s_pcsx_fb_thread_started = 0;
	}
	if (v90s_pcsx_fb_map)
		munmap(v90s_pcsx_fb_map, v90s_pcsx_fb_size);
	if (v90s_pcsx_fb_fd >= 0)
		close(v90s_pcsx_fb_fd);
	for (index = 0; index < 2; index++) {
		free(v90s_pcsx_fb_frames[index].pixels);
		v90s_pcsx_fb_frames[index].pixels = NULL;
	}
	v90s_pcsx_fb_map = NULL;
	v90s_pcsx_fb_fd = -1;
}

#endif
