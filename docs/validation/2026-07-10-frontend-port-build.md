# V90S Frontend Port Build Validation

Date: 2026-07-10

## Scope

Port the plumOS-MMF frontend into the V90S distribution shape.

The V90S port keeps the MMF frontend source structure but builds the generic
fbdev controller UI for arm64. MMF-specific GFX and SDL1 renderer paths are not
used for V90S.

## Implemented Build Path

```text
scripts/docker-build.sh frontend
```

Output:

```text
output/frontend/v90s/
output/frontend/v90s/frontend.manifest
output/frontend/v90s/checksums.sha256
output/frontend/v90s/plumos/bin/plumos-frontend-launch
output/frontend/v90s/plumos/bin/plumos-controller-ui-fbdev
output/frontend/v90s/plumos/bin/plumos-retroarch-launch
```

The frontend payload is merged into the app layer by:

```text
scripts/docker-build.sh app-layer --strict
```

Output:

```text
output/app-layer/v90s/
output/app-layer/v90s/manifest.json
output/app-layer/v90s/checksums.sha256
```

## Runtime Contract

On device, the frontend root is:

```text
/mnt/plumos
```

The boot/frontend launcher is:

```text
/mnt/plumos/bin/plumos-frontend-launch
```

The frontend starts:

```text
/mnt/plumos/bin/plumos-controller-ui-v90s
```

The V90S wrapper runs the fbdev frontend binary:

```text
/mnt/plumos/bin/plumos-controller-ui-fbdev --renderer fbdev
```

ROM launch goes through:

```text
/mnt/plumos/bin/plumos-retroarch-launch
```

That bridge translates the MMF frontend launch contract into the existing V90S
RetroArch launcher environment:

```text
PLUMOS_V90S_RETROARCH_BIN=/usr/local/bin/retroarch
PLUMOS_V90S_CORE=/mnt/plumos/cores/quicknes_libretro.so
PLUMOS_V90S_ROUTE_CONFIG=/mnt/plumos/config/retroarch/plumos-v90s-retroarch-route
PLUMOS_V90S_RETROARCH_CONFIG_PATH=/mnt/plumos/config/retroarch/retroarch-v90s.cfg
PLUMOS_V90S_SDL2_POWERVR_DIR=/mnt/plumos/lib/plumos-sdl2-powervr
```

The current FE bridge intentionally uses the vendor/rootfs RetroArch binary at
`/usr/local/bin/retroarch`. The app-layer RetroArch binary exists as a packaged
artifact, but this live rootfs does not yet provide its complete dependency
closure (`libpipewire-0.3.so.0` was missing during live validation).

The default NES system uses:

```text
launch_profile=retroarch:quicknes
```

PicoArch and standalone launchers are present only as explicit stubs. They log
that the V90S runtime is not implemented yet and exit with code 69.

## Build Results

Frontend build:

```text
created: output/frontend/v90s
launcher: output/frontend/v90s/plumos/bin/plumos-frontend-launch
```

The built frontend binaries are arm64 Linux ELF binaries.

App-layer build:

```text
created: output/app-layer/v90s
version: 0.1.0-dev
compat_vendor: v90s-stockos-r1
mount_path: /mnt/plumos
```

App-layer inventory:

```text
files=334
frontend manifest entries=319
symlinks=0
```

Checksum validation:

```text
cd output/app-layer/v90s
sha256sum -c checksums.sha256
```

Result:

```text
OK
```

## Launch Plan Smoke Test

A temporary empty NES file was created in the ignored app-layer output and then
removed after the test.

Command shape:

```text
PLUMOS_ROOT=/workspace/output/app-layer/v90s \
PLUMOS_SDCARD_ROOT=/workspace/output/app-layer/v90s \
output/app-layer/v90s/bin/plumos-text-ui launch nes nes/test.nes \
  --profile retroarch:quicknes --no-scan
```

Important output:

```text
retroarch: /workspace/output/app-layer/v90s/bin/plumos-retroarch-launch (exists)
core: /workspace/output/app-layer/v90s/cores/quicknes_libretro.so (exists)
rom_exists: yes
can_execute: yes
```

## Release Package

Generated:

```text
dist/plumos-v90s-update-0.1.0-dev/
dist/plumos-v90s-update-0.1.0-dev.tar.gz
dist/plumos-v90s-update-0.1.0-dev.zip
dist/plumos-v90s-update-0.1.0-dev-SHA256SUMS
```

Archive checksum validation:

```text
cd dist
sha256sum -c plumos-v90s-update-0.1.0-dev-SHA256SUMS
```

Result:

```text
plumos-v90s-update-0.1.0-dev.tar.gz: OK
plumos-v90s-update-0.1.0-dev.zip: OK
```

## Boot Hook

The current development Debian init now probes p7/p6 for a plumOS app layer and
mounts the first valid candidate at:

```text
/mnt/plumos
```

The app layer is considered valid when these files exist:

```text
/mnt/plumos/manifest.json
/mnt/plumos/checksums.sha256
/mnt/plumos/bin/plumos-frontend-launch
```

When present, init starts:

```text
PLUMOS_ROOT=/mnt/plumos PLUMOS_SDCARD_ROOT=/mnt/plumos \
  /mnt/plumos/bin/plumos-frontend-launch
```

For current StockOS-compatible development images, the app layer can be copied
into p7 `SHARE` with:

