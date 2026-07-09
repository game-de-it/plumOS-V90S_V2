# Step 1 direct payload image

Date: 2026-07-09

## Purpose

Device test 10 proved that stage1 can mount the Debian payload, but the second root handoff from stage1 to Debian did not produce Debian init logs.

This image adds a direct path in the diagnostic initramfs:

1. Mount the userdata partition.
2. Attach `/rootfs/step1-rootfs.squashfs` to `/dev/loop2`.
3. Mount it at `/payload_root`.
4. Move `/proc`, `/sys`, `/dev`, `/boot_root`, and the userdata share into the payload root.
5. `switch_root` directly from initramfs to `/payload_root/sbin/init`.

Stage1 remains in `/boot/knulli` as a fallback if the direct payload route cannot be prepared.

The image also changes stage1 and Debian init so they preserve an already-populated `/dev` and create `/dev/fb0` with `mknod c 29 0` when sysfs exposes `fb0` but the device node is missing.

## Image

```text
output/images/plumos-v90s-armbian-step1-20260709-11-direct-payload.img
sha256: 6644fb11cb4b8974a9d3bd9dcbe833d2cd1fb307066710fbe0138011cd06b7d7
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
  --name plumos-v90s-armbian-step1-20260709-11-direct-payload.img \
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
  sha256: 316f279e1d192dfdd2efd75350ba0c1acd565b44b75b0a7ff0c307fa26d4776f

debian-bookworm-minbase-step1.squashfs:
  compression: zstd
  size: 43941888 bytes
  sha256: dccb0e4b95967b5b93521166befdf4edc50bb3e8c313a4ac34f043bb51ad400c
```

## Host verification

`abootimg -i` confirmed the diagnostic cmdline:

```text
loglevel=8 ignore_loglevel initcall_debug=0 console=tty0 console=ttyS0,115200 rootwait root=/dev/mmcblk0p4 init=/sbin/init elevator=noop
```

The diagnostic ramdisk includes the direct payload route:

```text
payload-share: mounted
payload-root: attached payload to /dev/loop2
payload-root: mounted Debian payload rootfs
boot: switching directly to payload /sbin/init
```

The stage1 and Debian init scripts include `/dev/fb0` repair:

```text
mknod /dev/fb0 c 29 0
```

The completed image layout remains compact:

```text
partition 4 boot-resource: 67584 sectors
partition 5 userdata:      131072 sectors
```

The userdata partition extracted from the completed image passes `e2fsck -fn`, and its payload hash matches:

```text
/rootfs/step1-rootfs.squashfs
sha256: dccb0e4b95967b5b93521166befdf4edc50bb3e8c313a4ac34f043bb51ad400c
```

## Expected device evidence

If the direct route reaches Debian init, userdata should contain:

```text
plumos-v90s-debian-init.log
rootfs/plumos-v90s-debian-init.log
```

If direct payload preparation fails before handoff, the diagnostic log should contain:

```text
boot: direct payload root unavailable; falling back to stage1
```

If stage1 fallback runs, userdata may also contain:

```text
plumos-v90s-stage1.log
rootfs/plumos-v90s-stage1.log
```
