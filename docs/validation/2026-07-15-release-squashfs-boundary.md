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
  --name plumos-v90s-system-squashfs-20260715-2.img
```

## Results

The release system rootfs was generated at:

```text
output/system-rootfs/v90s/plumos-v90s-system-rootfs.squashfs
```

Recorded output:

```text
compressed size: 69,513,216 bytes
sha256: 55e508f11f155700c673b70f4712f53915732bce2f8b0bb7c7cbaf94340499eb
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

The known-good running V90S SD was captured over ADB into the ignored vendor
input directory:

```text
artifacts/vendor/v90s-stockos-r1
```

The resulting prepared runtime and complete image are:

```text
output/vendor/v90s-stockos-r1
output/images/plumos-v90s-system-squashfs-20260715-2.img
output/images/plumos-v90s-system-squashfs-20260715-2.img.manifest.txt
```

Recorded image result:

```text
size: 4,522,835,968 bytes
sha256: c7ee745401ad20b65f5f1f82f8e4bd42e3ccce0d9112bc3d594262c0776e559f
p5 sha256: 55e508f11f155700c673b70f4712f53915732bce2f8b0bb7c7cbaf94340499eb
boot0 source: vendor-runtime
boot package source: vendor-runtime
KNULLI boot fallback: disabled
```

The image uses `PLUMBOOT` for the 33 MiB p1 FAT volume and `PLUMOS` for the
4 GiB p7 FAT32 app layer. macOS read-only validation mounted both filesystems,
passed `fsck_msdos -n`, and verified all 3,798 p7 checksums. The p5 hash is
identical to the separately validated release-system squashfs because image
assembly used `--no-rootfs-repack`. The initial `-1.img` lacked the `/overlay`
mountpoint required by the vendor boot ramdisk and stopped after its boot logo;
the diagnosis and corrected host validation are recorded in
`docs/validation/2026-07-15-release-image-overlay-mountpoint-fix.md`.

Real-device boot, frontend startup, service control, emulator launch/stop, and
safe reboot/poweroff remain the next hardware validation boundary.
