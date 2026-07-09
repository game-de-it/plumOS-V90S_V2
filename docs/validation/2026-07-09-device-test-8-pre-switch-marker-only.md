# Device test 8: pre-switch marker only

Date: 2026-07-09

## Tested image

```text
output/images/plumos-v90s-armbian-step1-20260709-8-stage1-sh-prepersist.img
sha256: f52ba13d4faacb41e4eb2a08715659a3a682350722cb89d27ffc53153605402f
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
output/device-logs/v90s-disk4s5-userdata-after-sh-prepersist.img
sha256: 58ebd93d26153bf4cb57c75bcc24177b79255644db6b0af4ce158b520f8c2392
```

Recovered diagnostic logs:

```text
/plumos-v90s-diag.log
/rootfs/plumos-v90s-diag.log
sha256: 9ad9ccb02b3e4f3e3273a35777e97e2acad9e8c107c35e76bd8ac3b53fb0bba5
```

The log copy stored for this repository is:

```text
docs/validation/logs/2026-07-09-plumos-v90s-diag-userdata-sh-prepersist.log
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

Diagnostic init still reached the stage1 root:

```text
boot: mounted /boot_root/boot/knulli with KNULLI-style file mount
boot: mounted /boot_root/boot/knulli as stage1 root
```

The stage1 root listing changed from the previous image, consistent with the rebuilt stage1 that includes `/bin/sh`:

```text
## ls -la /new_root
drwxr-xr-x    2        40 bin
```

The new pre-switch marker was persisted:

```text
boot: preparing to switch to stage1 /sbin/init
```

The marker appears after the diagnostic log had already mounted userdata:

```text
persist: mounted /dev/mmcblk0p5 as ext4
boot: preparing to switch to stage1 /sbin/init
persist: mounted /dev/mmcblk0p5 as ext4
```

`/dev/fb0` exists, but no framebuffer probe result was persisted:

```text
crw-------    1   29,   0 fb0
```

## Interpretation

The image definitely used the updated diagnostic ramdisk and reached the boundary immediately before `switch_root`. However, the returned userdata still had no stage1 log.

Because device test 8 only persisted before mount handoff and not after `boot: switching to stage1 /sbin/init`, this result does not yet distinguish these two cases:

- `switch_root` itself does not successfully enter stage1.
- stage1 starts but cannot mount/persist userdata on its own.

The next image should mount userdata from diagnostic init at `/new_root/mnt/share` before `switch_root`, then let stage1 use that pre-mounted share. It should also persist diagnostic logs to that same handoff mount immediately before `switch_root` and after a `switch_root` failure path.
