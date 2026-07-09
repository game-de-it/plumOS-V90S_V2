# Device test 1: KNULLI logo only

Date: 2026-07-09

## Tested image

```text
output/images/plumos-v90s-armbian-step1-20260709-1.img
sha256: d5ee904e669a5b0d292815cf2700f176f93bcb88b8f11d7946737ae1b94e850b
```

## User-observed result

- V90S displays the KNULLI boot logo image.
- No Linux console was observed.
- No USB keyboard command test was possible yet.

## Confirmed by this result

- The SD image is recognized by the early V90S boot path.
- Early boot/display initialization reaches the point where the KNULLI boot logo can be shown.
- The issue is after, or at the transition from, the early boot logo path to kernel/ramdisk/rootfs console.

## Likely cause

The Android `boot.img` used in `-1` had this cmdline:

```text
loglevel=0 initcall_debug=0 console=tty0 console=ttyS0,115200 rootwait root=/dev/mmcblk0p1 init=/sbin/init
```

In the generated GPT image, partition 1 is the raw Android `boot.img` partition, while the FAT boot-resource partition containing `/boot/knulli` is partition 4:

```text
   start    size  index  contents
   41984   31744      1  GPT part - boot.img
   74240   67584      4  GPT part - FAT boot-resource
```

The extracted KNULLI ramdisk `init` reads `root=` from `/proc/cmdline`, mounts that device at `/boot_root`, and then expects:

```text
/boot_root/boot/knulli
```

If `root=/dev/mmcblk0p1` is used on this GPT layout, the ramdisk is likely trying to mount the Android boot image partition instead of the FAT boot-resource partition. That would prevent stage1 from being reached and leave only the boot logo visible.

This remains an inference until the real `/proc/cmdline` or serial output is available.

## Next image

Build a second image with the same rootfs payload but a patched Android boot image cmdline:

```text
output/images/plumos-v90s-armbian-step1-20260709-2.img
sha256: 3e1434f9abf653df7d8bf43dbabcc55134a1e4f9c84ca99f13bdda2ecc3ac490
```

Patched cmdline:

```text
loglevel=8 initcall_debug=0 console=tty0 console=ttyS0,115200 rootwait root=/dev/mmcblk0p4 init=/sbin/init elevator=noop
```

Host verification confirmed that both the raw GPT boot partition and the FAT copy at `/partitions/boot.img` contain the patched cmdline.

Expected next visible milestones:

```text
plumOS V90S stage1: looking for userdata rootfs payload
plumOS V90S Step1 Debian minbase console
```

If `-2` still shows only the logo, the next likely targets are bootloader cmdline override, `/dev/console` routing, or kernel framebuffer console behavior.
