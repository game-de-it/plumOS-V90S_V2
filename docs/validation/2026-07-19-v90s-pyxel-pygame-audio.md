# V90S Pyxel pygame Audio

Date: 2026-07-19

## Problem

`LastEmulator.pyxapp` prefers pygame mixer at 44100 Hz stereo and falls back to
Pyxel PCM at 22050 Hz mono. The official pygame 2.6.1 wheel bundled SDL2_mixer
and FluidSynth, but FluidSynth retained host dependencies on
`libgthread-2.0.so.0` and `libglib-2.0.so.0`. The V90S runtime did not expose
`libgthread`, so pygame mixer initialization failed and the game selected its
Pyxel PCM backend.

The old live process proved the fallback route directly:

```text
owner_pid: 2539
channels: 1
rate: 22050
pygame mixer mappings: none
```

## Fix

The `pyxel-runtime` build now packages the Debian Bookworm AArch64 host
libraries below an OS-owned path outside the replaceable venv:

```text
/mnt/plumos/lib/pyxel-host/libglib-2.0.so.0
/mnt/plumos/lib/pyxel-host/libgthread-2.0.so.0
/mnt/plumos/lib/pyxel-host/libpcre2-8.so.0
```

`plumos-pyxel-v90s-launch` requires all three files and adds this directory to
`LD_LIBRARY_PATH`. `Apps -> Pyxel Setup` can therefore continue replacing the
official Pyxel and pygame packages without deleting the V90S host libraries.
The build validation explicitly imports `pygame.mixer` so a top-level pygame
import cannot hide this dependency again.

## Live validation

A pygame-only sine-wave test first proved the complete output route:

```text
pygame_mixer=(44100, -16, 2)
pygame_channel_busy=True
state: RUNNING
owner_pid: 2691
channels: 2
rate: 44100
```

`LastEmulator.pyxapp` was then launched through the normal FE text launch plan,
without a temporary environment override. Its live process was PID 2950. The
process mapped pygame mixer, SDL2_mixer, `libgthread`, `libglib`, and the Pyxel
binding. It alone owned `/dev/snd/pcmC0D0p`, and ALSA reported:

```text
state: RUNNING
owner_pid: 2950
format: S16_LE
channels: 2
rate: 44100
period_size: 8192
buffer_size: 16384
```

Pyxel's own later 22050 Hz audio-device open printed `Failed to initialize
audio device` because the direct ALSA route was already owned by pygame. This
is expected for LastEmulator: it initializes its selected pygame backend before
`pyxel.init()`, and the running 44100 Hz owner proves that audio is no longer
coming from the Pyxel PCM fallback. Video fitting and the single frontend
process remained unchanged.
