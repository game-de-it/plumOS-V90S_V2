# V90S YabaSanshiro 2.10.4 Validation

Date: 2026-07-14

## Goal

Build the performance-oriented YabaSanshiro 2.10.4 libretro core for V90S from
the requested upstream commit:

```text
8406a5c11d7b6186a44c7fe48f493e6de5f8cb18
```

The source identifies itself as version `2.10.4` and Git revision `8406a5c`.

## AArch64 Compatibility

The normal V90S toolchain uses GCC 12.2. The first GCC build initialized the
PowerVR GLES context, core shaders, input, and ALSA, but crashed with
`SIGSEGV`/exit code 139 at the first execution frames. Temporarily selecting
the SH2 interpreter produced the same failure, so the result was not treated
as an SH2 dynarec-only problem.

PPSSPP was used as the working V90S AArch64 reference. Its implementation uses
explicit executable-memory protection and instruction-cache flushes for JIT
code, while its V90S launcher explicitly selects GLES 2.0. These checks helped
separate the general PowerVR/JIT runtime requirements from this core's legacy
compiler behavior.

YabaSanshiro 2.10.4's own AArch64 Makefile notes that Clang runs at nearly full
speed while GCC crashes. Rebuilding the same source and options with Clang 14
eliminated the device crash. The normal core builder therefore selects
`clang`/`clang++` only for this pinned core and records that selection in the
manifest; other core recipes retain the normal toolchain defaults.

The build also backports upstream commit
`441423afaf8d0c9c2efd4c579e40cac0931fdb74`, which changes the ARM64 MOVBL
helper's destination index from caller-clobbered `w4` to `w22`. The patch is
required and causes the build to fail if it no longer applies cleanly.

## Build

The official Docker entry point builds only the requested core without
replacing the complete canonical core output:

```sh
./scripts/docker-build.sh cores \
  --filter yabasanshiro \
  --out-dir output/libretro-cores/v90s-yabasanshiro-2.10.4
```

Result:

```text
built: 1
failed: 0
skipped: 113
compiler=clang
cxx_compiler=clang++
commit=8406a5c11d7b6186a44c7fe48f493e6de5f8cb18
```

Artifact:

```text
output/libretro-cores/v90s-yabasanshiro-2.10.4/cores/yabasanshiro_libretro.so
ELF 64-bit LSB shared object, ARM aarch64, stripped
size=1622632 bytes
sha256=3ec02601138e97ed650d9009d2b9dc6d03af85a7fdffa3728c18208a95398bdb
```

The binary exports `retro_init`, `retro_run`, and `retro_api_version`. Its
runtime dependencies include `libGLESv2.so.2`, `libstdc++.so.6`, `libm.so.6`,
`libgcc_s.so.1`, and `libc.so.6`.

## Device Validation

The core was copied to `/mnt/plumos/cores/yabasanshiro_libretro.so` through a
`.new` path, hash-checked, and atomically renamed. The live SHA-256 matched the
build artifact.

Fighting Vipers was launched through the normal RetroArch wrapper with the
SH2 dynarec default. Observed state after more than two minutes:

```text
RetroArch process: alive
CPU online: 0-3
game governor: interactive
observed CPU frequency: 1800000
ALSA state: RUNNING
ALSA owner: RetroArch
```

Two framebuffer samples taken 15 seconds apart had different SHA-256 hashes,
confirming continuing rendered output rather than a static or black frame. The
only logged EGL error was the already-known initial `EGL_BAD_NATIVE_WINDOW`
probe before the working fbdev context; no segmentation fault followed in the
Clang build.

After validation, RetroArch was stopped with the PID-validated stop helper.
The frontend was restarted once with all CPUs online and the governor restored
to `ondemand`. The temporary interpreter option was removed, so the deployed
core uses its intended dynarec default.

## Virtual Hydlide VDP1 Readback Fix

Virtual Hydlide exposed a separate framebuffer-readback defect. Its game menu
initially hid the 3D background, and after correcting the GL RGBA-to-Saturn
pixel conversion, both the MAP and game-menu screens still had a black band at
the bottom.

The physical framebuffer established an exact boundary. The black region began
at output row 411 in a 640x480 frame. The core renders 320x224, so the boundary
maps to Saturn scan line 192:

```text
411 * 224 / 480 = 191.8
0x30000 / 0x400 bytes per VDP1 line = 192 lines
```

Pinned YabaSanshiro 2.10.4 sent GPU framebuffer reads through
`VIDOGLVdp1ReadFrameBuffer()` only while `addr < 0x30000`. Lines 192 through
223 therefore came from the stale CPU-side buffer and appeared black. The
hardware framebuffer is `0x40000` bytes, and `Vdp1FrameBufferReadWord()` and
`Vdp1FrameBufferReadLong()` already mask addresses with `0x3ffff`.

The required build patch is:

```text
docker/plumos-v90s-toolchain/patches/
  yabasanshiro-2.10.4-vdp1-framebuffer-readback.patch
```

It applies the following related corrections:

- route word and long reads across the full `0x40000` VDP1 address range;
- read and map the complete active GL framebuffer height;
- use actual render width/height for framebuffer bounds;
- decode explicit GL RGBA bytes while preserving transparent and indexed
  Saturn pixel semantics;
- restore the caller's GL viewport after the readback pass.

The libretro-only rebuild completed with one built core and zero failures:

```text
output/libretro-cores/v90s-yabasanshiro-vdp1-full-address-range/
sha256=051fb69c56f2c0487aff5c4e18e6cfc724975438b87bdfa968a0dd8b29caae1a
```

The host artifact and atomically deployed device core had the same SHA-256.
The user confirmed on the physical V90S that both the Virtual Hydlide MAP and
game-menu screens retained the 3D background through the bottom scan line.
The same common patch was then rebuilt and validated in the standalone route.

Framebuffer evidence is stored outside git under:

```text
output/validation/v90s-yabasanshiro-vdp1-readback/
```

`ra-before-full-address-range.png` has SHA-256 `47b483c2...9326ef` and shows
the old lower band. `sa-after-full-address-range.png` has SHA-256
`73dd17ac...bfcb26a` and shows the MAP and 3D background reaching the physical
bottom edge.