```text
scripts/docker-build.sh sd-image --app-layer-dir output/app-layer/v90s ...
```

This is a compatibility route for frontend boot testing. The final release
layout still needs the validated FAT32 app/update/data partition.

## Real Device Live Validation

The app layer was copied to a running V90S over SSH:

```text
root@192.0.2.120:/mnt/plumos
```

Remote inventory after deployment:

```text
files=335
sha256sum -c checksums.sha256: OK
```

The test ROM was copied to:

```text
/mnt/plumos/Roms/nes/Super Mario Bros..nes
```

The frontend scanner detected it:

```text
PLUMOS_ROOT=/mnt/plumos PLUMOS_SDCARD_ROOT=/mnt/plumos \
  /mnt/plumos/bin/plumos-library-scan --system nes
```

Important output:

```text
system nes                roms=1 thumbnails=0
wrote: /mnt/plumos/state/frontend/systems/nes.json
```

The frontend was started independently from the SSH session:

```text
PLUMOS_ROOT=/mnt/plumos PLUMOS_SDCARD_ROOT=/mnt/plumos \
  nohup /mnt/plumos/bin/plumos-frontend-launch \
  >/mnt/plumos/Logs/frontend-ssh-start.log 2>&1 &
```

Running process:

```text
/mnt/plumos/bin/plumos-controller-ui-fbdev --renderer fbdev
```

Framebuffer capture confirmed that the frontend is drawing the top menu:

```text
PLUMOS CONTROLLER UI - TOP
1 NES
2 FAVORITES
3 RECENT
STATUS: FBDEV RENDERER READY
```

The framebuffer capture used:

```text
dd if=/dev/fb0 bs=1228800 count=1
```

The local PNG proof was written under the ignored output directory:

```text
output/validation/frontend-live/fb0-bgra.png
```

The launch plan for the copied test ROM is executable:

```text
PLUMOS_ROOT=/mnt/plumos PLUMOS_SDCARD_ROOT=/mnt/plumos \
  /mnt/plumos/bin/plumos-text-ui launch nes "nes/Super Mario Bros..nes" \
  --profile retroarch:quicknes --no-scan
```

Important output:

```text
retroarch: /mnt/plumos/bin/plumos-retroarch-launch (exists)
core: /mnt/plumos/cores/quicknes_libretro.so (exists)
rom_exists: yes
can_execute: yes
execute: no (--execute not specified)
```

## Frontend RetroArch Audio Regression

The first FE-launched NES run regressed to the old audio breakup behavior.
The cause was not the documented StockOS timing values themselves. They were
present in the repo, but the FE launch path was still allowing the older rootfs
route file to override them:

```text
/etc/plumos-v90s-retroarch-route
PLUMOS_V90S_VIDEO_THREADED=false
```

The resulting live launch log showed:

```text
retroarch-launch: route video=gl context=mali_fbdev threaded=false \
  input=sdl2 joypad=sdl2 audio=alsa sdl_video=mali sdl_render=software
```

The persistent RetroArch config also had to be repaired because
`v90s-retroarch-launch` reuses an existing config instead of rewriting it on
every launch:

```text
/mnt/plumos/config/retroarch/retroarch-v90s.cfg
video_threaded = "false"
```

The fix is to keep the FE/app-layer path independent of the rootfs `/etc`
route file:

```text
PLUMOS_V90S_ROUTE_CONFIG=/mnt/plumos/config/retroarch/plumos-v90s-retroarch-route
```

That app-layer route file preserves explicit overrides but defaults to the
StockOS-derived known-good route:

```text
PLUMOS_V90S_RETROARCH_BIN=/usr/local/bin/retroarch
PLUMOS_V90S_VIDEO_DRIVER=gl
PLUMOS_V90S_VIDEO_CONTEXT_DRIVER=mali_fbdev
PLUMOS_V90S_VIDEO_THREADED=true
PLUMOS_V90S_VIDEO_REFRESH_RATE=58.917103
PLUMOS_V90S_VRR_RUNLOOP_ENABLE=true
PLUMOS_V90S_AUDIO_DRIVER=alsa
PLUMOS_V90S_AUDIO_LATENCY=64
```

The live device was updated over SSH without deleting ROMs/Saves. The existing
RetroArch config was patched to the same known-good values:

```text
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
```

Post-fix live launch proof:

```text
retroarch-launch: route_config=/mnt/plumos/config/retroarch/plumos-v90s-retroarch-route present=yes
retroarch-launch: retroarch_bin=/usr/local/bin/retroarch
retroarch-launch: route video=gl context=mali_fbdev threaded=true input=sdl2 joypad=sdl2 audio=alsa sdl_video=mali sdl_render=software
```

RetroArch then stayed running:

```text
/usr/local/bin/retroarch --verbose --config /mnt/plumos/config/retroarch/retroarch-v90s.cfg \
  -L /mnt/plumos/cores/quicknes_libretro.so \
  /mnt/plumos/Roms/nes/Super Mario Bros..nes
```

Important RetroArch log lines:

```text
[INFO] [Video] Starting threaded video driver...
[INFO] [Audio] Set audio input rate to: 44100.00 Hz.
[INFO] [Audio] Started synchronous audio driver.
```

Still requiring physical validation:

- V90S built-in controls navigate the frontend
- pressing the frontend open button launches the NES ROM with continuous audio
- returning from RetroArch restores frontend control
- RetroArch settings persist under `/mnt/plumos/config/retroarch`
