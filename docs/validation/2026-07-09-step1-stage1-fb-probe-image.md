# Step 1 stage1 framebuffer probe image

Date: 2026-07-09

## Purpose

Device test 6 proved that the zstd stage1 squashfs mounts successfully, but the internal display still remains on the KNULLI boot logo.

The V90S/KNULLI kernel config has no framebuffer console, so this image adds stage1 and Debian init logs that persist to userdata, writes a small direct `/dev/fb0` white-band probe, and moves the Debian payload loop device from `/dev/loop0` to `/dev/loop1`.

## Image

```text
output/images/plumos-v90s-armbian-step1-20260709-7-stage1-fb-probe.img
sha256: 4f0b42cd1fbd74670af1f4780629eb3554fe34606f505be23f16bd0dd07a885c
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
  --name plumos-v90s-armbian-step1-20260709-7-stage1-fb-probe.img \
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
  sha256: d3a8ac80776bfaac8a36f9e1e51d95a3f7214eed461b16731e45b47908f46a78

debian-bookworm-minbase-step1.squashfs:
  compression: zstd
  size: 43941888 bytes
  sha256: 36a6e1c3156cbc6e6761f92c5d7bad76f5807527f35cdd1c134e64b73f27cb20
```

## Host verification

`abootimg -i` confirmed the diagnostic cmdline:

```text
loglevel=8 ignore_loglevel initcall_debug=0 console=tty0 console=ttyS0,115200 rootwait root=/dev/mmcblk0p4 init=/sbin/init elevator=noop
```

The stage1 init contains:

```text
LOG=/tmp/plumos-v90s-stage1.log
stage1: fb0 probe begin
payload_loop=/dev/loop1
plumos-v90s-stage1.log
```

The Debian init contains:

```text
LOG=/tmp/plumos-v90s-debian-init.log
debian-init: fb0 probe begin
plumOS V90S Step1 Debian minbase console
```

The diagnostic ramdisk still uses the BusyBox-compatible dmesg tail:

```text
dmesg | tail -n 120
```

GPT layout remains compact:

```text
partition 4 boot-resource: 67584 sectors
partition 5 userdata:      131072 sectors
```

The userdata ext4 image contains the Debian payload:

```text
/rootfs/step1-rootfs.squashfs 43941888 bytes
```

`e2fsck -fn` reports the extracted userdata partition as clean.

## Expected device behavior

If stage1 runs, the returned SD card should contain one or more of:

```text
plumos-v90s-stage1.log
rootfs/plumos-v90s-stage1.log
plumos-v90s-debian-init.log
rootfs/plumos-v90s-debian-init.log
```

If `/dev/fb0` accepts userspace writes, the screen may briefly change from the KNULLI boot logo to a cleared screen or a white band even without framebuffer console support.
