# Step 2 PowerVR SDL2 Mali Image

Date: 2026-07-09

## Purpose

The previous real-device test proved that the PowerVR kernel/userspace stack starts successfully:

```text
pvrsrvctl-start-cwd-moddir rc=0
Driver Status:   OK
Firmware Status: OK
Comparison of UM/KM components: MATCHING
```

RetroArch still failed because Debian's stock SDL2/RetroArch stack could not use the V90S fbdev PowerVR window system. This image adds a KNULLI-derived SDL2 `mali` video driver build while keeping the Debian RetroArch package for the first test.

## Build Commands

```sh
docker build -t plumos-v90s-assembly-tools docker/assembly-tools

./scripts/run-assembly-tools.sh ./scripts/build-sdl2-mali.sh \
  --out-dir output/sdl2-mali

./scripts/run-assembly-tools.sh ./scripts/build-step1-rootfs.sh \
  --profile debian-retroarch-pvr-sdl2 \
  --out-dir output/rootfs-step2-pvr-sdl2 \
  --rom artifacts/nes/'Super Mario Bros..nes'

./scripts/run-assembly-tools.sh ./scripts/assemble-v90s-image.sh \
  --rootfs output/rootfs-step1/stage1-userdata-loader.squashfs \
  --userdata-payload output/rootfs-step2-pvr-sdl2/debian-bookworm-retroarch-pvr-sdl2-step2.squashfs \
  --boot-vfat-size 33M \
  --userdata-size 512M \
  --diagnostic-init \
  --name plumos-v90s-armbian-step2-20260709-4-pvr-sdl2-mali.img
```

## Outputs

```text
output/images/plumos-v90s-armbian-step2-20260709-4-pvr-sdl2-mali.img
sha256: 8153fb1c692fb665386aeab502ae3b054d3fd512eab17d851de8de2a83dfc108
size: 581M

output/rootfs-step2-pvr-sdl2/debian-bookworm-retroarch-pvr-sdl2-step2.squashfs
sha256: 047eb8547131234b870772d5d546423c38cbcb8d094bca26829af291ecc3734d
size: 422M
```

Partition sizing:

- FAT boot-resource: 33MB
- userdata: 512MB

## Custom SDL2 Payload

The SDL2 runtime was built from SDL2 2.30.6 with KNULLI's V90S patch:

```text
.cache/knulli-linux/board/allwinner/a133/powkiddy-v90s/patches/sdl2/001-add-pvr-ge8300-mali-driver.patch
```

The configured video driver list includes:

```text
Video drivers: dummy offscreen opengl_es1 opengl_es2 mali
```

Installed runtime files:

```text
/usr/local/lib/plumos-sdl2-mali/libSDL2-2.0.so.0.3000.6
/usr/local/lib/plumos-sdl2-mali/libSDL2-2.0.so.0
/usr/local/lib/plumos-sdl2-mali/libSDL2.so
/usr/local/bin/v90s-sdl2-video-probe
```

The payload release marker contains:

```text
rootfs_profile=debian-retroarch-pvr-sdl2
power_pvr_probe=1
custom_sdl2_mali=1
rom_sha256=0b3d9e1f01ed1668205bab34d6c82b0e281456e137352e4f36a9b2cfa3b66dea
video_drivers=dummy mali offscreen
```

## Runtime Changes

`v90s-retroarch-launch` now:

- prepends `/usr/lib/powervr` and `/usr/local/lib/plumos-sdl2-mali` to `LD_LIBRARY_PATH`
- records the custom SDL2 manifest in FAT logs
- runs `/usr/local/bin/v90s-sdl2-video-probe` with `SDL_VIDEODRIVER=mali` before RetroArch
- tries RetroArch with `video_driver=sdl2` and `SDL_VIDEODRIVER=mali` first when the custom SDL2 runtime is present

## Expected FAT Logs

```text
/Volumes/KNULLI/plumos-logs/plumos-v90s-pvr-probe.log
/Volumes/KNULLI/plumos-logs/plumos-v90s-retroarch-launch.log
/Volumes/KNULLI/plumos-logs/plumos-v90s-retroarch.log
```

The key new signal is the `sdl2-video-probe-mali` section in `plumos-v90s-retroarch-launch.log`.

Best-case result:

```text
sdl2-probe: video_driver[*]=mali
sdl2-probe: current_video_driver=mali
sdl2-probe: SDL_CreateWindow ok
sdl2-probe: SDL_GL_CreateContext ok
sdl2-probe: ok
```

Then RetroArch should reach:

```text
retroarch-launch: attempt=1 video=sdl2 input=sdl2 joypad=sdl2 audio=alsa sdl_video=mali
```

If RetroArch still does not display, inspect whether the SDL2 probe succeeded. If the probe succeeds but RetroArch fails, the next branch is a KNULLI-built RetroArch binary with `--enable-mali_fbdev`. If the probe fails, repair the SDL2 fbdev/EGL path first.
