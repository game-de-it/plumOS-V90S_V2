# Device Test: Step 2 PowerVR Start-CWD

Date: 2026-07-09

## Tested Image

```text
output/images/plumos-v90s-armbian-step2-20260709-3-pvr-start-cwd.img
sha256: 70f35ca82a7147a1602c8c6c7ed4f0c05e6bce481f5c24cfcff17096ca13ba11
```

User result:

- RetroArch did not appear on the V90S LCD.
- SD card was returned to macOS and FAT logs were inspected.

## FAT Logs Present

```text
/Volumes/KNULLI/plumos-logs/session.txt
/Volumes/KNULLI/plumos-logs/plumos-v90s-diag.log
/Volumes/KNULLI/plumos-logs/plumos-v90s-debian-init.log
/Volumes/KNULLI/plumos-logs/plumos-v90s-fb-console.log
/Volumes/KNULLI/plumos-logs/plumos-v90s-pvr-probe.log
/Volumes/KNULLI/plumos-logs/plumos-v90s-retroarch-launch.log
/Volumes/KNULLI/plumos-logs/plumos-v90s-retroarch.log
```

## PowerVR Result

The corrected KNULLI-style init sequence worked:

```text
===== pvrsrvctl-start-cwd-moddir =====
Using default driver configuration (no powervr.ini present)
===== pvrsrvctl-start-cwd-moddir rc=0 =====
```

The kernel modules remained loaded and DRM nodes were present:

```text
/dev/dri/card0
/dev/dri/controlD64
/dev/dri/renderD128
dc_sunxi ... Live
pvrsrvkm ... Live
```

dmesg confirms the PVR and fbdev display class path:

```text
PVR_K: Read BVNC 22.102.54.38 from HW device registers
PVR_K: RGX Device registered with BVNC 22.102.54.38
[drm] Initialized pvr 1.19.6345021 20170530 on minor 0
Found usable fbdev device
xres x yres      = 640x480
xres x yres (v)  = 640x960
flipping?        = 1
```

debugfs exposes the PowerVR driver state:

```text
/sys/kernel/debug/pvr/status
Driver Status:   OK
Firmware Status: OK
Server Errors:   0

/sys/kernel/debug/pvr/version
Driver Version: Rogue_DDK_Linux rogueddk 1.19@6345021
GPU variant BVNC: 22.102.54.38 (HW)

/sys/kernel/debug/pvr/gpu00/debug_dump
Services State: OK
Comparison of UM/KM components: MATCHING
Window system: nullws
```

This proves the current blocker is no longer basic PowerVR module loading.

## RetroArch Result

RetroArch still finds the ROM and core:

```text
selected_core=/usr/lib/aarch64-linux-gnu/libretro/nestopia_libretro.so
selected_rom=/roms/nes/Super Mario Bros..nes
0b3d9e1f01ed1668205bab34d6c82b0e281456e137352e4f36a9b2cfa3b66dea  /roms/nes/Super Mario Bros..nes
```

All display attempts still fail:

```text
attempt=1 video=fbdev ... rc=1
attempt=2 video=fbdev ... rc=1
attempt=3 video=gl ... rc=1
attempt=4 video=sdl2 ... sdl_video=mali rc=1
attempt=5 video=sdl2 ... sdl_video=kmsdrm rc=1
all attempts failed
```

The repeated RA failure is the display backend:

```text
Couldn't find any video driver named "fbdev"
Available video drivers are: gl, sdl2, xvideo, x11, null
[DRM]: Found 0 connectors.
[KMS]: Couldn't find a suitable DRM device.
[SDL_GL]: Failed to set video mode: eglQueryDevicesEXT is missing
[Video]: Cannot open video driver
```

## Conclusion

The PVR stack is initialized well enough to proceed. The next blocker is that Debian's stock SDL2/RetroArch cannot use the V90S PVR fbdev window system. The next build should add KNULLI's patched SDL2 `mali-fbdev` backend and/or a KNULLI-built RetroArch binary instead of continuing to probe Debian stock video drivers.
