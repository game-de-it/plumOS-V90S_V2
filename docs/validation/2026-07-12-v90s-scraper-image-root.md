# V90S Scraper Image Root Validation

Date: 2026-07-12
Device: POWKIDDY V90S
Access: SSH `root@192.0.2.120`

## Change

The frontend's internal Scraping runner now passes an explicit image root to the
thumbnail scraper:

```text
PLUMOS_IMAGE_ROOT=/mnt/plumos/Images
```

This keeps scraper downloads aligned with the gallery thumbnail lookup contract:

```text
/mnt/plumos/Images/<system>/<rom-relative-stem>.png
```

The standalone scraper default was already policy-aligned:

```text
IMAGE_ROOT="${PLUMOS_IMAGE_ROOT:-${SDCARD_ROOT}/Images}"
```

## Live Device Deployment

Updated binaries copied to the device:

```text
/mnt/plumos/bin/plumos-controller-ui-fbdev
/mnt/plumos/bin/plumos-controller-ui
```

The frontend was restarted through the frontend stop wrapper, without stopping
SSH or network services.

Running frontend after restart:

```text
pid=32257
sha256=/proc/32257/exe bf9f4593436895a6a526056e7487d876d2bffa5ea6c0d152173b0d6d78b93550
```

The live binary contains the explicit environment key:

```text
PLUMOS_IMAGE_ROOT=
```

## Scraper Dry Run

Command:

```text
PLUMOS_SDCARD_ROOT=/mnt/plumos \
PLUMOS_ROOT=/mnt/plumos \
PLUMOS_IMAGE_ROOT=/mnt/plumos/Images \
/mnt/plumos/bin/plumos-thumbnail-scraper --system nes --limit 1
```

Result:

```text
status system enabled reason aliases_seen rom_candidates existing_thumbnails missing_thumbnails crc_workers download_workers
plan   nes    true    simple_rom_crc 1 1 1 0 2/2/2 2/2/2
```

## Result

The scraping output path and gallery thumbnail input path are now both anchored
at `/mnt/plumos/Images/`.
