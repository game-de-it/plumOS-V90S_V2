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
