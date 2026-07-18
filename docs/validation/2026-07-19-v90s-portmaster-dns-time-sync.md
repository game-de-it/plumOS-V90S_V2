# V90S PortMaster Catalog DNS and Wi-Fi Time Sync Validation

Date: 2026-07-19

## Symptom

PortMaster opened from FE Apps, but `All Ports` contained only the bundled
fallback entries and no thumbnails were visible.

The live persistent state confirmed that no online catalog had completed:

```text
020_portmaster.source.json last_checked=null data={}
021_portmaster.multiverse.source.json last_checked=null data={}
images_pm=0
images_pmmv=0
```

## Root Cause

Wi-Fi had a valid address and default route:

```text
wlan0=192.0.2.120/24
default_gateway=192.0.2.1
```

The system SquashFS was read-only, however, and `/etc/resolv.conf` still held
the Docker build host resolver:

```text
nameserver 192.168.65.7
```

The DHCP hook could not replace it:

```text
cannot create /etc/resolv.conf: Read-only file system
```

PortMaster consequently failed before catalog or image retrieval with:

```text
Temporary failure in name resolution
```

The same DNS failure prevented the existing post-Wi-Fi
`plumos-time-sync sync` call from reaching `time.nist.gov`.

## Fix

- Added `plumos-dns-runtime` as the owner of
  `/run/plumos/network/resolv.conf`.
- Bind-mount that writable file over `/etc/resolv.conf` before rootfs network
  initialization.
- Let the app-layer `udhcpc` hook write lease-provided DNS through the runtime
  owner.
- For an already-connected interface, seed the resolver from the current
  default gateway and `1.1.1.1` fallback.
- Prepare DNS synchronously before starting the bounded background time sync.

This keeps DNS state in tmpfs and does not attempt to modify the read-only
SquashFS at runtime.

## PortMaster Result

After live deployment, `api.github.com` resolved through `192.0.2.1` and
PortMaster downloaded and persisted its catalog assets:

```text
ports_info.items=560
images_pm=1331
images_pmmv=37
featured_images=21
PNG/JPEG total=1386
```

The image cache occupied about 95 MB and remained under:

```text
/mnt/plumos/state/portmaster/config
```

After one cached restart, the user confirmed that the missing ports and
thumbnails were visible.

## Automatic Time Result

`automatic_time` remained enabled. Running the same `--wifi on` path used by
the FE against the existing connection started the bounded synchronization in
the background.

Before:

```text
system: Sat, 18 Jul 2026 20:35:38 +0900
time-sync state: failed
RTC offset: 1538 seconds
```

After:

```text
system: Sun, 19 Jul 2026 02:17:02 +0900
time-sync state: synced
source: time.nist.gov
RTC store: success, UTC
RTC offset: 4 seconds
```

PortMaster remained running throughout the Wi-Fi/time test. No frontend,
emulator, SSH, ADB, or unrelated process was stopped.

## Reproducible Build Result

The normal build entry points completed after the live test:

```text
./scripts/docker-build.sh network-services
./scripts/docker-build.sh app-layer --strict
./scripts/docker-build.sh system-rootfs
```

The network-services package passed all 261 SHA-256 entries, and the app layer
passed all 4,256 entries. The three deployed network files matched the app
layer exactly:

```text
plumos-dns-runtime      b32f7169914d83e57e8d32cc18633195865db337424cd615494c3b5be057cbd2
plumos-network-control 51c49de309344f5ee2159acda651ae2ee7c63e8d7ac6af27b362eb18f485eebb
plumos-udhcpc-script   bf582a5fbb009bc15ca5a3be40c78c68fccb9eaef59fb48c36d8a000e7e973e5
```

The generated system SquashFS was 92.05 MiB and passed its sidecar SHA-256.
Direct inspection of `/usr/sbin/init` inside the SquashFS confirmed that
`prepare_runtime_resolver` runs before FAT log and network initialization and
bind-mounts the writable resolver over `/etc/resolv.conf`.
