# V90S Frontend Port Build Validation

Date: 2026-07-10

## Scope

Port the plumOS-MMF frontend into the V90S distribution shape.

The V90S port keeps the MMF frontend source structure but builds the generic
fbdev controller UI for arm64. MMF-specific GFX and SDL1 renderer paths are not
used for V90S.

## Implemented Build Path

```text
scripts/docker-build.sh frontend
```

Output:

```text
output/frontend/v90s/
output/frontend/v90s/frontend.manifest
output/frontend/v90s/checksums.sha256
output/frontend/v90s/plumos/bin/plumos-frontend-launch
output/frontend/v90s/plumos/bin/plumos-controller-ui-fbdev
output/frontend/v90s/plumos/bin/plumos-retroarch-launch
```

The frontend payload is merged into the app layer by:

```text
scripts/docker-build.sh app-layer --strict
```

Output:

```text
output/app-layer/v90s/
output/app-layer/v90s/manifest.json
output/app-layer/v90s/checksums.sha256
```

## Runtime Contract

On device, the frontend root is:

```text
/mnt/plumos
```

The boot/frontend launcher is:

```text
/mnt/plumos/bin/plumos-frontend-launch
```

The frontend starts:

```text
/mnt/plumos/bin/plumos-controller-ui-v90s
```

The V90S wrapper runs the fbdev frontend binary:

```text
/mnt/plumos/bin/plumos-controller-ui-fbdev --renderer fbdev
```

ROM launch goes through:

```text
/mnt/plumos/bin/plumos-retroarch-launch
```

That bridge translates the MMF frontend launch contract into the existing V90S
RetroArch launcher environment:

```text
PLUMOS_V90S_RETROARCH_BIN=/mnt/plumos/bin/retroarch
PLUMOS_V90S_CORE=/mnt/plumos/cores/quicknes_libretro.so
PLUMOS_V90S_RETROARCH_CONFIG_PATH=/mnt/plumos/config/retroarch/retroarch-v90s.cfg
PLUMOS_V90S_SDL2_POWERVR_DIR=/mnt/plumos/lib/plumos-sdl2-powervr
```

The default NES system uses:

```text
launch_profile=retroarch:quicknes
```

PicoArch and standalone launchers are present only as explicit stubs. They log
that the V90S runtime is not implemented yet and exit with code 69.

## Build Results

Frontend build:

```text
created: output/frontend/v90s
launcher: output/frontend/v90s/plumos/bin/plumos-frontend-launch
```

The built frontend binaries are arm64 Linux ELF binaries.

App-layer build:

```text
created: output/app-layer/v90s
version: 0.1.0-dev
compat_vendor: v90s-stockos-r1
mount_path: /mnt/plumos
```

App-layer inventory:

```text
files=334
frontend manifest entries=319
symlinks=0
```

Checksum validation:

```text
cd output/app-layer/v90s
sha256sum -c checksums.sha256
```

Result:

```text
OK
```

## Launch Plan Smoke Test

A temporary empty NES file was created in the ignored app-layer output and then
removed after the test.

Command shape:

```text
PLUMOS_ROOT=/workspace/output/app-layer/v90s \
PLUMOS_SDCARD_ROOT=/workspace/output/app-layer/v90s \
output/app-layer/v90s/bin/plumos-text-ui launch nes nes/test.nes \
  --profile retroarch:quicknes --no-scan
```

Important output:

```text
retroarch: /workspace/output/app-layer/v90s/bin/plumos-retroarch-launch (exists)
core: /workspace/output/app-layer/v90s/cores/quicknes_libretro.so (exists)
rom_exists: yes
can_execute: yes
```

## Release Package

Generated:

```text
dist/plumos-v90s-update-0.1.0-dev/
dist/plumos-v90s-update-0.1.0-dev.tar.gz
dist/plumos-v90s-update-0.1.0-dev.zip
dist/plumos-v90s-update-0.1.0-dev-SHA256SUMS
```

Archive checksum validation:

```text
cd dist
sha256sum -c plumos-v90s-update-0.1.0-dev-SHA256SUMS
```

Result:

```text
plumos-v90s-update-0.1.0-dev.tar.gz: OK
plumos-v90s-update-0.1.0-dev.zip: OK
```

## Boot Hook

The current development Debian init now probes p7/p6 for a plumOS app layer and
mounts the first valid candidate at:

```text
/mnt/plumos
```

The app layer is considered valid when these files exist:

```text
/mnt/plumos/manifest.json
/mnt/plumos/checksums.sha256
/mnt/plumos/bin/plumos-frontend-launch
```

When present, init starts:

```text
PLUMOS_ROOT=/mnt/plumos PLUMOS_SDCARD_ROOT=/mnt/plumos \
  /mnt/plumos/bin/plumos-frontend-launch
```

For current StockOS-compatible development images, the app layer can be copied
into p7 `SHARE` with:

```text
scripts/docker-build.sh sd-image --app-layer-dir output/app-layer/v90s ...
```

This is a compatibility route for frontend boot testing. The final release
layout still needs the validated FAT32 app/update/data partition.

## Real Device Status

Real V90S frontend boot validation has not been performed yet.

The next hardware validation should check:

- frontend appears after boot
- V90S built-in controls navigate the frontend
- NES ROM list is detected under `/mnt/plumos/Roms/nes`
- launching a NES ROM starts RetroArch through the known-good PowerVR route
- RetroArch settings persist under `/mnt/plumos/config/retroarch`
