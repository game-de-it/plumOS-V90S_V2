# Step 1 stage1 shell and pre-persist image

Date: 2026-07-09

## Purpose

Device test 7 reached the stage1 squashfs root but produced no stage1 log. Host inspection showed the stage1 rootfs lacked `/bin/sh`, even though `/sbin/init` is a shell script with `#!/bin/sh`.

This image adds `/bin/sh -> busybox`, persists a diagnostic marker immediately before `switch_root`, and moves stage1/Debian log persistence before framebuffer writes.

## Image

```text
output/images/plumos-v90s-armbian-step1-20260709-8-stage1-sh-prepersist.img
sha256: f52ba13d4faacb41e4eb2a08715659a3a682350722cb89d27ffc53153605402f
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
  --name plumos-v90s-armbian-step1-20260709-8-stage1-sh-prepersist.img \
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
  sha256: 82e5c48e7d0876cf8b96aa28323199bc1723adf3cba1048d31ab2e3179eef818

debian-bookworm-minbase-step1.squashfs:
  compression: zstd
  size: 43941888 bytes
  sha256: 58704d22bd72960f2bf2d4224453366bf0257db810edddf158194c2b3adeef9e
```

## Host verification

`abootimg -i` confirmed the diagnostic cmdline:

```text
loglevel=8 ignore_loglevel initcall_debug=0 console=tty0 console=ttyS0,115200 rootwait root=/dev/mmcblk0p4 init=/sbin/init elevator=noop
```

The stage1 rootfs now contains the shell interpreter required by `/sbin/init`:

```text
/bin/busybox
/bin/sh -> busybox
```

The stage1 init persists logs before framebuffer probing:

```text
stage1: found payload on $dev
persist_stage1_log
fb_probe
persist_stage1_log
```

The framebuffer black probe was reduced from a full 1200KiB clear to a 4KiB write:

```text
dd if=/dev/zero of=/dev/fb0 bs=4096 count=1
```

The diagnostic ramdisk persists a switch marker before moving mounts:

```text
boot: preparing to switch to stage1 /sbin/init
persist_logs
```

GPT layout remains compact:

```text
partition 4 boot-resource: 67584 sectors
partition 5 userdata:      131072 sectors
```

The userdata ext4 image contains the Debian payload and passes `e2fsck -fn`.

## Expected device behavior

If `switch_root` now starts stage1, the returned SD card should contain:

```text
plumos-v90s-stage1.log
rootfs/plumos-v90s-stage1.log
```

If stage1 reaches the Debian payload, the returned SD card may also contain:

```text
plumos-v90s-debian-init.log
rootfs/plumos-v90s-debian-init.log
```

If no stage1 log appears, the diagnostic log should at least include the pre-switch marker, narrowing the remaining failure to `switch_root` itself or `/sbin/init` execution.
