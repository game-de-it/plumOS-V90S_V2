# Step 1 framebuffer text and FAT logs image

Date: 2026-07-09

## Purpose

Device test 14 proved that the framebuffer console receives USB keyboard input and runs commands, but text was not visible. This image fixes font initialization and exports logs to the FAT boot-resource partition so the Mac can read logs without sudo/ext4 extraction.

## Image

```text
output/images/plumos-v90s-armbian-step1-20260709-15-fb-text-fat-logs.img
sha256: f26b6391af990a7b4637054d5558d3794fd50250674fb3b9ec68ed94e1d52f24
size: 133M
```

The image keeps the compact iteration layout:

- FAT boot-resource: 33MB
- userdata ext4: 64MB

## Changes

- Initialize `%FONT` in a `BEGIN` block before the main framebuffer console loop.
- Increase framebuffer text scale from 2 to 3.
- Prepare `/boot/plumos-logs` on the FAT boot-resource partition.
- Copy Debian init logs to FAT.
- Write framebuffer console logs directly to FAT as well as userdata.

On macOS, expected logs after boot:

```text
/Volumes/KNULLI/plumos-logs/session.txt
/Volumes/KNULLI/plumos-logs/plumos-v90s-diag.log
/Volumes/KNULLI/plumos-logs/plumos-v90s-debian-init.log
/Volumes/KNULLI/plumos-logs/plumos-v90s-fb-console.log
```

## Build command

```sh
./scripts/run-assembly-tools.sh ./scripts/build-step1-rootfs.sh \
  --out-dir output/rootfs-step1

./scripts/run-assembly-tools.sh ./scripts/assemble-v90s-image.sh \
  --rootfs output/rootfs-step1/stage1-userdata-loader.squashfs \
  --userdata-payload output/rootfs-step1/debian-bookworm-minbase-step1.squashfs \
  --out-dir output/images \
  --name plumos-v90s-armbian-step1-20260709-15-fb-text-fat-logs.img \
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
  sha256: d5f3a5a4328a9517fdbe480d5bfbcbdce46dab2b0acc4cb3996fa5bd1da0fabc

debian-bookworm-minbase-step1.squashfs:
  compression: zstd
  size: 43945984 bytes
  sha256: 827e5929bc1a0ed92527c3aa945bac8c0538ca9a51f55ec3ee7a1aa947512838
```

## Host verification

The completed image layout remains compact:

```text
partition 4 boot-resource: 67584 sectors
partition 5 userdata:      131072 sectors
```

The userdata partition extracted from the completed image passes `e2fsck -fn`, and its payload hash matches:

```text
/rootfs/step1-rootfs.squashfs
sha256: 827e5929bc1a0ed92527c3aa945bac8c0538ca9a51f55ec3ee7a1aa947512838
```

## Expected device evidence

The LCD should show framebuffer text. The startup output should include:

```text
plumOS V90S framebuffer console
$ uname -a
$ ls /
$ ls /dev/input
```

Typing `ls /` and pressing Enter should show command output. After returning the SD card to macOS, logs should be readable from `/Volumes/KNULLI/plumos-logs/` without a password prompt.
