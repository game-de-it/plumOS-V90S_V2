# V90S Docker Build Plan

Date: 2026-07-10

## Direction

The V90S build should move away from treating Armbian or Buildroot as the main
distribution builder. They are useful references, but both are larger than what
this project currently needs.

The recommended path is a plumOS-V90S-specific Docker build environment, modeled
after `plumOS-MMF`:

```text
StockOS/Batocera runtime extraction
  -> plumOS V90S Docker toolchain
  -> RA / libretro cores / PicoArch / standalone / frontend builds
  -> small SD-card image assembly
```

The vendor runtime baseline is the user's modified POWKIDDY V90S StockOS image,
which is Batocera-derived and already proved RetroArch video, input, and audio
on the real device. KNULLI remains useful historical context, but it is no
longer the primary runtime contract for new work.

## Layering

Use three layers:

```text
1. vendor-runtime
   StockOS/Batocera-derived boot image, env partitions, Linux 4.9.191 modules,
   PowerVR GE8300 firmware/libraries, SDL2, PipeWire/Pulse/ALSA config, and
   Batocera configgen reference files.

2. build-output
   plumOS-built RetroArch, libretro cores, PicoArch, standalone emulators, and
   frontend packages.

3. image
   Small repeat-test SD-card image containing the vendor runtime and plumOS
   build outputs.
```

The prepared vendor runtime is generated from the ignored artifact:

```sh
./scripts/docker-build.sh vendor-runtime
```

Default input:

```text
artifacts/vendor/v90s-stockos-r1
```

Default prepared output:

```text
output/vendor/v90s-stockos-r1
```

The older prepared output path remains a compatibility alias during migration:

```text
output/vendor/stockos-runtime
```

## Toolchain Entry Point

The V90S build entrypoint is:

```sh
./scripts/docker-build.sh image
./scripts/docker-build.sh shell
./scripts/docker-build.sh sdl2-powervr
./scripts/docker-build.sh retroarch
./scripts/docker-build.sh cores
./scripts/docker-build.sh system-rootfs ...
./scripts/docker-build.sh app-layer ...
./scripts/docker-build.sh sd-image ...
./scripts/docker-build.sh release ...
```

`rootfs` is a transitional alias for `system-rootfs`. `stockos-image` is a
transitional alias for `sd-image` while the partition contract remains
StockOS/Batocera-compatible. The older KNULLI-style image assembler remains
available only as an explicit legacy command:

```sh
./scripts/docker-build.sh knulli-image ...
```

Implemented compatibility aliases:

```sh
./scripts/docker-build.sh quicknes
./scripts/docker-build.sh rootfs
./scripts/docker-build.sh stockos-image
./scripts/docker-build.sh retroarch-knulli
```

Implemented app-layer target:

```sh
./scripts/docker-build.sh app-layer --strict
```

This writes `output/app-layer/v90s/` with `VERSION`, `COMPAT_VENDOR`,
`MOUNT_PATH`, `manifest.json`, `checksums.sha256`, standard user data
directories, RetroArch, QuickNES, SDL2 PowerVR private libraries, and the current
known-good RetroArch defaults template. Files are copied without symlinks so the
tree can be placed on FAT32.

Implemented update-only release target:

```sh
./scripts/docker-build.sh release
```

This packages `output/app-layer/v90s/` into
`dist/plumos-v90s-update-VERSION/`, `.tar.gz`, and `.zip`, plus archive
SHA256SUMS. This is intentionally update-only until the final p6/p7 FAT32 app
layer partition is validated.

Reserved next targets:

```sh
./scripts/docker-build.sh picoarch
./scripts/docker-build.sh standalone
./scripts/docker-build.sh frontend
./scripts/docker-build.sh all
```

These should follow the MMF style: each target gets a focused script under
`docker/plumos-v90s-toolchain/scripts/`, writes into `output/` or `dist/`, and
records enough manifest/hash data to reproduce the build.

## StockOS Image Layout

