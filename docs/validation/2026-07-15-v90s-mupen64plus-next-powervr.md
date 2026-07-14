# V90S Mupen64Plus-Next PowerVR Validation

Date: 2026-07-15

## Result

Mupen64Plus-Next now boots Super Mario 64 on the real V90S with the AArch64
dynamic recompiler and GLideN64. The game rendered the intro sequence, reached
59.09 FPS in the final 30-second capture, and stopped cleanly through the
PID-aware RetroArch stop helper.

The N64 frontend order remains unchanged: ParaLLEl-N64 is the default,
standalone Mupen64Plus is second, and Mupen64Plus-Next remains an explicitly
selectable RetroArch profile. The live FE preflight for `n64`,
`N64/SUPERMARIO64.Z64`, and `retroarch:mupen64plus_next` reports
`can_execute: yes` and resolves the fixed core in `/mnt/plumos/cores`.

## Root Cause

The previous build used commit `98c1b0d877542b01314b3b04272282ba223b65b3`
with `platform=arm64_cortex_a53_gles2`. Its live SHA-256 was:

```text
0a26dd1e28a7693d74c73a948e1acd2defc8627177969e0a293f6afe7a76ff8c
```

The dynarec process stayed alive after `Init new dynarec`, while a forced stop
then crashed. A pure-interpreter run produced a 786,583,552-byte core dump and
failed in the same graphics path, proving the CPU core selection was not the
primary fault.

The deployed core and the unstripped build had Build ID
`51d2b244ffb7a9a8533c8eedcf3da68964c6beb8`. GDB register and stack analysis
resolved the core return address to:

```text
opengl::BufferedDrawer::_updateBuffer(...)+0x5c
memcpy(destination=0x0, source=..., size=172)
```

The PowerVR Rogue GE8300 stack advertises `GL_EXT_buffer_storage`, so GLideN64
selected its persistent-buffer drawer. The corresponding `glMapBufferRange`
returned null, and GLideN64 copied vertex data to that null mapping.

## Fix

The required build patch is:

```text
docker/plumos-v90s-toolchain/patches/mupen64plus-next-powervr-buffer-storage.patch
```

`build-libretro-cores.sh` applies it only to `mupen64plus_next` and fails the
build if it no longer applies. GLideN64 already identifies PowerVR renderers;
the patch disables `bufferStorage` for that renderer so GLES uses its normal
unbuffered update and readback paths. It does not add a launch fallback or
change other GPU families.

The filtered Docker build completed with `built=1`, `failed=0`:

```text
PLUMOS_CORE_FILTER=mupen64plus_next
PLUMOS_V90S_CORES_OUT=output/libretro-cores/mupen64plus-next-powervr-test
```

Fixed core SHA-256:

```text
85f83c640735e56f036a759620ff71c667a51c66ee6032dd2f34059fa53c22cc
```

The same binary is installed in the live `/mnt/plumos/cores` path and the
current generated `output/app-layer/v90s` payload. The app-layer checksum set
passes in full.

## Hardware Evidence

Super Mario 64 ran for 30 seconds with `mupen64plus-cpucore` left at its normal
dynamic-recompiler default. Three complete 640x960 fbdev captures were taken:

| Time | Visible result | FPS | Raw framebuffer SHA-256 |
| --- | --- | ---: | --- |
| 10 s | black intro frame | 51.64 | `1db3d165485a0128ab4324815730760c54ffab6dec5765b402ea95aa057031fd` |
| 20 s | Peach message and rendered scene | 42.34 | `477ac83d63cdb5264c03b3b0738ec4ed5465bdc6396fef6f42113ef71cdc39aa` |
| 30 s | Lakitu intro scene | 59.09 | `5fe8a156b8ab49a2f319817a21ca4cc3a53cc7acaedba209c8b1beef17d12bcd` |

The RetroArch log contains `Enabled TLB`, followed by a clean shutdown:

```text
Starting R4300 emulator: Dynamic Recompiler
Init new dynarec
R4300 emulator finished.
Rom closed.
```

The complete frontend execution path was then tested with:

```text
plumos-text-ui launch n64 N64/SUPERMARIO64.Z64 \
  --profile retroarch:mupen64plus_next --no-scan --execute
```

It created RetroArch PID `3990` after four seconds, and `/proc/3990/cmdline`
contained `/mnt/plumos/cores/mupen64plus_next_libretro.so`. The process remained
active through the observation window, produced framebuffer SHA-256
`e68d8518ac10bfe9ea98367e37a3cd8229924b2efebed3ad1649972b9991c878`,
and the frontend command completed with `execute: ok` and RetroArch `rc=0`.

During the preceding diagnostic sequence, the kernel detected an inconsistent
FAT cluster deletion and protected p7 by remounting it read-only. The rootfs
power-action path rebooted the device without further FAT writes. Boot-time
`fsck.fat -a` completed with `rc=1` (repaired), after which p7 mounted `rw`, a
write/remove probe passed, and the normal FE launcher started exactly one FE.

Final live state:

```text
frontend=1
retroarch=0
mupen64plus_next=85f83c640735e56f036a759620ff71c667a51c66ee6032dd2f34059fa53c22cc
```

No broad process-name kill was used. The FE executable was identity-checked,
temporarily stopped with `SIGSTOP`, and restored after each run. RetroArch was
stopped with `/mnt/plumos/bin/v90s-retroarch-stop`.
