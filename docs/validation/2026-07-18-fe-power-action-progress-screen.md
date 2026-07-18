# V90S FE power-action progress screen

Date: 2026-07-18

## Goal

Make Reboot and Shutdown use the same clear visual language as the existing
Refresh TOP progress screen while retaining the non-interactive power-action
lock and the rootfs-owned safe-storage sequence.

## Implementation

`SCREEN_POWER_ACTION_RUNNING` now emits translated renderer metadata for:

```text
power_action_title
power_action_wait
power_action_saving
power_action_no_remove
```

The V90S fbdev renderer detects `power_action_running=1` before its generic
list renderer and draws the shared centered progress layout:

```text
top status bar
left blue accent
large action title
large yellow wait message
smaller safe-save message
smaller SD-card removal warning
```

Refresh TOP now calls the same centered-progress helper, preserving its
existing layout and strings. Reboot and Shutdown retain localized content from
the existing language files. The input lock and safe power scripts were not
changed.

## Build and deployment

```text
git diff --check: PASS
frontend build: PASS
strict app-layer build: PASS
changed payload files: 3
deployment chunks: 1
payload verification: PASS
manifest verification: PASS
frontend restart: PASS
```

The host, app-layer, and deployed frontend binary hashes match:

```text
925198d3866f71f1439a90c053d42e413685d3a10c48bb0ac4613de51e287bea
```

After deployment the V90S had one
`plumos-controller-ui-fbdev --renderer fbdev` process. ADB and SSH remained
active.

## Remaining physical check

Run both FE Start Menu actions and confirm before the terminal action occurs:

- Reboot shows the centered restart progress screen.
- Shutdown shows the centered shutdown progress screen.
- Neither screen has a cursor or accepts navigation.
- The subsequent fast boot and storage state remain unchanged.
