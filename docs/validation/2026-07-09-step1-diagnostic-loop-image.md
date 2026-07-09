# Step 1 diagnostic loop-mount image

Date: 2026-07-09

## Purpose

Device test 3 proved that the V90S boots the generated Android `boot.img`, reaches the diagnostic initramfs, sees the SD partitions, and finds `/boot/knulli` on the FAT boot-resource partition.

The recovered userdata log also showed that initramfs failed when it tried to mount the `/boot/knulli` squashfs image file directly:

```text
boot: failed to mount /boot_root/boot/knulli as squashfs
```

This image changes diagnostic init to attach that squashfs file to `/dev/loop0` first, then mount `/dev/loop0` as squashfs before switching to stage1.

## Image

```text
output/images/plumos-v90s-armbian-step1-20260709-4-diag-loop.img
sha256: 6f6490c19f173fa538fa9e8e781cb94bb5b39bde38f16f0f9e98c2b78eba057c
size: 133M
```

The image keeps the same small partition sizing:

- FAT boot-resource: 33MB
- userdata ext4: 64MB

## Build command

```sh
./scripts/run-assembly-tools.sh ./scripts/assemble-v90s-image.sh \
  --rootfs output/rootfs-step1/stage1-userdata-loader.squashfs \
  --userdata-payload output/rootfs-step1/debian-bookworm-minbase-step1.squashfs \
  --out-dir output/images \
  --name plumos-v90s-armbian-step1-20260709-4-diag-loop.img \
  --userdata-size 64M \
  --boot-cmdline 'loglevel=8 ignore_loglevel initcall_debug=0 console=tty0 console=ttyS0,115200 rootwait root=/dev/mmcblk0p4 init=/sbin/init elevator=noop' \
  --diagnostic-init \
  --keep-work
```

## Host verification

`abootimg -i` confirmed the generated `boot.img` uses the diagnostic cmdline:

```text
loglevel=8 ignore_loglevel initcall_debug=0 console=tty0 console=ttyS0,115200 rootwait root=/dev/mmcblk0p4 init=/sbin/init elevator=noop
```

The diagnostic ramdisk was extracted and checked. Its `/init` now contains the loop-device path:

```text
losetup /dev/loop0 /boot_root/boot/knulli
mount -t squashfs -o ro /dev/loop0 /new_root
boot: switching to stage1 /sbin/init
```

GPT layout remains compact:

```text
partition 4 boot-resource: 67584 sectors
partition 5 userdata:      131072 sectors
```

## Expected device behavior

The best outcome is that the screen advances from the KNULLI boot logo into either stage1 text or the Debian minbase console:

```text
plumOS V90S stage1: looking for userdata rootfs payload
plumOS V90S Step1 Debian minbase console
```

If the display still does not advance, return the SD card to the host and inspect FAT/userdata diagnostic logs. A new log should identify whether the loop mount succeeded and whether `switch_root` reached stage1.
