# Step 1 diagnostic zstd image

Date: 2026-07-09

## Purpose

Device test 5 showed that the gzip stage1 squashfs was readable and loop-attached, but every squashfs mount attempt failed with `Invalid argument`.

KNULLI's a133 board configuration uses zstd-compressed rootfs squashfs:

```text
BR2_TARGET_ROOTFS_SQUASHFS4_ZSTD=y
```

This image rebuilds both Step 1 squashfs payloads with zstd compression while keeping the same diagnostic mount probes. It also fixes the post-failure dmesg capture from `tail -120` to `tail -n 120`.

## Image

```text
output/images/plumos-v90s-armbian-step1-20260709-6-diag-zstd.img
sha256: 21ebb95f828bd4fd293ac53ba213480628f7c2761871937037c558f7acb623ea
size: 133M
```

The image keeps the same compact partition sizing:

- FAT boot-resource: 33MB
- userdata ext4: 64MB

## Build command

```sh
./scripts/run-assembly-tools.sh ./scripts/build-step1-rootfs.sh \
  --out-dir output/rootfs-step1

./scripts/run-assembly-tools.sh ./scripts/assemble-v90s-image.sh \
  --rootfs output/rootfs-step1/stage1-userdata-loader.squashfs \
  --userdata-payload output/rootfs-step1/debian-bookworm-minbase-step1.squashfs \
  --out-dir output/images \
  --name plumos-v90s-armbian-step1-20260709-6-diag-zstd.img \
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

The diagnostic ramdisk was extracted and checked. Its `/init` contains:

```text
boot: trying KNULLI-style file mount
boot: trying file mount with loop option
boot: trying explicit losetup on /dev/loop0
dmesg | tail -n 120
boot: failed to mount /boot_root/boot/knulli as stage1 root
```

Squashfs payloads:

```text
stage1-userdata-loader.squashfs:
  compression: zstd
  size: 2.7M
  sha256: ee7730474e43f8e9fcda5486c73888a707c5b9c1b47b802166c3201bdd6bb799

debian-bookworm-minbase-step1.squashfs:
  compression: zstd
  size: 42M
  sha256: c1ecd25e75b9b0da6cdb2b0a53fde33140b0885598f4b50e02e7cd479e2013b1
```

GPT layout remains compact:

```text
partition 4 boot-resource: 67584 sectors
partition 5 userdata:      131072 sectors
```

## Expected device behavior

If zstd squashfs matches the V90S/KNULLI kernel path, the screen may advance into stage1 or the Debian minbase console:

```text
plumOS V90S stage1: looking for userdata rootfs payload
plumOS V90S Step1 Debian minbase console
```

If the display still stays at the boot logo, return the SD card to the host and inspect FAT/userdata logs. The corrected dmesg tail should now show the exact squashfs kernel rejection reason.
