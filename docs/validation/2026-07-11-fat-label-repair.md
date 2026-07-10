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
