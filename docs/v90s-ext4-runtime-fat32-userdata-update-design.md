# plumOS V90S ext4 Runtime and FAT32 User-Data Update Design

Date: 2026-07-18
Status: Historical design input. The implemented update contract is now
`docs/plumos-v90s-update-contract.md`.

## Purpose

This document records a candidate four-partition replacement for the current
StockOS-compatible seven-partition layout and FAT32 app layer. It is intended
to preserve easy Windows/macOS updates, reduce removable-media enumeration
overhead, and move frequently changed plumOS applications and persistent state
onto ext4.

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
p1  FAT16     PLUMBOOT boot resources
p2  raw       env
p3  raw       env-redund
p4  raw       Android boot image
p5  squashfs  read-only Linux system
p6  ext4      BATOCERA, mounted read-only at /boot
p7  FAT32     PLUMOS app, update, configuration, and data layer
```

The current FAT32 design remains supported until this proposal is implemented
on a separate development path and validated on V90S hardware.

## Goals

- Keep ROM, BIOS, and update transfer accessible from Windows and macOS.
- Expose only `PLUMBOOT` and `PLUMOS` as mountable host volumes.
- Reduce the GPT layout from seven StockOS-compatible partitions to four
  plumOS-owned partitions.
- Store executable files, libraries, symlinks, permissions, settings, and saves
  on a native Linux filesystem.
- Make an interrupted application update leave the previous release bootable.
- Keep user settings and saves separate from replaceable release payloads.
- Allow one-step frontend updates with progress and an input-locked screen.
- Keep the StockOS-derived kernel, GPU, audio, input, boot0, and boot-package
  hardware contract while simplifying its partition policy.
- Keep the Android boot payload raw and independent of the FAT filesystems.
- Retain a recovery path when either the application update or FAT32 user area
  is damaged.

## Non-Goals

- This proposal does not replace the vendor kernel or low-level boot0 hardware
  initialization.
- It does not make arbitrary power loss harmless to a file actively being
  written.
- It does not permit overwriting the active SquashFS while it is mounted.
- It does not require online updates or a permanent package-manager daemon.
- It does not make SD2 mandatory for normal SD1-only operation.

## Proposed Partition Layout

The low-level Allwinner boot0 and boot package remain at their required raw
offsets before the GPT partitions. They are not exposed as partitions.

The agreed candidate SD1 layout is:

```text
raw boot area                  observed about 20.5 MiB before p1
p1  PLUMBOOT    FAT    1024 MiB       boot assets and versioned system SquashFS
p2  BOOT        raw      64 MiB       Android boot image: kernel, DTB, initramfs
p3  PLUMOS_SYS  ext4   1600 MiB seed  expand to 8192 MiB on first boot
p4  PLUMOS      FAT32  not in seed    create through the final usable SD sector
```

`1 GiB` and `8 GiB` in release tooling mean exactly `1024 MiB` and `8192 MiB`.
The compact seed image contains only p1-p3. Its expected logical size is about
2.64 GiB including the raw boot area, alignment, and GPT metadata. p4 is absent
until first-boot provisioning succeeds.

### PLUMBOOT

p1 keeps the bootloader-visible boot resources and adds versioned system images:

```text
/bootlogo.bmp
/System/system-a.squashfs
/System/system-a.manifest
/System/system-a.sig
/System/system-b.squashfs
/System/system-b.manifest
/System/system-b.sig
/Logs/                         bounded early-boot diagnostics when required
```

The filesystem may remain FAT16 for the first compatibility spike or move to
FAT32 after bootlogo and boot-package validation. Windows and macOS must mount
it as `PLUMBOOT`. A normal update writes only the inactive SquashFS slot.

The current system SquashFS is about 92.05 MiB, so two slots consume about
184.1 MiB before manifests and signatures. The 1024 MiB allocation deliberately
leaves substantial growth and recovery-package space. The image builder must
calculate both signed slot sizes and reject a release that cannot fit without
the required free-space margin.

### BOOT

p2 is the raw Android boot image and contains the vendor kernel, matching DTB,
and a plumOS-owned initramfs. It keeps the kernel payload outside FAT so an
ordinary host-side file operation cannot accidentally replace it.

The captured Android boot header describes about 12.49 MiB of kernel and
2.99 MiB of ramdisk, or about 15.48 MiB including page alignment and the boot
header. p2 remains 64 MiB so the initramfs can add GPT, ext4, FAT, signature,
framebuffer, input, and recovery tooling without immediately changing the
partition contract. The build must fail when the complete generated Android
boot image exceeds 64 MiB.

The current separate `env` and `env-redund` partitions are not carried into the
candidate layout. Their current values include a hard-coded
`mmc_root=/dev/mmcblk0p6`, so deleting them without changing the boot package
would not work. The candidate boot package must provide a fixed default
environment that loads the GPT partition named `boot` and lets the initramfs
select the system root by label and signed metadata. User settings must never
require U-Boot `saveenv`.

### PLUMOS_SYS

p3 is the Linux-native device-managed area. It contains application releases,
configuration, active saves and states, update staging, rollback metadata,
PortMaster, Python environments, and other data that requires POSIX semantics.

The current runtime payload is about 1.29 GiB. The release image carries a
1600 MiB ext4 p3 and the image build must verify that at least 256 MiB remains
free after seeding it. p3 is expanded to exactly 8192 MiB in the p2 initramfs
before p4 is created. This avoids making the downloadable and flashed raw image
as large as the final ext4 runtime allocation.

### PLUMOS

p4 does not exist in the distributed seed image. First-boot provisioning
creates it as the final GPT partition, formats it as FAT32, and extends it to
the final usable sector of the physical SD card. It is the user-managed area
for ROMs, BIOS, artwork, themes, screenshots, media, updates, imports, and
exports.

Windows and macOS should see only `PLUMBOOT` and `PLUMOS`. p2 is raw and p3 uses
a Linux filesystem, so neither should receive a host drive letter. Before the
first successful device boot, only `PLUMBOOT` exists as a host-mountable volume;
release instructions must require one V90S provisioning boot before the user
copies ROMs from a PC.

### Removed StockOS Partitions

The old p6 `BATOCERA` partition is not the Linux system root despite its
StockOS `rootfs` name. The validated runtime mounts it read-only at `/boot`,
while the old p5 SquashFS is mounted at `/overlay/base`. Its captured payload is
approximately 48 KiB and contains only Batocera boot configuration, board/vendor
identifiers, preinstall defaults, and small boot hook scripts.

The four-partition design moves any still-required early defaults into the
initramfs or signed system root and removes the hard-coded p6 dependency. The
old p5 raw SquashFS partition is also removed because the system SquashFS files
now live under p1 `PLUMBOOT`.

The old p2/p3 environment redundancy is replaced by an immutable boot-package
default. This saves little space, but removes two GPT entries and avoids a
writable bootloader policy that plumOS does not need.

## Boot Flow and Recovery Contract

The candidate boot flow is:

```text
boot0
  -> boot_package / U-Boot fixed environment
  -> p2 BOOT kernel and initramfs
  -> provision or resume physical-card layout when incomplete
  -> mount p1 PLUMBOOT read-only
  -> verify selected SquashFS manifest and signature
  -> loop-mount system-a or system-b
  -> mount p3 PLUMOS_SYS
  -> construct required tmpfs/overlay mounts
  -> switch_root
  -> start plumOS runtime and frontend
