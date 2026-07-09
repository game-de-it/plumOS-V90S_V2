# Device test 7: no stage1 log after framebuffer probe image

Date: 2026-07-09

## Tested image

```text
output/images/plumos-v90s-armbian-step1-20260709-7-stage1-fb-probe.img
sha256: 4f0b42cd1fbd74670af1f4780629eb3554fe34606f505be23f16bd0dd07a885c
```

## User-observed result

- V90S again stayed visually at the KNULLI boot logo.
- No Linux console appeared on the internal display.
- SD card was returned to the Mac for log inspection.

## FAT inspection

The FAT boot-resource partition mounted as:

```text
/Volumes/KNULLI
```

No diagnostic or stage1 logs were present on FAT.

## Userdata inspection

The userdata partition was read from the SD card and inspected offline.

Source partition:

```text
/dev/rdisk4s5
```

Extracted image:

```text
output/device-logs/v90s-disk4s5-userdata-after-fb-probe.img
sha256: 5b05fa9206e9e2a58b2666b867900deec822330ca1204fa89893e96b3246394c
```

Recovered diagnostic logs:

```text
/plumos-v90s-diag.log
/rootfs/plumos-v90s-diag.log
sha256: de4390c7e2e929ab75c31a39264a40d22d0ea58a5618d9f9caed2fbaab9a585a
```

The log copy stored for this repository is:

```text
docs/validation/logs/2026-07-09-plumos-v90s-diag-userdata-fb-probe.log
```

The expected stage1/Debian logs were absent:

```text
/plumos-v90s-stage1.log
/rootfs/plumos-v90s-stage1.log
/plumos-v90s-debian-init.log
/rootfs/plumos-v90s-debian-init.log
```

The userdata image still contained the Debian payload:

```text
/rootfs/step1-rootfs.squashfs 43941888 bytes
sha256: 36a6e1c3156cbc6e6761f92c5d7bad76f5807527f35cdd1c134e64b73f27cb20
compression: zstd
```

## Key evidence

Diagnostic init still reached the stage1 root:

```text
scan: found /boot/knulli on /dev/mmcblk0p4
boot: mounted /boot_root/boot/knulli with KNULLI-style file mount
boot: mounted /boot_root/boot/knulli as stage1 root
```

The diagnostic log listed the stage1 root:

```text
## ls -la /new_root
drwxr-xr-x    2        27 sbin
drwxr-xr-x    2        30 bin
```

`/dev/fb0` exists in the diagnostic `/dev` listing:

```text
crw-------    1   29,   0 fb0
```

USB HID and built-in input devices are still present in the kernel log:

```text
usbcore: registered new interface driver usbhid
usbhid: USB HID core driver
input: adc_gamepad
```

## Interpretation

This test did not prove that `/dev/fb0` writes hang, because host inspection found a more basic stage1 issue: the stage1 `/sbin/init` script uses `#!/bin/sh`, but the stage1 rootfs only contained `/bin/busybox` and no `/bin/sh` symlink.

That makes `switch_root /new_root /sbin/init` likely fail before stage1 can run or persist `plumos-v90s-stage1.log`.

The framebuffer probe also ran before the stage1 userdata log was persisted. The next image should:

- add `/bin/sh -> busybox` to stage1,
- persist a diagnostic marker immediately before `switch_root`,
- persist `plumos-v90s-stage1.log` before any framebuffer write,
- keep the framebuffer probe small enough that it does not block the boot path before evidence is saved.
