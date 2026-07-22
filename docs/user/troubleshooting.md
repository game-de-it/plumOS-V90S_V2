# Troubleshooting

## The First Boot Does Not Finish

The first start prepares the SD card, so it takes longer than normal. Keep the
V90S on stable power. If a failure message does not disappear, take a photo and
use the on-screen shutdown option when possible. Check `PLUMOS/plumos-logs/` on
a computer. If the problem remains, write the image to the SD card again.

## A System or Game Is Missing

- Check the ROM folder name and file extension.
- Confirm that SD2 is FAT32 and contains root-level `roms/` and `bios/` folders.
- Run `START -> UI Settings -> Refresh TOP`.
- Enable the option to show empty systems only when you need to inspect every
  configured system.

## Two ROMs Appear to Have the Same Name

Japanese filenames can look identical while being recorded differently inside
a computer. Copying the same ROM from different environments, such as macOS and
Windows, can therefore make the same name appear twice. This does not always
mean that the ROM data is corrupt.

1. Back up the ROMs to a computer.
2. Remove the visual duplicates and retain the required copy.
3. Copy the cleaned ROM set back using one computer and one transfer method
   where practical.
4. Run `START -> UI Settings -> Refresh TOP`.

Copying the same filename again from one computer normally overwrites the old
file. A separate file with the same visible name can appear when different
computers or applications are used. Remove duplicates before downloading
thumbnail images.

## A Game Does Not Start

- Confirm that required BIOS files have the exact expected names.
- Keep cue sheets, playlists, tracks, and directories together.
- Press SELECT in the ROM list and try another launch method.
- Restore that emulator's default settings if a saved setting prevents startup.

## Wi-Fi Does Not Connect

- V90S requires a supported USB Wi-Fi adapter.
- Reconnect the adapter and toggle Wi-Fi off and on.
- Wait for the SSID scan to finish before pressing another button.
- Check Network Information for the Wi-Fi name (SSID) and IP address.
- Try a direct OTG connection or another powered USB hub.

## No Sound

- Raise the system volume with the physical Volume + button.
- Reconnect a USB DAC and allow the route to switch.
- Check whether the application has its own mute or volume setting.
- Exit and relaunch the game after changing a device-specific audio option.

## The Computer Wants to Format a Partition

Cancel the prompt. A computer cannot read the Linux areas on SD1. Put files on
`PLUMOS` and do not format unknown areas.

## After an Unsafe Reset or Removal

Wait for the SD-card check to finish on the next start. Do not interrupt the
recovery screen even when it is slow. Use Shutdown before removing an SD card
in the future.
