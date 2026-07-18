# V90S power-action latency reduction

Date: 2026-07-18

## Goal

Reduce the time spent on the Reboot and Shutdown progress screens without
weakening the p3 ext4, p4 FAT32, or SD2 FAT32 clean-unmount contract.

## Initial timing

The previous rootfs helper used several fixed one-second waits, repeated full
sync sequences, a broad persistent-process scan, and a second SysRq
sync/remount sequence after the persistent filesystems had already been
unmounted.

A live reboot took about 33-35 seconds from action request until ADB returned.
The persisted power log showed roughly 10 seconds before the final p4/p3 phase.

## Changes

`scripts/plumos-power-action-rootfs.sh` now:

- polls terminated PIDs in 100 ms intervals instead of always sleeping one
  second before and after escalation
- ignores kernel threads during userspace process scans
- records both clean-shutdown markers and performs one consolidated sync
- unmounts SD2, p4 child mounts, p4, p3, and p1 in child-first order
- skips the extra SysRq sync/remount waits only after p4 and p3 both unmount
  successfully
- retains the conservative sync/remount fallback when either clean unmount
  fails
- preserves a FAT-visible final failure log when possible

The app-layer `plumos-safe-shutdown` wrapper now clears `LD_LIBRARY_PATH` and
`LD_PRELOAD` before starting `/usr/sbin/plumos-power-action`. This is required
because a rootfs helper started with the frontend loader environment mapped
p3 copies of libraries into its own process. The helper then became the final
blocker to unmounting p3.

## Hardware proof

The first optimized test without loader sanitization reached the p4 unmount
quickly but failed the p3 unmount. The next boot therefore used the checked
path with ext4/FAT checks and full system SquashFS hashing.

With an empty loader environment, two consecutive reboot tests produced:

```text
fast boot: clean p3/p4 and cached system verification accepted
normal boot: userdata provisioning is complete
system-a cached verification accepted
handoff: executing system init
```

The final test measured:

```text
action request to ADB return: about 20.9 seconds
device uptime when ADB returned: about 10.4 seconds
logged shutdown work through /boot unmount: about 3.6 seconds
```

The action-to-return time was reduced by about 12-14 seconds. The remaining
shutdown time is dominated by real FAT32/ext4 unmount and SD-card flush work;
it is intentionally retained for storage safety.

No ext4 journal recovery, FAT dirty warning, storage I/O error, or initramfs
progress screen appeared after the sanitized tests.

## Generated image

The rebuilt system rootfs and app layer were assembled as:

```text
output/images/plumos-v90s-four-partition-20260718-13.img
SHA-256: 28a9b0deb15e777594c6509bd2c9507cee65bcff4e0b25472a72dae6e2169dd6
```

Preflight and structural image verification both passed. The verifier
confirmed the fixed boot regions, p1/p2/p3 seed geometry, A/B system
SquashFS, app runtime, and frontend payload.

## Host checks

```text
sh -n scripts/plumos-power-action-rootfs.sh
sh -n package/frontend-v90s/plumos/bin/plumos-safe-shutdown
git diff --check
```

All passed. Host `shellcheck` was not installed in this session.
