# V90S RetroArch Directory Layout Validation

Date: 2026-07-16

## Problem

The persistent V90S configuration began as a small plumOS cfg. After RetroArch
saved it on exit, unspecified directory values were expanded to defaults under
`~/.config/retroarch`. On V90S this resolves through `HOME=/root`, putting user
paths in the 128MB root overlay instead of the p7 `PLUMOS` app/data partition.

## Policy

The launcher now migrates only empty, `default`, `nul`, and legacy
`~/.config/retroarch` or `/root/.config/retroarch` values. Any other explicit
path selected by the user is preserved on later launches.

Persistent targets use:

```text
/mnt/plumos/config/retroarch
/mnt/plumos/config/shaders
/mnt/plumos/bios
/mnt/plumos/Saves
/mnt/plumos/States
/mnt/plumos/Screenshots
/mnt/plumos/Recordings
/mnt/plumos/Images/retroarch
/mnt/plumos/Logs/retroarch
```

The disposable RetroArch cache uses `/run/plumos/cache/retroarch`. System-owned
assets and databases remain under `/usr/share/libretro`.

## Build and Deployment

```text
frontend checksums.sha256:
7ef6d6abe4ba5293d628384ad5d01d561ad66664f384f95e4c9cc0725d1d8fc5

app-layer checksums.sha256:
106223aa1e85901f1fac1c022f94f8a7d6ba2f2cae34c24b73e6bf2e0b873b30

app-layer manifest.json:
819677e105fe6529205ecd2d2c0b7d2643b3c5503f214cb25314dbdc2c546a5d
```

The hardened ADB deploy transferred and verified the updated launcher, factory
cfg, and frontend manifest as one payload chunk while preserving ADB/SSH.

## Live Migration

The current user cfg was backed up to:

```text
/mnt/plumos/config/retroarch/retroarch-v90s.cfg.before-v90s-paths-20260716
```

Twenty-eight directory/path values were mapped to the V90S layout. A live grep
after migration found zero `~/.config/retroarch` or
`/root/.config/retroarch` references. p7 remained mounted read-write and
`dmesg` contained no matching FAT or MMC error.

RetroArch was then started in menu mode, stopped normally so
`config_save_on_exit` rewrote the cfg, and started again. The second launch
retained zero legacy root references and reported these representative values:

```text
cache_directory = "/run/plumos/cache/retroarch"
playlist_directory = "/mnt/plumos/config/retroarch/playlists"
screenshot_directory = "/mnt/plumos/Screenshots"
thumbnails_directory = "/mnt/plumos/Images/retroarch"
video_shader_dir = "/mnt/plumos/config/shaders"
```

The final live state was RetroArch menu running alone with no frontend process.
