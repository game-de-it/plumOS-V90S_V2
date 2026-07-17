# plumOS V90S ext4 Runtime and FAT32 User-Data Update Design

Date: 2026-07-17
Status: Draft for discussion; not yet adopted by the Distribution Policy

## Purpose

This document records a candidate replacement for the current FAT32 app-layer
design. It is intended to preserve easy Windows/macOS updates while moving
frequently changed plumOS applications and persistent state onto ext4.

The user-facing update flow should remain simple:

1. Download one plumOS update archive.
2. Copy it onto the Windows/macOS-visible FAT32 partition.
3. Safely eject the SD card and boot the V90S.
4. Select `System Update` from the frontend.
5. Wait for validation, installation, and restart to complete.

The user must not need to extract the archive or replace individual runtime
files.

## Decision Status

This is a design proposal, not the current release contract.

The current implementation still uses:

```text
p5  squashfs  read-only Linux system
p6  ext4      BATOCERA, about 33 MiB, mounted read-only at /boot
p7  FAT32     PLUMOS app, update, configuration, and data layer
```

The current FAT32 design remains supported until this proposal is explicitly
accepted, implemented on a separate development path, and validated on V90S
hardware.

## Goals

- Keep ROM, BIOS, and update transfer accessible from Windows and macOS.
- Store executable files, libraries, symlinks, permissions, settings, and saves
  on a native Linux filesystem.
- Make an interrupted application update leave the previous release bootable.
- Keep user settings and saves separate from replaceable release payloads.
- Allow one-step frontend updates with progress and an input-locked screen.
- Keep the StockOS-derived bootloader, kernel, GPU, audio, and input contract.
- Avoid writing to the mounted p5 SquashFS backing partition.
- Retain a recovery path when either the application update or FAT32 user area
  is damaged.

## Non-Goals

- This proposal does not replace the vendor kernel or bootloader.
- It does not make arbitrary power loss harmless to a file actively being
  written.
- It does not define a live in-place update of the mounted p5 SquashFS.
- It does not require online updates or a permanent package-manager daemon.
- It does not make SD2 mandatory for normal SD1-only operation.

## Proposed Partition Layout

The candidate SD1 layout is:

```text
p1  boot-resource  PLUMBOOT    FAT16   existing vendor boot contract
p2  env                         raw     existing vendor boot contract
p3  env-redund                  raw     existing vendor boot contract
p4  boot                        raw     Android boot image
p5  system          PLUMSYS     squashfs read-only Linux system
p6  rootfs          BATOCERA    ext4    existing small /boot partition, read-only
p7  runtime         PLUMOS_SYS  ext4    plumOS releases and persistent Linux data
p8  userdata        PLUMOS      FAT32   ROM, BIOS, update inbox, and exports
```

p6 must not be reused as the general plumOS runtime. On the current image it is
small, boot-related, and mounted read-only at `/boot`. Mixing high-churn
application data into that boot-critical filesystem would create a new failure
boundary.

p7 returns `rootfs_data` to a Linux-native filesystem, which also resembles the
original StockOS observation more closely than the current development FAT32
format. p8 is added after p7 so it can be the final expandable partition on
larger SD cards.

Candidate sizes:

```text
p7 ext4: minimum 4 GiB, target 8 GiB pending payload and rollback sizing
p8 FAT32: small image-build minimum, then expand to the remaining card capacity
```

The current generated app layer is about 1.1 GiB. p7 must have room for the
active release, one previous release, staging overhead, persistent settings,
Pyxel environments, PortMaster state, and filesystem reserve. Exact sizing is
an open decision because a larger fixed p7 also increases the minimum image
size and SD flashing time.

## Mount and Path Contract

Proposed mounts:

```text
/dev/mmcblk0p7  -> /mnt/plumos       ext4
/dev/mmcblk0p8  -> /mnt/plumos-user  vfat
```

The ext4 runtime layout is:

```text
/mnt/plumos/releases/VERSION/    immutable installed release payload
/mnt/plumos/current              symlink to the active release
/mnt/plumos/previous             symlink or recorded previous release
/mnt/plumos/staging/             incomplete update extraction
/mnt/plumos/data/config/         user-editable configuration
/mnt/plumos/data/state/          FE state, favorites, recent, and resume data
/mnt/plumos/data/Saves/          game saves
/mnt/plumos/data/States/         save states
/mnt/plumos/data/venvs/          user-installed Python environments
/mnt/plumos/data/portmaster/     PortMaster persistent state and installed ports
/mnt/plumos/update-state/        installed package hashes and health markers
```

Stable compatibility paths may be symlinks or bind mounts on ext4:

