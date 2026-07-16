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
audio_device: plumos_output
internal physical PCM: hw:0,0
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
p1 boot-resource / PLUMBOOT vfat
p2 env
p3 env-redund
p4 boot Android boot image
p5 batocera squashfs
p6 rootfs / BATOCERA ext4
p7 rootfs_data / PLUMOS, StockOS observed as ext4/SHARE; plumOS development images use FAT32
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
p7 `rootfs_data` / `PLUMOS` as a 4GB FAT32 app/update/data partition so the full
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
4096MB FAT32 `PLUMOS` image. If the generated app layer grows past that budget,
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

### FAT32 Write-Safety Contract

The normal release-update path remains an offline copy from Windows or macOS
while V90S is powered off. Live ADB deployment and network-based application
updates are development/runtime exceptions and must use a stricter write
contract:

- verify the complete source artifact before touching p7
- calculate the changed-file set before stopping the frontend
- keep ADB and SSH alive as recovery paths
- quiesce known p7 writers, including the frontend, hardware-key daemon,
  emulator sessions, FTP, and Samba
- stage transfer archives and metadata under `/run`, not on FAT32
- write payloads in bounded chunks, then `sync` and SHA-256 verify every chunk
- commit `manifest.json` and `checksums.sha256` only after all payload chunks
  have verified
- restore only services that were running before the deployment
- abort immediately if `/mnt/plumos` is absent or has become read-only

Frequent frontend state replacements, such as favorites, recent games, resume
state, core overrides, and the ROM library index, must use a temporary sibling
file followed by this durability sequence:

```text
write -> fflush -> fsync(file) -> close -> rename -> fsync(parent directory)
```

If the vendor FAT implementation rejects directory `fsync` with `EINVAL`, the
implementation may use a full `sync` as the compatibility fallback. Failure at
any other stage must be reported rather than silently accepting the new state.

Large in-device installers such as PortMaster must fully stage and sync the new
tree before switching `upstream`, preserve the previous tree until the switch is
complete, sync the parent directory after each rename/removal, and durably write
their installed-version metadata. The PortMaster GUI launch boundary must also
`sync` completed game installations before control returns to the frontend.

Filesystem repair is not part of a live deployment. Never run `fsck.fat` against
mounted p7; repair belongs to the bounded pre-mount boot path or an offline host
workflow.

Launch wrappers in the squashfs should define the app-layer environment
explicitly, including:

```text
PLUMOS_HOME=/mnt/plumos
PATH=/mnt/plumos/bin:...
LD_LIBRARY_PATH=/mnt/plumos/lib:...
RETROARCH_CONFIG_DIR=/mnt/plumos/config/retroarch
```

RetroArch directory settings must not silently resolve to
`/root/.config/retroarch`. V90S launch-time migration owns only unset,
`default`, `nul`, and legacy `/root`/tilde defaults; an explicit custom path
chosen by the user must be preserved. The canonical layout is:

```text
/mnt/plumos/config/retroarch   RA configuration, playlists, overlays, filters
/mnt/plumos/config/shaders     GLSL shader presets and source files
/mnt/plumos/bios               system/BIOS files
/mnt/plumos/Saves              save files, with per-system launch subdirectory
/mnt/plumos/States             save states, with per-system launch subdirectory
/mnt/plumos/Screenshots        screenshots
/mnt/plumos/Recordings         recordings
/mnt/plumos/Images/retroarch   RetroArch thumbnails
/mnt/plumos/Logs/retroarch     logs and runtime logs
/run/plumos/cache/retroarch    disposable cache; never persistent FAT data
```

Read-only system assets and databases may remain under `/usr/share/libretro`.
The launcher must create writable targets before starting RetroArch and keep
`config_save_on_exit` compatible with this layout.

