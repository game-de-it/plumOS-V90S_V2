# Device Test: Step 2 RetroArch Video Driver Failure

Date: 2026-07-09

## Tested Image

```text
output/images/plumos-v90s-armbian-step2-20260709-1-retroarch-debian.img
sha256: d31d2913b1792bc4979e55a1437d7d9aedd60c84af11be613b4c0d3387df39a7
```

User result:

- RetroArch did not appear on the V90S LCD.
- SD card was returned to macOS and FAT logs were inspected.

## FAT Logs Present

```text
/Volumes/KNULLI/plumos-logs/session.txt
/Volumes/KNULLI/plumos-logs/plumos-v90s-diag.log
/Volumes/KNULLI/plumos-logs/plumos-v90s-debian-init.log
/Volumes/KNULLI/plumos-logs/plumos-v90s-retroarch-launch.log
/Volumes/KNULLI/plumos-logs/plumos-v90s-retroarch.log
```

## Confirmed Working

Boot chain and payload handoff worked:

```text
payload-share: mounted /dev/mmcblk0p5 as ext4 on /payload_share
payload-root: attached payload to /dev/loop2
payload-root: mounted Debian payload rootfs
boot: preparing to switch directly to payload /sbin/init
```

Debian userspace reached `/sbin/init` and started the RetroArch launcher:

```text
debian-init: init entered before tty setup
debian-init: fb0 probe begin
debian-init: fb0 full black wrote blocks=600 bytes=2457600
debian-init: starting RetroArch launcher
```

The framebuffer remained available:

```text
fb0 modes=U:640x480p-60
fb0 virtual_size=640,960
fb0 bits_per_pixel=32
fb0 stride=2560
```

The test ROM and NES core were found:

```text
selected_core=/usr/lib/aarch64-linux-gnu/libretro/nestopia_libretro.so
selected_rom=/roms/nes/Super Mario Bros..nes
0b3d9e1f01ed1668205bab34d6c82b0e281456e137352e4f36a9b2cfa3b66dea  /roms/nes/Super Mario Bros..nes
```

RetroArch loaded the Nestopia core and content before failing video init:

```text
[INFO] [Core]: Loading dynamic libretro core from: "/usr/lib/aarch64-linux-gnu/libretro/nestopia_libretro.so"
[INFO] [Content]: Loading content file: "/roms/nes/Super Mario Bros..nes".
[libretro INFO] [Nestopia]: Machine is NTSC.
```

Input devices exist. The built-in controller appears to be `/dev/input/event4`:

```text
N: Name="adc_gamepad"
H: Handlers=event4
```

Audio hardware exists and exposes playback:

```text
card 0: audiocodec [audiocodec], device 0: SUNXI-CODEC sun50iw10codec-0 []
/dev/snd/pcmC0D0p
```

## Failure Point

The Debian bookworm RetroArch package does not include a usable framebuffer video driver for this device.

Attempt 1 and 2 requested `video_driver = "fbdev"`:

```text
[ERROR] Couldn't find any video driver named "fbdev"
[INFO] Available video drivers are:
[INFO] 	gl
[INFO] 	sdl2
[INFO] 	xvideo
[INFO] 	x11
[INFO] 	null
```

RetroArch then fell back toward GL/SDL2 paths. These also failed for the V90S runtime:

```text
[ERROR] [Wayland]: Failed to connect to Wayland server.
[ERROR] [KMS]: Couldn't find a suitable DRM device.
[ERROR] [Video]: Cannot open video driver ... Exiting ...
Fatal error received in: "video_driver_init_internal()"
```

Attempt 3 with `SDL_VIDEODRIVER=kmsdrm` exited with rc=1:

```text
retroarch-launch: attempt=3 video=sdl2 input=sdl2 joypad=sdl2 audio=alsa sdl_video=kmsdrm
retroarch-launch: attempt=3 exited rc=1
```

Attempt 4 with SDL dummy video was reached but is not useful for real display:

```text
retroarch-launch: attempt=4 video=sdl2 input=sdl2 joypad=sdl2 audio=sdl2 sdl_video=dummy
```

## Interpretation

This was not a rootfs boot failure and not a ROM/core load failure. The root cause is the video stack:

- V90S exposes `/dev/fb0`, and direct framebuffer drawing works.
- The Debian RetroArch build has no `fbdev` video driver.
- The device currently has no usable `/dev/dri` path for Debian RetroArch KMS.
- Debian SDL2 lacks KNULLI's A133/PowerVR framebuffer EGL backend patches.

KNULLI's A133 board support carries:

- `BR2_PACKAGE_POWERVR_GE8300_DRIVER=y`
- PowerVR firmware and kernel modules under the A133 overlay
- SDL2 patches adding a framebuffer EGL backend
- RetroArch build options that can use the KNULLI graphics stack

## Next Direction

The next Step 2 image should stop using Debian stock RetroArch for display proof. Better next candidates:

1. Build or extract the KNULLI A133 graphics userspace path:
   - PowerVR GE8300 userland libraries
   - `pvrsrvkm.ko`, `dc_sunxi.ko`, and `rgx.*` firmware
   - patched SDL2 with the A133 framebuffer EGL backend
   - RetroArch built against that SDL2/EGL stack
2. Keep the current Debian payload and add only the minimum KNULLI graphics/RetroArch components.
3. Keep FAT at 33MB and put any larger runtime payload in userdata.

Input and audio should remain separate follow-up proof surfaces. The logs show devices exist, but neither in-game controls nor audible output has been validated because video initialization fails first.
