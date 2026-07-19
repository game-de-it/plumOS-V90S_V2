# V90S Recent Boot Checksum Recovery

Date: 2026-07-19

## Symptom

After selecting the UI setting whose effect is to show Recent at startup and
rebooting, the frontend did not appear. The saved device setting was valid:

```text
"boot_resume_mode": "recent"
```

Launching the same frontend manually opened the Recent screen, so loading the
history data was not the failing operation.

## Root Cause

The preceding Graphic TOP animation deployment had updated only this live
binary:

```text
/mnt/plumos/bin/plumos-controller-ui-fbdev
```

Its deployed SHA-256 was:

```text
11d7b32db27723832521d0329b0263fc97cd088a9ecea2656c1a79bedfb0817a
```

The live `checksums.sha256` and `manifest.json` still expected the older hash:

```text
6226e36e6746b886faf67e6bda5e2ee8f5634b912bd61e35029b29dad36f4cb3
```

The normal boot path therefore stopped before FE startup with:

```text
error=critical checksum failed: bin/plumos-controller-ui-fbdev
debian-init: plumOS frontend exited rc=1
```

This was an app-layer deployment consistency failure, not a failure in
`boot_resume_mode=recent` or the Recent history parser.

## Recovery

The current device metadata was pulled before editing. Only these entries were
changed:

```text
checksums.sha256: bin/plumos-controller-ui-fbdev
manifest.json:    bin/plumos-controller-ui-fbdev
checksums.sha256: manifest.json
```

Live user settings, PortMaster updates, saves, and all unrelated checksum
entries were preserved. The new metadata was staged under `/run`, verified,
then installed with `checksums.sha256` last as the commit marker.

Targeted verification passed:

```text
bin/plumos-controller-ui-fbdev: OK
manifest.json: OK
app_layer=ready
version=0.1.0-dev
vendor=v90s-stockos-r1
```

The complete generated host app layer also passed all 5,945 entries in its
own `checksums.sha256`.

## Hardware Reboot Proof

The V90S was rebooted through `plumos-safe-shutdown`. After USB gadget
re-enumeration, the new boot contained:

```text
boot_resume_mode=recent
frontend_processes=1
frontend=/mnt/plumos/bin/plumos-controller-ui-fbdev --renderer fbdev
/tmp/plumos-fe-ready:
pid=308
screen=4
```

`SCREEN_RECENT` is enum value 4 in the controller. The fresh bootstrap log
also recorded:

```text
validated version=0.1.0-dev vendor=v90s-stockos-r1
starting frontend launcher=/mnt/plumos/bin/plumos-frontend-launch
```

The setting now survives reboot and opens the intended Recent screen through
the normal boot path.

## Prevention

`AGENTS.md` now requires every managed app-layer deployment to include the
matching `checksums.sha256`, `manifest.json`, and required component metadata,
followed by live checksum validation before reboot. A selective live update
must preserve unrelated device-side mutable files and update only the affected
metadata entries.