Normal RetroArch launch must not run the early bring-up diagnostic sweep or
force repeated full-filesystem synchronization. Mount/input/ALSA/PowerVR,
RetroArch feature, dmesg, and ROM-hash collection belongs behind the explicit
`PLUMOS_V90S_RETROARCH_DIAGNOSTICS=1` switch. Per-log `sync` is separately
diagnostic-only through `PLUMOS_V90S_RETROARCH_SYNC_LOGS=1`; safe shutdown and
bulk-deploy boundaries remain responsible for normal filesystem durability.
Persistent RetroArch config migrations must be versioned and idempotent, not
rescanned on every game launch. Per-game save/state destinations belong in the
volatile append-config so normal launch does not rewrite the user's main config.
Generated app-runtime SONAME links must be signature-cached per boot; individual
emulator launches must not rebuild the complete compatibility map when its
signature is unchanged. Background prewarming must not leave an unreaped child
under the vendor PID 1 or move noticeable latency into frontend startup.

Power actions are a special case. The frontend may expose a compatibility
entry point in the FAT32 app layer, but the final Reboot/Shutdown implementation
must live in the system squashfs and run without depending on `/mnt/plumos`.
For the same reason, the system squashfs/rootfs owns the first writable mount of
p7 `PLUMOS`: before mounting p7 read-write, init should run a bounded
`fsck.fat -a`/`dosfsck -a` pass when the target is FAT32/vfat and the tool is
available. If the check reports an unrecoverable error or times out, the init
path should avoid a normal writable app-layer mount instead of continuing to
write into a suspicious FAT filesystem.

Before the final sysrq reboot or poweroff, that rootfs-owned helper should:

- stop SD2 bind mounts under `/mnt/plumos/roms` and `/mnt/plumos/bios`
- stop app-layer writers such as the frontend, FTP, Samba, RetroArch, and
  app-layer launch wrappers
- avoid killing SSH/dropbear diagnostic sessions by process name
- write final transient logs under `/run`, not into the FAT32 app layer
- sync filesystems
- unmount `/mnt/plumos` completely when possible
- unmount `/boot` too when it is a writable FAT boot-resource mount
- only then trigger sysrq reboot or poweroff

The FAT32 app-layer helper should therefore be a thin compatibility wrapper
around a rootfs command such as:

```text
/usr/sbin/plumos-power-action
```

This keeps the Windows/macOS-friendly update partition from being the final
executor during power loss-sensitive operations. If the rootfs helper is absent
on an old development image, that should be treated as a compatibility gap, not
as the release design.

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
- explicit targets for Wi-Fi/FTP/SFTP/Samba/ADB network service payloads
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
network-services   build Wi-Fi/FTP/SFTP/Samba/ADB payloads for the app layer
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
- base Python 3 runtime, `venv`, and `pip` tooling for user-managed Python apps
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
- user-created Python virtual environments, wheel caches, and Python app modules
- plumOS-owned private libraries
- default and user-editable config directories
- themes and assets
- ROM, BIOS, saves, states, screenshots, and logs directories
- license notices for bundled app-layer components
- update metadata

The app-layer network service controller owns the user-facing Wi-Fi and SSH
service state alongside FTP, SFTP, Samba, and ADB so the frontend, logs, and
troubleshooting view all agree. On V90S the Wi-Fi path must assume an external
USB dongle rather than internal Wi-Fi, and scan/connect actions must return a
bounded failure when no dongle or no supported interface is present.

`Network Settings -> Wi-Fi` controls the running USB Wi-Fi connection through
`plumos-network-control --wifi on|off` and persists the user's requested state
as `wifi_enabled` in `/mnt/plumos/config/system/settings.json`. Boot-time Wi-Fi
bring-up must eventually honor the same key; while the legacy rootfs
`v90s-network-ssh-init` hook remains, this is a known migration boundary rather
than a separate source of truth.

`Network Settings -> INFORMATION` must refresh and read the V90S runtime status
from `/run/plumos/network-control/wpa_status.txt`. The frontend passes that same
path to `plumos-network-control` as `PLUMOS_WPA_STATUS`, so producer and consumer
cannot silently diverge. `/mnt/plumos/config/network/wpa_status.txt` is a
persistent troubleshooting mirror, not the live frontend source. The older
`/tmp/wpa_status.txt` path is A30/MMF compatibility history and is not the V90S
release default.

