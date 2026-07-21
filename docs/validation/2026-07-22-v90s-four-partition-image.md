# V90S four-partition image 20260722-1

## Purpose

Build a new four-partition provisioning seed from all implementation commits
through source commit `c50d100f8ccb4152ede322c77335a5f99f1de819`. This image
therefore includes the event-driven device-side ADB recovery validated before
assembly.

## Build

The boot and runtime inputs were rebuilt instead of reusing the previous image:

```text
./scripts/docker-build.sh boot-package
./scripts/docker-build.sh boot-image
./scripts/docker-build.sh system-rootfs
./scripts/docker-build.sh app-layer --strict
./scripts/docker-build.sh preflight
./scripts/docker-build.sh sd-image \
  --name plumos-v90s-four-partition-20260722-1.img
```

Preflight passed the fixed boot environment, provisioning initramfs, system
SquashFS, complete app-layer checksums, bounded SD2 mount, single-FE exec chain,
and p3 capacity checks.

## Artifact

```text
path=output/images/plumos-v90s-four-partition-20260722-1.img
size=2840088576
sha256=8960197cf147c70be1ed4a2c1c87eeca6a8fe28b6a2c151ad80bf35d237f757d
```

Input identities:

```text
boot_package_sha256=f991e430bd7d290b8f3b7f2b9dd8071c5989867d7f3fbea0b95ba99939585ec9
boot_image_sha256=217bfa9d9cce69e8743a36096e4925dae40b6e777a1514165fa9a9ce64e42891
system_squashfs_sha256=d6898e8afcd7685a5e988ab818f15b8e19216428df5d4bd6e4df9c98dc09ada3
app_runtime_manifest_sha256=090764d628d8d7e3052994b3d3481277a3f15e9a2bb1f14d2f85a5e7ecd49eae
```

## Verification

The generated `.sha256` file passed an independent `sha256sum -c` check. The
image verifier also passed:

- 640x480 24-bit V90S boot logo
- GPT seed geometry: p1 1024 MiB, p2 64 MiB, p3 1600 MiB, p4 absent
- raw boot0 and boot-package regions
- p2 provisioning Android boot image
- p1 PLUMBOOT resources and identical A/B system SquashFS payloads
- p3 PLUMOS_SYS ext4 filesystem and frontend payload
- 349 MiB free in the p3 seed

The image is ready to write to an SD card. First boot remains responsible for
expanding p3 to 8192 MiB and creating p4 FAT32 `PLUMOS` through the remaining
card capacity. Real-device boot validation is not part of this host-side build.
