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
- [x] Inspect userdata ext4 from device test 3 and recover `plumos-v90s-diag.log`.
- [x] Confirm the V90S booted Linux 4.9.191, reached diagnostic initramfs `/init`, found `/boot/knulli` on `/dev/mmcblk0p4`, and persisted logs to userdata `/dev/mmcblk0p5`.
- [x] Fix diagnostic initramfs to loop-mount the `/boot/knulli` squashfs file before switching to stage1.
- [x] Build `plumos-v90s-armbian-step1-20260709-4-diag-loop.img`.
- [x] Record device test 4: diagnostic init still runs, but `/dev/loop0` squashfs mount fails.
- [x] Add KNULLI-style file mount probe path before explicit loop mount fallback.
- [x] Rebuild Debian minbase payload as gzip squashfs for kernel compatibility.
- [x] Build `plumos-v90s-armbian-step1-20260709-5-diag-mount-probe.img`.
- [x] Record device test 5: gzip stage1 squashfs is readable and loop-attached, but all squashfs mount attempts fail with `Invalid argument`.
- [x] Switch Step 1 squashfs payload generation to zstd to match KNULLI a133 rootfs settings.
- [x] Fix diagnostic dmesg tail command to BusyBox-compatible `tail -n 120`.
- [x] Build `plumos-v90s-armbian-step1-20260709-6-diag-zstd.img`.
- [x] Record device test 6: zstd `/boot/knulli` mounted successfully as the stage1 root, but the LCD still showed the KNULLI logo.
- [x] Confirm the V90S/KNULLI kernel config has `CONFIG_VT_CONSOLE=y` but `# CONFIG_FRAMEBUFFER_CONSOLE is not set`.
- [x] Add stage1 and Debian init logs that persist to userdata.
- [x] Add a direct `/dev/fb0` write probe in stage1 and Debian init.
- [x] Move the Debian payload loop mount from `/dev/loop0` to `/dev/loop1`.
- [x] Build `plumos-v90s-armbian-step1-20260709-7-stage1-fb-probe.img`.
- [x] Record device test 7: diagnostic still reached stage1 root, but no stage1/Debian logs were present.
- [x] Fix stage1 `/sbin/init` execution by adding `/bin/sh -> busybox`.
- [x] Persist a diagnostic marker immediately before `switch_root`.
- [x] Persist stage1/Debian logs before framebuffer writes.
- [x] Build `plumos-v90s-armbian-step1-20260709-8-stage1-sh-prepersist.img`.
- [x] Record device test 8: diagnostic reached pre-`switch_root` marker, but no stage1/Debian logs were present.
- [x] Add diagnostic userdata handoff mount at `/new_root/mnt/share`.
- [x] Teach stage1 to use a pre-mounted `/mnt/share` payload before scanning block devices.
- [x] Persist diagnostic logs through the handoff mount before `switch_root` and on the `switch_root` failure path.
- [x] Build `plumos-v90s-armbian-step1-20260709-9-stage1-share-handoff.img`.
- [x] Record device test 9: diagnostic persisted through handoff and reached `boot: switching to stage1 /sbin/init`, but no stage1/Debian logs were present.
- [x] Add tmpfs mounts for `/tmp` and `/run` before stage1/Debian init log writes.
- [x] Add a diagnostic chroot preflight that runs stage1 `/bin/sh` and writes to the handoff share.
- [x] Build `plumos-v90s-armbian-step1-20260709-10-stage1-tmpfs-log.img`.
- [x] Record device test 10: stage1 entered, used the pre-mounted share, mounted the Debian payload rootfs, then stopped before Debian logs.
- [x] Add a diagnostic direct-payload path that mounts userdata payload and switches from initramfs to Debian rootfs in one handoff.
- [x] Preserve moved `/dev` trees in stage1/Debian init and create `/dev/fb0` with `mknod` when sysfs exposes fb0.
- [x] Build `plumos-v90s-armbian-step1-20260709-11-direct-payload.img`.

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
- [x] Check userdata ext4 for:

```text
rootfs/plumos-v90s-diag.log
```

- [x] Result: userdata contained both `/plumos-v90s-diag.log` and `/rootfs/plumos-v90s-diag.log`.
- [x] Result: diagnostic init mounted `/dev/mmcblk0p4`, found `/boot/knulli`, then failed because the squashfs image file was mounted directly instead of through a loop device.
- [x] Commit the no-log result and FAT extra-file evidence under `docs/validation/`.
- [x] Defer serial UART for now because SD userdata logging proved the patched `boot.img` and initramfs path are active.

## Device Test 4

