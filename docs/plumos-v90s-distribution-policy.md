# plumOS V90S Distribution Policy

Date: 2026-07-10

This is the living policy document for deciding the overall shape of the
plumOS V90S distribution. Add later decisions here before turning them into
build scripts, image layout changes, or release behavior.

## Current Decision

plumOS V90S is a V90S-specific distribution.

It intentionally uses the proven POWKIDDY StockOS/Batocera low-level runtime as
the hardware baseline, while keeping the user-facing OS behavior under plumOS
control.

The current direction is:

- target only POWKIDDY V90S for now
- use StockOS-derived bootloader, kernel, kernel modules, GPU runtime, audio
  driver/runtime, and hardware-specific input drivers
- manage userspace, init, services, RetroArch, libretro cores, standalone
  emulators, frontend, launchers, settings, logs, and release images from
  plumOS
- treat Armbian and Buildroot as references or component build helpers, not as
  the identity of the final distribution

## Why

The V90S hardware depends on closed or vendor-specific pieces:

- Allwinner A133P boot flow
- StockOS Android boot image and env partitions
- Linux 4.9.191 kernel
- PowerVR GE8300 kernel modules, firmware, and userspace libraries
- fbdev/EGL display route used by RetroArch
- sunxi audio codec driver and mixer behavior
- adc_gamepad and other V90S input devices

Trying to replace all of these before shipping a working distribution would
spend time on low-level bring-up instead of the actual plumOS experience.

The practical path is to freeze the known-good hardware contract first, then
build a clean plumOS-controlled experience above it.

## Proven Baseline

The current known-good Step 2 result is documented in:

```text
docs/validation/2026-07-10-step2-stockos-video-perfect-runtime.md
```

The live-proven runtime used:

```text
kernel: Linux 4.9.191
userspace: Debian GNU/Linux 12 bookworm
GPU: PowerVR Rogue GE8300
RetroArch: 1.22.2
core: QuickNES
video_driver: gl
video_context_driver: mali_fbdev
video_refresh_rate: 58.917103
video_threaded: true
vrr_runloop_enable: true
audio_driver: alsa
audio_device: hw:0,0
```

User-visible result:

```text
fps, scrolling, and audio pitch are perfect.
```

This result is the current runtime anchor. Future changes should preserve this
path unless there is a deliberate replacement with equal or better real-device
evidence.

## Ownership Boundary

### Vendor Runtime

The vendor runtime is the hardware-enabling layer. It may be extracted from
StockOS/Batocera and prepared by plumOS tooling, but it is not treated as
plumOS-owned source.

Vendor-runtime responsibilities:

- `boot0`
- `boot_package`
- env partitions
- Android `boot.img`
- kernel image and initramfs behavior from StockOS
- Linux 4.9.191 kernel modules
- PowerVR GE8300 kernel modules
- PowerVR firmware and userspace GL/EGL libraries
- low-level display route required for `mali_fbdev`
- low-level ALSA codec driver behavior
- low-level V90S input devices such as `adc_gamepad`
- USB Wi-Fi kernel module support where needed for development access

The vendor runtime should be versioned as a stable input. The current vendor
runtime ID is:

```text
v90s-stockos-r1
```

Use this ID as the durable hardware-baseline name unless the underlying
StockOS-derived low-level runtime is intentionally replaced.

Recommended paths:

```text
raw artifact path:      artifacts/vendor/v90s-stockos-r1/
prepared output path:   output/vendor/v90s-stockos-r1/
manifest:               output/vendor/v90s-stockos-r1/vendor-runtime.manifest
display name:           V90S StockOS Vendor Runtime r1
```

The existing compatibility path may remain as a transitional alias:

```text
output/vendor/stockos-runtime
```

When this layer changes, record:

- source image or device source
- extraction command or script
- captured partition/runtime inventory
- hashes
- real-device validation result

The vendor manifest should include at least:

```text
id=v90s-stockos-r1
source=POWKIDDY V90S StockOS/Batocera-derived runtime
captured_at=2026-07-10
kernel=Linux 4.9.191
boot_model=a133-b6
gpu=PowerVR GE8300
display_route=mali_fbdev
known_good_step2=yes
known_good_doc=docs/validation/2026-07-10-step2-stockos-video-perfect-runtime.md
```

plumOS release versions and vendor runtime versions are separate. Normal
development should advance plumOS versions while keeping the vendor runtime
fixed:

```text
plumOS 0.1.0 + v90s-stockos-r1
plumOS 0.2.0 + v90s-stockos-r1
```

Image names may include the vendor ID when useful:

```text
plumos-v90s-dev-20260710-vendor-r1.img
plumos-v90s-ra-20260710-vendor-r1.img
plumos-v90s-release-0.1.0-vendor-r1.img
```

Create `v90s-stockos-r2` only if one of these is true:

- a different StockOS image or device source is used
- `boot.img`, kernel, modules, PowerVR runtime, audio runtime, or input runtime
  changes
- a low-level display/audio/input replacement is required
- the new runtime has equal or better real-device validation than
  `v90s-stockos-r1`

### plumOS Runtime

The plumOS runtime is the distribution behavior and user experience layer.

plumOS-owned responsibilities:

