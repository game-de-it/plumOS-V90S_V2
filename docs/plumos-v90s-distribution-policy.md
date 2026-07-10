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

The boot-critical SD-card layout should continue to follow the
StockOS/Batocera contract until there is real-device evidence that a partition
can be removed safely:

```text
p1 boot-resource / Volumn vfat
p2 env
p3 env-redund
p4 boot Android boot image
p5 batocera squashfs
p6 rootfs / BATOCERA ext4
p7 rootfs_data / SHARE, StockOS observed as ext4; plumOS development images use FAT32
```

Current boot policy:

- keep p1 small and reserved for boot-resource compatibility
- keep p2, p3, and p4 unchanged unless intentionally replacing the vendor boot
  flow
- keep p5 as the read-only main system squashfs
- do not use p1 as the large user/update area
- validate any p6/p7 format or role change on real hardware before making it a
  release default

### System SquashFS and FAT32 App Layer

plumOS V90S should use a split similar to the plumOS MMF release model.

The basic Linux system belongs in the read-only squashfs. It should contain:

- init and mount policy
- minimal shell and diagnostic tools
- vendor runtime integration
- PowerVR/audio/input startup glue
- Wi-Fi and SSH development-mode support
- launch wrappers that define the stable runtime environment
- default configuration templates
- license and notice files needed for the base system

The user-visible plumOS application layer belongs in a FAT32 partition that can
be mounted on Windows or macOS and updated by copying files onto the SD card.
This layer should contain:

- frontend
- RetroArch
- libretro cores
- PICO/PicoArch components
- standalone emulators
- plumOS-owned private libraries
- themes and frontend assets
- user-editable configuration
- saves, states, screenshots, and logs
- ROM and BIOS directories
- update packages and manifests

Normal OS updates are performed with the SD card mounted on a Windows or macOS
host. The user copies an update package over the FAT32 app layer. Because the
device is powered off during this workflow, updating while RetroArch or the
frontend is running is out of scope for the normal release design.

The app layer should be mounted at a stable path such as:

```text
/mnt/plumos
```

The exact partition used for this FAT32 app layer is still a hardware
validation item for release images. The current development direction is to use
p7 `rootfs_data` / `SHARE` as a 1GB FAT32 app/update/data partition so the full
generated app layer can be carried in a single SD image. The intended release
direction remains:

```text
p1-p4: keep StockOS boot contract
p5:    plumOS system squashfs
p6/p7: one user-visible FAT32 plumOS app/update/data area, once validated
```

Until the boot chain proves that p6/p7 can be simplified, image assembly may
keep the existing partition count and assign the plumOS app layer to the safest
validated partition.

The chosen FAT32 app-layer partition must be sized from the generated payload,
not from the early boot-test image. The July 11 live V90S p7 was only about
55MB, which is enough for a targeted FE/RA/Wi-Fi update but too small for the
current full app-layer output that includes userland and network-service
payloads. The StockOS-compatible development assembler now defaults p7 to a
1024MB FAT32 `SHARE` image. If the generated app layer grows past that budget,
increase the partition size deliberately or split optional payloads before
treating full app-layer metadata as deployable to that partition.

FAT32 limitations must be treated as part of the ABI:

- no per-file Unix ownership or executable bits
- no native symlink or hardlink support
- weaker case-sensitivity behavior than Linux filesystems
- no safe assumption that upstream Linux library trees can be copied unchanged

For that reason, low-level vendor libraries should stay in the system squashfs
or vendor runtime area. FAT32 should hold plumOS-built applications and private
runtime libraries that are packaged to avoid symlink-dependent layouts.

Launch wrappers in the squashfs should define the app-layer environment
explicitly, including:

```text
PLUMOS_HOME=/mnt/plumos
PATH=/mnt/plumos/bin:...
LD_LIBRARY_PATH=/mnt/plumos/lib:...
RETROARCH_CONFIG_DIR=/mnt/plumos/config/retroarch
```

The FAT32 app layer should include release metadata:

```text
VERSION
manifest.json
checksums.sha256
COMPAT_VENDOR=v90s-stockos-r1
```

At boot or frontend startup, plumOS should verify the app-layer metadata well
enough to detect obvious partial copies or vendor-runtime mismatches. If the
metadata is invalid, the system should report the problem clearly in logs and on
the development console instead of silently rewriting user configuration.

## Build System Direction

The build entry point is:

```sh
./scripts/docker-build.sh
```