- [x] Provide `output/images/plumos-v90s-armbian-step1-20260709-4-diag-loop.img`.
- [x] Host-verify that diagnostic initramfs contains the `/dev/loop0` squashfs mount path.
- [x] User flashes the image to SD and tests on V90S.
- [x] Wait at least 60 seconds at the boot logo or console.
- [x] Check whether the screen advances beyond the KNULLI boot logo.
- [x] Result: screen still shows only the KNULLI boot logo; console did not appear.
- [x] FAT diagnostic logs were not present.
- [x] Userdata ext4 logs were recovered and analyzed.
- [x] Result: `/boot/knulli` was found, explicit `losetup` did not report failure, but mounting `/dev/loop0` as squashfs failed.

## Device Test 5

- [x] Provide `output/images/plumos-v90s-armbian-step1-20260709-5-diag-mount-probe.img`.
- [x] Host-verify that diagnostic initramfs tries KNULLI-style file mount first and records loop/mount diagnostics.
- [x] User flashes the image to SD and tests on V90S.
- [x] Wait at least 60 seconds at the boot logo or console.
- [x] Check whether the screen advances beyond the KNULLI boot logo.
- [x] Result: screen still shows only the KNULLI boot logo; console did not appear.
- [x] FAT diagnostic logs were not present.
- [x] Userdata ext4 logs were recovered and analyzed.
- [x] Result: `/boot/knulli` was readable and loop-attached, but all squashfs mount attempts failed with `Invalid argument`.

## Device Test 6

- [x] Provide `output/images/plumos-v90s-armbian-step1-20260709-6-diag-zstd.img`.
- [x] Host-verify that stage1 and Debian payload squashfs files use zstd compression.
- [x] Host-verify that diagnostic initramfs uses BusyBox-compatible `tail -n 120` for post-failure dmesg capture.
- [x] User flashes the image to SD and tests on V90S.
- [x] Wait at least 60 seconds at the boot logo or console.
- [x] Check whether the screen advances beyond the KNULLI boot logo.
- [x] Result: screen still shows only the KNULLI boot logo; console did not appear.
- [x] FAT diagnostic logs were not present.
- [x] Userdata ext4 logs were recovered and analyzed.
- [x] Result: zstd `/boot/knulli` mounted with the KNULLI-style file mount and listed a valid stage1 root.
- [x] Result: likely no visible text console because the closed V90S/KNULLI kernel has no framebuffer console.

## Device Test 7

- [x] Provide `output/images/plumos-v90s-armbian-step1-20260709-7-stage1-fb-probe.img`.
- [x] Host-verify that stage1 logs to userdata and uses `/dev/loop1` for the Debian payload.
- [x] Host-verify that stage1 and Debian init include `/dev/fb0` white-band probes.
- [x] User flashes the image to SD and tests on V90S.
- [x] Wait at least 60 seconds at the boot logo, changed screen, or console.
- [x] Check whether the screen changes from the KNULLI boot logo.
- [x] Result: screen still shows only the KNULLI boot logo; console did not appear.
- [x] FAT diagnostic logs were not present.
- [x] Userdata ext4 logs were recovered and analyzed.
- [x] Result: diagnostic still mounted zstd `/boot/knulli` as stage1 root.
- [x] Result: no `plumos-v90s-stage1.log` or `plumos-v90s-debian-init.log` was present.
- [x] Result: host inspection found stage1 `/sbin/init` uses `#!/bin/sh`, but stage1 lacked `/bin/sh`.

## Device Test 8

- [x] Provide `output/images/plumos-v90s-armbian-step1-20260709-8-stage1-sh-prepersist.img`.
- [x] Host-verify that stage1 contains `/bin/sh -> busybox`.
- [x] Host-verify that diagnostic init persists a pre-`switch_root` marker.
- [x] Host-verify that stage1 persists logs before framebuffer probing.
- [x] User flashes the image to SD and tests on V90S.
- [x] Wait at least 60 seconds at the boot logo, changed screen, or console.
- [x] Check whether the screen changes from the KNULLI boot logo.
- [x] Result: screen still shows only the KNULLI boot logo; console did not appear.
- [x] FAT diagnostic logs were not present.
- [x] Userdata ext4 logs were recovered and analyzed.
- [x] Result: diagnostic log included `boot: preparing to switch to stage1 /sbin/init`.
- [x] Result: no `plumos-v90s-stage1.log` or `plumos-v90s-debian-init.log` was present.

## Device Test 9

