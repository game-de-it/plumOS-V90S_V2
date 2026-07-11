# TODO

Last updated: 2026-07-12

This TODO follows `docs/plumos-v90s-distribution-policy.md`. Historical Step 1
and Step 2 bring-up details are preserved in git history and `docs/validation/`.
Do not use old Armbian-first or KNULLI-first notes as the current plan.

## Current Goal

Build plumOS V90S as a V90S-specific distribution:

- StockOS/Batocera-derived vendor runtime provides boot, kernel, PowerVR, audio,
  and low-level input support.
- plumOS owns userspace behavior, init, launchers, RetroArch, cores, standalone
  emulators, frontend, configuration, image assembly, and releases.
- The Linux base lives in a read-only system squashfs.
- The user-visible app/update/data layer lives on a FAT32 partition mounted at
  `/mnt/plumos`.
- Normal updates are applied from Windows or macOS by copying update files onto
  the SD card.

## Working Rules

- Read `docs/plumos-v90s-distribution-policy.md` before design or
  implementation work.
- Keep work in small git commits with clear build, validation, or documentation
  boundaries.
- Keep `artifacts/`, `.cache/`, `output/`, and `dist/` out of git.
- Treat `artifacts/` as input-only. It may contain private ROMs, extracted
  vendor files, credentials, or other local-only material.
- User performs real-device validation. Record each result under
  `docs/validation/`.
- Do not add hidden runtime fallback paths. Keep validation routes explicit.
- Stop live device processes only through PID-file based tools that validate
  `/proc/<pid>/comm` or `/proc/<pid>/cmdline`.
- Do not use broad process-name kills that can affect SSH or unrelated sessions.
- Release builds must not contain private ROMs, Wi-Fi credentials, SSH keys, or
  root passwords.

## Completed Baseline

- [x] Step 1 boot console achieved: framebuffer console text visible, USB
  keyboard input works, and commands such as `df` execute.
- [x] Step 2 RetroArch baseline achieved on real V90S hardware.
- [x] Known-good runtime documented in
  `docs/validation/2026-07-10-step2-stockos-video-perfect-runtime.md`.
- [x] Known-good RetroArch path: `video_driver=gl`,
  `video_context_driver=mali_fbdev`, `video_refresh_rate=58.917103`,
  `video_threaded=true`, `vrr_runloop_enable=true`, ALSA `hw:0,0`, QuickNES.
- [x] User confirmed FPS, scrolling, controls, audio output, and audio pitch are
  good on the live device.
- [x] StockOS/Batocera runtime extracted into ignored artifacts.
- [x] Initial Docker build entry point exists at `scripts/docker-build.sh`.
- [x] Initial StockOS/Batocera-layout image assembler exists.
- [x] Distribution policy documented.
- [x] Vendor runtime identity documented as `v90s-stockos-r1`.
- [x] System squashfs plus FAT32 app layer policy documented.
- [x] Build system completion plan documented.

## Milestone 1: Vendor Runtime Formalization

- [x] Move the default vendor input path to
  `artifacts/vendor/v90s-stockos-r1/`.
- [x] Move the default prepared vendor output path to
  `output/vendor/v90s-stockos-r1/`.
- [x] Keep `output/vendor/stockos-runtime` only as a compatibility alias during
  migration.
- [x] Generate `output/vendor/v90s-stockos-r1/vendor-runtime.manifest`.
- [x] Ensure the vendor manifest includes:
  - `id=v90s-stockos-r1`
  - source image or extraction source
  - capture date
  - kernel version
  - boot model
  - GPU/display route
  - hashes
  - known-good validation document
- [x] Generate `output/vendor/v90s-stockos-r1/SHA256SUMS`.
- [x] Make `./scripts/docker-build.sh vendor-runtime` run consistently through
  the Docker entry point.
- [x] Require explicit opt-in before using KNULLI `boot0` / `boot_package`
  fallback assets in StockOS-layout image assembly.
- [x] Rename or isolate remaining KNULLI-specific runtime script/profile names
  that now describe the stable StockOS-derived runtime.

## Milestone 2: Build System Targets

