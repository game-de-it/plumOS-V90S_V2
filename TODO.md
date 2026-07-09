# TODO

Last updated: 2026-07-09

## Current Goal

Step 2: Run RetroArch on V90S real hardware with visible 60fps video, audible audio, and V90S built-in controller input.

Step 1 status: achieved on device test 15 with `plumos-v90s-armbian-step1-20260709-15-fb-text-fat-logs.img`.

## Working Rules

- Keep work in small git commits with clear investigation/build/test boundaries.
- Keep repeated-test images small. Current assembly defaults are 33MB FAT boot-resource and 64MB userdata.
- Use KNULLI only as the V90S boot-chain reference unless evidence shows a full KNULLI build is required.
- Treat Armbian-derived userspace/rootfs as the main target.
- Do not commit `artifacts/`; it may contain local ROMs or other test-only binaries.
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
- [x] Record device test 11: direct payload reached Debian init and Debian wrote to `/dev/fb0`, but the LCD still showed the KNULLI logo.
- [x] Expand the fb0 probe to clear the full virtual framebuffer and write white bands to both pages.
- [x] Build `plumos-v90s-armbian-step1-20260709-12-fb-full-probe.img`.
- [x] Record device test 12: boot logo disappeared and the full framebuffer probe became visible on the LCD.
- [x] Add a small userspace framebuffer console that draws text to `/dev/fb0`, reads `/dev/input/event*`, and runs commands through `/bin/sh`.
- [x] Build `plumos-v90s-armbian-step1-20260709-13-fb-console.img`.
- [x] Record device test 13: framebuffer console image reached Debian init, but screen stayed black and console log stayed empty.
- [x] Add framebuffer console stderr logging, startup marker drawing, and forced log flush/sync.
- [x] Build `plumos-v90s-armbian-step1-20260709-14-fb-console-logged.img`.
- [x] Record device test 14: framebuffer console executed commands and read USB keyboard input, but text was not visible because the font table was never initialized.
- [x] Fix framebuffer console font initialization and increase text scale.
- [x] Copy Debian and framebuffer console logs to the FAT boot-resource partition under `plumos-logs/`.
- [x] Build `plumos-v90s-armbian-step1-20260709-15-fb-text-fat-logs.img`.
- [x] Record device test 15: framebuffer console text was visible, USB keyboard input worked, `df` executed, and FAT logs were readable from macOS.
- [x] Define Step 2 as RetroArch bring-up: visible 60fps video, audible audio, and built-in controller input.
- [x] Add `artifacts/` to `.gitignore`.
- [x] Record Step 2 RetroArch plan in `docs/step2-retroarch-plan.md`.

## Step 2: RetroArch Bring-up

Target:

- [ ] Boot RetroArch from the generated V90S SD image.
- [ ] Launch local test ROM `artifacts/nes/Super Mario Bros..nes`.
- [ ] Show gameplay on the internal LCD.
- [ ] Reach approximately 60fps with no obvious pacing issue.
- [ ] Output audible sound.
- [ ] Use V90S built-in controls for Start, D-pad, A, and B.
- [ ] Save RetroArch launch/runtime logs to FAT under `/Volumes/KNULLI/plumos-logs/`.

Constraints:

- [x] Keep `artifacts/` out of git.
- [ ] Keep FAT boot-resource near 33MB.
- [ ] Grow userdata only if RetroArch/core payloads require it.
- [ ] Keep Step 1 console image as a known-good fallback.

First implementation tasks:

- [ ] Confirm the local NES test ROM exists before each Step 2 image build.
- [ ] Inventory RetroArch packaging/build options for Debian arm64 and KNULLI/Buildroot.
- [ ] Choose first NES libretro core for the fastest proof, likely `fceumm` or another lightweight packaged core.
- [ ] Add a Step 2 rootfs profile or launch mode.
- [ ] Add RetroArch config for the V90S runtime path:
  - video driver
  - audio driver
  - input driver
  - log verbosity
  - FPS display or logging
- [ ] Add a launcher that writes:
  - `plumos-v90s-retroarch-launch.log`
  - `plumos-v90s-retroarch.log`
