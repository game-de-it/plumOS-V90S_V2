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
