# Troubleshooting

## The First Boot Does Not Finish

Leave the device on stable power because first-boot storage setup takes longer
than a normal start. If a failure message remains on screen, shut down when
offered and inspect `PLUMOS/plumos-logs/` on a computer. Rewriting the released
image is the clean recovery path when provisioning cannot complete.

## A System or Game Is Missing

- Check the ROM folder name and file extension.
- Confirm that SD2 is FAT32 and contains root-level `roms/` and `bios/` folders.
- Run `START -> UI Settings -> Refresh TOP`.
- Enable the option to show empty systems only when you need to inspect every
  configured system.

## Two ROMs Appear to Have the Same Name

Japanese filenames can look identical while using different internal Unicode
representations. If decomposed names (NFD), commonly produced by macOS, and
composed names (NFC), commonly used by Windows and Linux, are mixed, FAT32 can
store both as different names. The frontend may then appear to list the same
ROM twice. This does not by itself mean that the ROM data is corrupt.

1. Back up the ROMs to a computer.
2. Remove the visual duplicates and retain the required copy.
3. Copy the cleaned ROM set back using one computer and one transfer method
   where practical.
4. Run `START -> UI Settings -> Refresh TOP`.

Copying a filename with the same Unicode representation through Windows and
FTP normally overwrites the existing file instead of creating a duplicate. A
visual duplicate can be created when the source or transfer application mixes
NFC and NFD names. The scraper may also treat those names as separate files,
so clean up duplicates before downloading thumbnails.

## A Game Does Not Start

- Confirm that required BIOS files have the exact expected names.
- Keep cue sheets, playlists, tracks, and directories together.
- Press SELECT in the ROM list and try another offered emulator profile.
- Restore that emulator's factory settings if a saved configuration prevents
  startup.

## Wi-Fi Does Not Connect

- V90S requires a supported USB Wi-Fi adapter.
- Reconnect the adapter and toggle Wi-Fi off and on.
- Wait for the SSID scan to finish before pressing another button.
- Check Network Information for the interface, SSID, and IP address.
- Try a direct OTG connection or another powered USB hub.

## No Sound

- Raise the system volume with the physical Volume + button.
- Reconnect a USB DAC and allow the route to switch.
- Check whether the application has its own mute or volume setting.
- Exit and relaunch the game after changing a device-specific audio option.

## The Computer Wants to Format a Partition

Cancel the prompt. Windows and macOS cannot read the Linux ext4 system
partition. Use only the visible plumOS FAT volume; do not format unknown
partitions.

## After an Unsafe Reset or Removal

Allow the next boot to complete its filesystem check. Do not interrupt a slow
recovery screen. Use the frontend Shutdown command before removing storage in
the future.
