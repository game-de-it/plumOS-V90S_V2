# App Layer Build Validation

Date: 2026-07-10

## Purpose

Validate the first policy-aligned FAT32 app-layer builder.

The app layer is generated at:

```text
output/app-layer/v90s/
```

The on-device mount path recorded in metadata is:

```text
/mnt/plumos
```

## Commands Run

```sh
sh -n scripts/build-app-layer.sh
bash -n scripts/docker-build.sh
./scripts/docker-build.sh app-layer --help
./scripts/docker-build.sh app-layer --strict
find output/app-layer/v90s -type l -print
(cd output/app-layer/v90s && sha256sum -c checksums.sha256)
```

## Results

- `app-layer --strict` succeeded.
- `COMPAT_VENDOR` is `v90s-stockos-r1`.
- `MOUNT_PATH` is `/mnt/plumos`.
- No symlinks were present in the generated tree.
- `checksums.sha256` verified all files.
- `manifest.json` recorded 13 files and no missing optional payloads.

Generated payload includes:

- `bin/retroarch`
- `cores/quicknes_libretro.so`
- `lib/plumos-sdl2-powervr/libSDL2-2.0.so.0.3000.6`
- `lib/plumos-sdl2-powervr/libSDL2-2.0.so.0`
- `lib/plumos-sdl2-powervr/libSDL2.so`
- `config/retroarch/v90s-powervr-quicknes.cfg`
- `licenses/NOTICE.txt`
- component build manifests under `licenses/`

## Notes

No real-device validation was performed for this change. The SD image still
needs mount and launch integration for `/mnt/plumos`.
