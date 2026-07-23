# Docker Build Guide

## Requirements

- Git
- Docker with at least 80 GiB of free space for AArch64 sources and images
- Internet access for Docker and emulator-source downloads
- release signing key only when producing official update packages

All target builds enter through `scripts/docker-build.sh`. The Docker image is
`plumos-v90s-toolchain:dev` by default and targets `linux/arm64`.

The sanitized and checksummed `v90s-stockos-r1` vendor input is tracked under
`artifacts/vendor/v90s-stockos-r1/`. It contains no ROM, game BIOS, save data,
personal network configuration, SSH key, or update-signing key. Vendor files
retain their original terms and are not relicensed under the plumOS MIT
license.

The checksummed non-emulator 1.0.0 baseline is also tracked under
`artifacts/release-inputs/v90s-1.0.0/`. It contains the System SquashFS,
frontend, userland, services, applications, PowerVR SDL2 runtime, and the
minimal KNULLI/GE8300 hardware inputs used by the existing build scripts.

## Clean-Clone Release Image

The supported clean-clone entry point is:

```sh
git clone REPOSITORY_URL
cd plumOS-V90S_v2
./scripts/docker-build.sh release-image --version 1.0.0
```

After the first full build, pass `--incremental` to check RetroArch, the full
libretro core set, PicoArch, and the standalone emulator set independently.
An output is reused only when its input fingerprint and artifact checksums
match. The app layer, boot payloads, SD image, and final verification are never
skipped.

```sh
./scripts/docker-build.sh release-image --version 1.0.0 --incremental
```

This command:

1. verifies and materializes the tracked non-emulator 1.0.0 baseline
2. validates and prepares the tracked vendor runtime
3. rebuilds only RetroArch, all 118 libretro cores, PicoArch, and standalone
   emulators from their existing pinned recipes
4. assembles the versioned strict app-layer from the local baseline and rebuilt
   emulator payloads
5. assembles and verifies
   `output/images/plumos-v90s-release-1.0.0-vendor-r1.img`

The target stops after the verified image and does not create signed update
packages. KNULLI and GE8300 are not downloaded by this target; the required
local subsets are part of the clone. The bundled subsets retain these source
identities:

| Input | Commit |
| --- | --- |
| KNULLI | `ac2ededdd3999443da4ba514dac22145d628f735` |
| GE8300 drivers | `3213ecb88a9e9c6813a7a6aafe78da1f055aa050` |

## Build Image and Inspect Targets

```sh
./scripts/docker-build.sh image
./scripts/docker-build.sh --help
./scripts/docker-build.sh shell
```

The sanitized `artifacts/vendor/v90s-stockos-r1/` and versioned
`artifacts/release-inputs/` baselines are tracked. All other `artifacts/` paths
are ignored, including the private update-signing key. Generated files go to
`output/` or `dist/`, also ignored. Build scripts, recipes, pins, patches,
manifest schemas, and the public update key stay tracked.

## Component Targets

```sh
./scripts/docker-build.sh vendor-runtime
./scripts/docker-build.sh boot-package
./scripts/docker-build.sh boot-image
./scripts/docker-build.sh sdl2-powervr
./scripts/docker-build.sh retroarch
./scripts/docker-build.sh cores
./scripts/docker-build.sh picoarch
./scripts/docker-build.sh standalone
./scripts/docker-build.sh userland
./scripts/docker-build.sh network-services
./scripts/docker-build.sh audio-router
./scripts/docker-build.sh nextcommander
./scripts/docker-build.sh music-player
./scripts/docker-build.sh pyxel-runtime
./scripts/docker-build.sh portmaster
./scripts/docker-build.sh frontend
```

Selected standalone emulators can be built without rebuilding the whole set:

```sh
./scripts/docker-build.sh standalone ppsspp
./scripts/docker-build.sh standalone yabasanshiro
```

