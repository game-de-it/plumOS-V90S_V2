# V90S boot speed fixes

Date: 2026-07-11

## Goal

Resolve the boot-time blockers found in
`docs/validation/2026-07-11-fe-startup-latency-audit.md`.

The desired behavior is:

- show the frontend as early as possible;
- do not block the first visible UI on Wi-Fi association, DHCP, FTP/SFTP/Samba,
  or SD2 FAT fsck;
- keep diagnostic behavior available only through explicit opt-in.

## Fixes

### Frontend-first init order

Changed the generated Debian init in `scripts/build-step1-rootfs.sh`:

- PowerVR probe now starts in the background.
- The old rootfs-level `v90s-network-ssh-init` now starts in the background.
- `/mnt/plumos` app layer is mounted as soon as possible.
- `plumos-frontend-launch` starts before app-layer network services.
- `plumos-network-services start-enabled` now runs in the background after the
  frontend is started.
- PID 1 waits on the frontend PID so the UI remains the primary foreground
  lifetime, while background services can finish independently.

Expected new boot markers:

```text
debian-init: starting PowerVR probe in background
debian-init: starting network/SSH init in background
debian-init: starting plumOS frontend
debian-init: plumOS frontend pid=...
debian-init: starting enabled plumOS network services in background
debian-init: waiting for plumOS frontend pid=...
```

### SD2 boot fsck no longer blocks FE

Changed generated `plumos-frontend-launch` in `scripts/build-frontend.sh`.

The frontend launcher still mounts SD2 before drawing by default, so SD2 ROMs
are visible to the initial scan. However, full FAT fsck is disabled during
normal FE startup:

```text
PLUMOS_SD2_FSCK="${PLUMOS_SD2_BOOT_FSCK:-off}"
```

The boot behavior can be changed explicitly:

```text
PLUMOS_SD2_BOOT_FSCK=auto
PLUMOS_FRONTEND_SD2_MODE=sync
PLUMOS_FRONTEND_SD2_MODE=background
PLUMOS_FRONTEND_SD2_MODE=off
```

This removes the observed six-second `fsck.fat -a -w /dev/mmcblk1p1` delay
from the normal path.

### Boot log sync is diagnostic-only

The old development init copied logs and called `sync` frequently before the
frontend. Normal boot now copies logs without forcing a sync at every marker.

Forced boot-log sync remains available for diagnostics:

```text
PLUMOS_V90S_BOOT_SYNC_LOGS=1
plumos.sync_boot_logs=1
/mnt/share/plumos-sync-boot-logs
/mnt/plumos/config/system/sync-boot-logs
```

## Build validation

Rebuilt frontend and app-layer:

```text
./scripts/docker-build.sh frontend
./scripts/docker-build.sh app-layer --strict
```

Known unrelated warning:

```text
plumos_text_ui.c: warning: '%ld' directive output may be truncated
```

Syntax checks:

```text
sh -n output/app-layer/v90s/bin/plumos-frontend-launch
sh -n package/frontend-v90s/plumos/bin/plumos-sd2-content-mount
sh -n /tmp/plumos-v90s-fast-init
```

Hashes:

```text
71ef50cdd7ae7daeb5fdbcc9d7acf3ade6e3aba83f03a67e94b011d277503b5a  /tmp/plumos-v90s-fast-init
321384e98e734d76938bd21614463d01bf385862b343a2514528629a7e2fa994  output/app-layer/v90s/bin/plumos-frontend-launch
77e1b13416e1b49297bc9b899e663219d0f1d801f46da5075d63931c2664a0b9  output/app-layer/v90s/manifest.json
3674aea21502eafae19f361b195454ad9c5cbbfd871569772a78ac1a6c488409  output/app-layer/v90s/checksums.sha256
```

## Live deployment

Device:

```text
root@192.0.2.120
```

Deployed with backups:

```text
/sbin/init
/mnt/plumos/bin/plumos-frontend-launch
/mnt/plumos/manifest.json
/mnt/plumos/checksums.sha256
```

Backups:

```text
/mnt/plumos/Logs/boot-fast-backups/init.20260608-074132.bak
/mnt/plumos/Logs/boot-fast-backups/init.20260608-074315.bak
/mnt/plumos/Logs/boot-fast-backups/plumos-frontend-launch.20260608-074132.bak
```

Live hashes:

```text
71ef50cdd7ae7daeb5fdbcc9d7acf3ade6e3aba83f03a67e94b011d277503b5a  /sbin/init
321384e98e734d76938bd21614463d01bf385862b343a2514528629a7e2fa994  /mnt/plumos/bin/plumos-frontend-launch
77e1b13416e1b49297bc9b899e663219d0f1d801f46da5075d63931c2664a0b9  /mnt/plumos/manifest.json
3674aea21502eafae19f361b195454ad9c5cbbfd871569772a78ac1a6c488409  /mnt/plumos/checksums.sha256
```

Live syntax checks passed:

```text
/bin/sh -n /sbin/init
/bin/sh -n /mnt/plumos/bin/plumos-frontend-launch
```

The live files contain the expected markers:

```text
debian-init: starting PowerVR probe in background
debian-init: starting network/SSH init in background
debian-init: plumOS frontend pid=$frontend_pid
debian-init: starting enabled plumOS network services in background
PLUMOS_SD2_FSCK="${PLUMOS_SD2_BOOT_FSCK:-off}"
```

## Remaining validation

The actual boot-speed improvement needs one user-side reboot test. Expected
result:

- no white-bar framebuffer probe;
- frontend appears before Wi-Fi/DHCP/Samba/SD2 fsck completion;
- SD2 mount should not spend six seconds in `fsck.fat` unless
  `PLUMOS_SD2_BOOT_FSCK=auto` is explicitly set;
- SSH may become reachable slightly after the FE appears because Wi-Fi/SSH now
  runs in the background.
