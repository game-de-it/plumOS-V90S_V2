# V90S SD2 content layer live validation

Date: 2026-07-11

## Device observation

The user inserted a FAT32 SD2 card while the device was running.

SD1 remained the app layer:

```text
/dev/mmcblk0p7 -> /mnt/plumos
```

SD2 appeared as:

```text
/dev/mmcblk1
/dev/mmcblk1p1
```

`blkid` identified the SD2 partition as:

```text
/dev/mmcblk1p1: LABEL="GAME" UUID="EED6-67C0" TYPE="vfat"
```

The runtime exposed filesystem support for:

```text
ext4
vfat
exfat
```

## FAT fsck

Before mounting, `fsck.fat -n -v /dev/mmcblk1p1` found FAT inconsistencies:

```text
/FSCK0359.REC
  File size is 32768 bytes, cluster chain length is 16384 bytes.
/.Spotlight-V100/.../0.indexPostings shared clusters.
/ROMS/odcommander/images/od-commander.png shared clusters.
Free cluster summary wrong.
```

Then `fsck.fat -a -w /dev/mmcblk1p1` repaired the filesystem. A follow-up
read-only check returned clean:

```text
fsck_verify_rc=0
```

## Manual mount test

SD2 was mounted as:

```text
/dev/mmcblk1p1 -> /run/plumos/sd2
```

Then the SD2 content directories were bind-mounted as:

```text
/run/plumos/sd2/roms -> /mnt/plumos/roms
/run/plumos/sd2/bios -> /mnt/plumos/bios
```

The SD2 root preserved mixed or upper-case names from older systems, but vfat
lookup made lowercase paths usable:

```text
/run/plumos/sd2/roms
/run/plumos/sd2/bios
```

## Helper implementation

Added:

```text
/mnt/plumos/bin/plumos-sd2-content-mount start|status|stop|restart
```

Build output hashes:

```text
dd5d6a487f0342d92f628f6951b7103f9e4956007126086b9f8738399a051f72  output/app-layer/v90s/bin/plumos-sd2-content-mount
a4c98d907c6f1a17d05df607cda72b683075c46f82fb2e0f38479ad4ed50f89f  output/app-layer/v90s/bin/plumos-frontend-launch
2c26e0bd5a17222cfff0e048f1805b0bd17f921a7f140ba82429ba49f76a794d  output/app-layer/v90s/manifest.json
e8e3300aeea06ddc4da37033d7c6209b0c43dd6f9eebae19d4fea338643e07ec  output/app-layer/v90s/checksums.sha256
```

Live deployment hashes:

```text
dd5d6a487f0342d92f628f6951b7103f9e4956007126086b9f8738399a051f72  /mnt/plumos/bin/plumos-sd2-content-mount
a4c98d907c6f1a17d05df607cda72b683075c46f82fb2e0f38479ad4ed50f89f  /mnt/plumos/bin/plumos-frontend-launch
```

The live helper reported:

```text
/dev/mmcblk1p1 /run/plumos/sd2 vfat rw,...
/dev/mmcblk1p1 /mnt/plumos/roms vfat rw,...
/dev/mmcblk1p1 /mnt/plumos/bios vfat rw,...
```

## Scanner validation

With SD2 bind-mounted, NES scan used the existing single root contract:

```text
PLUMOS_ROOT=/mnt/plumos PLUMOS_SDCARD_ROOT=/mnt/plumos \
  /mnt/plumos/bin/plumos-library-scan --system nes --defer-thumbnails
```

Result:

```text
system nes                roms=86 thumbnails=0
summary alias_dirs=2 files_seen=95 matched=86 roms=86 thumbnails=0
wrote: /mnt/plumos/state/frontend/systems/nes.json
```

## Remaining validation

- Reboot with SD2 inserted and confirm `/mnt/plumos/bin/plumos-frontend-launch`
  automatically runs `plumos-sd2-content-mount start`.
- Confirm FE Refresh TOP shows SD2 systems/ROM counts without manual SSH mount
  commands.
