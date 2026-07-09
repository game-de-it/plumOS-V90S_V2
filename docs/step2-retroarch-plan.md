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