```

Slot choice and boot-health state should be recorded on ext4. If p3 cannot be
mounted, the initramfs uses a documented default slot and enters recovery
rather than modifying either FAT filesystem blindly. If the selected system
slot fails verification or readiness, the previous verified slot is tried.

The p2 initramfs must contain enough framebuffer, input, storage, signature,
and diagnostic support to show a recovery screen when neither SquashFS slot can
boot. It must not depend on frontend or emulator files from p3.

## First-Boot Provisioning Contract

The compact release image contains only p1-p3. The minimum supported physical
SD-card capacity is 16 GB. Provisioning runs from the p2 initramfs before p1,
p3, or a system SquashFS is mounted for normal operation.

On every boot, the initramfs inspects the physical parent device and the actual
GPT/filesystem geometry. A completion marker is advisory; geometry is the
source of truth. When provisioning is incomplete, the initramfs performs or
resumes these operations in order:

1. Resolve the physical SD device without assuming it is `mmcblk0` and verify
   that it is at least 16 GB.
2. Validate the expected p1-p3 identities, starts, sizes, and seed-image
   manifest. Stop in recovery if an unexpected layout could contain user data.
3. Relocate the backup GPT header and table from the end of the seed image to
   the final usable sectors of the physical SD card.
4. Grow the p3 partition entry from 1600 MiB to exactly 8192 MiB without
   changing its start sector.
5. Ask the kernel to reread the partition table while no seed partition is
   mounted, and stop in recovery if the new geometry is not visible.
6. Run `e2fsck` on p3 and then `resize2fs` so the ext4 filesystem fills the
   8192 MiB partition.
7. Create p4 on the next 1 MiB-aligned sector and extend it through the final
   usable GPT sector.
8. Format a newly created p4 as FAT32 with filesystem label `PLUMOS`.
9. Mount p1 read-only, verify and loop-mount the selected system SquashFS, then
   mount p3 and p4. Create the portable user-data tree and copy any signed seed
   content that is absent from p4.
10. Flush file contents, filesystem metadata, and block-device state before
    recording completion.
11. Revalidate all four partitions, labels, target sizes, and seed-manifest
    hashes before continuing the normal boot flow.

The read-only system SquashFS provides the versioned seed at:

```text
/usr/share/plumos/userdata-seed/
```

It creates the exact p4 top-level directories documented below, including
`roms`, `bios`, `Images`, `Themes`, `updates`, `imports`, and `exports`. The
seed has its own manifest so provisioning can copy only missing distribution
files and never replace user content during a resume.

Durable progress is recorded on p3 after ext4 is available:

```text
/mnt/plumos/provision/state
/mnt/plumos/provision/gpt-expanded
/mnt/plumos/provision/ext4-resized
/mnt/plumos/provision/p4-formatted
/mnt/plumos/provision/userdata-seeded
/mnt/plumos/provision/complete
```

While p4 is being initialized it contains `/.plumos-provisioning`. That marker
is replaced by `/.plumos-ready` only after the directory tree, copied files,
and FAT metadata have been flushed successfully.

Every operation must be idempotent and safe to repeat after power loss. If p4
already exists, provisioning runs FAT filesystem repair and resumes from the
observed geometry and manifests. It must never blindly format an existing p4
that contains an unknown layout or user files. An ambiguous or failed step
shows the initramfs recovery screen and must not partially launch the frontend.

After geometry, filesystem state, `/mnt/plumos/provision/complete`, and
`/.plumos-ready` agree that provisioning is complete, the normal boot path must
not rerun `resize2fs`, rewrite provisioning markers, or reseed the p4 directory
tree. It may still perform bounded filesystem checks and verify the selected
system SquashFS. Normal boot uses a normal boot screen and `last-boot.log`; the
original `first-boot.log` is immutable diagnostic evidence and must not be
replaced on later boots.

## Mount and Path Contract

Proposed mounts:

```text
/dev/mmcblk0p1  -> /mnt/plumos-boot  vfat, normally read-only on device
/dev/mmcblk0p3  -> /mnt/plumos       ext4
/dev/mmcblk0p4  -> /mnt/plumos-user  vfat
```

p2 is consumed as an Android boot image and is not mounted by the running
system. Runtime code must resolve partitions by GPT name, filesystem label,
UUID, or signed metadata rather than assuming that the device is always
`mmcblk0`.

The ext4 runtime is the device-managed area. It contains data that users do not
normally manipulate from Windows or macOS, including executable payloads,
Linux-specific state, active saves, and update metadata:

```text
/mnt/plumos/releases/VERSION/    immutable installed release payload
/mnt/plumos/current              symlink to the active release
/mnt/plumos/previous             symlink or recorded previous release
/mnt/plumos/staging/             incomplete update extraction
/mnt/plumos/data/config/         user-editable configuration
/mnt/plumos/data/state/          FE state, favorites, recent, and resume data
/mnt/plumos/data/Saves/          game saves
/mnt/plumos/data/States/         save states
/mnt/plumos/data/Saves-backup/   automatic pre-import save backups
/mnt/plumos/data/venvs/          user-installed Python environments
/mnt/plumos/data/portmaster/     PortMaster persistent state and installed ports
/mnt/plumos/data/cache/          runtime caches that require Linux semantics
/mnt/plumos/data/logs/           persistent diagnostics when explicitly retained
/mnt/plumos/update-state/        installed package hashes and health markers
```

The ext4 area should also hold:

- frontend, RetroArch, libretro cores, PicoArch, standalone emulators, and their
  private libraries
- the minimal fallback theme, font, and assets required to reach a
  recovery-capable frontend without the FAT32 partition
- RetroArch configuration, core options, remaps, overrides, and generated
  playlists
- Wi-Fi credentials, SSH keys, network-service configuration, and other
  security-sensitive state
- PortMaster itself and installed ports that rely on executable bits, symlinks,
  case-sensitive paths, or many small files
- Python virtual environments and installed modules
- frontend ROM indexes, scraper databases, favorites, recent-game state, and
  other frequently rewritten metadata

Transient logs and caches should remain under `/run` where persistence is not
required. Persistent logs are kept on ext4 and copied to FAT32 only through an
explicit diagnostic export action.

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

The FAT32 user-data partition is the user-managed interchange area. Its exact
top-level directory names are:

```text
/mnt/plumos-user/roms/
/mnt/plumos-user/bios/
/mnt/plumos-user/Images/
/mnt/plumos-user/Themes/
/mnt/plumos-user/Screenshots/
/mnt/plumos-user/Music/
/mnt/plumos-user/Manuals/
/mnt/plumos-user/Cheats/
/mnt/plumos-user/Patches/
/mnt/plumos-user/Shaders/
/mnt/plumos-user/updates/
/mnt/plumos-user/imports/
/mnt/plumos-user/exports/
```

These directories have the following responsibilities:

| Directory | User-visible content |
| --- | --- |
| `roms/` | ROMs, disc images, multidisc playlists, and data-only game projects |
| `bios/` | BIOS and firmware supplied by the user |
| `Images/` | Scraped box art and other game artwork shared with A30/MMF layouts |
| `Themes/` | Portable bundled themes, user themes, artwork, and theme fonts |
| `Screenshots/` | Screenshots and user-requested captures |
| `Music/` | Music Player content |
| `Manuals/` | Manuals and other user-managed game documents |
| `Cheats/` | User-installed cheat databases and per-game cheats |
| `Patches/` | IPS, BPS, xdelta, translation, and other ROM patches |
| `Shaders/` | User-installed shader presets, overlays, borders, and bezels |
| `updates/` | Signed plumOS application update packages |
| `imports/` | Files staged by the user for an explicit FE import operation |
| `exports/` | Saves, settings, states, and diagnostics exported by plumOS |

Only the minimal assets required for recovery remain on ext4. Normal bundled
themes and user themes live together in FAT32 `Themes/` so they can be reused
across plumOS devices. The frontend may merge FAT32 `Shaders/` and similar user
additions over read-only runtime defaults, but a missing or damaged FAT32
partition must not prevent the recovery UI from starting.

The normal runtime may bind the FAT32 content into existing application paths:

```text
/mnt/plumos-user/roms  -> /mnt/plumos/roms
/mnt/plumos-user/bios  -> /mnt/plumos/bios
/mnt/plumos-user/Images -> /mnt/plumos/Images
/mnt/plumos-user/Themes -> /mnt/plumos/themes-user
```

Compatibility paths must be created by the mount/runtime policy rather than by
duplicating files across filesystems. The canonical ROM and BIOS directory
names remain lowercase. Capitalized names above intentionally follow the
portable A30/MMF user-content convention.

Using `roms/plumos/update.tar.gz` is not preferred because it can collide with
ROM scanning and system-directory rules. A dedicated FAT32-root update inbox is
clearer:

```text
/updates/plumos-v90s-app-0.2.0.tar.gz
```

SD2 may continue to override or provide ROM and BIOS content. It must not be
required to locate the application runtime, boot slot, or update state database.

## Save Import and Export Contract

Active game saves live on ext4 so that normal emulator writes receive native
Linux filesystem durability. FAT32 is used only as the interchange surface:

```text
active saves:  /mnt/plumos/data/Saves/SYSTEM_ID/
active states: /mnt/plumos/data/States/SYSTEM_ID/
save imports:  /mnt/plumos-user/imports/Saves/SYSTEM_ID/
save exports:  /mnt/plumos-user/exports/Saves/SYSTEM_ID/
state exports: /mnt/plumos-user/exports/States/SYSTEM_ID/
```

`SYSTEM_ID` is the lowercase frontend system ID, not one of its ROM-directory
aliases. For SNES/Super Famicom the ID is `sfc`, even when the ROM is stored in
`roms/SFC`, `roms/sfc`, or `roms/snes`.

For example:

```text
ROM on FAT32:
/mnt/plumos-user/roms/SFC/Super Mario World (Japan).sfc

