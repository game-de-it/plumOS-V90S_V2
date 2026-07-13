# V90S FE ROM Launch Matrix

Date: 2026-07-13

## Goal

Check every system which currently has ROM content in the live V90S frontend
library. Use the same launch planner and launcher selected by the frontend, and
record failures for later correction.

This pass checks whether representative content starts and draws. It does not
claim complete audio, controller, save, or clean-return validation.

## Live Inventory

The frontend TOP was refreshed before taking the test snapshot. The resulting
`/mnt/plumos/state/frontend/library-index.json` contained:

```text
systems with ROMs: 57
FE preflight can_execute=yes: 7
FE preflight can_execute=no: 50
```

The host build outputs contain 117 libretro cores in both
`output/libretro-cores/v90s` and `output/app-layer/v90s/cores`. The live V90S
app layer did not match that output:

```text
/mnt/plumos/cores/quicknes_libretro.so
/usr/lib/aarch64-linux-gnu/libretro/quicknes_libretro.so
/mnt/plumos/roms/ports/cavestory/nxengine_libretro.so
```

The two QuickNES files have the same SHA-256:

```text
da48490d5aab244bc0c13e6381555ac2003b438336dafe7db122043503686c68
```

Therefore, the main blocker in this snapshot is an incomplete live core
deployment, not an absent host build result.

## Method

For every system with `rom_count > 0`, the first indexed ROM was passed to:

```sh
/mnt/plumos/bin/plumos-text-ui launch SYSTEM RELATIVE_PATH --no-scan
```

Entries reporting `can_execute: yes` were then started with `--execute`. After
the observation interval, only the exact target emulator PID was terminated.
The frontend was restored and checked to have exactly one running process
before the next test. Framebuffer pages were captured from the live
640x960 BGRA `/dev/fb0` and inspected on the host.

## Executed FE Results

| System | Representative content | Result | Evidence |
| --- | --- | --- | --- |
| NES | `Akumajou Densetsu.nes` | PASS | FE selected QuickNES; RetroArch stayed active; framebuffer showed game output at about 60 fps. |
| PSP | `Ridge Racers (Japan).iso` | PASS | FE selected PPSSPP; `PPSSPPSDL` stayed active; framebuffer showed the Namco/game boot sequence at 60/60. |
| PSX | `TEKKEN3/SLPS-01300.bin` | FAIL | PCSX-ReARMed exited immediately with `SDL_Init failed: Unable to open a console terminal` and `No available video device`. |
| EasyRPG | `TurnedIntoAGirl` | FAIL | EasyRPG Player drew successfully but reported `No games found in the current directory`; the game directory argument did not start the content. |
| ScummVM | `Backyard Baseball (CD Windows)` | FAIL | ScummVM treated the directory as a target ID and exited with `Unrecognized game`. The launcher must detect/add a game or pass a valid target. |
| OpenBOR | `Dragon Ball [v.3.0 Build 4086].PAK` | FAIL | OpenBOR drew its launcher but reported `No Mods In Paks Folder`; passing the PAK as a positional argument did not install/select it. |
| Ports | `PORTS/tmp/1.sh` | FAIL | The script only writes a stale PID to `/dev/cpuset/foreground/tasks`; the path does not exist and the command exits. |

## Preflight-Blocked Systems

SFC was overridden to `picoarch:snes9x2010`, but the live
`/mnt/plumos/picoarch/cores/snes9x2010_libretro.so` was missing.

Pyxel selected `pyxel:mmf`, but
`/mnt/plumos/bin/plumos-pyxel-mmf-launch` was missing.

The following 48 systems all had indexed ROMs, but their selected libretro
core was absent from `/mnt/plumos/cores`, so the FE correctly refused to run
them:

```text
fds, gb, gbc, gba, megadrive, mastersystem, gamegear, sega32x, segacd,
pcengine, supergrafx, pcenginecd, neogeo, neogeocd, ngpc, wonderswan, fbneo,
pico8, pc88, pc98, atari2600, atari7800, supervision, odyssey2, gameandwatch,
pokemini, doom, amiga, atari5200, atari800, atarist, c64, cannonball,
chailove, channelf, colecovision, cpc, dinothawr, intellivision, j2me,
lowresnx, lutro, music, quake, thomson, ti83, vic20, zxspectrum
```

## Deployed Core Check

QuickNES was validated through the normal FE route by the NES test above.
The duplicate system copy has the same hash and was not counted as a separate
core implementation.

The deployed Cave Story `nxengine_libretro.so` is not available through the
FE because the `cavestory` system is disabled and the core is stored beside
ROM data instead of under `/mnt/plumos/cores`. A direct diagnostic launch with
`Doukutsu.exe` succeeded: RetroArch stayed active and the framebuffer showed
Cave Story at about 58.9 fps. This proves the core binary works, but the FE
route remains a failure until the system and packaging contract are fixed.

## Follow-up Order

1. Deploy the complete 117-core app-layer output to the V90S and verify hashes.
2. Re-run preflight and actual launch tests for the 48 missing-core systems.
3. Implement and deploy PicoArch and the V90S Pyxel launcher.
4. Correct PCSX-ReARMed SDL startup and the ScummVM, EasyRPG, and OpenBOR
   content argument contracts.
5. Replace or remove the stale `PORTS/tmp/1.sh` entry.
6. Enable and package Cave Story through the normal FE/core paths.
