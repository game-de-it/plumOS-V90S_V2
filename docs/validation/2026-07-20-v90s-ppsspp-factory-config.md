# V90S PPSSPP Factory Configuration

Date: 2026-07-20

## Goal

Use the complete PPSSPP configuration validated on the physical V90S as one
factory source for the frontend package, PPSSPP build artifact, first launch,
and explicit factory reset. Preserve existing user settings during normal
builds and deployments.

## Factory Input

The live files were captured from:

```text
/mnt/plumos/state/standalone/ppsspp/config/ppsspp/PSP/SYSTEM/ppsspp.ini
/mnt/plumos/state/standalone/ppsspp/config/ppsspp/PSP/SYSTEM/controls.ini
```

Run count, recent-ROM history, and play time were removed. Shader cache, saves,
and the temporary `ppsspp.ini.before-v90s-ui-scale-20260720` file were not
included. The tracked factory pair is:

```text
package/frontend-v90s/plumos/factory-defaults/sa/state/standalone/ppsspp/config/ppsspp/PSP/SYSTEM/ppsspp.ini
package/frontend-v90s/plumos/factory-defaults/sa/state/standalone/ppsspp/config/ppsspp/PSP/SYSTEM/controls.ini
```

```text
ppsspp.ini  4efab9522cd3b7743035072913cf7039a1b71b20df3d48e5e797146a4e87b568
controls.ini c5732a6a5e78a4f874f99aa460f01ad37b0cbf98526ca7f14a7e0da692c3ddb7
```

## Build Results

The focused PPSSPP build completed from upstream `v1.20.4`, commit
`fa50bb197606`:

```text
[standalone-v90s] built ppsspp
[standalone-v90s] done: built=1 failed=0 skipped=9
```

The standalone manifest records each factory source, artifact path, and hash.
Frontend and standalone copies produced identical hashes. A deliberate
`UIScaleFactor` mismatch made strict app-layer assembly fail with
`frontend and PPSSPP factory configs do not match`, proving that stale copies
cannot be silently packaged together.

The final checks completed successfully:

```text
./scripts/docker-build.sh frontend
./scripts/docker-build.sh standalone ppsspp
./scripts/docker-build.sh app-layer --strict
./scripts/docker-build.sh preflight

preflight: PASS
```

## Runtime And Reset Tests

An isolated launcher test verified:

- a missing user profile receives both factory files
- a later user `UIScaleFactor` and control mapping remain unchanged
- missing user and factory configs stop with status 78 and a clear log message
- no minimal generated PPSSPP fallback remains

An isolated `plumos-factory-reset sa` test verified that both existing user
files are copied to the timestamped backup tree before the factory pair is
restored. The live device was checked with `--dry-run` only, to avoid replacing
the user's validated settings:

```text
would restore sa: state/standalone/ppsspp/config/ppsspp/PSP/SYSTEM/ppsspp.ini
would restore sa: state/standalone/ppsspp/config/ppsspp/PSP/SYSTEM/controls.ini
```

## Live Deployment

Only the launcher and factory pair were deployed. The freshly rebuilt PPSSPP
binary was not required for this configuration-only update and was not used to
replace the known-working live binary. The obsolete
`config/standalone/ppsspp-v90s-default.ini` was removed from the device and its
metadata.

Device validation returned:

```text
app_layer=ready
launcher f524558b781f0983243fb03648b0357f687f07e22ef378548ac9314df682989f
manifest 5c8e8ab146bb4878a9103f726f1665ac04466435bcdaaca1aabe071b449efdff
```

The writable user settings were unchanged across deployment:

```text
ppsspp.ini  15ee411c09439969e454887f77607188adbca1b2e2f62c72feb2219bd92dd0e4
controls.ini 2a093f01cce40fdf8926a0da5833b9e941e98784e0fefe14b6ba6f8f2fb9a00e
```