- [x] Make `scripts/docker-build.sh` expose the official target set:
  - `image`
  - `shell`
  - `vendor-runtime`
  - `userland`
  - `network-services`
  - `sdl2-powervr`
  - `retroarch`
  - `cores`
  - `quicknes`
  - `picoarch`
  - `standalone`
  - `frontend`
  - `system-rootfs`
  - `app-layer`
  - `sd-image`
  - `release`
  - `all`
- [x] Keep `rootfs` as a transitional alias for `system-rootfs`.
- [x] Keep `stockos-image` as a transitional alias for `sd-image` while the
  partition contract remains StockOS/Batocera-compatible.
- [x] Keep `knulli-image` as a legacy investigation target only.
- [x] Implement `cores` as the normal libretro-core build target.
- [x] Keep `quicknes` as a compatibility or one-core development alias.
- [x] Implement `userland` for BusyBox and command-line tools.
- [x] Implement `network-services` for Wi-Fi/FTP/SFTP/Samba/ADB app-layer payloads.
- [ ] Implement `picoarch`.
- [ ] Implement `standalone`.
- [x] Implement `frontend`.
- [x] Implement `app-layer`.
- [x] Implement `release`.
- [ ] Implement `all` as the normal release build chain.
- [ ] Emit manifest and sha256 metadata for every reusable build output.
  - [x] `frontend` emits `output/frontend/v90s/frontend.manifest` and
    `output/frontend/v90s/checksums.sha256`.
  - [x] `userland` emits `output/userland/v90s/userland.manifest` and
    `output/userland/v90s/checksums.sha256`.
  - [x] `network-services` emits
    `output/network-services/v90s/network-services.manifest` and
    `output/network-services/v90s/checksums.sha256`.

## Milestone 3: System Rootfs

- [ ] Rename or introduce a release-oriented `system-rootfs` builder.
- [ ] Keep Step 1/Step 2 rootfs profiles as explicit development or diagnostic
  profiles only.
- [ ] Keep release `system-rootfs` focused on:
  - init
  - mount policy
  - `/tmp`, `/run`, `/dev`, `/proc`, `/sys`, `/boot`, `/mnt/plumos`
  - vendor runtime startup glue
  - PowerVR startup
  - audio startup
  - input startup
  - development-mode Wi-Fi and SSH hooks
  - safe process stop/restart helpers
  - minimal diagnostics and recovery console
  - app-layer launch wrappers
  - default configuration templates
  - base license and notice files
- [ ] Remove normal RetroArch binaries from release squashfs.
- [ ] Remove normal libretro cores from release squashfs.
- [ ] Remove frontend, PicoArch, and standalone emulators from release squashfs.
- [ ] Remove private ROMs from release squashfs.
- [ ] Ensure development-only Wi-Fi credentials and SSH credentials are never
  present in release squashfs.
- [ ] Make launch wrappers execute applications from `/mnt/plumos`.
- [ ] Make boot diagnostics report missing or invalid app-layer metadata clearly.
- [x] Disable the old fb0 black-screen/white-band boot probe by default; keep it
  available only through explicit diagnostic opt-in.
- [x] Start the frontend before slow development services by backgrounding
  PowerVR probe, rootfs Wi-Fi/SSH init, and app-layer network services.
- [x] Retry app-layer network services after rootfs Wi-Fi/DHCP completion so
  Samba is not lost when the first non-blocking service pass runs before
  interfaces are ready.
- [x] Keep SD2 FAT fsck enabled by default, but guard it with a short timeout
  so a bad SD2 cannot block FE startup indefinitely.
- [x] Reduce normal boot log sync pressure; keep forced boot-log sync behind an
  explicit diagnostic opt-in.
- [ ] Migrate the remaining rootfs-level `v90s-network-ssh-init` Wi-Fi/SSH
  bring-up into the plumOS app-layer network control path before disabling the
  old development hook.
- [x] Add a development init hook that probes p7/p6 for `/mnt/plumos`
  app-layer metadata and starts `/mnt/plumos/bin/plumos-frontend-launch` when
  present.

## Milestone 4: FAT32 App Layer

- [x] Define the app-layer tree under `output/app-layer/v90s/`.
- [x] Define the on-device mount path as `/mnt/plumos`.
- [x] Include app-layer metadata:
  - `VERSION`
  - `manifest.json`
  - `checksums.sha256`
  - `COMPAT_VENDOR`
