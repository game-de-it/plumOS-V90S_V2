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
- [x] Add a reproducible Step 1 rootfs builder with stage1 plus Debian Bookworm arm64 minbase payload.
- [x] Add userdata payload support to the V90S image assembly script.
- [x] Build `plumos-v90s-armbian-step1-20260709-1.img` for the first real-device boot attempt.
- [x] Record device test 1: KNULLI boot logo appears, but no console yet.
- [x] Add Android `boot.img` cmdline override support.
- [x] Build `plumos-v90s-armbian-step1-20260709-2.img` with `root=/dev/mmcblk0p4`.
- [x] Record device test 2: same KNULLI boot logo only.
- [x] Add diagnostic initramfs support that writes `plumos-v90s-diag.log` to SD storage.
- [x] Build `plumos-v90s-armbian-step1-20260709-3-diag.img`.
- [x] Record device test 3: no FAT diagnostic log; boot package created `lcd_compatible_index.txt`.

## Next: Armbian Rootfs Path

- [x] Re-check build host capacity with `./scripts/check-host.sh`.
- [x] Decide the first rootfs source:
  - Option A: Armbian build framework rootfs output.
  - Option B: temporary Armbian-like Debian/Ubuntu aarch64 console rootfs via `debootstrap`, used only to prove the V90S boot path.
- [ ] Later, fetch/update Armbian build framework with `./scripts/fetch-reference-sources.sh --with-armbian` when moving beyond the first boot proof.
- [x] Create a reproducible script for the first minimal aarch64 console rootfs.
- [x] Ensure the rootfs has:
  - `/sbin/init`
  - `/proc`, `/sys`, `/dev`, `/run` mount points
  - root shell or deterministic root login for bring-up
  - console shell/getty path for `tty0`/`tty1` and `ttyS0`
  - no desktop stack
- [x] Pack the rootfs as squashfs.
- [x] Record rootfs build commands, size, hash, and package basis in `docs/validation/`.

## Next: Image Assembly

- [x] Assemble `plumos-v90s-armbian-step1-YYYYMMDD-1.img` with the Armbian-derived squashfs.
- [x] Keep the FAT partition near the current 33MB default when possible.
- [x] If the Armbian rootfs does not fit in the small FAT, prefer adding a rootfs partition or adjusting initramfs/root mounting over expanding FAT to a large size.
- [x] Verify the generated image on the host:
  - `ls -lh`
  - `shasum -a 256`
  - `file`
  - `gpt -r show`
  - squashfs contents check
- [x] Add a validation note for the generated image.

## Device Test 1

- [x] Provide the generated image path and sha256 to the user.
- [x] User flashes the image to SD and tests on V90S.
- [x] Collect this report:

```text
image: output/images/plumos-v90s-armbian-step1-20260709-1.img
sha256: d5ee904e669a5b0d292815cf2700f176f93bcb88b8f11d7946737ae1b94e850b
SD card:

boot result: KNULLI boot logo appears only
screen: KNULLI boot logo visible
USB keyboard: not testable yet

commands:
- uname -a: not reached
- cat /proc/cmdline: not reached
- mount: not reached
- ls /: not reached
- ls /dev/input: not reached
- dmesg | tail -80: not reached

notes: likely stuck before stage1 because boot.img cmdline used root=/dev/mmcblk0p1
photo/log:
```

- [x] Commit the device result under `docs/validation/`.

## Device Test 2

- [x] Provide `output/images/plumos-v90s-armbian-step1-20260709-2.img`.
- [x] User flashes the image to SD and tests on V90S.
- [x] Check whether the screen advances beyond the KNULLI boot logo.
- [x] Look for either stage1 text or the Debian minbase console:

```text
plumOS V90S stage1: looking for userdata rootfs payload
plumOS V90S Step1 Debian minbase console
```

- [x] Result: screen still shows only the KNULLI boot logo; console did not appear.

## Device Test 3

- [x] Provide `output/images/plumos-v90s-armbian-step1-20260709-3-diag.img`.
- [x] User flashes the image to SD and tests on V90S.
- [x] Wait at least 60 seconds at the boot logo.
- [x] Power off and return the SD card to the host.
- [x] Check FAT boot-resource partition for:

```text
plumos-v90s-diag.log
boot/plumos-v90s-diag.log
```

- [x] Result: no FAT diagnostic log was present.
- [x] Record extra FAT file `lcd_compatible_index.txt`, likely written by the boot package/U-Boot path.
- [ ] If a Linux host can mount userdata ext4, also check:

```text
rootfs/plumos-v90s-diag.log
```

- [x] Commit the no-log result and FAT extra-file evidence under `docs/validation/`.
- [x] If no log exists, move to serial UART or bootloader `boot.img` selection investigation.

## Console Command Check

- [ ] If console appears in any test, run:

```sh
uname -a
cat /proc/cmdline
mount
ls /
ls /dev/input
dmesg | tail -80
```

- [ ] Commit the device result under `docs/validation/`.

## Branches After Device Test

- [x] If there is no visible boot activity, inspect boot offsets, boot package, GPT layout, and bootloader cmdline assumptions.
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
