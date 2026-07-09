# Device Test: Step 2 PowerVR SDL2 Mali

Date: 2026-07-09

## Tested Image

```text
output/images/plumos-v90s-armbian-step2-20260709-4-pvr-sdl2-mali.img
sha256: 8153fb1c692fb665386aeab502ae3b054d3fd512eab17d851de8de2a83dfc108
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
```

`plumos-v90s-retroarch.log` was not present on the FAT partition. The launcher reached the first RetroArch attempt, but did not log an exit status or the final `all attempts failed` line.

## PowerVR Result

PowerVR still starts successfully:

```text
===== pvrsrvctl-start-cwd-moddir =====
Using default driver configuration (no powervr.ini present)
===== pvrsrvctl-start-cwd-moddir rc=0 =====
```

debugfs still reports a healthy driver/firmware state:

```text
Driver Status:   OK
Firmware Status: OK
Server Errors:   0
Comparison of UM/KM components: MATCHING
```

dmesg still confirms the fbdev window system:

```text
PVR_K: Read BVNC 22.102.54.38 from HW device registers
PVR_K: RGX Device registered with BVNC 22.102.54.38
[drm] Initialized pvr 1.19.6345021 20170530 on minor 0
Found usable fbdev device
xres x yres      = 640x480
xres x yres (v)  = 640x960
flipping?        = 1
```

## SDL2 Mali Probe Result

The custom SDL2 runtime was detected:

```text
retroarch-launch: custom SDL2 mali runtime detected
video_drivers=dummy mali offscreen
retroarch-launch: LD_LIBRARY_PATH=/usr/lib/powervr:/usr/local/lib/plumos-sdl2-mali:...
```

The real-device SDL2 probe succeeded:

```text
sdl2-probe: compiled=2.30.6 linked=2.30.6
sdl2-probe: SDL_VIDEODRIVER=mali
sdl2-probe: video_driver[0]=mali
sdl2-probe: current_video_driver=mali
sdl2-probe: joysticks=1
sdl2-probe: joystick[0]=adc_gamepad
MALI_CreateWindow:0xaaaacbff0280 done.
sdl2-probe: SDL_CreateWindow ok
sdl2-probe: SDL_GL_CreateContext ok
sdl2-probe: ok
===== sdl2-video-probe-mali rc=0 =====
```

This is a major improvement: the KNULLI-derived SDL2 `mali` video driver can open the V90S fbdev PowerVR path and create an OpenGL ES context on real hardware. Built-in controls are also visible to SDL2 as `adc_gamepad`.

## RetroArch Result

RetroArch and the NES content were found:

```text
RetroArch: Frontend for libretro -- v1.14.0 -- b2ceb50 --
SDL2            - SDL2 input/audio/video drivers: yes
EGL             - Video context driver: yes
ALSA            - Audio driver: yes
selected_core=/usr/lib/aarch64-linux-gnu/libretro/nestopia_libretro.so
selected_rom=/roms/nes/Super Mario Bros..nes
0b3d9e1f01ed1668205bab34d6c82b0e281456e137352e4f36a9b2cfa3b66dea  /roms/nes/Super Mario Bros..nes
```

The launcher then started the first attempt:

```text
retroarch-launch: attempt=1 video=sdl2 input=sdl2 joypad=sdl2 audio=alsa sdl_video=mali
```

There is no later line such as:

```text
retroarch-launch: attempt=1 exited rc=...
retroarch-launch: all attempts failed
```

This means the Debian RetroArch process did not return to the launcher before the device was powered down or the SD card was removed. It is no longer the previous "missing video driver" failure.

## Conclusion

The SDL2/PowerVR fbdev EGL path is now proven on hardware. The current blocker has moved to Debian RetroArch itself: it starts with the SDL2/mali runtime but does not produce a visible RetroArch screen or return an exit code.

Two follow-ups are useful:

1. Add a timed RetroArch attempt with an explicit pre-launch sync so `plumos-v90s-retroarch.log` survives even if RetroArch hangs.
2. Build or import KNULLI's RetroArch path, including the SDL GL context workaround and `--enable-mali_fbdev`, because the generic Debian RetroArch binary is now the suspicious layer.
