# Device test 11: Debian init reached and fb0 writes succeed

Date: 2026-07-09

## Tested image

```text
output/images/plumos-v90s-armbian-step1-20260709-11-direct-payload.img
sha256: 6644fb11cb4b8974a9d3bd9dcbe833d2cd1fb307066710fbe0138011cd06b7d7
```

## User-observed result

- V90S stayed visually at the KNULLI boot logo.
- No Linux console appeared on the internal display.
- SD card was returned to the Mac for log inspection.

## FAT inspection

The FAT boot-resource partition mounted as `/Volumes/KNULLI`.

No diagnostic, stage1, or Debian logs were present on FAT.

The FAT stage1 root matched the expected `-11` payload:

```text
/Volumes/KNULLI/boot/knulli
sha256: 316f279e1d192dfdd2efd75350ba0c1acd565b44b75b0a7ff0c307fa26d4776f
```

## Userdata inspection

The userdata partition was read from the SD card and inspected offline.

Source partition:

```text
/dev/rdisk4s5
```

Extracted image:

```text
output/device-logs/v90s-disk4s5-userdata-after-direct-payload.img
sha256: fe0d755295149df924737ccc2a4ee64315134afdcf8e44355ca83dafddf0f0ce
```

The root directory contained:

```text
/plumos-v90s-diag.log             39198 bytes
/plumos-v90s-debian-init.log        508 bytes
/rootfs/step1-rootfs.squashfs  43941888 bytes
/rootfs/plumos-v90s-diag.log
/rootfs/plumos-v90s-debian-init.log
```

Stage1 logs were absent, which is expected for this image because the direct payload route succeeded before stage1 fallback:

```text
/plumos-v90s-stage1.log
/rootfs/plumos-v90s-stage1.log
```

Recovered logs stored in this repository:

```text
docs/validation/logs/2026-07-09-plumos-v90s-diag-userdata-direct-payload.log
sha256: f8333fb7f4940d352fa0e5d78b7f9f62f396dc19ec9a13014279c553c01bb0d7

docs/validation/logs/2026-07-09-plumos-v90s-debian-init-direct-payload.log
sha256: 0bfad4b9d55636b41f1644ed66e2472df75d223dd68082078c7458a5eefb8cd1
```

The Debian payload was intact:

```text
/rootfs/step1-rootfs.squashfs
sha256: dccb0e4b95967b5b93521166befdf4edc50bb3e8c313a4ac34f043bb51ad400c
compression: zstd
```

## Key evidence

The diagnostic initramfs mounted userdata and mounted the Debian payload directly:

```text
payload-share: mounted /dev/mmcblk0p5 as ext4 on /payload_share
payload-root: attached payload to /dev/loop2
payload-root: mounted Debian payload rootfs
boot: switching directly to payload /sbin/init
```

The Debian init script started and persisted its log:

```text
debian-init: init entered before tty setup
plumOS V90S Step1 Debian minbase console
```

Debian init saw the V90S framebuffer:

```text
debian-init: fb0 probe begin
debian-init: name=
debian-init: modes=U:640x480p-60
debian-init: virtual_size=640,960
debian-init: bits_per_pixel=32
debian-init: stride=2560
```

The probe wrote successfully to `/dev/fb0`:

```text
debian-init: fb0 black probe wrote
debian-init: fb0 white band wrote
```

## Interpretation

Device test 11 proves the direct payload path works: the V90S boots the generated boot image, diagnostic initramfs mounts the userdata Debian rootfs, and Debian `/sbin/init` starts.

It also proves userland can open and write `/dev/fb0`. The remaining problem is not booting into Linux anymore; it is visible display output and interactive console rendering.

The previous framebuffer probe only wrote the first 4 KiB black and the first 32 KiB white. The V90S framebuffer reports `virtual_size=640,960`, which strongly suggests a 640x480 visible mode with two framebuffer pages. The short write may have missed the displayed page or may have been too small to notice over the boot logo.

The next image should write the full virtual framebuffer black, then write large white bands to both page 0 and page 1. If that still leaves the KNULLI logo visible while logs report successful writes, the display may be using a different plane or requiring an Allwinner display/pan operation before fb0 memory appears.
