# V90S Pyxel Runtime Image Inclusion

Date: 2026-07-19

## Root cause

The four-partition SD image contained Python 3.11, the V90S Pyxel launcher,
Pyxel Setup, and the default requirements file. It did not contain the mutable
virtual environment at `/mnt/plumos/venvs/pyxel`. That environment had been
installed on the earlier development card and was therefore lost when the new
image was written. SD2 still contained the `.pyxapp` files, so FE discovery
passed but launch failed before the runtime started.

## Build fix

The official build now exposes:

```sh
./scripts/docker-build.sh pyxel-runtime
```

It builds an AArch64 copied-file venv from a pinned lock file and emits a
manifest plus SHA-256 metadata under `output/pyxel-runtime/v90s`. The artifact
contains:

```text
Python=3.11.2
pyxel=2.9.3
pygame=2.6.1
numpy=2.4.6
Pillow=12.3.0
files=1680
size=143 MiB
```

The build validates imports with the plumOS PowerVR SDL 2.30 runtime rather
than the toolchain image's older SDL. Strict app-layer assembly now requires
and merges this artifact, so subsequent SD images include the working venv.
Tests, examples, and wheel documentation are omitted from the release runtime.
The unnecessary `lib64 -> lib` convenience link is also omitted to prevent the
app-layer copier from duplicating 149 MiB.

The complete app layer no longer fitted the original 1536 MiB p3 seed while
retaining the required 256 MiB free-space guard. The seed allocation is now
1600 MiB and still expands to exactly 8192 MiB on first boot. This adds only
64 MiB to the downloadable image rather than shipping a fragile nearly-full
filesystem.

The provisioning initramfs, boot-image manifest, assembler, structural image
verifier, policy, and TODO now share the 1600 MiB value. The rebuilt p2 image
has SHA-256
`d6314f6f8497e1f34e791cbac99716b557652264635f5881027d060e19687802`.
The complete four-partition preflight passed with 1,319,412 KiB used in p3,
leaving about 311 MiB before first-boot expansion.

## Live validation

The generated app layer was deployed over ADB in 11 verified chunks. On the
device, `pip check` reported no broken requirements and `plumos-pyxel-setup
status` verified all four pinned packages. `/mnt/plumos` remained ext4 with
6.4 GiB free after deployment.

After release pruning, the live venv was reduced to the same 1,680 files as the
build artifact. Every remaining venv entry passed the app-layer SHA list,
`pip check` and all four imports passed again, and no runtime package version
changed.

The V90S launcher exports `PYTHONDONTWRITEBYTECODE=1`. A final five-second game
run kept the venv at exactly 1,680 files before and after execution, avoiding
untracked `__pycache__` writes in the factory runtime.

`finardry.pyxapp` then remained running for the bounded hardware test as:

```text
/mnt/plumos/venvs/pyxel/bin/python3 -m pyxel play \
  /mnt/plumos/roms/pyxel/finardry.pyxapp
```

The process maps proved that it loaded the StockOS PowerVR EGL/GLES libraries,
`/mnt/plumos/lib/plumos-sdl2-powervr/libSDL2-2.0.so.0`, and the plumOS ALSA
runtime. The framebuffer SHA-256 during execution was
`c1a430281f1c3de59f85b86632e70db568e41d46d5eebfee2d633c4eade2afef`.
The audio router selected `internal_mono`, the bounded stop completed, and
exactly one frontend process was restored.
