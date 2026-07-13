# V90S Full Core Deployment

Date: 2026-07-13

## Goal

Deploy the MMF-matched complete libretro core set to the live V90S app layer,
make the cores selectable through the normal frontend launch contract, and
retain enough FAT32 capacity for later payload and user-data growth.

## FAT32 Capacity

The original 1GB p7 was 93% full and its FAT had shared/free cluster damage.
Before changing it, the partition table, first 2MiB, user settings, saves, and
state were backed up under the ignored `artifacts/device-backups/` tree.

p7 was then expanded to 4096MiB and reformatted as FAT32 label `PLUMOS`. p1
through p6 were not changed. The resulting live mount was:

```text
Filesystem      Size  Used Avail Use% Mounted on
/dev/mmcblk0p7  4.0G  673M  3.4G  17% /mnt/plumos
```

`scripts/assemble-v90s-stockos-image.sh` now uses the same 4096MiB default for
future images. `scripts/v90s-expand-plumos-fat.sh` records the maintenance run,
drains exact p7 holders, and uses rootfs-resident mount/reboot commands so it
does not depend on the filesystem being resized.

## Deployment Integrity

The full `output/app-layer/v90s` tree was copied to the new p7 before restoring
writable user settings. Baseline app-layer verification succeeded:

```text
sha256sum -c checksums.sha256: 0 failures
deployed cores:               117
deployed info files:          110
```

The deployed snapshot uses 673MB on FAT32. A clean host regeneration after the
test occupies about 867MiB of file data because it also rebuilt the current
userland, network-service, app, RetroArch, and standalone inputs; both fit well
inside the new 4GB budget.

After restoring settings and saves, the core-only manifest was checked again:

```text
core checksum count:    117
core checksum failures: 0
```

macOS AppleDouble sidecars produced during the first transfer were removed;
the final device count is zero.

## Preserved Runtime Settings

The known-good writable RetroArch configuration was restored with SHA-256:

```text
4bd5b60450aaddd702ae3890e0bf58bac9c6da47940fb94eddf96a1f20900b75
```

Its validated route remains PowerVR fbdev GL, threaded video, 58.917103Hz VRR,
and ALSA `hw:0,0` with 64ms latency. The stale SFC override to unimplemented
PicoArch was intentionally not restored; SFC now selects
`retroarch:snes9x2005`.

Cave Story was enabled in `systems.json` and now selects
`/mnt/plumos/cores/nxengine_libretro.so` through the normal FE route.

## Frontend Preflight

After remounting SD2 at `/mnt/plumos/roms` and `/mnt/plumos/bios`, Refresh TOP
indexed 58 systems with ROMs. The first indexed content for every system was
passed to the FE launch planner:

```text
can_execute=yes: 57
can_execute=no:   1
```

All 48 systems previously blocked by absent deployed libretro cores now report
`can_execute=yes`. The sole remaining failure is Pyxel, whose selected
`pyxel:mmf` launcher is not a libretro core and remains separate work.

## Runtime Smoke Tests

The following representative cores were launched with the FE backend using
`plumos-text-ui launch ... --execute`. Each active RetroArch process was
stopped with the exact PID-aware `v90s-retroarch-stop` helper.

| System | Core | Result |
| --- | --- | --- |
| SFC | `snes9x2005` | PASS; LCD frame captured at about 59.92 fps |
| GB | `gambatte` | PASS with `Baseball.gb` |
| GBA | `gpsp` | PASS |
| Mega Drive | `genesis_plus_gx` | PASS |
| PC Engine | `mednafen_pce_fast` | PASS |
| FBNeo | `fbneo` | PASS |
| PC-98 | `np2kai` | PASS |
| Cave Story | `nxengine` | PASS |

The first indexed GB file, `ARETHA.gb`, was rejected by Gambatte as invalid
content. A second GB ROM remained active with the same core, so this is a ROM
file issue rather than a deployment or FE routing failure.

The final runtime state has one frontend process, no RetroArch process, SD2
mounted at the ROM/BIOS paths, and the restored known-good configuration.

## Result

Pass for complete core deployment, integrity, FE availability, and
representative runtime execution. Per-core gameplay compatibility across every
one of the 117 binaries remains broader emulator validation work.
