# V90S YabaSanshiro Standalone Validation

Date: 2026-07-14

## Goal

Keep YabaSanshiro as the only Saturn libretro choice, remove the unusable
PicoArch Saturn route, and add a native standalone YabaSanshiro choice with the
standalone route selected by default.

## Source And Build

The standalone build uses the same performance-oriented YabaSanshiro 2.10.4
source as the validated libretro core:

```text
repo=https://github.com/libretro/yabause.git
commit=8406a5c11d7b6186a44c7fe48f493e6de5f8cb18
port=retro_arena
```

KNULLI's standalone recipe was used as the runtime reference. Its important
AArch64 choices are `retro_arena`, `USE_EGL=ON`, `SH2_DYNAREC=FALSE`, and
`YAB_WANT_DYNAREC_DEVMIYAX=ON`. The plumOS build keeps those choices, uses the
already validated Clang workaround for this old release, and links only EGL and
GLES instead of accidentally retaining Docker-host GLUT, GLU, and X11
dependencies.

The one-emulator build command is:

```sh
./scripts/docker-build.sh standalone-emulators yabasanshiro
```

Result:

```text
built=1 failed=0 skipped=9
ELF 64-bit LSB pie executable, ARM aarch64
sha256=8eff35380bbde97a1088af4191dbb9dd20a6b68c14da197d63826b217cb5daa0
```

The final direct graphics dependencies are `libEGL.so.1`, `libGLESv2.so.2`,
and the plumOS PowerVR SDL2 runtime. Desktop `libGL`, `libGLU`, `libX11`, and
`libXrandr` are absent from the final executable's `DT_NEEDED` list.

## V90S Input

The old 2.10.4 `retro_arena` JSON mapping path throws a nlohmann JSON type
exception even with an empty device map. The V90S-specific patch bypasses that
broken path only for the built-in `adc_gamepad`; external controllers retain
the upstream path.

The built-in mapping follows the KNULLI Saturn layout. D-pad and Start map
directly, the six Saturn face buttons use V90S ABXY/L/R, L/R use V90S L2/R2,
and physical Function button 10 opens the standalone menu.

## FE Policy

The Saturn system definition now exposes exactly:

```text
standalone:yabasanshiro  (default, performance)
retroarch:yabasanshiro
```

Beetle Saturn and Mednafen Saturn were removed. The text UI's automatic
PicoArch companion generation is disabled for Saturn, so
`picoarch:yabasanshiro` is not recreated behind `systems.json`.

## Live Validation

The standalone binary and FE changes were deployed through ADB. `VH.iso`
started with the StockOS BIOS and the live process reported:

```text
renderer=PowerVR Rogue GE8300
OpenGL ES=3.2 build 1.19@6345021
ALSA pcmC0D0p=RUNNING
controller=adc_gamepad event4
CPU governor=performance
CPU frequency=1800000
```

Two framebuffer samples three seconds apart had different hashes. A captured
640x480 framebuffer showed the non-black Vampire Hunter title sequence, proving
continuing game rendering rather than a static initialization frame. The ALSA
PCM stream remained active and owned by the standalone process.

Physical controller behavior, Function-menu operation, gameplay performance,
and clean return to the FE remain pending user observation.
