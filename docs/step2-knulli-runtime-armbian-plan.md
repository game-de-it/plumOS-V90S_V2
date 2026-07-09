# Step 2 KNULLI Runtime And Armbian Build Plan

Date: 2026-07-09

Update 2026-07-10: this document records the KNULLI/Armbian-era reasoning that
led to the working boot/runtime path. The current build-system direction is now
`docs/v90s-docker-build-plan.md`: use the user's StockOS/Batocera extraction as
the vendor runtime baseline and build plumOS userspace with a V90S-specific
Docker toolchain.

## Goal

Reproduce KNULLI's V90S video/audio runtime closely enough that RetroArch can run
NES at smooth 60fps with audio and built-in controls, while moving the rootfs
generation path toward the Armbian build framework.

The current mainline-A133 kernel spike is paused. Without UART, the reboot and
black-screen loops are too expensive to debug right now. The productive path is
to keep the proven KNULLI V90S boot chain and kernel, then replace the userspace
in controlled steps.

## Proven On Real Hardware

- KNULLI boot chain and Linux 4.9.191 boot to our payload.
- FAT boot-resource can stay small at 33MB; larger rootfs payloads live on the
  userdata/rootfs partition.
- Framebuffer drawing and the custom framebuffer console work on the LCD.
- USB keyboard and built-in V90S controls are visible.
- USB Wi-Fi dongle and SSH work, so no-reflash iterations should happen over
  SSH.
- PowerVR GE8300 startup works when launched from the correct module directory.
- KNULLI-derived SDL2 `mali` video driver can create an EGL/GLES context on the
  V90S LCD.
- KNULLI-derived `asound.state` values make the internal speaker path audible.
- KNULLI-pinned QuickNES stops the audio breakup seen with Nestopia.
- The user's modified StockOS image runs RetroArch through Batocera's generated
  config with QuickNES, `video_refresh_rate=58.917103`,
  `vrr_runloop_enable=true`, `video_threaded=true`, Pulse/PipeWire audio, and a
  measured LCD cadence around 59.02 Hz while RA is running.

## Current Failure Boundary

The generic Debian RetroArch package is no longer a good final target.

It can launch, load the ROM, show video through `video_driver=sdl2` plus
`SDL_VIDEODRIVER=mali`, accept controls, and output audio after mixer setup.
However, frame pacing is not KNULLI-equivalent. `video_threaded=false` falls to
about 50fps, and `video_driver=gl` reaches the PowerVR GLES stack but then
segfaults.

This points at RetroArch's video context/windowing path rather than the kernel,
PowerVR module, SDL2 `mali` driver, input path, or ALSA path.

The StockOS comparison refined this boundary further. The visible `59 fps`
behavior matches the panel cadence instead of proving an emulator-core CPU
problem. The remaining work is to reproduce the runtime contract in layers:
first the generated RetroArch timing profile, then the Pulse/PipeWire audio
buffering path, then StockOS-like CPU governor and interrupt-balancing behavior
if the RA-only settings are not enough.

## KNULLI Runtime Contract To Reproduce

KNULLI's RetroArch package builds RetroArch `v1.22.2` and adds the native Mali
framebuffer context when a libmali provider exists:

```text
RETROARCH_CONF_OPTS += --enable-mali_fbdev
```

The V90S audio state is also device-specific. KNULLI ships:

```text
board/allwinner/a133/powkiddy-v90s/boot/asound.state
```

The state enables `DAC Swap`, `Headphone Switch`, `HpSpeaker Switch`, and
`LINEOUT Switch`, with the speaker route made active by the A133 audio init
script. Our launcher should keep a single explicit V90S mixer profile based on
the values that produced audible game audio.

For NES validation, prefer KNULLI's pinned QuickNES commit:

```text
058d66516ed3f1260b69e5b71cd454eb7e9234a3
```

The rootfs builder now treats QuickNES as required for RetroArch payloads. If
the core is missing, image generation fails instead of silently using a heavier
core.

## Armbian Build Role

For this phase, Armbian is the rootfs/userspace build framework, not the kernel
replacement. The image should continue using:

- KNULLI V90S boot assets and Android-style `boot.img`
- KNULLI/stock Linux 4.9.191 kernel
- KNULLI A133/V90S PowerVR modules and firmware
- GE8300 fbdev/glibc userspace libraries
- KNULLI-derived SDL2 `mali` runtime
- KNULLI-equivalent RetroArch with `--enable-mali_fbdev`

The Armbian checkout is kept under `.cache/armbian-build` and is ignored by git.
Use the wrapper from the repository root:

```sh
./scripts/fetch-reference-sources.sh --with-armbian
./scripts/run-armbian-build.sh inventory
./scripts/run-armbian-build.sh inventory-boards
```

Validation on 2026-07-09:

```text
./scripts/run-armbian-build.sh inventory
result: success
runtime: 0:48 min
outputs:
  .cache/armbian-build/output/info/all_boards_all_branches.json
  .cache/armbian-build/output/info/all_userspace_inventory.json
```

The only V90S entry in the inventory is the local userpatch spike:

```text
BOARD=powkiddy-v90s-a133-mainline
BOARD_CORE_OR_USERPATCHED=userpatched
BOARDFAMILY=sun50iw10-v90s
BOARD_SUPPORT_LEVEL=wip
```

So this does not change the kernel decision. Armbian is ready to be used as a
build framework, but not as proof that an upstream A133/V90S mainline kernel
target is available.

The first useful Armbian output to pursue is a small arm64 CLI rootfs/cache that
can replace the hand-maintained debootstrap payload while preserving the V90S
boot/runtime contract above.

## Next Build Target

The next image is now a KNULLI-runtime reproduction image:

- small FAT boot-resource
- userdata/rootfs payload
- SSH enabled for live iteration
- QuickNES installed as `/usr/lib/aarch64-linux-gnu/libretro/quicknes_libretro.so`
- launcher fixed to QuickNES unless `PLUMOS_V90S_CORE` explicitly overrides it
- KNULLI mixer profile applied before RetroArch
- no automatic video/core fallback sequence
- RetroArch built/imported with `--enable-mali_fbdev`

Generated image:

```text
output/images/plumos-v90s-armbian-step2-20260709-9-knulli-retroarch.img
sha256: 68af8bc2d8cfc712718805a26ba0d188ff18f10f0b411eaf8840634d0dc86cd9
```

The current RetroArch binary is built from RetroArch `v1.22.2` with
`--enable-mali_fbdev`, `--enable-egl`, `--enable-opengles`, `--enable-sdl2`,
and `--enable-alsa`. KNULLI's package patches are not replayed yet because
`000-input_sort_devices.patch` does not apply cleanly to the checked-out tag.
That patch mismatch is tracked separately from the first video-context test.