The build system should be shaped like the MMF workflow:

- Docker-based cross-build and packaging environment
- explicit targets for vendor runtime preparation
- explicit targets for command-line userland tools
- explicit targets for Wi-Fi/FTP/SFTP/Samba network service payloads
- explicit targets for RetroArch
- explicit targets for libretro cores
- explicit targets for standalone emulators
- explicit targets for frontend
- explicit targets for rootfs and SD image assembly
- explicit targets for FAT32 app-layer packaging
- full SD-root style packages for first installs
- update-only packages that can be copied over an existing FAT32 app layer
- manifests and hashes for generated artifacts

Armbian and Buildroot can remain useful references, but they should not force the
final distribution structure.

### Build System Completion Plan

The current build scripts started as Step 1/Step 2 bring-up tooling. They should
now be reshaped into a distribution build system with a clear build graph and
clear artifact ownership.

`scripts/docker-build.sh` is the only official user-facing build entry point.
Helper scripts may still exist under `scripts/` or
`docker/plumos-v90s-toolchain/scripts/`, but normal documentation and release
instructions should call them through `scripts/docker-build.sh`.

The official target set should become:

```text
image              build the Docker toolchain image
shell              open an interactive toolchain shell
vendor-runtime     prepare v90s-stockos-r1 from artifacts/
userland           build BusyBox and command-line tools for the app layer
network-services   build Wi-Fi/FTP/SFTP/Samba payloads for the app layer
sdl2-powervr       build the patched SDL2 PowerVR compatibility payload
retroarch          build RetroArch for the V90S PowerVR fbdev route
cores              build supported libretro cores
quicknes           compatibility alias for cores or one-core development
picoarch           build V90S PicoArch/PICO payloads
standalone         build supported standalone emulators
frontend           build the plumOS frontend
system-rootfs      build the read-only Linux system squashfs
app-layer          assemble the FAT32 plumOS app/update/data tree
sd-image           assemble the complete V90S SD-card image
release            assemble full and update-only release packages
all                build the normal release chain
```

Legacy or transitional targets may remain for bring-up work, but they must be
named as such:

```text
rootfs             transitional alias for system-rootfs
stockos-image      transitional alias for sd-image while the partition contract
                  is still StockOS/Batocera-compatible
knulli-image       legacy investigation target only
```

Implementation naming rule:

- plumOS-facing RetroArch artifacts use `retroarch-powervr` and
  `output/retroarch-powervr`
- `retroarch-knulli` remains only as a compatibility alias or legacy
  investigation name
- KNULLI source paths may still appear where the file is genuinely a reference
  patch/source input
- live device transfer should use `live-transfer-retroarch-powervr.sh` unless a
  historical validation note explicitly requires the old KNULLI-named helper

The build graph should be:

```text
artifacts/vendor/v90s-stockos-r1/
  -> vendor-runtime
  -> system-rootfs
  -> app-layer
  -> sd-image
  -> release

source pins and local patches
  -> userland
  -> network-services
  -> sdl2-powervr
  -> retroarch
  -> cores
  -> picoarch
  -> standalone
  -> frontend
  -> app-layer
```

`vendor-runtime` must prepare the stable hardware baseline:

- default input: `artifacts/vendor/v90s-stockos-r1/`
- default output: `output/vendor/v90s-stockos-r1/`
- compatibility alias: `output/vendor/stockos-runtime`
- manifest: `output/vendor/v90s-stockos-r1/vendor-runtime.manifest`
- hashes: `output/vendor/v90s-stockos-r1/SHA256SUMS`

The prepared vendor runtime should include the StockOS-derived boot and
hardware-enabling pieces only. It should not become a generic place for
plumOS-built applications.

`system-rootfs` must build the read-only squashfs. It should contain:

- init
- mount and app-layer discovery logic
- `/tmp`, `/run`, `/dev`, `/proc`, `/sys`, `/boot`, and `/mnt/plumos` setup
- vendor runtime startup glue
- PowerVR, audio, and input initialization
- development-mode Wi-Fi and SSH support
- safe process stop/restart helpers
- minimal diagnostics and recovery console
- launch wrappers that execute applications from the app layer
- default configuration templates
- base notices and licenses

Release `system-rootfs` builds must not contain user ROMs, user Wi-Fi
credentials, or normal app-layer payloads such as RetroArch, libretro cores,
frontend, PicoArch, and standalone emulators. Development profiles may bundle a
test ROM or temporary payload only when the profile name makes that explicit.

