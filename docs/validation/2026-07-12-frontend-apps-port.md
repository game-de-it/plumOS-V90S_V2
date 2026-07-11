# 2026-07-12 V90S Frontend Apps Port

## Scope

Port the MMF-style frontend Apps menu path to V90S without overwriting user
RetroArch configuration.

Visible Apps on V90S now match the MMF Apps set and order:

```text
1. Scraping
2. File Manager
3. Music Player
4. RetroArch
```

Hidden Apps/helper entries:

```text
thumbnail-plan
thumbnail-fetch
thumbnail-results
settings
network
```

The V90S app layer uses `/mnt/plumos`, so MMF paths under
`/mnt/SDCARD/plumos` were adapted instead of copied verbatim.

## Runtime Notes

The MMF/A30 file manager and music player payloads cannot be copied directly as
the final V90S payloads:

```text
MMF music player:  32-bit ARM, /mnt/SDCARD/plumos/lib/ld-linux-armhf.so.3
A30 NextCommander: 32-bit ARM, /lib/ld-linux-armhf.so.3
V90S runtime:      aarch64, /lib/aarch64-linux-gnu/ld-linux-aarch64.so.1
```

MMF does include `src/apps/plumos_music_player.c`, so a fuller native V90S music
player is a source port/build-system task rather than a binary-copy task.

For now:

- `File Manager` is a safe file overview app that shows mounts and directory
  contents.
- `Music Player` is a V90S-safe ALSA/WAV entrypoint. It lists and plays WAV
  files from `/mnt/plumos/music` and SD2 music paths, and has a `--smoke`
  command for short ALSA validation.
- `Scraping` uses the V90S-adapted MMF thumbnail scraper.
- `RetroArch` remains the validated V90S RetroArch launch route.

## Changed Files

```text
package/frontend-v90s/plumos/config/frontend/apps.json
package/frontend-v90s/plumos/config/frontend/systems.json
package/frontend-v90s/plumos/bin/plumos-file-manager
package/frontend-v90s/plumos/bin/plumos-music-player-launch
package/frontend-v90s/plumos/bin/plumos-thumbnail-scraper
scripts/build-app-layer.sh
TODO.md
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
sh -n package/frontend-v90s/plumos/bin/plumos-music-player-launch
git diff --check
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
17b74743d3ecf7a189494acc82e7eb486d7e26ef7d244e0505e4735413533062  bin/plumos-music-player-launch
0b4f22096a21a61b32de5be3809eea833b87cde24e6d295af0b45139669dd1e5  bin/plumos-file-manager
f7909b438b02a0902651c477ffdcd07c8bc40a2223c428db9933120837498f9f  bin/plumos-thumbnail-scraper
4ba8d94e95d7ff0e493b78dd76aee766bd2c1f9dd7bab60cca9dab5626b0c4e9  config/frontend/apps.json
d273973bd14ac1d3d127cedefe36a6f1b6fed6a989d757cc3d38d2a916136132  config/frontend/systems.json
```

Generated visible Apps:

```text
1. Scraping      scraping       tool      internal:scraping
2. File Manager  file_manager   tool      shell:/mnt/plumos/bin/plumos-file-manager
3. Music Player  music_player   tool      shell:/mnt/plumos/bin/plumos-music-player-launch
4. RetroArch     retroarch      emulator  shell:/mnt/plumos/bin/plumos-retroarch-menu-launch
```

## Live Deploy

Only these files were copied to the live device during the final Apps parity
deploy:

```text
/mnt/plumos/bin/plumos-music-player-launch
/mnt/plumos/config/frontend/apps.json
```

Previous `apps.json` was backed up under `/mnt/plumos/backups/`.

`manifest.json`, `checksums.sha256`, RetroArch config, ROMs, saves, and other
app-layer files were not overwritten during the final partial deploy.

## Live Device Validation

Device:

```text
root@192.0.2.120
kernel arch: aarch64
```

Deployed final file hashes:

```text
17b74743d3ecf7a189494acc82e7eb486d7e26ef7d244e0505e4735413533062  /mnt/plumos/bin/plumos-music-player-launch
4ba8d94e95d7ff0e493b78dd76aee766bd2c1f9dd7bab60cca9dab5626b0c4e9  /mnt/plumos/config/frontend/apps.json
```

Apps menu as reported by the device text UI:

```text
No.  App                      Kind       Launch profile
---  ---                      ----       --------------
  1. Scraping                 tool       internal:scraping
  2. File Manager             tool       shell:/mnt/plumos/bin/plumos-file-manager
  3. Music Player             tool       shell:/mnt/plumos/bin/plumos-music-player-launch
  4. RetroArch                emulator   shell:/mnt/plumos/bin/plumos-retroarch-menu-launch
```

File Manager smoke output:

```text
plumOS File Manager
root    /mnt/plumos
target  /mnt/plumos

[mounts]
/dev/mmcblk0p7  1022.0M  345.2M  676.8M  34%  /mnt/plumos
/dev/mmcblk1p1   116.4G   32.0G   84.4G  27%  /run/plumos/sd2
```

Music Player list mode:

```text
plumOS Music Player
root          /mnt/plumos
audio_device  hw:0,0
mode          list
status        no_supported_audio_files
hint          copy WAV files to /mnt/plumos/music or SD2 music
```

Music Player ALSA smoke mode:

```text
Playback device is hw:0,0
Stream parameters are 48000Hz, S16_LE, 1 channels
Sine wave rate is 440.0000Hz
status  smoke_finished
```

Scraper plan on the live SD2-backed ROM set:

```text
status  system  enabled  reason          aliases_seen  rom_candidates  existing_thumbnails  missing_thumbnails  crc_workers  download_workers
plan    nes     true     simple_rom_crc  1             5               0                    5                   2/2/2        2/2/2
```

Scraper fetch validation:

```text
status  system  enabled  reason          aliases_seen  rom_candidates  existing_thumbnails  missing_thumbnails  crc_checked  crc_matched  downloaded
fetch   nes     true     simple_rom_crc  1             1               0                    1                   1            1            1
```

Resulting thumbnail:

```text
/mnt/plumos/media/nes/images/Akumajou Densetsu.png
```

RetroArch Apps entry validation:

```text
retroarch_launcher_executable=yes
retroarch_launcher_shell_syntax=ok
```

Frontend restart used the PID-checked stop helper. After restart there was one
frontend process:

```text
18065 /mnt/plumos/bin/plumos-controller-ui-fbdev --renderer fbdev
```

## Follow-ups

- Replace the temporary file overview app with a fuller V90S-native file
  manager payload once a 64-bit-compatible candidate is validated.
- Replace the lightweight ALSA/WAV Music Player entry with a fuller native UI
  after display/input/audio ownership is validated.
