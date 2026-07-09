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

The device was not reachable over SSH immediately after the user's reboot.

Observed scan results:

```text
192.0.2.111: no ping, SSH timed out
192.0.2.6: SSH open, but public-key login refused; not treated as V90S
192.0.2.100: SSH port open, but banner exchange timed out
192.0.2.108: host up, SSH connection refused
192.0.2.140: host up, SSH connection refused
192.0.2.157: host up, SSH connection refused
```

The user later found that DHCP had moved the V90S to `192.0.2.118`. SSH
verified the device:

```text
Linux (none) 4.9.191 #17 SMP PREEMPT Tue May 13 18:14:09 UTC 2025 aarch64 GNU/Linux
wlan0 UP 192.0.2.118/24
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

This was run against `192.0.2.118`. Transfer hashes:

```text
/tmp/retroarch-knulli
sha256=d377e9ed983290d3829dc17e551561558e75b16ebf55bad49d0b0449178f1664
/tmp/quicknes_libretro.so
sha256=da48490d5aab244bc0c13e6381555ac2003b438336dafe7db122043503686c68
```

The launcher started RetroArch and kept SSH alive:

```text
RetroArch: pid=1227 running comm='retroarch-knull'
launcher: pid=1056 running comm='v90s-retroarch-'
```

The important log signal is now confirmed. `plumos-v90s-retroarch.log` contains
the new retry line followed by a native `mali_fbdev` context:

```text
RetroArch 1.22.2 (Git 69a4f0ea1e)
[Core] Loading dynamic libretro core from: "/tmp/quicknes_libretro.so".
[Core] Geometry: 256x224, Aspect: 1.306, FPS: 60.00, Sample rate: 44100.00 Hz.
[Mali] GLES version = 2.
[EGL] EGL version: 1.4.
[EGL] Created shared context
[Mali] Native fbdev window rejected; retrying EGL surface with NULL native window.
[EGL] #0x300b, EGL_BAD_NATIVE_WINDOW.
[EGL] Current context
[GL] Found GL context: "fbdev_mali".
[GL] Vendor: Imagination Technologies, Renderer: PowerVR Rogue GE8300.
[GL] Version: OpenGL ES 3.2 build 1.19@6345021.
```

User visual/audio/FPS confirmation is still pending. The current process was
left running for real-device observation.

## Framebuffer Console Interference

The user reported that the old boot console output flickered behind RetroArch
and FPS still displayed around 59fps. Live process inspection confirmed that the
Step 1 framebuffer console was still running alongside RetroArch:

```text
v90s-fb-console /usr/bin/perl /usr/local/sbin/v90s-fb-console
retroarch-knull /tmp/retroarch-knulli --verbose --config /tmp/retroarch-v90s.cfg ...
```

That console writes directly to the framebuffer, so it can interfere with
RetroArch presentation and frame pacing. It was stopped by validating the
specific PID cmdline before sending TERM; SSH and RetroArch remained running:

```text
stopping fb-console pid=1432 cmd=/usr/bin/perl /usr/local/sbin/v90s-fb-console
fb-console stopped
RetroArch: pid=1227 running comm='retroarch-knull'
```

`scripts/v90s-retroarch-launch.sh` now stops only a validated
`v90s-fb-console` process before starting RetroArch. This is not a fallback
route; it prevents the diagnostic console from drawing over the emulator.

At the user's request, RetroArch was then restarted with the updated launcher.
The live transfer helper first had to stop the existing RetroArch process,
because Linux refused to overwrite the currently executing
`/tmp/retroarch-knulli`. `scripts/live-transfer-retroarch-knulli.sh` now runs
the existing safe stop script before copying files.

Restart result:

```text
RetroArch: pid=2536 running comm='retroarch-knull'
launcher: pid=2194 running comm='v90s-retroarch-'
RetroArch 1.22.2 (Git 69a4f0ea1e)
[Mali] Native fbdev window rejected; retrying EGL surface with NULL native window.
[GL] Found GL context: "fbdev_mali".
```

User FPS confirmation after removing the framebuffer console is pending.

## Periodic Log Mirror

The user then reported that the audio dropout sounded like a regular one-second
or periodic interruption. Live process inspection found one launcher child doing
periodic work:

```text
2533 2194 v90s-retroarch- /bin/sh /tmp/v90s-retroarch-launch.sh
2694 2533 sleep           sleep 5
```

This is the launcher's periodic log mirror. It copies logs to FAT/userdata and
runs `sync` every five seconds while RetroArch is running. Even though the
period is five seconds rather than one second, that SD-card I/O is a plausible
audio/frame pacing disturbance, so it was stopped by validating that it was a
child of the launcher:

```text
stopping periodic log mirror pid=2533 ppid=2194 cmd=/bin/sh /tmp/v90s-retroarch-launch.sh
```

After the stop, the relevant remaining userspace processes were only SSH,
`wpa_supplicant`, the RetroArch launcher parent, and RetroArch itself:

```text
sshd
wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant/wpa_supplicant.conf
v90s-retroarch- /bin/sh /tmp/v90s-retroarch-launch.sh
retroarch-knull /tmp/retroarch-knulli --verbose --config /tmp/retroarch-v90s.cfg ...
```

`scripts/v90s-retroarch-launch.sh` now disables the periodic log mirror by
default. Set `PLUMOS_V90S_PERIODIC_LOG_MIRROR=1` only when a hang/crash needs
continuous FAT log preservation.
