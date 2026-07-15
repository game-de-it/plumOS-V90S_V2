# Release core-set recovery

Date: 2026-07-15

## Symptom

Games selected from the frontend did not start. The visible FE remained on the
ROM list and no RetroArch process survived.

The FE launch log identified the failed preflight:

```text
core: /mnt/plumos/cores/quicknes_libretro.so (missing)
rom_exists: yes
can_execute: no
error: launch plan is not executable
```

The FAT32 app layer and SD2 ROM/BIOS mounts were writable and had sufficient
free space. This initial preflight failure was not caused by the ROM,
controller action, or mount state.

## Causes

### Partial core package

A filtered Parallel-N64 build used the canonical output directory. The core
builder removed that directory before every build, so the former complete set
was replaced by one file. The later app-layer build treated any nonzero core
count as complete, and the release image therefore contained only:

```text
/mnt/plumos/cores/parallel_n64_libretro.so
```

### Stale binary route

After restoring QuickNES, FE preflight succeeded but the launch wrapper still
used the former squashfs path:

```text
retroarch-launch: RetroArch binary missing: /usr/local/bin/retroarch
```

The distribution policy assigns RetroArch to the writable app layer. The
packaged binary was present at `/mnt/plumos/bin/retroarch`, so the generated
route and both FE wrappers were corrected to use that path.

### FAT32 SONAME aliases

The corrected binary route exposed one more packaging error:

```text
/mnt/plumos/bin/retroarch: error while loading shared libraries:
libxkbcommon.so.0: cannot open shared object file
```

The real AArch64 library was packaged as `libxkbcommon.so.0.0.0`, but FAT32
cannot preserve the normal Linux SONAME symlink. The standalone launcher
already solved this by creating validated transient aliases under `/run` from
`config/standalone/soname-links.tsv`. RetroArch now uses the same mapping and
prepends `/run/plumos/retroarch/lib` to `LD_LIBRARY_PATH`. Strict app-layer
generation validates the mapping and every referenced real library.

## Recovery

The retained recipe build trees contained 115 libretro shared objects. Every
object was verified as AArch64. Applying the recipe staging names and four
compatibility aliases reconstructed the current package:

```text
recipes staged: 114
cores:           118
info files:      111
failed:          0
```

The core set, info files, and core-specific runtime libraries were deployed to
the live V90S over ADB without replacing user settings. Device verification
checked 258 core/info/runtime checksum entries with zero failures.

The NES launch plan then changed to:

```text
core: /mnt/plumos/cores/quicknes_libretro.so (exists)
rom_exists: yes
can_execute: yes
```

## Recurrence prevention

- `./scripts/docker-build.sh cores` now builds the complete catalog by default.
- filtered builds automatically use
  `output/libretro-cores/v90s-filtered/FILTER`;
- a filtered build cannot target the canonical output without the explicit
  `--replace-canonical` option;
- `--stage-existing` reconstructs staged artifacts from existing AArch64 build
  trees;
- strict app-layer generation rejects fewer than 118 cores and records the
  staged/minimum counts in `manifest.json`.

Validation results:

```text
canonical after filtered QuickNES test: 118
isolated filtered QuickNES output:       1
canonical replacement guard:            PASS
partial strict app-layer guard:          PASS
strict full app-layer core count:        118
strict full app-layer complete:          true
```

## Live FE-path result

The live V90S was tested over the real FE action path, not by launching
RetroArch directly. The FE selected NES content and started:

```text
/mnt/plumos/bin/retroarch
  --config /mnt/plumos/config/retroarch/retroarch-v90s.cfg
  -L /mnt/plumos/cores/quicknes_libretro.so
  /mnt/plumos/roms/nes/Akumajou Densetsu.nes
```

Runtime proof:

```text
RetroArch: 1.22.2
core: QuickNES
core FPS: 60.00
video: PowerVR Rogue GE8300, OpenGL ES 3.2
audio: ALSA hw:0,0 initialized
input: POWKIDDY V90S Gamepad configured in port 1
```

The visible framebuffer contained the running game's Japanese prologue. The
capture is retained locally at
`output/validation/2026-07-15-fe-game-launch/visible.png`. RetroArch was then
stopped with the PID-validated stop helper and exactly one normal FE process
was restored.
