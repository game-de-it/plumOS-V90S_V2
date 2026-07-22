# Save Data and Screenshots

plumOS keeps active save data on the Linux ext4 system volume. This reduces
write exposure on the FAT32 user volume. Windows and macOS do not show these
folders when the SD card is inserted directly.

## RetroArch and PicoArch

Save RAM and save states are organized by system:

```text
/mnt/plumos/Saves/<system>/
/mnt/plumos/States/<system>/
```

The save filename normally follows the ROM filename. Keep the same base name
when moving a save from another device. For example:

```text
ROM:  Super Metroid.sfc
Save: Super Metroid.srm
```

## Standalone Emulators

Standalone emulators keep their writable data below:

```text
/mnt/plumos/state/standalone/
```

The internal layout belongs to each emulator. Use the Apps file manager, SFTP,
or SSH when copying these files. Shut down the emulator before replacing save
data.

## Screenshots

RetroArch screenshots use the configured image directory under:

```text
/mnt/plumos/Images/
```

Other applications may keep screenshots in their own state directory. Use the
file manager or a network service to copy them to the FAT32 `PLUMOS` volume if
you want to read them directly on a computer.

## Backups

1. Exit the running game or application.
2. Copy the relevant save directory to another device.
3. Keep the system name, ROM base name, and extension unchanged.
4. Eject or disconnect safely after the copy finishes.

Do not overwrite active save data while a game is running.