The canonical core output is `output/libretro-cores/v90s/`. Filtered builds go
to `output/libretro-cores/v90s-filtered/<filter>` and must not replace the
canonical release set. Core source URLs, refs, classes, build directories, and
arguments are locked in `docker/plumos-v90s-toolchain/libretro-core-recipes.tsv`.

## Main Outputs

| Target | Output |
| --- | --- |
| `vendor-runtime` | `output/vendor/v90s-stockos-r1/` |
| `sdl2-powervr` | `output/sdl2-powervr/` |
| `retroarch` | `output/retroarch-powervr/` |
| `cores` | `output/libretro-cores/v90s/` |
| `picoarch` | `output/picoarch/v90s/` |
| `standalone` | `output/standalone-emulators/v90s/` |
| `frontend` | `output/frontend/v90s/` |
| `userland` | `output/userland/v90s/` |
| `network-services` | `output/network-services/v90s/` |
| `audio-router` | `output/audio-router/v90s/` |
| `pyxel-runtime` | `output/pyxel-runtime/v90s/` |
| `portmaster` | `output/portmaster/v90s/` |
| `system-rootfs` | `output/system-rootfs/v90s/` |
| `app-layer` | `output/app-layer/v90s/` |

## Assemble the Runtime and System

```sh
PLUMOS_V90S_APP_LAYER_VERSION=VERSION \
  ./scripts/docker-build.sh app-layer --strict

PLUMOS_V90S_SYSTEM_VERSION=VERSION \
  ./scripts/docker-build.sh system-rootfs

./scripts/docker-build.sh license-audit output/app-layer/v90s
./scripts/docker-build.sh preflight
```

Strict app-layer assembly requires the supported payload set, the canonical
core count, factory RetroArch and PPSSPP configurations, notices, licenses, and
component manifests. It writes `VERSION`, `COMPAT_VENDOR`, `RUNTIME_ABI`,
`manifest.json`, and `checksums.sha256`. `manifest.json.complete` must be true
and `missing_optional` empty for a release.

## Build and Verify the Seed Image

```sh
./scripts/docker-build.sh sd-image \
  --name plumos-v90s-four-partition-seed.img

./scripts/docker-build.sh verify-image \
  --image output/images/plumos-v90s-four-partition-seed.img
```

`sd-image` runs the four-partition preflight before assembly. The preflight
checks boot inputs, partition capacity, System A/B hashes, p3 app-layer
metadata, SD2 mount tooling, frontend startup, update tooling, network services,
USB Disk Mode, licenses, and checksums.

`stockos-image` and `knulli-image` are explicit legacy investigation paths;
they are not normal release targets.

## Signed Updates

Official packages use `update-package`, not the older copy-over `release`
archive:

```sh
./scripts/docker-build.sh update-package \
  --type runtime \
  --input output/app-layer/v90s \
  --base-dir PATH/TO/PREVIOUS/RUNTIME \
  --base-version OLD --version NEW \
  --output-dir dist/updates

./scripts/docker-build.sh update-package \
  --type system \
  --input output/system-rootfs/v90s/plumos-v90s-system-rootfs.squashfs \
  --base-version OLD --version NEW \
  --output-dir dist/updates
```

The private Ed25519 key belongs under ignored
`artifacts/update-signing/`. Only the public key under
`package/system-v90s/` is tracked. See the [update contract](../plumos-v90s-update-contract.md).

## PortMaster Audit

```sh
PLUMOS_PORTMASTER_AUDIT_JOBS=4 \
  ./scripts/docker-build.sh portmaster-audit
```

The static audit inventories official AArch64 Port metadata, launch scripts,
ELF architecture, interpreters, `DT_NEEDED` libraries, runtime-family markers,
and unresolved ABI requirements. It is a routing and packaging check, not a
substitute for physical video, audio, input, save, and exit checks.

## Live Deployment Rule

Use `scripts/deploy-app-layer-adb.sh` or an equivalent metadata-aware path.
Never push one managed binary alone. Update the corresponding checksum entry
and manifest atomically, then verify on device before restart. Preserve all
device-owned mutable paths.
