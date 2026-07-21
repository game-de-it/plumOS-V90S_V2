# V90S Final Seed Automated Hardware Validation

Date: 2026-07-22
Result: Automated hardware checks PASS; physical control and listening checks remain

## Target

- image SHA-256:
  `8d580bf0f8c46c76b53fc6ef31276dfd119123db65dea6824b4dfb2153f9b3b9`
- Runtime: `0.1.0-dev`
- System: `0.1.0-dev`, active slot `a`
- device transport: standard ADB FunctionFS

## Boot and Storage

- p3 expanded to 8GiB and p4 FAT32 filled the remaining 106GiB
- p1 remained read-only during normal operation
- both System A/B images passed their stored SHA-256
- SD2 `roms` and `bios` were bind-mounted into the app runtime
- exactly one frontend process produced `/tmp/plumos-fe-ready`
- all 5,644 deployed app-runtime checksums passed before the build metadata
  follow-up

## SD2 RetroArch Route

The FE execution contract resolved `nes/Baseball.nes` to the app-layer
`plumos-retroarch-launch`, `/mnt/plumos/bin/retroarch`, and
`/mnt/plumos/cores/quicknes_libretro.so`. During execution:

- `/dev/fb0` changed from the FE hash and continued changing
- RetroArch reported QuickNES geometry at 60.00 FPS and 48kHz
- the process owned `/dev/snd/pcmC0D0p`
- the launcher selected `plumos_output`, internal mono, PowerVR
  `mali_fbdev`, SDL2 input, and the `ondemand` governor
- safe stop removed RetroArch and restored exactly one frontend
- launch and runtime logs were present under `/mnt/plumos/Logs`

The generated user RetroArch configuration contained the known-good V90S
video, audio, and input values. Its SHA-256 remained
`d0df443fa1748cd0232da2d4ae42edcd84ba543ea1b871f1f967fe315e0d3b5e`
after a safe reboot. `plumos-factory-reset ra --dry-run` also resolved the
tracked RA defaults and controller profiles.

## Update Failure Evidence

An intentionally invalid temporary update archive was rejected as non-gzip.
The same bounded JSON failure was written to p3
`update-state/last-result.json` and p4 FAT32
`plumos-logs/update/last-failure.json`. The invalid archive was removed after
the test. Physical host-side reading of p4 remains a separate user-visible
validation.

## Remaining Physical Checks

- built-in control response in the final seed game session
- audible quality, pitch, scrolling cadence, and perceived FPS
- safe poweroff followed by a cold boot
- p4 enumeration and failure-log reading from macOS or Windows
