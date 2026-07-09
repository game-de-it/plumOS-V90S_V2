# Step 2 RetroArch Plan

Date: 2026-07-09

## Goal

Run RetroArch on the POWKIDDY V90S from the generated SD-card image with:

- NES test ROM booting in RetroArch
- video output visible on the internal LCD
- stable 60fps gameplay target
- audible audio output
- V90S built-in controls usable in game

## Test ROM

The local test ROM is intentionally outside git:

```text
artifacts/nes/Super Mario Bros..nes
```

`artifacts/` must stay ignored. Build scripts may consume files from this directory when present, but repository commits must not include ROM contents.

## Current Baseline

Step 1 is complete with:

```text
output/images/plumos-v90s-armbian-step1-20260709-15-fb-text-fat-logs.img
sha256: f26b6391af990a7b4637054d5558d3794fd50250674fb3b9ec68ed94e1d52f24
```

Confirmed device capabilities:

- direct Debian payload boot works
- `/dev/fb0` is visible on the LCD
- `/dev/input/event*` can be opened from userspace
- USB keyboard input reaches userspace
- FAT logs are available under `/Volumes/KNULLI/plumos-logs/`
- `/dev/snd` exists in diagnostic logs, but audio output is not validated yet

## Approach

Keep the KNULLI/stock V90S kernel and boot chain for now. Add a Step 2 userspace payload that can launch RetroArch instead of the framebuffer console.

Initial implementation route:

1. Add a Step 2 rootfs profile based on the current Debian/Armbian-path minbase.
2. Add RetroArch plus one NES libretro core, preferring Debian arm64 packages first for the fastest proof.
3. If Debian packages do not provide a usable framebuffer/audio/input path, use KNULLI/Buildroot sources as the next reference path instead of full KNULLI image generation.
4. Keep FAT near 33MB. If RetroArch/core packages do not fit in 64MB userdata, grow userdata only as much as needed.
5. Copy the test ROM from `artifacts/nes/` into the image at build time when present.
6. Log RetroArch stdout/stderr and launch environment to FAT under `/boot/plumos-logs/`.

## First Implementation Snapshot

The first Step 2 image uses Debian bookworm arm64 packages:

- `retroarch`
- `libretro-nestopia`
- `alsa-utils`
- `input-utils`
- `procps`
- `psmisc`
- `kmod`

Debian bookworm did not provide `libretro-fceumm` from the default package index in the assembly container, so the first NES core is `nestopia_libretro.so`. This is heavier than ideal but keeps the first proof on the Armbian/Debian path.

The first generated image is:

```text
output/images/plumos-v90s-armbian-step2-20260709-1-retroarch-debian.img
sha256: d31d2913b1792bc4979e55a1437d7d9aedd60c84af11be613b4c0d3387df39a7
```

Partition sizing:

- FAT boot-resource: 33MB
- userdata: 512MB

Payload sizing:

- uncompressed rootfs: 947MB
- squashfs: 399MB

The launcher tries RetroArch with `fbdev` first, then `sdl2` fallbacks, and writes verbose logs to FAT. If RetroArch exits, Debian init falls back to the known framebuffer console.

The real-device test of this first image showed that the Debian package route is not enough for display. Boot, payload handoff, ROM discovery, and Nestopia core loading all worked, but Debian RetroArch did not include `fbdev`, and the V90S runtime did not expose a usable KMS/DRM path. The next route is to use KNULLI's A133 graphics stack: PowerVR GE8300 userspace, the A133 kernel modules/firmware, patched SDL2 framebuffer EGL support, and a RetroArch binary built for that stack.

The second generated image is a PowerVR initialization probe:

```text
output/images/plumos-v90s-armbian-step2-20260709-2-pvr-probe.img
sha256: eb5de70bc4d9c289a0add25fedb2316cb9939b72847c328cf3291f567af40953
```

Partition sizing remains small:

- FAT boot-resource: 33MB
- userdata: 512MB

This image adds the KNULLI A133 PowerVR GE8300 userspace libraries, `pvrsrvkm.ko`, `dc_sunxi.ko`, `rgx.*` firmware, and `/usr/local/sbin/v90s-pvr-probe`. It writes `plumos-v90s-pvr-probe.log` to FAT before launching RetroArch. If PowerVR initializes, the next build should add KNULLI's patched SDL2 framebuffer EGL route or a KNULLI-built RetroArch binary. If it does not, fix module/firmware/userspace initialization first.

