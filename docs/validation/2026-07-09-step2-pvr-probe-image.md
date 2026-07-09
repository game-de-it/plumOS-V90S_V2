# Step 2 PowerVR Probe Image

Date: 2026-07-09

## Purpose

The first Debian RetroArch image booted and loaded the NES core/ROM, but failed because Debian RetroArch did not provide a usable V90S video path. This image keeps the same small FAT partition and adds a diagnostic PowerVR path before RetroArch starts.

This is still a probe image, not the final Step 2 target. The goal is to learn whether the KNULLI A133 PowerVR kernel module, display class module, firmware, and userspace can initialize inside the Debian payload.

## Build Commands

```sh
./scripts/run-assembly-tools.sh ./scripts/build-step1-rootfs.sh \
  --profile debian-retroarch-pvr-probe \
  --out-dir output/rootfs-step2-pvr \
  --rom artifacts/nes/'Super Mario Bros..nes'

./scripts/run-assembly-tools.sh ./scripts/assemble-v90s-image.sh \
  --rootfs output/rootfs-step1/stage1-userdata-loader.squashfs \
  --userdata-payload output/rootfs-step2-pvr/debian-bookworm-retroarch-pvr-probe-step2.squashfs \
  --boot-vfat-size 33M \
  --userdata-size 512M \
  --diagnostic-init \
  --name plumos-v90s-armbian-step2-20260709-2-pvr-probe.img
```

## Outputs

```text
output/images/plumos-v90s-armbian-step2-20260709-2-pvr-probe.img
sha256: eb5de70bc4d9c289a0add25fedb2316cb9939b72847c328cf3291f567af40953
size: 581M

output/rootfs-step2-pvr/debian-bookworm-retroarch-pvr-probe-step2.squashfs
sha256: 4464c58a602f1e8a21cdc634552e6e5e069a69617e6068adadc6c3cc6f71f8d8
size: 421M
```

Partition sizing:

- FAT boot-resource: 33MB
- userdata: 512MB

## Included PowerVR Components

The payload includes:

- `/usr/bin/pvrsrvctl`
- `/usr/lib/powervr/libEGL.so`
- `/usr/lib/powervr/libGLESv2.so`
- `/lib/firmware/rgx.fw.22.102.54.38`
- `/lib/firmware/rgx.sh.22.102.54.38`
- `/lib/modules/4.9.191/pvrsrvkm.ko`
- `/lib/modules/4.9.191/dc_sunxi.ko`
- `/usr/local/sbin/v90s-pvr-probe`

On Debian Bookworm these `/lib` paths are visible in host `unsquashfs` output as `/usr/lib/...` because of usr-merge.

## Expected FAT Logs

After a real-device test, macOS should show these logs without requiring ext4 access:

```text
/Volumes/KNULLI/plumos-logs/session.txt
/Volumes/KNULLI/plumos-logs/plumos-v90s-diag.log
/Volumes/KNULLI/plumos-logs/plumos-v90s-debian-init.log
/Volumes/KNULLI/plumos-logs/plumos-v90s-pvr-probe.log
/Volumes/KNULLI/plumos-logs/plumos-v90s-retroarch-launch.log
/Volumes/KNULLI/plumos-logs/plumos-v90s-retroarch.log
```

The key file for the next decision is `plumos-v90s-pvr-probe.log`. It records:

- `insmod pvrsrvkm.ko`
- `insmod dc_sunxi.ko`
- `/dev/pvr*`, `/dev/pvrsrvkm`, and `/dev/dri/*`
- `/proc/pvr` and `/sys/kernel/debug/pvr`
- `pvrsrvctl --start`
- `pvrsrvctl --start --no-module`
- dmesg before and after module initialization

## Next Decision

If the probe log shows PowerVR successfully initialized, the next work should be a KNULLI-style patched SDL2/RetroArch build for the fbdev EGL path.

If module loading or `pvrsrvctl` fails, fix the module/firmware/userspace contract before spending time on patched SDL2.
