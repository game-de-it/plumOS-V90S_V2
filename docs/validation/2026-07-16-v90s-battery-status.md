# V90S frontend battery status

Date: 2026-07-16

## Symptom

The frontend top bar always displayed:

```text
BAT --
```

The renderer read only the conventional Linux path:

```text
/sys/class/power_supply/battery
```

That power-supply name does not exist in the StockOS-derived V90S kernel.

## Live hardware contract

The V90S exposes its battery and USB supply under AXP2202-specific names:

```text
/sys/class/power_supply/axp2202-battery
/sys/class/power_supply/axp2202-usb
```

The live values during validation were:

```text
type=Battery
status=Full
capacity=100
present=1
voltage_now=4200000

USB present=1
USB online=1
```

## Fix

The fbdev renderer now locates the battery in this order:

1. Standard `battery` power-supply name.
2. V90S `axp2202-battery` power-supply name.
3. Any `/sys/class/power_supply/*` entry whose `type` is `Battery` and which
   exposes `capacity`.

Capacity is parsed as an integer and clamped to 0 through 100. The existing
MMF-style label contract remains:

```text
BAT <capacity>  while discharging or not charging
CHG <capacity>  while Charging or Full
BAT --          when no usable battery supply exists
```

The V90S graphic TOP now refreshes every five seconds. This updates battery,
charging, time, and Wi-Fi labels without requiring a menu transition.

## Live proof

The deployed frontend rendered:

```text
PLUMOS V90S GUI                  14:37  WIFI  CHG 100
```

Both 640x480 framebuffer pages were identical. The captured page hash was:

```text
625b6979d7715ab7e41a4f4835bb7577dffde76f484827f8d7de55d18311ba06
```

An attached `strace` proved that the resident frontend reread the real battery
files at five-second intervals:

```text
14:38:02  axp2202-battery/type, capacity, status
14:38:07  axp2202-battery/type, capacity, status
14:38:12  axp2202-battery/type, capacity, status
```

Exactly one frontend process remained after deployment. Wi-Fi stayed connected
at `192.0.2.120`, and ADB remained available.

## Build validation

The following official targets completed without new compiler warnings:

```text
./scripts/docker-build.sh frontend
./scripts/docker-build.sh app-layer
```

The remaining physical check is to disconnect external power and confirm that
the live label changes from `CHG` to `BAT` as the kernel status changes from
`Full` or `Charging` to `Discharging`.