The real-device test of the second image showed that `pvrsrvkm.ko` and `dc_sunxi.ko` can load, `/dev/dri/*` appears, and dmesg reports `RGX Device registered` plus `Found usable fbdev device`. The remaining PowerVR init issue was that the probe ran `pvrsrvctl --start` outside `/lib/modules/4.9.191`, while KNULLI's a133 `rcS` does `cd /lib/modules/4.9.191` first so `pvrsrvctl` can find `pvrsrvkm.ko` and `dc_sunxi.ko` by relative filename.

The real-device test of the third image confirmed that this corrected sequence works: `pvrsrvctl-start-cwd-moddir rc=0`, `/sys/kernel/debug/pvr/status` reports `Driver Status: OK` and `Firmware Status: OK`, and `gpu00/debug_dump` reports `Services State: OK` plus `Comparison of UM/KM components: MATCHING`. RetroArch still cannot display because the Debian stock SDL2/RetroArch stack lacks KNULLI's fbdev EGL path. The next build should therefore focus on patched SDL2 `mali-fbdev` support and/or a KNULLI-built RetroArch binary.

The fourth generated image keeps Debian RetroArch but adds a KNULLI-derived SDL2 2.30.6 build with the V90S `mali` video driver and a small `v90s-sdl2-video-probe` diagnostic:

```text
output/images/plumos-v90s-armbian-step2-20260709-4-pvr-sdl2-mali.img
sha256: 8153fb1c692fb665386aeab502ae3b054d3fd512eab17d851de8de2a83dfc108
```

The launcher now runs the SDL2 probe with `SDL_VIDEODRIVER=mali` before RetroArch and then tries `video_driver=sdl2` with `SDL_VIDEODRIVER=mali` first. If the probe succeeds but Debian RetroArch still fails, the next branch is to build/import KNULLI's RetroArch binary with `--enable-mali_fbdev`.

The real-device test of the fourth image proved the custom SDL2 path: `SDL_VIDEODRIVER=mali`, `current_video_driver=mali`, `SDL_CreateWindow ok`, `SDL_GL_CreateContext ok`, and `joystick[0]=adc_gamepad`. Debian RetroArch then reached attempt 1 with `video_driver=sdl2` and `SDL_VIDEODRIVER=mali`, but did not return to the launcher and did not leave `plumos-v90s-retroarch.log` on FAT. The next build should add a timed RetroArch attempt for better logs and move toward KNULLI's RetroArch build/patches rather than more SDL2/PVR probing.

## Runtime Investigation Targets

Video:

- Identify the best RetroArch video driver for this kernel: `fbdev`, `sdl2`, or another non-X11 path.
- Prove that the image is not black with a real-device photo.
- Record reported frame timing or FPS output in logs.

Audio:

- Inspect `/dev/snd`, ALSA cards, and mixer controls on device.
- Prefer ALSA output first.
- Confirm audible output on real hardware.
- Keep audio-open success separate from audible sound confirmation.

Input:

- Map V90S built-in controls from `/dev/input/event*`.
- Keep USB keyboard as a diagnostic fallback only.
- Confirm in-game Start, D-pad movement, and A/B actions.

Performance:

- Target stable 60fps for the NES test ROM.
- Record FPS evidence from RetroArch logs or on-screen FPS.
- If below 60fps, separate video driver cost, audio sync/blocking, and CPU frequency before changing emulator/core settings.

## Validation Criteria

Step 2 is complete when the user confirms on V90S hardware:

- `Super Mario Bros..nes` boots in RetroArch
- gameplay is visible on the LCD
- FPS is approximately 60fps, with no obvious frame pacing issue
- audio is audible
- V90S built-in controls can start the game and control Mario
- FAT logs contain RetroArch launch/config/runtime evidence

## Expected FAT Logs

```text
/Volumes/KNULLI/plumos-logs/plumos-v90s-diag.log
/Volumes/KNULLI/plumos-logs/plumos-v90s-debian-init.log
/Volumes/KNULLI/plumos-logs/plumos-v90s-retroarch-launch.log
/Volumes/KNULLI/plumos-logs/plumos-v90s-retroarch.log
```

## First Tasks

- Keep `artifacts/` ignored.
- Confirm local test ROM presence.
- Inventory available RetroArch packaging/build options for arm64.
- Add a Step 2 rootfs profile or launch mode.
- Build the first RetroArch image with verbose FAT logging.
- Run the image on device and analyze FAT logs.
