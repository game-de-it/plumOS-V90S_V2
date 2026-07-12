# V90S SELECT Menu MMF-Style Layout Validation

## Goal

Make the frontend SELECT button Core Settings menu match the MMF-style settings
screen layout on V90S.

## Issue

The Core Settings screen was rendered through the generic fbdev path without a
screen-specific marker. That made it look different from MMF settings screens
and let renderer metadata influence the visible body.

There was also an fbdev hidden-line rule that treated any line containing
`A:` as a help row. This hid the valid core label `RA: quicknes`, so the
`Cores < RA: quicknes >` row could disappear.

## Changes

- `render_core_select()` now emits `settings_screen=1` and
  `core_settings_screen=1`.
- The fbdev renderer treats `core_settings_screen=1` as a settings-family page
  with the larger MMF-style Core Settings row scale.
- Renderer-only metadata such as `source=` and `core_settings_screen=` is
  hidden from the visible fbdev body.
- The help-line filter was narrowed so labels such as `RA: quicknes` remain
  visible.
- `target=` and `source=` are kept for text output, but are not emitted for the
  framebuffer renderer path.

## Build Validation

Commands:

```sh
./scripts/docker-build.sh frontend
./scripts/docker-build.sh app-layer --strict
cd output/app-layer/v90s && sha256sum -c checksums.sha256
```

Result:

- `frontend`: success.
- `app-layer --strict`: success.
- `checksums.sha256`: all files verified OK.

The existing `plumos_text_ui.c` `snprintf("%ld", cpu_cores)` truncation
warnings are unrelated to this change.

## Live Device Validation

Device:

- `root@192.0.2.120`
- App layer: `/mnt/plumos`

Deployment used the PID-scoped frontend stop helper:

```sh
/mnt/plumos/bin/plumos-frontend-stop stop
```

The updated app-layer frontend payload was copied to `/mnt/plumos`, permissions
were restored, and the frontend was restarted through:

```sh
PLUMOS_ROOT=/mnt/plumos PLUMOS_SDCARD_ROOT=/mnt/plumos \
  /mnt/plumos/bin/plumos-frontend-launch
```

Live binary hashes after deployment:

```text
8cf5e87d64075b20ca402c2f4945b9235f919a7354aab8a751715fcc6e1a4dfa  /mnt/plumos/bin/plumos-controller-ui-fbdev
f698dc520c4148773c9989752e6f1fa45ed53ae5f03f72f97bb86cdae81e3a91  /mnt/plumos/bin/plumos-frontend-launch
```

Framebuffer capture:

```text
output/validation/select-menu-mmf-style/select-menu-4-page0.png
```

Observed page:

- Title bar shows `CORE SETTINGS`.
- Selected row is visible as `> CORES < RA: QUICKNES >`.
- `DEFAULT < INHERIT TOP >`, separator, and `CPU FREQ < ONDEMAND >` are aligned
  as a settings menu rather than as plain text output.
- Footer text is shown through renderer footer lines.
- No `target=` or `source=` metadata appears in the visible framebuffer body.

Frontend process after validation:

```text
pid=10389 cmd=/mnt/plumos/bin/plumos-controller-ui-fbdev --renderer fbdev
```

## Status

The SELECT/Core Settings menu now uses the MMF-style settings layout on the live
V90S framebuffer.
