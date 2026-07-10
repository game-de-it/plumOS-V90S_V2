# Step 2 StockOS Video Runtime Success

Date: 2026-07-10

## Result

The V90S was booted from:

```text
output/images/plumos-v90s-stockos-ra-20260710-1.img
```

The live device was then patched over SSH at `192.0.2.120` with the
StockOS-derived RetroArch video timing defaults.

User-observed result:

```text
fps, scrolling, and audio pitch are perfect.
```

This is the first Step 2 result where RetroArch video pacing, scrolling, audio
pitch, audible output, and controller operation are all considered good on real
V90S hardware.

## Snapshot

Runtime snapshot:

```text
output/device-logs/runtime-snapshots/stockos-video-perfect-20260710/snapshot.txt
sha256: e679f66c51d153ddd92dc31f7459111c34a16bc439709a68511e131122955336
lines: 1449
```

## OS Runtime

Kernel:

```text
Linux 4.9.191 #17 SMP PREEMPT Tue May 13 18:14:09 UTC 2025 aarch64
```

Userspace:

```text
Debian GNU/Linux 12 bookworm
```

Boot command line includes the StockOS/Batocera partition contract:

```text
root=/dev/mmcblk0p6 rootwait init=/sbin/init
partitions=boot-resource@mmcblk0p1:env@mmcblk0p2:env-redund@mmcblk0p3:boot@mmcblk0p4:batocera@mmcblk0p5:rootfs@mmcblk0p6:rootfs_data@mmcblk0p7
```

Mounted runtime layout:

```text
/dev/mmcblk0p6  /boot          ext4      ro
/dev/mmcblk0p5  /overlay/base  squashfs  ro
/dev/loop0      /overlay/vendor squashfs ro
overlay         /              overlay   rw, tmpfs upper
/run            tmpfs
/tmp            tmpfs
```

Important caveat: `rootfs_data` / `SHARE` exists as `/dev/mmcblk0p7`, but it is
not mounted in this runtime snapshot. The live `/mnt/share` RetroArch config and
logs are therefore on the tmpfs-backed overlay for this boot. The reproducible
path is to bake the route and launcher defaults into the p5 squashfs, as done by
`plumos-v90s-stockos-ra-20260710-2-stockos-video.img`.

Loaded hardware/runtime modules:

```text
8821cu
dc_sunxi
pvrsrvkm
```

Network:

```text
USB Wi-Fi dongle via rtl8821cu/8821cu
OpenSSH reachable at 192.0.2.120
```

CPU governor during the successful run:

```text
ondemand
current sample: 816000 kHz
min: 408000 kHz
max: 1800000 kHz
```

## Display And GPU

Framebuffer:

```text
fb0 mode: U:640x480p-60
virtual_size: 640,960
bits_per_pixel: 32
stride: 2560
```

Interrupt sample from the running game:

```text
display_delta=593 display_hz=59.06375
pvr_delta=1186 pvr_hz=118.12749
```

RetroArch GL path:

```text
video_driver = "gl"
video_context_driver = "mali_fbdev"
```

RetroArch log confirms:

```text
GL context: fbdev_mali
GL vendor: Imagination Technologies
GL renderer: PowerVR Rogue GE8300
GL version: OpenGL ES 3.2 build 1.19@6345021
```

The local `mali_fbdev` NULL native window retry is active and expected:

```text
Native fbdev window rejected; retrying EGL surface with NULL native window.
```

## RetroArch Runtime

Active process:

```text
/usr/local/bin/retroarch --verbose \
  --config /mnt/share/retroarch/retroarch-v90s.cfg \
  -L /usr/lib/aarch64-linux-gnu/libretro/quicknes_libretro.so \
  /roms/nes/Super Mario Bros..nes
```

RetroArch:

```text
Version: 1.22.2 (Git 69a4f0ea1e) Jul 9 2026
```

Core:

```text
QuickNES
/usr/lib/aarch64-linux-gnu/libretro/quicknes_libretro.so
```

Content:

