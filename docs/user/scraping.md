# Downloading Thumbnail Images

When the V90S is connected to Wi-Fi, it can download images for the game list.
This feature is called scraping.

## Download Images

1. Connect a supported USB Wi-Fi adapter.
2. Connect to Wi-Fi from `START -> Network Settings`.
3. Open Scraping from Apps or the ROM list.
4. Select the game system and start the download.
5. Return to TOP and run `Refresh TOP` if artwork is not shown immediately.

Keep the device powered and connected while files are being downloaded.

## Image Location

Images are stored by game system below:

```text
/mnt/plumos/Images/<system>/
```

For example, NES images are stored under `/mnt/plumos/Images/nes/`. The part of
the image filename before its extension must match the ROM filename. Other
plumOS devices use the same folder layout, so images can be copied between them.

## Manual Artwork

You can copy images into the same folder with the Apps file manager, SFTP, or
SSH. Exit the game list before replacing many files. Start it again or run
`Refresh TOP` after the copy finishes.
