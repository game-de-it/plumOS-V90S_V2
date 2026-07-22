# Systems and Emulators

plumOS provides several ways to launch games. Depending on the game system, it
uses RetroArch, PicoArch, or a dedicated standalone emulator.

## Launch a Game

1. Select a system on TOP.
2. Select a game in the ROM list or Gallery.
3. Press A to launch it.

Press SELECT before launching to choose another launch method. Your choice is
saved for that game system. If only one method is available, the game starts
directly.

## Launch Methods

- **RetroArch (RA)** supports the most game systems and has an in-game settings
  menu.
- **PicoArch (PICO)** is a lightweight launch method available for supported
  systems.
- **Standalone (SA)** uses a dedicated emulator. Menus and button shortcuts
  differ between emulators.

The available launch methods depend on the game system. plumOS hides choices
that do not work on the V90S.

## Where to Put Game Files

Put games in a system folder below `roms/`. For CD games and other multi-file
games, copy the cue sheet, playlist, tracks, and subfolders together. Do not
rename only one file from the set.

BIOS files belong below `bios/`. Each emulator expects specific BIOS files and
names, so do not change filenames or letter case. Arcade games need a ROM set
that matches the selected emulator.

## Performance

The normal `ondemand` setting adjusts CPU speed automatically. If a demanding
game runs slowly, select its system in `START -> Performance Settings` and try
`performance`. Reset to Default restores the normal setting.

Some demanding games may still run slowly after changing settings. Fast-forward
speed also depends on the system and game.

## Emulator Settings

Changes saved from RetroArch, PicoArch, PPSSPP, and other supported emulators
persist on the system volume. To restore defaults, use:

`START -> System Settings -> Factory Reset`

You can restore all emulator settings or only RA, PicoArch, or standalone
settings. Current settings are backed up before they are reset.
