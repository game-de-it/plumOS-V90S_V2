# V90S ParaLLEl-N64 KNULLI/A133 validation

Date: 2026-07-15

## Scope

Restore visible N64 output on the physical V90S without changing the validated
RetroArch PowerVR route, then verify audio and all primary controller inputs.

Test content:

```text
/mnt/plumos/roms/N64/Super Mario 64*.z64
/mnt/plumos/roms/N64/AeroGauge [V1.1].z64
```

## Initial failure

The previous core loaded content and produced audio, but its GLideN64, gln64,
and Glide64 paths left the game framebuffer black. Rice rendered severe
triangle corruption. Angrylion produced a very dark, slow image. This exposed
that the earlier all-core matrix had confirmed core loading rather than usable
N64 video.

The previous deployed core was:

```text
parallel_n64_libretro.so
b1b1cee04f552bed8809cdbedf691a2a7be2818b9e91d4df3ebae9f5013bb662
```

## Build correction

ParaLLEl-N64 is pinned to KNULLI's V90S-compatible upstream revision and built
with an explicit Allwinner H5/A133-class AArch64 GLES2 target:

```text
repository: https://github.com/libretro/parallel-n64.git
revision:   1b57f9199b1f8a4510f7f89f14afa9cabf9b3bdd
platform:   h5
dynarec:    aarch64
CPU:        Cortex-A53 / ARMv8-A
graphics:   GLES2
```

The local patch adds only the KNULLI-derived H5 target to the upstream
Makefile. The normal build entry point remains:

```sh
PLUMOS_CORE_FILTER=parallel_n64 FAIL_ON_CORE_ERROR=1 JOBS=4 \
  ./scripts/docker-build.sh cores
```

The build completed with one built core and zero failures. Host and device
SHA-256 matched:

```text
36c0a20d0eb0b458770ee8dd7102e530990e1995d73ca39a9fcce44abb3d3278
```

## Runtime defaults

The validated core options are:

```text
parallel-n64-gfxplugin = "gliden64"
parallel-n64-rspplugin = "hle"
parallel-n64-screensize = "640x480"
```

The V90S D-pad is exposed as digital buttons, while N64 content expects the
left analog stick. A core-specific remap translates only the ParaLLEl-N64
D-pad directions to RetroPad left-analog directions. Other cores keep the
normal V90S mapping. The launcher installs this remap only when it is missing
and adds absent core-option defaults without replacing user values.

## Physical V90S result

- Super Mario 64 displayed its game scene through GLideN64.
- AeroGauge displayed the vehicle-selection and race scenes.
- Audio played during the N64 test.
- ABXY, shoulder, Start/Select, and D-pad input worked. The user explicitly
  confirmed the D-pad after the core-specific remap was applied.
- AeroGauge showed approximately 26.5 fps in a race scene. Rendering
  compatibility is fixed, but this title is not full speed and remains a
  performance investigation rather than a video-path failure.

RetroArch was stopped through `v90s-retroarch-stop`; the stopped, identity-
checked FE process was resumed afterward. Final live state was one running FE,
no RetroArch process, and no stale RetroArch pidfile.
