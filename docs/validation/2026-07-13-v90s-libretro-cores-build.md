# 2026-07-13 V90S Libretro Cores Build

## Goal

Build libretro cores through the V90S build system instead of relying on the
old QuickNES-only development target.

The normal entry point is now:

```sh
./scripts/docker-build.sh cores
```

The implementation follows the MMF-style recipe approach, but the V90S recipes
target the aarch64 userspace and use native upstream libretro build arguments
instead of MMF/A30 armhf-specific options.

## Default Core Set

`PLUMOS_CORE_FILTER=v90s` builds the Class A core set:

```text
quicknes
fceumm
gambatte
genesis_plus_gx
snes9x2005
mednafen_pce_fast
```

Class B recipes are present for follow-up work, but are not part of the default
V90S build yet:

```text
nestopia
picodrive
mgba
gpsp
snes9x
mednafen_supergrafx
```

Picodrive remains Class B because the V90S aarch64 `platform=unix` build hit
upstream libchdr/lzma source layout and include issues. It should be patched
before being promoted into the default core set.

## Build Outputs

Core build output:

```text
output/libretro-cores/v90s/cores/*.so
output/libretro-cores/v90s/info/*.info
output/libretro-cores/v90s/logs/*.log
output/libretro-cores/v90s/libretro-cores.manifest
output/libretro-cores/v90s/checksums.sha256
```

App-layer integration output:

```text
output/app-layer/v90s/cores/*.so
output/app-layer/v90s/info/*.info
output/app-layer/v90s/licenses/libretro-cores-manifest.txt
output/app-layer/v90s/licenses/libretro-cores-checksums.sha256
```

The frontend launch wrappers now export:

```text
PLUMOS_V90S_LIBRETRO_DIR=/mnt/plumos/cores
PLUMOS_V90S_LIBRETRO_INFO_DIR=/mnt/plumos/info
```

## Validation Commands

Syntax checks:

```sh
bash -n docker/plumos-v90s-toolchain/scripts/build-libretro-cores.sh \
  scripts/docker-build.sh \
  scripts/build-app-layer.sh \
  scripts/build-frontend.sh
```

Recipe selection:

```sh
docker/plumos-v90s-toolchain/scripts/build-libretro-cores.sh --list
```

Result:

```text
quicknes          A
fceumm            A
gambatte          A
genesis_plus_gx   A
snes9x2005        A
mednafen_pce_fast A
```

Build:

```sh
./scripts/docker-build.sh cores
```

Result:

```text
created: output/libretro-cores/v90s
built: 6
failed: 0
skipped: 6
```

Core checksums:

```sh
cd output/libretro-cores/v90s
sha256sum -c checksums.sha256
```

Result: all files verified OK.

Architecture check:

```sh
file output/libretro-cores/v90s/cores/*_libretro.so
```

Result: all six default cores are `ELF 64-bit LSB shared object, ARM aarch64`
and stripped.

App-layer integration:

```sh
./scripts/docker-build.sh frontend
./scripts/docker-build.sh app-layer --strict
cd output/app-layer/v90s
sha256sum -c checksums.sha256
```

Result: frontend and app-layer builds succeeded; app-layer checksums verified
OK.

## Core Hashes

```text
b72b989c8a8c6bdda65ab1611b82c7165e3d16e764dd91b3101debc95457d3a6  fceumm_libretro.so
6f197f761480bd20110ace1ab0a2ddd332ad3b409ae3d9fdfccbe36538b51fff  gambatte_libretro.so
9f4b47c652972f6a238be31ea4be27b5180072ac1497af8dc7b1297e56d6a8b2  genesis_plus_gx_libretro.so
a01507a8ec385d1bc3f8de7a1db3fdbe49f4ff693ecaa9f0a0a6bd66c1636cac  mednafen_pce_fast_libretro.so
ee43cbe69885acf45cd6e6cf3364e958fe6052a8da0e7eb603384bbfbf98361e  quicknes_libretro.so
c31ef6013ebc6ac2055db278d729377d21174b8d4e6c5e75984bd25be147e0a3  snes9x2005_libretro.so
```

## Status

Pass for local Docker build and app-layer packaging.

Real-device runtime validation for the newly added non-NES cores remains a
separate V90S test item.
