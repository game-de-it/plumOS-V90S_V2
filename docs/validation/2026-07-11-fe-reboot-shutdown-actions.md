# V90S FE reboot and shutdown actions

Date: 2026-07-11

## Goal

Make OS reboot and shutdown available from the V90S frontend without adding a
hidden fallback path or touching SSH/network services during normal frontend
restart.

## Implementation

Added an app-layer power helper:

```text
/mnt/plumos/bin/plumos-safe-shutdown
```

The helper supports:

```text
--reboot
--shutdown --poweroff
--sleep
--dry-run
```

For reboot and shutdown it performs:

1. Stop SD2 content bind mounts through `plumos-sd2-content-mount stop`.
2. Run `sync`.
3. Call the requested final action:
   - reboot: `reboot`, then `busybox reboot`, then sysrq `b` fallback.
   - shutdown: selected power backend, defaulting to `auto`.

Frontend changes:

```text
Power menu: Sleep / Reboot / Shutdown / Cancel
START menu: Reboot / Shutdown
```

`system:reboot` now calls:

```text
plumos-safe-shutdown --reboot --no-hold-resume
```

`system:shutdown` continues to call the shutdown path, now through the V90S
helper:

```text
plumos-safe-shutdown --shutdown --poweroff --power-backend auto --no-hold-resume
```

Power action logs are written to:

```text
/mnt/plumos/Logs/power-action.log
/mnt/plumos/Logs/frontend-power-action.log
```

## Build validation

Syntax checks:

```text
sh -n package/frontend-v90s/plumos/bin/plumos-safe-shutdown
sh -n package/frontend-v90s/plumos/bin/plumos-sd2-content-mount
python3 -m json.tool package/frontend-v90s/plumos/config/frontend/menus.json
```

Local dry-run checks:

```text
result=dry_run_reboot
result=dry_run_poweroff
```

Docker build checks:

```text
./scripts/docker-build.sh frontend
./scripts/docker-build.sh app-layer --strict
```

Build output hashes:

```text
782703bad96430187bb754eceaa6d8254013b8c4cf33c43bcc4380a26b1c9356  output/app-layer/v90s/bin/plumos-controller-ui-fbdev
453b12135ed5a48aa2c937e98ae642ed4a56a131c47bb9d8c188d9585a05a58c  output/app-layer/v90s/bin/plumos-safe-shutdown
3494b5ccaa5a0c47f24156ad9ac5256860efe7f14406bd300877295f19632baa  output/app-layer/v90s/config/frontend/menus.json
f1739964ddc94a11cd5ab92b63dc9440499577d10755b9853ef5b738dccc0ec9  output/app-layer/v90s/share/frontend/lang/ja.lang
c413b90af6bb28647472ac94ee5e3e5c3c6e08ca11bf88c8866977f316edae54  output/app-layer/v90s/manifest.json
6505b488f8bc7c4cd63f7eb662d931e542df5aecb0d46c33d6ff0e97ab116141  output/app-layer/v90s/checksums.sha256
```

## Live deployment

Device:

```text
root@192.0.2.120
```

Deployed:

```text
/mnt/plumos/bin/plumos-controller-ui-fbdev
/mnt/plumos/bin/plumos-safe-shutdown
/mnt/plumos/config/frontend/menus.json
/mnt/plumos/share/frontend/lang/
```

Live hashes:

```text
782703bad96430187bb754eceaa6d8254013b8c4cf33c43bcc4380a26b1c9356  /mnt/plumos/bin/plumos-controller-ui-fbdev
453b12135ed5a48aa2c937e98ae642ed4a56a131c47bb9d8c188d9585a05a58c  /mnt/plumos/bin/plumos-safe-shutdown
3494b5ccaa5a0c47f24156ad9ac5256860efe7f14406bd300877295f19632baa  /mnt/plumos/config/frontend/menus.json
f1739964ddc94a11cd5ab92b63dc9440499577d10755b9853ef5b738dccc0ec9  /mnt/plumos/share/frontend/lang/ja.lang
```

Live dry-run checks:

```text
PLUMOS_ROOT=/mnt/plumos /mnt/plumos/bin/plumos-safe-shutdown --dry-run --reboot --wait-sec 0
result=dry_run_reboot

PLUMOS_ROOT=/mnt/plumos /mnt/plumos/bin/plumos-safe-shutdown --dry-run --shutdown --poweroff --wait-sec 0
result=dry_run_poweroff
```

The live FE was restarted only through the PID-file controlled frontend helper:

```text
plumos-frontend-stop: TERM pid=2648
plumos-frontend-stop: pid=2974 cmd=/mnt/plumos/bin/plumos-controller-ui-fbdev --renderer fbdev
```

Actual reboot and poweroff were not executed by Codex, to avoid interrupting
SSH without the user's explicit real-device confirmation. The next validation
step is to trigger Reboot and Shutdown from the FE on the device.

## Follow-up: returned reboot/poweroff commands

The user tested Reboot and Shutdown from the START menu and reported that
nothing appeared to happen.

The live log proved that the START menu action did reach the helper:

```text
start action=reboot poweroff=0 dry_run=0 power_backend=auto sleep_backend=mem
sd2: stopping content mounts
sync: begin
sync: done
reboot: requested
```

Shutdown also reached the helper:

```text
start action=shutdown poweroff=1 dry_run=0 power_backend=auto sleep_backend=mem
sd2: stopping content mounts
sync: begin
sync: done
poweroff: requested backend=auto
cmd: poweroff
```

On the live device, `reboot`, `poweroff`, and `halt` resolve to app-layer
BusyBox wrappers:

```text
/mnt/plumos/bin/reboot
/mnt/plumos/bin/poweroff
/mnt/plumos/bin/halt
```

BusyBox supports forced terminal actions:

```text
reboot [-d DELAY] [-nf]
poweroff [-d DELAY] [-nf]
```

The issue was that the first helper version treated a returned `reboot` or
`poweroff` command as success. On this runtime those commands can return after
asking init to act, while the system keeps running. The helper now treats any
returned terminal command as failure and proceeds to the next backend:

```text
reboot -f -> busybox reboot -f -> sysrq b
poweroff -f -> busybox poweroff -f -> halt -f -> sysrq o
```

Updated live hash:

```text
0648e9bd78ef90b4326dee898181a1c4eb993e7fbdc3f800567c8419a3af2f0b  /mnt/plumos/bin/plumos-safe-shutdown
```

Updated output hashes:

```text
0648e9bd78ef90b4326dee898181a1c4eb993e7fbdc3f800567c8419a3af2f0b  output/app-layer/v90s/bin/plumos-safe-shutdown
aea582067bfe365994237a018b54b5dc4dc3cebb84bae1504e06eb62a04d6b39  output/app-layer/v90s/manifest.json
ddeece97a003478341a0ff09db0319d881957d64e37272f6198f07779b4a2401  output/app-layer/v90s/checksums.sha256
```

Dry-run was rechecked on the live device after deployment:

```text
result=dry_run_reboot
result=dry_run_poweroff
```

Actual reboot and poweroff still need user-side real-device validation because
running either action intentionally drops SSH.
