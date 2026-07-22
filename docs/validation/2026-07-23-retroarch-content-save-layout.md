# RetroArch Content-Local Save Layout

Date: 2026-07-23

## Scope

Confirm the save and save-state layout produced by the tracked V90S RetroArch
factory configuration. No ROM content was copied into the repository.

## Factory Configuration

The tracked configuration contains:

```text
autosave_interval = "10"
savefiles_in_content_dir = "true"
savestates_in_content_dir = "true"
savestate_auto_index = "true"
savestate_auto_load = "false"
savestate_auto_save = "true"
savestate_max_keep = "20"
savestate_thumbnail_enable = "true"
sort_savefiles_by_content_enable = "true"
sort_savefiles_enable = "true"
sort_savestates_by_content_enable = "true"
sort_savestates_enable = "true"
```

The managed launcher still supplies per-system fallback directories in its
volatile append config:

```text
savefile_directory = "/mnt/plumos/Saves/gb"
savestate_directory = "/mnt/plumos/States/gb"
```

The content-local settings take precedence in the factory-default behavior.

## Real-Device Evidence

SD2 was mounted at `/run/plumos/sd2`, and its `roms` directory was bind-mounted
at `/mnt/plumos/roms`. RetroArch ran the Gambatte core with this content path:

```text
/mnt/plumos/roms/GB/Zelda no Densetsu - Yume o Miru Shima (Japan).gb
```

The active FAT32 GB directory contained the following generated examples:

```text
roms/GB/GB/Gambatte/Aretha (Japan).srm
roms/GB/GB/Gambatte/Aretha (Japan).state.auto
roms/GB/GB/Gambatte/Aretha (Japan).state.auto.png
roms/GB/GB/Gambatte/Zelda no Densetsu - Yume o Miru Shima (Japan).srm
roms/GB/GB/Gambatte/Zelda no Densetsu - Yume o Miru Shima (Japan).state
roms/GB/GB/Gambatte/Zelda no Densetsu - Yume o Miru Shima (Japan).state.png
```

This proves that the current factory configuration sorts RetroArch saves and
states first by the content directory (`GB`) and then by core display name
(`Gambatte`). When SD2 is active, these files are owned by SD2. Without SD2,
the same rule applies below p4 `PLUMOS/roms` on SD1.

