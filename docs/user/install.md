# Installing plumOS

## What You Need

- POWKIDDY V90S
- good-quality microSD card for SD1
- Windows, macOS, or Linux computer with an SD-card reader
- released plumOS V90S SD-card image
- image writer such as Raspberry Pi Imager or balenaEtcher

An optional FAT32 microSD card may be used in SD2 for ROMs and BIOS files.

## Write the Image

1. Copy any files you need from the SD card to a computer. Writing the image
   erases the card.
2. Select the plumOS V90S image in your image-writing application.
3. Select the SD1 card carefully and write the image.
4. Eject the card safely and insert it into the V90S SD1 slot.
5. Leave SD2 empty for the first boot unless it is already prepared as
   described in [SD cards and folders](storage.md).

## First Boot

Connect the V90S to stable USB power and turn it on. The first start prepares
the SD card and creates its folders, so it takes longer than a normal start.
Wait until the game list appears.

Do not press Reset or remove the card during first boot. If an error screen is
shown, take a photo of the message and follow
[Troubleshooting](troubleshooting.md).

## After Installation

Use `START -> Shutdown` before removing the SD card.
Connect the card to a computer and place content under the folders described in
[SD cards and folders](storage.md), or transfer files through a network service
or USB Disk Mode.
