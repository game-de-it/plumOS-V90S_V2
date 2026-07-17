# Four-Partition First-Boot Hash Failure

Date: 2026-07-18

## Hardware result

The first physical boot of
`plumos-v90s-four-partition-20260718-6.img` remained on the boot logo.
Post-boot media inspection confirmed that provisioning had completed these
storage operations:

- relocated the backup GPT to the physical SD-card tail
- expanded p3 `PLUMOS_SYS` from 1536 MiB to exactly 8192 MiB
- resized the p3 ext4 filesystem
- created p4 `PLUMOS` as FAT32 through the final usable sector
- created the expected p3 provisioning markers and p4 `.plumos-ready`

## Root cause

The ext4 p3 filesystem was mounted read-only on macOS through FUSE-T and the
FUSE-T fork of `ext4fuse`. Its `provision/first-boot.log` ended with:

```text
sha256sum: invalid option -- 'c'
recovery: system-a hash verification failed
```

The initramfs supplies BusyBox `sha256sum`, whose build can calculate SHA-256
digests but does not implement GNU coreutils checksum mode (`-c`). The system
SquashFS itself was not shown to be corrupt; the verifier invocation was
incompatible with the runtime tool.

## Correction

The provisioning init now reads the expected digest from the fixed checksum
file, calculates the system image digest with plain `sha256sum`, and compares
the two values in the shell. Preflight rejects any reintroduction of
`sha256sum -c` into this initramfs.

Recovery and progress paths also mirror `first-boot.log` to
`PLUMOS/Logs/boot/first-boot.log` whenever p4 is mounted. Future logo-only boot
diagnostics therefore do not require macOS ext4 support.

## Remaining physical validation

- boot `plumos-v90s-four-partition-20260718-7.img` on the V90S
- boot on V90S and confirm system SquashFS handoff
- confirm frontend startup and exactly one frontend process
- launch an SD2 ROM and compare video, audio, controls, and persistence with
  the established seven-partition runtime

## Corrected candidate

The corrected provisioning boot image, preflight, image assembly, and structural
verification completed successfully:

```text
image=output/images/plumos-v90s-four-partition-20260718-7.img
sha256=b1557869e0cd5ccfe99bfaac70d19be1334c45c6c0beebe8f175aeceb9412381
preflight=PASS
verification=PASS
```

Structural verification reconfirmed the 1024 MiB p1, 64 MiB p2, 1536 MiB p3
seed, absent p4, fixed boot package, provisioning Android boot image, A/B system
SquashFS files, and complete frontend payload.

## Second physical boot

The corrected p2 on the written SD matched the generated boot image byte for
byte. Both system SquashFS files also matched their expected SHA-256 digest, and
the extracted initramfs BusyBox successfully calculated that digest without
`-c`. The second stall was therefore not media corruption or the previous hash
verifier bug.

The system SquashFS inventory exposed the next handoff defect. It contained
`/mnt/plumos` but omitted `/mnt/plumos-boot` and `/mnt/plumos-user`. The
initramfs mounted the SquashFS read-only and then attempted to create those
directories. `mkdir` failed on the read-only filesystem, and global `set -e`
ended PID 1 before a recovery message could be persisted.

The system-rootfs builder now creates all three persistent mountpoints before
SquashFS packing. Initramfs verifies that every handoff mountpoint exists,
wraps each mount move with a named recovery failure, and mirrors additional
handoff checkpoints to p3 and p4.

The same log exposed an unaligned p4 start (`19047424 % 2048 != 0`) and reuse of
the previous test run's stale FAT signature. Provisioning now rounds p4 up to
the next 1 MiB boundary and always formats a p4 that it has just created. A p4
already present in the active GPT remains preserved on ordinary subsequent
boots.

To distinguish slow first-boot work from a stall, the initramfs now writes
simple 640x480 progress frames directly to both fb0 pages. It displays storage
preparation, p3 resize, p4 creation, system verification, SquashFS mount, and
system-init handoff stages. Recovery displays a persistent `STARTUP FAILED`
screen directing the tester to the PLUMOS logs.

## Third candidate

The system rootfs, progress-enabled initramfs, and compact SD image were rebuilt
and passed preflight plus structural verification:

```text
image=output/images/plumos-v90s-four-partition-20260718-8.img
sha256=e1ddfa494a93ee7ea2828d7bf787968d35c081755620e44c1a0883062a95d4dc
preflight=PASS
verification=PASS
```

The generated progress frames are 640x960 BGRA buffers containing identical
pages for the V90S double-buffered fb0 layout. This avoids a dependency on SDL,
the PowerVR userspace, fonts, or the system SquashFS during early boot.

## Third physical boot result

The third candidate completed first boot and displayed the frontend. ADB was
enabled from the FE and provided the following live evidence:

```text
mmcblk0p1 start=41984    sectors=2097152   PLUMBOOT   vfat
mmcblk0p2 start=2139136  sectors=131072    boot       raw
mmcblk0p3 start=2270208  sectors=16777216  PLUMOS_SYS ext4
mmcblk0p4 start=19048448 sectors=222609408 PLUMOS     vfat
```

`19048448 % 2048 == 0`, so p4 begins on the required 1 MiB boundary. Runtime
mount ownership was:

```text
/dev/mmcblk0p1 /mnt/plumos-boot ro vfat
/dev/mmcblk0p3 /mnt/plumos      rw ext4 noatime
/dev/mmcblk0p4 /mnt/plumos-user rw vfat
/dev/mmcblk1p1 /mnt/plumos/roms rw vfat bind
/dev/mmcblk1p1 /mnt/plumos/bios rw vfat bind
```

p3 had approximately 6.8 GiB free and p4 approximately 106.1 GiB free. Every
provisioning marker, including `complete`, existed. Identical complete handoff
logs were present on p3 and p4 and ended with:

```text
system-a hash verification passed
handoff: attaching system SquashFS loop
handoff: mounting system SquashFS
handoff: moving persistent mounts into system root
handoff: executing system init
```

The system root identified itself as Debian bookworm `release-system` with
vendor runtime `v90s-stockos-r1`. The app-layer manifest was complete with all
118 required libretro cores. Exactly one FE renderer was running:

```text
/mnt/plumos/bin/plumos-controller-ui-fbdev --renderer fbdev
```

SD2 `GAME` mounted after a bounded FAT check returned `rc=0`. The 364
`FSCK*.REC` files on SD2 have 1980 timestamps and are already present in its
macOS Spotlight index, so they predate this boot. No current MMC I/O error,
filesystem error, or read-only remount appeared in the kernel log.
