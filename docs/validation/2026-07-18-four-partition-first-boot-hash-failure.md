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

## SD2 FE game runtime

The user launched SD2 `nes/Baseball.nes` from the frontend and confirmed both
visible gameplay and physical controls. Live ADB process arguments proved the
complete intended launch path:

```text
plumos-retroarch-launch --system nes \
  --core /mnt/plumos/cores/quicknes_libretro.so \
  --rom /mnt/plumos/roms/nes/Baseball.nes --cpu ondemand
v90s-retroarch-launch
retroarch --config /mnt/plumos/config/retroarch/retroarch-v90s.cfg \
  --appendconfig /run/plumos/retroarch/retroarch-launch-2872.cfg \
  -L /mnt/plumos/cores/quicknes_libretro.so \
  /mnt/plumos/roms/nes/Baseball.nes
```

RetroArch owned `/dev/input/event4`, `/dev/dri/renderD128`, and
`/dev/snd/pcmC0D0p`. The framebuffer remained `640x480p-60` with the expected
double-height virtual buffer. CPU policy remained `ondemand` rather than a
forced fixed frequency.

The frontend process remained asleep for post-game return. Its CPU tick count
did not change during a two-second sample while RetroArch's count advanced, so
there was no active duplicate FE workload. ALSA reported `RUNNING`, owned by
RetroArch, at signed 16-bit stereo/48 kHz with no XRUN. The internal DAC mixer
and plumOS software-volume backend agreed on the expected `170,170` DAC target.

All p1, p3, p4, ROM, and BIOS mounts remained intact and writable according to
their policy. The kernel log contained no new segfault, OOM, MMC I/O,
filesystem, or read-only-remount error. Audible audio quality and pitch,
FPS/scrolling, normal game exit, FE return, and persistence remain physical
follow-up checks.

## Second-boot setup and shutdown defect

After the user selected Shutdown from the FE start menu and powered the V90S
on again, the storage setup screen appeared a second time. The partition layout
and durable markers were still correct, so provisioning had not actually
recreated p3 or p4. The old initramfs nevertheless executed these operations on
every boot:

```text
provision: resizing p3 ext4
resize2fs: Nothing to do
fsck.fat
userdata directory seeding
PREPARING STORAGE / VERIFYING SYSTEM progress frames
```

It also replaced `first-boot.log` with the latest boot log. The completion
marker existed but was never consulted to distinguish provisioning from normal
boot.

The same boot log showed that this was not a forced-power-loss event. The FE
power-action log proved a normal menu shutdown request, but the previous
SquashFS helper stopped only SD2 and selected app-layer processes. It did not
unmount p4 at `/mnt/plumos-user`, its `/boot`, `Images`, and theme mounts, or
processes such as hardware keys and ADB that retained executables on p3. It then
issued immediate SysRq poweroff. The next boot consequently reported:

```text
PLUMOS_SYS: recovering journal
Dirty bit is set. Fs was not properly unmounted
```

The initramfs now validates geometry on every boot but uses the completed
provisioning state to skip `resize2fs`, progress-marker writes, and userdata
seeding. Normal boots display `BOOTING PLUMOS`, write `last-boot.log`, and
preserve the original `first-boot.log`.

The SquashFS power helper now stops every process holding p3/p4 paths, unmounts
SD2 and p4 child mounts before p4 and p3, and sends SysRq sync plus read-only
remount before the final reboot or poweroff action. A live reboot with this
helper produced a clean next boot: ext4 did not recover its journal and FAT32
did not report or clear a dirty bit.

The corrected system rootfs and p2 were built and passed the extended
preflight. The generated full candidate also passed structural verification:

```text
image=output/images/plumos-v90s-four-partition-20260718-9.img
sha256=22bcfdc7229c4dbfe6e4038bd9f4145cfdfe9def2911422f3573681b9384adb8
system_squashfs_sha256=6772b9a5eb77f1148436bfda713c153c2ca5fd1a8c13cc27579a85c530cdc8e4
p2_boot_image_sha256=020cca7b42a03a56205f3b6fa96b36f1c58caf1b623e9b84bdee4fb395a131a9
preflight=PASS
verification=PASS
```

Both corrected SquashFS slots and p2 were also transferred to the existing
physical card before reboot. The SquashFS payload and p2 hashes matched their
host artifacts, but the separate p1 hash files were not read back after the
active-file replacement. That omission caused the next failure described
below. Final confirmation of the updated normal-boot screen, FE startup, and a
complete menu-shutdown/cold-boot cycle remains pending.

## Active p1 live-update failure

The next boot displayed `STARTUP FAILED`. The new normal-boot path itself
worked: `last-boot.log` reported complete p3 and userdata provisioning, with no
ext4 journal recovery and no FAT dirty bit. Recovery was triggered by the
system integrity check:

```text
sha256 mismatch
expected=5781f1247e4eb15ff729b3715a8a81b36f4574e148c7ee3af703c7c429cac3cb
actual=6772b9a5eb77f1148436bfda713c153c2ca5fd1a8c13cc27579a85c530cdc8e4
recovery: system-a hash verification failed
```

The live deployment had remounted p1 read-write while the running root used
`system-a.squashfs` through loop0. Both new SquashFS payloads were intact and
matched `6772b9...c8e4`, but macOS FAT repair found both `.sha256` entries
starting at free clusters and truncated them. This was a deployment-procedure
defect, not candidate image corruption.

`diskutil repairVolume` repaired p1, both 84-byte hash files were recreated,
and the A/B payload and metadata hashes were read back successfully. A second
p1 repair and the p4 repair both completed with exit code 0 and no remaining
filesystem modification. The complete SD device was then cleanly unmounted.
Future p1 updates must be offline or use a tested inactive-slot transaction;
active p1 live replacement is prohibited.
