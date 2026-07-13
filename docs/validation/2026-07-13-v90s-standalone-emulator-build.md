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

PPSSPP is built with ARM64, fbdev, GLES2, and bundled FFmpeg enabled. Direct
PPSSPP EGL ownership is disabled because the V90S SDL2 PowerVR driver owns the
EGL display, surface, and context. This keeps PSP video playback support in the
package and avoids importing the A30-specific display rotation patches.

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
AUDIODEV=hw:0,0
LD_LIBRARY_PATH=/usr/lib/powervr:/tmp/plumos-standalone-lib:/mnt/plumos/lib/plumos-sdl2-powervr:/mnt/plumos/lib
```

FAT32 cannot represent the staged ELF SONAME symlinks reliably. The package
therefore records SONAME-to-file mappings and the launcher materializes only
the required symlinks under `/tmp/plumos-standalone-lib` at runtime.

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

## PPSSPP Hardware Validation

The FE launch route was exercised on the V90S with Ridge Racers:

```text
plumos-text-ui launch psp \
  "PSP/Ridge Racers (Japan)/Ridge Racers (Japan).iso" \
  --profile standalone:ppsspp --execute --no-scan
```

The route started the packaged `PPSSPPSDL`, booted the ISO, and opened ALSA
PCM `hw:0,0`. Audio was audible from the V90S speaker.

The first running build produced correct RGB content in both 640x480 pages of
`/dev/fb0`, but the physical LCD remained black. Alpha extraction from the
640x960 BGRA framebuffer returned zero for every pixel. The StockOS display
layer consumes per-pixel alpha, so the otherwise valid PPSSPP image was fully
transparent.

The V90S PPSSPP patch now preserves RGB and clears only the default
framebuffer alpha plane to opaque immediately before `SDL_GL_SwapWindow()`.
It also requests an 8-bit SDL GL alpha channel. After deployment:

```text
framebuffer alpha min=65535 max=65535 mean=65535
PPSSPPSDL sha256=2b5e98aa4cd75a58fdc38069d692296815eb61c7324f6e7c6b174b6b033daaad
```

The 16-bit ImageMagick quantum value `65535` means fully opaque. The captured
frame showed Ridge Racers and the user confirmed that the same image appeared
on the physical LCD. The live ALSA PCM owner was the same PPSSPP process.

Ridge Racers initially crashed when entering a race. A captured 434 MiB core
dump identified this stack:

```text
GLQueueRunner::PerformCopy
GLQueueRunner::RunSteps
GLRenderManager::Run
GLRenderManager::ThreadFrame
```

The PowerVR driver advertises `GL_EXT_copy_image`, but PPSSPP's Linux GLES2
path left `glCopyImageSubDataOES` null because the EXT/NV alias loader was
Android-only. The V90S patch now resolves the advertised OES, NV, or EXT entry
point with `eglGetProcAddress` and enables framebuffer copy only when the
function pointer is valid. The user then entered and drove a race successfully.

## PPSSPP Performance Result

The V90S frontend originally accepted only two CPU cores, inherited from the
MMF contract. The V90S parser now accepts one through four cores, PSP defaults
to four, and `plumos-standalone-launch` applies the requested online-core count
and governor. The live launch plan now reports:

```text
cpu: performance
cpu_cores: 4
```

Ridge Racers reaches 60/60 in light scenes but falls to approximately 38/60 in
the heavy grandstand scene. At 39/60, live measurements showed:

```text
PPSSPP main thread: about 104 percent of one CPU core
EmuThread: about 27 percent of one CPU core
CPU: four cores online, performance governor, 1.8 GHz
GPU: 35 percent at approximately 702 MHz
CPU thermal zone: 80.8 C; first trip point: 95 C
internal resolution: 1x
```

The same scene remained approximately 38 fps with Vulkan, anisotropic
filtering disabled, and spline/Bezier quality set to minimum. This rules out
the PowerVR GLES presentation path, GPU saturation, core parking, thermal
throttling, and those quality settings as the dominant limit. The current
limit is PPSSPP's saturated single main/render thread on the Cortex-A53.

Auto Frame Skip may improve emulated game speed by presenting fewer frames,
but it must not be reported as true 60 fps. The V90S default remains frame skip
off. Vulkan was an explicit test only; the reproducible launcher remains on
GLES2.

## Remaining Hardware Validation

PPSSPP still needs save/config persistence and clean return to the FE. Its
controller, display, audio, race-start stability, and Ridge Racers performance
characteristics are validated. The other five standalone emulators still need
complete real-device display, audio, controller, save, and FE-return passes.