```text
/mnt/plumos/bin       -> current/bin
/mnt/plumos/lib       -> current/lib
/mnt/plumos/cores     -> current/cores
/mnt/plumos/frontend  -> current/frontend
/mnt/plumos/config    -> data/config
/mnt/plumos/Saves     -> data/Saves
/mnt/plumos/States    -> data/States
```

The FAT32 user-data layout is:

```text
/mnt/plumos-user/roms/
/mnt/plumos-user/bios/
/mnt/plumos-user/updates/
/mnt/plumos-user/exports/
/mnt/plumos-user/screenshots/    optional user-visible output
```

The normal runtime may bind the FAT32 content into existing application paths:

```text
/mnt/plumos-user/roms  -> /mnt/plumos/roms
/mnt/plumos-user/bios  -> /mnt/plumos/bios
```

Using `roms/plumos/update.tar.gz` is not preferred because it can collide with
ROM scanning and system-directory rules. A dedicated FAT32-root update inbox is
clearer:

```text
/updates/plumos-v90s-app-0.2.0.tar.gz
```

SD2 may continue to override or provide ROM and BIOS content. It must not be
required to locate the application runtime or the update state database.

## Application Update Package

The proposed release name is versioned and target-specific:

```text
plumos-v90s-app-0.2.0.tar.gz
```

A generic permanent name such as `update.tar.gz` is not sufficient because it
makes version identification, duplicate detection, and recovery ambiguous.

Each package must provide authenticated metadata before its payload is trusted:

```text
package format version
plumOS version
device ID: powkiddy-v90s
architecture: aarch64
vendor runtime ID: v90s-stockos-r1
minimum and maximum compatible system-rootfs ABI
allowed source versions or migration range
uncompressed size and required free space
payload file manifest and SHA-256 values
configuration migration version
package signature
```

A checksum stored only inside the same untrusted archive is not sufficient to
authenticate a public release. The updater should verify a plumOS release
signature using a public key embedded in the read-only system rootfs.

Archive extraction must reject:

- absolute paths
- `..` path traversal
- device nodes and unexpected special files
- symlinks or hardlinks that escape the staged release root
- ownership, mode, or path entries not allowed by the package manifest
- payloads larger than their declared limit

The archive preserves executable bits and symlinks that FAT32 cannot represent
when files are copied individually. The FAT32 4 GiB single-file limit still
applies to the compressed package.

## Frontend Update Flow

The frontend should expose a `System Update` action that scans only the
dedicated FAT32 update inbox.

Before confirmation it should show:

```text
installed version
package version
system-rootfs compatibility
required and available ext4 space
signature and checksum result
whether rollback space is available
```

After confirmation, the frontend must switch to a non-interactive progress
screen. Normal navigation, volume, power, and quit input remain disabled until
the updater returns success or a recoverable failure.

The actual privileged updater must live in the read-only system SquashFS, for
example:

```text
/usr/sbin/plumos-system-update
```

The update must not depend on the application release that it is replacing.
The updater should own process shutdown, filesystem synchronization, release
switching, rollback metadata, and frontend restart.

## Transactional Installation

The updater should use this sequence:

1. Locate a selected package under `/mnt/plumos-user/updates`.
2. Read and verify signed metadata before extraction.
3. Verify device, architecture, vendor runtime, rootfs ABI, source version, and
   free-space requirements.
4. Extract into `/mnt/plumos/staging/VERSION.partial` without changing
   `/mnt/plumos/current`.
5. Verify every extracted file against the signed manifest.
6. Flush regular files, directories, and staging metadata to ext4.
7. Rename the complete staging tree to `/mnt/plumos/releases/VERSION`.
8. Stop frontend, emulator, FTP, Samba, and other update-sensitive writers by
   their owned process contracts. Keep an intentional recovery transport when
   safe to do so.
9. Run versioned, idempotent configuration migrations against persistent data.
10. Create `current.new` and atomically rename it over `current`.
11. Record the previous release and pending boot-health state durably.
12. Restart the frontend from the new release or reboot when required.
13. Mark the release healthy only after the frontend reaches its ready state.

The previous complete release should be retained until the new release has
passed its health check. Old releases may be removed later through an explicit
cleanup step, not during the critical switch.

## Failure and Rollback Contract

Expected behavior:

| Failure point | Required result |
| --- | --- |
| Incomplete FAT32 copy | Signature/hash validation rejects the package |
| Insufficient ext4 space | Reject before stopping the frontend |
| Extraction failure | Delete or ignore `.partial`; current release unchanged |
| Power loss during extraction | Current release unchanged |
| Manifest mismatch | Current release unchanged; preserve diagnostic result |
| Failure before current switch | Previous release remains active |
| Failure immediately after switch | Boot health logic selects previous release |
| New FE fails readiness check | Mark failed and offer or perform rollback |
| FAT32 user partition damaged | ext4 runtime and recovery UI can still boot |
| ext4 runtime damaged | system SquashFS reports recovery mode; do not rewrite blindly |

