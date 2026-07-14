# V90S RetroArch SDL2 Controller Mapping

Date: 2026-07-14

## Problem

RetroArch controls became scrambled after the V90S route selected the `udev`
joypad driver. Physical R opened the RetroArch menu, physical L acted as Start,
and YabaSanshiro could not be controlled reliably. The FE also kept its evdev
input descriptors open across emulator launches.

The vendor SDL2 runtime exposes `adc_gamepad` through SDL_GameController, so
RetroArch receives SDL logical buttons rather than the kernel's raw evdev
numbers. The V90S defaults were still written as raw indices.

## Mapping

The SDL2 probe now reports both raw joystick events and logical controller
events. The validated logical contract is:

```text
A=0 B=1 X=2 Y=3
Select=4 Function/Guide=5 Start=6
L=9 R=10
D-pad Up=11 Down=12 Left=13 Right=14
L2=+axis4 R2=+axis5
```

The route, factory configuration, generated app layer, frontend launcher, and
rootfs defaults now select:

```text
input_driver = "sdl2"
input_joypad_driver = "sdl2"
```

The launcher migrates only the exact previous V90S raw-index profile. It does
not overwrite arbitrary user mappings. A legacy `udev` migration marker is
repaired once, while already-customized configurations remain user-owned.

The FE opens controller and power event descriptors with `O_CLOEXEC`. Emulator
children therefore do not inherit the FE's evdev handles, while the original
FE process remains available to resume after emulator exit.

## Device Result

The rebuilt defaults and launcher were deployed through ADB. The user confirmed
normal NES controls, then normal YabaSanshiro controls and RetroArch menu
operation on the physical V90S. The correction remained active through the
Virtual Hydlide MAP/menu validation and did not require a broad process stop or
a fallback input path.
