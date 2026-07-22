# SD Cards and Folders

The V90S can use two SD cards. SD1 is required. SD2 is needed only when you
want to keep ROMs and BIOS files on a separate card.

## Overview

```text
V90S
├─ SD1 (required: plumOS and user data)
│  ├─ PLUMBOOT       Startup files. Do not change or delete them
│  ├─ Linux areas    Usually hidden on a computer. Do not format them
│  └─ PLUMOS         ROMs, images, music, updates, and other user files
│
└─ SD2 (optional: ROMs and BIOS files)
   ├─ roms/          Game files and RetroArch saves
   └─ bios/          BIOS files
```

The ROM and BIOS locations change when SD2 is inserted. RetroArch saves and
save states follow the ROMs because they are stored below the active ROM folder.

```text
Without SD2  -> use PLUMOS/roms/ and PLUMOS/bios/ on SD1
With SD2     -> use roms/ and bios/ on SD2

RetroArch saves and states -> stored below the active roms/ folder
OS, settings, PicoArch/standalone saves, images, and updates -> remain on SD1
```

## SD1

SD1 contains plumOS and user data. A computer may show both `PLUMBOOT` and
`PLUMOS`.

- `PLUMBOOT` contains startup files. Do not change or delete its contents.
- Put your files on `PLUMOS` during normal use.
- If the computer asks to format another partition, cancel the request.

Main folders on `PLUMOS`:

```text
PLUMOS/
  roms/          Game files arranged by system
  bios/          BIOS files supplied by the user
  Images/        Thumbnail images
  Themes/        User themes
  Screenshots/   Screenshots exported for a computer
  Music/         Music and other user media
  Cheats/        Cheat files
  Patches/       Game patches
  Shaders/       RetroArch shader files
  updates/       plumOS update files
  imports/       Files waiting to be imported by plumOS
  exports/       Files exported for copying to a computer
  plumos-logs/   Logs used when troubleshooting errors
```

System settings and PicoArch/standalone saves are kept in Linux areas that a
computer does not normally show. RetroArch saves and save states are stored
below `roms/`. See [Save Data](save-data.md) for the exact layout.

## SD2

SD2 is optional. Format it as FAT32 and create these two folders at the top of
the card:

```text
SD2/
  roms/
  bios/
```

When the V90S starts with SD2 inserted, plumOS uses `roms/` and `bios/` on SD2.
RetroArch saves and save states are also written below `roms/` on SD2.
After SD2 is removed, plumOS returns to the SD1 folders on the next start.

Always shut down the V90S before inserting or removing an SD card.

## ROM Folder Names

Create one folder for each system below `roms/`. Both naming styles below are
supported.

```text
Miyoo style:             FC  SFC  GB  GBC  GBA
EmulationStation style:  nes snes gb  gbc  gba
```

Using both names for the same system can show games twice. Use only one naming
style for each system.

After adding or removing ROMs, run `START -> UI Settings -> Refresh TOP`.
ROMs and BIOS files are not included with plumOS.
