# 2026-07-15 Release SquashFS Boundary Validation

## Scope

Implement the distribution-policy split between the read-only system squashfs
and the writable FAT32 app layer. This is a host-side build validation; the new
system squashfs has not yet been booted on a V90S.

## Build Commands

```sh
./scripts/docker-build.sh frontend
./scripts/docker-build.sh network-services
./scripts/docker-build.sh picoarch
./scripts/docker-build.sh standalone launcher-only
./scripts/docker-build.sh app-layer --strict
./scripts/docker-build.sh system-rootfs
```

## Results

The release system rootfs was generated at:

```text
output/system-rootfs/v90s/plumos-v90s-system-rootfs.squashfs
```

Recorded output:

```text
compressed size: 69,513,216 bytes
sha256: 34784c7d0061ff541041e7267b6ca564366f2a0102f8e92a8423103617be3fab
app-layer files checked: 3,798
app-layer compatibility: v90s-stockos-r1
```

Manifest checks confirmed that the release squashfs contains init, PowerVR,
the rootfs power-action helper, the app-layer bootstrap, the vendor identity,
and base notices. It does not contain RetroArch, libretro cores, the frontend,
PicoArch, standalone emulator payloads, or private ROMs.

The rootfs bootstrap accepted the generated app layer with the matching vendor
identity. A mismatched identity failed explicitly with:

```text
plumOS app layer error: vendor mismatch: app=v90s-stockos-r1 system=wrong-vendor
```

No application fallback was started. A release build with Wi-Fi credentials
also failed intentionally, proving that credentials cannot be embedded in the
release squashfs through the normal build target.

Transient PID, lock, cache, and in-progress state paths now use
`/run/plumos`. Persistent frontend indexes, settings, emulator configuration,
saves, states, artwork, and user-visible logs remain in `/mnt/plumos`.

## SD Image Status

Full SD image assembly was attempted with the generated p5 squashfs and p7 app
layer, but stopped before writing an image because the ignored local vendor
input is absent:

```text
artifacts/vendor/v90s-stockos-r1/files/stockos-selected-files.tar.gz
```

This is intentionally not bypassed with the legacy KNULLI boot fallback. After
restoring or re-extracting the StockOS vendor input, run:

```sh
./scripts/docker-build.sh vendor-runtime
./scripts/docker-build.sh sd-image \
  --rootfs-squashfs output/system-rootfs/v90s/plumos-v90s-system-rootfs.squashfs \
  --app-layer-dir output/app-layer/v90s \
  --share-size 4096M \
  --name plumos-v90s-system-squashfs-20260715-1.img
```

Real-device boot, frontend startup, service control, emulator launch/stop, and
safe reboot/poweroff remain the next hardware validation boundary.
