# V90S lowercase roms/bios roots

Date: 2026-07-11

## Goal

Formalize SD1 user content roots for V90S as lowercase StockOS/Batocera-style
directories:

```text
/mnt/plumos/roms
/mnt/plumos/bios
```

The frontend ROM scanner should use `/mnt/plumos/roms` as the only ROM root.
System-specific compatibility, such as `FC` and `nes` for NES/Famicom, stays in
`config/frontend/systems.json` `directory_aliases`.

## Changes

- `scripts/build-app-layer.sh` creates `roms/` and `bios/`.
- `scripts/build-frontend.sh` wrapper defaults create/use `roms/` and `bios/`.
- `scripts/build-release.sh` checks `roms/` for accidental private ROM files.
- `src/frontend/plumos_library_scan.c` scans only `$PLUMOS_SDCARD_ROOT/roms`.
- `src/frontend/plumos_frontend.c` reads `roms/recentlist.json`.
- `package/frontend-v90s/plumos/config/frontend/systems.json` labels `FC` as a
  Miyoo-style alias and `nes` / `famicom` as EmulationStation-style aliases.
- `docs/plumos-v90s-distribution-policy.md` records the content-root policy.
- `TODO.md` tracks this as completed app-layer work.

## Validation

Commands:

```sh
git diff --check
./scripts/docker-build.sh frontend
./scripts/docker-build.sh app-layer --strict
(cd output/app-layer/v90s && sha256sum -c checksums.sha256)
./scripts/docker-build.sh release
./scripts/docker-build.sh sd-image \
  --boot0 output/device-live/raw-boot-chain/plumos-v90s-stockos-ra-20260710-2-stockos-video.img/boot0.bin \
  --boot-package output/device-live/raw-boot-chain/plumos-v90s-stockos-ra-20260710-2-stockos-video.img/boot-package.bin \
  --rootfs-squashfs output/rootfs-step2-appfat/debian-bookworm-retroarch-knulli-step2.squashfs \
  --app-layer-dir output/app-layer/v90s \
  --share-size 1024M \
  --name plumos-v90s-appfat-1g-roms-bios-lower-20260711-1.img
```

Docker scan check:

```text
system nes                roms=1 thumbnails=0
summary alias_dirs=1 files_seen=1 matched=1 roms=1 thumbnails=0 elapsed_ms=1
"path": "/tmp/.../roms/FC/lower.nes"
```

The same check also staged `/tmp/.../Roms/FC/upper.nes`; it was not scanned.

Generated app-layer directories:

```text
output/app-layer/v90s/bios
output/app-layer/v90s/roms
```

Generated release directories:

```text
dist/plumos-v90s-update-0.1.0-dev/bios
dist/plumos-v90s-update-0.1.0-dev/roms
```

Hashes:

```text
a97b1532d7a9a7c45566f603afac84cc5e6155b00f75be92a8e3e85e8ffff68c  output/app-layer/v90s/manifest.json
9958acbc76ad716509df8b31fe2b5df516344decfb7a50eca0ed55d2330873f4  output/frontend/v90s/plumos/bin/plumos-library-scan
d121cc44703a0ba0201299fdf19753ca59ecf4b32205584cf9d12d4c2d08d254  output/frontend/v90s/plumos/config/frontend/systems.json
38d00c54fb3d7a94507feabb193c2e18b79089f9020c384317cede69d2f47a40  output/images/plumos-v90s-appfat-1g-roms-bios-lower-20260711-1.img
3ae0ae27543f3e67cba7e68805498f59a3fbc96c36629891a35ce2f92b9037e4  dist/plumos-v90s-update-0.1.0-dev.zip
```

Image:

```text
output/images/plumos-v90s-appfat-1g-roms-bios-lower-20260711-1.img
sha256=38d00c54fb3d7a94507feabb193c2e18b79089f9020c384317cede69d2f47a40
manifest=output/images/plumos-v90s-appfat-1g-roms-bios-lower-20260711-1.img.manifest.txt
share_size=1024M
app_layer_manifest_sha256=a97b1532d7a9a7c45566f603afac84cc5e6155b00f75be92a8e3e85e8ffff68c
```

Known warning:

```text
plumos_text_ui.c: warning: '%ld' directive output may be truncated
```

This is an existing warning unrelated to the ROM/BIO root change.
