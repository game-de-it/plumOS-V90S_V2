# V90S PortMaster Common Runtime Validation

Date: 2026-07-20

## Problem

The official `Moonlight New` PortMaster port reached its LÖVE launcher, but
Moonlight Embedded could not start because its AArch64 binary required library
ABIs absent from the current plumOS userspace.

The exact launch environment reported these unresolved dependencies:

```text
libavcodec.so.58 => not found
libavutil.so.56 => not found
libevdev.so.2 => not found
```

The PowerVR libraries were not missing when the real PortMaster launch path,
including `/usr/lib/powervr`, was used.

## Packaged Runtime

`scripts/docker-build.sh portmaster` now builds and packages:

- FFmpeg 4.4.6 from its SHA-256-pinned upstream source archive
- `libavcodec.so.58`
- `libavformat.so.58`
- `libavutil.so.56`
- `libswresample.so.3`
- `libswscale.so.5`
- libevdev 1.13.1 from its SHA-256-pinned upstream source archive
- `libevdev.so.2`

FFmpeg uses built-in decoders and demuxers, disables programs, network access,
encoders, muxers, filters, devices, hardware accelerators, and external codec
autodetection. Its ELF closure therefore remains within the packaged FFmpeg
libraries, `libm`, and glibc. The files are regular app-layer files; runtime
SONAME links are created below `/run/plumos/portmaster/lib` because the user
volume must not depend on persistent symlinks.

The common runtime deliberately excludes unrelated compatibility classes such
as old SDL 1.2 stacks, desktop OpenGL, Android/Bionic, and ARMHF.

## Build Evidence

The PortMaster component and complete app-layer were rebuilt successfully:

```text
./scripts/docker-build.sh portmaster
./scripts/docker-build.sh app-layer
```

`output/portmaster/v90s/checksums.sha256` and the complete app-layer checksum
set passed. ELF inspection confirmed the expected SONAMEs and showed that the
new `libavcodec.so.58` depends only on `libswresample.so.3`,
`libavutil.so.56`, `libm.so.6`, and `libc.so.6`.

## Hardware Evidence

The update was selectively deployed over ADB with these controls:

- the active PortMaster process group was stopped through its PID-owned helper
- only 12 managed payload and component-metadata files were replaced
- updated `manifest.json` and `checksums.sha256` were committed last
- all 12 payload hashes and the merged manifest hash passed on the V90S
- user-installed ports, settings, saves, and online-updated upstream payload
  files were preserved

After `plumos-portmaster-runtime prepare`, `ldd` on the installed Moonlight
Embedded binary reported no `not found` entries with the real launch search
path. Executing the binary reached its own help output and identified itself
as:

```text
Moonlight Embedded 2.7.0-master-274d3db
```

The normal `Moonlight New.sh` path then started its LÖVE GUI with one owned
`love` process. The user can now select a host and stream to validate the
network session, video decode, audio, controls, and exit behavior separately
from dynamic-loader availability.
