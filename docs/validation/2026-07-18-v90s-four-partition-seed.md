# V90S Four-Partition Provisioning Seed

Date: 2026-07-18

## Scope

Build and host-validate the first compact seed for the candidate layout in
`docs/v90s-ext4-runtime-fat32-userdata-update-design.md`. This is a spike; it
does not promote the four-partition layout to the release default before the
physical V90S checks pass.

## Build Contract

The official entry points are:

```text
./scripts/docker-build.sh boot-package
./scripts/docker-build.sh boot-image
./scripts/docker-build.sh preflight
./scripts/docker-build.sh sd-image --name plumos-v90s-four-partition-20260718-6.img
```

`sd-image` runs the preflight before assembly. The legacy seven-partition
development image remains available through the explicit `stockos-image`
target.

The seed geometry is:

```text
raw boot0       offset 131072
raw boot_package offset 16793600
p1 boot-resource / PLUMBOOT    FAT16  1024 MiB
p2 boot                         raw      64 MiB
p3 runtime / PLUMOS_SYS         ext4   1536 MiB
p4 userdata / PLUMOS            absent from seed
```

## Boot Chain

The captured vendor boot package was unpacked and repacked with only the known
U-Boot default environment changed. An unmodified repack must byte-match the
captured package prefix before the patched package is accepted.

```text
bootcmd=sunxi_flash read 45000000 boot;bootm 45000000
external_env_required=no
boot_package_sha256=f991e430bd7d290b8f3b7f2b9dd8071c5989867d7f3fbea0b95ba99939585ec9
```

The p2 Android boot image retains the captured vendor kernel and replaces the
initramfs entry point with `scripts/v90s-four-partition-init`. The initramfs
contains isolated AArch64 `parted`, `e2fsck`, `resize2fs`, `mkfs.fat`, and
`fsck.fat` binaries and libraries.

```text
boot_image_sha256=bfe68d54ef1ec5be6b64ada46f71ae06f668768280cb028052c62d68bafe50ab
cmdline=console=ttyS0,115200 rootwait init=/init loglevel=4 cma=32M gpt=1
```

Before modifying storage, init validates the p1-p3 partition numbers, exact
starts and seed/target sizes, p1 `PLUMBOOT` label, p3 `PLUMOS_SYS` label, and a
minimum physical size of 31,250,000 sectors. An existing p4 is accepted only
when it is vfat with label `PLUMOS`; an unknown filesystem or label enters
recovery instead of being formatted.

## Preflight Evidence

The preflight completed with:

```text
PASS boot package fixed environment
PASS p2 provisioning initramfs and storage tools
PASS system SquashFS init and app-runtime bootstrap
PASS complete app runtime and checksums
PASS bounded SD2 mount and single frontend exec chain
PASS p3 seed capacity used_kib=1172104
preflight: PASS
```

The SD2 proof checks a bounded fsck path, `/dev/mmcblk[1-9]p*` discovery, ROM
and BIOS bind mounts, restoration of the p4 ROM/BIOS bindings after SD2 stops,
and the startup chain:

```text
system /sbin/init
  -> /usr/sbin/plumos-app-layer-bootstrap
  -> /mnt/plumos/bin/plumos-frontend-launch
  -> plumos-sd2-content-mount start
  -> exec /mnt/plumos/bin/plumos-controller-ui-v90s
```

Before SD2 is considered, the system-root bootstrap binds portable p4 content
into the stable application paths:

```text
/mnt/plumos-user/roms   -> /mnt/plumos/roms
/mnt/plumos-user/bios   -> /mnt/plumos/bios
/mnt/plumos-user/Images -> /mnt/plumos/Images
/mnt/plumos-user/Themes -> /mnt/plumos/themes-user
```

When SD2 is present, only ROM and BIOS mounts override their p4 bindings. The
SD2 stop path restores the p4 bindings, so ejecting or disabling SD2 does not
redirect later writes into the p3 ext4 placeholder directories.

## First-Boot Simulation

The seed was cloned to a sparse 16,000,000,000-byte disk image. The production
initramfs was run in privileged AArch64 Docker with explicit test-only device
and provision-only variables. The first run reported:

```text
geometry disk=/dev/loop0 sectors=31250000 p3_start=2270208 p3_sectors=3145728
provision: relocating backup GPT
provision: growing p3 partition to 8192 MiB
provision: resizing p3 ext4
provision: creating p4 start=19047424 end=100%
provision: formatting new p4 as FAT32
```

The resulting geometry was:

```text
p1 41984s..2139135s       2097152 sectors  FAT16  PLUMBOOT
p2 2139136s..2270207s      131072 sectors  raw
p3 2270208s..19047423s   16777216 sectors  ext4   PLUMOS_SYS
p4 19047424s..31249966s  12202543 sectors  FAT32  PLUMOS
```

p3 mounted as 7.9 GiB with approximately 6.8 GiB available. p4 mounted as 5.9
GiB and contained `/.plumos-ready` plus `roms`, `bios`, `Images`, `Themes`,
`Screenshots`, `Music`, `Manuals`, `Cheats`, `Patches`, `Shaders`, `updates`,
`imports`, and `exports`.

The same initramfs was then run a second time against the provisioned image:

```text
P4_UUID_BEFORE=F624-C401
geometry disk=/dev/loop0 sectors=31250000 p3_start=2270208 p3_sectors=16777216
provision: resizing p3 ext4
P4_UUID_AFTER=F624-C401
SECOND_BOOT_IDEMPOTENCE=PASS
```

The unchanged p4 UUID proves that the normal second-boot path did not reformat
the user FAT32 filesystem.

## Generated Candidate

```text
image=output/images/plumos-v90s-four-partition-20260718-6.img
image_size=2772979712
image_sha256=1478db486d599f1d7b634b81878db2d5b0579523d229c6c2485886134620c2de
p3_seed_free_mib=416
verification=PASS
```

The image verifier confirmed exact GPT geometry, absence of p4, raw boot0 and
boot-package regions, exact p2 content, both p1 system SquashFS hashes, a clean
p3 ext4 filesystem, app manifest equality, and the expected FE launcher.

## Pending Physical Validation

The following claims are intentionally not made from host simulation:

1. The patched boot package reaches p2 on the physical V90S.
2. The vendor kernel accepts the GPT reread and completes switch-root.
3. The system root mounts p3 at `/mnt/plumos` and p4 at
   `/mnt/plumos-user`, then starts exactly one FE process.
4. SD2 ROM/BIOS bind mounts work in this new partition numbering.
5. One SD2 game matches the current LCD, audio, controller, FPS, scrolling,
   audio-pitch, exit, and persistence baseline.

These checks require the user to flash the generated candidate and boot the
physical V90S. Signature enforcement, A/B health/rollback, recovery UI, and
power-cut fault injection remain later candidate work; this spike currently
uses complete SHA-256 verification for the system image rather than release
signature verification.
