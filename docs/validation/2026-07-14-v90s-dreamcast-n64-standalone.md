# V90S Dreamcast And N64 Standalone Validation

Date: 2026-07-14

## Scope

Build native aarch64 Dreamcast and N64 standalone emulators, expose them
through the frontend, and validate the intended StockOS-derived PowerVR and
audio paths on a live POWKIDDY V90S.

## Build And Packaging

The normal build entry point now supports both full and incremental builds:

```sh
./scripts/docker-build.sh standalone
./scripts/docker-build.sh standalone flycast
./scripts/docker-build.sh standalone mupen64plus
```

The full build produced eight standalone recipes with zero failures. A
Flycast-only build produced one updated recipe and seven preserved recipes;
the standalone output directory count remained eight.

The new components are:

| System | Emulator | Ref | Renderer |
| --- | --- | --- | --- |
| Dreamcast | Flycast | `v2.6` | GLES2 through V90S SDL2 PowerVR |
| N64 | Mupen64Plus | `2.6.0` | Rice GLES through V90S SDL2 PowerVR |

Mupen64Plus packages its console UI, core, SDL audio/input, HLE RSP, and Rice
video plugin under `/mnt/plumos/standalone/mupen64plus`. Its internal SONAME
link is materialized as a regular file so the payload remains valid on FAT32.

## Frontend Contract

The frontend keeps the validated libretro profiles available:

```text
n64:       standalone:mupen64plus, retroarch:parallel_n64,
           retroarch:mupen64plus_next
dreamcast: retroarch:flycast_xtreme, retroarch:flycast
```

Mupen64Plus remains the N64 default. Flycast Xtreme libretro is the Dreamcast
default. Standalone Flycast remains packaged for direct diagnostics, but is no
longer exposed by the FE because later gameplay validation found black frames,
audio stutter, and rendering defects.

## V90S N64 Controls

Mupen64Plus did not ship an `adc_gamepad` definition. The build now appends a
V90S-specific `InputAutoCfg.ini` entry with this policy:

| V90S control | N64 control |
| --- | --- |
| D-pad | analog stick and N64 D-pad |
| A / B | A / B |
| X / Y | C-down / C-up |
| L2 / R2 | C-left / C-right |
| L / R | L / R |
| Select | Z trigger |
| Start | Start |

The live Mupen64Plus log confirmed:

```text
Input: N64 Controller #1: Using auto-config with SDL joystick 0 ('adc_gamepad')
```

## Live Runtime Evidence

Flycast launched `Crazy Taxi (Japan).chd`, remained active for the initial
observation window, and reported:

```text
Monitor refresh rate: 60 Hz (640 x 480)
Vendor 'Imagination Technologies' Renderer 'PowerVR Rogue GE8300'
SDL: Opened joystick 0 on port 0: 'adc_gamepad'
ALSA PCM state: RUNNING
framebuffer sha256: 31ad22614c859ea9f1464829e973b70beb720a4894a8e01e9f18921c87fd6120
```

This initial result did not cover enough gameplay. Later tests reached the
city scene and showed that upstream standalone Flycast 2.6 is not a valid V90S
runtime:

- the normal PowerVR-reported GLES 3.2 path produces black RGB scanout;
- forcing the GLES2 texture-backed path makes the image visible;
- the GLES2 path runs at about 46 FPS, stutters audio, and drops textures;
- 240p, larger audio buffers, and one level of automatic frame skipping do not
  materially improve the result;
- forcing opaque window alpha does not help; black captures already have alpha
  255, so the failure is in game rendering rather than scanout composition.

The standalone binary is therefore retained only for direct diagnostics and
must not appear as a normal FE choice.

Mupen64Plus launched `SUPERMARIO64.Z64`, remained active for the observation
window, and reported:

```text
Video: Using OpenGL: PowerVR Rogue GE8300 - OpenGL ES 3.2
Audio: Initializing SDL audio subsystem...
ALSA PCM state: RUNNING
framebuffer sha256: 6de9e73ad4e8b5afcb1d2764f171af8abaea5226208b0b1a6b6f9366d57ae30c
```

Each test stopped only the exact validated emulator PID with `TERM`; both
processes exited within one second. The frontend was then restored as one
`plumos-controller-ui-fbdev` process.

## Remaining Physical Checks

The software paths for display, audio, and controller discovery are live.
Long-play performance, every physical N64 mapping, save persistence, emulator
hotkey exit, and visual confirmation of clean return to the FE remain device
interaction checks rather than automated claims.
