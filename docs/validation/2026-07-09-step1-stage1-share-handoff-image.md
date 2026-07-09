# Step 1 stage1 share handoff image

Date: 2026-07-09

## Purpose

Device test 8 reached the diagnostic pre-`switch_root` marker, but no stage1 log appeared in userdata.

This image mounts the userdata payload partition in diagnostic init at `/new_root/mnt/share` before `switch_root`, so stage1 can immediately use the already-mounted share and persist `plumos-v90s-stage1.log` before doing any framebuffer work.

## Image

```text
output/images/plumos-v90s-armbian-step1-20260709-9-stage1-share-handoff.img
sha256: 049f684e0ba2b4a845282c79b16e79bef284c0c4e7f23122b8473bb941b58617
size: 133M
```

The image keeps the compact iteration layout:

- FAT boot-resource: 33MB
- userdata ext4: 64MB

## Build command

```sh
./scripts/run-assembly-tools.sh ./scripts/build-step1-rootfs.sh \
  --profile stage1 \
  --out-dir output/rootfs-step1

./scripts/run-assembly-tools.sh ./scripts/assemble-v90s-image.sh \
  --rootfs output/rootfs-step1/stage1-userdata-loader.squashfs \
  --userdata-payload output/rootfs-step1/debian-bookworm-minbase-step1.squashfs \
  --out-dir output/images \
  --name plumos-v90s-armbian-step1-20260709-9-stage1-share-handoff.img \
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
  sha256: b4eac7d084bc1a66a411a353737c1b9211f75f2127619265ef84228a9a7030a9

debian-bookworm-minbase-step1.squashfs:
  compression: zstd
  size: 43941888 bytes
  sha256: 58704d22bd72960f2bf2d4224453366bf0257db810edddf158194c2b3adeef9e
```

## Host verification

`abootimg -i` confirmed the diagnostic cmdline:

```text
loglevel=8 ignore_loglevel initcall_debug=0 console=tty0 console=ttyS0,115200 rootwait root=/dev/mmcblk0p4 init=/sbin/init elevator=noop
```

The stage1 rootfs still contains the shell interpreter required by `/sbin/init`:

```text
/bin/busybox
/bin/sh -> busybox
```

The stage1 init now handles the diagnostic handoff mount first:

```text
stage1: using pre-mounted payload on /mnt/share
persist_stage1_log
fb_probe
persist_stage1_log
```

The diagnostic ramdisk now includes userdata handoff and extra persistence:

```text
stage1-share: scanning writable SD partitions
stage1-share: mounted $dev as $fs on /new_root/mnt/share
boot: switching to stage1 /sbin/init
persist_logs_to_stage1_share
boot: switch_root failed
persist_logs_to_stage1_share
```

The diagnostic ramdisk also lists `/new_root/bin` and `/new_root/sbin` before switching, so the returned diagnostic log can confirm the on-device stage1 `/bin/sh` symlink.

GPT layout remains compact:

```text
partition 4 boot-resource: 67584 sectors
partition 5 userdata:      131072 sectors
```

The userdata ext4 image contains the Debian payload and passes `e2fsck -fn`.

## Expected device behavior

If diagnostic init can mount userdata for handoff, the returned diagnostic log should include:

```text
stage1-share: mounted /dev/mmcblk0p5 as ext4 on /new_root/mnt/share
boot: switching to stage1 /sbin/init
```

If stage1 starts, the returned SD card should contain:

```text
plumos-v90s-stage1.log
rootfs/plumos-v90s-stage1.log
```

If `switch_root` fails, the returned diagnostic log should include:

```text
boot: switch_root failed
```
