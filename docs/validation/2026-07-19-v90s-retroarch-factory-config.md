# V90S RetroArch Factory Configuration

Date: 2026-07-19

## Source

The current physical-device configuration was captured from:

```text
/mnt/plumos/config/retroarch/retroarch-v90s.cfg
```

It is tracked as:

```text
package/frontend-v90s/plumos/factory-defaults/ra/config/retroarch/retroarch-v90s.cfg
```

The captured file contains 3,374 lines. Non-empty password, token, username,
Wi-Fi credential, host-address, and macOS host-path checks found no private
values. Its SHA-256 is:

```text
63d0f997a267e6428d6173ca94e0bff090996a1e6e2a67ffd662a79c57634604
```

Representative validated settings include:

```text
video_driver = "gl"
video_context_driver = "mali_fbdev"
video_refresh_rate = "58.917103"
video_threaded = "true"
vrr_runloop_enable = "true"
audio_driver = "alsa"
audio_device = "plumos_output"
input_driver = "sdl2"
input_joypad_driver = "sdl2"
libretro_directory = "/mnt/plumos/cores"
libretro_info_path = "/mnt/plumos/info"
system_directory = "/mnt/plumos/bios"
video_shader_dir = "/mnt/plumos/config/shaders"
config_save_on_exit = "true"
```

## Build Contract

`scripts/docker-build.sh retroarch` now validates the tracked cfg, places an
identical copy under the RetroArch output's `plumos/factory-defaults/ra` tree,
writes `retroarch-v90s-factory.cfg.sha256`, and records the source, relative
output path, and hash in `manifest.txt`.

The Docker build completed successfully. The tracked source and generated
factory artifact both produced SHA-256
`63d0f997a267e6428d6173ca94e0bff090996a1e6e2a67ffd662a79c57634604`.

App-layer assembly compares the factory copy supplied by the RetroArch artifact
with the frontend factory tree and fails on a mismatch. The runtime launcher
installs that factory cfg only when the writable user cfg is absent. It no longer
generates a separate minimal cfg. Existing user settings remain untouched by
normal starts and application-layer updates.

## Verification

Completed checks:

```text
sh syntax: pass
RetroArch Docker build: pass
frontend build: pass
strict app-layer build: pass
intentional factory mismatch rejection: pass
artifact checksum verification: pass
live factory deploy/hash: pass
live user cfg preserved: pass
```

Generated artifact hashes:

```text
49dac4029423ffbbaa17b75d00008b0345e90e1592e6e9dda1b000bbb25301b0  output/app-layer/v90s/checksums.sha256
58dced79ed505956816704223ee779d797515b359bc7c25ff5de4ac05d5c9874  output/app-layer/v90s/manifest.json
```

The hardened ADB deploy transferred five changed payload files and verified the
new RetroArch binary, launcher, factory cfg, frontend manifest, and RetroArch
manifest before committing app-layer metadata. Before and after deployment,
the writable user cfg hash remained
`63d0f997a267e6428d6173ca94e0bff090996a1e6e2a67ffd662a79c57634604`.
The deployed factory cfg now has the same hash.

`plumos-factory-reset retroarch --dry-run` lists
`config/retroarch/retroarch-v90s.cfg` without changing it. The frontend is
running as one owned `plumos-controller-ui-fbdev` process, no RetroArch process
is active, and `/mnt/plumos` is mounted read-write from `/dev/mmcblk0p3` as
ext4.

macOS attached a provenance extended attribute to the captured cfg. BSD tar can
encode such metadata as an untracked AppleDouble `._retroarch-v90s.cfg` on a
Linux target. The source attribute and deployed sidecar were removed, and the
ADB app-layer deploy now runs tar with `COPYFILE_DISABLE=1`. A test archive
contains only the requested cfg path, so future config deploys cannot add the
sidecar to the factory-reset file set.
