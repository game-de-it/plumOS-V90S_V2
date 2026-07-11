# 2026-07-12 V90S Frontend Apps Port

## Scope

Port the MMF-style frontend Apps menu path to V90S without overwriting user
RetroArch configuration.

Visible Apps on V90S after this change:

- `Scraping`
- `File Manager`
- `RetroArch`

Hidden Apps/helper entries:

- `thumbnail-plan`
- `thumbnail-fetch`
- `thumbnail-results`
- `music_player` remains hidden until a V90S music player runtime is ported.

The V90S app layer uses `/mnt/plumos`, so MMF paths under
`/mnt/SDCARD/plumos` were not copied directly.

## Changed Files

```text
package/frontend-v90s/plumos/config/frontend/apps.json
package/frontend-v90s/plumos/config/frontend/systems.json
package/frontend-v90s/plumos/bin/plumos-file-manager
package/frontend-v90s/plumos/bin/plumos-thumbnail-scraper
```

`plumos-thumbnail-scraper` is based on the MMF scraper, adapted for:

```text
ROM root:      /mnt/plumos/roms
image root:    /mnt/plumos/media
image layout:  /mnt/plumos/media/<system>/images/<rom-stem>.png
```

NES scraping is enabled first because NES/QuickNES is the current validated
V90S emulator path.

## Build Validation

Commands:

```sh
python3 -m json.tool package/frontend-v90s/plumos/config/frontend/apps.json
python3 -m json.tool package/frontend-v90s/plumos/config/frontend/systems.json
sh -n package/frontend-v90s/plumos/bin/plumos-thumbnail-scraper
sh -n package/frontend-v90s/plumos/bin/plumos-file-manager
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

Known existing warning:

```text
src/frontend/plumos_text_ui.c: snprintf cores_buf may be truncated
```

Output app-layer hashes:

```text
0b4f22096a21a61b32de5be3809eea833b87cde24e6d295af0b45139669dd1e5  bin/plumos-file-manager
f7909b438b02a0902651c477ffdcd07c8bc40a2223c428db9933120837498f9f  bin/plumos-thumbnail-scraper
05f9ed6030b7983cd07efa7197d63010329302e1b484c1c1245a538fad97d5d2  config/frontend/apps.json
d273973bd14ac1d3d127cedefe36a6f1b6fed6a989d757cc3d38d2a916136132  config/frontend/systems.json
```

## Live Deploy

Only these files were copied to the live device:

```text
/mnt/plumos/bin/plumos-file-manager
/mnt/plumos/bin/plumos-thumbnail-scraper
/mnt/plumos/config/frontend/apps.json
/mnt/plumos/config/frontend/systems.json
```

`manifest.json`, `checksums.sha256`, RetroArch config, ROMs, saves, and other
app-layer files were not overwritten.

The previous frontend `apps.json` and `systems.json` were backed up on device
with `.bak-apps-<timestamp>` suffixes.

## Live Device Validation

Device:

```text
root@192.0.2.120
```

Deployed file hashes:

```text
0b4f22096a21a61b32de5be3809eea833b87cde24e6d295af0b45139669dd1e5  /mnt/plumos/bin/plumos-file-manager
f7909b438b02a0902651c477ffdcd07c8bc40a2223c428db9933120837498f9f  /mnt/plumos/bin/plumos-thumbnail-scraper
05f9ed6030b7983cd07efa7197d63010329302e1b484c1c1245a538fad97d5d2  /mnt/plumos/config/frontend/apps.json
d273973bd14ac1d3d127cedefe36a6f1b6fed6a989d757cc3d38d2a916136132  /mnt/plumos/config/frontend/systems.json
```

Scraper policy:

```text
system  enabled  reason          crc_default  crc_bulk  crc_max  dl_default  dl_bulk  dl_max  extensions
nes     true     simple_rom_crc  2            2         2        2           2        2       nes unf unif zip
```

Scraper plan on the live SD2-backed ROM set:

```text
status  system  enabled  reason          aliases_seen  rom_candidates  existing_thumbnails  missing_thumbnails  crc_workers  download_workers
plan    nes     true     simple_rom_crc  1             5               0                    5                   2/2/2        2/2/2
```

Scraper image-layout smoke test with a temporary `roms/FC/test.nes` and
`media/nes/images/test.png` confirmed that the V90S scraper checks the
system-ID image directory, not the alias directory:

```text
plan    nes     true     simple_rom_crc  1  1  1  0  2/2/2  2/2/2
```

Apps menu as reported by the device text UI:

```text
No.  App                      Kind       Launch profile
---  ---                      ----       --------------
  1. Scraping                 tool       internal:scraping
  2. File Manager             tool       shell:/mnt/plumos/bin/plumos-file-manager
  3. RetroArch                emulator   shell:/mnt/plumos/bin/plumos-retroarch-menu-launch
```

Frontend restart used the PID-checked stop helper:

```text
before: pid=9046 cmd=/mnt/plumos/bin/plumos-controller-ui-fbdev --renderer fbdev
after:  pid=16558 cmd=/mnt/plumos/bin/plumos-controller-ui-fbdev --renderer fbdev
```

File Manager smoke output:

```text
plumOS File Manager
root    /mnt/plumos
target  /mnt/plumos

[mounts]
/dev/mmcblk0p7  1022.0M  345.2M  676.8M  34%  /mnt/plumos
/dev/mmcblk1p1   116.4G   32.0G   84.4G  27%  /run/plumos/sd2

[target]
file  COMPAT_VENDOR  16
dir   Logs
file  MOUNT_PATH     12
dir   Saves
dir   Screenshots
dir   States
file  VERSION        10
dir   adb
dir   backups
dir   bin
dir   bios
```

## Notes

The V90S File Manager is intentionally a small file overview app for now. MMF's
stock `App/Commander_Italic` route and A30's bundled NextCommander route both
carry device/runtime assumptions that are not yet validated on V90S.

The V90S music player is kept hidden until audio/input/display ownership for a
native player is validated.
