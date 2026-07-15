# V90S PicoArch game input

Date: 2026-07-15

## Symptom

The physical V90S controls operated PicoArch's own menu, but gameplay input was
missing in several systems. Menu operation alone did not prove that the loaded
libretro core considered a controller connected.

## Root cause

V90S PicoArch intentionally gives the built-in `adc_gamepad` to libpicofe's
evdev input path. SDL joystick enumeration remains disabled because exposing
the same physical controller through both SDL and evdev caused duplicate menu
input.

The evdev path correctly updated PicoArch's `buttons` mask, but
`core_load_content()` did not call the core's
`retro_set_controller_port_device()` function except for a later fMSX-specific
override. Cores that do not assume a connected joypad therefore received no
game input even though the PicoArch menu worked.

## Fix

`picoarch-v90s-controller-init.patch` explicitly connects port 0 as
`RETRO_DEVICE_JOYPAD` before `retro_load_game()`. TyrQuake is the one preserved
exception: matching the MMF/A30 implementation, its controller is attached
after content loading. The existing fMSX joypad-plus-keyboard subclass remains
applied after the generic registration.

This keeps a single physical input owner:

```text
adc_gamepad -> libpicofe evdev -> PicoArch buttons -> libretro port 0 joypad
```

It does not re-enable SDL joystick ownership.

## Build and deployment

The normal build target completed:

```text
./scripts/docker-build.sh picoarch
```

Built and live binary:

```text
eaa90866f5a30970741193bc0599bbe9dcd4bdb78d1d6bf625657f4d8a79b47f  picoarch
```

Only `/mnt/plumos/picoarch/bin/picoarch` was replaced for the live test. The
launcher, core binaries, controller mapping, and saved per-system state were
not changed.

## Real-device validation

The user confirmed gameplay controls, not just PicoArch menu controls, in two
independent cores:

```text
sega32x  picoarch:picodrive  BC Racers (USA).32x  controls OK
3do      picoarch:opera      biofury.iso           controls OK
```

Each runtime was stopped through `plumos-picoarch-stop`; no PicoArch PID file
or process remained. The frontend was then restored as one process through
`plumos-frontend-launch`.

The earlier investigation also launched PicoArch 32X, 3DO, and Amiga in that
order and then started RetroArch YabaSanshiro without rebooting. The 32X and
3DO exits left no process residue, and the user confirmed Saturn controls were
normal. This does not reproduce a cross-frontend input ownership leak.

## Separate Amiga issue

PUAe crashed with a segmentation fault before PicoArch input initialization.
No PicoArch process or PID file remained after the crash. That failure is a
separate core/content startup problem and is not evidence that this controller
registration fix failed; Amiga gameplay input remains unvalidated until the
PUAe crash is resolved.