User-provided import on FAT32:
/mnt/plumos-user/imports/Saves/sfc/Super Mario World (Japan).srm

Installed active save on ext4:
/mnt/plumos/data/Saves/sfc/Super Mario World (Japan).srm
```

An exact system ID and ROM basename match may be offered as the default import
target. It must still pass a confirmation screen before replacing an active
save. A fuzzy filename match may order candidates but must never authorize an
automatic replacement.

If the save filename does not match a ROM basename, the frontend should reuse
its normal ROM browser in `Import Destination` mode:

1. The user selects an unmatched save in the Save Import app.
2. The frontend opens the ROM list for that `SYSTEM_ID` with the most likely
   candidates first and the normal thumbnail/list presentation.
3. `A` selects a destination instead of launching the game; `B` cancels.
4. The confirmation screen shows source save, selected game, final filename,
   existing-save size/date, and backup behavior.
5. The importer copies the source into an ext4 sibling temporary file, verifies
   its hash and expected size, flushes it, backs up an existing target, and
   atomically renames the new save into place.
6. The FAT32 source remains unchanged. Its hash is recorded on ext4 to prevent
   accidental repeated imports; the user may remove it later from a PC.

The target emulator session must not be running during import. Exported saves
should include a small manifest containing system ID, ROM path and hash,
emulator/profile, save type, filename, size, and checksum. Imports from another
device may omit that manifest and fall back to exact-name or manual ROM
selection.

The first implementation should support ordinary battery/SRAM saves such as
SNES `.srm`. Save states are a separate import operation because they are often
specific to an emulator core and version; they must never be treated as
portable merely because their filename matches.

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

## System SquashFS Update Contract

The current release image uses a raw p5 SquashFS partition. The candidate
layout replaces it with signed A/B SquashFS files on p1 `PLUMBOOT` so Windows
Explorer and macOS Finder can install a base-system update without rewriting a
raw partition or the entire SD image.

A normal host-side system update must use a versioned inactive-slot package:

```text
/System/system-b.squashfs
/System/system-b.manifest
/System/system-b.sig
```

when slot A is active, or the corresponding slot A files when B is active. The
user must never be instructed to overwrite the currently active file.

The p2 initramfs owns the trust and rollback boundary:

1. Mount `PLUMBOOT` read-only.
2. Read the requested slot from durable ext4 boot state when available.
3. Verify device ID, system ABI, complete image hash, and release signature.
4. Reject an incomplete or oversized FAT file before loop attachment.
5. Loop-mount the verified SquashFS read-only.
6. Boot it with a pending-health marker.
7. Mark it healthy only after the expected runtime/frontend readiness proof.
8. Select the previous verified slot after a failed readiness check.

FAT32 is only the container for immutable signed images. The active image must
not be modified from the running device. A kernel, DTB, initramfs, boot0, or
boot-package update remains outside this ordinary file-copy flow and requires a
full image or a separately validated boot updater.

## Build-System Impact

The current `app-layer` target builds a directly copyable FAT32 tree. The
candidate design needs distinct outputs:

```text
boot-package      prepare the fixed U-Boot environment for the four-part layout
boot-image        build p2 kernel/DTB/initramfs Android boot payload
system-rootfs     build and sign the p1 A/B SquashFS payload
app-runtime       build one versioned p3 ext4 release payload
update-package    build and sign the app archive copied to p4
user-data-seed    build the initial p4 portable-content directory tree
sd-image          assemble the compact p1/p2/p3 provisioning image
release           publish full image, update packages, signatures, and hashes
```

Existing component build targets remain unchanged. `frontend`, `retroarch`,
`cores`, `picoarch`, `standalone`, `userland`, and `network-services` feed the
new `app-runtime` output instead of a directly overwritten FAT32 tree.

The image assembler must not inherit the old p2/p3 env, p5 raw SquashFS, or p6
BATOCERA partitions. It must fail if the boot package still contains the old
`mmc_root=/dev/mmcblk0p6` contract or if the generated p1 cannot contain both
signed system slots within the selected capacity.

The `sd-image` output is a compact provisioning seed with p1 exactly 1024 MiB,
p2 exactly 64 MiB, p3 exactly 1600 MiB, and no p4 partition. Its build manifest
records at least:

```text
p1_seed_mib=1024
p2_mib=64
p3_seed_mib=1600
p3_target_mib=8192
p3_minimum_free_mib=256
minimum_sd_gb=16
```

Assembly must fail if the complete Android boot image exceeds p2, both signed
SquashFS slots and their metadata do not fit p1, or seeded p3 free space is less
than 256 MiB. The p2 initramfs includes the provisioning tools, while the
signed system root supplies the user-data seed and manifest. p4 is created only
on the physical V90S and therefore is not represented as an empty partition in
the downloadable image.

Development ADB deployment should exercise the same staging and current-switch
contract as the release updater rather than restoring an unrelated in-place
overwrite path.

## Migration From Current Development Images

Changing from the current seven-partition StockOS layout to the four-partition
plumOS layout changes bootloader environment, initramfs, partition numbering,
filesystems, and mount contracts. It requires a new full SD image.

It should not attempt an in-place filesystem conversion on a user's only card.
Migration guidance must explicitly back up and restore:

```text
FAT32: roms, bios, Images, Themes, Screenshots, Music, custom content
ext4:  config, Saves, States, frontend state, and update state
ext4:  PortMaster installations and Pyxel environments when portable
```

The current FAT32 app-layer build and deploy path should remain available as a
development compatibility mode until the new image has equivalent real-device
video, audio, input, networking, update, rollback, and shutdown validation.

## Validation Plan

The first spike should prove only the new boot and storage contract:

1. Build a compact p1-p3 seed while preserving known-good boot0 and hardware
   initialization inputs, and verify exact 1024/64/1600 MiB capacities.
2. Insert the seed into a 16 GB or larger card and boot p2 with a fixed
   environment that has no p6 or external-env dependency.
3. Verify first boot relocates the backup GPT, expands p3 to exactly 8192 MiB,
   and creates p4 through the physical card's final usable sector.
4. Verify p4 is FAT32 label `PLUMOS`, contains the complete seed tree, and has a
   durable `/.plumos-ready` marker.
5. Interrupt power separately after GPT relocation, p3 partition growth, ext4
   resize, p4 format, and user-data seeding; confirm each image resumes without
   reformatting user content.
6. Mount p1 and loop-mount a signed test SquashFS from `System/`.
7. Mount p3 at `/mnt/plumos`, mount p4 at `/mnt/plumos-user`, and start the
   existing frontend through `current`.
8. Launch one RetroArch game and verify save/config persistence on ext4.
9. Boot once from each signed SquashFS slot.
10. Corrupt the inactive slot and confirm the active slot still boots.
11. Fail the pending-slot readiness check and confirm rollback.
12. Damage or remove p4 and confirm p2 plus a verified system slot reaches a
    recovery screen without rewriting the user partition.
13. Insert an unprovisioned seed into Windows and macOS and confirm that only
    `PLUMBOOT` mounts. After one successful V90S boot, confirm that only
    `PLUMBOOT` and `PLUMOS` mount and record enumeration time on both hosts.

Only after the spike passes should the Distribution Policy, TODO, release
workflow, image assembler, and normal app-layer target be changed.

## Open Decisions

- Whether p1 `PLUMBOOT` remains FAT16 or moves to FAT32 after the compatibility
  spike.
- Which initramfs GPT/FAT/ext4 tool implementations are included to satisfy the
  fixed first-boot provisioning contract.
- Whether SD2 overrides p4 ROM/BIOS, merges with it, or is selected in FE.
- Whether update packages use gzip, zstd, or a plumOS-specific container.
- Which signing algorithm and key-rotation policy plumOS uses.
- Whether successful app updates restart only FE or always reboot.
- How many previous releases are retained.
- Whether failed boot health triggers automatic rollback or a recovery menu.
- Which configuration migrations are safe to roll back.
- Whether p2 boot updates are full-image-only or receive a separate signed
  updater after the four-partition baseline is stable.
