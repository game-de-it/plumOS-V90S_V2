# V90S Refresh TOP intermediate screen removal

Date: 2026-07-11

## Change

- Removed the dedicated `SCREEN_TOP_REFRESH_RUNNING` screen used by manual TOP refresh.
- Manual TOP refresh now keeps the current screen visible, sets `status=refreshing TOP`, runs the scanner, reloads TOP entries, and then updates status.
- Removed the obsolete fbdev hidden-line marker `top_refresh_running=`.

## Build validation

Host commands:

```sh
rg -n "SCREEN_TOP_REFRESH_RUNNING|UI_TOP_REFRESH_MIN_VISIBLE_MS|render_top_refresh_running|top_refresh_running|wait_until_ms" src/frontend
git diff --check
./scripts/docker-build.sh frontend
./scripts/docker-build.sh app-layer --strict
```

Results:

- Refresh-running screen references: none.
- `git diff --check`: clean.
- Frontend build: success.
- App layer build: success.
- Known unrelated warning remains in `src/frontend/plumos_text_ui.c` for `%ld` into `cores_buf`.

Generated hashes:

```text
fa1d763756da9dfc341a11c00405975bc7ac0e7c7a984e3cab4ea6a8bf02ec51  output/frontend/v90s/plumos/bin/plumos-controller-ui-fbdev
fa1d763756da9dfc341a11c00405975bc7ac0e7c7a984e3cab4ea6a8bf02ec51  output/app-layer/v90s/bin/plumos-controller-ui-fbdev
0f65078d54adea6d228a9089f30db9c3ec4d7eee59e6a3e60bc1ac067ebdeb81  output/app-layer/v90s/manifest.json
f8616a9a0055b89f2caf03984693dc60b7a0837d7b4970a8d47cd33eafa296a3  output/app-layer/v90s/checksums.sha256
```

## Live device deployment

Target:

```text
root@192.0.2.120:/mnt/plumos/bin/plumos-controller-ui-fbdev
```

Deployment result:

```text
old_hash=53eb3b95e9c72b433069b7da4322375c830dae27041a6b5a8afe2e0cf37475d1
new_hash=fa1d763756da9dfc341a11c00405975bc7ac0e7c7a984e3cab4ea6a8bf02ec51
installed_hash=fa1d763756da9dfc341a11c00405975bc7ac0e7c7a984e3cab4ea6a8bf02ec51
backup=plumos-controller-ui-fbdev.bak-20260608-065810
restarted_pid=2519
```

The frontend was stopped through `/mnt/plumos/bin/plumos-frontend-stop`, then relaunched through `/mnt/plumos/bin/plumos-frontend-launch`. SSH and network services were not stopped.

## Remaining manual check

Use the real device to run FE Start Menu -> Refresh TOP. Expected behavior:

- The current FE screen remains visible while refresh runs.
- No temporary "Refresh TOP" progress screen appears.
- The TOP list updates after refresh completes.
