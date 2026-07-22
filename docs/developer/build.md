# Docker Build Guide

## Requirements

- Git
- Docker with enough free space for AArch64 sources and images
- vendor input under `artifacts/vendor/v90s-stockos-r1/`
- release signing key only when producing official update packages

All target builds enter through `scripts/docker-build.sh`. The Docker image is
`plumos-v90s-toolchain:dev` by default and targets `linux/arm64`.

## Build Image and Inspect Targets

```sh
./scripts/docker-build.sh image
./scripts/docker-build.sh --help
./scripts/docker-build.sh shell
```

`artifacts/` is input-only and ignored. Generated files go to `output/` or
`dist/`, also ignored. Build scripts, recipes, pins, patches, manifest schemas,
and public update keys stay tracked.

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
