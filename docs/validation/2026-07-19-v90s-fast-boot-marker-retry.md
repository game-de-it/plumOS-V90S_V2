# V90S fast-boot clean-marker retry

Date: 2026-07-19

## Symptom

A normal reboot from the frontend unexpectedly displayed the initramfs checked
boot progress screen. The boot completed, but it ran p3 ext4 fsck, p4 FAT fsck,
and the full system SquashFS hash instead of the clean fast path.

The issue reproduced on demand. The original `last-boot.log` only showed the
checked path, so initramfs was extended to record each fast-boot predicate.

## Root cause

The diagnostic boot reported:

```text
fast boot rejected: p3_complete=1 p3_clean=0 p4_ready=1 p4_clean=1 hash_metadata=1 hash_match=1
```

Only the p3 clean-shutdown marker was missing. The p4 marker, p4 readiness,
provisioning completion, p1 hash metadata, and p3 verified-system cache were
all valid. The p1 and p3 system hashes both remained:

```text
c17aeb0e9d53aede636318fe581086cbe3e6e93a8a1fa5fd88aa397c0c3e2713
```

Therefore replacing `bootlogo.bmp` was not the cause. The logo is outside the
fast-boot predicates and did not change the system hash metadata.

The power helper created both clean markers, but its old unmount sequence
invalidated a marker immediately after the first unmount failure. It then
retried p3 after deleting the marker. A short-lived persistent-storage user
during process shutdown could therefore force the next boot onto the checked
path even when the retry completed the unmount.

## Fix

`scripts/plumos-power-action-rootfs.sh` now:

- verifies both marker writes and records whether they succeeded
- refreshes the set of persistent-storage users after an unmount failure
- waits 200 ms and retries the same unmount
- removes the corresponding clean marker only if the retry also fails
- treats the quiesce as clean only when both marker writes and both unmounts
  succeeded

`scripts/v90s-four-partition-init` now logs every fast-boot predicate whenever
the clean path is rejected. The image preflight requires this diagnostic.

## Hardware validation

The diagnostic p2 was written and read back as:

```text
edad81b42d12f6262651c20c079c383de8d19b2d9a20a6114606a830db33eeb4
```

The fixed system SquashFS and installed power helper were:

```text
system_squashfs=c1001d5d2a0cd0b3c6716e6dffbff6854e0580b94c947da90d7cf3ea6856ae60
power_helper=69c6def53bb212bbed2470f404390376cee7e8de922690ae7d4ec1090f9e8e35
```

Two consecutive reboots succeeded through the clean path, including one using
the installed frontend power-action wrapper:

```text
fast boot: clean p3/p4 and cached system verification accepted
normal boot: userdata provisioning is complete
system-a cached verification accepted
```

There was no ext4 fsck, FAT fsck, full system hash, or progress framebuffer.
After handoff, p1 was mounted read-only and exactly one
`plumos-controller-ui-fbdev` process was running.

The regenerated seed image passed preflight and complete structural
verification:

```text
image=output/images/plumos-v90s-four-partition-20260719-2.img
sha256=01b2512f6c3b4bfcc34f8966b0502ff02edd519d1e4f381b56b11170137e96e0
verification=PASS
```
