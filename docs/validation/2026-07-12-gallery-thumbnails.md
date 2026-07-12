# V90S Gallery thumbnail path and rendering

Date: 2026-07-12

## Decision

Use the same thumbnail path convention as plumOS A30/MMF:

```text
/mnt/plumos/Images/<system>/<rom-relative-stem>.png
```

Examples:

```text
/mnt/plumos/Images/nes/Super Mario Bros..png
/mnt/plumos/Images/nes/Akumajou Densetsu.png
```

The V90S app layer uses `/mnt/plumos` as `PLUMOS_SDCARD_ROOT`, so this is the
V90S equivalent of the A30/MMF `$PLUMOS_SDCARD_ROOT/Images/<system>` layout.

## Current Path Flow

- `package/frontend-v90s/plumos/bin/plumos-thumbnail-scraper`
  - default `PLUMOS_IMAGE_ROOT=$PLUMOS_SDCARD_ROOT/Images`
  - writes thumbnails to `$PLUMOS_IMAGE_ROOT/<system>/<rom-relative-stem>.png`
- `package/frontend-v90s/plumos/config/frontend/systems.json`
  - keeps A30/MMF-style `artwork.lookup` entries such as
    `{"root": "sdcard", "path": "Images/nes"}`
- `src/frontend/plumos_library_scan.c`
  - resolves thumbnail paths during `--with-thumbnails`
  - writes them as `media.thumbnail` in
    `state/frontend/systems/<system>.json`
- `src/frontend/plumos_controller_ui.c`
  - emits `graphic_entry` with thumbnail path as the media column
  - refreshes the current system cache with thumbnails before opening Gallery
- `src/frontend/plumos_fbdev_renderer.h`
  - Gallery cards already draw the media column with
    `plumos_fbdev_draw_png_contain`

## Local Validation

Created:

```text
roms/FC/thumbtest.nes
Images/nes/thumbtest.png
```

Ran:

```text
PLUMOS_ROOT=<tmp>/plumos PLUMOS_SDCARD_ROOT=<tmp>/plumos \
  plumos-library-scan --system nes --with-thumbnails
```

Result:

```text
system nes                roms=1 thumbnails=1
summary alias_dirs=1 files_seen=1 matched=1 roms=1 thumbnails=1 elapsed_ms=2
```

The generated system cache contained:

```text
<tmp>/plumos/Images/nes/thumbtest.png
```

## Build Validation

Built through the official Docker entry point:

```text
./scripts/docker-build.sh frontend
./scripts/docker-build.sh app-layer
```

Result:

```text
created: output/frontend/v90s
created: output/app-layer/v90s
version: 0.1.0-dev
compat_vendor: v90s-stockos-r1
mount_path: /mnt/plumos
```

Existing `plumos_text_ui.c` `%ld` truncation warnings remain unrelated.

## Live Device Validation

Device:

```text
root@192.0.2.120
```

Updated:

```text
/mnt/plumos/bin/plumos-controller-ui-fbdev
/mnt/plumos/bin/plumos-controller-ui
/mnt/plumos/bin/plumos-library-scan
/mnt/plumos/bin/plumos-thumbnail-scraper
/mnt/plumos/config/frontend/systems.json
```

Confirmed live scraper path:

```text
IMAGE_ROOT="${PLUMOS_IMAGE_ROOT:-${SDCARD_ROOT}/Images}"
```

Confirmed live `systems.json` lookup:

```text
{"root": "sdcard", "path": "Images/nes"}
```

Added one test PNG:

```text
/mnt/plumos/Images/nes/Akumajou Densetsu.png
```

Ran:

```text
PLUMOS_ROOT=/mnt/plumos PLUMOS_SDCARD_ROOT=/mnt/plumos \
  /mnt/plumos/bin/plumos-library-scan --system nes --with-thumbnails
```

Result:

```text
system nes                roms=86 thumbnails=1
summary alias_dirs=2 files_seen=95 matched=86 roms=86 thumbnails=1 elapsed_ms=729
wrote: /mnt/plumos/state/frontend/systems/nes.json
```

Gallery script output included the thumbnail path as the media column:

```text
graphic_entry	1	Akumajou Densetsu	nes/Akumajou Densetsu.nes	/mnt/plumos/Images/nes/Akumajou Densetsu.png
graphic_entry	0	Argus	nes/Argus.nes	<empty>
graphic_entry	0	Baltron	nes/Baltron.nes	<empty>
```

Restarted the live frontend:

```text
plumos-frontend-stop: pid=31432 cmd=/mnt/plumos/bin/plumos-controller-ui-fbdev --renderer fbdev
```