- [x] Set `COMPAT_VENDOR` to `v90s-stockos-r1`.
- [x] Add directories for:
  - `bin/`
  - `gnu/`
  - `lib/`
  - `cores/`
  - `frontend/`
  - `picoarch/`
  - `standalone/`
  - `ssh/`
  - `samba/`
  - `config/`
  - `fonts/`
  - `share/`
  - `state/`
  - `themes/`
  - `media/`
  - `roms/`
  - `bios/`
  - `Saves/`
  - `States/`
  - `Screenshots/`
  - `Logs/`
  - `updates/`
  - `licenses/`
- [x] Copy RetroArch into the app layer.
- [x] Copy supported libretro cores into the app layer.
- [x] Copy frontend into the app layer.
- [x] Port the MMF-style FE Apps menu path to V90S with live-device validated
  `Scraping`, `File Manager`, and `RetroArch` entries.
- [x] Add the V90S-adapted MMF thumbnail scraper as
  `/mnt/plumos/bin/plumos-thumbnail-scraper`, using `/mnt/plumos/roms` and
  `/mnt/plumos/media/<system>/images`.
- [x] Copy BusyBox and command-line userland into the app layer.
- [x] Copy Wi-Fi/SSH/FTP/SFTP/Samba/ADB network service payloads into the app layer.
- [x] Add the MMF-compatible default `config/system/settings.json` so frontend
  system settings such as `wifi_enabled` can persist on V90S.
- [x] Expose `Network Settings` from the V90S START menu so Wi-Fi and network
  services are reachable from the frontend.
- [x] Live-validate the FE `Network Settings -> Wi-Fi` checkbox for runtime
  OFF/ON control: OFF stops `wpa_supplicant` and removes the IP, ON reconnects
  `wlan0`, restores the IP, and persists `wifi_enabled`.
- [x] Make `Network Settings` and `NW Service` open from saved config state
  instead of synchronously spawning every network-service status command; keep
  full runtime checks on the `INFORMATION` screen.
- [x] Live-validate FTP, SFTP, and Samba startup plus read/write access from a
  Mac client.
- [x] Add USB Disk Mode as a file-transfer fallback for unstable USB Wi-Fi
  dongles. It exposes a dedicated transfer image, not `/mnt/plumos` itself.
- [x] Add a USB command mailbox to USB Disk Mode so diagnostics can be queued
  as `commands/run.sh` plus `commands/ALLOW_EXECUTE` and results are written
  back to `RESULT-LATEST.txt` and `results/` after V90S remounts the transfer
  image.
- [ ] Physically validate USB Disk Mode from macOS with a data-capable USB
  cable and confirm the `PLUMUSB` drive appears, can be ejected, and remounts
  on V90S at `/mnt/plumos/usb-transfer`.
- [ ] Physically validate the USB command mailbox from macOS by copying a
  diagnostic `commands/run.sh`, creating `commands/ALLOW_EXECUTE`, ejecting
  `PLUMUSB`, unplugging USB, and confirming the result files on the next USB
  Disk Mode session.
- [x] Add standard ADB over USB FunctionFS/configfs as the intended interactive
  USB command path.
- [x] Physically validate ADB from macOS: enable ADB from the frontend or
  `plumos-network-services`, confirm `adb devices`, run `adb shell id`, and
  confirm file transfer with normal `adb push`/`adb pull`.
- [x] Register ADB in the FE NW Service screen and validate the frontend-facing
  service controller can stop/start ADB while keeping
  `/mnt/plumos/config/network/services.conf` in sync.
- [x] Validate that NW Service checkboxes use the persistent `enabled=` state
  while service status reports exact live process state for SSH, FTP, SFTP,
  Samba, and ADB.
- [x] Validate the FE navigation/action path for
  `START -> Network Settings -> NW Service -> ADB` by running the controller UI
  script path that presses `A` on the ADB checkbox and confirming `adb devices`
  disappears on OFF and returns on ON.
