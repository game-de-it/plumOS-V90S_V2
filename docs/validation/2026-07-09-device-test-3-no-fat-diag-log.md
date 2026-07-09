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

Current possibilities:

- kernel did not reach initramfs `/init`
- bootloader is not loading the patched Android `boot.img`
- kernel/initramfs started but could not enumerate or mount the SD partitions
- diagnostic init failed before `persist_logs`

Because the boot package can write `lcd_compatible_index.txt`, the problem is probably after early boot/display setup but before, or very early inside, the Linux initramfs path.

## Not yet inspected

The userdata ext4 partition was not inspected on macOS during this pass because reading `/dev/rdisk4s5` requires an interactive `sudo` Terminal command. The diagnostic init writes FAT first when possible, so the lack of FAT log is already a strong negative signal, but ext4 inspection remains a possible follow-up.

## Next direction

The next most useful evidence is serial UART boot logging. If staying SD-only, the next image should test whether the bootloader is actually loading the patched `boot.img`, for example by changing only one boot source at a time or by creating a deliberately obvious boot-image failure/probe.
