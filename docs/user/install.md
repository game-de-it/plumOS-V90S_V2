# Installing plumOS

## What You Need

- POWKIDDY V90S
- reliable microSD card for SD1
- Windows, macOS, or Linux computer with an SD-card reader
- released plumOS V90S SD-card image
- image writer such as Raspberry Pi Imager or balenaEtcher

An optional FAT32 microSD card may be used in SD2 for ROMs and BIOS files.

## Write the Image

1. Back up any files on the target card. Writing the image erases it.
2. Select the plumOS V90S image in your image-writing application.
3. Select the SD1 card carefully and write the image.
4. Eject the card safely and insert it into the V90S SD1 slot.
5. Leave SD2 empty for the first boot unless it is already prepared as
   described in [SD cards and folders](storage.md).

## First Boot

Turn on the V90S and leave it connected to stable power. The first boot expands
the system area, creates the FAT32 user volume, and installs the initial folder
layout. This takes longer than later boots. Keep the device powered on until
the plumOS frontend appears.

Do not press Reset or remove the card during first boot. If an error screen is
shown, note the message and follow [Troubleshooting](troubleshooting.md).

## After Installation

Use the frontend's `START -> Shutdown` command before removing the SD card.
Connect the card to a computer and place content under the folders described in
[SD cards and folders](storage.md), or transfer files through a network service
or USB Disk Mode.