`Network Settings -> NW Service` checkboxes are persistent service toggles, not
momentary status lamps. Turning a checkbox ON must start the service now and
write `*_enabled=1` so boot-time `plumos-network-services start-enabled` starts
it on the next boot. Turning it OFF must stop the service now and write
`*_enabled=0` so the next boot leaves it disabled. The frontend should display
the saved `enabled=` value from `plumos-network-services status`, while the
status text must still report the real runtime state using exact PID-file and
`/proc/<pid>/comm` or `/proc/<pid>/cmdline` checks.

The app-layer controller may start or adopt the OpenSSH daemon supplied by the
system rootfs, but the visible SSH control command is still:

```text
/mnt/plumos/bin/plumos-network-services start|stop|status ssh
```

SSH login environments must prefer plumOS command tools:

```text
PATH=/mnt/plumos/bin:/mnt/plumos/gnu/bin:...
```

SFTP may provide an app-layer `sftp-server` payload, but it depends on the same
SSH service state. FTP, SSH, Samba, and ADB stop/restart logic should use PID
files plus `/proc/<pid>/cmdline` or `/proc/<pid>/comm` checks before
terminating processes.

The `network-services` artifact must be independently deployable for its stated
service set. In particular, it must include the BusyBox binary and `tcpsvd` /
`ftpd` wrappers required by FTP rather than assuming a separate userland copy
already exists on the FAT32 partition. Rebuilding or copying network services
must not leave an enabled FTP checkbox with a `not_installed` runtime.

An associated USB Wi-Fi link without an IPv4 address is not a connected runtime
state. `plumos-network-control --wifi on` should renew DHCP in that state and
rerun idempotent startup for enabled network services after IPv4 becomes
available. Samba may persist as enabled while no IPv4 exists, but its runtime
state should report `waiting_network` and start after address acquisition.

The system-rootfs OpenSSH configuration must route the SFTP subsystem through
`/mnt/plumos/ssh/libexec/sftp-server`. This lets the SFTP checkbox enable or
disable the app-layer server path without stopping the shared SSH listener.
SSH process adoption and status checks must recognize an actual `[listener]`
process, not an authenticated child or a stale PID file.

USB cable diagnostics are a separate path from Wi-Fi/SSH. With the current
StockOS-derived kernel, USB Ethernet and USB ACM serial are not available, so
the supported file-transfer cable path is USB Disk Mode plus a command mailbox
in the dedicated `PLUMUSB` transfer image. The mailbox may execute an
explicitly armed `commands/run.sh` after the PC ejects the drive and the V90S
remounts the image, then write command output back under `results/`. This does
not make `/mnt/plumos` itself a shared live USB disk.

The supported interactive USB command path is standard ADB over the kernel's
FunctionFS/configfs gadget support. The app layer should ship the `adbd`
userspace daemon and expose it through:

```text
/mnt/plumos/bin/plumos-network-services start|stop|status adb
/mnt/plumos/bin/plumos-adbd start|stop|status
```

ADB is a development-access service and should default to OFF unless a
development profile explicitly enables it. The initial V90S daemon is no-auth
because the StockOS-derived userspace has no Android framework key-management
stack; the frontend and docs must describe it as a trusted-host-only local USB
debugging path.

Host-side V90S development should use `scripts/v90s-adb.sh`. The helper must
select one current ADB installation instead of allowing older Android SDK and
package-manager copies to start competing servers. On macOS, it may restart
only the host ADB server when IOKit still enumerates `plumOS V90S ADB` but the
ADB transport list is empty. This is host transport recovery, not a device-side
fallback and must not restart the V90S, its frontend, or unrelated services.
The validated macOS host version is ADB 36.0.2; ADB 35.0.2 failed to rediscover
the still-enumerated gadget after a USB read error.

