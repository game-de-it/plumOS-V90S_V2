# Device test 5: gzip squashfs mount probe failed

Date: 2026-07-09

## Tested image

```text
output/images/plumos-v90s-armbian-step1-20260709-5-diag-mount-probe.img
sha256: c4c600696276c550d3be36b0fa83b039221a462e796ad1ccb72ca1e6120e2089
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
output/device-logs/v90s-disk4s5-userdata-after-mount-probe.img
sha256: c467aa36cebb208dd6e7e5477164af473815fa1867b04c51ce63df87b33808cf
```

Recovered diagnostic logs:

```text
/plumos-v90s-diag.log
/rootfs/plumos-v90s-diag.log
sha256: e339559e478fd6fad2da17e5c864df7374e8092791a28321d2729f4eccefee29
```

The log copy stored for this repository is:

```text
docs/validation/logs/2026-07-09-plumos-v90s-diag-userdata-mount-probe.log
```

## Key evidence

The kernel and diagnostic initramfs path are still active:

```text
Linux version 4.9.191
plumOS V90S diagnostic init started
root=/dev/mmcblk0p4
```

The boot-resource partition was found and mounted:

```text
scan: mounted /dev/mmcblk0p4 as vfat
scan: found /boot/knulli on /dev/mmcblk0p4
boot: mounted /dev/mmcblk0p4 as vfat on /boot_root
```

The gzip stage1 squashfs file exists and loop attachment reads a valid squashfs superblock:

```text
/boot_root/boot/knulli size: 3121152
/dev/loop0 size: 6096 sectors
00000000  68 73 71 73 ... |hsqs|
```

All mount styles failed with `Invalid argument`:

```text
boot: trying KNULLI-style file mount
mount: mounting /dev/loop0 on /new_root failed: Invalid argument
boot: trying file mount with loop option
mount: mounting /dev/loop0 on /new_root failed: Invalid argument
boot: trying loop device mount with autodetect
mount: mounting /dev/loop0 on /new_root failed: Invalid argument
boot: trying loop device mount as squashfs
mount: mounting /dev/loop0 on /new_root failed: Invalid argument
```

The post-failure `dmesg` capture used `tail -120`, which BusyBox rejected. The next diagnostic image must use `tail -n 120`.

## Interpretation

The file is readable through both vfat and `/dev/loop0`, so this is no longer a missing-file or loop-attach issue. The kernel rejects the stage1 squashfs itself.

The tested stage1 image used gzip squashfs. The KNULLI a133 board configuration uses zstd rootfs squashfs:

```text
BR2_TARGET_ROOTFS_SQUASHFS4_ZSTD=y
```

The V90S kernel binary also contains zstd squashfs decompressor strings. The next image should test a zstd-compressed stage1 and zstd Debian payload, matching KNULLI's a133 default more closely.
