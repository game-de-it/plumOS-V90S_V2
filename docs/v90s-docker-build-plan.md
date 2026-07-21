# V90S Docker Build Plan

Date: 2026-07-10

Status: Historical build-system plan. The current four-partition ownership and
update behavior are defined by `docs/plumos-v90s-distribution-policy.md` and
`docs/plumos-v90s-update-contract.md`. Commands below that describe the old
seven-partition/FAT32 app-layer flow are retained only as implementation
history.

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
./scripts/capture-v90s-vendor-runtime-adb.sh --force
./scripts/docker-build.sh vendor-runtime
```

The capture command reads the currently running known-good V90S SD through
plumOS ADB. It is only required when the ignored vendor input is missing or is
being deliberately refreshed.

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
./scripts/docker-build.sh userland
./scripts/docker-build.sh network-services
./scripts/docker-build.sh sdl2-powervr
./scripts/docker-build.sh retroarch
./scripts/docker-build.sh cores
./scripts/docker-build.sh frontend
./scripts/docker-build.sh system-rootfs ...
./scripts/docker-build.sh app-layer ...
./scripts/docker-build.sh sd-image ...
./scripts/docker-build.sh release ...
```

The release-system image keeps the validated p5 squashfs byte-for-byte:

```sh
./scripts/docker-build.sh sd-image \
  --rootfs-squashfs output/system-rootfs/v90s/plumos-v90s-system-rootfs.squashfs \
  --no-rootfs-repack \
  --app-layer-dir output/app-layer/v90s \
  --share-size 4096M \
  --name plumos-v90s-system-squashfs-20260715-5.img
```

The no-repack path validates `/boot`, `/overlay`, `/proc`, `/sys`, and `/dev`
because the StockOS boot ramdisk moves its early mounts into those paths before
switching to the system rootfs.

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
./scripts/docker-build.sh userland
./scripts/docker-build.sh network-services
./scripts/docker-build.sh pyxel-runtime
./scripts/docker-build.sh frontend
./scripts/docker-build.sh app-layer --strict
```

This writes `output/app-layer/v90s/` with `VERSION`, `COMPAT_VENDOR`,
`MOUNT_PATH`, `manifest.json`, `checksums.sha256`, standard user data
directories, the MMF-derived V90S frontend, BusyBox/command tools,
SSH/FTP/SFTP/Samba service payloads, RetroArch, the complete 118-core V90S
catalog, SDL2 PowerVR private libraries, the pinned AArch64 Pyxel environment,
and the current known-good RetroArch defaults template. SSH logins prefer
`/mnt/plumos/bin` and then
`/mnt/plumos/gnu/bin` in PATH. Files are copied without symlinks so the tree can
be placed on FAT32.

The `network-services` target builds its BusyBox userland dependency first and
copies `busybox`, `tcpsvd`, and `ftpd` into the network-services artifact. This
keeps the FTP runtime atomic with its controller. A strict app-layer manifest
sets `complete=true`; release packaging rejects manifests with missing optional
components.

The canonical core output is the complete set:

```sh
./scripts/docker-build.sh cores
# output/libretro-cores/v90s/cores: 118 cores
```

Filtered development builds never replace that directory implicitly:

```sh
./scripts/docker-build.sh cores --filter quicknes
# output/libretro-cores/v90s-filtered/quicknes
```

Use `--out-dir` for a specifically named diagnostic artifact. A filtered build
targeting `output/libretro-cores/v90s` is rejected unless the destructive
intent is made explicit with `--replace-canonical`. `--stage-existing` can
reconstruct package outputs from already-built AArch64 recipe trees without a
source rebuild. Strict app-layer generation requires at least 118 cores, so a
one-core diagnostic output cannot be accepted as a release/image app layer.

RetroArch is app-layer-owned and the FE route must resolve its binary as
`/mnt/plumos/bin/retroarch`; `/usr/local/bin/retroarch` is a legacy squashfs
path and is not a valid release default. Shared-library real files remain on
FAT32, while `config/standalone/soname-links.tsv` is used to create the normal
Linux SONAME aliases under `/run/plumos/retroarch/lib` at launch time. Strict
app-layer generation verifies that the mapping and all referenced real files
are present.

Implemented update-only release target:

```sh
./scripts/docker-build.sh release
```

This packages `output/app-layer/v90s/` into
`dist/plumos-v90s-update-VERSION/`, `.tar.gz`, and `.zip`, plus archive
SHA256SUMS. This is intentionally update-only until the final p6/p7 FAT32 app
layer partition is validated.

Implemented PicoArch and standalone targets:

```sh
./scripts/docker-build.sh picoarch
./scripts/docker-build.sh standalone
```

`picoarch` builds the pinned AArch64 PicoArch frontend and SDL12 compatibility
runtime. It deliberately reuses the 64-bit core set under
`/mnt/plumos/cores` instead of producing or copying a second core set.

Reserved next target:

```sh
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
p7 rootfs_data / SHARE FAT32
```

The current assembler is:

```sh
./scripts/docker-build.sh sd-image \
  --name plumos-v90s-stockos-smoke-20260710-1.img
```

For current development images, the app layer can be copied into p7 `SHARE`:

```sh
./scripts/docker-build.sh frontend
./scripts/docker-build.sh app-layer --strict
./scripts/docker-build.sh system-rootfs
./scripts/docker-build.sh sd-image \
  --app-layer-dir output/app-layer/v90s \
  --rootfs-squashfs output/system-rootfs/v90s/plumos-v90s-system-rootfs.squashfs \
  --share-size 4096M \
  --name plumos-v90s-stockos-frontend-YYYYMMDD-N.img
```

The assembler defaults p7 `PLUMOS` to 4096MB FAT32 so the full generated app
layer can be included in a development image. This is still a hardware
validation point: the final release layout should keep the FAT32 app/update/data
partition mounted at `/mnt/plumos`, but real-device boot evidence decides
whether p7 remains the final location.

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