Device-side ADB status must distinguish an active configured transport from an
enabled gadget waiting for a USB host. `udc_state=configured` or `suspended`
maps to `running`; a bound gadget with another UDC state maps to `waiting_usb`.
The persistent FE checkbox continues to represent `adb_enabled`, independently
of this live status.

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
complete
```

`COMPAT_VENDOR` must be `v90s-stockos-r1` until the vendor runtime is
intentionally revised.

`complete` is true only when the supported app-layer inputs are all present and
`missing_optional` is empty. Release packaging must reject partial app-layer
outputs even when those outputs are useful for an incremental development
deployment.

User content directories in the V90S FAT32 app layer should follow the
StockOS/Batocera lowercase convention for content roots:

```text
/mnt/plumos/roms/
/mnt/plumos/bios/
```

The frontend library scanner must treat `/mnt/plumos/roms` as the single ROM
root. System-specific folder compatibility belongs in
`config/frontend/systems.json` through `directory_aliases`; for example NES can
recognize both the Miyoo-style `FC` directory and the EmulationStation-style
`nes` directory under the same lowercase root:

```text
/mnt/plumos/roms/FC/
/mnt/plumos/roms/nes/
```

Do not revive a top-level `/mnt/plumos/Roms` fallback for V90S release behavior.
If a migration helper is needed later, make it explicit and one-shot rather than
adding another permanent scan root.

Scraped or user-supplied frontend artwork should follow the existing
plumOS A30/MMF convention so artwork can be shared across devices:

```text
/mnt/plumos/Images/<system>/<rom-relative-stem>.png
/mnt/plumos/Images/nes/Super Mario Bros..png
```

The thumbnail scraper should write to this `Images/<system>` tree by default,
and the frontend scanner should resolve thumbnails through each system's
`artwork.lookup` entries in `config/frontend/systems.json`.

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
StockOS-compatible `BATOCERA` ext4 partition and formats p7 `PLUMOS` as 4GB
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
audio_device = "plumos_output"
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

### Audio Output Policy

Normal plumOS applications must open the logical ALSA PCM `plumos_output`, not
bind directly to a numbered hardware card.

- With only the V90S `audiocodec` present, `plumos_output` routes
  `0.5 * left + 0.5 * right` to both hardware channels of `hw:<card>,0`. The
  built-in speaker therefore receives all stereo content as mono without
  clipping the sum.
- When a USB playback card is present, `plumos_output` selects it and preserves
  two-channel stereo.
- `plumos-audio-output prepare` owns runtime detection and atomically writes
  `/run/plumos/audio/asound.conf` and `/run/plumos/audio/output.status`.
- `plumos_output` is backed by the plumOS-owned ALSA ioplug
  `libasound_module_pcm_plumos_hotplug.so`. The plugin runs inside the
  application process, monitors playback-card availability without a daemon,
  and migrates an already-open stream between the built-in codec and a USB DAC.
- RetroArch, PicoArch, standalone emulators, and plumOS Music Player must run
  the helper before opening audio and must export the generated file through
  `ALSA_CONFIG_PATH` and the plugin directory through `ALSA_PLUGIN_DIR`.
- RetroArch alone enables the bounded nonblocking producer policy needed for
  fast-forward. PicoArch, standalone emulators, and Music Player use blocking
  physical writes so ordinary playback cannot discard samples.
- Failure to detect or configure a valid output is fatal to that application
  launch. The normal path must not silently fall back to `hw:0,0`.
- Direct `hw:0,0` playback remains available only in explicit audio diagnostics.
- USB DAC insertion and removal during gameplay must not require restarting the
  emulator. Physical USB disconnect errors are recorded by the vendor kernel;
  the normal application route follows the resulting ALSA card state.

This route does not require PulseAudio or PipeWire. The StockOS-era
`auto_mono_output` script is retained as design evidence, but its PulseAudio
daemon and sink-monitoring model is not part of the plumOS runtime. A
PulseAudio migration prototype reduced even Game Boy content to about 36 FPS
on the physical V90S and is explicitly rejected as the normal route.

### PicoArch Timing Policy

PicoArch must keep emulation and audio on the core's native clock. The fixed
V90S LCD refresh must not be used as the audio clock.

- `PLUMOS_PICOARCH_AUDIO_TARGET_FPS=0` is the normal setting. It preserves the
  core sample rate and normal pitch.
- A fixed `58.955` audio target remains a diagnostic option only. It removes
  underfeed when video and audio share the LCD clock, but lowers pitch and is
  not an acceptable default.
- V90S framebuffer conversion and presentation run on a dedicated thread. The
  emulation thread queues the newest RGB565 frame without waiting for LCD
  VBlank, matching the proven RetroArch `video_threaded=true` ownership split.
- The LCD is approximately 58.955 Hz while NTSC NES content is approximately
  60.10 FPS. Small cadence differences shared with RetroArch are a hardware
  display boundary, not a reason to slow the core or alter audio pitch.
- Cores that register the libretro asynchronous-audio callback continue to use
  PicoArch's dedicated callback thread and must stop it before core unload.

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

Python virtual environments on FAT32 must be created without symbolic links.
In particular, CPython's optional `lib64 -> lib` alias must be omitted while
the environment's interpreter files are copied. Normal Python app modules must
remain outside the squashfs so a user can replace `requirements.txt` and
recreate the environment without rewriting the SD image.

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
emulators, PortMaster, and frontend should build into reusable outputs, then be
collected into the FAT32 app layer rather than being baked into the release
squashfs.

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

Use p7 `rootfs_data` / `PLUMOS` as a 1024MB FAT32 partition in the
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

### 2026-07-13: 4GB FAT32 p7 Full Core Deployment

Decision:

Supersede the 1GB development default with a 4096MB FAT32 p7 `PLUMOS`
partition. Keep p1 through p6 unchanged.

Rationale:

The regenerated complete app layer with the MMF-matched 117-core set occupies
about 900MB
before user ROM artwork, saves, logs, and later standalone payload growth. A
4GB partition keeps routine update and validation work away from the capacity
limit while remaining quick to assemble and write compared with a full-card
image.

Validation:

The live 128GB V90S SD card was expanded and reformatted in place. The kernel
reported a 4GB p7, `/mnt/plumos` mounted read-write, and all app-layer files
passed `checksums.sha256` after deployment.

### 2026-07-11: V90S SD1 ROM and BIOS Roots

Decision:

Use lowercase StockOS/Batocera-style content roots inside the V90S FAT32
app-layer partition:

```text
/mnt/plumos/roms/
/mnt/plumos/bios/
```

For SD1-only operation, these are the authoritative locations for user ROMs and
BIOS files. The frontend library scanner starts at `/mnt/plumos/roms`; system
folder compatibility is expressed below that root through
`config/frontend/systems.json` `directory_aliases`.

Examples:

```text
/mnt/plumos/roms/FC/   # Miyoo-style Famicom/NES folder
/mnt/plumos/roms/nes/  # EmulationStation-style NES folder
```

Rationale:

V90S is StockOS/Batocera-derived at the boot/runtime boundary, so the user
content root names should not carry the older MMF top-level `Roms/` and
`BIOS/` convention. Keeping only one ROM root avoids duplicate scans and makes
Windows/macOS copy-over updates easier to reason about.

Constraints:

Do not add a permanent top-level `/mnt/plumos/Roms` scan fallback for V90S. If
an existing test card needs migration, handle it as an explicit one-time file
move or copy. Future system additions should reuse the MMF directory alias
model, but only enable launch profiles that are actually supported on V90S.

### 2026-07-11: V90S SD2 Content Layer

Decision:

Support SD2 as an optional external content layer for ROM and BIOS data only.
SD1 remains the authoritative plumOS app/update/data layer mounted at:

```text
/mnt/plumos
```

When an SD2 content card is present, mount the SD2 filesystem at an internal
runtime mount point such as:

```text
/run/plumos/sd2
```

Then bind-mount its content directories onto the existing plumOS content roots:

```text
/run/plumos/sd2/roms -> /mnt/plumos/roms
/run/plumos/sd2/bios -> /mnt/plumos/bios
```

The frontend, library scanner, RetroArch launchers, BIOS lookup, network
services, and user-facing paths should continue to use `/mnt/plumos` as the
single visible root. Do not add a second scanner root for SD2.

Rationale:

V90S has two SD slots, but the app layer and update model should remain simple.
Keeping SD1 as the OS/app layer and mapping only SD2 `roms` and `bios` into the
existing paths allows SD1-only and SD1+SD2 operation to share the same FE and
launcher contracts.

Initial implementation rules:

- Detect SD2 as a non-SD1 `mmcblk` device, normally `/dev/mmcblk1p1`.
- Prefer FAT32/vfat and exFAT for user-managed SD2 media; ext4 may be accepted
  for development cards.
- For FAT32/vfat, run a bounded `fsck.fat -a` or `dosfsck -a` before mounting
  when available. Keep the timeout short enough that a damaged SD2 cannot block
  FE startup forever.
- Accept `roms`/`ROMS`/`Roms` and `bios`/`BIOS`/`Bios` at the SD2 root, but
  expose them through lowercase `/mnt/plumos/roms` and `/mnt/plumos/bios`.
- If SD2 is absent, invalid, or missing either directory, leave SD1 content
  roots in place and continue booting.
- Do not require hot-unplug support for the first release. Treat SD2 as
  insertion-at-boot media unless a later frontend flow explicitly unmounts it.

Operational behavior:

The app layer should provide a small helper:

```text
/mnt/plumos/bin/plumos-sd2-content-mount start|status|stop|restart
```

The normal frontend launch path should call `start` before opening the FE, so
rebooting with SD2 inserted automatically exposes SD2 ROMs and BIOS files. The
`status` and `stop` commands are for troubleshooting and safe manual unmounts.

### 2026-07-14: CPU and GPU Performance Policy

Decision:

Use dynamic CPU governors rather than user-selectable fixed frequencies. The
frontend exposes these V90S-supported choices:

```text
Interactive   recommended default for games
Performance   explicit maximum-performance option
Ondemand      general-purpose compatibility option
Schedutil     scheduler-driven option
Conservative  slower-ramping power-conscious option
```

Every system profile defaults to `interactive`. The frontend itself returns to
`ondemand` while browsing menus. Before applying a selected game governor, the
launcher restores `scaling_min_freq` and `scaling_max_freq` to the hardware
`cpuinfo_min_freq` and `cpuinfo_max_freq` range. This prevents an old fixed-MHz
override from surviving a governor change.

All four Cortex-A53 CPUs, CPU0 through CPU3, must remain online while the
frontend is idle and while RetroArch, PicoArch, Pyxel, standalone emulators,
and scraper jobs run. V90S has no supported per-system or per-ROM CPU-count
setting. Frontend configuration and launch plans must not accept or persist a
CPU core count, and plumOS launchers must never write `0` to
`/sys/devices/system/cpu/cpu*/online`. Each application launcher should
defensively bring CPU1 through CPU3 online before applying its selected
governor so an old runtime state cannot reduce the available CPUs.

Do not expose `userspace`, fixed MHz, or OC frequency presets. Do not expose
`powersave` as a normal FE choice because on this target it behaves as an
effective minimum-frequency selection rather than a responsive game policy.
`Performance` remains available for demanding emulators and diagnostics.

The StockOS-derived PowerVR GE8300 runtime does not expose a standard devfreq
governor under `/sys/class/devfreq`. Its vendor `sunxi_gpu` debug state reports
DVFS disabled and an active clock around 700 MHz, while runtime PM can still
suspend the GPU when idle. Therefore plumOS must not present a GPU governor
setting. Add one only if a stable vendor-supported runtime interface is found
and validated on the V90S.

### 2026-07-15: Release SquashFS Ownership Boundary

Decision:

The official `system-rootfs` target builds the `release-system` profile by
default and writes:

```text
output/system-rootfs/v90s/plumos-v90s-system-rootfs.squashfs
```

This squashfs owns init, p7 mount-before-fsck, safe reboot/poweroff, PowerVR
and SDL2 PowerVR integration, minimal diagnostics, and the app-layer bootstrap.
It does not contain the frontend, RetroArch, libretro cores, PicoArch,
standalone emulators, or private ROMs. The older Step 1 and Step 2 profiles are
development diagnostics and require an explicit `--profile` argument.
The `release-system` profile refuses Wi-Fi credentials, SSH keys, and root
passwords even when those values are present in the build environment.

The rootfs bootstrap validates `/mnt/plumos/COMPAT_VENDOR`, release metadata,
and checksums for the critical frontend entry points before starting the FE.
Missing, damaged, or vendor-incompatible app layers stop with a visible error.
They must not silently start an application bundled in the squashfs.

Transient runtime ownership is standardized as:

```text
/run/plumos/frontend
/run/plumos/network-services
/run/plumos/network-control
/run/plumos/network-recovery
/run/plumos/ssh
/run/plumos/adb
/run/plumos/usb-disk
/run/plumos/retroarch
/run/plumos/picoarch
/run/plumos/standalone
/run/plumos/cache
/run/plumos/tmp
```

PID files, executable ownership records, locks, temporary command results,
in-progress scraper state, runtime volume state, and disposable emulator caches
belong under this tmpfs tree. Persistent settings, frontend library indexes,
favorites/recent history, emulator configuration, saves, states, screenshots,
downloaded artwork, and user-visible logs remain on the FAT32 app layer.

Rationale:

Moving immutable hardware glue and power/mount policy into squashfs prevents a
partially damaged FAT32 partition from changing the boot contract. Keeping
volatile high-churn files off p7 reduces needless FAT updates and eliminates
stale PID/lock state after a reset, while preserving the Windows/macOS copy-over
update model for user-facing applications and data.

### 2026-07-16: Pyxel Python and Virtual-Environment Boundary

Decision:

The system squashfs owns the Bookworm Python 3 interpreter and the standard
`venv` and `pip` tooling. Pyxel and project-specific Python modules are not
baked into the squashfs. They are installed into the p7 app/data layer:

```text
project requirements: /mnt/plumos/roms/pyxel/requirements.txt
default requirements: /mnt/plumos/share/pyxel/requirements.txt
venv:                /mnt/plumos/venvs/pyxel
wheel cache:         /mnt/plumos/cache/pip
temporary:           /mnt/plumos/cache/pip-tmp
```

The project requirements file takes precedence when present. If it is absent,
the installer uses the plumOS-owned default requirements so Pyxel setup remains
available when SD2 is mounted over `/mnt/plumos/roms` or a new SD2 does not yet
contain a requirements file. An explicit `PLUMOS_PYXEL_REQUIREMENTS` override
takes precedence over both paths.

`Apps -> Pyxel Setup` is the user-facing installer. It must return a bounded
failure when Python, `requirements.txt`, networking, or a compatible wheel is
unavailable, and it must display the captured result in the frontend. The
normal policy accepts binary wheels only so an SD-card install cannot
unexpectedly begin a native compiler/Rust toolchain build. A failed update
restores the previous working virtual environment.

The V90S launch profile is `pyxel:v90s` and executes through
`/mnt/plumos/bin/plumos-pyxel-v90s-launch`. MMF and A30 launcher names remain
device-specific compatibility profiles and must not be used as the V90S
default.

Rationale:

Keeping Python itself read-only makes the interpreter and standard library
stable across resets. Keeping pip-installed modules on p7 preserves the normal
Windows/macOS copy-over workflow and allows a project's `requirements.txt` to
change independently of the OS image. The packaged default prevents the
optional SD2 content partition from becoming a prerequisite for the base Pyxel
runtime. The FAT-safe venv creator skips only
CPython's optional `lib64` symlink and otherwise uses the standard copied-file
venv layout.

### 2026-07-16: PortMaster Ownership and Update Boundary

Decision:

PortMaster is an optional FAT32 app-layer component. Keep its official payload,
V90S integration, and writable state as three separate layers:

```text
official payload: /mnt/plumos/apps/portmaster/upstream/PortMaster
V90S adapter:     /mnt/plumos/apps/portmaster/adapter
writable state:   /mnt/plumos/state/portmaster
installed ports:  /mnt/plumos/roms/ports
runtime files:    /run/plumos/portmaster
logs:             /mnt/plumos/Logs/apps
```

The reproducible build target pins an official stable `PortMaster.zip` by both
the upstream MD5 and a plumOS-recorded SHA-256. It packages the upstream license
files without patching them in place. Hardware identification, PowerVR SDL2,
ALSA routing, V90S controls, FAT32 SONAME aliases, and process ownership remain
in the external plumOS adapter so an upstream update cannot replace them.

Online updates must use `/mnt/plumos/bin/plumos-portmaster-update`. The V90S
adapter disables only the official GUI's in-place payload self-update call;
catalog metadata, thumbnails, runtimes, and port downloads remain enabled and
persist below `/mnt/plumos/state/portmaster/config`. The broad upstream
`--no-check` option must not be used because it also disables those catalog
updates. The plumOS updater:

1. reads the selected official stable/beta/alpha release metadata
2. downloads into a sibling staging directory on p7
3. verifies the official MD5, records SHA-256, rejects unsafe archive paths and
   symlinks, and checks the required PortMaster files and version
4. refuses to switch while the GUI is running
5. renames the current payload to `upstream.previous` and atomically renames the
   validated stage to `upstream`

Pre-switch failure leaves the current payload untouched. A switch failure is
reported explicitly and leaves the previous payload named
`upstream.previous`; plumOS must not silently launch that copy as a fallback.
Normal Windows/macOS copy-over releases may also replace the official payload,
but must preserve adapter and state paths.

PortMaster GUI and installed-port launchers must use PID files plus validated
process identity. Port games run in an owned session/process group. Legacy port
requests to broadly stop GPTokeYB or restart `oga_events` are intercepted and
limited to the owned GPTokeYB PID; they must never stop SSH, ADB, the frontend,
or unrelated emulators. FE-launched apps borrow the FE display lifecycle,
whereas direct SSH/ADB launches stop and restore exactly one frontend process.
Both launch paths must bind the same persistent `config`, `libs`, and `themes`
directories and export the same HarbourMaster tools, ports, and scripts paths.
An installed port must not see a second empty PortMaster state tree.

The StockOS kernel SquashFS implementation does not support the zlib-compressed
runtimes currently distributed by PortMaster. The V90S adapter therefore uses
a packaged AArch64 `unsquashfs` and extracts PortMaster runtime images into
`/mnt/plumos/state/portmaster/runtime-cache`. Cache directories include the
source SHA-256, so an upstream runtime replacement creates a new cache instead
of reusing stale files. The extracted directory is bind-mounted only for the
owned port session and must be unmounted after its process group exits. This
userspace extraction mode is the normal V90S contract; do not attempt a kernel
mount first or silently select another runtime.

Port-local libraries absent from the base userspace belong to the external
adapter. In particular, LÖVE-based ports use the adapter-owned AArch64 OpenAL
Soft build configured for ALSA, while the normal plumOS audio router remains
the only PCM route.

The boot-persistent hardware-key service provides a one-second `Select+Start`
emergency exit for PortMaster ports by calling the same ownership-validated
stop helper. It must not signal a process name, PID outside the recorded
session, SSH, ADB, the frontend, or another emulator.

Initial capability metadata is deliberately conservative: AArch64, 640x480,
4:3, 1GB RAM, and no analog sticks. Do not advertise ARMHF, desktop OpenGL,
Weston/GL4ES, Box64, Mono, Java, or other runtime classes until each class has a
packaged V90S runtime and real-device video, audio, input, exit, save, and FE
restoration evidence. A working GUI or successful download alone is not a port
compatibility result.
