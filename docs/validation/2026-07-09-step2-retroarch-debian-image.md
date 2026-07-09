# Step 2 RetroArch Debian Image

Date: 2026-07-09

## Purpose

Build the first Step 2 V90S image that boots the known KNULLI/stock boot chain, switches into a Debian userspace payload, and launches RetroArch with the local NES test ROM.

This is an implementation image, not a completed device validation. The real-device result still needs to be captured from the V90S.

## Inputs

Test ROM:

```text
artifacts/nes/Super Mario Bros..nes
sha256: 0b3d9e1f01ed1668205bab34d6c82b0e281456e137352e4f36a9b2cfa3b66dea
```

Debian packages selected:

```text
retroarch
libretro-nestopia
alsa-utils
input-utils
procps
psmisc
kmod
```

Package inventory note:

- Debian bookworm arm64 provides `retroarch` and `libretro-nestopia`.
- `libretro-fceumm` was not available from the default Debian bookworm package index in the assembly container.
- KNULLI/Buildroot remains the fallback reference if Debian RetroArch cannot use the V90S framebuffer/audio/input path.

## Build Commands

```sh
./scripts/run-assembly-tools.sh ./scripts/build-step1-rootfs.sh \
  --profile debian-retroarch \
  --out-dir output/rootfs-step2 \
  --rom artifacts/nes/'Super Mario Bros..nes'
```

```sh
./scripts/run-assembly-tools.sh ./scripts/assemble-v90s-image.sh \
  --rootfs output/rootfs-step1/stage1-userdata-loader.squashfs \
  --userdata-payload output/rootfs-step2/debian-bookworm-retroarch-step2.squashfs \
  --out-dir output/images \
  --name plumos-v90s-armbian-step2-20260709-1-retroarch-debian.img \
  --boot-vfat-size 33M \
  --userdata-size 512M \
  --diagnostic-init
```

## Outputs

Rootfs payload:

```text
output/rootfs-step2/debian-bookworm-retroarch-step2.squashfs
sha256: db20f97d07aa98fe27f220d1ae5c0c6bb4986c61bff23f3728b21dda15154360
size: 399MB
uncompressed rootfs: 947MB
```

SD image:

```text
output/images/plumos-v90s-armbian-step2-20260709-1-retroarch-debian.img
sha256: d31d2913b1792bc4979e55a1437d7d9aedd60c84af11be613b4c0d3387df39a7
size: 581MB
```

GPT layout verified with `gpt -r show`:

```text
start 74240 size 67584 index 4  boot-resource FAT, 33MB
start 141824 size 1048576 index 5  userdata, 512MB
```

## Payload Verification

The squashfs contains:

```text
/usr/bin/retroarch
/usr/lib/aarch64-linux-gnu/libretro/nestopia_libretro.so
/usr/local/sbin/v90s-retroarch-launch
/roms/nes/Super Mario Bros..nes
/etc/plumos-step2-release
```

The ROM is copied only into ignored build output. It is not tracked by git.

## Expected Device Behavior

1. KNULLI boot logo appears as before.
2. Stage1 mounts userdata and switches into the Debian RetroArch payload.
3. Debian init prepares `/boot/plumos-logs` on FAT.
4. The RetroArch launcher records environment, framebuffer, input, sound, RetroArch feature, and dmesg diagnostics.
5. The launcher tries RetroArch with `fbdev` first, then `sdl2` fallback attempts.
6. If all RetroArch attempts fail or exit, Debian init falls back to the Step 1 framebuffer console.

Expected FAT logs after the SD card is returned to macOS:

```text
/Volumes/KNULLI/plumos-logs/plumos-v90s-diag.log
/Volumes/KNULLI/plumos-logs/plumos-v90s-debian-init.log
/Volumes/KNULLI/plumos-logs/plumos-v90s-retroarch-launch.log
/Volumes/KNULLI/plumos-logs/plumos-v90s-retroarch.log
```

## Open Questions For Real Hardware

- Does the Debian `retroarch` build include a working `fbdev` video driver on this kernel?
- If `fbdev` fails, does `sdl2` have any usable non-X11 backend on V90S?
- Does ALSA expose a default playback device that RetroArch can open?
- Which `/dev/input/event*` node maps to the built-in V90S controls?
- Does Nestopia reach approximately 60fps with audio sync enabled?
