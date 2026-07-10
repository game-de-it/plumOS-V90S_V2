# V90S rootfs-owned power action for FAT32 safety

## Goal

Reduce the chance of p7 `PLUMOS` FAT32 corruption or dirty-bit warnings during
FE Reboot/Shutdown.

The previous helper lived entirely under `/mnt/plumos`. It could stop writers
and remount p7 read-only, but the next boot still reported:

```text
FAT-fs (mmcblk0p7): Volume was not properly unmounted. Some data may be corrupt. Please run fsck.
```

## Implementation

Added a rootfs-owned final-stage helper:

```text
/usr/sbin/plumos-power-action
```

The helper is installed into system-rootfs builds from:

```text
scripts/plumos-power-action-rootfs.sh
```

The app-layer compatibility entry point remains:

```text
/mnt/plumos/bin/plumos-safe-shutdown
```

When the rootfs helper exists, `plumos-safe-shutdown` delegates Reboot/Shutdown
to it. Final Reboot/Shutdown is started detached so the frontend shell
redirection to `/mnt/plumos/Logs/frontend-power-action.log` is closed before the
rootfs helper tries to unmount p7.

The rootfs helper uses only rootfs commands in `PATH`, logs to `/run`, stops
SD2 bind mounts, stops known app-layer writers, syncs, attempts to unmount
`/mnt/plumos`, unmounts `/boot` when it is a writable FAT boot-resource mount,
and then triggers sysrq reboot or poweroff.

SSH/dropbear diagnostic sessions are deliberately not matched by process name.
If an SSH shell itself keeps `/mnt/plumos` busy, the helper logs blockers and
falls back to a read-only remount after a second unmount attempt.

## Local Checks

Syntax:

```text
sh -n scripts/plumos-power-action-rootfs.sh
sh -n package/frontend-v90s/plumos/bin/plumos-safe-shutdown
sh -n scripts/build-step1-rootfs.sh
```

Rootfs helper dry-run:

```text
result=dry_run_reboot
```

App-layer wrapper dry-run delegation:

```text
result=dry_run_poweroff
delegate rootfs_helper=... args=--dry-run --shutdown --poweroff --wait-sec 0
```

Detached final-action scheduling test on host:

```text
result=power_action_scheduled
quiesce: begin root=...
sd2: stopping content mounts
quiesce: no app-layer writers found
sysrq: unavailable action=reboot
```

The final line is expected on the macOS host test because `/proc/sysrq-trigger`
does not exist there.

## Build

Rebuilt the app layer:

```sh
./scripts/docker-build.sh frontend
./scripts/docker-build.sh app-layer --strict
```

Rebuilt the system rootfs:

```sh
./scripts/docker-build.sh system-rootfs \
  --profile debian-retroarch-knulli \
  --out-dir output/rootfs-step2-appfat \
  --rom "artifacts/nes/Super Mario Bros..nes" \
  --wifi-ssid example-wifi-2 \
  --wifi-psk REDACTED_WIFI_PASSWORD \
  --ssh-root-password linux
```

Rootfs inspection confirmed:

```text
-rwxr-xr-x root/root 11741 ... squashfs-root/usr/sbin/plumos-power-action
```

Rebuilt the SD image:

```sh
./scripts/docker-build.sh sd-image \
  --boot0 output/device-live/raw-boot-chain/plumos-v90s-stockos-ra-20260710-2-stockos-video.img/boot0.bin \
  --boot-package output/device-live/raw-boot-chain/plumos-v90s-stockos-ra-20260710-2-stockos-video.img/boot-package.bin \
  --rootfs-squashfs output/rootfs-step2-appfat/debian-bookworm-retroarch-knulli-step2.squashfs \
  --app-layer-dir output/app-layer/v90s \
  --name plumos-v90s-appfat-1g-powerclean-20260711-1.img
```

Generated artifacts:

```text
d41d411fa12fe1fc1e2faf549ba2d127411ed2c5aba8960f5e2f0b9f9f34d540  output/images/plumos-v90s-appfat-1g-powerclean-20260711-1.img
e48d561a4f279b5a90a00a7bf5679c3d14d55db1c97dd5ac3169a1d49419a26c  output/rootfs-step2-appfat/debian-bookworm-retroarch-knulli-step2.squashfs
9e93421a0a92edc0aaebdda281eaa7d949615d083470799dc04dfbf0af3ee83e  output/app-layer/v90s/bin/plumos-safe-shutdown
5c659efdaa1fe285177b2f093a625718b66ced76933c1633a6ea898d69a4dd7b  output/app-layer/v90s/manifest.json
8ffb63930f4582286518913ff8369542a84e23cd365a11e602a80c4519b64891  output/app-layer/v90s/checksums.sha256
```

Image manifest:

```text
image=output/images/plumos-v90s-appfat-1g-powerclean-20260711-1.img
sha256=d41d411fa12fe1fc1e2faf549ba2d127411ed2c5aba8960f5e2f0b9f9f34d540
rootfs_squashfs_sha256=e48d561a4f279b5a90a00a7bf5679c3d14d55db1c97dd5ac3169a1d49419a26c
share_size=1024M
app_layer_manifest_sha256=5c659efdaa1fe285177b2f093a625718b66ced76933c1633a6ea898d69a4dd7b
partitions=p1:boot-resource/PLUMBOOT,p2:env,p3:env-redund,p4:boot,p5:batocera,p6:rootfs/BATOCERA,p7:rootfs_data/PLUMOS-FAT32
```

## Validation Status

Not yet hardware-validated.

Expected test:

1. Flash `output/images/plumos-v90s-appfat-1g-powerclean-20260711-1.img`.
2. Boot V90S.
3. Confirm FE starts and p7 is mounted read-write.
4. Use FE Reboot.
5. After reboot, check that dmesg no longer contains:

```text
FAT-fs (mmcblk0p7): Volume was not properly unmounted.
```
