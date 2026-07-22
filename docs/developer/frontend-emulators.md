# Frontend and Emulator Integration

## Frontend Data Model

The canonical system catalog is
`package/frontend-v90s/plumos/config/frontend/systems.json`. Each system defines
ROM roots and aliases, extensions, thumbnail paths, launch profiles, and a
default profile. The frontend scans active `/mnt/plumos/roms`, persists settings
below `/mnt/plumos/config/frontend`, and resolves artwork below
`/mnt/plumos/Images/<system>`.

TOP, ROM list, Gallery, START, SELECT, Apps, settings, progress, and power views
share the MMF-derived data and theme model. The V90S renderer writes directly to
the vendor framebuffer, uses stable page dimensions, preserves CJK fallback
fonts, and animates graphical TOP transitions at the display frame cadence.
Refresh TOP must display its progress view and atomically replace the scan model.

## Launch Profile Contract

Profile strings are namespaced:

```text
retroarch:<core-id>
picoarch:<core-id>
standalone:<emulator-id>
```

FE passes the system ID, selected profile, absolute content path, active ROM
root, BIOS root, save/state directories, and ownership token to the controlled
launcher. A profile is exposed only when its binary/core and launcher mapping
exist; artificial runtime core allowlists are forbidden.

## RetroArch

The owned binary is `/mnt/plumos/bin/retroarch`. The launcher creates a private
runtime library tree under `/run/plumos/retroarch/lib`, including SONAME aliases
from `config/standalone/soname-links.tsv`. It rewrites only legacy directory
values, preserving user changes elsewhere.

V90S defaults include:

```text
video_driver = sdl2
video_context_driver = mali_fbdev
audio_driver = alsa
audio_device = plumos_output
input_driver = sdl2
input_joypad_driver = sdl2
```

The known-good factory configuration is a versioned build input and is staged
under `factory-defaults/ra/`. Factory reset copies it to the writable config;
normal builds and live deploys do not overwrite an active user config.

The factory configuration enables `savefiles_in_content_dir` and
`savestates_in_content_dir`, placing saves and states on the active ROM
filesystem. It also enables `sort_savefiles_enable`,
`sort_savefiles_by_content_enable`, `sort_savestates_enable`, and
`sort_savestates_by_content_enable`. For example, GB/Gambatte produces
`roms/GB/GB/Gambatte/<ROM name>.srm` and `<ROM name>.state*`. The launcher still
passes `/mnt/plumos/Saves/<system>` and `States/<system>` in its append config;
these become fallback destinations when the user disables content-directory
storage. When SD2 is the active ROM root, it also owns the default RA saves and
states.

```text
autosave_interval = 10
savefiles_in_content_dir = true
savestates_in_content_dir = true
savestate_auto_index = true
savestate_auto_load = false
savestate_auto_save = true
savestate_max_keep = 20
savestate_thumbnail_enable = true
```

## PicoArch

PicoArch is AArch64 and reuses `/mnt/plumos/cores`; it does not maintain a
second core set. V90S patches own direct framebuffer presentation, pixel format,
aspect fit, controller initialization, content directory, frame pacing, and
asynchronous audio callback behavior. Normal audio keeps the core's native
clock with `PLUMOS_PICOARCH_AUDIO_TARGET_FPS=0`; fixed refresh-derived audio
targets are diagnostic only.

## Standalone Emulators

The build target supports `ppsspp`, `scummvm`, `easyrpg`, `openbor`,
`pcsx_rearmed`, `flycast`, `mupen64plus`, `nxengine-evo`, and `yabasanshiro`.
The system catalog determines which are user-selectable; building a binary does
not automatically make it the default route.

`plumos-standalone-launch` owns per-emulator working directories, XDG state,
BIOS links, input helper lifetime, PowerVR/SDL libraries, audio environment,
factory PPSSPP settings, and cleanup. The adopted Saturn route uses pinned
YabaSanshiro 2.10.4 patches for AArch64, V90S input, VDP1 readback, and direct
framebuffer behavior.

## Apps, Pyxel, and PortMaster

Apps are foreground children under the same display/input/power lifecycle.
NextCommander and Music Player are V90S-built native applications. Pyxel keeps
the base Python runtime in System SquashFS and the user-updatable virtual
environment on p3; `roms/pyxel/requirements.txt` is installed by the dedicated
setup app. Display aspect fitting and ALSA/pygame routing are wrapper policy,
not modifications to the user-controlled Pyxel package.

PortMaster uses the pinned official GUI plus the V90S adapter and common AArch64
ABI bundle. Installed ports and mutable PortMaster state are device-owned.
ARMHF ports are unsupported because no 32-bit PowerVR userspace driver exists.
Static audit results guide library packaging, but each runtime family still
needs physical lifecycle checks.

## Configuration Ownership

Settings saved by FE and emulators are authoritative device state. Build output
may update versioned factory defaults and idempotent migrations, never copy host
configs over active settings by default. RA, PicoArch, standalone, and PPSSPP
factory reset paths remain independent.
