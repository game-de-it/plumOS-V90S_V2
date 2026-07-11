# V90S FAT32 check after game launch and FE reboot

## Scenario

User booted the freshly generated image, launched a game from FE, exited/rebooted
through the frontend Reboot action, and left the device running for inspection.

Device:

```text
ssh root@192.0.2.120
password: linux
```

## Observed State

System was reachable over SSH after reboot:

```text
Linux (none) 4.9.191 #17 SMP PREEMPT Tue May 13 18:14:09 UTC 2025 aarch64 GNU/Linux
/dev/mmcblk0p7 /mnt/plumos vfat rw,...,errors=remount-ro 0 0
p7_write_test=ok
```

p7 `PLUMOS` did not report the previous dirty FAT warning:

```text
FAT-fs (mmcblk0p7): Volume was not properly unmounted.
```

The only FAT dirty warning in the inspected boot was from SD2:

```text
FAT-fs (mmcblk1p1): Volume was not properly unmounted. Some data may be corrupt. Please run fsck.
```

Current mounts:

```text
/dev/mmcblk0p7 /mnt/plumos vfat rw,...,errors=remount-ro 0 0
/dev/mmcblk1p1 /run/plumos/sd2 vfat rw,...,errors=remount-ro 0 0
/dev/mmcblk1p1 /mnt/plumos/roms vfat rw,...,errors=remount-ro 0 0
/dev/mmcblk1p1 /mnt/plumos/bios vfat rw,...,errors=remount-ro 0 0
```

Rootfs-owned power action was present and the app-layer wrapper was the expected
delegating wrapper:

```text
-rwxr-xr-x /usr/sbin/plumos-power-action
-rwxr-xr-x /mnt/plumos/bin/plumos-safe-shutdown
5d84bfa00f163969cbfb41c366b0a9585ab1418fd3aba5b6b37d5944bb69f937  /usr/sbin/plumos-power-action
9e93421a0a92edc0aaebdda281eaa7d949615d083470799dc04dfbf0af3ee83e  /mnt/plumos/bin/plumos-safe-shutdown
```

Previous reboot log showed SD2 bind mounts were stopped before reboot:

```text
sd2: stopping content mounts
umount: done target=/mnt/plumos/bios
umount: done target=/mnt/plumos/roms
umount: done target=/run/plumos/sd2
```

## Interpretation

The rootfs-owned final power path appears to have fixed the p7 dirty warning for
this test path. The remaining FAT warning is specific to SD2 and likely reflects
either an already-dirty SD2 card or the frontend launch path mounting SD2 with
boot fsck disabled.

At the time of inspection, the frontend log showed:

```text
plumos-frontend-launch: SD2 mount sync fsck=off
```

## Follow-up Implemented

- Re-enabled SD2 FAT fsck by default in `plumos-frontend-launch`.
- Added a bounded `PLUMOS_SD2_FSCK_TIMEOUT` to `plumos-sd2-content-mount` so a
  bad SD2 cannot block startup indefinitely.
- Added `dosfstools` to the rootfs payload.
- Added rootfs init mount-before-fsck protection for p7 `PLUMOS` before the
  first writable app-layer mount.

## Follow-up Build

Rebuilt artifacts:

```text
3838569fa67fc56b6ad747c5e39e553ef64a73e48146cc20971e250b76e03c47  output/images/plumos-v90s-appfat-1g-fatguard-20260711-1.img
8f9027299a069b38d1cbf8785b2fbd7b0f5339763648fb7fd796108b974b658d  output/rootfs-step2-appfat/debian-bookworm-retroarch-knulli-step2.squashfs
4e8e77e52ce477837310f60b4df74956bd3a8913394df80b74b2a4207661b6e8  output/app-layer/v90s/bin/plumos-sd2-content-mount
f698dc520c4148773c9989752e6f1fa45ed53ae5f03f72f97bb86cdae81e3a91  output/app-layer/v90s/bin/plumos-frontend-launch
be7dc159c88ae872b5a797a15523dd734b17dc0914cd521855312236e428174b  output/app-layer/v90s/manifest.json
8d8b2719a4004710125e9300dcd2c39abc17bf012bcfcb5b437bc9db09a91a13  output/app-layer/v90s/checksums.sha256
```

Rootfs inspection:

```text
lrwxrwxrwx root/root     8 ... squashfs-root/usr/sbin/dosfsck -> fsck.fat
-rwxr-xr-x root/root 80040 ... squashfs-root/usr/sbin/fsck.fat
-rwxr-xr-x root/root 13282 ... squashfs-root/usr/sbin/init
```

Init inspection confirmed:

```text
fsck_fat_app_layer_if_needed()
debian-init: fsck running dev=$dev tool=$fsck_bin timeout=${timeout_sec}s
debian-init: app layer fsck failed dev=$dev; skipping rw mount
```

App-layer inspection confirmed:

```text
PLUMOS_SD2_FSCK="${PLUMOS_SD2_BOOT_FSCK:-auto}"
FSCK_TIMEOUT="${PLUMOS_SD2_FSCK_TIMEOUT:-15}"
fsck: running $fsck_bin -a $dev timeout=${FSCK_TIMEOUT}s
```

## Next Validation

Build a new image, boot with SD2 inserted, then confirm dmesg contains no dirty
FAT warning for either:

```text
mmcblk0p7
mmcblk1p1
```
