# Step 2 PowerVR Start-CWD Image

Date: 2026-07-09

## Purpose

The previous PowerVR probe proved that `pvrsrvkm.ko` and `dc_sunxi.ko` can load and that the kernel reports a usable fbdev display path. It also showed that `pvrsrvctl --start` was run from the wrong working directory.

KNULLI's a133 init flow does:

```sh
cd /lib/modules/4.9.191
pvrsrvctl --start
```

This image applies that flow in the Debian payload probe.

## Build Commands

```sh
./scripts/run-assembly-tools.sh ./scripts/build-step1-rootfs.sh \
  --profile debian-retroarch-pvr-probe \
  --out-dir output/rootfs-step2-pvr-start-cwd \
  --rom artifacts/nes/'Super Mario Bros..nes'

./scripts/run-assembly-tools.sh ./scripts/assemble-v90s-image.sh \
  --rootfs output/rootfs-step1/stage1-userdata-loader.squashfs \
  --userdata-payload output/rootfs-step2-pvr-start-cwd/debian-bookworm-retroarch-pvr-probe-step2.squashfs \
  --boot-vfat-size 33M \
  --userdata-size 512M \
  --diagnostic-init \
  --name plumos-v90s-armbian-step2-20260709-3-pvr-start-cwd.img
```

## Outputs

```text
output/images/plumos-v90s-armbian-step2-20260709-3-pvr-start-cwd.img
sha256: 70f35ca82a7147a1602c8c6c7ed4f0c05e6bce481f5c24cfcff17096ca13ba11
size: 581M

output/rootfs-step2-pvr-start-cwd/debian-bookworm-retroarch-pvr-probe-step2.squashfs
sha256: 8b6dace6e81c407af84182db4a4186c927ac884416762c66d983327ccf6a65a3
size: 421M
```

Partition sizing:

- FAT boot-resource: 33MB
- userdata: 512MB

## Changes From Probe 2

- `v90s-pvr-probe` mounts debugfs before reading `/sys/kernel/debug/pvr`.
- `v90s-pvr-probe` runs `pvrsrvctl --start` from `/lib/modules/4.9.191`.
- Manual `insmod` remains as a fallback if `pvrsrvctl --start` does not load both modules.
- `v90s-retroarch-launch` no longer tries `SDL_VIDEODRIVER=dummy`, because that can run headless and prevent useful fallback.

## Expected FAT Logs

```text
/Volumes/KNULLI/plumos-logs/plumos-v90s-pvr-probe.log
/Volumes/KNULLI/plumos-logs/plumos-v90s-retroarch-launch.log
/Volumes/KNULLI/plumos-logs/plumos-v90s-retroarch.log
```

The next key signal is whether `plumos-v90s-pvr-probe.log` contains:

```text
===== pvrsrvctl-start-cwd-moddir =====
...
===== pvrsrvctl-start-cwd-moddir rc=0 =====
```

If this passes and RetroArch still cannot display, move to patched SDL2 / KNULLI-built RetroArch.
