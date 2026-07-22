# Thumbnail Scraping

The frontend can download artwork for ROMs when the V90S is connected to the
network.

## Download Images

1. Connect a supported USB Wi-Fi adapter.
2. Connect to Wi-Fi from `START -> Network Settings`.
3. Open the scraper from Apps or the applicable ROM-list action.
4. Select the system and start scraping.
5. Return to TOP and run `Refresh TOP` if artwork is not shown immediately.

Keep the device powered and connected while files are being downloaded.

## Image Location

Images are organized by system below:

```text
/mnt/plumos/Images/<system>/
```

For example, NES artwork is stored under `/mnt/plumos/Images/nes/`. The image
base name should match the ROM base name. The same `Images/<system>` layout is
used by plumOS on other supported devices, so artwork can be copied between
them.

## Manual Artwork

You may copy compatible image files into the same directory with the Apps file
manager, SFTP, or SSH. Exit the frontend before replacing many files, then
restart it or run `Refresh TOP`.
