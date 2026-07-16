# V90S PortMaster Integration

Date: 2026-07-16

## Result

The official PortMaster stable GUI and one lightweight Ready-to-Run port now
run through the plumOS V90S app-layer contract. The GUI rendered at 640x480,
loaded the PowerVR SDL stack, opened `adc_gamepad`, fetched current catalog
metadata, stopped through its owned PID, removed its bind mounts, and restored
exactly one frontend process.

Apotris then rendered a real game screen through the FE `external:port` route,
used `plumos_output`, ran GPTokeYB under an owned PID, stopped through its owned
process group, and again restored exactly one FE process.

## Reproducible Package

Official release:

```text
channel: stable
version: 2026.06.23-0015
official MD5: 41d137e6bb123c755806939831bcce2f
plumOS SHA-256: 772f2d56fc1abfbf79a3404ca78f240776c81c5a5b92786a0a748ae554339b7b
```

Build commands:

```text
./scripts/docker-build.sh portmaster
./scripts/docker-build.sh frontend
./scripts/docker-build.sh app-layer --strict
```

The strict app-layer manifest reported `complete=true` and contained the
PortMaster upstream payload, adapter, launchers, updater, manifest, and hashes.

## Update Validation

The live V90S reached the official release endpoint and reported:

```text
installed=2026.06.23-0015
latest=2026.06.23-0015
channel=stable
update_available=no
official_md5=41d137e6bb123c755806939831bcce2f
```

A local synthetic newer release exercised the complete staged switch. The
updater verified its archive, installed `2099.01.01-0000` into `upstream`, and
kept the original test payload as `upstream.previous`. This test used temporary
paths only and did not modify the V90S installation. A future real upstream
release should be used to repeat the network switch itself.

The GUI runs with normal online checks enabled so source metadata, catalog
images, runtimes, and ports can update. The V90S bootstrap replaces only the
single upstream self-update call with a plumOS no-op. Therefore only the
plumOS-owned staged updater may replace the official payload; `--no-check` must
not be used because upstream also applies it to source metadata and images.

## GUI Runtime Evidence

Live device: ADB serial `plumos-v90s-a778c2b9`.

The official log recorded:

```text
PM: 2026.06.23-0015
SDL DLL: /run/plumos/portmaster/lib/libSDL2-2.0.so.0, 2.30.6
TTF DLL: /run/plumos/portmaster/lib/libSDL2_ttf-2.0.so.0, 2.20.1
IMG DLL: /run/plumos/portmaster/lib/libSDL2_image-2.0.so.0, 2.6.3
MIX DLL: /run/plumos/portmaster/lib/libSDL2_mixer-2.0.so.0, 2.6.2
Opened GameController 0: adc_gamepad
device: powkiddy-v90s
name: plumOS
resolution: 640x480
analogsticks: 0
cpu: a133plus
primary_arch: aarch64
glibc: 2.36
Display size: 640x480
```

Catalog refresh created persistent source, featured-port, port-info, porter,
runtime, and statistics JSON files under
`/mnt/plumos/state/portmaster/config`. The GUI state directories were bind
mounted only for the GUI lifetime and no PortMaster mounts remained after
stop. The upstream `pugwash.txt` path was file-bind-mounted to
`/mnt/plumos/Logs/apps/portmaster-upstream.log`, keeping runtime logs outside
the replaceable official payload.

While GUI PID `26997` was alive, an update attempt failed as intended:

```text
plumos-portmaster-update: PortMaster is running (pid=26997); close it before updating
```

The ignored local framebuffer capture is:

```text
output/validation/portmaster-v90s-integration/fb0-page0.png
SHA-256: 6a8d4852f82e84eae54858f2abd18220ab2ba505e27afc98c7b4427d59269fab
```

It shows the correctly framed official PortMaster disclaimer at 640x480.

The initial V90S launch incorrectly used `--no-check`. PortMaster interprets
that option broadly: both payload self-update and `images.zip` source refresh
were disabled, leaving `last_checked` null and catalog entries on the bundled
`no-image.jpg`. Adapter version 2 removes that argument and suppresses only the
payload self-update call. Source images remain in the persistent bind-mounted
`config/images_*` directories.

The repaired live launch downloaded the official PortMaster and Multiverse
source metadata plus image archives. Both source files received a non-null
`last_checked` value, and the persistent cache contained 1,386 PNG/JPEG files
using 100.1 MiB. A second launch reached the main menu in about two seconds,
performed no image download, and retained the same image count. The official
payload stayed at `2026.06.23-0015`, and no `upstream.previous` directory was
created, proving that the catalog refresh did not invoke payload replacement.

The ignored post-relaunch framebuffer capture is:

```text
output/validation/portmaster-v90s-thumbnails/catalog-thumbnail.png
SHA-256: 435d25003260a2c07242708abcfcdf7787d29d9627a7a74b60efb4f5172d9743
```

