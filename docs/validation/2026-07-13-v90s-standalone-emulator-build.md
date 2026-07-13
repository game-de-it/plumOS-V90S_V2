# V90S Standalone Emulator Build

Date: 2026-07-13

## Goal

Implement the official V90S `standalone` build target using the standalone
emulator set shipped in the plumOS MMF final package, with PPSSPP added from
the plumOS A30 build model.

PicoArch remains a separate build target and is not counted as a standalone
emulator in this validation.

## Build Entry Point

```sh
JOBS=4 ./scripts/docker-build.sh standalone
```

Result:

```text
built=6
failed=0
skipped=0
```

Output:

```text
output/standalone-emulators/v90s/
```

## Built Set

| ID | Version/ref | Executable |
| --- | --- | --- |
| `ppsspp` | `v1.20.4` | `PPSSPPSDL` |
| `scummvm` | `v2026.2.0` | `scummvm` |
| `easyrpg` | `0.8.1.1` | `easyrpg-player` |
| `openbor` | `v6391` | `OpenBOR` |
| `dosbox-staging` | `v0.82.2` | `dosbox` |
| `pcsx_rearmed` | `r26l` | `pcsx` |

All six executables were verified with `file` as 64-bit ARM aarch64 ELF
executables using `/lib/ld-linux-aarch64.so.1`.

PPSSPP is built with ARM64, EGL, fbdev, GLES2, and bundled FFmpeg enabled.
This keeps PSP video playback support in the package and avoids importing the
A30-specific display rotation patches.

## V90S Runtime Boundary

The standalone package recursively stages non-vendor shared-library
dependencies under:

```text
output/standalone-emulators/v90s/lib/
```

The dependency collector deliberately excludes:

```text
libEGL
libGLESv2
libGL
libMali
libSDL2-2.0
```

PowerVR EGL/GLES remains owned by `v90s-stockos-r1`. SDL2 remains owned by the
V90S `sdl2-powervr` target. This preserves the distribution policy instead of
accidentally shipping Debian Mesa or a generic SDL2 display path.

The V90S SDL2 PowerVR target was rebuilt successfully and reported the `mali`
video driver.

## App-Layer Integration

The standalone package is copied into the normal FAT32 app-layer contract:

```text
/mnt/plumos/standalone/<id>/
/mnt/plumos/bin/plumos-standalone-launch
/mnt/plumos/lib/
```

The generated app layer contains all six standalone directories and is about
724 MiB total, below the current approximately 1 GiB FAT32 partition target.

The launcher uses:

```text
SDL_VIDEODRIVER=mali
SDL_AUDIODRIVER=alsa
LD_LIBRARY_PATH=/mnt/plumos/lib/plumos-sdl2-powervr:/mnt/plumos/lib
```

Each emulator receives a writable state root under:

```text
/mnt/plumos/state/standalone/<id>/
```

## Verification

The following host-side checks passed:

- standalone manifest summary: six built, zero failed, zero skipped
- all standalone executables are aarch64 ELF files
- standalone `checksums.sha256` validates all files
- app-layer `checksums.sha256` validates all files
- all six executables resolve their dynamic dependencies when checked against
  the app-layer libraries, V90S SDL2 PowerVR, and vendor PowerVR libraries
- `plumos-standalone-launch` passes shell syntax validation

The app-layer manifest records all six executable paths, and its complete
checksum set also validates successfully.

## Remaining Hardware Validation

This validation proves build and packaging completeness. It does not yet prove
runtime behavior on the V90S LCD, speaker, or physical controller.

Each emulator still needs a real-device pass for display, audio, controller
mapping, save/config persistence, and safe return to the frontend. PPSSPP in
particular needs a lightweight PSP title before its default performance and
graphics settings can be finalized.
