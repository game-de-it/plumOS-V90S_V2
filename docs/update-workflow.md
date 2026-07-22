# plumOS V90S Update Workflow

This is the developer workflow for the adopted signed update system. End users
follow the shorter [System Updates](user/updates.md) manual.

## Update Types

- Runtime Update: transactional update of plumOS-managed p3 ext4 files
- System Update: complete read-only System SquashFS written to the inactive p1
  A/B slot

The fixed StockOS-derived boot0, boot package, kernel, DTB, p2 initramfs, and
matching vendor modules are not normal update targets. Change them only in a
new fully validated SD image.

## Prepare Build Inputs

Build a complete strict app layer and the matching System SquashFS version:

```sh
PLUMOS_V90S_APP_LAYER_VERSION=NEW \
  ./scripts/docker-build.sh app-layer --strict

PLUMOS_V90S_SYSTEM_VERSION=NEW \
  ./scripts/docker-build.sh system-rootfs

./scripts/docker-build.sh license-audit output/app-layer/v90s
```

The Runtime input must have `manifest.json.complete=true`, no
`missing_optional` entries, correct `COMPAT_VENDOR`, and a complete
`checksums.sha256`. The System embedded version must equal the System package
target version.

## Signing Key

The tracked verification key is:

```text
package/system-v90s/plumos-update-public.pem
```

Keep the Ed25519 private key only at the ignored local path:

```text
artifacts/update-signing/plumos-v90s-ed25519-private.pem
```

Never commit or place the private key in an app layer, image, log, or release
archive.

## Build a Runtime Update

```sh
./scripts/docker-build.sh update-package \
  --type runtime \
  --input output/app-layer/v90s \
  --base-dir PATH/TO/PREVIOUS/RUNTIME \
  --base-version OLD \
  --version NEW \
  --output-dir dist/updates
```

The base directory is required to calculate managed additions, replacements,
and deletions while excluding mutable device-owned paths.

## Build a System Update

```sh
./scripts/docker-build.sh update-package \
  --type system \
  --input output/system-rootfs/v90s/plumos-v90s-system-rootfs.squashfs \
  --base-version OLD \
  --version NEW \
  --output-dir dist/updates
```

## Host Delivery

Copy the signed `.tar.gz` archive without extracting it to:

```text
PLUMOS:/updates/
/mnt/plumos-user/updates/
```

The frontend scans this inbox from `System Settings -> System Update`, verifies
all candidates, selects the newest compatible signed package, records the
request under p3, and enters the safe reboot path.

## Boot-Time Application

The updater runs from System SquashFS before FE and normal network writers.
Runtime packages use staging, a write-ahead rollback journal, atomic renames,
and renderer-ready health confirmation. System packages write and read back the
inactive p1 slot, commit pending-slot state, and boot it once. Missing health
proof causes rollback on the next boot.

Exactly one Runtime backup and two fixed System slots are retained. Stale
updater staging is removed. Archives in p4 remain user-managed.

## Diagnostics

On device:

```sh
plumos-system-update scan
plumos-system-update inspect /mnt/plumos-user/updates/PACKAGE.tar.gz
```

Persistent update state and full logs remain on p3. The bounded host-readable
failure summary is copied to:

```text
/mnt/plumos-user/plumos-logs/update/
```

For package format, trust checks, path rejection, journaling, A/B state, and
retention rules, see the [Update Contract](plumos-v90s-update-contract.md).
