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

## KNULLI-Style RetroArch Config

The user asked whether the RetroArch `.cfg` could be aligned with KNULLI. KNULLI
does not keep a single V90S-specific static RA config in the source tree; it
generates one through `knulli-configgen`. The relevant KNULLI sources are:

```text
package/system/knulli-configgen/configs/configgen-defaults-a133.yml
package/system/knulli-configgen/configgen/configgen/generators/libretro/libretroConfig.py
package/system/knulli-configgen/configgen/configgen/generators/libretro/libretroRetroarchCustom.py
```

The notable A133/libretro differences from our minimal cfg were:

```text
gfxbackend=gl
video_threaded=true
retroarch.audio_driver=alsathread
input_driver=udev
input_joypad_driver=udev
fps_show=false
audio_latency=64
```

Added local test config:

```text
configs/retroarch/v90s-knulli-a133-nes.cfg
```

It is KNULLI A133/libretro-style with paths adapted to the current Debian
payload, and with `video_context_driver=mali_fbdev` pinned so the patched GE8300
fbdev path is used.

`scripts/v90s-retroarch-launch.sh` now supports an explicit external config via
`PLUMOS_V90S_RETROARCH_CONFIG`. `scripts/live-transfer-retroarch-knulli.sh` can
transfer and use one with:

```text
./scripts/live-transfer-retroarch-knulli.sh 192.0.2.118 --config configs/retroarch/v90s-knulli-a133-nes.cfg
```

Live result:

```text
external_config=/tmp/v90s-knulli-a133-nes.cfg
copied external RetroArch config from /tmp/v90s-knulli-a133-nes.cfg
RetroArch: pid=3492 running comm='retroarch-knull'
```

The active cfg on the device contains:

```text
video_driver = "gl"
video_context_driver = "mali_fbdev"
video_threaded = "true"
audio_driver = "alsathread"
audio_latency = "64"
input_driver = "udev"
input_joypad_driver = "udev"
fps_show = "false"
```

RetroArch accepted the config and stayed on the native GE8300 route:

```text
RetroArch 1.22.2 (Git 69a4f0ea1e)
[Input] Found input driver: "udev".
[Mali] Native fbdev window rejected; retrying EGL surface with NULL native window.
[GL] Found GL context: "fbdev_mali".
[Input] Found joypad driver: "udev".
[Audio] Set audio input rate to: 44100.00 Hz.
[Audio] Started synchronous audio driver.
```

User confirmation of display smoothness, audio continuity, and controls is
pending.

The first KNULLI-style config used KNULLI configgen's final libretro input
defaults:

```text
input_driver = "udev"
input_joypad_driver = "udev"
input_autodetect_enable = "false"
```

The user reported that controls stopped working. This means the current Debian
payload does not yet carry KNULLI's full udev/autoconfig controller database for
the V90S `adc_gamepad`, even though RetroArch can open the udev driver.

The live config was adjusted to keep the KNULLI A133 video/audio settings but
return input to the previously working SDL2 route:

```text
video_driver = "gl"
video_context_driver = "mali_fbdev"
video_threaded = "true"
audio_driver = "alsathread"
audio_latency = "64"
input_driver = "sdl2"
input_joypad_driver = "sdl2"
input_autodetect_enable = "true"
fps_show = "false"
```

Restart result:

```text
RetroArch: pid=3961 running comm='retroarch-knull'
[Input] Found input driver: "sdl2".
[GL] Found GL context: "fbdev_mali".
[Input] Found joypad driver: "sdl2".
[Audio] Started synchronous audio driver.
```

User confirmation of input recovery is pending.

The user then reported that Start did not work and the key mapping still seemed
wrong. The problem was that the first SDL2 recovery kept Xbox-like fixed button
numbers:

```text
start_btn=9
select_btn=8
dpad_btn=13..16
```

KNULLI's bundled EmulationStation controller database maps the local GPIO
controller differently:

```text
.cache/knulli-linux/package/emulationstation/knulli-emulationstation/controllers/es_input.cfg
GPIO Controller 1:
  b=0
  a=1
  x=2
  y=3
  pageup=4
  pagedown=5
  select=6
  start=7
  hotkey=8
  left/right=axis 0
  up/down=axis 1
```

The live V90S input device is:

```text
/dev/input/event4
NAME="adc_gamepad"
PRODUCT=19/133/1190/0
PHYS="rocknix-singleadc-joypad/input0"
```

`configs/retroarch/v90s-knulli-a133-nes.cfg` was changed to keep SDL2 input but
bind that GPIO mapping explicitly:

```text
input_autodetect_enable = "false"
input_player1_analog_dpad_mode = "0"
input_enable_hotkey_btn = "8"
input_player1_a_btn = "1"
input_player1_b_btn = "0"
input_player1_x_btn = "2"
input_player1_y_btn = "3"
input_player1_l_btn = "4"
input_player1_r_btn = "5"
input_player1_select_btn = "6"
input_player1_start_btn = "7"
input_player1_left_axis = "-0"
input_player1_right_axis = "+0"
input_player1_up_axis = "-1"
input_player1_down_axis = "+1"
```

This config was transferred and RetroArch was restarted:

```text
./scripts/live-transfer-retroarch-knulli.sh 192.0.2.118 --config configs/retroarch/v90s-knulli-a133-nes.cfg
RetroArch: pid=4974 running comm='retroarch-knull'
input_autodetect_enable = "false"
input_player1_start_btn = "7"
input_player1_left_axis = "-0"
[Input] Found input driver: "sdl2".
[Input] Found joypad driver: "sdl2".
[Audio] Started synchronous audio driver.
```

User confirmation of Start, d-pad, and A/B behavior is pending.

The user then observed that the physical Start button was recognized as Select.
Only Start/Select were swapped and the test config was transferred again:

```text
input_player1_select_btn = "7"
input_player1_start_btn = "6"
```

Live verification showed the updated config in `/tmp/retroarch-v90s.cfg` and a
new RetroArch process:

```text
RetroArch: pid=5431 running comm='retroarch-knull'
input_player1_select_btn = "7"
input_player1_start_btn = "6"
[Input] Found input driver: "sdl2".
[Input] Found joypad driver: "sdl2".
```

User confirmation of the physical Start/Select behavior after this swap is
pending.
