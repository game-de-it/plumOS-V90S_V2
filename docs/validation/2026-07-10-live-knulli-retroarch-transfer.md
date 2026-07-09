# Live KNULLI RetroArch Transfer Test

Date: 2026-07-10

## Purpose

Avoid an SD-card rebuild when only the RetroArch binary changed. The live V90S
was reachable over SSH, so the KNULLI-style RetroArch binary was copied to
`/tmp` and launched with the current PVR/SDL2/QuickNES runtime.

## Device

```text
ip=192.0.2.111
kernel=Linux 4.9.191 #17 SMP PREEMPT Tue May 13 18:14:09 UTC 2025 aarch64
rootfs_profile=debian-retroarch-pvr-sdl2
```

## Transfer

```text
/tmp/retroarch-knulli
sha256=96d830e236a92094e5aa77252f9fe7f9cac213158ca61bfab9a3f7efc3e760c5
/tmp/v90s-retroarch-launch.sh
/tmp/v90s-retroarch-stop.sh
```

The previous RetroArch process was stopped through `v90s-retroarch-stop`, which
used the recorded PID file and left SSH alive.

## Runtime Dependency Check

`ldd` on device resolved the important libraries to the intended runtime:

```text
libGLESv2.so.2 => /usr/lib/powervr/libGLESv2.so.2
libEGL.so.1 => /usr/lib/powervr/libEGL.so.1
libSDL2-2.0.so.0 => /usr/local/lib/plumos-sdl2-mali/libSDL2-2.0.so.0
libIMGegl.so => /usr/lib/powervr/libIMGegl.so
libsrv_um.so => /usr/lib/powervr/libsrv_um.so
libglslcompiler.so => /usr/lib/powervr/libglslcompiler.so
libusc.so => /usr/lib/powervr/libusc.so
```

## Launch Route

The live launch used a single explicit route:

```text
PLUMOS_V90S_RETROARCH_BIN=/tmp/retroarch-knulli
PLUMOS_V90S_CORE=/tmp/quicknes_libretro.so
PLUMOS_V90S_VIDEO_DRIVER=gl
PLUMOS_V90S_VIDEO_CONTEXT_DRIVER=mali_fbdev
PLUMOS_V90S_VIDEO_THREADED=false
PLUMOS_V90S_INPUT_DRIVER=sdl2
PLUMOS_V90S_JOYPAD_DRIVER=sdl2
PLUMOS_V90S_AUDIO_DRIVER=alsa
PLUMOS_V90S_SDL_VIDEODRIVER=mali
PLUMOS_V90S_SDL_RENDER_DRIVER=software
```

## Observed Log

RetroArch started and stayed running:

```text
RetroArch 1.22.2 (Git 69a4f0ea1e)
Core: /tmp/quicknes_libretro.so
ROM: /roms/nes/Super Mario Bros..nes
[Mali] GLES version = 2.
[EGL] EGL version: 1.4.
[EGL] Created shared context
[ERROR] [EGL] #0x300b, EGL_BAD_NATIVE_WINDOW.
[SDL GL] SDL 2.26.5 gfx context driver initialized.
[GL] Found GL context: "gl_sdl".
[GL] Vendor: Imagination Technologies, Renderer: PowerVR Rogue GE8300.
[GL] Version: OpenGL ES 3.2 build 1.19@6345021.
[Audio] Started synchronous audio driver.
[Display] Found display driver: "gl".
```

Process status after launch:

```text
RetroArch: pid=2501 running comm='retroarch-knull'
launcher: pid=2367 running comm='v90s-retroarch-'
```

## Pending

User visual/audio confirmation is still needed. The important distinction for
the next step is whether the internal RetroArch context fallback to `gl_sdl`
still improves frame pacing, or whether the `EGL_BAD_NATIVE_WINDOW` means the
native `mali_fbdev` path needs a source-level fix.