- rootfs contents
- init scripts and services
- overlay and writable storage policy
- `/tmp`, `/run`, `/dev`, `/proc`, `/sys`, `/boot`, `/mnt/share` setup
- SSH and development access policy
- RetroArch build and launch policy
- libretro cores
- standalone emulators
- frontend
- hotkeys
- safe process stop/restart behavior
- audio policy and volume UI
- brightness UI
- controller mapping and user-facing input policy
- save/state/screenshot/log directories
- user settings persistence
- release image assembly
- license and notice files

This layer should be reproducible from the repository and ignored local inputs.

## Naming Rules

Use hardware-accurate names in plumOS-facing paths.

Preferred plumOS names:

```text
sdl2-powervr
plumos-sdl2-powervr
PowerVR GE8300
vendor-runtime
```

Compatibility names may remain where upstream or vendor code requires them:

```text
SDL_VIDEODRIVER=mali
video_context_driver=mali_fbdev
```

Do not rename compatibility settings casually; document them as compatibility
names instead.

## Distribution Shape

The current SD-card layout should follow the StockOS/Batocera contract:

```text
p1 boot-resource / Volumn vfat
p2 env
p3 env-redund
p4 boot Android boot image
p5 batocera squashfs
p6 rootfs / BATOCERA ext4
p7 rootfs_data / SHARE ext4
```

Current policy:

- keep p1 small for repeated test writes
- keep p5 as the read-only main runtime squashfs
- make p7 the persistent user data partition
- mount or otherwise expose p7 so RetroArch config, saves, states, frontend
  settings, logs, and Wi-Fi settings survive reboot
- avoid relying on live overlay changes as the only copy of important settings

## Build System Direction

The build entry point is:

```sh
./scripts/docker-build.sh
```

The build system should be shaped like the MMF workflow:

- Docker-based cross-build and packaging environment
- explicit targets for vendor runtime preparation
- explicit targets for RetroArch
- explicit targets for libretro cores
- explicit targets for standalone emulators
- explicit targets for frontend
- explicit targets for rootfs and SD image assembly
- manifests and hashes for generated artifacts

Armbian and Buildroot can remain useful references, but they should not force the
final distribution structure.

## Configuration Policy

plumOS should ship known-good defaults but not lock users into them.

Current known-good NES/QuickNES RetroArch defaults:

```text
video_driver = "gl"
video_context_driver = "mali_fbdev"
video_refresh_rate = "58.917103"
video_threaded = "true"
threaded_data_runloop_enable = "true"
vrr_runloop_enable = "true"
video_vsync = "true"
video_swap_interval = "1"
audio_driver = "alsa"
audio_device = "hw:0,0"
audio_latency = "64"
audio_sync = "true"
input_driver = "sdl2"
input_joypad_driver = "sdl2"
```

Policy:

- users must be able to save RetroArch settings
- frontend/config tools must not silently overwrite user settings on every launch
- generated defaults should be resettable, not constantly regenerated
- diagnostics and fallback experiments must be explicit, not hidden inside normal
  launch paths

## Validation Policy

Do not treat a code change or image build as complete until the relevant
real-device behavior is validated.

For hardware-facing changes, record:

- image name
- rootfs/vendor-runtime inputs
- hashes
- boot result
- display result
- input result
- audio result
- logs or runtime snapshot location
- user-observed behavior

Validation notes live under:

```text
docs/validation/
```

Runtime snapshots live under:

```text
output/device-logs/runtime-snapshots/
```

## Open Decisions

Add future decisions here before implementation.

- How p7 `rootfs_data` / `SHARE` should be mounted and exposed.
- Which files belong in persistent user data.
- How frontend should launch RetroArch and standalone emulators.
- How user RetroArch config should be reset, backed up, or migrated.
- How release images should differ from development images.
- Which emulators/cores become first-class supported targets.
- How to package BIOS, user ROMs, saves, and screenshots without committing
  private content.
- How license notices should be bundled in release artifacts.

## Decision Log

### 2026-07-10: Distribution Foundation

Decision:

Use a V90S-specific distribution model. Keep StockOS/Batocera-derived
boot/kernel/GPU/audio/input hardware support as vendor runtime, and build the
plumOS userspace, emulators, frontend, settings, and release tooling above it.

Rationale:

The real device now has a known-good RetroArch path with correct video pacing,
scrolling, audio pitch, audio output, and controls. Replacing the low-level
vendor runtime before finishing the user-facing distribution would increase risk
without improving the immediate product.

Follow-up:

Define persistent storage using p7 `rootfs_data` / `SHARE`.

### 2026-07-10: Vendor Runtime Identity

Decision:

Use `v90s-stockos-r1` as the stable vendor runtime ID.

Rationale:

The vendor runtime is expected to be effectively fixed. A short revision-style
ID is clearer than a date-based ID because routine plumOS development should not
imply new vendor runtime captures. Capture dates, source details, hashes, and
known-good validation links belong in the vendor runtime manifest.

Follow-up:

Rename or alias prepared vendor output paths so future tooling can target
`output/vendor/v90s-stockos-r1/` while preserving the current
`output/vendor/stockos-runtime` compatibility path during migration.
