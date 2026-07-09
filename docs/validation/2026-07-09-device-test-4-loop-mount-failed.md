# Device test 4: loop-backed stage1 mount failed

Date: 2026-07-09

## Tested image

```text
output/images/plumos-v90s-armbian-step1-20260709-4-diag-loop.img
sha256: 6f6490c19f173fa538fa9e8e781cb94bb5b39bde38f16f0f9e98c2b78eba057c
```

## User-observed result

- V90S again stopped visually at the KNULLI boot logo.
- SD card was returned to the Mac for log inspection.

## FAT inspection

The FAT boot-resource partition mounted as:

```text
/Volumes/KNULLI
```

Expected diagnostic log files were not present:

```text
plumos-v90s-diag.log
boot/plumos-v90s-diag.log
rootfs/plumos-v90s-diag.log
```

## Userdata inspection

The userdata partition was read from the SD card and inspected offline.

Source partition:

```text
/dev/rdisk4s5
```

Extracted image:

```text
output/device-logs/v90s-disk4s5-userdata-after-diag-loop.img
sha256: 91f223f12a7968ff702f86af89f2a0fa8872fa2e80634fed5dd5491517cdad6a
```

Recovered diagnostic logs:

```text
/plumos-v90s-diag.log
/rootfs/plumos-v90s-diag.log
sha256: 7c00ff5d989bf19b6ac51d50d5bc85d7327563c0368290871048ad75305dd891
```

The log copy stored for this repository is:

```text
docs/validation/logs/2026-07-09-plumos-v90s-diag-userdata-loop.log
```

## Key evidence

The kernel and initramfs path still work:

```text
plumOS V90S diagnostic init started
console=ttyS0,115200 root=/dev/mmcblk0p4 ...
```

Supported filesystems include squashfs:

```text
ext4
squashfs
vfat
overlay
```

The SD card partitions were visible:

```text
mmcblk0p1
mmcblk0p2
mmcblk0p3
mmcblk0p4
mmcblk0p5
```

The diagnostic init found the FAT boot-resource partition and `/boot/knulli`:

```text
scan: mounted /dev/mmcblk0p4 as vfat
scan: found /boot/knulli on /dev/mmcblk0p4
boot: mounted /dev/mmcblk0p4 as vfat on /boot_root
```

The file exists on device with the expected size:

```text
/boot_root/boot/knulli
size: 3121152
```

The new failure point is:

```text
boot: failed to mount /dev/loop0 as squashfs
```

There was no preceding `failed to attach` message, so the explicit `losetup /dev/loop0 /boot_root/boot/knulli` command probably returned success. The mount of the loop block device failed afterward.

## Host comparison

The stage1 `/boot/knulli` file is a valid gzip squashfs on the host:

```text
Compression gzip
Filesystem size 3118954 bytes
sha256: ab4aeebb376243a4ad10930935050f43609a2bc4e0d7956f8c0f677657673d42
```

KNULLI's original initramfs does not explicitly run `losetup`. It mounts the rootfs file with the BusyBox mount applet directly:

```sh
mount ${REAL_ROOTFS} /overlay_root/base
```

Device test 4 used explicit `losetup` plus `mount -t squashfs /dev/loop0`, which is not exactly the KNULLI boot path.

## Interpretation

The boot chain is active and the Linux initramfs is running. The display staying at the logo is now caused by failing to mount the stage1 squashfs, not by missing kernel boot or missing SD partitions.

The next image should try the KNULLI-style direct file mount first, then fall back through explicit loop variants while logging loop device size, file magic, and post-failure `dmesg`.
