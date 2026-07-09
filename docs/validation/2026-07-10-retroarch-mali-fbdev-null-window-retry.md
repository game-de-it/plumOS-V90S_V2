# RetroArch Mali Fbdev NULL Window Retry

Date: 2026-07-10

## Purpose

The previous live KNULLI RetroArch transfer proved that the binary can load the
QuickNES core and the V90S ROM, but RetroArch did not stay on its native
`mali_fbdev` context:

```text
[Mali] GLES version = 2.
[EGL] EGL version: 1.4.
[EGL] Created shared context
[ERROR] [EGL] #0x300b, EGL_BAD_NATIVE_WINDOW.
[SDL GL] SDL 2.26.5 gfx context driver initialized.
[GL] Found GL context: "gl_sdl".
```

KNULLI's V90S SDL2 Mali patch has an important compatibility behavior: if the
PowerVR GE8300 EGL stack rejects the fbdev native window, SDL2 retries
`eglCreateWindowSurface` with a NULL native window. RetroArch's upstream
`mali_fbdev` context did not have that retry, so the next small experiment is
to add the same retry to RetroArch.

## Source Changes

Added:

```text
patches/retroarch/001-v90s-mali-fbdev-null-window-retry.patch
```

The patch keeps the first attempt with `mali->native_window`; if it fails,
RetroArch logs the EGL error and retries surface creation with `NULL`.

`scripts/build-retroarch-knulli.sh` now always applies local RetroArch patches
from `patches/retroarch` after resetting the source tree to the requested tag.
KNULLI package patches remain opt-in with `--apply-patches`.

## Build

Command:

```text
./scripts/build-retroarch-knulli.sh
```

Result:

```text
output/retroarch-knulli/usr/local/bin/retroarch-knulli
sha256=d377e9ed983290d3829dc17e551561558e75b16ebf55bad49d0b0449178f1664
```

Manifest excerpt:

```text
version=v1.22.2
patches=none
local_patches=001-v90s-mali-fbdev-null-window-retry.patch
configure=--enable-mali_fbdev --enable-egl --enable-opengles --enable-opengles3 --enable-sdl2 --enable-alsa --disable-x11 --disable-wayland --disable-kms
```

## Live Transfer Status

The device was not reachable over SSH after the user's reboot.

Observed scan results:

```text
192.0.2.111: no ping, SSH timed out
192.0.2.6: SSH open, but public-key login refused; not treated as V90S
192.0.2.100: SSH port open, but banner exchange timed out
192.0.2.108: host up, SSH connection refused
192.0.2.140: host up, SSH connection refused
192.0.2.157: host up, SSH connection refused
```

Added helper for the next reachable-SSH attempt:

```text
scripts/live-transfer-retroarch-knulli.sh IP
```

It transfers:

```text
/tmp/retroarch-knulli
/tmp/quicknes_libretro.so
/tmp/v90s-retroarch-launch.sh
/tmp/v90s-retroarch-stop.sh
```

Then it uses `v90s-retroarch-stop.sh` to stop only the managed RetroArch PID and
launches the single explicit test route:

```text
PLUMOS_V90S_VIDEO_DRIVER=gl
PLUMOS_V90S_VIDEO_CONTEXT_DRIVER=mali_fbdev
PLUMOS_V90S_VIDEO_THREADED=false
PLUMOS_V90S_INPUT_DRIVER=sdl2
PLUMOS_V90S_JOYPAD_DRIVER=sdl2
PLUMOS_V90S_AUDIO_DRIVER=alsa
PLUMOS_V90S_SDL_VIDEODRIVER=mali
PLUMOS_V90S_SDL_RENDER_DRIVER=software
```

## Next Check

When SSH is reachable again, run:

```text
./scripts/live-transfer-retroarch-knulli.sh <V90S_IP>
```

The important log signal is whether `plumos-v90s-retroarch.log` now contains
the new retry line followed by a native `mali_fbdev` context, without falling
through to `gl_sdl`.
