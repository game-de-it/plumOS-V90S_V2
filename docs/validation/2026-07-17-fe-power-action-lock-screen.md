# V90S FE Power Action Lock Screen

Date: 2026-07-17

## Goal

Prevent normal frontend navigation after the user starts Reboot or Shutdown.
The filesystem safety path needs an unambiguous, non-interactive screen while
the rootfs-owned helper stops writers, syncs, unmounts p7, and performs the
terminal action.

## Implementation

The frontend now enters `SCREEN_POWER_ACTION_RUNNING` before invoking
`plumos-safe-shutdown` for either terminal action.

The screen has no cursor and displays:

```text
Restarting / Shutting Down
PLEASE WAIT
Saving data safely
Controls are disabled
Do not remove the SD card
```

While this screen is active, `handle_action()` ignores every frontend action,
including navigation, ABXY, START, SELECT, volume, power, and text-mode quit.
Pending key repeat state is cleared when the screen opens.

If command execution fails or returns non-zero, the previous menu is restored
and the existing error status is shown. A successful production Reboot or
Shutdown remains locked until the rootfs helper stops the frontend. Dry-run
tests restore the previous screen because no terminal action follows.

Sleep remains unchanged: after a successful resume it returns to the screen
that opened the physical power menu.

## Build Checks

```text
git diff --check
language duplicate-key check: passed
./scripts/docker-build.sh frontend
./scripts/docker-build.sh app-layer --strict
```

Both Docker targets completed successfully.

## Input-Lock Test

The newly built AArch64 frontend was executed on the V90S with a temporary
`PLUMOS_ROOT` whose power helper was the harmless `/bin/true`. After selecting
Reboot, the scripted test sent:

```text
DOWN UP LEFT RIGHT B START SELECT VOLUME_DOWN VOLUME_UP POWER
```

The final screen remained:

```text
power_action_running=1
power_action=reboot
entries=4 cursor=0
```

The same test passed for Shutdown. A second test used `/bin/false`; its final
screen returned to START with:

```text
status: power action returned non-zero; see frontend-power-action.log
```

No real reboot or poweroff was performed by these scripted checks.

The deployed binary was also exercised against the real rootfs helper with
`PLUMOS_CONTROLLER_POWER_DRY_RUN=1`. It showed the lock screen, the helper
reported `result=dry_run_reboot`, and the frontend then restored START with
`status: reboot requested` as intended for a dry run.

## Deployment

The strict app-layer differential deployment changed nine payload files plus
the manifest. Every payload was verified on-device before the manifest switch.

```text
deploy=ok
chunks=1
frontend_restart=1
frontend_processes=1
```

The deployed frontend binary matches the build output:

```text
f2be74ca2c8a10c0482b395efad5714ba9684a403fe56f19a13d22285b920005
```
