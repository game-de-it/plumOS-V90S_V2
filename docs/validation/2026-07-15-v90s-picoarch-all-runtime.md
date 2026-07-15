# V90S PicoArch all-route runtime validation

## Scope

This validation covers every PicoArch profile that the live frontend can offer
for currently indexed content. The test derives profiles with the same rules as
the frontend, launches them through `plumos-text-ui --execute`, observes the
runtime for four seconds, verifies the loaded core and framebuffer update, and
stops only the PID owned by `plumos-picoarch-stop`.

The final inventory is:

```text
candidate systems: 59
unique cores:      78
launch routes:     97
working routes:    94
data prerequisites: 3
segmentation faults: 0
```

This is startup, render, and process-lifecycle coverage. It does not claim
complete gameplay, input, audio, or save-state validation for every route.

## PUAe segmentation fault

The Amiga crash was reproduced with a core dump from the live V90S. The AArch64
backtrace ended in `strlen` while PUAe called `retro_init`, then set its libretro
core options, and PicoArch entered `options_init`.

`RETRO_ENVIRONMENT_SET_CORE_OPTIONS` passes a direct
`struct retro_core_option_definition *`. The pinned PicoArch revision treated
that pointer as a pointer-to-pointer and dereferenced unrelated memory. The V90S
build now passes the direct definition array to `options_init`.

Both PUAe profiles now remain active and update the framebuffer:

```text
picoarch:km_puae_xtreme_amped  RUNNING
picoarch:puae                  RUNNING
```

## Host interfaces

The full run found two more crashes caused by frontend interfaces that PicoArch
did not provide:

- Lutro required the libretro performance callback interface.
- GME crashed in its bundled VFS fallback while closing a playlist file.

The V90S PicoArch build now provides monotonic timing, ARM NEON/ASIMD feature
flags, performance counters, and libretro VFS v3 file/directory operations.
PCSX-ReARMed is deliberately allowed to retain its bundled VFS because that
implementation carries the CD-ROM sector semantics needed by multi-track PSX
images. With the generic host VFS, PCSX loaded the image but failed at LBA 4.

Focused hardware regression after the final build:

```text
puae          RUNNING  framebuffer changed
lutro         RUNNING  framebuffer changed
gme           RUNNING  framebuffer changed
pcsx_rearmed  RUNNING  framebuffer changed
```

## ChaiLove

ChaiLove embeds its own SDL video runtime and cannot acquire another V90S video
device below PicoArch. It exits before useful content execution and previously
ended in a segmentation fault. The frontend no longer synthesizes the
`picoarch:chailove` companion profile. Its RetroArch profile remains available.

## Remaining prerequisites

Three offered routes reached their expected core but could not load the test
content. They did not segfault:

| System | Profile | Required action |
| --- | --- | --- |
| Channel F | `picoarch:freechaf` | Add `sl90025.bin`, `sl31253.bin`, and `sl31254.bin`; the experimental HLE rejects function `0xd0`. |
| Neo Geo | `picoarch:fbalpha2012` | Supply a ROM/BIOS set matching FBA 2012; required `033-m1.m1` CRC `5be10ffd` is absent. |
| Neo Geo | `picoarch:fbalpha2012_neogeo` | Supply the same generation-matched FBA 2012 ROM/BIOS set. |

## Evidence

The final deployed binaries are:

```text
e33c3b0b8f3ff3014ea94abda8107194cb60f6e933156f101b9aca0853a2f374  /mnt/plumos/picoarch/bin/picoarch
e698fd2fdd3b59f9dd30ce14bf5134b707b888464535803b16c5305f3074f5bd  /mnt/plumos/bin/plumos-text-ui
```

Host-side evidence directories:

```text
output/validation/v90s-fe-pico-smoke-20260715-final
output/validation/v90s-fe-pico-smoke-20260715-vfs-regression
```

The 97-route run ended with one frontend process, no PicoArch process, and no
PicoArch PID file. The final focused regression ended in the same state.

Repeat the matrix with:

```sh
scripts/v90s-fe-pico-smoke-test.sh \
  --out-dir output/validation/v90s-fe-pico-smoke-$(date +%Y%m%d-%H%M%S)
```
