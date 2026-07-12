# 2026-07-13 V90S MMF Final Package Core Build

## Goal

Build the V90S libretro core payload so that its packaged core filename set
matches the final plumOS MMF package, not only the smaller MMF source-built
A/B core set.

## MMF Reference

Reference package:

```text
/Users/example/plumOS-MMF/dist/plumos-mmf-package/plumos/retroarch/cores
```

Observed reference count:

```text
117 *_libretro.so
```

## V90S Build Command

Validated command:

```sh
PLUMOS_CORE_FILTER=all FAIL_ON_CORE_ERROR=1 JOBS=4 BUILD_JOB_FALLBACKS=2,1 ./scripts/docker-build.sh cores
```

Result:

```text
created: /workspace/output/libretro-cores/v90s
built: 113
failed: 0
skipped: 0
```

The V90S recipe table currently contains:

```text
A: 37
B: 4
O: 72
total: 113
```

The package output contains 117 cores because four MMF package names are
generated as explicit aliases:

```text
dosbox_pure_0.9.7_libretro.so -> dosbox_pure_libretro.so
beetle_saturn_libretro.so -> mednafen_saturn_libretro.so
km_puae_xtreme_amped_libretro.so -> puae_libretro.so
uae4arm_libretro.so -> puae2021_libretro.so
```

The two Amiga aliases are intentional for V90S. The old `KMFDManic/puae` and
`uae4arm-libretro` paths are tightly tied to old ARM/Pandora-style build
assumptions and did not produce a trustworthy aarch64 V90S build without deep
runtime-risky patching. The maintained PUAE-family aarch64 builds provide the
packaged filename compatibility while keeping the actual binary target native
to V90S.

## Filename Comparison

Comparison command:

```sh
python3 - <<'PY'
from pathlib import Path
pkg_dir = Path('/Users/example/plumOS-MMF/dist/plumos-mmf-package/plumos/retroarch/cores')
v90_dir = Path('/Users/example/plumOS-V90S_v2/output/libretro-cores/v90s/cores')
pkg = {p.name for p in pkg_dir.glob('*_libretro.so')}
v90 = {p.name for p in v90_dir.glob('*_libretro.so')}
print('mmf_pkg_cores', len(pkg))
print('v90_cores', len(v90))
print('missing', sorted(pkg - v90))
print('extra', sorted(v90 - pkg))
PY
```

Result:

```text
mmf_pkg_cores 117
v90_cores 117
missing []
extra []
```

## Architecture Spot Check

Checked representative previous failures and alias outputs:

```text
km_puae_xtreme_amped_libretro.so:            ELF 64-bit LSB shared object, ARM aarch64
uae4arm_libretro.so:                         ELF 64-bit LSB shared object, ARM aarch64
flycast_libretro.so:                         ELF 64-bit LSB shared object, ARM aarch64
km_duckswanstation_xtreme_amped_libretro.so: ELF 64-bit LSB shared object, ARM aarch64
mame2000_libretro.so:                        ELF 64-bit LSB shared object, ARM aarch64
yabasanshiro_libretro.so:                    ELF 64-bit LSB shared object, ARM aarch64
```

## App Layer Integration

Validated command:

```sh
./scripts/docker-build.sh app-layer
```

Result:

```text
created: output/app-layer/v90s
version: 0.1.0-dev
compat_vendor: v90s-stockos-r1
mount_path: /mnt/plumos
```

App-layer filename comparison:

```text
mmf_pkg_cores 117
v90_app_cores 117
missing []
extra []
```

Checksum validation:

```text
output/libretro-cores/v90s/checksums.sha256: OK
output/app-layer/v90s/checksums.sha256: OK
```

## Status

Pass for local Docker build and app-layer packaging.

Real-device runtime validation remains separate. This validation proves that
the V90S build system can reproduce the MMF final package core filename set as
native aarch64 binaries and documented compatibility aliases.
