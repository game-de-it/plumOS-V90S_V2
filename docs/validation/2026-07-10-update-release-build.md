# Update Release Build Validation

Date: 2026-07-10

## Purpose

Validate the first update-only release package for the FAT32 app layer.

## Commands Run

```sh
sh -n scripts/build-release.sh
bash -n scripts/docker-build.sh
./scripts/docker-build.sh release --help
./scripts/docker-build.sh release
(cd dist && sha256sum -c plumos-v90s-update-0.1.0-dev-SHA256SUMS)
(cd dist/plumos-v90s-update-0.1.0-dev && sha256sum -c release-checksums.sha256)
find dist/plumos-v90s-update-0.1.0-dev -type l -print
find dist/plumos-v90s-update-0.1.0-dev/Roms -type f -print
```

## Results

Generated:

```text
dist/plumos-v90s-update-0.1.0-dev/
dist/plumos-v90s-update-0.1.0-dev.tar.gz
dist/plumos-v90s-update-0.1.0-dev.zip
dist/plumos-v90s-update-0.1.0-dev-SHA256SUMS
```

Validation:

- archive SHA256SUMS passed
- release payload `release-checksums.sha256` passed
- no symlinks were present
- no ROM files were present under `Roms/`
- `release-manifest.json` records:
  - `type=update-only`
  - `version=0.1.0-dev`
  - `compat_vendor=v90s-stockos-r1`
  - `copy_target=/mnt/plumos`

Archive sizes observed:

```text
plumos-v90s-update-0.1.0-dev.tar.gz  7.5M
plumos-v90s-update-0.1.0-dev.zip     7.5M
```

## Notes

This is not a full SD-root release yet. It is only the copy-over update package
for the future FAT32 app layer.
