# System Updates

plumOS update files use the `.tar.gz` format. Before installation, the V90S
checks automatically that the file is a valid update for this device.

## Update Types

- **Runtime Update** updates the game list, applications, emulators, and default
  settings.
- **System Update** updates the basic Linux part of plumOS.

Follow the instructions on screen. You do not need to choose an internal
storage location.

## Update Inbox and Internal Staging

When SD1 is opened in standard Windows, use the FAT32 volume named `PLUMOS`.
Place the update file directly in:

```text
PLUMOS/updates/
```

The separate Linux ext4 volume `PLUMOS_SYS` is not normally mounted as a drive
by Windows. It contains the updater's internal
`/mnt/plumos/updates/staging` directory. If an ext4-capable tool exposes this
volume or its `staging` directory, do not add, modify, or delete anything
there. It is different from the user-facing `PLUMOS/updates/` inbox.

Only the `.tar.gz` file is required on the SD card. The accompanying `.sha256`
file is optional and is provided for checking download integrity on the
computer; the updater does not require it.

## Apply an Update

1. Download the update file for POWKIDDY V90S. Do not extract it.
2. Without extracting it, copy the `.tar.gz` file directly to
   `PLUMOS/updates/` on SD1. Do not put it in `staging`. You can use a card
   reader, USB Disk Mode, SFTP, or SSH.
3. Eject or disconnect safely.
4. Open `START -> System Settings -> System Update`.
5. Press A to select the newest available update.
6. Keep the device connected to stable power while it checks, installs, and
   restarts.

Buttons are disabled during the update. Do not press Reset, turn off power, or
remove either SD card.

## Recovery and Logs

A Runtime Update keeps only the previous version in case it needs to go back.
A System Update also returns to the previous system if the new one cannot start.

If an update fails, a log that can be read on a computer is saved to:

```text
PLUMOS/plumos-logs/update/
```

After confirming that the V90S starts normally, you may delete old update files
from `PLUMOS/updates/`.
