# V90S Transactional Update Host Validation

Date: 2026-07-22
Result: Host validation PASS; physical V90S update/rollback validation pending

## Scope

- signed Runtime and System update package generation
- p3 flat-runtime journal, rollback, and one-generation retention
- p1 inactive-slot System write and health promotion
- p2 initramfs pending-slot trial and rollback paths
- frontend update request and safe reboot entry point
- complete four-partition seed image assembly

## Automated Results

`python3 -m unittest -v tests/test_v90s_update.py` passed all three transaction
tests. The tests prove that:

- a second Runtime update replaces the previous rollback backup instead of
  adding another generation
- persistent configuration outside the managed path set is not packaged
- an update that does not reach frontend health is restored on the next boot
- a power interruption immediately after backup or new-file placement is
  recovered from the write-ahead journal
- a System update leaves the active slot unchanged, writes only the inactive
  slot, and promotes it only after health confirmation

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
sha256: d23bcf2fe55aa52714560d25c650ab6f7514e81f58640177ee3ee9bdb0acb453
```

## Seed Image

```text
output/images/plumos-v90s-four-partition-seed.img
size: approximately 2.6 GiB
sha256: 4d48e3ab8642f59525a0d5b608dd413e7d9af42078be1d641e502ec78739a987
```

`verify-v90s-four-partition-image.sh` passed exact GPT geometry, raw boot0 and
boot-package regions, p2 boot image, p1 A/B System images, p3 ext4 integrity,
`RUNTIME_ABI=1`, frontend payload, and app-layer manifest identity. The p3 seed
retains 349 MiB free before first-boot expansion.

## Remaining Hardware Proof

The new image must be booted on V90S before release. Runtime success,
interrupted Runtime rollback, System slot promotion, System readiness failure
rollback, update progress frames, and normal post-update reboot/shutdown must
each be validated and recorded separately.
