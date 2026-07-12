# V90S live Gallery thumbnail copy

Date: 2026-07-12

## Purpose

After standardizing the V90S artwork path on the A30/MMF-compatible layout:

```text
/mnt/plumos/Images/<system>/<rom-relative-stem>.png
```

check whether the earlier NES scraping run left files in the previous V90S
experimental path, and copy them into the final path if present.

## Live Device

Device:

```text
root@192.0.2.120
```

Before copy:

```text
OLD_MEDIA_NES_IMAGES=82
CURRENT_IMAGES_NES=1
```

Old source examples:

```text
/mnt/plumos/media/nes/images/Akumajou Densetsu.png
/mnt/plumos/media/nes/images/Clu Clu Land.png
/mnt/plumos/media/nes/images/Argus.png
/mnt/plumos/media/nes/images/Baseball.png
```

Copied:

```text
/mnt/plumos/media/nes/images/* -> /mnt/plumos/Images/nes/
```

After copy:

```text
COPIED_IMAGES_NES=82
```

## Scanner Validation

Ran:

```text
PLUMOS_ROOT=/mnt/plumos PLUMOS_SDCARD_ROOT=/mnt/plumos \
  /mnt/plumos/bin/plumos-library-scan --system nes --with-thumbnails
```

Result:

```text
system nes                roms=86 thumbnails=82
summary alias_dirs=2 files_seen=95 matched=86 roms=86 thumbnails=82 elapsed_ms=93
wrote: /mnt/plumos/state/frontend/systems/nes.json
```

## Gallery Output Validation

Manual frontend script output included the final `Images/nes` paths in
`graphic_entry` media fields:

```text
graphic_entry 1 Akumajou Densetsu nes/Akumajou Densetsu.nes /mnt/plumos/Images/nes/Akumajou Densetsu.png
graphic_entry 0 Argus nes/Argus.nes /mnt/plumos/Images/nes/Argus.png
graphic_entry 0 Baltron nes/Baltron.nes /mnt/plumos/Images/nes/Baltron.png
```

Frontend remained running:

```text
plumos-frontend-stop: pid=31432 cmd=/mnt/plumos/bin/plumos-controller-ui-fbdev --renderer fbdev
```
