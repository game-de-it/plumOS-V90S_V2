# V90S FAT32 Bulk-Write Hardening Validation

Date: 2026-07-16

## Scope

This validation covers p7 `/mnt/plumos` write durability for frequent frontend
state replacement, full ROM-library index generation, live ADB app-layer
deployment, and PortMaster payload switching.

## Implementation

- `plumos-text-ui` now flushes and `fsync`s each temporary state file before
  rename, then syncs the parent directory.
- `plumos-library-scan` uses the same contract for library-index replacement.
- `deploy-app-layer-adb.sh` verifies the full host artifact before changing the
  device, preserves ADB/SSH, quiesces known p7 writers, transfers bounded
  chunks through `/run`, syncs and verifies each chunk, and commits metadata
  last.
- The PortMaster updater syncs its staged tree before switching it into place,
  syncs the app directory after tree changes, and durably replaces
  `installed.json`.
- PortMaster dependency extraction durably replaces its digest, and the GUI
  launcher syncs completed game-install writes before returning to the FE.

## Built Artifacts

```text
frontend checksums.sha256:
22899ed164c7ef9f79780aa27820a13891253a64753c950a7d2981583feb8851

app-layer checksums.sha256:
f9fe56e6ef9332b6a17da8a015000d7a82c21f56b6ab44e2d4ce1675becca740

app-layer manifest.json:
47a6cec061db8eaa717451982c9fea2d0b6922445cd7128d4bc0c22bb7d916c1

PortMaster package checksums.sha256:
11508936ce8788824ceaf351eddd644dc547869b8a761e7111bb9d97696b6327

Pinned upstream PortMaster payload:
772f2d56fc1abfbf79a3404ca78f240776c81c5a5b92786a0a748ae554339b7b
```

## Real-Device Deployment

Device transport: `plumos-v90s-af929c1b`

The deployment was intentionally run with
`PLUMOS_DEPLOY_CHUNK_FILES=2`. Six changed files were found: five payload files
plus `manifest.json`. The payload completed as three verified chunks.

Post-deployment evidence:

```text
/dev/mmcblk0p7 /mnt/plumos vfat rw,...,errors=remount-ro
frontend process count: 1
hardware key service: running
FTP: running and enabled
SSH: running and enabled
ADB: running and enabled
Samba: enabled, waiting for IPv4
app_layer=ready
vendor=v90s-stockos-r1
```

There were no matching FAT read-only/error messages or MMC CRC, timeout, reset,
or I/O errors in `dmesg`. A second unchanged deployment returned
`deploy=up-to-date`, and the frontend PID remained `5779` before and after it.

The final PortMaster GUI/dependency durability follow-up was deployed as two
verified chunks. Device hashes for the launcher, bootstrap, manifest, and
checksum list matched the rebuilt app layer. The final state remained p7
read-write, one FE process, app-layer validation ready, SSH/FTP/ADB running,
and no FAT/MMC error in `dmesg`.

## State and Index Stress Test

With the frontend stopped, the device completed:

- 64 durable replacements of `state/frontend/recent.json`
- five full rebuilds of `state/frontend/library-index.json` (about 486 KiB)
- restoration of the original recent-history file

After the test:

- p7 remained mounted read-write
- both JSON files parsed successfully with `jq`
- no temporary state files remained
- no FAT/MMC error was present in `dmesg`
- the frontend restarted as exactly one process

This validates the intended write path under repeated metadata and moderate
bulk-index activity. It does not replace offline `fsck.fat` validation after an
actual unexpected power loss.
