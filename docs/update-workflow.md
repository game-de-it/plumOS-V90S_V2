# plumOS V90S Update Workflow

This document describes the intended copy-over update flow for the FAT32 app
layer.

## Current Package

The update-only package is generated with:

```sh
./scripts/docker-build.sh app-layer --strict
./scripts/docker-build.sh release
```

Outputs:

```text
dist/plumos-v90s-update-VERSION/
dist/plumos-v90s-update-VERSION.tar.gz
dist/plumos-v90s-update-VERSION.zip
dist/plumos-v90s-update-VERSION-SHA256SUMS
```

The current package is not a full SD image. It is the contents that should be
copied over the future FAT32 app-layer partition mounted on-device at:

```text
/mnt/plumos
```

## macOS

1. Shut down the V90S before removing the SD card.
2. Insert the SD card into the Mac.
3. Open the FAT32 plumOS app-layer volume in Finder.
4. Extract `plumos-v90s-update-VERSION.zip` or `.tar.gz`.
5. Copy the extracted package contents onto the FAT32 volume, replacing existing
   files when prompted.
6. Eject the SD card from Finder before removing it.

## Windows

1. Shut down the V90S before removing the SD card.
2. Insert the SD card into the PC.
3. Open the FAT32 plumOS app-layer drive in Explorer.
4. Extract `plumos-v90s-update-VERSION.zip`.
5. Copy the extracted package contents onto the FAT32 drive, replacing existing
   files when prompted.
6. Use "Safely Remove Hardware" before removing the SD card.

## Safety Rules

- Do not copy private ROMs into release packages.
- Do not copy Wi-Fi credentials, SSH keys, or root passwords into release
  packages.
- Do not rely on symlinks in the app layer; FAT32 does not preserve them.
- Keep `COMPAT_VENDOR` equal to `v90s-stockos-r1` until the vendor runtime is
  intentionally revised.
- Validate `checksums.sha256` or `release-checksums.sha256` when debugging a
  failed update.
