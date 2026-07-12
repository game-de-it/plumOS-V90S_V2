# 2026-07-12 V90S frontend Apps foreground fix

## Goal

Fix the V90S `File Manager` and `Music Player` Apps entries after live-device
testing showed that selecting them from the frontend did not start the intended
application screens.

## MMF/A30 comparison

MMF and A30 register these Apps entries as foreground shell applications:

- `File Manager`: `shell:/mnt/SDCARD/plumos/bin/plumos-nextcommander-launch`
- `Music Player`: `shell:/mnt/SDCARD/plumos/bin/plumos-music-player-launch`

Those entries do not set `show_results`. Only background/report-style tools
such as thumbnail scraping use the frontend result-log screen.

The V90S Apps definitions had diverged:

- `File Manager` used `show_results: true`
- `Music Player` used `show_results: true`
- the music launcher defaulted to a diagnostic `--play-first` path instead of
  a foreground UI

That made both entries behave like command-output tools rather than Apps that
take over the framebuffer.

Directly copying MMF/A30 payloads is not correct for V90S. The MMF Music Player,
MMF DinguxCommander, and A30 NextCommander payloads inspected in the reference
trees are 32-bit ARM/armhf binaries. V90S userspace is aarch64, so this fix
adds V90S-native foreground payloads instead of reusing those binaries.

## Change

- Removed `show_results` from the visible V90S `File Manager` and
  `Music Player` Apps entries.
- Added a V90S-native fbdev Apps payload source:
  `src/apps/plumos_v90s_apps.c`.
- Built two aarch64 entry binaries from the same source:
  `/mnt/plumos/bin/plumos-file-manager`
  and `/mnt/plumos/bin/plumos-music-player-ui`.
- Changed `plumos-music-player-launch` so the default mode is the foreground
  UI. Diagnostic modes remain available as `--list`, `--smoke`, and
  `--play-first`.

The File Manager is intentionally a safe native file overview/navigation app for
now. A fuller NextCommander-compatible file manager remains a separate task.

The Music Player foreground UI currently lists common audio files and can play
WAV/WAVE files through `aplay -D hw:0,0`. A fuller MMF-style decoder/player port
remains a separate task.

## Build validation

Commands:

```sh
python3 -m json.tool package/frontend-v90s/plumos/config/frontend/apps.json
sh -n package/frontend-v90s/plumos/bin/plumos-music-player-launch
git diff --check
./scripts/docker-build.sh frontend
./scripts/docker-build.sh app-layer
```

The generated app-layer manifest includes:

```text
bin/plumos-file-manager
bin/plumos-music-player-ui
bin/plumos-music-player-launch
config/frontend/apps.json
```

Final app-layer hashes:

```text
1f25f87a7f62e271eccd48d0b80ab99bc8349a7b766fee5f882c6ae6c1c94af9  bin/plumos-file-manager
1f25f87a7f62e271eccd48d0b80ab99bc8349a7b766fee5f882c6ae6c1c94af9  bin/plumos-music-player-ui
d49d063e26455d6bccced472ca106def98b3ee5c2f89d521fd2bb2403684ad7e  bin/plumos-music-player-launch
48e3802f76d0b0e46f9e35e1b4076a77ed1a4a15a2236e092e9f535bf7b5b807  config/frontend/apps.json
```

## Live-device validation

Device:

```text
root@192.0.2.120
```

Deployed:

```text
/mnt/plumos/bin/plumos-file-manager
/mnt/plumos/bin/plumos-music-player-ui
/mnt/plumos/bin/plumos-music-player-launch
/mnt/plumos/config/frontend/apps.json
```

The previous live `apps.json` was backed up under:

```text
/mnt/plumos/backups/apps.json.bak-front-apps-<timestamp>
```

Frontend scripted launch checks:

- `START -> Apps -> File Manager`: process returned successfully and frontend
  reported `File Manager finished`.
- `START -> Apps -> Music Player`: process returned successfully and frontend
  reported `Music Player finished`.

After the final deploy, both scripted launch paths returned `rc=0`:

```text
File Manager sequence: start,down,down,down,a,down,a
Music Player sequence: start,down,down,down,a,down,down,a
```

Framebuffer proof was captured from `/dev/fb0` while each App was active:

- File Manager showed `PLUMOS FILE MANAGER`, path `/mnt/plumos`, and directory
  entries such as `bin`, `bios`, `config`, and `cores`.
- Music Player showed `PLUMOS MUSIC PLAYER`; with no music files present it
  correctly displayed `No supported music files`.

After validation, the resident frontend was restarted:

```text
/mnt/plumos/bin/plumos-controller-ui-fbdev --renderer fbdev
```
