# V90S System Information Runtime Validation

Date: 2026-07-12

## Scope

Fix `System Settings -> INFORMATION` so it reflects the V90S plumOS
distribution split instead of inherited Miyoo/MMF firmware assumptions.

## Implemented Behavior

- Default model is now `POWKIDDY V90S`.
- The screen reads plumOS app-layer metadata from `/mnt/plumos/VERSION` and
  `/mnt/plumos/COMPAT_VENDOR`.
- The compatible vendor runtime is shown separately from the plumOS version.
- GPU, display backend, and audio backend are shown as runtime information.
- The old `miyoo_version` wording was removed from all frontend language files.
- `Firmware` was renamed to `Base OS` and is read from StockOS/Batocera or
  rootfs release metadata.

## Live Device

```text
ssh root@192.0.2.120
password: linux
PLUMOS_ROOT=/mnt/plumos
PLUMOS_SDCARD_ROOT=/mnt/plumos
```

## Live Check

The text renderer was used to open `START -> System Settings -> INFORMATION` on
the running V90S:

```text
System Settings - INFORMATION
  Device Model             POWKIDDY V90S
  plumOS                   0.1.0-dev
  Vendor                   v90s-stockos-r1
  Kernel                   4.9.191
  GPU                      PowerVR GE8300
  Display                  disp enhance
  Audio                    plumOS volume helper
  Storage                  752/1021 MB (74%)
  Memory                   148/977 MB (15%)
  Base OS                  Debian GNU/Linux 12 (bookworm)
```

Frontend status after deployment:

```text
plumos-frontend-stop: pid=6250 cmd=/mnt/plumos/bin/plumos-controller-ui-fbdev --renderer fbdev
```

## Build Checks

```text
git diff --check
./scripts/docker-build.sh frontend
./scripts/docker-build.sh app-layer
```

All completed. The frontend build still emits pre-existing
`plumos_text_ui.c` `snprintf` truncation warnings for CPU core count formatting;
they are unrelated to this change.
