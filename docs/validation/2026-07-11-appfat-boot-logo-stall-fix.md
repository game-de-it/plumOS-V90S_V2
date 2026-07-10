# AppFAT Boot Logo Stall Fix

Date: 2026-07-11

## Symptom

The user tested:

```text
output/images/plumos-v90s-liveboot-appfat-1g-20260711-1.img
```

Observed result:

```text
plumOS-V90S / Powered by Batocera boot logo remains on screen.
```

## Cause

The image was generated with `--app-layer-dir` and p7 `SHARE` as 1GB FAT32, but
`--rootfs-squashfs` was not specified. The assembler therefore used its smoke
default:

```text
output/rootfs-step1/stage1-userdata-loader.squashfs
```

That default is a 2.7MB stage1 loader from the older two-stage boot path. It
expects to find a later payload under an ext4 `/mnt/share/rootfs/` flow and is
not the current direct system rootfs with `/mnt/plumos` app-layer startup
support.

The tested image therefore reached the boot logo but did not have the correct
p5 system rootfs to mount p7 FAT32 and launch the frontend.

## Preventive Guard

`scripts/assemble-v90s-stockos-image.sh` now rejects `--app-layer-dir` when
`--rootfs-squashfs` was not specified explicitly:

```text
error: --app-layer-dir requires an explicit --rootfs-squashfs with /mnt/plumos init support
```

This keeps smoke/stage1 images possible while preventing accidental app-layer
images that cannot boot into the current plumOS runtime.

## Corrected Rootfs

Built a current rootfs with app-layer startup support:

```sh
./scripts/docker-build.sh system-rootfs \
  --profile debian-retroarch-knulli \
  --out-dir output/rootfs-step2-appfat \
  --rom "artifacts/nes/Super Mario Bros..nes" \
  --wifi-ssid example-wifi-2 \
  --wifi-psk REDACTED_WIFI_PASSWORD \
  --ssh-root-password linux
```

Output:

```text
output/rootfs-step2-appfat/debian-bookworm-retroarch-knulli-step2.squashfs
sha256=84e172279486f55f8824c9a653d431005e73023bbac8f78e333c31a92ea4826d
size=447M
```

Inspection confirmed that `/sbin/init` contains:

```text
prepare_plumos_app_layer
/mnt/plumos/bin/plumos-network-services start-enabled
/mnt/plumos/bin/plumos-frontend-launch
```

The rootfs also includes the known-good RetroArch route:

```text
PLUMOS_V90S_VIDEO_DRIVER=gl
PLUMOS_V90S_VIDEO_CONTEXT_DRIVER=mali_fbdev
PLUMOS_V90S_VIDEO_THREADED=true
PLUMOS_V90S_VIDEO_REFRESH_RATE=58.917103
PLUMOS_V90S_VRR_RUNLOOP_ENABLE=true
PLUMOS_V90S_AUDIO_DRIVER=alsa
```

## Corrected Image

Built:

```sh
./scripts/docker-build.sh sd-image \
  --boot0 output/device-live/raw-boot-chain/plumos-v90s-stockos-ra-20260710-2-stockos-video.img/boot0.bin \
  --boot-package output/device-live/raw-boot-chain/plumos-v90s-stockos-ra-20260710-2-stockos-video.img/boot-package.bin \
  --rootfs-squashfs output/rootfs-step2-appfat/debian-bookworm-retroarch-knulli-step2.squashfs \
  --app-layer-dir output/app-layer/v90s \
  --share-size 1024M \
  --keep-work \
  --name plumos-v90s-appfat-1g-20260711-2.img
```

Output:

```text
output/images/plumos-v90s-appfat-1g-20260711-2.img
output/images/plumos-v90s-appfat-1g-20260711-2.img.manifest.txt
sha256=1f46b33d840abe2ef947fcc8f45f42afd09bff7e34a954a575ec3e3c3df3230f
```

Manifest excerpts:

```text
rootfs_squashfs=output/rootfs-step2-appfat/debian-bookworm-retroarch-knulli-step2.squashfs
rootfs_squashfs_sha256=84e172279486f55f8824c9a653d431005e73023bbac8f78e333c31a92ea4826d
share_size=1024M
app_layer_manifest_sha256=28639f16f7ba7ca6ea923aa33a11d452c6502da576f07cd08b63afb4921480fb
allow_knulli_boot_fallback=0
```

Partition table:

```text
p1  33M     Microsoft basic data
p2  256K    Linux filesystem
p3  256K    Linux filesystem
p4  64M     Linux filesystem
p5  446.6M  Linux filesystem
p6  33M     Linux filesystem
p7  1G      Microsoft basic data
```

p7 FAT32 verification:

```text
Volume label: SHARE
Extracted app layer: 146M
sha256sum -c checksums.sha256: OK
fsck.fat -n -v: OK
/tmp/plumos-p7-2.vfat: 1075 files, 37351/261627 clusters
```

## Next Real-Device Check

Write `plumos-v90s-appfat-1g-20260711-2.img` and check:

- boot logo should proceed into plumOS frontend
- p7 FAT32 should mount at `/mnt/plumos`
- Wi-Fi should reconnect with password authentication available as `root/linux`
- frontend should launch RetroArch with the known-good video/audio route

