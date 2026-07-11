# V90S frontend long text marquee

Date: 2026-07-11

## Goal

Match the plumOS MMF frontend behavior for strings that exceed their visible
width. Long selected ROM names and preview text should pause briefly, then
scroll horizontally instead of being permanently clipped.

## Change

- Added a fbdev renderer marquee clock and MMF-style offset calculation.
- Implemented `plumos_fbdev_renderer_reset_marquee()`.
- Applied marquee clipping to:
  - selected ROM-list title
  - ROM preview title
  - ROM preview detail/path
  - gallery footer title
- Fixed the fbdev ROM-list periodic refresh interval to
  `UI_GRAPHIC_SCROLL_REFRESH_MS` so marquee updates are actually redrawn without
  a zero-millisecond busy refresh loop.

The timing follows MMF:

```text
hold_ms=1000
pixels_per_second=80
```

## Build

```text
./scripts/docker-build.sh frontend
./scripts/docker-build.sh app-layer
```

The existing `plumos_text_ui.c` CPU-core formatting warnings are unrelated to
this change.

## Offscreen Render Check

Generated comparison images:

```text
output/validation/fbdev-marquee-start.png
output/validation/fbdev-marquee-after.png
```

Test string:

```text
ダウンタウン熱血行進曲 それゆけ大運動会
```

Result:

- `fbdev-marquee-start.png` shows the beginning of the long title.
- `fbdev-marquee-after.png` shows the same title shifted left after elapsed
  marquee time, exposing later characters.

This exercises the same fbdev text width, clipping, and marquee offset path as
the V90S frontend.

## Live Device Deployment

Device:

```text
ssh root@192.0.2.120
```

Deployed binary:

```text
2084f71b1a67cebec53c301f5c122b64a87aba5c52bc66db9e73f63b0e8ca98e  /mnt/plumos/bin/plumos-controller-ui-fbdev
```

Running frontend after deploy:

```text
pid=2235
```

Live notes:

- The binary was copied to `/tmp`, the frontend was stopped with
  `/mnt/plumos/bin/plumos-frontend-stop stop`, and the binary was moved into
  `/mnt/plumos/bin/`.
- The frontend was restarted through `/mnt/plumos/bin/plumos-frontend-launch`.
- SSH stdin injection was not reliable for leaving the live UI on a long ROM
  entry while waiting for the marquee phase, so the live proof is limited to
  deployed binary hash plus running FE state. User-side validation should hold
  the cursor on a long ROM name such as:

```text
ダウンタウン熱血行進曲 それゆけ大運動会
```
