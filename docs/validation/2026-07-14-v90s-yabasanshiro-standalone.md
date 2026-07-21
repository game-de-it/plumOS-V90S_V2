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

## Duplicate-Process Fix

The first long-running test eventually stopped producing frames while leaving
its process and ALSA PCM handle alive. A diagnostic restart then created a
second YabaSanshiro process, which failed with `ALSA: Device or resource busy`.
Both framebuffer pages remained static and the physical LCD and speaker were
black and silent.

The standalone launcher now records the exact PID and executable under
`/run/plumos-standalone`, refuses a second live instance, and ships
`plumos-standalone-stop`. The stop helper validates `/proc/PID/exe`, sends
`SIGTERM`, and escalates only that verified PID to `SIGKILL` after three
seconds. It never uses a broad process-name match.

After removing the two verified stale processes, Fighting Vipers started as a
single process. Framebuffer hashes changed across samples, ALSA reported the
new PID as its sole owner, and no SDL audio initialization error was logged.
The user then confirmed that the physical device displayed and played the game
normally.

The deployed launcher was also tested while that process remained active. A
second launch returned exit code `75` with `standalone emulator already
running`, the verified live-instance count remained one, and ALSA ownership
did not change.

## RetroArch Exit Comparison

A separate live test checked whether the libretro YabaSanshiro route was the
process that failed to stop. Before launch, the previously running process was
PID `5465` with this executable:

```text
/mnt/plumos/standalone/yabasanshiro/bin/yabasanshiro
```

It was therefore the standalone runtime, not RetroArch. It was stopped through
the exact-PID `plumos-standalone-stop yabasanshiro` helper before starting the
FE test.

The FE then started `retroarch:yabasanshiro` with RetroArch PID `9857` and
launcher PID `9439`. RetroArch owned framebuffer/DRM input resources and ALSA
PCM, while the FE waited for its launch command. The user selected the normal
RetroArch quit action. The process reached core teardown and exited normally:

```text
[INFO] [Config] Saved config to "/mnt/plumos/config/retroarch/retroarch-v90s.cfg".
[INFO] [Core] Unloading game...
[INFO] [Core] Unloading core...
[INFO] [Core] Unloading core symbols...
retroarch-launch: retroarch exited rc=0
```

Within about four seconds, both RetroArch and its launcher were gone, ALSA was
closed, both `/run/plumos-v90s/*.pid` files had been removed, and the existing
FE process resumed drawing. No RetroArch stop defect was reproduced. The
observed stale owner was the standalone runtime; future diagnosis must compare
`/proc/PID/exe` instead of treating any YabaSanshiro session as RetroArch.

## Standalone Menu And Exit Fix

The first controlled standalone exit attempt exposed two separate issues. The
user initially tried to open a menu inside the Saturn game rather than the
RetroArena emulator menu, and the standalone process exited. This was not used
as evidence for the emulator-menu exit path. It did expose that the original
launcher used `exec`, so an emulator exit left stale `.pid` and `.exe` records
under `/run/plumos-standalone`.

The next attempt opened the RetroArena menu with the physical Function button,
but its controls did not work. RetroArena has separate input paths:

- the V90S JSON/direct mapping already drove Saturn gameplay;
- menu navigation called `InputConfig`, which only loaded an
  EmulationStation-style XML file that plumOS does not provide.

The V90S YabaSanshiro patch now gives `adc_gamepad` an explicit menu mapping:

```text
D-pad hat 0  -> menu up/down/left/right
button 0     -> confirm
button 1     -> back
button 9     -> start
button 10    -> Function/menu toggle
```

The common standalone launcher now supervises the emulator as a child instead
of replacing itself with `exec`. It writes the child PID, waits for the exact
child, preserves its exit status, and removes the PID/executable records from
an `EXIT` trap only when they still belong to that child. The targeted stop
helper continues to validate `/proc/PID/exe` before sending a signal.

Only YabaSanshiro was rebuilt, then the binary and updated launcher were
deployed over ADB. Device and host SHA-256 values matched. The user confirmed
that the physical Function button opened the menu and that D-pad, confirm, and
back controls worked. Exiting from that menu removed YabaSanshiro PID `831`
and supervisor PID `533`, closed ALSA, removed both ownership records, and
resumed the same FE PID `6636`.

## Full VDP1 Address Range Validation

The common VDP1 framebuffer patch described in
`2026-07-14-v90s-yabasanshiro-2.10.4.md` is applied before the standalone-only
GL-context ownership patch. This keeps both routes on the same pixel decoding,
full-height readback, and `0x40000` VDP1 address contract. The standalone patch
then keeps a coherent mapped frame across SCU DMA reads and returns GL-context
ownership at DMA completion or VBlank.

The single-emulator rebuild completed with zero failures:

```text
./scripts/docker-build.sh standalone yabasanshiro
built=1 failed=0 skipped=9
sha256=19969852f184c3086b6fda292eeecbf8ed4ae84925c431aa30a794aa9cd8c0bf
```

The host and atomically deployed device hashes matched. Virtual Hydlide was
started through the normal FE standalone profile. The captured MAP frame showed
the map and 3D background through the physical bottom edge, and the user
confirmed that both MAP and game-menu screens no longer contain the lower black
band. This also proves the shared correction does not depend on RetroArch's GL
context path.

## Final Hardware Acceptance

On 2026-07-22 the user confirmed that standalone YabaSanshiro gameplay and
performance have no remaining practical issue on the physical V90S. Together
with the prior video, audio, gameplay input, emulator-menu input, clean exit,
and FE-return evidence, this completes the standalone YabaSanshiro acceptance
check.