- [x] Investigate the 2026-07-12 ADB disconnect seen after SSH was re-enabled:
  it was not an `adbd` idle timeout. V90S had `adb_enabled=1`, `adbd` alive,
  FunctionFS mounted, but `gadget_bound=0`, `udc_state=not attached`, and macOS
  no longer enumerated `plumOS V90S ADB`; restarting only ADB over SSH rebound
  the gadget and restored `adb devices`.
- [ ] Physically confirm the FE ADB checkbox can be toggled with V90S controls
  during normal menu navigation.
- [ ] Investigate ADB host re-enumeration after repeated cable-attached
  stop/start cycles; V90S can report `udc_state=configured` while macOS sees
  `plumOS V90S ADB` but `adb devices` stays empty.
- [ ] Copy PicoArch/PICO payloads into the app layer.
- [ ] Copy standalone emulators into the app layer.
- [ ] Port a real V90S file-manager payload to replace the current safe file
  overview app once NextCommander or a stock-compatible equivalent is validated.
- [ ] Port and validate a V90S native Music Player before making
  `music_player` visible in Apps.
- [x] Copy plumOS-owned private libraries into the app layer.
- [x] Avoid symlink-dependent library layouts on FAT32.
- [x] Generate app-layer `manifest.json`.
- [x] Generate app-layer `checksums.sha256`.
- [x] Add boot/frontend startup checks for app-layer metadata in the
  development init path.
- [x] Validate frontend boot on real V90S hardware.
- [x] Live-validate the formal V90S fbdev frontend design after SSH reconnect,
  including a `/dev/fb0` capture and single-frontend-process check.
- [x] Align V90S settings-screen checkbox and option control placement with the
  MMF/A30-style frontend layout.
- [x] Keep V90S START/settings/Wi-Fi list cursors inside the visible fbdev
  screen by using a scroll window and 2x text for settings-family rows.
- [x] Formalize the V90S SD1 content roots as lowercase `roms/` and `bios/`,
  with FE ROM scanning rooted at `/mnt/plumos/roms`.
- [x] Define SD2 as an optional ROM/BIOS-only content layer that is mounted
  internally and bind-mounted onto `/mnt/plumos/roms` and `/mnt/plumos/bios`.
- [x] Add `plumos-sd2-content-mount start|status|stop|restart` for SD2 content
  mount control, including FAT fsck before FAT32/vfat mounts.
- [x] Expose FE reboot and shutdown actions through
  `/mnt/plumos/bin/plumos-safe-shutdown`, with SD2 content mounts stopped and
  filesystem sync performed before reboot or poweroff.
- [x] Add a final-action watchdog so a hung `reboot -f` or `poweroff -f` cannot
  block the already-synced FE Reboot/Shutdown path before reaching sysrq.
- [x] Change the normal FE Reboot/Shutdown path to direct sysrq after SD2 stop
  and sync, because BusyBox `reboot` / `poweroff` can return or hang on V90S.
- [x] Repair and revalidate the p7 FAT32 app layer after the kernel remounted
  `/mnt/plumos` read-only due to FAT corruption.
- [x] Improve FE Reboot/Shutdown so app-layer writers are stopped and p7
  `PLUMOS` is remounted read-only before final sysrq reboot/poweroff.
- [x] Replace the final p7 read-only remount with a stronger final-stage path
  that runs outside `/mnt/plumos`, unmounts p7 completely, and then triggers
  sysrq reboot/poweroff.
- [x] Add rootfs-side mount-before-fsck protection for p7 `PLUMOS` using
  `dosfstools`/`fsck.fat` so dirty FAT can be repaired before app-layer use.
- [x] Validate `plumos-v90s-appfat-1g-fatguard-20260711-1.img` on hardware
  and confirm FE Reboot no longer leaves p7 `PLUMOS` with the FAT dirty
  warning on the next boot.
- [x] Validate SD2 auto-mount from a clean reboot with SD2 inserted.

## Milestone 5: SD Image Layout

- [ ] Keep p1 through p4 compatible with the StockOS boot contract:
  - p1 boot-resource / PLUMBOOT
  - p2 env
  - p3 env-redund
  - p4 Android boot image
