# Step 1 diagnostic initramfs image

Date: 2026-07-09

## Purpose

Device tests `-1` and `-2` both reached the KNULLI boot logo but did not show a Linux console. Since visible console output is not reliable yet, build a diagnostic image that writes boot/initramfs evidence back to the SD card.

This is intended to answer the next question:

- Did the kernel reach initramfs `/init`?
- Which `/proc/cmdline` did the device actually use?
- Which mmc partitions were visible?
- Could initramfs mount the FAT boot-resource partition?
- Could it find `/boot/knulli`?

## Image

```text
output/images/plumos-v90s-armbian-step1-20260709-3-diag.img
sha256: d0c0c2caaf37f29d2011a550b83e4bef3bb846d0baa8482f262a306d74b4f001
size: 133M
```

The image keeps the same small partition sizing:

- FAT boot-resource: 33MB
- userdata ext4: 64MB

## Build command

```sh
./scripts/run-assembly-tools.sh ./scripts/assemble-v90s-image.sh \
  --rootfs output/rootfs-step1/stage1-userdata-loader.squashfs \
  --userdata-payload output/rootfs-step1/debian-bookworm-minbase-step1.squashfs \
  --out-dir output/images \
  --name plumos-v90s-armbian-step1-20260709-3-diag.img \
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
plumOS V90S diagnostic init started
plumos-v90s-diag.log
boot: switching to stage1 /sbin/init
```

The finished image was also checked:

- raw GPT boot partition contains the patched Android `boot.img`
- FAT `/partitions/boot.img` also contains the patched Android `boot.img`
- FAT `/boot/knulli` contains the stage1 squashfs
- userdata `/rootfs/step1-rootfs.squashfs` contains the Debian minbase payload

## How to test

1. Flash `output/images/plumos-v90s-armbian-step1-20260709-3-diag.img`.
2. Boot it on the V90S.
3. Wait at least 60 seconds, even if the screen stays on the KNULLI boot logo.
4. Power off the V90S.
5. Put the SD card back into the host.
6. Check the FAT boot-resource partition for:

```text
plumos-v90s-diag.log
boot/plumos-v90s-diag.log
```

If the ext4 userdata partition is mounted on a Linux host, also check:

```text
rootfs/plumos-v90s-diag.log
```

## Interpretation

If `plumos-v90s-diag.log` exists:

- kernel reached initramfs
- the diagnostic init ran
- analyze `/proc/cmdline`, `/proc/partitions`, mount attempts, and whether `/boot/knulli` was found

If no log exists anywhere:

- the kernel may not be reaching initramfs
- the bootloader may be loading another `boot.img`
- mmc partitions may not be visible by the time initramfs runs
- serial UART logging becomes the most reliable next option

## Serial note

Serial UART is the strongest logging route if SD logging does not appear. It would require locating V90S UART pads and using a 3.3V USB-TTL adapter at the likely boot console rate of 115200 bps. This is more invasive than SD logging, so the diagnostic image should be tried first.
