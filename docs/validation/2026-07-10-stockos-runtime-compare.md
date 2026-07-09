# StockOS Runtime Comparison

Date: 2026-07-10

## Goal

Use the user's modified StockOS-based SD image as a comparison target for the
current KNULLI-kernel plus Debian/Armbian-rootfs environment. The immediate
question is whether StockOS differs in the parts that affect RetroArch pacing:

- LCD/display interrupt cadence
- RetroArch sync and refresh settings
- RetroArch video/context driver route
- ALSA driver, device, buffer, and mixer state
- CPU governor/frequency behavior while RetroArch is running
- PowerVR userspace/kernel initialization

## Current Baseline

The current runtime snapshot was collected over SSH from:

```text
root@192.0.2.119
```

Output:

```text
output/device-logs/runtime-snapshots/current-plumos-knulli-armbian/snapshot.txt
output/device-logs/runtime-snapshots/current-plumos-knulli-armbian/SHA256SUMS
```

Snapshot hash:

```text
ee3648fdf7befc5a468fc8bd540d696897de5feb793ca43e90eb1044cc7fbe42
```

Important baseline signals:

```text
kernel: Linux 4.9.191 #17 SMP PREEMPT Tue May 13 18:14:09 UTC 2025
rootfs: Debian GNU/Linux 12 (bookworm)
modules: 8821cu, dc_sunxi, pvrsrvkm
display: fb0 U:640x480p-60, virtual 640x960, stride 2560
sound: card0 audiocodec, hw:0,0 playback
RetroArch process: /usr/local/bin/retroarch with QuickNES
RetroArch config: /mnt/share/retroarch/retroarch-v90s.cfg
current test setting: video_refresh_rate=59.25000, vrr_runloop_enable=false
```

## Collection Command

After booting the StockOS-based SD image and finding its IP address, collect the
same style of snapshot:

```text
scripts/v90s-collect-runtime-snapshot.sh root@<stockos-ip> stockos-modified
```

If the image uses a different SSH user, pass that user in the target:

```text
scripts/v90s-collect-runtime-snapshot.sh <user>@<stockos-ip> stockos-modified
```

The script is tolerant of missing paths and commands, so it can run against both
the current Debian rootfs and StockOS-like environments.

## Compare Command

Once both snapshots exist:

```text
diff -u \
  output/device-logs/runtime-snapshots/current-plumos-knulli-armbian/snapshot.txt \
  output/device-logs/runtime-snapshots/stockos-modified/snapshot.txt \
  > output/device-logs/runtime-snapshots/current-vs-stockos.diff
```

Focus first on these sections:

```text
cmdline
mounts
cpu
modules
interrupts-key
interrupt-rate-5s
display-sysfs
sound-devices
alsa-pcm-status
amixer
pvr-status
retroarch-version
retroarch-features
retroarch-configs
retroarch-logs
knulli-configs
```

## Notes

The StockOS image path has not been identified in the workspace yet. Searches in
the current repository and `~/Downloads` found many generated plumOS images, but
not an obvious StockOS-based image. Once the path is known, the image can either
be written manually by the user or written from this workspace using the same
SD-card flow used for earlier tests.

## StockOS RA-Running Snapshot

The user's modified StockOS image was booted and RetroArch was launched through
EmulationStation. The device was reachable at:

```text
root@192.0.2.120
```

The RA-running snapshot was collected with the updated script:

```text
scripts/v90s-collect-runtime-snapshot.sh root@192.0.2.120 stockos-modified-ra-running-3
```

Output:

```text
output/device-logs/runtime-snapshots/stockos-modified-ra-running-3/snapshot.txt
output/device-logs/runtime-snapshots/stockos-modified-ra-running-3/SHA256SUMS
output/device-logs/runtime-snapshots/current-vs-stockos-ra-running.diff
```

Snapshot hash:

```text
52ddd896670249378019669fd9082afa45a676854d3a73ca2d1ce2fbbcfe2e3d
```

The runtime command proves StockOS is not launching a bare RetroArch config. It
uses Batocera's launcher-generated config and shader handoff:

```text
/usr/bin/retroarch -L /usr/lib/libretro/quicknes_libretro.so \
  --config /userdata/system/configs/retroarch/retroarchcustom.cfg \
  --set-shader /usr/share/batocera/shaders/interpolation/sharp-bilinear-simple.glslp \
  --verbose /userdata/roms/nes/Super Mario Bros..nes
```

Generated RetroArch settings:

```text
audio_driver = "pulse"
audio_latency = 64
audio_out_rate = "48000"
audio_rate_control = "true"
audio_rate_control_delta = "0.005000"
input_driver = udev
input_joypad_driver = udev
video_driver = "gl"
video_refresh_rate = "58.917103"
video_shader_enable = true
video_threaded = true
vrr_runloop_enable = true
```

The display and PowerVR interrupt cadence while RA was running:

```text
sample_seconds=10.03
display_delta=592 display_hz=59.02293
pvr_delta=1184 pvr_hz=118.04586
```

The previous 30-second manual sample was close:

```text
display_delta=1775 display_hz=59.16667
pvr_delta=3527 pvr_hz=117.56667
pvr_per_display=1.98704
```

This supports the idea that the visible `59 fps` behavior is not necessarily a
CPU or emulator-core defect. The LCD cadence itself is around 59 Hz, and the
important question is whether RetroArch is paced to that cadence without
creating audio rate-control pressure.

Audio is different from the current plumOS image. StockOS does not let
RetroArch own ALSA directly:

```text
audio_driver = "pulse"
Server Name: PulseAudio (on PipeWire 1.2.7)
Default Sink: mono_output
mono_output PipeWire float32le 1ch 48000Hz RUNNING
application.name = "RetroArch"
/proc/asound/card0/pcm0p/sub0/status owner_pid: 685
```

The ALSA owner is PipeWire, not RetroArch. This is a major difference from the
current plumOS baseline, where RetroArch owns `hw:0,0` directly with
`audio_driver=alsathread`.

CPU and scheduling are also different:

```text
StockOS:  schedutil, current freq sampled at 1800000
plumOS:   ondemand, current freq sampled at 816000
StockOS:  irqbalance is running
```

## Current Interpretation

The StockOS comparison says the closed kernel and PowerVR stack are compatible
with the KNULLI-derived path, but the smooth RA result is a layered Batocera
runtime behavior rather than one magic RetroArch option.

The next plumOS tests should be layered in this order:

1. Apply only the StockOS generated RA timing profile:
   `58.917103 Hz`, `vrr_runloop_enable=true`, `video_threaded=true`,
   `audio_latency=64`.
2. If video pacing improves but audio differs, add a Pulse/PipeWire-compatible
   audio path instead of direct ALSA ownership.
3. If pacing still differs, test `schedutil` or a pinned performance governor
   together with `irqbalance`.
4. Keep Batocera configgen and evmapy as later reference material. They are
   useful, but importing them wholesale would obscure which layer actually fixes
   Step 2.
