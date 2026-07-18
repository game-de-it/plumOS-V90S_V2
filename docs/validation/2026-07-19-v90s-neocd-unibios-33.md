# V90S NeoCD UniBIOS 3.3 Validation

Date: 2026-07-19

## Goal

Run the Neo Geo CD copy of Fatal Fury with UniBIOS 3.3 through the V90S
RetroArch/NeoCD route. The BIOS under test is intentionally supplied outside
the repository:

```text
/mnt/plumos/bios/neocd/uni-bioscd.rom
```

## Content Integrity

The SD2 content below was compared with the host reference directory:

```text
/mnt/plumos/roms/neogeocd/Fatal Fury WAV
/Volumes/example/rom-library/emu/ROM/rom2/_etc/neogeocd/Fatal Fury WAV
```

All 34 game payload files, including the CUE, ISO, and 32 WAV tracks, matched
by file size and SHA-256. The only mismatch was `readme.html`, where the SD2
copy has different line endings. It is not referenced by the CUE or core.

Key content hashes:

```text
Fatal Fury WAV.cue  0985ad45b800c0bea00c0ec3ca50303df555cf3e8b2d6e0ee3278de2cb959203
Fatal Fury WAV.iso  fac7d91c789b1abe9c3c7268783f92fef229e1b3a00c3591f842f0979f9bcd23
```

The mounted ISO contains a valid `IPL.TXT` and game payload, so this was not a
damaged-ROM failure.

## BIOS Isolation

The unmodified NeoCD core produced these real-device results with the same
content:

| BIOS selection | Result |
| --- | --- |
| `uni-bioscd.rom (CDZ, Universe 3.3)` | UniBIOS screen appeared, but the CD player remained at `TRACK 00` |
| `neocd_z.rom (CDZ)` | Remained at `TRACK 00` |
| `front-sp1.bin (Front Loader)` | Fatal Fury reached the game title/start screen |
| `top-sp1.bin (Top Loader)` | Fatal Fury reached the game title/start screen |

This isolates the failure to the NeoCD core's CDZ runtime path. It does not
indicate a damaged BIOS or game image. UniBIOS 3.3 is identified by this core
as a CDZ-family BIOS.

## V90S Workaround

`neocd-unibios-toploader-drive.patch` preserves the existing CDZ BIOS patches
for UniBIOS 3.3, but changes its runtime drive model to Top Loader. In NeoCD,
that changes the tray signal polarity and CD-ROM timer from the CDZ-specific
path to the Top Loader path that was proven to boot this content on V90S.

The patch is applied only when the selected BIOS type is exactly CDZ plus
Universe 3.3. Stock Front Loader, Top Loader, CDZ, and other modified BIOS
types retain their upstream behavior.

The isolated build command was:

```sh
PLUMOS_CORE_FILTER=neocd FAIL_ON_CORE_ERROR=1 JOBS=4 \
  BUILD_JOB_FALLBACKS=2,1 ./scripts/docker-build.sh cores
```

Filtered output:

```text
output/libretro-cores/v90s-filtered/neocd/cores/neocd_libretro.so
```

The output is AArch64 and has this SHA-256:

```text
c4178112748c3d320b781a63edd6641de9177d24f35941e6dac8accf64381b0ca4
```

## Live Result

The patched core was deployed through ADB without replacing the canonical
full-core output. The existing RetroArch instance was stopped through the
PID-aware `v90s-retroarch-stop` helper. No broad process-name kill was used.

The live options were:

```text
neocd_bios = "uni-bioscd.rom (CDZ, Universe 3.3)"
neocd_cdspeedhack = "On"
neocd_loadskip = "On"
neocd_per_content_saves = "Off"
neocd_region = "Japan"
```

RetroArch then launched the SD2 CUE through the normal FE launcher route:

```text
core: /mnt/plumos/cores/neocd_libretro.so
rom:  /mnt/plumos/roms/neogeocd/Fatal Fury WAV/Fatal Fury WAV.cue
CPU:  ondemand
```

The user confirmed on the physical V90S that the game started with UniBIOS
3.3. This closes the previous `TRACK 00` boot blocker. Audio quality and a full
controller map were not separately revalidated in this test.

## Earlier Matrix Scope

The 2026-07-14 all-core matrix classified NeoCD as running because its pass
criteria were process survival, the expected core in the command line, and a
readable framebuffer during an eight-second window. That result did not prove
that Fatal Fury reached gameplay. This validation supersedes that limited
NeoCD interpretation with a real game-boot result.
