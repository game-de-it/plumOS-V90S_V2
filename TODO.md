# TODO

Last updated: 2026-07-09

## Current Goal

Step 1: V90S real hardware boots from a generated SD-card image, shows a Linux console on the internal display, accepts USB keyboard input, and can run basic commands such as `ls`.

## Working Rules

- Keep work in small git commits with clear investigation/build/test boundaries.
- Keep repeated-test images small. Current assembly defaults are 33MB FAT boot-resource and 64MB userdata.
- Use KNULLI only as the V90S boot-chain reference unless evidence shows a full KNULLI build is required.
- Treat Armbian-derived userspace/rootfs as the main target.
- User performs real-device validation; record each device result under `docs/validation/`.

## Done

- [x] Initialize git repository and project notes.
- [x] Investigate KNULLI V90S target, boot assets, Android `boot.img`, and SD image layout.
- [x] Add Docker-based image assembly tooling.
- [x] Add `scripts/assemble-v90s-image.sh` for KNULLI-boot-chain image generation.
- [x] Validate host-side smoke image assembly with a tiny BusyBox squashfs.
- [x] Reduce iteration image size from inherited multi-GB KNULLI layout to 33MB FAT plus 64MB userdata.

## Next: Armbian Rootfs Path

- [ ] Re-check build host capacity with `./scripts/check-host.sh`.
- [ ] Decide the first rootfs source:
  - Option A: Armbian build framework rootfs output.
  - Option B: temporary Armbian-like Debian/Ubuntu aarch64 console rootfs via `debootstrap`, used only to prove the V90S boot path.
- [ ] If using Armbian build framework, fetch/update it with `./scripts/fetch-reference-sources.sh --with-armbian`.
- [ ] Create a reproducible script for the first minimal aarch64 console rootfs.
- [ ] Ensure the rootfs has:
  - `/sbin/init`
  - `/proc`, `/sys`, `/dev`, `/run` mount points
  - root shell or deterministic root login for bring-up
  - console/getty path for `tty0`/`tty1` and `ttyS0`
  - no desktop stack
- [ ] Pack the rootfs as squashfs.
- [ ] Record rootfs build commands, size, hash, and package basis in `docs/validation/`.

## Next: Image Assembly

- [ ] Assemble `plumos-v90s-armbian-step1-YYYYMMDD-1.img` with the Armbian-derived squashfs.
- [ ] Keep the FAT partition near the current 33MB default when possible.
- [ ] If the Armbian rootfs does not fit in the small FAT, prefer adding a rootfs partition or adjusting initramfs/root mounting over expanding FAT to a large size.
- [ ] Verify the generated image on the host:
  - `ls -lh`
  - `shasum -a 256`
  - `file`
  - `gpt -r show`
  - squashfs contents check
- [ ] Add a validation note for the generated image.

## Device Test 1

- [ ] Provide the generated image path and sha256 to the user.
- [ ] User flashes the image to SD and tests on V90S.
- [ ] Collect this report:

```text
image:
sha256:
SD card:

boot result:
screen:
USB keyboard:

commands:
- uname -a:
- cat /proc/cmdline:
- mount:
- ls /:
- ls /dev/input:
- dmesg | tail -80:

notes:
photo/log:
```

- [ ] Commit the device result under `docs/validation/`.

## Branches After Device Test

- [ ] If there is no visible boot activity, inspect boot offsets, boot package, GPT layout, and bootloader cmdline assumptions.
- [ ] If kernel boots but no console appears, focus on framebuffer console, `console=` parameters, getty, and init behavior.
- [ ] If console appears but USB keyboard fails, inspect USB host/input modules and `/dev/input` availability.
- [ ] If init fails, test a simpler init wrapper before debugging full systemd behavior.
- [ ] If `/boot_root/boot/knulli` is not found, confirm the real kernel cmdline and which partition the ramdisk mounts.

## Later

- [ ] Decide whether to keep squashfs-over-FAT or move rootfs to a dedicated partition for larger Armbian builds.
- [ ] Add a helper for compressing/releasing test images.
- [ ] Add an SD-writing checklist for macOS/Linux hosts.
- [ ] Explore whether a native Armbian board/family definition is worth maintaining after Step 1 works.
- [ ] Revisit open kernel / open U-Boot possibilities after the first boot-console proof.
