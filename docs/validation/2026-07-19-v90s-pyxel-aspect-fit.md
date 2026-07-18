# V90S Pyxel Aspect Fit

Date: 2026-07-19

## Problem

`LastEmulator.pyxapp` initializes Pyxel at 720x480. The V90S SDL2 PowerVR
window is correctly fixed at the LCD's native 640x480, but official Pyxel 2.9.3
does not select a render scale below 1.0. Its 720-pixel-wide screen was therefore
centered at native size and cropped by 40 pixels on both sides. The captured
prologue frame showed the `PROLOGUE` title extending beyond both LCD edges.

## Ownership boundary

The fix does not modify the Pyxel wheel or files inside
`/mnt/plumos/venvs/pyxel`. `Apps -> Pyxel Setup` and a project's
`requirements.txt` remain free to install an official Pyxel update.

`plumos-pyxel-v90s-launch` instead loads the OS-owned
`/mnt/plumos/lib/plumos-pyxel-fit.so`. The library observes the SDL2/OpenGL
screen rectangle used by Pyxel. Rectangles larger than 640x480 are reduced by
the smaller axis scale, retaining aspect ratio, and then centered. Rectangles
which already fit are not changed. The library is active only for the V90S
Pyxel launcher and cannot affect RetroArch, the frontend, or standalone
emulators.

The `pyxel-runtime` build compiles this library for AArch64 and records its
source and binary SHA-256 values in the runtime manifest and checksum list. The
factory venv is still installed from the unmodified official PyPI wheel.

```text
source ca6681906b03c9d9cfff38a64cc6e7937d74d16f455d8aed69cba05fe93b42ca
binary 35ba154ec2851ceffa9e18326e17760e7a09f6098f152ce146821cc8cc658325
```

## Live validation

The live device used the official `pyxel=2.9.3` environment. `/proc` mappings
proved that the Pyxel process loaded both
`/mnt/plumos/lib/plumos-sdl2-powervr/libSDL2-2.0.so.0` and
`/mnt/plumos/lib/plumos-pyxel-fit.so`.

For `LastEmulator.pyxapp`, the runtime reported:

```text
plumos-pyxel-fit: source=720x480 output=640x427 factor=0.888889 offset=0.0,26.7
```

The resulting framebuffer contained the complete title screen with horizontal
geometry intact and approximately 27-pixel bars above and below. Its captured
PNG SHA-256 was:

```text
b6f1ed20f541755463f9e714d0c478e0bcfc7b8ef6cd1f88521361d87db9936f
```

A separate 480x480 test drew a border and unique color blocks at all four
corners. All corners were visible, with the square centered at x=80 through
x=559 and 80-pixel bars on the left and right. Its captured PNG SHA-256 was:

```text
7a3fc0948e34ccc1945a125c562ad908cc2f602ecfcc575fba029cf85e83dd41
```

These checks prove both oversized 3:2 fitting and already-fitting 1:1
positioning on the real 640x480 framebuffer. Controller input remains on
Pyxel's existing gamepad route; the fit layer changes only final screen
uniforms.
