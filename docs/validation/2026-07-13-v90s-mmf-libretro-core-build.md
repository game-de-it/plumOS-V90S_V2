# V90S MMF-Compatible Libretro Core Build

Date: 2026-07-13

## Goal

Build the same source-built libretro core payload that plumOS MMF currently
produces, using the V90S build system and native aarch64 toolchain image.

## MMF Reference

Reference output:

```text
/Users/example/plumOS-MMF/dist/plumos-libretro-cores/plumos/retroarch/cores
```

Observed MMF built core count:

```text
41 *_libretro.so
```

This corresponds to the MMF recipe table's plumOS A/B set:

```text
A: 37 recipes
B: 4 recipes
```

The MMF recipe table also contains an `O` class for Onion/MMF-compatible catalog
entries. Those recipes are now present in the V90S recipe table, but they are
not part of this validated default build.

## V90S Build Command

The default `cores` target now uses `PLUMOS_CORE_FILTER=plumos`, matching the
MMF default A/B build set.

Validated command:

```sh
PLUMOS_CORE_FILTER=plumos FAIL_ON_CORE_ERROR=1 JOBS=4 ./scripts/docker-build.sh cores
```

Result:

```text
created: output/libretro-cores/v90s
built: 41
failed: 0
skipped: 61
```

Output checks:

```text
output/libretro-cores/v90s/cores: 41 *_libretro.so
output/libretro-cores/v90s/info: 41 *.info
sha256sum -c output/libretro-cores/v90s/checksums.sha256: OK
```

MMF/V90S filename comparison:

```text
mmf 41 v90s 41
missing_in_v90s []
extra_in_v90s []
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

App-layer checks:

```text
output/app-layer/v90s/cores: 41 *_libretro.so
output/app-layer/v90s/info: 41 *.info
```

## Notes

- The V90S recipe table is aligned with MMF recipe IDs, repositories, refs, and
  classes, but uses native aarch64/Linux build arguments.
- MMF-derived patches are copied into
  `docker/plumos-v90s-toolchain/patches/` and applied with dry-run guards so
  repeated builds skip already-integrated or layout-mismatched patches instead
  of stopping interactively.
- `easyrpg` requires `libfmt-dev` and `libpixman-1-dev` in the V90S Docker
  toolchain image.
- The `O` class can be selected with `PLUMOS_CORE_FILTER=class-o`, and the full
  catalog with `PLUMOS_CORE_FILTER=all`.
- Follow-up: the MMF final package filename set is validated separately in
  `docs/validation/2026-07-13-v90s-mmf-final-package-core-build.md`.
