# V90S Refresh TOP system definitions

Date: 2026-07-12

## Question

The frontend Refresh TOP action was expected to update systems from:

```text
/mnt/plumos/roms/
```

The scan path is correct, but the live V90S app layer still had only the
minimal NES system definition:

```text
SYSTEMS_IDS:nes
```

That meant Refresh TOP could rescan ROM files under `/mnt/plumos/roms`, but it
could not create new TOP systems such as SFC, GB, GBA, Mega Drive, etc. because
those systems were not present in `config/frontend/systems.json`.

## Change

Replaced the V90S minimal `systems.json` with the MMF system catalog and kept
the V90S NES launch default on the known-good QuickNES route:

```text
NES default_launch_profile=retroarch:quicknes
NES launch_profiles=["retroarch:quicknes"]
```

The V90S scanner still treats `/mnt/plumos/roms` as the single ROM root. System
folder names are resolved through each system's `directory_aliases`.

## Local Validation

Compiled a host copy of `src/frontend/plumos_library_scan.c` and scanned a temp
app layer with:

```text
roms/FC/test.nes
roms/sfc/test.sfc
roms/gb/test.gb
```

Result:

```text
systems: .../config/frontend/systems.json loaded=91
system nes                roms=1 thumbnails=0
system sfc                roms=1 thumbnails=0
system gb                 roms=1 thumbnails=0
summary alias_dirs=5 files_seen=5 matched=3 roms=3 thumbnails=0 elapsed_ms=2
```

## Build Validation

Built the frontend and app layer through the official Docker entry point:

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

## Live Device Validation

Device:

```text
root@192.0.2.120
```

Deployed:

```text
package/frontend-v90s/plumos/config/frontend/systems.json
-> /mnt/plumos/config/frontend/systems.json
```

Ran:

```text
PLUMOS_ROOT=/mnt/plumos PLUMOS_SDCARD_ROOT=/mnt/plumos \
  /mnt/plumos/bin/plumos-library-scan --defer-thumbnails
```

Result:

```text
systems: /mnt/plumos/config/frontend/systems.json loaded=91
system nes                roms=86 thumbnails=0
system sfc                roms=92 thumbnails=0
system gb                 roms=40 thumbnails=0
system gbc                roms=10 thumbnails=0
system gba                roms=18 thumbnails=0
system megadrive          roms=148 thumbnails=0
system gamegear           roms=17 thumbnails=0
system pcengine           roms=50 thumbnails=0
system pcenginecd         roms=1 thumbnails=0
system psx                roms=4 thumbnails=0
system ngpc               roms=27 thumbnails=0
system fbneo              roms=18 thumbnails=0
system pico8              roms=1 thumbnails=0
system scummvm            roms=1 thumbnails=0
system ports              roms=33 thumbnails=0
system pyxel              roms=3 thumbnails=0
summary alias_dirs=85 files_seen=9296 matched=548 roms=549 thumbnails=0 elapsed_ms=2526
wrote: /mnt/plumos/state/frontend/library-index.json
```

Text UI TOP check:

```text
plumOS text UI - TOP
cache: /mnt/plumos/state/frontend/library-index.json
cache_ready_ms: 2507

  1.     NES                 retroarch:quicknes
  2.     SFC                 retroarch:snes9x2005
  3.     GB                  retroarch:gambatte
  4.     GBC                 retroarch:gambatte
  5.     GBA                 retroarch:gpsp
  6.     Mega Drive          retroarch:genesis_plus_gx
  7.     Game Gear           retroarch:genesis_plus_gx
  8.     PC Engine           retroarch:mednafen_pce_fast
  9.     PC Engine CD        retroarch:mednafen_pce_fast
 10.     PlayStation         standalone:pcsx_rearmed
 11.     NGPC                retroarch:mednafen_ngp
 12.     FBNeo               retroarch:fbneo
 13.     PICO-8              retroarch:fake08
 14.     ScummVM             standalone:scummvm
 15.     Ports               external:port
 16.     Pyxel               pyxel:mmf
 17. *   Favorites           internal:favorites
```

Restarted the live frontend with the PID-safe frontend stop helper:

```text
plumos-frontend-stop: pid=24017 cmd=/mnt/plumos/bin/plumos-controller-ui-fbdev --renderer fbdev
plumos-frontend-stop: TERM pid=24017
plumos-frontend-stop: pid=24274 cmd=/mnt/plumos/bin/plumos-controller-ui-fbdev --renderer fbdev
```

## Notes

Refresh TOP does not auto-invent systems from arbitrary folder names. The
frontend scans `/mnt/plumos/roms`, but system recognition is intentionally
controlled by `config/frontend/systems.json` so that aliases, extensions,
artwork paths, scraping policy, and launch profiles remain deterministic.
