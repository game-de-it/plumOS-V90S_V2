# V90S Refresh TOP fbdev progress screen

Date: 2026-07-11

## Change

The earlier attempt to remove the intermediate Refresh TOP screen was wrong:
it made the A button action look unresponsive. Refresh TOP is a meaningful FE
state and must remain visible while the scanner runs.

This change restores the original Refresh TOP state flow and adds the missing
V90S fbdev renderer support:

- Restored `SCREEN_TOP_REFRESH_RUNNING`.
- Restored the one-second minimum visible Refresh TOP screen.
- Restored `top_refresh_running=1` output from the controller UI.
- Added a dedicated fbdev renderer path for `top_refresh_running=1`.
- The visible V90S screen now renders a centered:
  - `REFRESH TOP`
  - `PLEASE WAIT`
  - `SCANNING SYSTEMS`
  - `RELOADING TOP LIST`

## Build validation

Host commands:

```sh
git diff --check
./scripts/docker-build.sh frontend
./scripts/docker-build.sh app-layer --strict
```

Results:

- `git diff --check`: clean.
- Frontend build: success.
- App layer build: success.
- Known unrelated warning remains in `src/frontend/plumos_text_ui.c` for `%ld` into `cores_buf`.

Generated hashes:

```text
7e7be035a00ce13e5a9a1953fe9b5a873371c751f6043404b4b2838620da8a41  output/frontend/v90s/plumos/bin/plumos-controller-ui-fbdev
7e7be035a00ce13e5a9a1953fe9b5a873371c751f6043404b4b2838620da8a41  output/app-layer/v90s/bin/plumos-controller-ui-fbdev
05948b7999d97e57169b4eb23eb2632d02ee6e9f70a6f3c97c4e71b35f5aab35  output/app-layer/v90s/manifest.json
2113cb45a58b2c43d86d13cba5d1cbf5baf3c7d776863d3b00872b590c8a5211  output/app-layer/v90s/checksums.sha256
```

## Live device deployment

Target:

```text
root@192.0.2.120:/mnt/plumos/bin/plumos-controller-ui-fbdev
```

Deployment result:

```text
old_hash=fa1d763756da9dfc341a11c00405975bc7ac0e7c7a984e3cab4ea6a8bf02ec51
new_hash=7e7be035a00ce13e5a9a1953fe9b5a873371c751f6043404b4b2838620da8a41
installed_hash=7e7be035a00ce13e5a9a1953fe9b5a873371c751f6043404b4b2838620da8a41
backup=plumos-controller-ui-fbdev.bak-20260608-070437
restarted_pid=2648
```

The frontend was stopped through `/mnt/plumos/bin/plumos-frontend-stop`, then
relaunched through `/mnt/plumos/bin/plumos-frontend-launch`. SSH and network
services were not stopped.

## Remaining manual check

Use the real device to run FE Start Menu -> Refresh TOP. Expected behavior:

- Pressing A immediately shows the Refresh TOP progress screen.
- The progress screen is visible for at least about one second.
- After refresh completes, FE returns to the previous Settings screen.
- The TOP list updates after refresh completes.
