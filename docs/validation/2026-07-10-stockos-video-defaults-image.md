# StockOS RetroArch Video Defaults Image

Date: 2026-07-10

## Purpose

Apply the video timing settings observed in the modified StockOS/Batocera
RetroArch launch configuration to the plumOS V90S RetroArch path.

The source reference is:

```text
output/vendor/stockos-runtime/root/userdata/system/configs/retroarch/retroarchcustom.cfg
```

Relevant StockOS values:

```text
video_threaded = true
video_refresh_rate = "58.917103"
vrr_runloop_enable = true
threaded_data_runloop_enable = "true"
```

## Live Device Status

The V90S answered at `192.0.2.120` and was running
`plumOS V90S Step2 RetroArch Debian payload`. The live device was updated over
SSH with the same launcher, route, and RetroArch config values documented here,
then RetroArch was restarted.

User-observed result after the live update:

```text
fps, scrolling, and audio pitch are perfect.
```

The full live success snapshot is recorded in:

```text
docs/validation/2026-07-10-step2-stockos-video-perfect-runtime.md
```

## Build

Repacked rootfs:

```text
output/rootfs-step2-retroarch-knulli-stockos-video/debian-bookworm-retroarch-knulli-step2.squashfs
sha256: 345af89b81aa04894414354b632a90be4b5d71fcf13df72dc1abce160c82da11
```

SD image:

```text
output/images/plumos-v90s-stockos-ra-20260710-2-stockos-video.img
size: 662M
sha256: 609ecafc95bb84283aa627c5c48fe4a5a469a6617f97b16eff9ddabf74d24596
```

## Verified In p5

`/etc/plumos-v90s-retroarch-route` contains:

```text
PLUMOS_V90S_VIDEO_DRIVER=gl
PLUMOS_V90S_VIDEO_CONTEXT_DRIVER=mali_fbdev
PLUMOS_V90S_VIDEO_THREADED=true
PLUMOS_V90S_VIDEO_REFRESH_RATE=58.917103
PLUMOS_V90S_VRR_RUNLOOP_ENABLE=true
```

`/usr/local/sbin/v90s-retroarch-launch` now writes:

```text
video_refresh_rate = "58.917103"
video_threaded = "true"
threaded_data_runloop_enable = "true"
vrr_runloop_enable = "true"
```

`mali_fbdev` is intentionally kept because it is the current plumOS/KNULLI
display route. StockOS used an empty `video_context_driver`, but that exact
setting is not assumed to be portable to the current runtime.

## Next Test

Clean-boot `plumos-v90s-stockos-ra-20260710-2-stockos-video.img` from SD and
confirm it reproduces the live-patched success without SSH-side edits.
