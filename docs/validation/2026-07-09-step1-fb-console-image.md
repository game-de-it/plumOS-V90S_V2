# Step 1 framebuffer console image

Date: 2026-07-09

## Purpose

Device test 12 proved that `/dev/fb0` writes are visible on the V90S LCD. The kernel still has no framebuffer console, so this image adds a small userspace framebuffer console.

The console is implemented as:

```text
scripts/v90s-fb-console.pl
```

It is installed into the Debian payload as:

```text
/usr/local/sbin/v90s-fb-console
```

Debian init runs it after the fb0 probe:

```text
debian-init: starting framebuffer console
exec /usr/local/sbin/v90s-fb-console
```

## Behavior

The framebuffer console:

- draws text directly to `/dev/fb0`
- mirrors drawing to page 0 and page 1 when `virtual_size` is taller than the visible mode
- automatically prints `uname -a`, `ls /`, and `ls /dev/input`
- opens `/dev/input/event*`
- decodes basic USB keyboard key events
- runs entered commands through `/bin/sh`
- logs output to:

```text
/mnt/share/plumos-v90s-fb-console.log
/mnt/share/rootfs/plumos-v90s-fb-console.log
```

## Image

```text
output/images/plumos-v90s-armbian-step1-20260709-13-fb-console.img
sha256: e81b77a18d3530ab094be55896c69e48ba9647bc61c59efac7caa2a24d7d18b6
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
  --name plumos-v90s-armbian-step1-20260709-13-fb-console.img \
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
  sha256: 6e74bc431acc26e7ea1eb96ac533cf13f83a00f9a3d9f8bce6298b8095bbaa81

debian-bookworm-minbase-step1.squashfs:
  compression: zstd
  size: 43945984 bytes
  sha256: 56cc7e4a3700b60977b3fcde1a3b7301ed48ae4b0ddfd42731d0329d0638a721
```

## Host verification

`abootimg -i` confirmed the diagnostic cmdline:

```text
loglevel=8 ignore_loglevel initcall_debug=0 console=tty0 console=ttyS0,115200 rootwait root=/dev/mmcblk0p4 init=/sbin/init elevator=noop
```

The payload contains the framebuffer console and Debian init starts it:

```text
/usr/local/sbin/v90s-fb-console
debian-init: starting framebuffer console
exec /usr/local/sbin/v90s-fb-console
```

The completed image layout remains compact:

```text
partition 4 boot-resource: 67584 sectors
partition 5 userdata:      131072 sectors
```

The userdata partition extracted from the completed image passes `e2fsck -fn`, and its payload hash matches:

```text
/rootfs/step1-rootfs.squashfs
sha256: 56cc7e4a3700b60977b3fcde1a3b7301ed48ae4b0ddfd42731d0329d0638a721
```

## Expected device evidence

The LCD should show text instead of the white-band probe. It should include startup output similar to:

```text
plumOS V90S framebuffer console
$ uname -a
$ ls /
$ ls /dev/input
```

With a USB keyboard attached, typed characters should appear at the bottom prompt. Pressing Enter should run the command. The first target command is:

```sh
ls /
```

If text does not appear, the returned SD should still contain `plumos-v90s-debian-init.log`. If the console starts, it should additionally contain `plumos-v90s-fb-console.log`.