```text
/roms/nes/Super Mario Bros..nes
core geometry: 256x224
core fps: 60.00
core sample rate: 44100.00 Hz
```

Route file:

```text
/etc/plumos-v90s-retroarch-route
```

Known-good route values:

```text
PLUMOS_V90S_RETROARCH_BIN=/usr/local/bin/retroarch
PLUMOS_V90S_RETROARCH_START_MODE=content
PLUMOS_V90S_VIDEO_DRIVER=gl
PLUMOS_V90S_VIDEO_CONTEXT_DRIVER=mali_fbdev
PLUMOS_V90S_VIDEO_THREADED=true
PLUMOS_V90S_VIDEO_REFRESH_RATE=58.917103
PLUMOS_V90S_VRR_RUNLOOP_ENABLE=true
PLUMOS_V90S_INPUT_DRIVER=sdl2
PLUMOS_V90S_JOYPAD_DRIVER=sdl2
PLUMOS_V90S_AUDIO_DRIVER=alsa
PLUMOS_V90S_SDL_VIDEODRIVER=mali
PLUMOS_V90S_SDL_RENDER_DRIVER=software
```

Known-good RetroArch config values:

```text
video_driver = "gl"
video_context_driver = "mali_fbdev"
video_refresh_rate = "58.917103"
video_threaded = "true"
threaded_data_runloop_enable = "true"
vrr_runloop_enable = "true"
video_vsync = "true"
video_swap_interval = "1"
video_hard_sync = "false"
video_shader_enable = "false"
fps_show = "true"
```

Audio config:

```text
audio_driver = "alsa"
audio_device = "hw:0,0"
audio_latency = "64"
audio_sync = "true"
audio_out_rate = "48000"
audio_rate_control = "true"
audio_rate_control_delta = "0.005000"
audio_max_timing_skew = "0.050000"
```

Input config:

```text
input_driver = "sdl2"
input_joypad_driver = "sdl2"
adc_gamepad is used through RetroArch fallback/autoconfig behavior.
```

## Audio Runtime

ALSA playback device:

```text
card 0: audiocodec
device 0: SUNXI-CODEC sun50iw10codec-0
```

During the successful run:

```text
/proc/asound/card0/pcm0p/sub0/status
state: RUNNING
owner_pid: RetroArch pid 1364
```

RetroArch log:

```text
ALSA playback device: hw:0,0
sample format: S16_LE
period: 4 periods per buffer, 768 frames
buffer size: 3072 frames
Audio: Started synchronous audio driver
```

Mixer values from the successful run:

```text
codec hub mode = hub_enable
DAC Swap = On
ADC Swap = Off
digital volume = 0
DAC volume = 160,160
ADC volume = 160,160
Headphone Switch = on
Headphone Volume = 2
HpSpeaker Switch = on
LINEOUT Switch = on
LINEOUT Output Select = DAC_SINGLE
LINEOUT volume = 26
MIC1/MIC2 gain volume = 31
ADCL/ADCR MIC Boost = on
```

## Reproducible Image

The live patch was applied to the currently booted `-1` image, but the same
defaults were also baked into:

```text
output/images/plumos-v90s-stockos-ra-20260710-2-stockos-video.img
sha256: 609ecafc95bb84283aa627c5c48fe4a5a469a6617f97b16eff9ddabf74d24596
```

That image should be treated as the first reproducible known-good candidate for
Step 2. It still needs a clean boot-from-SD validation pass to prove the baked
defaults reproduce the live-patched success after a cold boot.

## Step 2 Status

Confirmed on the live device:

- RetroArch launches.
- NES ROM launches with QuickNES.
- Internal LCD displays gameplay.
- Built-in controls operate RetroArch/gameplay.
- Audio output is audible.
- FPS, scrolling, and audio pitch are user-confirmed perfect after applying the
  StockOS video timing defaults.

Remaining follow-up:

- Mount or otherwise persist `rootfs_data` / `SHARE` so user RetroArch settings
  survive reboots without relying only on baked defaults.
- Clean-boot test `plumos-v90s-stockos-ra-20260710-2-stockos-video.img`.