`app-layer` must assemble the FAT32-visible plumOS tree. It should collect:

- BusyBox and command-line userland tools
- Wi-Fi/FTP/SFTP/Samba network service payloads
- RetroArch
- libretro cores
- PicoArch/PICO payloads
- standalone emulators
- frontend
- plumOS-owned private libraries
- default and user-editable config directories
- themes and assets
- ROM, BIOS, saves, states, screenshots, and logs directories
- license notices for bundled app-layer components
- update metadata

The app-layer network service controller owns the user-facing Wi-Fi and SSH
service state alongside FTP, SFTP, and Samba so the frontend, logs, and
troubleshooting view all agree. On V90S the Wi-Fi path must assume an external
USB dongle rather than internal Wi-Fi, and scan/connect actions must return a
bounded failure when no dongle or no supported interface is present. The
app-layer controller may start or adopt the OpenSSH daemon supplied by the
system rootfs, but the visible SSH control command is still:

```text
/mnt/plumos/bin/plumos-network-services start|stop|status ssh
```

SSH login environments must prefer plumOS command tools:

```text
PATH=/mnt/plumos/bin:/mnt/plumos/gnu/bin:...
```

SFTP may provide an app-layer `sftp-server` payload, but it depends on the same
SSH service state. FTP, SSH, and Samba stop/restart logic should use PID files
plus `/proc/<pid>/cmdline` or `/proc/<pid>/comm` checks before terminating
processes.

The app-layer output should use a stable tree layout under:

```text
output/app-layer/v90s/
```

The on-device mount path should be:

```text
/mnt/plumos
```

The release package paths should follow the MMF style:

```text
dist/plumos-v90s-sdroot-VERSION/
dist/plumos-v90s-update-VERSION/
```

or archive equivalents generated from those directories.

The app-layer metadata must include:

```text
VERSION
manifest.json
checksums.sha256
COMPAT_VENDOR
```

`COMPAT_VENDOR` must be `v90s-stockos-r1` until the vendor runtime is
intentionally revised.

Every build target that emits a reusable artifact must emit checksums and a
manifest. Text manifests are acceptable for intermediate artifacts, but release
artifacts should have machine-readable JSON metadata.

Minimum metadata for reusable artifacts:

```text
artifact_name
artifact_type
target
version_or_git_ref
source_url_or_input_path
patches
builder_image
build_timestamp_utc
compat_vendor
output_path
sha256
```

Minimum metadata for the final SD image:

```text
image
image_sha256
vendor_runtime_id
vendor_runtime_manifest_sha256
system_rootfs
system_rootfs_sha256
app_layer_manifest_sha256
partition_layout
boot_chain_inputs
release_or_dev_profile
```

The image assembler should keep p1 through p4 compatible with StockOS until
there is real-device evidence that they can be changed. p5 should be the
plumOS system squashfs. One validated p6/p7 partition should become the
FAT32 app layer. The development assembler currently keeps p6 as the small
StockOS-compatible `BATOCERA` ext4 partition and formats p7 `SHARE` as 1GB
FAT32 for app-layer validation. Release builds should not regress to ext4
`SHARE` as the final app-layer design unless real-device evidence proves that a
different layout is required.

The build system must keep path ownership strict:

- `artifacts/`: ignored input-only files supplied by the user or extracted from
  devices
- `.cache/`: ignored downloaded or cloned source/reference material
- `output/`: ignored intermediate build output
- `dist/`: ignored release packages and release staging directories
- tracked repository files: build scripts, patches, configs, docs, manifests
  templates, and source owned by plumOS

Secrets and private content must not be baked into normal release artifacts:

- Wi-Fi SSID and password are development-profile inputs only
- SSH keys and root passwords are development-profile inputs only
- commercial ROMs are development/test inputs only and stay under `artifacts/`

Current implementation gaps to close:

- change default vendor-runtime paths from the date-based StockOS extraction
  names to `v90s-stockos-r1`
- run `vendor-runtime` preparation through the Docker entry point consistently
- implement `app-layer`
- move RetroArch, cores, frontend, PicoArch, and standalone emulators out of the
  release squashfs and into the FAT32 app layer
- implement `frontend`, `picoarch`, and `standalone` targets instead of leaving
  them reserved
- convert or validate one p6/p7 partition as the FAT32 app layer
- generate app-layer `manifest.json`, `checksums.sha256`, `VERSION`, and
  `COMPAT_VENDOR`
