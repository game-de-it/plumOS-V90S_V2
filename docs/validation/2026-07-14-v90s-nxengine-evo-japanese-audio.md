# V90S NXEngine-evo Japanese and audio validation

Date: 2026-07-14

## Problem

The FE originally launched Cave Story with `nxengine_libretro.so`. That core
expects Cave Story 1.0.0.6 with the Aeon Genesis translation. The Japanese
`Doukutsu.exe` on the V90S therefore did not match either of these core
contracts:

- the core has only a 256-character built-in bitmap font, so Japanese text was
  corrupted;
- Organya resources are extracted from fixed translated-executable offsets, so
  the Japanese executable did not provide working BGM.

The RetroArch ALSA backend was initialized normally. The failure was a content
and engine mismatch, not an ALSA mixer or system-font problem.

## plumOS implementation

NXEngine-evo is now the default Cave Story profile:

```text
default_launch_profile=standalone:nxengine-evo
launch_profiles=standalone:nxengine-evo,retroarch:nxengine
```

The old libretro profile remains a manual compatibility choice for translated
content. It is not an automatic fallback.

The standalone recipe pins:

```text
repo=https://github.com/nxengine/nxengine-evo.git
commit=21d8aaf477092b22eceb849c6430c9ce2194c4f7
data_url=https://github.com/PortsMaster/PortMaster-Releases/releases/download/2023-10-12_1508/Cave.Story-evo.zip
data_md5=ca5ff2645f99601d6a60fa8707826e28
```

The build uses `PORTABLE=ON` and installs the data at the path expected by that
build:

```text
/mnt/plumos/standalone/nxengine-evo/bin/nxengine-evo
/mnt/plumos/standalone/nxengine-evo/share/nxengine/data
```

SDL2_mixer and SDL2_image dependencies are packaged in the app layer, while the
V90S PowerVR SDL2 remains the active SDL implementation.

## V90S input defaults

The NXEngine-evo source build defines these SDL joystick mappings for
`adc_gamepad`:

| V90S control | NXEngine action |
| --- | --- |
| D-pad hat 0 | movement/menu navigation |
| A / B | jump/accept, fire/back |
| X / Y | inventory, strafe |
| L / R | previous/next weapon |
| Select | map |
| Start | enter |
| Function | pause/escape |

The user confirmed that the live V90S became controllable with this mapping.
The same mapping is compiled into the formal binary and no external
`gptokeyb` process is required.

## Real-device evidence

Formal runtime process:

```text
pid=27102
/mnt/plumos/standalone/nxengine-evo/bin/nxengine-evo
```

Audio ownership:

```text
state: RUNNING
owner_pid: 27102
Organya init done
Entering main loop...
```

Japanese and BGM assets were read from the formal app-layer path:

```text
380   share/nxengine/data/lang/japanese/Stage/Start.tsc
19626 share/nxengine/data/org/wanpaku.org
```

Deployed hashes:

```text
5d0560d9ae3d6f500966b4b2f1ab9d87307922432e36a7631463775240e6cda3  nxengine-evo
1ec3fd4ad9f354d57aae81e3f34d7e164ac887371a1e463d8083d1a1e5846d88  plumos-standalone-launch
e1f81a60fb8abf690165c9790c4a512d97b0a67968279a088bc98a51e784a0eb  systems.json
```

The framebuffer capture is stored at:

```text
output/validation/nxengine-evo-formal/fb0.png
```

It shows `洞窟物語`, the Japanese menu, and `NXEngine-evo 2.6.5` on the
physical V90S framebuffer. Missing high-numbered optional PXT warnings remain
in the upstream data package, but they do not prevent Organya BGM, menu sound,
or the main loop from running.
