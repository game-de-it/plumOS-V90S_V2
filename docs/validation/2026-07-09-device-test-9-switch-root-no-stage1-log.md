# Device test 9: switch_root boundary without stage1 log

Date: 2026-07-09

## Tested image

```text
output/images/plumos-v90s-armbian-step1-20260709-9-stage1-share-handoff.img
sha256: 049f684e0ba2b4a845282c79b16e79bef284c0c4e7f23122b8473bb941b58617
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
output/device-logs/v90s-disk4s5-userdata-after-share-handoff.img
sha256: 3e9ed28bb3736007f665c896a9a1e6c67447029b2074528ccbb6ef1b4306cd4f
```

Recovered diagnostic logs:

```text
/plumos-v90s-diag.log
/rootfs/plumos-v90s-diag.log
sha256: 9d5a1081b4f3693f24ba74ebc8fd9da5edff6cce13e0eb9bdca4cc123b353a68
```

The log copy stored for this repository is:

```text
docs/validation/logs/2026-07-09-plumos-v90s-diag-userdata-share-handoff.log
```

The expected stage1/Debian logs were still absent:

```text
/plumos-v90s-stage1.log
/rootfs/plumos-v90s-stage1.log
/plumos-v90s-debian-init.log
/rootfs/plumos-v90s-debian-init.log
```

The userdata image still contained the Debian payload:

```text
/rootfs/step1-rootfs.squashfs 43941888 bytes
sha256: 58704d22bd72960f2bf2d4224453366bf0257db810edddf158194c2b3adeef9e
compression: zstd
```

## Key evidence

The image definitely contained the rebuilt stage1 with `/bin/sh`:

```text
## ls -la /new_root/bin
lrwxrwxrwx    1         7 sh -> busybox
-rwxr-xr-x    1   1540088 busybox
```

Diagnostic init mounted userdata for stage1 handoff:

```text
stage1-share: mounted /dev/mmcblk0p5 as ext4 on /new_root/mnt/share
```

The diagnostic log was persisted through that handoff mount:

```text
persist_device=stage1-share
persist_path=/plumos-v90s-diag.log
```

The last stage before handoff was:

```text
boot: switching to stage1 /sbin/init
```

No `boot: switch_root failed` marker appeared. This strongly suggests `switch_root` did not return to the diagnostic script.

## Interpretation

Device test 9 reached the `switch_root` handoff and persisted through the handoff mount. Since `boot: switch_root failed` is absent, the diagnostic script probably exec'd into stage1.

The missing stage1 log is therefore likely inside the earliest stage1 init path. A strong issue was found in host inspection: stage1 and Debian init write logs under `/tmp`, but both rootfs images are squashfs, and `/tmp` was not mounted as tmpfs. The first `echo >> /tmp/plumos-v90s-stage1.log` would fail on the read-only squashfs root.

The next image should mount tmpfs on `/tmp` and `/run` in stage1 and Debian init before any log write, persist a marker before tty redirection, and add a diagnostic chroot preflight that proves `/bin/sh` can run inside the stage1 root and write to the handoff share.
