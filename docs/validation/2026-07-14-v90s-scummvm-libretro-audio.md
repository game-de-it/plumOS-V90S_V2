# V90S ScummVM Libretro Audio Validation

Date: 2026-07-14

## Symptom

The ScummVM libretro core displayed and accepted controller input correctly on
the physical V90S, but Beneath a Steel Sky skipped audio heavily:

```text
core=/mnt/plumos/cores/scummvm_libretro.so
content=/mnt/plumos/roms/SCUMMVM/BASS-Floppy-1.3
```

The V90S video contract was unchanged:

```text
video_refresh_rate=58.917103
video_threaded=true
vrr_runloop_enable=true
audio_device=hw:0,0
audio_out_rate=48000
```

## Findings

There were three separate problems. Treating an ALSA stream that remained
`RUNNING` as proof of normal audible output hid the final one.

1. The synchronous `alsa` driver repeatedly entered `PREPARED`. Its trigger
   time reset after recovery and `avail_max` exceeded the 7680-frame hardware
   buffer. `alsathread` with the core-requested 160 ms latency kept the PCM
   stream running, but the audible skipping remained.
2. The generated frontend launcher accepted per-ROM `--audio` and
   `--audio-latency` arguments but discarded them. The saved ScummVM override
   therefore did not select `alsathread` unless the persistent RetroArch config
   had already been edited manually.
3. With the `interactive` CPU governor, ScummVM libretro's short, bursty load
   remained at 600-816 MHz. The displayed rate fell to 42-47 fps even though
   the core advertised 58.917 Hz. Because the libretro backend retrieves one
   video frame's audio during each `retro_run()`, the low execution rate also
   reduced the supplied audio duration. This was the decisive audible fault.

All four CPU cores were online. `top` showed substantial idle CPU time, so the
low frame rate was governor response rather than full SoC saturation.

## Comparison Tests

The standalone ScummVM build ran the same game normally through SDL2 and ALSA:

```text
format=S16_LE
channels=2
rate=44100
period_size=1024
buffer_size=2048
state=RUNNING
```

This excluded the ROM, ScummVM game engine, speaker, and kernel audio driver.
Changing only the libretro core to 44.1 kHz did not help. Matching both the core
and RetroArch output to 44.1 kHz also did not help while the CPU policy remained
`interactive`.

Setting the core frame-rate cap to 30 Hz made the fault worse. The core then
requested about 288 ms of minimum latency, and ALSA trigger times reset roughly
once per second. The 30 Hz cap is not part of the final configuration.

## Core Corrections

The required source patch is:

```text
docker/plumos-v90s-toolchain/patches/scummvm-libretro-audio-clock.patch
```

It makes two backend corrections:

- Submit every requested frame-sized audio buffer, including silence and the
  zero-filled tail already produced by `Audio::MixerImpl`.
- Preserve the fractional 58.917 Hz refresh value when calculating audio
  frames per video frame. Upstream cast it to integer `58`, which generated
  about 827.6 frames per call instead of the required 814.7 at 48 kHz.

The Docker core recipe treats the patch as required and fails if it no longer
applies cleanly.

## Runtime Fix

The frontend system definition uses `performance` as ScummVM's default CPU
policy. This is a governor selection, not a fixed-frequency setting. The V90S
then runs the available performance governor at 1.8 GHz while ScummVM is
active. Other systems keep their existing policies.

The launcher applies per-ROM audio driver and latency values through a
temporary RetroArch `--appendconfig` file under `/run/plumos-v90s`. It removes
the temporary file when RetroArch exits, so the persistent user config is not
rewritten for unrelated systems.

## Build

The official Docker entry point built only ScummVM:

```sh
./scripts/docker-build.sh cores \
  --filter scummvm \
  --out-dir output/libretro-cores/v90s-scummvm-audio-clock
```

Result:

```text
commit=660e13b0764fe2be39b6d723345ecabfbb318cc5
built=1
failed=0
skipped=113
sha256=4de4a1682ccac6e9a22361178db13c7ac87b16b2ca5be391c95889480fef88ed
```

## Physical V90S Validation

The core was copied through a `.new` path after a PID-validated RetroArch stop.
The deployed SHA-256 matched the Docker result.

Final validated settings and observations:

```text
cpu_governor=performance
cpu_frequency=1800000
core_fps=58.92
core_sample_rate=48000
alsa_format=S16_LE
alsa_channels=2
alsa_rate=48000
alsa_period_size=1920
alsa_buffer_size=7680
displayed_fps=58.91
audible_output=normal
```

The user confirmed normal audio and approximately 58.91 fps on the physical
V90S. A separate performance test at 44.1 kHz produced the same normal result,
so 48 kHz remains the final standard configuration.

After the PID-validated stop, the per-launch append file was absent, no
RetroArch process remained, and exactly one frontend process was restored. The
frontend reset the CPU policy to its normal `ondemand` baseline at 408 MHz.
