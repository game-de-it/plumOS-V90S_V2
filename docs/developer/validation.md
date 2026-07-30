# Validation and Evidence Index

## Evidence Rules

Validation records live under `docs/validation/` and are named
`YYYY-MM-DD-topic.md`. Each record should identify the build or deployed files,
hashes when applicable, commands or runtime evidence, physical-device result,
remaining risk, and the commit that made the result reproducible.

Do not treat a file existing on the host as proof that it runs on the V90S.
Useful device evidence includes process identity, mount ownership, ELF
architecture and dependency resolution, active configuration, checksums,
framebuffer ownership or screenshot, ALSA route, input events, exit behavior,
and FE recovery.

## Current Release Baseline

Start with these records:

- [Release 1.0.1 preparation](../validation/2026-07-31-v90s-release-1.0.1-preparation.md)
- [RTL8811CU driver-disk mode switch](../validation/2026-07-31-v90s-rtl8811cu-mode-switch.md)
- [Clean-clone release-image contract](../validation/2026-07-23-v90s-clean-clone-release-image.md)
- [Release 1.0.0 SD image](../validation/2026-07-23-v90s-release-1.0.0-image.md)
- [Release 1.0.0 preparation](../validation/2026-07-23-v90s-release-1.0.0-preparation.md)
- [Release 1.0.0 publication](../validation/2026-07-23-v90s-release-1.0.0-publication.md)
- [StockOS backlight route](../validation/2026-07-23-v90s-stockos-backlight.md)
- [Final automated seed validation](../validation/2026-07-22-v90s-final-seed-automated-validation.md)
- [Four-partition image](../validation/2026-07-22-v90s-four-partition-image.md)
- [Transactional update host validation](../validation/2026-07-22-v90s-transactional-update-host-validation.md)
- [User final validation](../validation/2026-07-22-v90s-user-final-validation.md)
- [PortMaster cleanup and license audit](../validation/2026-07-22-v90s-portmaster-cleanup-license-audit.md)
- [USB Disk Mode host writes](../validation/2026-07-11-usb-disk-mode.md)
- [USB Wi-Fi hotplug recovery](../validation/2026-07-22-v90s-wifi-hotplug-recovery.md)

## Evidence by Area

### Boot and Storage

- `2026-07-09-step1-*` and `device-test-*`: KNULLI-derived boot-chain and
  framebuffer-console progression
- `2026-07-11-boot-*`, `fat32-*`, `sd2-*`: startup, FAT safety, and SD2 content
- `2026-07-18-four-partition-*` through `2026-07-22-v90s-four-partition-*`:
  provisioning, recovery, and current image contract

### Frontend and Controls

- `2026-07-10-frontend-*` through `2026-07-14-v90s-top-*`: MMF port, renderer,
  menu, list, gallery, CJK, settings, and system information
- `2026-07-13-v90s-physical-keymap.md` and input-specific records: physical
  event mapping and emulator controls
- `2026-07-19-v90s-global-power-menu.md` and later power records: cross-runtime
  overlay, shutdown, and sleep lifecycle

### Video, Audio, and Performance

- `2026-07-10-step2-stockos-video-perfect-runtime.md` and refresh/sync sweep:
  adopted RetroArch video timing basis
- `2026-07-15-v90s-alsa-mono-usb-audio.md`: internal mono and USB-DAC routing
- `2026-07-16-v90s-global-volume-brightness-hotkeys.md` and
  `2026-07-19-v90s-volume-response-12-step.md`: system controls
- `2026-07-23-v90s-stockos-backlight.md`: six-step hardware backlight and
  independent Lumination contract
- PicoArch, standalone, and core-specific dated files: pacing, audio, rendering,
  input, and performance decisions

### Emulators and Apps

- `2026-07-13-v90s-*core*` and `2026-07-15-release-core-set-recovery.md`:
  canonical libretro set and deployment
- standalone records for YabaSanshiro, PPSSPP, PCSX-ReARMed, OpenBOR, ScummVM,
  EasyRPG, N64, Dreamcast, and removed DOSBox-staging route
- `2026-07-23-v90s-ppsspp-factory-identity.md`: removal of the captured PPSSPP
  network identity and release gates requiring per-installation MAC generation
- `2026-07-16-v90s-pyxel-*`, `2026-07-19-v90s-pyxel-*`: Python/Pyxel setup,
  aspect fit, inclusion, and pygame audio
- `2026-07-20-v90s-portmaster-*`: static audit, common ABI, architecture boundary,
  and representative hardware samples

### Network and Update

- Wi-Fi, network-information, FTP/SFTP/Samba, SSH-password, ADB, and USB recovery
  records dated July 11-22
- `2026-07-23-v90s-default-ssh-credential.md`: public initial credential
  `root / plumos`, device-local shadow preservation, System SquashFS, and
  real-device password-login validation
- `2026-07-22-v90s-transactional-update-host-validation.md` plus the adopted
  [update contract](../plumos-v90s-update-contract.md)

## Release Gate

Before release, require clean `git diff --check`, strict app-layer assembly,
license audit, preflight, image verification, archive checksums, no ROM/BIOS or
secrets, exact vendor compatibility, and physical cold boot. Then check FE
renderer, controls, audio, representative RA/PicoArch/standalone/App launch and
exit, save persistence, SD2, network service state, USB Disk Mode, safe reboot,
safe shutdown, and update rollback.

Unverified systems requiring private ROM or BIOS content remain user-report
follow-up, not fabricated pass results.
