# 2026-07-12 V90S Frontend Apps Launch Check

## Scope

Validate that each visible Apps entry can be launched through the frontend
action path, not only by running the backing shell command directly.

The test uses `plumos-controller-ui-fbdev --script`, which drives the same
`handle_action()` path as button input.

Device:

```text
root@192.0.2.120
kernel arch: aarch64
frontend before test: 18065 /mnt/plumos/bin/plumos-controller-ui-fbdev --renderer fbdev
```

Visible Apps:

```text
1. Scraping      internal:scraping
2. File Manager  shell:/mnt/plumos/bin/plumos-file-manager
3. Music Player  shell:/mnt/plumos/bin/plumos-music-player-launch
4. RetroArch     shell:/mnt/plumos/bin/plumos-retroarch-menu-launch
```

## Scraping

FE script:

```text
start,down,down,down,a,a,a
```

Meaning:

```text
START -> Apps -> Scraping -> A to open -> A to start
```

Limits were set for a minimal real-device test:

```text
PLUMOS_SCRAPING_PLAN_LIMIT=1
PLUMOS_SCRAPING_FETCH_LIMIT=1
PLUMOS_SCRAPING_FETCH_TIMEOUT=10
PLUMOS_SCRAPING_FETCH_RETRY=0
```

Result:

```text
rc=0
status: Scraping finished
app_start  thumbnail-scraping
plan       nes true simple_rom_crc 1 1 1 0
fetch      nes true simple_rom_crc 1 1 1 0
app_finish thumbnail-scraping rc=0
```

The FE moved from Apps to the Scraping screen, then to Scraping Running, then to
Scraping Results.

## File Manager

FE script:

```text
start,down,down,down,a,down,a
```

Meaning:

```text
START -> Apps -> File Manager -> A
```

Result:

```text
rc=0
status: File Manager finished
app_start  file_manager
plumOS File Manager
root       /mnt/plumos
target     /mnt/plumos
/dev/mmcblk0p7 mounted at /mnt/plumos
/dev/mmcblk1p1 mounted at /run/plumos/sd2
app_finish file_manager rc=0
```

The FE showed the running screen, then opened the results screen.

## Music Player

FE script:

```text
start,down,down,down,a,down,down,a
```

Meaning:

```text
START -> Apps -> Music Player -> A
```

Result:

```text
rc=0
status: Music Player finished
app_start  music_player
plumOS Music Player
root       /mnt/plumos
audio_device hw:0,0
mode       play-first
status     no_supported_audio_files
hint       copy WAV files to /mnt/plumos/music or SD2 music
app_finish music_player rc=0
```

The FE showed the running screen, then opened the results screen. No WAV files
were present, so the launcher exited successfully with a clear hint.

## RetroArch

RetroArch owns the display until it exits, so the resident FE was stopped first
with the PID-checked helper:

```text
/mnt/plumos/bin/plumos-frontend-stop stop
```

FE script:

```text
start,down,down,down,a,down,down,down,a
```

Meaning:

```text
START -> Apps -> RetroArch -> A
```

Launch detection:

```text
launch_detected=1
retroarch-stop: RetroArch: pid=19907 running comm='retroarch'
cmdline='/usr/local/bin/retroarch --verbose --config /mnt/plumos/config/retroarch/retroarch-v90s.cfg --menu '
retroarch-stop: launcher: pid=19540 running comm='v90s-retroarch-'
cmdline='/bin/sh /mnt/plumos/bin/v90s-retroarch-launch '
```

Stop and recovery:

```text
/mnt/plumos/bin/v90s-retroarch-stop stop
retroarch-stop: RetroArch: sending TERM to pid=19907
retroarch-stop: launcher: no pidfile
ui rc=0
status: RetroArch finished
```

Final state:

```text
frontend after test: 19995 /mnt/plumos/bin/plumos-controller-ui-fbdev --renderer fbdev
retroarch-stop: RetroArch: no pidfile
retroarch-stop: launcher: no pidfile
```

RetroArch log tail showed:

```text
retroarch-launch: selected_start_mode=menu
retroarch-launch: route video=gl context=mali_fbdev threaded=true input=sdl2 joypad=sdl2 audio=alsa sdl_video=mali sdl_render=software
retroarch-launch: started RetroArch pid=19907 mode=menu
retroarch-launch: retroarch exited rc=0
```

## Conclusion

All visible Apps entries can be launched through the FE Apps path.

```text
Scraping:     pass
File Manager: pass
Music Player: pass
RetroArch:    pass
```
