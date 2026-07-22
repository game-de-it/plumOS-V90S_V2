# Save Data and Screenshots

RetroArch stores save data below `roms/` on the same SD card as the ROM. Saves
are therefore on SD2 when SD2 supplies the ROMs, or on the SD1 `PLUMOS` volume
when SD2 is not used. PicoArch and standalone emulators use different paths.

## RetroArch

The plumOS factory configuration keeps normal saves and save states beside the
ROM collection, sorted by both ROM folder and core name:

```text
roms/<ROM folder>/<ROM folder>/<core name>/
```

### Game Boy Example

Launching `Aretha (Japan).gb` with the Gambatte core produces this layout:

```text
roms/GB/
  Aretha (Japan).gb
  GB/
    Gambatte/
      Aretha (Japan).srm
      Aretha (Japan).state.auto
      Aretha (Japan).state.auto.png
```

The first `GB` is the ROM folder. The second `GB` is created by RetroArch's
sort-by-content-directory setting, and `Gambatte` is created by its sort-by-core
setting.

| File | Purpose |
| --- | --- |
| `<ROM name>.srm` | Normal in-game save data |
| `<ROM name>.state` | Manual save state in slot 0 |
| `<ROM name>.state1`, etc. | Numbered save-state slots |
| `<ROM name>.state.auto` | Automatic save state created when the game exits |
| `<state filename>.png` | Save-state thumbnail |

Normal save data is written about every 10 seconds while playing. The automatic
exit state is created, but it is not loaded automatically on the next launch.
Manual save states use automatic indexing with a configured maximum of 20
generations.

When importing a save from another device, make the filename before `.srm`
match the ROM filename and place it in the folder for the core you use. Save
formats may differ between cores.

## PicoArch

PicoArch stores saves in the Linux area on SD1:

```text
/mnt/plumos/Saves/<system>/
```

A computer does not normally show this folder when the SD card is inserted.
Use the Apps file manager, SFTP, or SSH to copy it.

## Standalone Emulators

Dedicated standalone emulators keep their saves and settings below:

```text
/mnt/plumos/state/standalone/
```

The folders differ between emulators. Exit the game before copying or replacing
save data.

## Screenshots

RetroArch screenshots are stored below:

```text
/mnt/plumos/Images/
```

Other applications may store images elsewhere. To move them to a computer, use
the file manager or a network service to copy them to `PLUMOS`.

## Backups

1. Exit the running game or application.
2. Copy the relevant save folder to a computer or another SD card.
3. Do not change the ROM folder, core name, matching ROM filename, or extension.
4. Eject or disconnect safely after the copy finishes.

Do not overwrite active save data while a game is running.
