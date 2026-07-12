# V90S physical key evdev mapping

Date: 2026-07-13

## Goal

Record how the POWKIDDY V90S physical buttons are exposed by the running
StockOS-derived plumOS runtime. This is an OS-level evdev capture, not a
frontend or RetroArch policy change.

## Method

- Device: live POWKIDDY V90S, reachable at `root@192.0.2.120`.
- The frontend was stopped with `/mnt/plumos/bin/plumos-frontend-stop stop`
  before each capture and restarted with `/mnt/plumos/bin/plumos-frontend-launch`
  after capture.
- Events were captured with:
  `/mnt/plumos/bin/plumos-controller-ui --dump-events --event /dev/input/eventX --timeout N`
- Relevant live log directories:
  - `/tmp/plumos-v90s-keymap-1783877896`
  - `/tmp/plumos-v90s-keymap-abdpad-1783878164`
  - `/tmp/plumos-v90s-combo-keytest-1783878670`

## Input Devices

`/proc/bus/input/devices` exposes the relevant physical controls as:

| Event node | Device name | Role |
| --- | --- | --- |
| `/dev/input/event0` | `sunxi-keyboard` | Volume keys |
| `/dev/input/event1` | `axp2202-pek` | Power key |
| `/dev/input/event4` | `adc_gamepad` | D-pad, face buttons, shoulders, select/start/function |

The V90S game controls are therefore expected to prefer `adc_gamepad` for
normal frontend and app input.

## Physical Key Mapping

| Physical key | Event node | evdev event |
| --- | --- | --- |
| Up | `/dev/input/event4` | `EV_ABS ABS_HAT0Y(17) value=-1`, release `value=0` |
| Down | `/dev/input/event4` | `EV_ABS ABS_HAT0Y(17) value=1`, release `value=0` |
| Left | `/dev/input/event4` | `EV_ABS ABS_HAT0X(16) value=-1`, release `value=0` |
| Right | `/dev/input/event4` | `EV_ABS ABS_HAT0X(16) value=1`, release `value=0` |
| A | `/dev/input/event4` | `EV_KEY BTN_SOUTH(304) value=1`, release `value=0` |
| B | `/dev/input/event4` | `EV_KEY BTN_EAST(305) value=1`, release `value=0` |
| X | `/dev/input/event4` | `EV_KEY BTN_NORTH(307) value=1`, release `value=0` |
| Y | `/dev/input/event4` | `EV_KEY BTN_WEST(308) value=1`, release `value=0` |
| L | `/dev/input/event4` | `EV_KEY BTN_TL(310) value=1`, release `value=0` |
| R | `/dev/input/event4` | `EV_KEY BTN_TR(311) value=1`, release `value=0` |
| L2 | `/dev/input/event4` | `EV_KEY BTN_TL2(312) value=1`, release `value=0` |
| R2 | `/dev/input/event4` | `EV_KEY BTN_TR2(313) value=1`, release `value=0` |
| Select | `/dev/input/event4` | `EV_KEY BTN_SELECT(314) value=1`, release `value=0` |
| Start | `/dev/input/event4` | `EV_KEY BTN_START(315) value=1`, release `value=0` |
| Function | `/dev/input/event4` | `EV_KEY BTN_MODE(316) value=1`, release `value=0` |
| Volume down | `/dev/input/event0` | `EV_KEY KEY_VOLUMEDOWN(114) value=1`, release `value=0` |
| Volume up | `/dev/input/event0` | `EV_KEY KEY_VOLUMEUP(115) value=1`, release `value=0` |
| Power short press | `/dev/input/event1` | `EV_KEY KEY_POWER(116) value=1`, release `value=0` |

Long-press power behavior was not tested here.

## Combo Behavior

The StockOS-style `Select+Start` combo was tested after the basic keymap
capture. Pressing Select and Start together produced all three key events:

| Combo | Observed event |
| --- | --- |
| Select+Start | `BTN_SELECT(314)`, `BTN_START(315)`, and `BTN_MODE(316)` |

This confirms that the vendor input layer still exposes the StockOS-style
`Select+Start` as a Function-mode event. It does not suppress the original
Select and Start events.

The `Select+R2` analog/digital toggle behavior was also tested. The result was:

| Combo | Observed result |
| --- | --- |
| Select+R2 | `BTN_SELECT(314)` plus `BTN_TR2(313)` only |
| D-pad before Select+R2 | `ABS_HAT0X(16)` / `ABS_HAT0Y(17)` |
| D-pad after Select+R2 | `ABS_HAT0X(16)` / `ABS_HAT0Y(17)` |

