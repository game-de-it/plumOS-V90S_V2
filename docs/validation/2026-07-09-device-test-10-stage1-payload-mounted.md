# Device test 10: stage1 mounted payload rootfs

Date: 2026-07-09

## Tested image

```text
output/images/plumos-v90s-armbian-step1-20260709-10-stage1-tmpfs-log.img
sha256: 370c63fd8f9953703643fea737aff762ec2ca2cca9d657303c563484908c15af
```

## User-observed result

- V90S stayed visually at the KNULLI boot logo.
- No Linux console appeared on the internal display.
- SD card was returned to the Mac for log inspection.

## FAT inspection

The FAT boot-resource partition mounted as `/Volumes/KNULLI`.

No diagnostic, stage1, or Debian logs were present on FAT.

The FAT stage1 root matched the expected `-10` payload:

```text
/Volumes/KNULLI/boot/knulli
sha256: 055d78005fab725fd83efbe7f2db15d533159919fa8047fee6acd987429b5006
```

## Userdata inspection

The userdata partition was read from the SD card and inspected offline.

Source partition:

```text
/dev/rdisk4s5
```

Extracted image:

```text
output/device-logs/v90s-disk4s5-userdata-after-tmpfs-log.img
sha256: 57f3a4131581329ae402c9aa1ccd75d4e33d0f55a1565daa11c0851b2141e442
```

The root directory contained:

```text
/plumos-v90s-diag.log        35500 bytes
/plumos-v90s-stage1.log        377 bytes
/rootfs/step1-rootfs.squashfs 43941888 bytes
/rootfs/plumos-v90s-diag.log
/rootfs/plumos-v90s-stage1.log
```

Recovered logs stored in this repository:

```text
docs/validation/logs/2026-07-09-plumos-v90s-diag-userdata-tmpfs-log.log
sha256: dafb63025ff7b4fad41f626b9e34a8b7db12d6201c4fd67973b583104e3f25d0

docs/validation/logs/2026-07-09-plumos-v90s-stage1-userdata-tmpfs-log.log
sha256: 9f8b7e7681d6b1e6daca6a024b8a1d38f6c693772a2a246e58e22a32fff21f98
```

The Debian payload was still intact:

```text
/rootfs/step1-rootfs.squashfs
sha256: d9f2918f1e29234dce44eb70e89dea4a1a87943a1be1a09f86b6e65b5fff708a
compression: zstd
```

No Debian init logs were present:

```text
/plumos-v90s-debian-init.log
/rootfs/plumos-v90s-debian-init.log
```

## Key evidence

The diagnostic preflight attempted to chroot into stage1, but the KNULLI busybox does not provide that applet:

```text
stage1-preflight: running /bin/sh inside stage1 root
chroot: applet not found
stage1-preflight: chroot shell failed
```

This did not block the real handoff. Stage1 itself entered and persisted its log:

```text
stage1: init entered before tty setup
plumOS V90S stage1: looking for userdata rootfs payload
stage1: using pre-mounted payload on /mnt/share
```

Stage1 saw framebuffer sysfs information, but `/dev/fb0` was no longer present after its `/dev` setup:

```text
stage1: fb0 probe begin
stage1: =
stage1: =U:640x480p-60
stage1: =640,960
stage1: =32
stage1: =2560
stage1: /dev/fb0 not present
```

Most importantly, stage1 successfully attached and mounted the Debian payload:

```text
stage1: attached payload to /dev/loop1
stage1: mounted payload rootfs
stage1: switching to payload rootfs
```

## Interpretation

Device test 10 proves that diagnostic initramfs can enter stage1, and stage1 can use the pre-mounted userdata share, attach the Debian squashfs payload, and mount it as the next root.

The remaining boot block is after `stage1: switching to payload rootfs`. No Debian init log was persisted. A likely cause is the second `switch_root`: the first handoff from initramfs to stage1 works, but stage1 is already running from a mounted squashfs root. BusyBox `switch_root` is intended for leaving initramfs/rootfs, so using it again from the stage1 squashfs root is a bad fit. Also, because the stage1 script used `exec switch_root`, a `switch_root` applet failure after exec would not return to the shell code that logs `stage1: switch_root failed`.

The next image should avoid this two-step root switch. Diagnostic initramfs should mount the userdata Debian payload directly and `switch_root` into it once, using stage1 only as a fallback. The next image should also preserve the moved `/dev` tree and create `/dev/fb0` with `mknod` if sysfs shows fb0 but the node is absent.
