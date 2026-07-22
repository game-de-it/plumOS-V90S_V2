# Systems and Emulators

plumOS can launch a system through RetroArch, PicoArch, or a standalone
emulator. The available choices depend on the system and the installed runtime.

## Launch a Game

1. Select a system on TOP.
2. Select a game in the ROM list or Gallery.
3. Press A to launch it.

Press SELECT before launching to choose another available emulator profile.
The chosen profile is saved per system. Systems with only one supported profile
start directly.

## Profiles

- **RetroArch (RA)** provides the widest core coverage and an in-game menu.
- **PicoArch (PICO)** is a small libretro frontend used only for systems with a
  compatible V90S profile.
- **Standalone (SA)** runs an emulator outside RetroArch. Its menu and shortcuts
  depend on that emulator.

Not every core is offered on every frontend. plumOS hides combinations that do
not have a usable V90S launch profile.

## Content Layout

Put content in a system folder below `roms/`. Multi-file disc games should keep
their cue sheet, playlist, tracks, and subdirectories together. Do not rename
only one file in a cue/track set.

BIOS files belong below `bios/`. Required names and hashes are defined by the
emulator, so preserve the original filename and letter case. Arcade ROM sets
must match the selected core or emulator version.

## Performance

The default CPU governor is `ondemand`. Use `START -> Performance Settings` to
select a system and choose `performance` when a demanding game needs sustained
CPU speed. Reset to Default returns that system to its normal profile.

Higher-end systems may require game-specific settings, frameskip, or a lighter
emulator profile. Fast-forward speed also depends on the system and game.

## Emulator Settings

Changes saved from RetroArch, PicoArch, PPSSPP, and other supported emulators
persist on the system volume. To restore defaults, use:

`START -> System Settings -> Factory Reset`

The reset screen can restore all emulator settings or only RA, PicoArch, or
standalone settings. Current files are backed up before replacement.