No D-pad switch from digital hat events to analog axis events was observed in
this test. The device reports `capabilities/abs=3001b`, so `adc_gamepad` does
advertise analog-capable ABS bits, but this tested `Select+R2` sequence did not
toggle the D-pad output away from `ABS_HAT0X/Y`.

## Raw Evidence

D-pad and ABXY capture from `/dev/input/event4`:

```text
type=3 code=17 value=-1
type=0 code=0 value=0
type=3 code=17 value=0
type=0 code=0 value=0
type=3 code=17 value=1
type=0 code=0 value=0
type=3 code=17 value=0
type=0 code=0 value=0
type=3 code=16 value=-1
type=0 code=0 value=0
type=3 code=16 value=0
type=0 code=0 value=0
type=3 code=16 value=1
type=0 code=0 value=0
type=3 code=16 value=0
type=0 code=0 value=0
type=1 code=304 value=1
type=0 code=0 value=0
type=1 code=304 value=0
type=0 code=0 value=0
type=1 code=305 value=1
type=0 code=0 value=0
type=1 code=305 value=0
type=0 code=0 value=0
type=1 code=307 value=1
type=0 code=0 value=0
type=1 code=307 value=0
type=0 code=0 value=0
type=1 code=308 value=1
type=0 code=0 value=0
type=1 code=308 value=0
type=0 code=0 value=0
```

Shoulders, select/start/function capture from `/dev/input/event4`:

```text
type=1 code=310 value=1
type=0 code=0 value=0
type=1 code=310 value=0
type=0 code=0 value=0
type=1 code=311 value=1
type=0 code=0 value=0
type=1 code=311 value=0
type=0 code=0 value=0
type=1 code=312 value=1
type=0 code=0 value=0
type=1 code=312 value=0
type=0 code=0 value=0
type=1 code=313 value=1
type=0 code=0 value=0
type=1 code=313 value=0
type=0 code=0 value=0
type=1 code=314 value=1
type=0 code=0 value=0
type=1 code=314 value=0
type=0 code=0 value=0
type=1 code=315 value=1
type=0 code=0 value=0
type=1 code=315 value=0
type=0 code=0 value=0
type=1 code=316 value=1
type=0 code=0 value=0
type=1 code=316 value=0
type=0 code=0 value=0
```

Volume and power captures:

```text
/dev/input/event0:
type=1 code=114 value=1
type=0 code=0 value=0
type=1 code=114 value=0
type=0 code=0 value=0
type=1 code=115 value=1
type=0 code=0 value=0
type=1 code=115 value=0
type=0 code=0 value=0

/dev/input/event1:
type=1 code=116 value=1
type=0 code=0 value=0
type=1 code=116 value=0
type=0 code=0 value=0
```

Combo capture from `/dev/input/event4`:

```text
Select+Start:
type=1 code=314 value=1
type=1 code=315 value=1
type=1 code=316 value=1
type=0 code=0 value=0
type=1 code=314 value=0
type=1 code=315 value=0
type=1 code=316 value=0
type=0 code=0 value=0

Select+R2:
type=1 code=314 value=1
type=0 code=0 value=0
type=1 code=313 value=1
type=0 code=0 value=0
type=1 code=313 value=0
type=0 code=0 value=0
type=1 code=314 value=0
type=0 code=0 value=0

D-pad after Select+R2:
type=3 code=17 value=-1
type=0 code=0 value=0
type=3 code=17 value=0
type=0 code=0 value=0
type=3 code=16 value=-1
type=0 code=0 value=0
type=3 code=16 value=0
type=0 code=0 value=0
type=3 code=17 value=1
type=0 code=0 value=0
type=3 code=17 value=0
type=0 code=0 value=0
type=3 code=16 value=1
type=0 code=0 value=0
type=3 code=16 value=0
type=0 code=0 value=0
```

## Frontend Notes

The current frontend key decoder already handles:

- `BTN_SOUTH/EAST/NORTH/WEST` as `A/B/X/Y`
- `ABS_HAT0X/ABS_HAT0Y` as D-pad movement
- `BTN_SELECT` as Select
- `BTN_START` as Start
- `KEY_VOLUMEDOWN`, `KEY_VOLUMEUP`, and `KEY_POWER`

Current frontend behavior that should be treated separately from this OS-level
mapping:

- `BTN_MODE` is currently decoded as `ACTION_START`, so the physical Function
  button and the `Select+Start` Function combo are not independent in the
  frontend yet.
- `BTN_TL`, `BTN_TR`, `BTN_TL2`, and `BTN_TR2` are visible to the OS, but are
  not assigned to frontend actions yet.