- [ ] Map V90S built-in `/dev/input/event*` controls.
- [ ] Build first Step 2 RetroArch test image.
- [ ] User flashes image and verifies on real hardware.
- [ ] Analyze FAT logs and record result under `docs/validation/`.

Validation buckets:

- [ ] Video visible but FPS unknown.
- [ ] FPS near 60 confirmed.
- [ ] Audio device opens but audible output unconfirmed.
- [ ] Audible output confirmed.
- [ ] USB keyboard input works only.
- [ ] Built-in controls work in game.
- [ ] Built-in controls fail; event mapping needed.

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
- [x] User flashes the image to SD and tests on V90S.
- [x] Wait at least 60 seconds at the boot logo, changed screen, or console.
- [x] Check whether the screen changes from the KNULLI boot logo.
- [x] Result: screen still shows only the KNULLI boot logo; console did not appear.
- [x] FAT diagnostic logs were not present.
- [x] Userdata ext4 logs were recovered and analyzed.
- [x] Result: direct payload route mounted `/dev/mmcblk0p5`, attached payload to `/dev/loop2`, mounted Debian rootfs, and switched to payload `/sbin/init`.
- [x] Result: `plumos-v90s-debian-init.log` was present.
- [x] Result: Debian init saw `fb0` as `640x480p-60`, `virtual_size=640,960`, `bits_per_pixel=32`, `stride=2560`.
- [x] Result: Debian init wrote black and white probes to `/dev/fb0` successfully.
- [x] Result: no `plumos-v90s-stage1.log` was present, as expected because the direct route did not fall back to stage1.

## Device Test 12

- [x] Provide `output/images/plumos-v90s-armbian-step1-20260709-12-fb-full-probe.img`.
- [x] Host-verify that Debian init writes a full virtual framebuffer black fill and white bands to page 0 and page 1.
- [x] Host-verify that direct payload route remains present.
- [x] Host-verify compact 33MB FAT plus 64MB userdata layout.
- [x] User flashes the image to SD and tests on V90S.
- [x] Wait at least 60 seconds at the boot logo, changed screen, or console.
- [x] Check whether the screen changes from the KNULLI boot logo.
- [x] Result: KNULLI boot logo disappeared.
- [x] Result: screen changed to the expected black framebuffer with a white band near the top.
- [x] Result: FAT diagnostic logs were not present.
- [x] Result: userdata ext4 logs were recovered and analyzed.
- [x] Result: direct payload route still reached Debian `/sbin/init`.
- [x] Result: Debian init saw `fb0` as `640x480p-60`, `virtual_size=640,960`, `bits_per_pixel=32`, `stride=2560`.
- [x] Result: Debian init wrote the full black fill and white bands to page 0 and page 1.
- [x] Result: `/dev/fb0` userspace writes are visible on the V90S LCD.

## Device Test 13

- [x] Provide `output/images/plumos-v90s-armbian-step1-20260709-13-fb-console.img`.
- [x] Host-verify that Debian payload contains `/usr/local/sbin/v90s-fb-console`.
- [x] Host-verify that Debian init executes `v90s-fb-console` after the fb0 probe.
- [x] Host-verify compact 33MB FAT plus 64MB userdata layout.
- [x] User flashes the image to SD and tests on V90S.
- [x] Wait at least 60 seconds for framebuffer text to appear.
- [x] Check whether startup text appears instead of the white-band probe.
- [x] Result: KNULLI boot logo disappeared, then the screen stayed black.
- [x] Result: USB keyboard key presses did not visibly affect the screen.
- [x] Result: Caps Lock LED did not toggle, but this is not conclusive because the userspace console does not drive keyboard LEDs.
- [x] Result: FAT stage1 hash matched the `-13` image.
- [x] Result: userdata ext4 logs were recovered and analyzed.
- [x] Result: Debian init reached `debian-init: starting framebuffer console`.
- [x] Result: `plumos-v90s-fb-console.log` and `rootfs/plumos-v90s-fb-console.log` were present but 0 bytes.
- [x] Result: dmesg showed the USB keyboard as `ELECOM ELECOM TK-FCP096`, `input3/input4`, `hidraw0/hidraw1`, and `usbhid`.

## Device Test 14

