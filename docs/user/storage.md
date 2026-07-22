# SD Cards and Folders

## SD1

SD1 contains the operating system and the `PLUMOS` FAT32 user volume. Windows
and macOS normally show only the user-facing volumes; do not format partitions
that the computer reports as unknown.

Important folders on the `PLUMOS` volume are:

```text
PLUMOS/
  roms/          game content by system
  bios/          user-provided BIOS files
  Images/        scraped or copied thumbnails
  Themes/        user themes
  Screenshots/   exported screenshots
  Music/         user media
  Cheats/        cheat files
  Patches/       game patches
  Shaders/       RetroArch shader files
  updates/       signed plumOS update archives
  imports/       files waiting for an explicit import
  exports/       files exported from Linux-managed storage
  plumos-logs/   host-readable update/recovery logs
```

System settings, emulator binaries, saves, states, and writable runtime data
are kept on the Linux ext4 system volume and are not directly shown by Windows
or macOS.

## SD2

SD2 is optional and must use FAT32. Create these folders at its root:

```text
roms/
bios/
```

When SD2 is present, plumOS checks the filesystem and mounts those folders as
the active ROM and BIOS locations. Removing SD2 restores the SD1 locations on
the next boot or refresh. Shut down before inserting or removing either card.

## ROM Folder Names

plumOS accepts the configured system aliases, including common Miyoo-style
uppercase names such as `FC`, `SFC`, `GB`, `GBC`, and `GBA`, and
EmulationStation-style lowercase names such as `nes`, `snes`, `gb`, `gbc`, and
`gba`. Keep one naming style per system to avoid duplicate entries.

Run `Refresh TOP` after changing content. ROMs and BIOS files are not included
with plumOS.
