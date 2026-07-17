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
