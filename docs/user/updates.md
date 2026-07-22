# System Updates

plumOS uses signed update archives. Normal updates do not replace the fixed
StockOS-derived kernel or bootloader.

## Update Types

- **Runtime Update** updates the frontend, applications, emulators, libraries,
  factory defaults, and other plumOS-managed files on the ext4 system volume.
- **System Update** updates the read-only Linux SquashFS by writing the inactive
  A/B system slot.

## Apply an Update

1. Download the update archive for POWKIDDY V90S. Do not extract it.
2. Copy the `.tar.gz` file to `PLUMOS/updates/` on SD1. Use a card reader, USB
   Disk Mode, or SFTP/SSH with the absolute path `/mnt/plumos-user/updates/`.
3. Eject or disconnect safely.
4. Open `START -> System Settings -> System Update`.
5. Press A to select the newest compatible signed package.
6. Keep the device connected to stable power while it verifies, installs, and
   restarts.

The frontend is locked during the update. Do not press Reset, remove power, or
remove either SD card.

## Recovery and Logs

A Runtime Update keeps one previous transaction for rollback. A System Update
writes the inactive system slot and returns to the previous slot if the new one
does not reach the frontend.

The latest host-readable failure summary is copied to:

```text
PLUMOS/plumos-logs/update/
```

The update archives in `PLUMOS/updates/` remain user-managed. Delete obsolete
archives after confirming that the installed version starts normally.
