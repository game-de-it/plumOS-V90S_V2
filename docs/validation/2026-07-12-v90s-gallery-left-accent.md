# V90S Gallery Left Accent Removal

Date: 2026-07-12
Device: POWKIDDY V90S
Access: SSH `root@192.0.2.120`

## Symptom

In gallery mode, the V90S screen showed a vertical orange accent bar on the far
left edge. The MMF gallery reference did not show this bar.

## Change

Removed the gallery-specific full-height accent fill from:

```text
src/frontend/plumos_fbdev_renderer.h
plumos_fbdev_draw_gallery_top_bar()
```

The normal graphic top screen and settings/sidebar accent behavior were left
unchanged.

## Build

Command:

```text
./scripts/docker-build.sh frontend
```

Result:

```text
created: output/frontend/v90s
launcher: output/frontend/v90s/plumos/bin/plumos-frontend-launch
```

Existing `plumos_text_ui.c` `snprintf` warnings were still present and are not
related to this renderer change.

## Live Device Deployment

Updated binary:

```text
/mnt/plumos/bin/plumos-controller-ui-fbdev
```

Frontend restart:

```text
plumos-frontend-stop: TERM pid=32257
new_pid=1231
```

Running binary hash:

```text
f496212e181badf0ee6fbb0c6eceb841171e3456b317836e46fe057a4fab9ac7  /proc/1231/exe
f496212e181badf0ee6fbb0c6eceb841171e3456b317836e46fe057a4fab9ac7  /mnt/plumos/bin/plumos-controller-ui-fbdev
```

## Result

The gallery renderer no longer draws the V90S-only vertical orange bar at the
left edge. User visual confirmation is still needed on the physical LCD.
