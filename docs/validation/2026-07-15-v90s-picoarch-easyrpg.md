# V90S PicoArch EasyRPG validation

Date: 2026-07-15

## Scope

Make the frontend `PICO` profile launch the EasyRPG libretro core with a game
directory, visible video, working controls, and continuous BGM on the physical
V90S.

Test content:

```text
/mnt/plumos/roms/EASYRPG/TurnedIntoAGirl
```

## Initial failures

The route failed in four distinct stages:

1. `plumos-picoarch-launch` rejected directory content as a missing ROM.
2. PicoArch attempted to read the directory as a regular content file.
3. EasyRPG registered libretro frame-time and asynchronous-audio callbacks that
   PicoArch did not implement. Without the frame-time callback, EasyRPG's
   internal clock did not advance and every video frame remained black.
4. Driving one 800-sample audio callback from each video frame tied 48 kHz
   audio generation to the V90S LCD's measured 58.955 Hz refresh. ALSA reported
   underruns and the BGM contained periodic popping.

## Implementation

- Accept regular files and directories in `plumos-picoarch-launch` and include
  `/mnt/plumos/lib/libretro` in its runtime library path.
- Pass directory content to cores without trying to load it into memory.
- Accept the libretro pixel formats used by the deployed core and convert the
  frame into PicoArch's RGB565 presentation surface.
- Add the environment commands needed by EasyRPG, including shutdown,
  frame-time, geometry, core-assets, and audio callback registration.
- Dispatch the frame-time callback before every `retro_run()` call.
- Run asynchronous core audio from a dedicated pthread. PicoArch's existing
  audio ring buffer provides backpressure, so audio production follows ALSA
  consumption instead of the LCD refresh period.
- Join and disable the audio callback thread before unloading the core. No
  synchronous-audio fallback is retained.

## Build and deployment

```sh
./scripts/docker-build.sh picoarch
bash -n docker/plumos-v90s-toolchain/scripts/build-picoarch.sh
bash -n package/picoarch-v90s/bin/plumos-picoarch-launch
git diff --check
```

The original diagnostic-free EasyRPG validation binary was copied to:

```text
/mnt/plumos/picoarch/bin/picoarch
```

Original host and device SHA-256:

```text
c996ae4fbf4c23ea0a4c9a7177353a2d9288a2018e78c378c907ec93a5d18d07
```

That binary contained no `VIDEO_PROBE` diagnostic logging.

The 2026-07-16 consolidated PicoArch build retains the same asynchronous audio
callback lifecycle and adds threaded V90S framebuffer presentation plus the
shared ALSA hotplug route. Its SHA-256 is:

```text
df82476720649ccdeba2a39ca3e84e2c8d96da93beda36447d99b62f3f12f400
```

See `2026-07-15-v90s-alsa-mono-usb-audio.md` for the consolidated timing and
USB DAC validation.

## Physical V90S result

The normal frontend route loaded the EasyRPG project, recognized the RPG Maker
2003 RTP, displayed the game, accepted controller input, and played its BGM.
The runtime log confirmed:

```text
INFO: SET_AUDIO_CALLBACK: enabled
INFO: SET_FRAME_TIME_CALLBACK: enabled reference=16666
INFO: Audio callback thread started
Debug: Loading game CookieCutterTurnedIntoGirl
Debug: RTP is "Official English" (675/675)
INFO: Audio callback thread stopped
INFO: SET_AUDIO_CALLBACK: disabled
```

The user confirmed that video and BGM were normal and that the previous
periodic popping was gone. A single ALSA recovery line was observed while the
validated session was being stopped; no repeating underrun was heard during
playback.

After deployment the frontend was the only remaining framebuffer owner and no
PicoArch process was left running.