It shows the `-SPROUT-` catalog entry using its downloaded screenshot rather
than the bundled no-image placeholder.

## Ready-to-Run Port Evidence

The FE launch plan for `PORTS/Apotris.sh` resolved to:

```text
launch_profile: external:port
command: /mnt/plumos/bin/plumos-portmaster-port-launch /mnt/plumos/roms/PORTS/Apotris.sh
can_execute: yes
```

Live ownership while the game rendered:

```text
session leader: bash /mnt/plumos/roms/PORTS/Apotris.sh
game: ./Apotris.aarch64
input helper: PortMaster/gptokeyb Apotris.aarch64
audio: mode=internal_mono pcm=plumos_output physical_pcm=hw:0,0
```

The ignored game framebuffer capture is:

```text
output/validation/portmaster-v90s-integration/apotris-page0.png
SHA-256: b55a80b1ce9a75a8b4f88fb45fc6d070d21280151898496937b5e08e109e0b68
```

After `plumos-portmaster-port-stop`, the game, wrapper, and GPTokeYB processes
were absent, all ownership files were removed, and one frontend remained:

```text
plumos-frontend-stop: pid=26554 cmd=/mnt/plumos/bin/plumos-controller-ui-fbdev --renderer fbdev
```

The same stop contract is exposed as a one-second `Select+Start` emergency
hold by the boot-persistent hardware-key daemon. A live hung
`8-BIT BUCCANEER` session at PID/PGID `31349` was terminated through that
hotkey path. Its entire owned group and state files disappeared, one FE resumed,
and ADB, SSH, and the key daemon remained alive.

## Balatro And Donut Dodo Compatibility

Balatro initially stopped before startup because its bundled LÖVE 11.5 runtime
requires `libopenal.so.1`. Adapter version 4 builds OpenAL Soft 1.23.1 as an
AArch64 ALSA-only library and exposes it from the volatile PortMaster library
directory. On hardware, `love.aarch64 Balatro` remained running, owned the
active ALSA PCM, and continuously changed both framebuffer pages. The captured
title screen is:

```text
output/validation/portmaster-v90s-integration/balatro-page0.png
SHA-256: 2c76141c78790c85f9e5ee4eff38ee78c0881f418ceda9c2a9d3beaf15fe8ad3
```

Donut Dodo exposed two separate integration defects. Installed-port launchers
did not export the same `HM_TOOLS_DIR`, `HM_PORTS_DIR`, and `HM_SCRIPTS_DIR`
contract as the GUI, so HarbourMaster could not find the persistent runtime
metadata. After aligning that environment, it downloaded
`frt_3.5.2.squashfs` and verified the expected MD5
`d98d82d86ae7630b8ef62da9705cbda8`.

The StockOS kernel then rejected that image because its SquashFS driver lacks
zlib decompression. The V90S adapter therefore treats PortMaster SquashFS
runtimes as userspace archives: the pinned AArch64 `unsquashfs` extracts each
archive into a SHA-256-keyed p7 cache, and the adapter bind-mounts that cache at
the port's requested runtime directory. This is the selected V90S runtime mode,
not a retry after a failed kernel mount. The first extraction produced:

```text
/mnt/plumos/state/portmaster/runtime-cache/
  frt_3.5.2.squashfs.b7599230407793a5befcad6f544694f298bca61ed9c7a4f686af1ed5c430f45e/
```

`frt_3.5.2 --resolution 640x480 -f` then remained running, owned the active
ALSA PCM, and updated the framebuffer. The captured title screen is:

```text
output/validation/portmaster-v90s-integration/donutdodo-page0.png
SHA-256: 46c6ae1134e9bf42a460a4d4499c1e84c3c4dfeb8afdd285bab3cea1e09be8
```

Godot 3.5 rejects the newer SDL mapping `crc` field, so the generated V90S
mapping omits that optional field. GPTokeYB loaded `donutdodo.gptk`, opened
`adc_gamepad`, and entered fake-keyboard mode without the mapping parse error.
Physical gameplay control still requires the user's button test.

Stopping either title removed the owned game and GPTokeYB processes. The port
launcher now waits for its process group before reversing runtime, theme,
library, and configuration mounts. The final Donut Dodo stop left no FRT or
PortMaster mount and restored exactly one frontend process. `status` is also a
non-destructive action now; it no longer aliases the stop operation.

## Compatibility Boundary

The pre-existing A7Xpg Ready-to-Run installation did not start because its
port-local runtime lacks `libFLAC.so.8`. Its launcher and process cleanup still
completed safely. This is recorded as a port payload/runtime compatibility
failure, not a PortMaster GUI or V90S platform-adapter failure.

Physical GUI navigation and game-control confirmation remain for the user. SDL
opened the real `adc_gamepad` with the V90S mapping in both paths, but process
and framebuffer evidence do not replace a physical button test. ARMHF and
heavier runtime classes remain unadvertised pending separate validation.
