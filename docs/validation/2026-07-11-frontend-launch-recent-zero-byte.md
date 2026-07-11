# V90S frontend launch blocked by zero-byte recent state

Date: 2026-07-11

## Symptom

The frontend could scroll ROM-list text, but launching a game from the frontend
did not start RetroArch.

## Log Finding

Live device:

```text
ssh root@192.0.2.120
```

`/mnt/plumos/Logs/frontend-launch.log` showed that ROM/core resolution was
successful, but the launch stopped before RetroArch execution:

```text
rom_exists: yes
can_execute: yes
command: '/mnt/plumos/bin/plumos-retroarch-launch' --system 'nes' ...
error: cannot read recent: /mnt/plumos/state/frontend/recent.json
```

The state file existed but was empty:

```text
-rwxr-xr-x 1 root root 0 /mnt/plumos/state/frontend/recent.json
```

## Fix

`plumos-text-ui` now treats a zero-byte `state/frontend/recent.json` as an empty
Recent list. The next `recent add` or game launch can then rewrite it as valid
JSON instead of aborting.

This keeps the launcher tolerant of interrupted FAT32 writes while still using
the same normal Recent state path.

## Build

```text
./scripts/docker-build.sh frontend
./scripts/docker-build.sh app-layer
```

The existing `plumos_text_ui.c` CPU-core formatting warnings are unrelated to
this change.

## Live Deployment

Deployed binary:

```text
8ef65ae21a130f7e32758fde73ecf57d494958a8a9efaa878faf4f4751e310f1  /mnt/plumos/bin/plumos-text-ui
```

The previous binary was backed up under:

```text
/mnt/plumos/backups/frontend-recent-zero-byte-20260711/
```

## Live Tests

The real `/mnt/plumos/state/frontend/recent.json` was still zero bytes, and
listing Recent no longer failed:

```text
plumOS text UI - Recent
source: /mnt/plumos/state/frontend/recent.json
count: 0
RC=0
```

An isolated `/tmp/plumos-recent-test` root was used to verify that `recent add`
can rewrite a zero-byte Recent file into valid JSON without changing the real
Recent state:

```text
PLUMOS_ROOT=/tmp/plumos-recent-test \
PLUMOS_SDCARD_ROOT=/mnt/plumos \
/mnt/plumos/bin/plumos-text-ui recent add nes nes/Baseball.nes \
  --profile retroarch:quicknes --no-scan --resume yes \
  --played-at 2026-07-11T00:00:00Z
```

Result:

```text
count: 1
relative_path: nes/Baseball.nes
launch_profile: retroarch:quicknes
```

The generated test file was valid JSON and the `/tmp/plumos-recent-test` tree
was removed afterward.
