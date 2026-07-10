# V90S Frontend Settings Layout Alignment

Date: 2026-07-11

## Trigger

The user reported that the V90S frontend START/settings menu did not match the
MMF-style layout. In particular, checkbox positions and selectable option
positions were visibly different.

## Finding

The V90S fbdev renderer handled generic settings pages as plain text rows:

```text
[x] Label
Label < Value >
```

That made the control portion render at the left edge of the label text. The
A30/MMF-style frontend layout splits settings rows into a left label and a
right-aligned control area, so checkboxes and `< Value >` choices line up
consistently.

## Change

Updated `src/frontend/plumos_fbdev_renderer.h` so only
`settings_screen=1` pages split settings rows before drawing:

- `[x] Label` and `[ ] Label` are rendered as `Label` plus right-aligned
  `[x]` / `[ ]`.
- `Label < Value >` rows are rendered as `Label` plus right-aligned
  `< Value >`.
- Non-settings pages, including TOP and ROM list rendering, keep their existing
  layout path.

The renderer also strips the frontend setting flash marker from the visible
control text before drawing.

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

Frontend artifact hashes:

```text
fd17bd4dcb1cc6f4c1a2234d3c8ae9bd10aecfb45a75dbf72085d59d57acedc1  output/frontend/v90s/plumos/bin/plumos-controller-ui-fbdev
fbad5401a30c285f557d02cc46f9b33e64bc59ea1fc8a17d1d4f77de92f655ee  output/frontend/v90s/frontend.manifest
34409a9f0882631afd529dcaa0ecd853812331547f63096ca5f927a4b4ad0e0d  output/frontend/v90s/checksums.sha256
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
  --name plumos-v90s-appfat-1g-fe-settings-layout-20260711-1.img
```

Generated image:

```text
output/images/plumos-v90s-appfat-1g-fe-settings-layout-20260711-1.img
sha256=7a14f44deda0b3f277e5f4ebcbadb38f72483940d98135005273af1874f6ffbe
```

Image manifest highlights:

```text
share_size=1024M
app_layer_dir=output/app-layer/v90s
app_layer_manifest_sha256=829e9a0fea1a39b38ff1e0e21398787e7530d35ce301d59a18bdb114424f3e5c
allow_knulli_boot_fallback=0
```

## Live Deploy

Device:

```text
root@192.0.2.120
```

Deployed file:

```text
/mnt/plumos/bin/plumos-controller-ui-fbdev
sha256=fd17bd4dcb1cc6f4c1a2234d3c8ae9bd10aecfb45a75dbf72085d59d57acedc1
```

Previous device binary was preserved as:

```text
/mnt/plumos/bin/plumos-controller-ui-fbdev.bak-20260608-061243
sha256=9d6c08f57f6426047ebc85ba0927a7f3d80f7e4edb067148692d904ae15f9e98
```

Frontend restart used only the PID-scoped frontend helper:

```text
plumos-frontend-stop: pid=875 cmd=/mnt/plumos/bin/plumos-controller-ui-fbdev --renderer fbdev
plumos-frontend-stop: TERM pid=875
plumos-frontend-stop: pid=1592 cmd=/mnt/plumos/bin/plumos-controller-ui-fbdev --renderer fbdev
```

No broad process-name kill was used, and SSH/network services were not stopped.

Runtime framebuffer status after restart:

```text
geometry 640 480 640 960 32
mode "640x480-59"
V: 58.955 Hz
```

Next user-visible check: open the START/settings menu on the V90S and confirm
that checkbox and selectable option controls align with the MMF/A30-style
settings layout.
