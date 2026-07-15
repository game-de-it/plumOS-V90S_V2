# 2026-07-15 Release SquashFS Boundary Validation

## Scope

Implement the distribution-policy split between the read-only system squashfs
and the writable FAT32 app layer, then assemble the first complete SD image.
This is a host-side build and filesystem validation; the new image has not yet
been booted on a V90S.

## Build Commands

```sh
./scripts/docker-build.sh frontend
./scripts/docker-build.sh network-services
./scripts/docker-build.sh picoarch
./scripts/docker-build.sh standalone launcher-only
./scripts/docker-build.sh app-layer --strict
./scripts/docker-build.sh system-rootfs
./scripts/capture-v90s-vendor-runtime-adb.sh --force
./scripts/docker-build.sh vendor-runtime
./scripts/docker-build.sh sd-image \
  --rootfs-squashfs output/system-rootfs/v90s/plumos-v90s-system-rootfs.squashfs \
  --no-rootfs-repack \
  --app-layer-dir output/app-layer/v90s \
  --share-size 4096M \
  --name plumos-v90s-system-squashfs-20260715-3.img
```

## Results

The release system rootfs was generated at:

```text
output/system-rootfs/v90s/plumos-v90s-system-rootfs.squashfs
```

Recorded output:

```text
compressed size: 69,513,216 bytes
sha256: ebd57859384c055458a25ad6a02cd14f057aaf465d5741376005aad7683d2438
app-layer files checked: 3,802
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

The known-good running V90S SD was captured over ADB into the ignored vendor
input directory:

```text
artifacts/vendor/v90s-stockos-r1
```

The resulting prepared runtime and complete image are:

```text
output/vendor/v90s-stockos-r1
output/images/plumos-v90s-system-squashfs-20260715-3.img
output/images/plumos-v90s-system-squashfs-20260715-3.img.manifest.txt
```

Recorded image result:

```text
size: 4,522,835,968 bytes
sha256: da71786bd994f85d388f006e76b577570630d44995aaa857a84a4bfe04ea35ae
p5 sha256: ebd57859384c055458a25ad6a02cd14f057aaf465d5741376005aad7683d2438
boot0 source: vendor-runtime
boot package source: vendor-runtime
KNULLI boot fallback: disabled
```

The image uses `PLUMBOOT` for the 33 MiB p1 FAT volume and `PLUMOS` for the
4 GiB p7 FAT32 app layer. macOS read-only validation mounted both filesystems,
passed `fsck_msdos -n`, and verified all 3,802 p7 checksums. The p5 hash is
identical to the separately validated release-system squashfs because image
assembly used `--no-rootfs-repack`. The initial `-1.img` lacked the `/overlay`
mountpoint required by the vendor boot ramdisk and stopped after its boot logo;
the diagnosis and corrected host validation are recorded in
`docs/validation/2026-07-15-release-image-overlay-mountpoint-fix.md`.
The `-2.img` then reached the frontend but exposed a missing frontend runtime
library path. Its diagnosis and the `-3.img` correction are recorded in
`docs/validation/2026-07-15-release-image-frontend-runtime-fix.md`.

Real-device boot, frontend startup, service control, emulator launch/stop, and
safe reboot/poweroff remain the next hardware validation boundary.