The StockOS/Batocera layout observed on the user's modified V90S image is:

```text
p1 boot-resource / Volumn vfat
p2 env
p3 env-redund
p4 boot Android boot image
p5 batocera squashfs
p6 rootfs / BATOCERA ext4
p7 rootfs_data / SHARE ext4
```

The current assembler is:

```sh
./scripts/docker-build.sh sd-image \
  --name plumos-v90s-stockos-smoke-20260710-1.img
```

The first RA-capable StockOS-layout image uses the current RetroArch payload as
p5:

```sh
./scripts/docker-build.sh system-rootfs \
  --profile debian-retroarch-powervr \
  --out-dir output/rootfs-step2 \
  --rom "artifacts/nes/Super Mario Bros..nes"

./scripts/docker-build.sh sd-image \
  --rootfs-squashfs output/rootfs-step2/debian-bookworm-retroarch-powervr-step2.squashfs \
  --name plumos-v90s-stockos-ra-20260710-1.img
```

The StockOS-video-defaults variant keeps the same layout and applies the
observed StockOS RetroArch timing defaults. The same values were live-applied
to `plumos-v90s-stockos-ra-20260710-1.img`, where the user confirmed FPS,
scrolling, and audio pitch were perfect:

```sh
./scripts/docker-build.sh sd-image \
  --rootfs-squashfs output/rootfs-step2/debian-bookworm-retroarch-powervr-step2.squashfs \
  --name plumos-v90s-stockos-ra-20260710-2-stockos-video.img
```

For fast iteration, p1 defaults to `33M` instead of StockOS's larger FAT area.
The assembled smoke image uses the StockOS-derived p2/p3 env and p4 Android boot
partition from `output/vendor/v90s-stockos-r1`. If the extraction includes
raw StockOS `boot0` and `boot_package` captures, they are used automatically;
otherwise `--allow-knulli-boot-fallback` must be passed explicitly for a legacy
diagnostic image that uses the KNULLI V90S fallback assets.

## Naming

Do not use `sdl2-mali` as the plumOS-facing name. The V90S GPU is PowerVR
GE8300. Use:

```text
sdl2-powervr
/usr/local/lib/plumos-sdl2-powervr
retroarch-powervr
output/retroarch-powervr
```

Some upstream/KNULLI/Batocera implementation names still contain `mali`, such as
`SDL_VIDEODRIVER=mali` and RetroArch's `mali_fbdev` context. Those should be
treated as upstream compatibility names until the implementation itself is
renamed or replaced.

The old `retroarch-knulli` binary/output names remain compatibility aliases for
historical validation and live-transfer notes. New plumOS-facing commands should
use `retroarch`, `retroarch-powervr`, and `live-transfer-retroarch-powervr.sh`.

## RetroArch Policy

StockOS/Batocera proves that RetroArch can run well, but plumOS should not copy
Batocera's restrictive configuration behavior. The goal is:

- ship working defaults based on the StockOS runtime
- keep `retroarch.cfg` user-writable and persistent
- avoid configgen rewriting user settings on every launch
- keep diagnostics explicit instead of hiding validation behind fallback routes

The StockOS comparison showed that threaded video was part of the working
configuration. The plumOS live success kept the PowerVR `mali_fbdev` display
route and direct ALSA audio while applying the StockOS timing values:

```text
video_driver = "gl"
video_context_driver = "mali_fbdev"
video_refresh_rate = "58.917103"
vrr_runloop_enable = true
video_threaded = true
threaded_data_runloop_enable = true
audio_driver = "alsa"
audio_device = "hw:0,0"
audio_latency = 64
```

Those are the current NES/QuickNES known-good defaults. Other cores may still
need their own timing or audio validation.

## License Notice

plumOS V90S may include files derived from POWKIDDY V90S StockOS/Batocera for
device compatibility. Release packages should include a notice saying that
boot/runtime components are reused from POWKIDDY's StockOS distribution, with
Batocera and other upstream licenses preserved where applicable.
