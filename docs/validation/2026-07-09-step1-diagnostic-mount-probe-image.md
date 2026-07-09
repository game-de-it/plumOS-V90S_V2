# Step 1 diagnostic mount-probe image

Date: 2026-07-09

## Purpose

Device test 4 showed that explicit `losetup /dev/loop0 /boot_root/boot/knulli` did not produce an attach failure, but mounting `/dev/loop0` as squashfs failed afterward.

KNULLI's original V90S initramfs mounts the rootfs image file directly with BusyBox mount:

```sh
mount ${REAL_ROOTFS} /overlay_root/base
```

This image follows that KNULLI-style mount path first. If it fails, diagnostic init then tries `-o loop`, explicit `losetup`, loop autodetect mount, and explicit squashfs mount while recording extra evidence.

## Image

```text
output/images/plumos-v90s-armbian-step1-20260709-5-diag-mount-probe.img
sha256: c4c600696276c550d3be36b0fa83b039221a462e796ad1ccb72ca1e6120e2089
size: 133M
```

The image keeps the same compact partition sizing:

- FAT boot-resource: 33MB
- userdata ext4: 64MB

## Build command

```sh
./scripts/run-assembly-tools.sh ./scripts/assemble-v90s-image.sh \
  --rootfs output/rootfs-step1/stage1-userdata-loader.squashfs \
  --userdata-payload output/rootfs-step1/debian-bookworm-minbase-step1.squashfs \
  --out-dir output/images \
  --name plumos-v90s-armbian-step1-20260709-5-diag-mount-probe.img \
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
boot: trying loop device mount with autodetect
boot: trying loop device mount as squashfs
boot: failed to mount /boot_root/boot/knulli as stage1 root
```

Both squashfs payloads now use gzip compression:

```text
stage1-userdata-loader.squashfs:
  compression: gzip
  sha256: ab4aeebb376243a4ad10930935050f43609a2bc4e0d7956f8c0f677657673d42

debian-bookworm-minbase-step1.squashfs:
  compression: gzip
  sha256: d94c08bd3b331eee0503c0cba9da04f26e5a030d9c9f4cd0471536f57eab411b
  size: 45M
```

GPT layout remains compact:

```text
partition 4 boot-resource: 67584 sectors
partition 5 userdata:      131072 sectors
```

## Expected device behavior

If KNULLI-style direct file mount works, the screen may advance into either stage1 text or the Debian minbase console:

```text
plumOS V90S stage1: looking for userdata rootfs payload
plumOS V90S Step1 Debian minbase console
```

If the display still stays at the boot logo, return the SD card to the host and inspect FAT/userdata logs. The new log should show which mount attempt failed and include loop size, first bytes of the image, and the post-failure kernel messages.
