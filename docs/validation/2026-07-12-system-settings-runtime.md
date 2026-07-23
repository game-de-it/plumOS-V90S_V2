# V90S System Settings Runtime Validation

Date: 2026-07-12

> Correction, 2026-07-23: V90S does expose the StockOS hardware backlight
> after loading `sunxi_backlight`. `Brightness` now uses that six-step backend.
> The observations below describe the earlier state in which the module was not
> loaded. See `2026-07-23-v90s-stockos-backlight.md`.

## Scope

Make the START menu `System Settings` entries use real V90S runtime backends
where they exist, and show unsupported entries as unavailable instead of saving
misleading values.

## Live Device

```text
ssh root@192.0.2.120
password: linux
PLUMOS_ROOT=/mnt/plumos
```

## Backend Findings

V90S does not use the A30-style backlight path:

```text
/sys/devices/virtual/disp/disp/attr/lcdbl: missing
```

V90S does expose display enhancement and color-temperature controls:

```text
/sys/class/disp/disp/attr/enhance_bright
/sys/class/disp/disp/attr/enhance_contrast
/sys/class/disp/disp/attr/enhance_saturation
/sys/class/disp/disp/attr/color_temperature
```

The `enhance_*` files read as two values, but accept a single value on write.
Writing the current two-value text back returns `EINVAL`; writing a single
neutral value succeeds.

## Implemented Behavior

- `Volume`: backed by `/mnt/plumos/bin/plumos-volume-control`, using the V90S
  StockOS ALSA `Headphone` and `HpSpeaker` controls.
- `Brightness`: this historical build showed `N/A` because
  `sunxi_backlight` had not been loaded.
- `Lumination`: writes `enhance_bright`.
- `Display Color -> Contrast`: writes `enhance_contrast`.
- `Display Color -> Color Temp`: uses the existing `system_hue` setting ID but
  presents it as color temperature and writes `color_temperature`.
- `Display Color -> Saturation`: writes `enhance_saturation`.
- `Factory Reset`: shows only installed default sets. The current app layer
  installs `ra`, so only `RetroArch Settings` is shown.
- `Time Settings`: the initial manual-time-only implementation was superseded
  by the RTC-aware automatic, immediate, and manual time behavior documented in
  `docs/validation/2026-07-17-v90s-rtc-time-settings.md`.

## Live Checks

Text renderer path confirmed the visible settings:

```text
System Settings
  Volume                   14
  Brightness               N/A
  Lumination               5
  Display Color
  Time Settings
  Language                 English
  Factory Reset
  INFORMATION
```

Display Color screen:

```text
System Settings - Display Color
  Contrast                 10
  Color Temp               10
  Saturation               10
```

Factory Reset screen:

```text
System Settings - Factory Reset
  RetroArch Settings
```

Runtime write tests were performed through the frontend script path and then
restored:

```text
Lumination 5 -> 6: enhance_bright      50 50 -> 60 60
Contrast   10 -> 11: enhance_contrast  50 50 -> 55 55
Color Temp 10 -> 11: color_temperature 0 -> 15
Saturation 10 -> 11: enhance_saturation 50 50 -> 55 55
```

Brightness was tested through the frontend script path:

```text
status: runtime backend unavailable
config/system/settings.json checksum unchanged
```

Volume was tested through the frontend script path:

```text
Volume 14 -> 15
Headphone 2 -> 3
```

The setting was restored:

```text
Volume 14
Headphone 2
```

Factory reset dry-run after cleaning macOS AppleDouble transfer files:

```text
would restore ra: config/retroarch/retroarch-v90s.cfg
```

## Build Checks

```text
./scripts/docker-build.sh frontend
./scripts/docker-build.sh app-layer
```

Both completed. The frontend build still emits pre-existing
`plumos_text_ui.c` `snprintf` truncation warnings for CPU core count formatting;
they are unrelated to this change.
