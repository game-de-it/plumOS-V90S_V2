# Storage and Updates

## Partition Contract

| Partition | Format | Initial size | Runtime role |
| --- | --- | ---: | --- |
| p1 `PLUMBOOT` | FAT16 | 1024 MiB | boot resources and fixed System A/B SquashFS slots |
| p2 `BOOT` | raw Android boot image | 64 MiB | fixed vendor kernel, DTB, provisioning initramfs |
| p3 `PLUMOS_SYS` | ext4 | 1600 MiB seed | expanded to 8192 MiB; app-layer and Linux state |
| p4 `PLUMOS` | FAT32 | absent in seed | created at first boot through the SD-card end |

The image also preserves vendor-required raw boot data before the GPT
partitions. p1 is normally mounted read-only at `/mnt/plumos-boot`, p3 at
`/mnt/plumos`, and p4 at `/mnt/plumos-user`.

## Directory Ownership

### p3 ext4

```text
/mnt/plumos/
  bin/ lib/ gnu/ cores/ standalone/ frontend/ apps/
  config/ factory-defaults/ state/ Saves/ States/ Logs/
  ssh/ samba/ python/ portmaster/ licenses/
  manifest.json checksums.sha256 VERSION COMPAT_VENDOR RUNTIME_ABI
```

This partition contains POSIX permissions, links materialized at runtime,
device-local settings, non-content-local saves from PicoArch and standalone
emulators, service credentials, and transactional update state. `Saves/` and
`States/` also remain RetroArch fallbacks when content-directory storage is
disabled. Runtime package management must not erase mutable subtrees.

### p4 FAT32

```text
/mnt/plumos-user/
  roms/ bios/ Images/ Themes/ Screenshots/ Music/
  Manuals/ Cheats/ Patches/ Shaders/
  updates/ imports/ exports/ plumos-logs/
```

At bootstrap, `roms`, `bios`, and `Images` are bound to their compatibility
paths under `/mnt/plumos`. The current RetroArch factory configuration sorts
saves and states below the active `roms/` by content-directory and core name, so
RA saves belong to p4 or the active SD2. USB Disk Mode exports the p4 block
device directly, not a loopback staging image.

### SD2

`plumos-sd2-content-mount` finds a FAT32 second card, runs bounded filesystem
repair, accepts case variants of root `roms` and `bios`, and bind-mounts them
over `/mnt/plumos/roms` and `/mnt/plumos/bios`. Stopping the helper restores the
p4 bindings. RA saves and states follow the active ROM root onto SD2. Images and
update archives remain on SD1 p4.

## Runtime Update Transaction

A signed Runtime package targets p3. The boot-time updater verifies signature,
device, architecture, vendor runtime, ABI, paths, file types, sizes, and
SHA-256 before mutation. It extracts into a `.partial` staging tree, rejects
user-owned paths, checks free space, then commits replacements through a
write-ahead rollback journal. `VERSION`, `manifest.json`, and
`checksums.sha256` are committed last.

An interrupted commit is rolled back before FE start. Exactly one previous
successful transaction backup is retained; older backup and stale staging
trees are deleted before the next transaction. Health is confirmed only after
the FE writes renderer-ready proof.

## System Update Transaction

A signed System package contains one complete SquashFS. The updater stages and
hashes it on p3, remounts p1 writable only for the operation, writes the inactive
slot under a temporary name, flushes it, reads the complete image back, verifies
SHA-256, atomically commits slot metadata, restores p1 read-only, and reboots.

The initramfs boots a pending slot once. FE renderer readiness promotes it. A
second boot without readiness rejects the pending slot and selects the previous
active slot. Storage remains bounded to two fixed slot images.

## Package Format and Trust

Both package types are `.tar.gz` archives with:

```text
META/manifest.json
META/manifest.sig
payload/...
```

The Ed25519 signature covers the canonical manifest. Production FE updates
never enable unsigned mode. The fixed vendor kernel, DTB, boot0, boot package,
and p2 initramfs are full-image-only changes.

## USB Disk Mode Safety

Before exporting p4, the controller releases content bindings, stops conflicting
FTP/SFTP/Samba writers, unmounts p4, and gives its block device to USB mass
storage with write-through semantics. On return, it runs `fsck.fat`, refuses a
failed check, remounts p4, restores bindings, and restarts only previously
enabled services. ADB and mass storage use the same gadget path and are
exclusive.

See the [update contract](../plumos-v90s-update-contract.md) for transaction and
recovery details.
