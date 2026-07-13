# V90S AArch64 PicoArch validation

Date: 2026-07-14

## Previous state

The FE exposed `picoarch:*` launch profiles, but
`plumos-picoarch-launch` was only a placeholder that exited with status 69.
The MMF and A30 PicoArch binaries and cores are ARM32 EABI and cannot be reused
by the V90S AArch64 userspace.

## Implemented route

The official build entry point is now:

```sh
./scripts/docker-build.sh picoarch
```

It builds pinned PicoArch commit
`802047c276a5a931b0bf837c4ea4b8e238bdeabe` as an AArch64 PIE and pinned
SDL12 compatibility commit `fc2ec0c128197f1f5050e48359bc41e618f3abfb`.
The runtime resolves cores from `/mnt/plumos/picoarch/cores` first and then the
normal shared 64-bit set at `/mnt/plumos/cores`.

The V90S display cannot use SDL12 compatibility's normal SDL2 renderer output:
it produced a right-shifted RGB565 image with incorrect line pitch. The V90S
port therefore keeps PicoArch's RGB565 logical surface and converts it to the
32-bit framebuffer's inactive page. It waits for vsync and switches pages with
`FBIOPAN_DISPLAY`, matching the FE fbdev ownership model. The default scaling
effect is `NONE`; upstream's default `SCANLINE` effect was the source of the
one-line gaps seen during the first test.

The V90S controller is read directly through evdev instead of relying on SDL's
generic joystick numbering. The platform mapping follows the captured
`adc_gamepad` contract: `ABS_HAT0X/Y` provide the d-pad, `BTN_SOUTH/EAST` are
A/B, `BTN_NORTH/WEST` are X/Y, and the remaining shoulder, trigger, Select,
Start, and Function buttons use their Linux input codes. Function opens the
PicoArch menu. HAT axes are translated to digital directions both during core
execution and in PicoArch menus.

The first evdev deployment also let SDL register `adc_gamepad`. Runtime input
diagnostics showed both `evdev:adc_gamepad` and `sdl:adc_gamepad` with active
bindings, which delivered one physical menu action through two devices and
looked like an excessive key repeat. V90S builds now leave SDL keyboard input
enabled but skip SDL joystick registration; `adc_gamepad` has one owner through
evdev. PicoArch's normal 450 ms initial menu-repeat delay is unchanged.

The default screen-size setting is `Aspect`. This changes only the initial
value; settings saved by a user under `/mnt/plumos/state/picoarch/<system>`
continue to take precedence.

## Real-device result

The deployed process was:

```text
/mnt/plumos/picoarch/bin/picoarch
  /mnt/plumos/cores/quicknes_libretro.so
  /mnt/plumos/roms/nes/Super Mario Bros..nes
  NONE
```

Validated facts:

- PicoArch and QuickNES are AArch64 binaries.
- the FE resolves `picoarch:quicknes` to the shared core, reports
  `can_execute: yes`, and starts the same formal PicoArch binary;
- the captured visible 640x480 framebuffer page contains correctly positioned
  4:3 game output while the inactive page is populated separately;
- the visible route uses vsync-aware double-buffer page switching;
- the deployed PicoArch opens `/dev/input/event4` through the V90S evdev path
  in addition to SDL's device handle;
- ALSA PCM playback reports `state: RUNNING` with PicoArch as owner;
- configuration, saves, BIOS, logs, and state remain under `/mnt/plumos`;
- `plumos-picoarch-stop` verifies the exact executable before signalling and
  does not use broad process matching.
- `flycast` and `flycast_xtreme` both exit with `ERROR: Couldn't load content`
  when hosted by PicoArch on V90S. They remain available through RetroArch but
  are excluded from PicoArch launch-profile choices; direct launcher use also
  reports that PicoArch lacks libretro hardware rendering. No fallback is
  performed.

The deployed binary SHA-256 after removing duplicate SDL controller
registration is
`101976cc0265c571faf55ab41fee1fb6e857d976a2edae0d6b1ec11db95dfdca`.
Physical button response and final subjective motion stability remain manual
device checks.
