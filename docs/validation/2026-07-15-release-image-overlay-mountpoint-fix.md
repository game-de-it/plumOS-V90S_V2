# 2026-07-15 Release Image Overlay Mountpoint Fix

## Device Result

The first release-system image stopped after displaying the boot logo:

```text
output/images/plumos-v90s-system-squashfs-20260715-1.img
```

The USB Wi-Fi dongle LED remained off. `adb devices -l` returned no device,
macOS did not enumerate an ADB/Android gadget, and no V90S SSH endpoint was
found at the known addresses or elsewhere on `192.0.2.0/24`.

This placed the failure before plumOS init, network initialization, and the
app-layer frontend bootstrap.

## Root Cause

The captured vendor `boot.img` ramdisk mounts p5 as the base of an overlay
root, then requires these destinations in the squashfs before `switch_root`:

```text
/boot
/overlay
/proc
/sys
/dev
```

The initial release-system squashfs contained all except `/overlay`. Its
`/init` therefore failed at:

```sh
mount --move /overlay_root /new_root/overlay || return 1
```

It then entered the boot ramdisk getty path instead of running
`/sbin/init` from the release-system squashfs. The image used
`--no-rootfs-repack`, so the image assembler did not add the missing directory.

## Fix

The release-system builder now creates `/overlay`. The image assembler also
rejects `--no-rootfs-repack` unless all five boot-contract directories are
present, preventing another logo-only image from being emitted for this cause.

Corrected outputs:

```text
rootfs: output/system-rootfs/v90s/plumos-v90s-system-rootfs.squashfs
rootfs sha256: 55e508f11f155700c673b70f4712f53915732bce2f8b0bb7c7cbaf94340499eb
image: output/images/plumos-v90s-system-squashfs-20260715-2.img
image sha256: c7ee745401ad20b65f5f1f82f8e4bd42e3ccce0d9112bc3d594262c0776e559f
```

Host validation confirmed:

- p1 and p7 pass read-only `fsck_msdos`
- all 3,798 p7 app-layer checksums match
- the raw p5 partition hash matches the corrected release-system squashfs
- p5 contains `/boot`, `/overlay`, `/proc`, `/sys`, and `/dev`
- vendor boot0 and boot package are used with KNULLI fallback disabled

Real-device testing of `-2.img` later proved that this root handoff was fixed:
p7 and SD2 mounted and the frontend launcher ran. The frontend then stopped on
a separate missing runtime-library path, documented in
`docs/validation/2026-07-15-release-image-frontend-runtime-fix.md`.
