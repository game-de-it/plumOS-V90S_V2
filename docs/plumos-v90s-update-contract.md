# plumOS V90S Update Contract

Date: 2026-07-22
Status: Adopted implementation contract

## Live Baseline

The physical V90S state is the source of truth for this contract:

```text
p1 PLUMBOOT    vfat, normally read-only at /mnt/plumos-boot
p2 BOOT        raw Android boot image; fixed vendor kernel, DTB, and initramfs
p3 PLUMOS_SYS  ext4 at /mnt/plumos
p4 PLUMOS      FAT32 at /mnt/plumos-user
/               read-only SquashFS selected from p1
```

The existing flat compatibility paths under `/mnt/plumos`, such as `bin`,
`lib`, `frontend`, and `cores`, remain the runtime ABI. Updates must not require
applications to move to a `releases/current` path.

The fixed StockOS-derived kernel and its matching vendor modules are not normal
update targets. `boot0`, the boot package, p2 kernel, DTB, and initramfs require
a full, separately validated SD image. Normal plumOS updates have two types:

- Runtime Update: files managed by plumOS on p3 ext4
- System Update: the read-only system SquashFS stored in p1

## User Workflow

Both package types are versioned `.tar.gz` archives copied from Windows or
macOS into:

```text
PLUMOS:/updates/
/mnt/plumos-user/updates/
```

The frontend scans only this inbox. It verifies and records the selected
package, then uses the normal safe reboot path. The updater lives in the
read-only system SquashFS and applies the request before the frontend or any
app-layer network writer starts. Update archives are not extracted by the user
and are not modified or deleted by plumOS.

## Package Trust and Compatibility

Every archive contains `META/manifest.json`, `META/manifest.sig`, and a
`payload/` tree. The Ed25519 signature covers the canonical manifest. The
manifest contains at least:

```text
format version
package type: runtime or system
target device: powkiddy-v90s
architecture: aarch64
vendor runtime: v90s-stockos-r1
source and target version
runtime ABI and system ABI compatibility
uncompressed size and required free space
payload file path, type, mode, size, and SHA-256
managed deletion list
```

Extraction rejects absolute paths, traversal, special files, undeclared
members, escaping links, and payloads exceeding declared limits. Production
updates require a valid signature from the public key embedded in the system
SquashFS. A developer-only unsigned mode must require an explicit environment
override and must never be the frontend default.

The repository stores only `package/system-v90s/plumos-update-public.pem`.
The release private key is local-only at
`artifacts/update-signing/plumos-v90s-ed25519-private.pem` and is excluded from
git. Official packages are built through the Docker entry point:

```sh
./scripts/docker-build.sh update-package \
  --type runtime --input output/app-layer/v90s \
  --base-dir PATH/TO/PREVIOUS/RUNTIME \
  --base-version OLD --version NEW --output-dir dist/updates

./scripts/docker-build.sh update-package \
  --type system \
  --input output/system-rootfs/v90s/plumos-v90s-system-rootfs.squashfs \
  --base-version OLD --version NEW --output-dir dist/updates
```

`PLUMOS_V90S_SYSTEM_VERSION=NEW` must be used when building the System
SquashFS so its embedded version matches the System package target version.

## Runtime Update

The p3 layout remains flat. An update is applied as a journaled file
transaction:

1. Verify the package before changing p3.
2. Extract into `/mnt/plumos/updates/staging/TRANSACTION.partial`.
3. Verify every staged payload file.
4. Reject persistent/user-owned paths.
5. Reserve enough ext4 space for staging and rollback.
6. Acquire the global update lock and commit each rollback-journal entry before
   moving a replaced or deleted managed file into the transaction backup.
7. Atomically rename its staged replacement into the live flat path.
8. Flush each file and affected parent directory.
9. Commit `VERSION`, `manifest.json`, and `checksums.sha256` last.
10. Record pending health and start the frontend.
11. Mark the update healthy only after the frontend writes its renderer-ready
    proof.

An interrupted transaction is rolled back before the next frontend start.
The same non-blocking lock protects request registration, boot-time apply, and
frontend health confirmation, so two updater processes cannot mutate state at
the same time.
Only the immediately previous successful Runtime Update backup is retained.
Before a new transaction starts, the older backup and stale staging trees are
removed. Thus updater-owned backups do not grow without bound.

Runtime updates may replace plumOS-managed executables, libraries, cores,
frontend code, factory defaults, and static launch metadata. They must not
replace active settings, saves, states, logs, ROM/BIOS content, user artwork,
Pyxel environments, credentials, SSH keys, or PortMaster-installed content.
Configuration changes use versioned idempotent migrations against known keys.

## System SquashFS Update

p1 contains exactly two system slots. A System Update always writes only the
inactive slot:

1. Verify the signed package in the current system root.
2. Stage and hash the complete SquashFS on p3.
3. Temporarily remount p1 read-write.
4. Copy the image under a temporary inactive-slot filename.
5. Flush it, read it back, and verify SHA-256.
6. Atomically replace the inactive image and commit its hash/manifest last.
7. Remount p1 read-only.
8. Record the pending slot durably on p3 and reboot.
9. The p2 initramfs verifies and boots the pending slot once.
10. Frontend renderer readiness promotes it to active.
11. A second boot without readiness rejects the pending slot and returns to the
    previously active slot.

The active slot is never overwritten. System storage therefore remains fixed
at two slots rather than accumulating old SquashFS images. p3 is authoritative
for active, pending, attempted, and healthy state; p1 `active-slot` is only a
host-visible seed hint.

The StockOS-derived Linux 4.9 VFAT implementation can return `fsync()` failure
with errno left at zero after flushing a large file. Only that unsupported
errno class may fall back to a filesystem-wide `sync`; the inactive image must
still pass a complete readback SHA-256 before rename or pending-slot commit.
p1 remount mode is verified through `/proc/mounts`, and p1 is restored to
read-only on every success or failure path.

## Retention and Logs

- Runtime backups: one previous transaction
- System backups: the other fixed A/B slot
- Staging: removed after success or rollback
- Update state: bounded current/previous metadata
- Logs: one bounded latest result on ext4
- FAT32 update archives: user-managed and never automatically deleted

Failure details are stored on p3 and a bounded last-failure summary is copied
to `/mnt/plumos-user/plumos-logs/update/` for host-side recovery.

## Frontend Contract

`System Settings -> System Update` displays the installed Runtime and System
versions. Pressing A verifies compatible packages in p4 `updates/`, selects the
newest valid package, records the request, locks normal input, and enters the
existing safe reboot flow. The rootfs command `plumos-system-update scan`
provides the complete compatible/invalid package inventory for diagnostics;
the initial frontend implementation intentionally keeps the normal flow to one
action rather than exposing package internals to users.
The following boot displays dedicated verifying, installing, finalizing,
rollback, or failure progress frames. Updates always complete through a reboot;
the frontend must not replace running files itself.
