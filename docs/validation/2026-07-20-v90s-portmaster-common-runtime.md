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

## Upstream Compatibility Path Follow-up

The first GUI retest still displayed the old loader error. A framebuffer
capture proved that this was not merely stale text. `gui/main.lua` launches
Pair and Reload Apps with an explicit environment:

```text
LD_LIBRARY_PATH=<port>/moonlight/libs:/usr/lib/compat
```

That assignment discards the inherited plumOS runtime path. The normal shell
launch and `ldd` test therefore succeeded while the Lua GUI child failed.

The adapter bind-mounts `/run/plumos/portmaster/lib` at the upstream convention
`/usr/lib/compat` for the lifetime of an owned port session when the rootfs
contains that empty mountpoint. Future rootfs images provide it.

The current read-only SquashFS image predates that mountpoint. A temporary
overlay on global `/usr/lib` was tested and rejected: cleanup could leave the
overlay busy and change the library view for unrelated processes. The adapter
instead recognizes only `Moonlight New.sh`, verifies the exact known Lua source
string, and changes the assignment to prepend the port libraries while retaining
`${LD_LIBRARY_PATH}` inherited from the owned plumOS launcher. This preserves
the common FFmpeg runtime as well as Avahi, Pulse compatibility, PowerVR, and
normal system paths. Already-patched content is accepted idempotently; unknown
content is not modified.

The corrected launcher and complete app-layer were deployed again with the
metadata files committed last. Device-side SHA-256 verification passed for the
launcher, PortMaster component checksum set, and merged app-layer manifest.
The exact shell assignment emitted by the Lua GUI then produced:

```text
exact_rc=0
Moonlight Embedded 2.7.0-master-274d3db
unresolved ELF dependencies: none
```

The old `pair.txt` loader error was replaced by Moonlight's expected connection
result for the placeholder host. After the owned stop helper ran, exactly one
frontend process remained and `/proc/self/mountinfo` contained no `/usr/lib`
or `/usr/lib/compat` mount. This proves both the GUI child path and cleanup
boundary on the current hardware image.
