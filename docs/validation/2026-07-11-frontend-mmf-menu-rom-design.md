# 2026-07-11 V90S Frontend MMF Menu/ROM Design Validation

## Scope

The V90S fbdev frontend was updated after the MMF-style TOP and flicker fixes.
This pass aligns the non-TOP screens that were still visibly different from the
MMF frontend:

- START/settings-family screens now use the MMF TTY-style top bar.
- START/settings-family screens keep the blue left accent and compact menu
  entries instead of showing internal metadata.
- ROM selection screens use the MMF graphic ROM layout: left ROM list, right
  preview panel, selected-row highlight, and system/count header.

The V90S label remains device-specific:

```text
PLUMOS V90S TTY1
```

## Source Changes

- `src/frontend/plumos_controller_ui.c`
  - Treat fbdev as an MMF/A30-style compact renderer for menu line output.
- `src/frontend/plumos_fbdev_renderer.h`
  - Add an MMF-style TTY top bar for generic START/settings-family screens.
  - Rework generic menu rendering to hide internal metadata and draw compact
    selected rows.
  - Rework ROM list rendering to match the MMF `graphic_draw_roms` layout.
  - Keep fbdev double buffering from the previous validation.

## Build

Commands:

```sh
./scripts/docker-build.sh frontend
./scripts/docker-build.sh app-layer
(cd output/app-layer/v90s && sha256sum -c checksums.sha256)
```

Result:

```text
created: output/frontend/v90s
created: output/app-layer/v90s
version: 0.1.0-dev
compat_vendor: v90s-stockos-r1
mount_path: /mnt/plumos
```

The build still emits the existing `plumos_text_ui.c` `cores_buf` truncation
warnings. The fbdev renderer changes did not introduce new build warnings.

Local app-layer hashes:

```text
be1d4e1ed3c446c6d742f12e2bc73a2518b8bc05227bed9e96e259e85349651b  output/app-layer/v90s/bin/plumos-controller-ui
cf2ceb3f1bcee69679e21a64a62e114e9464e772ddcde966a8b6ea1686a16e69  output/app-layer/v90s/bin/plumos-controller-ui-fbdev
265d28fe5a34afa12fad8103944d3949335f7dedf90e64863e3d17a02ba6572c  output/app-layer/v90s/bin/plumos-controller-ui-v90s
1f14637c1089e582bac776c73af966f2617fd2c6cfa6c0f966bafdd1f24512b5  output/app-layer/v90s/checksums.sha256
c01e15819df68686c4add5674a94917a3c39e2d7c3f203ce68bc6968cfde2150  output/app-layer/v90s/manifest.json
c0840e4ae63f31b512fd3f44a031ee8be85c0dc045a3b3e110b605179833b224  output/app-layer/v90s/licenses/frontend-manifest.txt
```

## Live Device Deployment

Device:

```text
root@192.0.2.120
```

Updated files:

```text
/mnt/plumos/bin/plumos-controller-ui
/mnt/plumos/bin/plumos-controller-ui-fbdev
/mnt/plumos/bin/plumos-controller-ui-v90s
/mnt/plumos/checksums.sha256
/mnt/plumos/manifest.json
/mnt/plumos/licenses/frontend-manifest.txt
```

The app-layer checksum passed on the device:

```sh
cd /mnt/plumos && sha256sum -c checksums.sha256
```

Result: all entries OK.

## Framebuffer Capture

START screen capture:

```text
output/validation/frontend-mmf-menu-rom-design/start-page1.png
sha256: 11d886181ab7424983708ec154b08be08882bda5940982603cc069f19914bab1
raw: output/validation/frontend-mmf-menu-rom-design/fb0-start.raw
raw sha256: fcfa31a288a3b935fc98c9be0fb70b8126f250cbc16e520c84b8ead3cd07e69a
```

ROM selection screen capture:

```text
output/validation/frontend-mmf-menu-rom-design/rom-page1.png
sha256: 5871aa4a161b66a45e391528443132cec3f13aed067328fcf4027392c89d6d8c
raw: output/validation/frontend-mmf-menu-rom-design/fb0-rom.raw
raw sha256: 73a40103487bf49a82c57f40c0d257ea5b7ff1d379cd107b11561a8e6d09d0a4
```

The captured START screen shows the MMF-style TTY header and compact menu list.
The captured ROM screen shows the MMF-style ROM list plus preview panel.

## Runtime State

The normal frontend was restarted after validation:

```sh
nohup /mnt/plumos/bin/plumos-frontend-launch \
  >/mnt/plumos/Logs/frontend-mmf-menu-rom-design.log 2>&1 &
```

Process check:

```text
plumos-frontend-stop: pid=2499 cmd=/mnt/plumos/bin/plumos-controller-ui-fbdev --renderer fbdev
```

Only one long-lived frontend process was present after the SSH helper command
finished.

## User Validation Needed

Host-side fb0 capture confirms the intended screen shape, but final acceptance
still needs physical V90S inspection:

- START opens with the MMF-style TTY header and compact list.
- ROM selection screen matches the MMF left-list/right-preview layout.
- Cursor movement remains flicker-free on the real LCD.
- Controller navigation and ROM launch are unchanged.
