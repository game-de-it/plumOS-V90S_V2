# V90S Frontend fbdev Double Buffer Validation

Date: 2026-07-11

## Scope

The V90S fbdev frontend flickered when moving the TOP cursor with the d-pad.
The renderer was drawing directly into the currently visible framebuffer page,
so the LCD could show the intermediate clear and redraw steps.

## Fix

`plumos-controller-ui-fbdev` now uses framebuffer page flipping when the fbdev
device exposes at least two visible-height pages:

```text
visible page -> keep on screen
hidden page  -> draw complete frame
FBIOPAN_DISPLAY -> show hidden page
next frame    -> draw into the previous visible page
```

For V90S this matches the known fb0 shape:

```text
virtual_size=640,960
visible=640x480
bpp=32
stride=2560
```

If `FBIOPAN_DISPLAY` fails, the renderer falls back to the previous direct
single-buffer behavior after copying the completed frame to the visible page.
The double-buffer path can be disabled for diagnostics with:

```text
PLUMOS_FBDEV_DOUBLE_BUFFER=0
```

## Build

```text
./scripts/docker-build.sh frontend
./scripts/docker-build.sh app-layer
```

The frontend build still emits the pre-existing `plumos_text_ui.c` `cores_buf`
format truncation warnings. No new fbdev renderer warning was emitted.

Host app-layer checksum:

```text
cd output/app-layer/v90s && sha256sum -c checksums.sha256: OK
```

Updated fbdev frontend binary:

```text
426efb73422344016fa399095013a4222c15ae029531d4bb62ebe7bad7a6a54d  output/app-layer/v90s/bin/plumos-controller-ui-fbdev
```

## Live Deployment

The live V90S was reachable at:

```text
root@192.0.2.120
```

The frontend was stopped without touching SSH or Wi-Fi:

```text
/mnt/plumos/bin/plumos-frontend-stop stop
plumos-frontend-stop: TERM pid=2245
plumos-frontend-stop: frontend not running
```

Only the fbdev frontend binary and app-layer metadata were copied:

```text
/mnt/plumos/bin/plumos-controller-ui-fbdev
/mnt/plumos/checksums.sha256
/mnt/plumos/manifest.json
/mnt/plumos/licenses/frontend-manifest.txt
```

Live hashes:

```text
426efb73422344016fa399095013a4222c15ae029531d4bb62ebe7bad7a6a54d  /mnt/plumos/bin/plumos-controller-ui-fbdev
b69211bda0524e503c20e596f21f12c57562168a00e497629c51973212eb336f  /mnt/plumos/checksums.sha256
f7a6f6ac95246061ef8092baa010b20e4feeba5c55fe93c6d4c64fc20c564c72  /mnt/plumos/manifest.json
484c4d01ff21bdc44c64c6dbe43fcdf8dbc5a6bb7bbe92da3570efed32a1b418  /mnt/plumos/licenses/frontend-manifest.txt
```

Live app-layer checksum:

```text
cd /mnt/plumos && sha256sum -c checksums.sha256: OK
```

The frontend was restarted as a single process:

```text
/mnt/plumos/bin/plumos-frontend-stop status
plumos-frontend-stop: pid=2352 cmd=/mnt/plumos/bin/plumos-controller-ui-fbdev --renderer fbdev
```

## Framebuffer Proof

After restart, `/dev/fb0` was captured from both virtual pages:

```text
output/validation/frontend-flicker-fix/fb0-page0.png
3fdf1f56f9c75c4d33bb149681b71dceb87ae7e5468547cb3c6822aa4038125d

output/validation/frontend-flicker-fix/fb0-page1.png
8e02f1f75220a1707f624daf37168f4d694dfe94e01c571f2c9a63a41478065a
```

Both pages contain valid TOP frames. Page 0 captured the current cursor on
`RECENT`, and page 1 retained the previous valid TOP frame with cursor on `NES`.
This confirms the renderer is no longer clearing and redrawing only the currently
visible page.

Physical validation still required:

- move the TOP cursor with the V90S d-pad
- confirm the visible screen no longer flashes during cursor movement
