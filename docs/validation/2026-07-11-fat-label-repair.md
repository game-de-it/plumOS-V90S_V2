# V90S FAT app layer repair and volume labels

Date: 2026-07-11

## Context

After a hung FE power action, the user had to press the V90S hardware reset
button. On the next boot the kernel remounted p7 read-only:

```text
/dev/mmcblk0p7 /mnt/plumos vfat ro,...,errors=remount-ro
```

The SD card was connected to macOS for repair and label cleanup.

## macOS Device

The SD card appeared as:

```text
/dev/disk4
```

Initial visible FAT labels:

```text
disk4s1  Volumn  FAT16  boot-resource
disk4s7  SHARE   FAT32  plumOS app layer
```

## p7 Repair

macOS repair command:

```sh
diskutil repairVolume disk4s7
```

Repair output showed FAT damage consistent with the reset-button recovery:

```text
Warning: /STATE/FRONTEND/recent.json starts with cross-linked cluster
Warning: /STATE/FRONTEND/resume-session.json starts with cross-linked cluster
Warning: Found orphan cluster(s)
***** FILE SYSTEM WAS MODIFIED *****
```

The modified files are FE state/recent-session files, not the RetroArch runtime
config.

Post-repair verification:

```text
diskutil verifyVolume disk4s7
File system check exit code is 0
```

## Labels

The user-visible FAT labels were changed to:

```text
disk4s1  PLUMBOOT
disk4s7  PLUMOS
```

macOS remounts FAT labels in uppercase, so the stable label names are recorded
as `PLUMBOOT` and `PLUMOS`.

Current mount points:

```text
/dev/disk4s1 on /Volumes/PLUMBOOT
/dev/disk4s7 on /Volumes/PLUMOS
```

Both volumes verified cleanly:

```text
diskutil verifyVolume disk4s1
File system check exit code is 0

diskutil verifyVolume disk4s7
File system check exit code is 0
```

## Power Helper Deployment

The sysrq-direct `plumos-safe-shutdown` helper from commit `8cd7cfc` was copied
to p7 after repair:

```text
1c34c9670e782bd2f586402bbe97a4c1ba167e13c1d72f980d35b178da09adf4  /Volumes/PLUMOS/bin/plumos-safe-shutdown
1c34c9670e782bd2f586402bbe97a4c1ba167e13c1d72f980d35b178da09adf4  output/app-layer/v90s/bin/plumos-safe-shutdown
bin/plumos-safe-shutdown: OK
```

The RetroArch user config was present and was not overwritten:

```text
/Volumes/PLUMOS/config/retroarch/retroarch-v90s.cfg
```

## Source Update

The StockOS-compatible image assembler now uses the new user-visible labels:

```text
p1 boot-resource / PLUMBOOT
p7 rootfs_data / PLUMOS FAT32
```

The partition roles and numbering remain StockOS-compatible; only the FAT volume
labels changed.

## Live Boot Check After Repair

The repaired SD card booted on the V90S and SSH returned at:

```text
root@192.0.2.120
```

Runtime labels are visible from the device:

```text
/dev/mmcblk0p1: LABEL="PLUMBOOT" TYPE="vfat"
/dev/mmcblk0p7: LABEL="PLUMOS" TYPE="vfat"
/dev/mmcblk1p1: LABEL="GAME" TYPE="vfat"
```

p7 is mounted read-write and accepts writes:

```text
/dev/mmcblk0p7 /mnt/plumos vfat rw,...,errors=remount-ro 0 0
p7_write_ok
```

The sysrq-direct power helper is active:

```text
1c34c9670e782bd2f586402bbe97a4c1ba167e13c1d72f980d35b178da09adf4  /mnt/plumos/bin/plumos-safe-shutdown
bin/plumos-safe-shutdown: OK
```

The RetroArch user config is present and writable on p7:

```text
e565ea5dfa3c57639c9a306722851124471fa2a281920b7578ee607562966151  /mnt/plumos/config/retroarch/retroarch-v90s.cfg
config_save_on_exit = "true"
video_driver = "gl"
video_context_driver = "mali_fbdev"
video_refresh_rate = "58.917103"
video_threaded = "true"
vrr_runloop_enable = "true"
audio_driver = "alsa"
audio_device = "hw:0,0"
audio_latency = "64"
```

Network services are all running:

```text
ssh    running
ftp    running
sftp   running
samba  running
```

SD2 is mounted and bind-mounted onto the plumOS content roots:

```text
/dev/mmcblk1p1 /run/plumos/sd2 vfat rw,...
/dev/mmcblk1p1 /mnt/plumos/roms vfat rw,...
/dev/mmcblk1p1 /mnt/plumos/bios vfat rw,...
```

Remaining caveat:

```text
FAT-fs (mmcblk0p7): Volume was not properly unmounted. Some data may be corrupt. Please run fsck.
```

The filesystem did not remount read-only this time and the write probe passed,
so the live state is usable. However, the warning means the power-action path
should be improved further: before the final sysrq reboot/poweroff, plumOS
should stop app-layer writers and remount or otherwise cleanly quiesce p7 so
the FAT dirty bit is not left set.