- [ ] Keep p1 small and reserved for boot-resource compatibility.
- [ ] Use p5 as the plumOS system squashfs.
- [x] Use p7 `rootfs_data` / `PLUMOS` as the current development FAT32
  app/update/data partition.
- [ ] Validate the chosen p6/p7 FAT32 layout on real hardware.
- [x] Increase the development FAT32 app-layer capacity to 1024MB so the full
  generated app-layer can be included without exceeding the current payload
  size.
- [ ] Keep an explicit development compatibility mode for the current p6/p7
  shape until the FAT32 app-layer partition is validated.
- [x] Stop treating ext4 `SHARE` as the current app-layer development design.
- [x] Include app-layer manifest hash in the SD image manifest.
- [x] Add `--app-layer-dir` support to the StockOS-compatible image assembler
  so current p7 development images can carry the app layer for frontend boot
  tests.
- [x] Include vendor-runtime manifest hash in the SD image manifest.
- [x] Include system-rootfs hash in the SD image manifest.

## Milestone 6: RetroArch Runtime Integration

- [ ] Move the normal RetroArch launch path to `/mnt/plumos`.
- [ ] Preserve the known-good V90S defaults:
  - `video_driver = "gl"`
  - `video_context_driver = "mali_fbdev"`
  - `video_refresh_rate = "58.917103"`
  - `video_threaded = "true"`
  - `vrr_runloop_enable = "true"`
  - `audio_driver = "alsa"`
  - `audio_device = "hw:0,0"`
  - `audio_latency = "64"`
  - `input_driver = "sdl2"`
  - `input_joypad_driver = "sdl2"`
- [ ] Ensure users can save RetroArch settings.
- [ ] Ensure frontend/config tooling does not overwrite user settings on every
  launch.
- [ ] Provide a resettable defaults mechanism.
- [ ] Write RetroArch launch and runtime logs to the app layer.
- [ ] Keep future Pulse/PipeWire audio experiments separate from the known-good
  ALSA path unless real-device validation proves a replacement.
- [ ] Keep future CPU governor or `irqbalance` experiments separate from the
  known-good video/audio baseline unless validation proves a benefit.

## Milestone 7: Release Packaging

- [ ] Generate a full SD-root style package:
  `dist/plumos-v90s-sdroot-VERSION/`.
- [x] Generate an update-only package:
  `dist/plumos-v90s-update-VERSION/`.
- [x] Ensure update-only packages can be copied over the FAT32 app layer from
  Windows or macOS.
- [x] Generate release `manifest.json`.
- [x] Generate release `checksums.sha256`.
- [ ] Include license and notice files for:
  - plumOS-owned files
  - POWKIDDY StockOS/Batocera-derived runtime files
  - RetroArch
  - libretro cores
  - bundled standalone emulators
  - bundled frontend dependencies
- [x] Ensure release archives do not contain private ROMs or credentials.
- [x] Document the copy-over update workflow for Windows and macOS users.

## Milestone 8: Validation

- [ ] Build the first policy-aligned development image with:
  - `v90s-stockos-r1` vendor runtime
  - system squashfs on p5
  - FAT32 app layer on the chosen p6/p7 partition
  - RetroArch launched from `/mnt/plumos`
- [ ] User boot-tests the development image on V90S.
- [ ] Record boot result under `docs/validation/`.
- [ ] Confirm LCD output.
- [ ] Confirm built-in controls.
- [ ] Confirm audio output.
- [ ] Confirm FPS, scrolling, and audio pitch remain at the known-good level.
- [ ] Confirm RetroArch settings persist after reboot.
- [ ] Confirm logs are visible from macOS or Windows through the FAT32 app
  layer.
- [ ] Test an update-only package by copying it onto the SD card from macOS or
  Windows.
- [ ] Record the update test result under `docs/validation/`.

## Deferred Reference Work

- [ ] Revisit Armbian only as a userspace/rootfs reference or component build
  helper.
- [ ] Revisit Buildroot only as a component build reference.
- [ ] Keep old KNULLI investigation paths available for comparison, but do not
  use them as the distribution identity.
- [ ] Add more libretro cores after the app-layer split is stable.
- [ ] Add standalone emulators after the app-layer split is stable.
- [ ] Add frontend workflows after the app-layer split is stable.
