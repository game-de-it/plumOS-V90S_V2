# V90S Transactional Update Host Validation

Date: 2026-07-22
Result: Host validation PASS; physical Runtime success and System A/B promotion PASS

## Scope

- signed Runtime and System update package generation
- p3 flat-runtime journal, rollback, and one-generation retention
- p1 inactive-slot System write and health promotion
- p2 initramfs pending-slot trial and rollback paths
- frontend update request and safe reboot entry point
- complete four-partition seed image assembly

## Automated Results

`python3 -m unittest -v tests/test_v90s_update.py` passed all four transaction
tests. The tests prove that:

- a second Runtime update replaces the previous rollback backup instead of
  adding another generation
- persistent configuration outside the managed path set is not packaged
- an update that does not reach frontend health is restored on the next boot
- a power interruption immediately after backup or new-file placement is
  recovered from the write-ahead journal
- a System update leaves the active slot unchanged, writes only the inactive
  slot, and promotes it only after health confirmation
- the vendor VFAT errno-zero `fsync()` fallback is accepted while real I/O
  errors remain fatal

State-changing updater commands share a non-blocking `/run` lock, preventing
frontend request registration, boot-time apply, and health confirmation from
mutating the transaction state concurrently.

`./scripts/docker-build.sh preflight` passed the boot package, A/B initramfs,
System SquashFS updater/public key/progress frames, app-layer checksums, SD2
mount, frontend exec chain, and p3 capacity checks.

The official Ed25519 public key successfully verified a generated System
package. Its package-level SHA-256 also passed:

```text
dist/update-validation/plumos-v90s-system-0.1.0-dev.tar.gz
sha256: b07fdae01183420aebdc66f8211e31fd222f4ec612b1ff17a8f9fee8f3d4ca6e
```

## Seed Image

```text
output/images/plumos-v90s-four-partition-seed.img
size: approximately 2.6 GiB
sha256: 8d580bf0f8c46c76b53fc6ef31276dfd119123db65dea6824b4dfb2153f9b3b9
```

`verify-v90s-four-partition-image.sh` passed exact GPT geometry, raw boot0 and
boot-package regions, p2 boot image, p1 A/B System images, p3 ext4 integrity,
`RUNTIME_ABI=1`, frontend payload, and app-layer manifest identity. The p3 seed
retains 349 MiB free before first-boot expansion.

## Physical V90S Results

The seed image completed first boot on a 128GB SD card. p3 expanded to 8GiB,
p4 was created through the remaining 106GiB, p1 stayed read-only during normal
operation, SD2 ROM/BIOS bind mounts were present, one frontend owned the
display, and all 5,644 app-runtime checksums passed.

A signed Runtime package changed only `VERSION`, `manifest.json`, and
`checksums.sha256`. The device advanced from `0.1.0-dev` to
`0.1.0-runtime-test1`, wrote frontend readiness, marked the transaction
healthy, retained exactly one 2.3MiB previous-generation backup, removed all
pending state, and passed all 5,644 checksums again.

The first System test exposed a vendor-kernel VFAT behavior: Python `fsync()`
returned failure with errno zero after writing the 96MiB inactive image even
though a BusyBox `dd conv=fsync` comparison produced an identical readback
SHA-256. Cleanup then initially masked that error by trying to remove the
temporary file after remounting p1 read-only. The updater now preserves the
original exception, verifies actual remount state, cleans temporary files while
still writable, falls back from only the vendor unsupported-fsync errno class
to `sync`, and still requires a full image readback hash.

With that correction, slot `b` was written and verified while active slot `a`
remained unchanged. The p2 initramfs trial-booted `b`; frontend renderer proof
then promoted it. The final observed state was System
`0.1.0-system-test1`, active=`b`, pending absent, p1 read-only, and exactly one
frontend process.

## Remaining Hardware Proof

Interrupted Runtime rollback, System readiness-failure rollback, and final
post-update reboot/shutdown should still be validated and recorded separately.
