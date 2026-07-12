# 2026-07-12 V90S NextCommander and Music Player Port

## Purpose

Replace the temporary V90S-only foreground Apps payloads with the actual
MMF/A30-style programs:

- File Manager: LoveRetro NextCommander, following the A30 file-manager path.
- Music Player: `plumos_music_player.c` imported from plumOS-MMF and adapted for
  V90S fbdev, input, and ALSA.

The FE Apps entries now call:

```text
File Manager  shell:/mnt/plumos/bin/plumos-nextcommander-launch
Music Player  shell:/mnt/plumos/bin/plumos-music-player-launch
```

## Build Outputs

Commands:

```sh
./scripts/docker-build.sh image
./scripts/docker-build.sh nextcommander
./scripts/docker-build.sh music-player
./scripts/docker-build.sh frontend
./scripts/docker-build.sh app-layer
```

Final app-layer hashes:

```text
26caad11b917606ec6d3269fd31745a91eb91e6acc9e242fff2dfc638d969dbe  output/app-layer/v90s/bin/plumos-nextcommander-launch
471a34b047e241ae1a410e9195e144ba107eed70e58c86f8ea27f4754b976117  output/app-layer/v90s/apps/nextcommander/bin/NextCommander
6905bbe7f0496211f16e4255755b89d5c2e009658e70d1a7f68737281067ee90  output/app-layer/v90s/bin/plumos-music-player-launch
b1ebdd198623f66392d2cc628b2ffbd0c77b5258305124a89b133162c4363434  output/app-layer/v90s/apps/music-player/bin/plumos-music-player.bin
e642a7a65017fe4c74c713baac7fdca42e2c8ebbfc64aad9268e43b3c0c7a9bd  output/app-layer/v90s/config/frontend/apps.json
```

## Implementation Notes

NextCommander:

- Adds `PLATFORM=v90s` to upstream `Makefile`.
- Uses `/mnt/plumos` and `/mnt/plumos/roms` as default panels.
- Builds an aarch64 SDL2 binary.
- Uses the plumOS SDL2 PowerVR runtime plus `/usr/lib/powervr`.
- Starts PowerVR services with `pvrsrvctl --start` before launching.
- V90S-specific patch renders the existing SDL surface UI through an SDL texture
  because the V90S `mali` SDL2 backend requires the EGL/GLES window path.

Music Player:

- Source was copied from plumOS-MMF.
- Uses the V90S fbdev renderer compatibility header.
- Scans `/mnt/plumos/music`, `/mnt/plumos/roms/music`, and SD2 equivalents.
- Uses ALSA `hw:0,0` by default, configurable with
  `PLUMOS_MUSIC_ALSA_DEVICE`.
- Keeps FFmpeg/libav fallback decoding for additional formats.

## Live Device Deployment

Device:

```text
ssh root@192.0.2.120
password: linux
```

The full app payload was transferred as:

```text
aba2187948ef953ae3cfc82b0b85cc7fedf0393c0cecf1576b0ad3ea1b737136  /mnt/plumos/updates/plumos-v90s-apps-port.tar.gz
```

After the NextCommander PowerVR launcher fix, the smaller follow-up payload was:

```text
ee13a7819d1fa76629f45390e1fd36cd42502732a2103eec77a5286d0695e1e3  /mnt/plumos/updates/plumos-v90s-nextcommander-launcher.tar.gz
```

## Live Smoke Test

The frontend was stopped with `/mnt/plumos/bin/plumos-frontend-stop stop`, each
launcher was run directly, then the frontend was restarted.

NextCommander stayed alive for the smoke window:

```text
nextcommander_running_pid=23215
Reading settings from /mnt/plumos/apps/nextcommander/config/v90s.cfg
Set resource directory to /mnt/plumos/apps/nextcommander/res/
Opened Joystick 0
Name: adc_gamepad
Number of Axes: 4
Number of Buttons: 11
Number of Balls: 0
MALI_CreateWindow:0xaaaae61abdf0 done.
```

Earlier failure before the launcher fix was:

```text
INFO: Failed to create window: Could not initialize OpenGL / GLES library
```

That was fixed by adding `/usr/lib/powervr` to `LD_LIBRARY_PATH` and running
`pvrsrvctl --start` before launching NextCommander.

Music Player ran through input and ALSA initialization. No music files were
present on the test SD, so playback itself remains a separate physical
validation item.

```text
scan total tracks=0
input opened path=/dev/input/event0 name=sunxi-keyboard
audio alsa setup ok device=hw:0,0 rate=48000 channels=2
```

The frontend restarted cleanly after the smoke test:

```text
plumos-frontend-stop: pid=23231 cmd=/mnt/plumos/bin/plumos-controller-ui-fbdev --renderer fbdev
```

## Result

Pass for build integration and live-device smoke launch.

Remaining real-control validation:

- Confirm NextCommander button mapping through the physical V90S controls.
- Put at least one music file under `/mnt/plumos/music` or `/mnt/plumos/roms/music`
  and confirm Music Player navigation plus audio playback.
