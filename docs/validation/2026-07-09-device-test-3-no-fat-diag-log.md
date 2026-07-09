# Device test 3: no FAT diagnostic log

Date: 2026-07-09

## Tested image

```text
output/images/plumos-v90s-armbian-step1-20260709-3-diag.img
sha256: d0c0c2caaf37f29d2011a550b83e4bef3bb846d0baa8482f262a306d74b4f001
```

## User-observed result

- V90S again showed only the KNULLI boot logo.
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
```

Files present on the FAT partition:

```text
boot/autoresize
boot/knulli
boot/knulli.board
bootlogo.bmp
knulli-boot.conf
lcd_compatible_index.txt
partitions/boot.img
partitions/boot0.img
partitions/boot_package.fex
partitions/env.img
partitions/genimage.cfg
```

## Extra file created on device

`lcd_compatible_index.txt` exists on the SD card but was not present in the generated image work tree.

Hex dump:

```text
00000000: 6c 63 64 30 00 00 00 00 00 00 63 62 21 00 00 00  lcd0......cb!...
```

`lcd_compatible_index.txt` appears in the KNULLI V90S boot package binaries:

```text
.cache/knulli-linux/package/boot/uboot-a133/powkiddy-v90s/boot_package/u-boot.bin
.cache/knulli-linux/board/allwinner/a133/powkiddy-v90s/partitions/boot_package.fex
```

This strongly suggests the A133 boot package/U-Boot code is running and can write to the FAT partition.

## Interpretation

No FAT diagnostic log means the diagnostic initramfs did not successfully persist logs to the FAT partition.

A later userdata ext4 inspection showed this was not a bootloader or initramfs selection failure. The diagnostic initramfs did run and persisted logs to userdata `/dev/mmcblk0p5`.

Because the boot package can write `lcd_compatible_index.txt` and userdata logs prove `/init` ran, the observed failure is inside the Linux initramfs path after the boot-resource partition is found.

## Follow-up userdata inspection

After sudo access was granted, the userdata partition was read from the SD card and inspected offline.

Source partition:

```text
/dev/rdisk4s5
```

Extracted image:

```text
output/device-logs/v90s-disk4s5-userdata-after-diag.img
sha256: 748e343f8d322dcb2a6ed333422693327e0b3a305b997327fccd31a3d13edb3a
```

Recovered diagnostic logs:

```text
/plumos-v90s-diag.log
/rootfs/plumos-v90s-diag.log
sha256: 769480194ab2a0fc122c76cd11c3d2958509c0a0943f9b1a3c9ad798706f95c4
```

The log copy stored for this repository is:

```text
docs/validation/logs/2026-07-09-plumos-v90s-diag-userdata.log
```

Key evidence from the recovered log:

- Linux kernel booted: `Linux version 4.9.191`
- diagnostic init started: `plumOS V90S diagnostic init started`
- real kernel cmdline included the generated image override: `root=/dev/mmcblk0p4`
- SD partitions were visible as `/dev/mmcblk0p1` through `/dev/mmcblk0p5`
- `/dev/mmcblk0p4` mounted as vfat and contained `/boot/knulli`
- `/dev/mmcblk0p5` mounted as ext4 for log persistence
- the failure point was `boot: failed to mount /boot_root/boot/knulli as squashfs`

The failure is consistent with trying to mount a squashfs image file directly from BusyBox initramfs without first attaching it to a loop device.

## Next direction

Serial UART is no longer the immediate next step because SD logging proved that the patched Android `boot.img` is active and initramfs is executing.

The next image should attach `/boot/knulli` to `/dev/loop0`, mount `/dev/loop0` as squashfs, and then switch to stage1.
