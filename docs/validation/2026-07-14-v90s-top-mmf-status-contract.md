# V90S TOP MMF Status Contract Validation

Date: 2026-07-14

## Scope

Re-check the complete V90S graphic TOP contract against the current MMF
frontend instead of treating each unwanted footer message as an independent
translation issue.

## MMF Contract

The MMF graphic TOP renderer keeps these elements:

- 3x2 system tile grid for `tile_grid`
- system logo, system title, selection frame, and theme colors
- top bar with product title, time, Wi-Fi, and battery state
- 5-pixel left accent on the normal TOP screen
- paged system navigation and configured transition behavior

MMF intentionally does not render the controller's transient `status` string
on TOP. Its TOP renderer receives the value but discards it with
`(void)status`. Status/help text remains valid on screens that provide an
explicit footer area, such as settings and operations.

## V90S Divergence

The V90S fbdev port added `plumos_fbdev_draw_status()` to the TOP renderer.
That made internal and transient strings appear at the lower-left edge of the
normal TOP screen, including:

```text
FBDEV RENDERER READY FONT=/MNT/PLUMOS/FONTS/DEFAULT.OTF
close START menu
```

The earlier attempt to translate or clear only the menu-close message did not
fix the screen-level contract. Any later status value could still appear.

## Fix

- Removed status rendering from `plumos_fbdev_render_top()`.
- Removed successful fbdev/font initialization messages from the UI status
  buffer. Renderer failures remain visible diagnostics.
- Kept status handling on non-TOP screens unchanged.
- Kept the V90S-specific title `PLUMOS V90S GUI`; all other normal TOP layout
  elements continue to follow the MMF structure.

## Live Proof

The rebuilt frontend was deployed over ADB to
`plumos-v90s-330ad2e0`. Two 640x960 framebuffer captures were checked using
the active page selected by `/sys/class/graphics/fb0/pan`:

1. normal frontend startup at TOP
2. `START` followed by `B` to return to TOP

Both active 640x480 pages contained only the MMF-style TOP grid and top bar.
There was no lower status/debug line after startup or after closing START.
The normal frontend was then restarted and exactly one frontend process was
running.

```text
28721 root  /mnt/plumos/bin/plumos-controller-ui-fbdev --renderer fbdev
```

Host, app-layer, and live-device frontend hashes matched:

```text
b16ef27dfabf44a63cbc4aae2b2c763a84b31a8471b71cfc7ae07a424cb2099a
```

## Build Validation

```text
git diff --check
./scripts/docker-build.sh frontend
./scripts/docker-build.sh app-layer
```

All completed successfully.
