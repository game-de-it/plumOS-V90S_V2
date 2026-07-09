# Device test 12: fb0 full probe is visible

Date: 2026-07-09

## Tested image

```text
output/images/plumos-v90s-armbian-step1-20260709-12-fb-full-probe.img
sha256: c2345d8daf6bed5644ebd786b11952797139a901b3b7236a29cd824d9064b3e2
```

## User-observed result

- The KNULLI boot logo disappeared.
- The LCD showed a black screen with a white band near the top.
- This matches the framebuffer full-probe pattern.
- SD card was returned to the Mac for log inspection.

Photo:

```text
/Users/example/Downloads/IMG_4348.jpg
```

## FAT inspection

The FAT boot-resource partition mounted as `/Volumes/KNULLI`.

No diagnostic, stage1, or Debian logs were present on FAT.

The FAT stage1 root matched the expected `-12` payload:

```text
/Volumes/KNULLI/boot/knulli
sha256: 4546df08d5a2b56f835096d5f430e035d7c56ac862fe9ba6542373bac8a4da62
```

## Userdata inspection

The userdata partition was read from the SD card and inspected offline.

Source partition:

```text
/dev/rdisk4s5
```

Extracted image:

```text
output/device-logs/v90s-disk4s5-userdata-after-fb-full-probe.img
sha256: 097999c56ed7d4da84ee0f4a54c5541fee8f5bc697d0ebba5a8d03ebfe0e7ccc
```

The root directory contained:

```text
/plumos-v90s-diag.log             37829 bytes
/plumos-v90s-debian-init.log        734 bytes
/rootfs/step1-rootfs.squashfs  43941888 bytes
/rootfs/plumos-v90s-diag.log
/rootfs/plumos-v90s-debian-init.log
```

Recovered logs stored in this repository:

```text
docs/validation/logs/2026-07-09-plumos-v90s-diag-userdata-fb-full-probe.log
sha256: 89697b43cb943ed46e989d1107a60df3a556840c6c925774bac0d5b4a830d734

docs/validation/logs/2026-07-09-plumos-v90s-debian-init-fb-full-probe.log
sha256: 66474a72cc0e8d10892128cd51c4a6aeaf6f008b68ea3cd91b56fb42f28f5ef0
```

The Debian payload was intact:

```text
/rootfs/step1-rootfs.squashfs
sha256: 2b85f6c827ff067e606a232bfd5b796a6b6dce44f04a7013fb7c4308ef9bc120
compression: zstd
```

## Key evidence

The direct payload route still worked:

```text
payload-share: mounted /dev/mmcblk0p5 as ext4 on /payload_share
payload-root: attached payload to /dev/loop2
payload-root: mounted Debian payload rootfs
boot: switching directly to payload /sbin/init
```

Debian init reached fb0 and wrote the full probe:

```text
debian-init: modes=U:640x480p-60
debian-init: virtual_size=640,960
debian-init: bits_per_pixel=32
debian-init: stride=2560
debian-init: fb0 unblank requested
debian-init: fb0 full black wrote blocks=600 bytes=2457600
debian-init: fb0 white band page0 wrote
debian-init: fb0 white band page1 wrote seek_blocks=300
```

The diagnostic dmesg also shows input and HID support is present in the kernel:

```text
usbcore: registered new interface driver usbhid
usbhid: USB HID core driver
input: sunxi-keyboard
input: axp2202-pek
input: sunxi-gpadc0
input: adc_gamepad
```

## Interpretation

Device test 12 proves that userland writes to `/dev/fb0` are visible on the V90S LCD. The boot-logo-only problem is cleared: Linux and Debian are booting, and framebuffer output can replace the boot logo.

The remaining Step 1 work is to provide a usable console without relying on kernel framebuffer console support. The next image should start a small userspace framebuffer console from Debian init, draw text directly to fb0, open `/dev/input/event*`, and run typed commands through `/bin/sh`.