- [x] Provide `output/images/plumos-v90s-armbian-step1-20260709-14-fb-console-logged.img`.
- [x] Host-verify that Debian init captures framebuffer console stdout/stderr to userdata.
- [x] Host-verify that the framebuffer console no longer depends on Perl `Fcntl` constants.
- [x] Host-verify that the framebuffer console writes a large start marker and forced-flushes logs.
- [x] Host-verify compact 33MB FAT plus 64MB userdata layout.
- [x] User flashes the image to SD and tests on V90S.
- [x] Wait at least 60 seconds for framebuffer text or a large white start marker to appear.
- [x] Result: white frame/start marker appeared on the LCD.
- [x] Result: text still did not appear.
- [x] Result: typing `ls` and pressing Enter made the white frame blink.
- [x] Result: userdata logs confirmed `uname -a`, `ls /`, and `ls /dev/input` ran automatically.
- [x] Result: userdata logs confirmed USB keyboard input produced `> ls` and the command output.
- [x] Result: remaining display issue was the framebuffer console font table being assigned after the infinite event loop.

## Device Test 15

- [x] Provide `output/images/plumos-v90s-armbian-step1-20260709-15-fb-text-fat-logs.img`.
- [x] Host-verify that font bitmap initialization runs before the framebuffer console main loop.
- [x] Host-verify that framebuffer text scale is increased.
- [x] Host-verify that Debian init prepares `/boot/plumos-logs` on the FAT boot-resource partition.
- [x] Host-verify that the framebuffer console writes directly to `/boot/plumos-logs/plumos-v90s-fb-console.log`.
- [x] Host-verify compact 33MB FAT plus 64MB userdata layout.
- [x] User flashes the image to SD and tests on V90S.
- [x] Wait at least 60 seconds for framebuffer text to appear.
- [x] Result: framebuffer console text appeared on the internal LCD.
- [x] Result: USB keyboard input worked.
- [x] Result: `df` was typed and executed.
- [x] Result: command output was visible on screen.
- [x] Result: FAT logs were present under `/Volumes/KNULLI/plumos-logs/` and readable without sudo.
- [x] Attach a USB keyboard and type:

```text
df
```

- [x] Press Enter and check whether command output appears on screen.
- [x] Return the SD card and check FAT logs without sudo:

```text
/Volumes/KNULLI/plumos-logs/session.txt
/Volumes/KNULLI/plumos-logs/plumos-v90s-diag.log
/Volumes/KNULLI/plumos-logs/plumos-v90s-debian-init.log
/Volumes/KNULLI/plumos-logs/plumos-v90s-fb-console.log
```

## Console Command Check

- [x] If the framebuffer console accepts keyboard input, run at least one command and verify output appears on screen.
- [ ] Optional broader command inventory for the next validation pass:

```sh
uname -a
cat /proc/cmdline
mount
ls /
ls /dev/input
dmesg | tail -80
```

- [ ] Commit the device result under `docs/validation/`.
- [x] Commit the device result under `docs/validation/`.

## Branches After Device Test

- [x] If there is no visible boot activity, inspect boot offsets, boot package, GPT layout, and bootloader cmdline assumptions.
- [x] If kernel boots but no console appears, focus on framebuffer console, `console=` parameters, getty, and init behavior.
- [x] If `/dev/fb0` userspace writes work but framebuffer console is unavailable, add a tiny framebuffer terminal or boot-time getty bridge for Step 1.
- [x] If console appears but USB keyboard fails, inspect USB host/input modules and `/dev/input` availability.
- [x] If init fails, test a simpler init wrapper before debugging full systemd behavior.
- [x] If `/boot_root/boot/knulli` is not found, confirm the real kernel cmdline and which partition the ramdisk mounts.

## Later

- [ ] Decide whether to keep squashfs-over-FAT or move rootfs to a dedicated partition for larger Armbian builds.
- [ ] Add a helper for compressing/releasing test images.
- [ ] Add an SD-writing checklist for macOS/Linux hosts.
- [ ] Explore whether a native Armbian board/family definition is worth maintaining after Step 1 works.
- [ ] Revisit open kernel / open U-Boot possibilities after the first boot-console proof.
