# Step 2 RetroArch Timeout Log Image

Date: 2026-07-09

## Purpose

The fourth Step 2 image proved the V90S PowerVR fbdev EGL path and the custom SDL2 `mali` video driver on real hardware, but Debian RetroArch did not return after starting attempt 1. `plumos-v90s-retroarch.log` was not left on the FAT partition.

This fifth image is a diagnostic image for that exact failure mode. It should make the RetroArch runtime log survive even if RetroArch hangs on a black screen.

## Launcher Changes

`scripts/v90s-retroarch-launch.sh` now:

- creates and syncs the RetroArch log file before any RetroArch attempt
- writes each attempt config to `plumos-v90s-retroarch.log`
- mirrors launch/runtime logs every 5 seconds while RetroArch is running
- runs RetroArch through `timeout`, defaulting to 45 seconds per attempt
- logs `attempt=N timed out after 45s` when a hang is captured
- logs process state after each attempt

The timeout can be overridden in userspace with `PLUMOS_V90S_RETROARCH_TIMEOUT_SECONDS`, but this image uses the built-in 45 second default.

## Build Commands

```sh
./scripts/run-assembly-tools.sh ./scripts/build-step1-rootfs.sh \
  --profile debian-retroarch-pvr-sdl2 \
  --out-dir output/rootfs-step2-pvr-sdl2-timeout \
  --rom "artifacts/nes/Super Mario Bros..nes"

./scripts/run-assembly-tools.sh ./scripts/assemble-v90s-image.sh \
  --rootfs output/rootfs-step1/stage1-userdata-loader.squashfs \
  --userdata-payload output/rootfs-step2-pvr-sdl2-timeout/debian-bookworm-retroarch-pvr-sdl2-step2.squashfs \
  --boot-vfat-size 33M \
  --userdata-size 512M \
  --diagnostic-init \
  --name plumos-v90s-armbian-step2-20260709-5-retroarch-timeout-log.img
```

## Artifacts

```text
output/images/plumos-v90s-armbian-step2-20260709-5-retroarch-timeout-log.img
sha256: b098ae5474b7517980810245c4227384e04a5d0a621e1e98e23e99acfb57c298
size: 581M

output/rootfs-step2-pvr-sdl2-timeout/debian-bookworm-retroarch-pvr-sdl2-step2.squashfs
sha256: 5b6af1778f050ab9f057c4263a3ebe34d038924dcacf319cc855604ffa719b8f
size: 422M
```

The FAT boot-resource partition remains 33MB. The larger image size comes from the 512MB userdata partition required by the Debian RetroArch payload.

## Build Verification

The generated rootfs contains the timeout launcher:

```text
RETROARCH_TIMEOUT_SECONDS="${PLUMOS_V90S_RETROARCH_TIMEOUT_SECONDS:-45}"
start_periodic_log_mirror()
run_retroarch()
retroarch-launch: retroarch_timeout_seconds=$RETROARCH_TIMEOUT_SECONDS
retroarch-launch: attempt=$attempt pre-launch sync complete
retroarch-launch: attempt=$attempt timed out after ${RETROARCH_TIMEOUT_SECONDS}s
processes-after-attempt-$attempt
```

The payload release file still confirms the intended Step 2 stack:

```text
rootfs_profile=debian-retroarch-pvr-sdl2
power_pvr_probe=1
custom_sdl2_mali=1
rom_path=/roms/nes/Super Mario Bros..nes
rom_sha256=0b3d9e1f01ed1668205bab34d6c82b0e281456e137352e4f36a9b2cfa3b66dea
```

## Expected FAT Logs

After the user flashes this image, boots the V90S, waits for the attempts to timeout or for the console to return, powers down, and mounts the SD card on macOS, inspect:

```text
/Volumes/KNULLI/plumos-logs/session.txt
/Volumes/KNULLI/plumos-logs/plumos-v90s-diag.log
/Volumes/KNULLI/plumos-logs/plumos-v90s-debian-init.log
/Volumes/KNULLI/plumos-logs/plumos-v90s-pvr-probe.log
/Volumes/KNULLI/plumos-logs/plumos-v90s-retroarch-launch.log
/Volumes/KNULLI/plumos-logs/plumos-v90s-retroarch.log
```

Important new markers:

```text
retroarch-launch: retroarch_timeout_seconds=45
retroarch-launch: attempt=1 video=sdl2 input=sdl2 joypad=sdl2 audio=alsa sdl_video=mali
retroarch-launch: attempt=1 pre-launch sync complete
retroarch-launch: attempt=1 exited rc=124
retroarch-launch: attempt=1 timed out after 45s
===== processes-after-attempt-1 =====
```

If `plumos-v90s-retroarch.log` is still absent, the remaining issue is earlier than RetroArch execution or FAT sync. If it exists, use the last verbose RetroArch lines to decide whether to keep debugging Debian RetroArch or switch immediately to a KNULLI-built RetroArch binary.

## KNULLI RetroArch Follow-up

The next binary route is KNULLI's RetroArch build rather than more SDL2/PVR probing:

- `.cache/knulli-linux/package/retroarch/retroarch/retroarch.mk` uses RetroArch `v1.22.2`.
- It enables SDL2 when `BR2_PACKAGE_SDL2=y`.
- It enables EGL when `BR2_PACKAGE_HAS_LIBEGL=y`.
- It adds `--enable-mali_fbdev` when `BR2_PACKAGE_HAS_LIBMALI=y`, except the RK3326/RK3568 target exclusions.
- `.cache/knulli-linux/configs/knulli-a133.board` selects `BR2_PACKAGE_POWERVR_GE8300_DRIVER=y`.
- `.cache/knulli-linux/package/gpu/powervr-ge8300-driver` provides GE8300 fbdev/glibc libEGL/libGLES and `pvrsrvctl`.

The current fifth image should provide the missing evidence before doing that heavier binary import/build.
