# 2026-07-12 V90S Music Player Input Fix

## Symptom

Music Player rendered on the V90S screen, but the built-in controller did not
operate it.

## Cause

The first port opened `/dev/input/event0`:

```text
input opened path=/dev/input/event0 name=sunxi-keyboard
```

The real V90S controller is exposed as `adc_gamepad` on `/dev/input/event4`:

```text
N: Name="adc_gamepad"
H: Handlers=event4
B: EV=20000b
B: KEY=1fdb000000000000 0 0 0 0
B: ABS=3001b
```

The Music Player input discovery treated `sunxi-keyboard` as a V90S gamepad and
scanned from `event0`, so it selected the wrong event device before reaching
`adc_gamepad`.

## Fix

- Prioritize V90S `adc_gamepad` / `adc gamepad` / `plumOS V90S` before A30, MMF,
  or keyboard fallbacks.
- Keep `sunxi-keyboard` and `gpio-keys` only as late fallback devices.
- Add `ABS_X` and `ABS_Y` handling with the same 512 deadzone used by the V90S
  frontend; keep existing `ABS_HAT0X` and `ABS_HAT0Y` handling.

## Build

```sh
./scripts/docker-build.sh music-player
./scripts/docker-build.sh app-layer
```

Updated app-layer hashes:

```text
ec06375137f2e1abc9eeb4a41f8d1587fe856f05eb83eb5e42cad4d9379e5c76  output/app-layer/v90s/apps/music-player/bin/plumos-music-player.bin
6905bbe7f0496211f16e4255755b89d5c2e009658e70d1a7f68737281067ee90  output/app-layer/v90s/bin/plumos-music-player-launch
```

Deployed payload:

```text
f6842d337a44606127399156ce0be14bc4d1a0e66a9a481603e6149fabe47d96  /mnt/plumos/updates/plumos-v90s-music-input-fix.tar.gz
```

## Live Device Check

The running Music Player process was stopped by matching the exact cmdline:

```text
stop_music_player pid=23365 cmd=/mnt/plumos/apps/music-player/bin/plumos-music-player.bin
```

After deployment, a short launch confirmed the corrected event device:

```text
input opened path=/dev/input/event4 name=adc_gamepad
audio alsa setup ok device=hw:0,0 rate=48000 channels=2
```

The frontend was restored to a single process:

```text
plumos-frontend-stop: TERM pid=23867
plumos-frontend-stop: TERM pid=23231
plumos-frontend-stop: frontend not running
plumos-frontend-stop: pid=24017 cmd=/mnt/plumos/bin/plumos-controller-ui-fbdev --renderer fbdev
24017 root      0:00 /mnt/plumos/bin/plumos-controller-ui-fbdev --renderer fbdev
```

## Result

The Music Player now opens the V90S controller event device. Physical button
operation still needs user confirmation from the rendered Music Player screen.
