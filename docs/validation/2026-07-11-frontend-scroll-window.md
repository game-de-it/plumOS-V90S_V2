# V90S Frontend Scroll Window

Date: 2026-07-11

## Trigger

The user reported that when frontend settings screens contain many entries, the
cursor can move outside the visible screen area. The requested behavior is the
MMF-like behavior where the list moves so the selected item remains visible.

The user also noted that future Japanese and French UI text can be longer than
the current English labels, so V90S settings/menu rows should use a smaller
font scale, around 2x, to reduce overflow risk.

## Change

Updated `src/frontend/plumos_controller_ui.c`:

- Added a V90S fbdev row-capacity helper based on the active framebuffer height.
- Reserved footer space for settings-style screens that draw `footer1` and
  `footer2`, so rows are not hidden underneath the footer band.
- Added a scroll-window helper that shifts the emitted list range as the cursor
  moves down.
- Applied the scroll window to:
  - START menu
  - settings screens
  - Wi-Fi scan result list
  - thumbnail/scraping result list

Updated `src/frontend/plumos_fbdev_renderer.h`:

- Changed generic settings/menu-family row rendering from 3x font to 2x font.
- Kept the same TOP/ROM graphic rendering paths.

For a 640x480 V90S framebuffer, the fbdev helper now exposes approximately:

```text
settings/menu without footer: 16 rows
settings/menu with footer:    14 rows
non-settings text list:       15 rows
```

This keeps the cursor visible while leaving more horizontal space for future
localized strings.

## Build Verification

Commands:

```sh
git diff --check
./scripts/docker-build.sh frontend
./scripts/docker-build.sh app-layer --strict
(cd output/app-layer/v90s && sha256sum -c checksums.sha256)
```

Result:

- `git diff --check`: OK
- frontend build: OK
- app-layer build: OK
- app-layer checksum verification: all files OK

Known unrelated warning:

```text
plumos_text_ui.c: snprintf '%ld' output may be truncated into cores_buf
```

Frontend artifact hashes:

```text
53eb3b95e9c72b433069b7da4322375c830dae27041a6b5a8afe2e0cf37475d1  output/frontend/v90s/plumos/bin/plumos-controller-ui-fbdev
9347714e4fd7946e6339b6a21b041db9dca00285fbe0add3a03e55ab8fd68dc2  output/frontend/v90s/frontend.manifest
a1dddbec6480c15964323aab17af1f0b818b3106b6bd712ea6e6181e995d30eb  output/frontend/v90s/checksums.sha256
```

App-layer hashes:

```text
53eb3b95e9c72b433069b7da4322375c830dae27041a6b5a8afe2e0cf37475d1  output/app-layer/v90s/bin/plumos-controller-ui-fbdev
f73b236379e8ade4a18f85ac8057c948aeedc4c785111b371f3591783a3fc72b  output/app-layer/v90s/manifest.json
279ae9519d2e6a1a5dfa48df8d63afbdf0b333d1babf718c343d6061c97f725b  output/app-layer/v90s/checksums.sha256
```

## Live Deploy

Device:

```text
root@192.0.2.120
```

Deployed file:

```text
/mnt/plumos/bin/plumos-controller-ui-fbdev
sha256=53eb3b95e9c72b433069b7da4322375c830dae27041a6b5a8afe2e0cf37475d1
```

Previous device binary was preserved as:

```text
/mnt/plumos/bin/plumos-controller-ui-fbdev.bak-20260608-062322
sha256=fd17bd4dcb1cc6f4c1a2234d3c8ae9bd10aecfb45a75dbf72085d59d57acedc1
```

Frontend restart used only the PID-scoped frontend helper:

```text
plumos-frontend-stop: pid=1592 cmd=/mnt/plumos/bin/plumos-controller-ui-fbdev --renderer fbdev
plumos-frontend-stop: TERM pid=1592
plumos-frontend-stop: pid=1892 cmd=/mnt/plumos/bin/plumos-controller-ui-fbdev --renderer fbdev
```

Runtime framebuffer status after restart:

```text
geometry 640 480 640 960 32
mode "640x480-59"
V: 58.955 Hz
```

## SD Image

Command:

```sh
./scripts/docker-build.sh sd-image \
  --boot0 output/device-live/raw-boot-chain/plumos-v90s-stockos-ra-20260710-2-stockos-video.img/boot0.bin \
  --boot-package output/device-live/raw-boot-chain/plumos-v90s-stockos-ra-20260710-2-stockos-video.img/boot-package.bin \
  --rootfs-squashfs output/rootfs-step2-appfat/debian-bookworm-retroarch-knulli-step2.squashfs \
  --app-layer-dir output/app-layer/v90s \
  --share-size 1024M \
  --name plumos-v90s-appfat-1g-fe-scroll-20260711-1.img
```

Generated image:

```text
output/images/plumos-v90s-appfat-1g-fe-scroll-20260711-1.img
sha256=7cdddf73c9c9f33cd69309c59dd79c1722538cc9df905cdea4419d7ef966cb32
```

Next user-visible check: open a settings screen with many entries and confirm
that the cursor remains visible as it moves down, with the list scrolling
underneath the selection.
