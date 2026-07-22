# Architecture and Ownership

## Layer Model

```text
StockOS vendor baseline (v90s-stockos-r1)
  boot0 / boot package / Linux 4.9.191 / DTB / vendor modules
  PowerVR GE8300 EGL/GLES / ALSA codec / adc_gamepad / USB drivers
                         |
plumOS System SquashFS (read-only, p1 A/B)
  init / update engine / mount orchestration / rootfs libraries / diagnostics
                         |
plumOS Runtime (writable ext4, p3)
  frontend / launchers / emulators / cores / apps / services / config / saves
                         |
plumOS User Data (FAT32, p4 or SD2 content bindings)
  ROMs / BIOS / artwork / themes / media / update inbox / host-readable logs
```

The vendor layer is a redistributable binary input, not reconstructed source.
Record its origin and hashes in the vendor manifest, and create a new runtime ID
only when the low-level baseline changes. Normal plumOS releases advance while
remaining compatible with `v90s-stockos-r1`.

## Process and Mount Ownership

| Path or resource | Owner | Rule |
| --- | --- | --- |
| `/` | active p1 System SquashFS | read-only after `switch_root` |
| `/mnt/plumos-boot` | p1 PLUMBOOT | read-only except inactive-slot update |
| `/mnt/plumos` | p3 PLUMOS_SYS | plumOS runtime ABI and persistent Linux state |
| `/mnt/plumos-user` | p4 PLUMOS | FAT32 host interchange |
| `/run/plumos` | tmpfs | PID, lock, generated audio, and transient state |
| `/dev/fb0` | one foreground renderer | FE, emulator, app, or power overlay |
| physical input devices | active frontend/helper | never leave duplicate readers |
| ALSA `default` | plumOS audio router | internal mono or USB-DAC stereo |

At bootstrap, p4 `roms`, `bios`, and `Images` are bind-mounted over the same
paths below `/mnt/plumos`; `Themes` is bound to `/mnt/plumos/themes-user`. If
SD2 is present, only `roms` and `bios` are replaced by SD2 bindings. This
preserves the stable application-facing path while keeping portable files on
FAT32.

## Persistent and Mutable Data

plumOS-managed immutable or replaceable files include executables, shared
libraries, cores, frontend code, launch metadata, factory defaults, notices,
and manifests. Device-owned mutable paths include active config, saves, states,
logs, PortMaster-installed content, Pyxel environments, credentials, SSH home,
and user files. Runtime updates must enforce this ownership boundary.

## Compatibility Names

PowerVR-facing plumOS names use `sdl2-powervr` and `PowerVR GE8300`. Vendor or
upstream compatibility strings such as `SDL_VIDEODRIVER=mali` and
`video_context_driver=mali_fbdev` remain where required and must not be renamed
without proving the complete display path.

## Source of Truth

1. Current source and executable contracts
2. [Distribution policy](../plumos-v90s-distribution-policy.md)
3. [Update contract](../plumos-v90s-update-contract.md)
4. Current generated manifests and checksums
5. Dated validation evidence
6. Historical Step 1/Step 2 plans