- make `release` produce full SD-root and update-only packages
- rename KNULLI-specific script/profile names where they now describe the
  stable StockOS-derived runtime, while preserving compatibility names only
  where the underlying implementation still requires them
- keep legacy KNULLI and Step 1/Step 2 bring-up paths available only as explicit
  diagnostic targets

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

- Whether p7 `rootfs_data` / `SHARE` is the final validated FAT32 plumOS app
  layer, or only a development-image bridge.
- Whether p6/p7 can be collapsed after the StockOS boot contract is fully
  understood.
- The final mount label and mount path for the FAT32 app layer.
- The exact file layout under `/mnt/plumos`.
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

Define persistent storage and the app/update/data partition without assuming
that p7 ext4 `rootfs_data` / `SHARE` remains the final design.

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

### 2026-07-10: System SquashFS plus FAT32 App Layer

Decision:

Use a two-layer distribution model. Keep the Linux base, init, mount policy,
vendor-runtime integration, and hardware startup glue in a read-only system
squashfs. Put the user-visible plumOS app layer on FAT32 so Windows and macOS
users can update by copying files onto the SD card.

The FAT32 app layer owns frontend, RetroArch, libretro cores, PICO/PicoArch,
standalone emulators, plumOS private libraries, themes, user configuration,
saves, states, screenshots, logs, ROM directories, BIOS directories, update
metadata, and update packages.

Rationale:

This matches the proven plumOS MMF-style update workflow while preserving the
V90S-specific StockOS boot and hardware runtime contract. Users should be able
to apply normal plumOS updates without rebuilding or rewriting the whole SD
image, and without depending on Linux filesystem tools on the host PC.

Constraints:

FAT32 is not a full Linux runtime filesystem. Do not place symlink-dependent
vendor runtime trees there. Keep boot, kernel, PowerVR, audio, input, and other
hardware-critical runtime pieces in the protected system/vendor layer unless a
specific replacement is validated.

Follow-up:

Choose and validate the actual FAT32 app-layer partition, then define the
release package layout and update-only package format.

### 2026-07-10: Build System Completion Plan

Decision:

Keep `scripts/docker-build.sh` as the official build entry point and complete
the build system around a distribution-oriented graph:

```text
vendor-runtime -> system-rootfs -> app-layer -> sd-image -> release
```

Application targets such as RetroArch, libretro cores, PicoArch, standalone
emulators, and frontend should build into reusable outputs, then be collected
into the FAT32 app layer rather than being baked into the release squashfs.

Rationale:

The current scripts already prove the important device bring-up path, but they
still mix experimental Step 1/Step 2 payloads with the future release layout.
The completed build system needs to preserve the working hardware baseline
while making ordinary plumOS updates copy-over friendly on Windows and macOS.

Constraints:

Release rootfs builds must stay small and hardware-focused. Private ROMs,
development Wi-Fi credentials, SSH credentials, and normal app-layer binaries
must not be hidden inside the release squashfs. Each reusable output needs
manifest and hash metadata so SD images and update packages can be audited.

Follow-up:

Implement the missing `app-layer`, `frontend`, `picoarch`, `standalone`, and
`release` targets; migrate vendor-runtime defaults to `v90s-stockos-r1`; and
validate which p6/p7 partition can safely become the FAT32 app layer.

### 2026-07-11: 1GB FAT32 p7 Development Image

Decision:

Use p7 `rootfs_data` / `SHARE` as a 1024MB FAT32 partition in the
StockOS-compatible development image assembler.

Rationale:

The earlier 55MB live p7 was useful for narrow SSH-deployed FE/RA/Wi-Fi tests,
but it cannot contain the full plumOS app layer once userland and network
service payloads are included. A 1GB FAT32 p7 keeps p1 small, preserves the
StockOS boot-critical partitions, and allows Windows/macOS copy-over update
testing with all plumOS-owned data present.

Constraints:

p7 FAT32 is still a hardware validation point. Keep p1 through p4 unchanged and
keep p6 as the small StockOS-compatible `BATOCERA` ext4 partition until there is
real-device evidence that the boot chain can tolerate a simpler layout.

Follow-up:

Build and boot-test a p7 FAT32 image on real V90S hardware, then record whether
`/mnt/plumos` mounts correctly, the frontend starts from the app layer, and
logs/configs remain visible from macOS or Windows.
