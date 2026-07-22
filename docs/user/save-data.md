# Save Data and Screenshots

Save data is stored in an area on SD1 that a computer does not normally show.
Use the Apps file manager, SFTP, or SSH when you need to copy it.

## RetroArch and PicoArch

Normal saves and save states are stored by game system:

```text
/mnt/plumos/Saves/<system>/
/mnt/plumos/States/<system>/
```

The save filename normally matches the ROM filename. When moving a save from
another device, keep the part before the file extension the same. For example:

```text
ROM:  Super Metroid.sfc
Save: Super Metroid.srm
```

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
3. Do not change the game system, ROM filename, or file extension.
4. Eject or disconnect safely after the copy finishes.

Do not overwrite active save data while a game is running.
