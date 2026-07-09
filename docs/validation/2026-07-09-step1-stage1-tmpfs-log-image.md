# Step 1 stage1 tmpfs log image

Date: 2026-07-09

## Purpose

Device test 9 reached `boot: switching to stage1 /sbin/init` and did not show `switch_root failed`, but no stage1 log appeared.

This image fixes the earliest stage1/Debian log path by mounting tmpfs on `/tmp` and `/run` before writing logs. It also adds a diagnostic chroot preflight that runs `/bin/sh` inside the stage1 root and writes a marker to the userdata handoff mount.

## Image

```text
output/images/plumos-v90s-armbian-step1-20260709-10-stage1-tmpfs-log.img
sha256: 370c63fd8f9953703643fea737aff762ec2ca2cca9d657303c563484908c15af
size: 133M
```

The image keeps the compact iteration layout:

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
  --name plumos-v90s-armbian-step1-20260709-10-stage1-tmpfs-log.img \
  --userdata-size 64M \
  --boot-cmdline 'loglevel=8 ignore_loglevel initcall_debug=0 console=tty0 console=ttyS0,115200 rootwait root=/dev/mmcblk0p4 init=/sbin/init elevator=noop' \
  --diagnostic-init \
  --keep-work
```

## Payloads

```text
stage1-userdata-loader.squashfs:
  compression: zstd
  size: 2875392 bytes
  sha256: 055d78005fab725fd83efbe7f2db15d533159919fa8047fee6acd987429b5006

debian-bookworm-minbase-step1.squashfs:
  compression: zstd
  size: 43941888 bytes
  sha256: d9f2918f1e29234dce44eb70e89dea4a1a87943a1be1a09f86b6e65b5fff708a
```

## Host verification

`abootimg -i` confirmed the diagnostic cmdline:

```text
loglevel=8 ignore_loglevel initcall_debug=0 console=tty0 console=ttyS0,115200 rootwait root=/dev/mmcblk0p4 init=/sbin/init elevator=noop
```

The stage1 init now mounts tmpfs before writing its first log:

```text
mount -t tmpfs tmpfs /run
mount -t tmpfs tmpfs /tmp
stage1: init entered before tty setup
persist_stage1_log
```

The Debian init has the same early tmpfs log setup:

```text
mount -t tmpfs tmpfs /run
mount -t tmpfs tmpfs /tmp
debian-init: init entered before tty setup
persist_debian_log
```

The diagnostic ramdisk includes the chroot preflight:

```text
stage1-preflight: running /bin/sh inside stage1 root
stage1-preflight: chroot shell ok
```

If the preflight succeeds, the returned SD card should contain:

```text
plumos-v90s-stage1-preflight.log
```

If stage1 itself starts, the returned SD card should contain:

```text
plumos-v90s-stage1.log
rootfs/plumos-v90s-stage1.log
```

The userdata ext4 image contains the Debian payload and passes `e2fsck -fn`.
