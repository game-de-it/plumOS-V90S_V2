# Step 1 framebuffer full-probe image

Date: 2026-07-09

## Purpose

Device test 11 reached Debian init and successfully wrote to `/dev/fb0`, but the user still saw the KNULLI boot logo.

This image makes the framebuffer probe visually obvious:

1. Request fb0 unblank when `/sys/class/graphics/fb0/blank` is writable.
2. Read `virtual_size`, `bits_per_pixel`, and `stride`.
3. Write black across the full virtual framebuffer.
4. Write a 128 KiB white band to page 0.
5. If `virtual_size` is taller than the visible mode, write the same white band to page 1 as well.

For the observed V90S mode, this should write black across `640x960x32bpp` and white bands at both page offsets.

## Image

```text
output/images/plumos-v90s-armbian-step1-20260709-12-fb-full-probe.img
sha256: c2345d8daf6bed5644ebd786b11952797139a901b3b7236a29cd824d9064b3e2
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
  --name plumos-v90s-armbian-step1-20260709-12-fb-full-probe.img \
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
  sha256: 4546df08d5a2b56f835096d5f430e035d7c56ac862fe9ba6542373bac8a4da62

debian-bookworm-minbase-step1.squashfs:
  compression: zstd
  size: 43941888 bytes
  sha256: 2b85f6c827ff067e606a232bfd5b796a6b6dce44f04a7013fb7c4308ef9bc120
```

## Host verification

`abootimg -i` confirmed the diagnostic cmdline:

```text
loglevel=8 ignore_loglevel initcall_debug=0 console=tty0 console=ttyS0,115200 rootwait root=/dev/mmcblk0p4 init=/sbin/init elevator=noop
```

The diagnostic ramdisk still includes the direct payload route:

```text
payload-root: attached payload to /dev/loop2
payload-root: mounted Debian payload rootfs
boot: switching directly to payload /sbin/init
```

The Debian init includes the full framebuffer probe:

```text
debian-init: fb0 unblank requested
debian-init: fb0 full black wrote blocks=
debian-init: fb0 white band page0 wrote
debian-init: fb0 white band page1 wrote seek_blocks=
```

The completed image layout remains compact:

```text
partition 4 boot-resource: 67584 sectors
partition 5 userdata:      131072 sectors
```

The userdata partition extracted from the completed image passes `e2fsck -fn`, and its payload hash matches:

```text
/rootfs/step1-rootfs.squashfs
sha256: 2b85f6c827ff067e606a232bfd5b796a6b6dce44f04a7013fb7c4308ef9bc120
```

## Expected device evidence

If fb0 is the visible scanout buffer, the KNULLI logo should be replaced by a mostly black screen with a white band.

If the screen still shows the KNULLI logo, userdata should still contain:

```text
plumos-v90s-debian-init.log
rootfs/plumos-v90s-debian-init.log
```

The Debian log should show whether the full-buffer and page 1 writes succeeded.