- [x] Provide `output/images/plumos-v90s-armbian-step1-20260709-9-stage1-share-handoff.img`.
- [x] Host-verify that diagnostic init mounts userdata at `/new_root/mnt/share` for stage1 handoff.
- [x] Host-verify that stage1 uses pre-mounted `/mnt/share` before scanning block devices.
- [x] Host-verify that diagnostic init persists through the handoff mount before `switch_root` and on `switch_root` failure.
- [x] User flashes the image to SD and tests on V90S.
- [x] Wait at least 60 seconds at the boot logo, changed screen, or console.
- [x] Check whether the screen changes from the KNULLI boot logo.
- [x] Result: screen still shows only the KNULLI boot logo; console did not appear.
- [x] FAT diagnostic logs were not present.
- [x] Userdata ext4 logs were recovered and analyzed.
- [x] Result: diagnostic log confirmed `/new_root/bin/sh -> busybox`.
- [x] Result: diagnostic mounted `/dev/mmcblk0p5` at `/new_root/mnt/share`.
- [x] Result: diagnostic persisted through `persist_device=stage1-share`.
- [x] Result: diagnostic reached `boot: switching to stage1 /sbin/init`; `boot: switch_root failed` was absent.
- [x] Result: no `plumos-v90s-stage1.log` or `plumos-v90s-debian-init.log` was present.

## Device Test 10

- [x] Provide `output/images/plumos-v90s-armbian-step1-20260709-10-stage1-tmpfs-log.img`.
- [x] Host-verify that stage1 and Debian init mount tmpfs on `/tmp` and `/run` before writing logs.
- [x] Host-verify that diagnostic init runs a stage1 `/bin/sh` chroot preflight and writes `plumos-v90s-stage1-preflight.log`.
- [x] User flashes the image to SD and tests on V90S.
- [x] Wait at least 60 seconds at the boot logo, changed screen, or console.
- [x] Check whether the screen changes from the KNULLI boot logo.
- [x] Result: screen still shows only the KNULLI boot logo; console did not appear.
- [x] FAT diagnostic logs were not present.
- [x] Userdata ext4 logs were recovered and analyzed.
- [x] Result: diagnostic log confirmed stage1 handoff mount and attempted stage1 preflight, but KNULLI busybox lacks the `chroot` applet.
- [x] Result: stage1 log was present.
- [x] Result: stage1 used the pre-mounted `/mnt/share` payload.
- [x] Result: stage1 saw fb0 sysfs data but `/dev/fb0` was not present.
- [x] Result: stage1 attached the Debian payload to `/dev/loop1`, mounted the payload rootfs, and reached `stage1: switching to payload rootfs`.
- [x] Result: no `plumos-v90s-debian-init.log` was present.

## Device Test 11

- [x] Provide `output/images/plumos-v90s-armbian-step1-20260709-11-direct-payload.img`.
- [x] Host-verify that diagnostic init mounts userdata payload directly on `/dev/loop2`.
- [x] Host-verify that diagnostic init switches directly to payload `/sbin/init` before the stage1 fallback.
- [x] Host-verify that stage1 and Debian init preserve existing `/dev` and can create `/dev/fb0`.
- [ ] User flashes the image to SD and tests on V90S.
- [ ] Wait at least 60 seconds at the boot logo, changed screen, or console.
- [ ] Check whether the screen changes from the KNULLI boot logo.
- [ ] If console appears, continue with the Console Command Check below.
- [ ] If console still does not appear, return the SD card and check FAT/userdata logs for the new failure point:

```text
plumos-v90s-diag.log
boot/plumos-v90s-diag.log
rootfs/plumos-v90s-diag.log
plumos-v90s-debian-init.log
rootfs/plumos-v90s-debian-init.log
plumos-v90s-stage1.log
rootfs/plumos-v90s-stage1.log
```

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
- [x] If kernel boots but no console appears, focus on framebuffer console, `console=` parameters, getty, and init behavior.
- [ ] If `/dev/fb0` userspace writes work but framebuffer console is unavailable, add a tiny framebuffer terminal or boot-time getty bridge for Step 1.
- [ ] If console appears but USB keyboard fails, inspect USB host/input modules and `/dev/input` availability.
- [ ] If init fails, test a simpler init wrapper before debugging full systemd behavior.
- [ ] If `/boot_root/boot/knulli` is not found, confirm the real kernel cmdline and which partition the ramdisk mounts.

## Later

- [ ] Decide whether to keep squashfs-over-FAT or move rootfs to a dedicated partition for larger Armbian builds.
- [ ] Add a helper for compressing/releasing test images.
- [ ] Add an SD-writing checklist for macOS/Linux hosts.
- [ ] Explore whether a native Armbian board/family definition is worth maintaining after Step 1 works.
- [ ] Revisit open kernel / open U-Boot possibilities after the first boot-console proof.
