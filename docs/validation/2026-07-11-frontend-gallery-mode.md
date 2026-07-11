# V90S frontend gallery mode

Date: 2026-07-11

## Scope

Implemented the MMF-style Gallery screen for the V90S fbdev frontend.

The controller already emitted `graphic_mode=gallery`, `graphic_entry`, and
`graphic_prev_entry` lines. The missing piece was the V90S fbdev renderer path:
it routed `gallery` through the ROM-list renderer.

## Changes validated

- `graphic_mode=gallery` now renders a dedicated Gallery layout.
- Gallery uses the MMF-style center card, side cards, shelf/background, and
  footer title.
- fbdev Gallery refresh is enabled at 16 ms while the screen is active or a
  Gallery transition is active.
- ROM/Favorites/Recent screens accept `X` as the Gallery entry action even when
  the renderer is not in graphic mode, so the script/test path matches the live
  controller action.
- PNG rendering now uses a small LRU cache, avoiding per-frame PNG decode during
  Gallery refresh.

## Build proof

Commands:

```sh
./scripts/docker-build.sh frontend
./scripts/docker-build.sh app-layer --strict
```

Result:

- `output/frontend/v90s` created.
- `output/app-layer/v90s` created.
- Existing `plumos_text_ui.c` `%ld` truncation warnings remain unrelated to this
  Gallery change.

## Live V90S proof

Device: `root@192.0.2.120`

Updated on the live device:

- `/mnt/plumos/bin/plumos-controller-ui`
- `/mnt/plumos/bin/plumos-controller-ui-fbdev`

Text-mode script proof:

```sh
PLUMOS_ROOT=/mnt/plumos \
PLUMOS_SDCARD_ROOT=/mnt/plumos \
PLUMOS_FRONTEND_MODE=manual \
/mnt/plumos/bin/plumos-controller-ui --script a,x
```

Observed final output:

```text
plumOS controller UI - Gallery
graphic_mode=gallery
graphic_system=NES  ROMS 86
status: Gallery ready
```

fbdev script proof:

```sh
PLUMOS_ROOT=/mnt/plumos \
PLUMOS_SDCARD_ROOT=/mnt/plumos \
PLUMOS_FRONTEND_MODE=manual \
/mnt/plumos/bin/plumos-controller-ui-v90s --script a,x --timeout 1
```

Framebuffer capture:

- `fb0` reported `640x960` virtual size, `32` bpp, stride `2560`.
- Captured both framebuffer pages with `dd if=/dev/fb0 bs=2457600 count=1`.
- Page 1 showed the new Gallery layout.

Converted proof image:

- `output/validation/plumos-gallery-page1.png` (ignored artifact)

Runtime restore proof:

```text
/mnt/plumos/bin/plumos-controller-ui-fbdev --renderer fbdev
[plumos-frontend]
```

The frontend was restarted after validation and remained resident.