Applied-package identity should be recorded on ext4 using the package hash.
The updater does not need to rename or delete the archive on FAT32. This avoids
an unnecessary FAT write and prevents the same package from being reapplied.

## Persistent Data and Configuration Migration

Release archives must never replace user-owned settings, saves, states, or ROM
content as ordinary payload files.

Configuration migrations must be:

- versioned
- idempotent
- limited to known configuration keys and paths
- backed up before destructive conversion
- compatible with rollback, or explicitly marked as non-rollbackable before
  the user confirms the update

Transient logs and caches should remain under `/run` whenever persistence is
not required. User-requested exports can be copied to FAT32 through a dedicated
frontend action.

## SquashFS Update Boundary

p5 is currently a raw SquashFS partition, not a normal file on a FAT32 volume.
Windows Explorer and macOS Finder cannot replace it by copying a file.

The mounted p5 backing partition must not be overwritten from the running OS.
Safe system-rootfs update options are:

1. Distribute a complete SD image for infrequent base-system releases.
2. Provide a PC-side partition updater that writes only p5 with strict device,
   partition, size, and hash checks.
3. Add an A/B SquashFS partition scheme and switch only after verifying the
   inactive image.
4. Add an updater to an earlier boot stage that writes p5 before p5 is mounted.

For the first implementation, normal application updates should change only
the ext4 runtime. The p5 SquashFS can remain fixed and be updated through a new
full SD image when the kernel-facing or base-system contract changes. A safer
partial p5 updater can be designed later; it is not required to validate the
ext4/FAT32 application update model.

## Build-System Impact

The current `app-layer` target builds a directly copyable FAT32 tree. The
candidate design needs distinct outputs:

```text
app-runtime       build one versioned ext4 release payload
update-package    build and sign the archive copied to FAT32
user-data-seed    build the initial FAT32 roms/bios/updates directory tree
sd-image          assemble p7 ext4 plus final p8 FAT32
release           publish full image, update package, signatures, and hashes
```

Existing component build targets remain unchanged. `frontend`, `retroarch`,
`cores`, `picoarch`, `standalone`, `userland`, and `network-services` feed the
new `app-runtime` output instead of a directly overwritten FAT32 tree.

Development ADB deployment should exercise the same staging and current-switch
contract as the release updater rather than restoring an unrelated in-place
overwrite path.

## Migration From Current Development Images

Changing current p7 from FAT32 to ext4 and adding p8 changes the partition and
mount contract. The first implementation should require a new SD image.

It should not attempt an in-place filesystem conversion on a user's only card.
Migration guidance must explicitly back up and restore:

```text
roms
bios
config
Saves
States
screenshots
PortMaster installations
Pyxel requirements and user environments when portable
```

The current FAT32 app-layer build and deploy path should remain available as a
development compatibility mode until the new image has equivalent real-device
video, audio, input, networking, update, rollback, and shutdown validation.

## Validation Plan

The first spike should prove only the storage and update contract:

1. Build a test image with p7 ext4 and p8 FAT32.
2. Boot with p7 at `/mnt/plumos` and p8 at `/mnt/plumos-user`.
3. Start the existing frontend through a `current` release symlink.
4. Launch one RetroArch game and verify save/config persistence on ext4.
5. Copy a signed test update archive to FAT32 from macOS.
6. Install it through a rootfs-owned updater and atomically switch releases.
7. Confirm FE restart and previous-release retention.
8. Interrupt extraction and confirm the active release remains unchanged.
9. Interrupt immediately after the release switch and confirm boot rollback.
10. Damage or remove p8 and confirm the ext4 runtime still reaches a recovery
    screen without rewriting the user partition.

Only after the spike passes should the Distribution Policy, TODO, release
workflow, image assembler, and normal app-layer target be changed.

## Open Decisions

- Whether p7 should be 4, 6, or 8 GiB by default.
- How the final p8 FAT32 partition expands to the SD card's remaining capacity.
- Whether screenshots and save exports live directly on FAT32 or require an
  explicit export action.
- Whether SD2 overrides p8 ROM/BIOS, merges with it, or is selected in FE.
- Whether update packages use gzip, zstd, or a plumOS-specific container.
- Which signing algorithm and key-rotation policy plumOS uses.
- Whether successful app updates restart only FE or always reboot.
- How many previous releases are retained.
- Whether failed boot health triggers automatic rollback or a recovery menu.
- Which configuration migrations are safe to roll back.
- How p5 SquashFS updates are delivered after the first release.
- Whether a p8 partition is accepted by the complete StockOS boot chain on real
  hardware without side effects.

