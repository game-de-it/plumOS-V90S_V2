# Device Test: Step 2 PowerVR Probe

Date: 2026-07-09

## Tested Image

```text
output/images/plumos-v90s-armbian-step2-20260709-2-pvr-probe.img
sha256: eb5de70bc4d9c289a0add25fedb2316cb9939b72847c328cf3291f567af40953
```

User result:

- RetroArch did not appear on the V90S LCD.
- SD card was returned to macOS and FAT logs were inspected.

## FAT Logs Present

```text
/Volumes/KNULLI/plumos-logs/session.txt
/Volumes/KNULLI/plumos-logs/plumos-v90s-diag.log
/Volumes/KNULLI/plumos-logs/plumos-v90s-debian-init.log
/Volumes/KNULLI/plumos-logs/plumos-v90s-pvr-probe.log
/Volumes/KNULLI/plumos-logs/plumos-v90s-retroarch-launch.log
/Volumes/KNULLI/plumos-logs/plumos-v90s-retroarch.log
```

## Confirmed Working

Boot chain and Debian payload handoff still work:

```text
payload-share: mounted /dev/mmcblk0p5 as ext4 on /payload_share
payload-root: attached payload to /dev/loop2
payload-root: mounted Debian payload rootfs
boot: preparing to switch directly to payload /sbin/init
```

Debian init ran the PowerVR probe before RetroArch:

```text
debian-init: starting PowerVR probe
debian-init: PowerVR probe exited rc=0
debian-init: starting RetroArch launcher
```

Framebuffer remains usable:

```text
fb0 modes=U:640x480p-60
fb0 virtual_size=640,960
fb0 bits_per_pixel=32
fb0 stride=2560
```

Input and audio devices are still present:

```text
adc_gamepad -> /dev/input/event4
audiocodec playback -> /dev/snd/pcmC0D0p
```

## PowerVR Result

The PowerVR kernel-side path made real progress. Manual `insmod` loaded both modules and created DRM nodes:

```text
insmod-pvrsrvkm rc=0
insmod-dc_sunxi rc=0
/dev/dri/card0
/dev/dri/controlD64
/dev/dri/renderD128
dc_sunxi ... Live
pvrsrvkm ... Live
```

dmesg also shows the GPU and fbdev display class path registering:

```text
PVR_K: Read BVNC 22.102.54.38 from HW device registers
PVR_K: RGX Device registered with BVNC 22.102.54.38
[drm] Initialized pvr 1.19.6345021 20170530 on minor 0
Found usable fbdev device
xres x yres      = 640x480
xres x yres (v)  = 640x960
flipping?        = 1
```

The first probe still ran `pvrsrvctl --start` from the wrong working directory. KNULLI's a133 `rcS` changes to `/lib/modules/4.9.191` before running `pvrsrvctl --start`, because this userspace loader looks for `pvrsrvkm.ko` and `dc_sunxi.ko` by relative filename:

```text
Failed to load pvrsrvkm.ko: No such file or directory
```

The next probe image should run:

```sh
cd /lib/modules/4.9.191
pvrsrvctl --start
```

before falling back to manual `insmod`.

## RetroArch Result

RetroArch still finds the ROM and NES core:

```text
selected_core=/usr/lib/aarch64-linux-gnu/libretro/nestopia_libretro.so
selected_rom=/roms/nes/Super Mario Bros..nes
0b3d9e1f01ed1668205bab34d6c82b0e281456e137352e4f36a9b2cfa3b66dea  /roms/nes/Super Mario Bros..nes
```

The RA failure is still video initialization, not content loading:

```text
Couldn't find any video driver named "fbdev"
Available video drivers are: gl, sdl2, xvideo, x11, null
[DRM]: Found 0 connectors.
[KMS]: Couldn't find a suitable DRM device.
[SDL_GL]: Failed to set video mode: eglQueryDevicesEXT is missing
[Video]: Cannot open video driver
```

The stock Debian SDL2/RetroArch path still lacks KNULLI's `mali-fbdev` SDL2 backend. The probe did prove that the PVR/fbdev kernel modules are close enough to continue toward that path.

## Follow-up

Implemented after this analysis:

- Run `pvrsrvctl --start` from `/lib/modules/4.9.191`.
- Mount debugfs before probing `/sys/kernel/debug/pvr`.
- Remove the final `SDL_VIDEODRIVER=dummy` RetroArch attempt because it can run headless without showing anything useful.

Next image should verify whether `pvrsrvctl --start` completes cleanly. If it does, move to a patched SDL2 or KNULLI-built RetroArch payload.
