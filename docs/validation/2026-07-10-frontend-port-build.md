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

## Frontend D-Pad Regression

After the RetroArch route fix, the user reported that FE d-pad movement did not
seem to work. Process inspection showed that the frontend itself was not double
started:

```text
frontend_count=1
/run/plumos-v90s/frontend.pid=2488
/mnt/plumos/bin/plumos-controller-ui-fbdev --renderer fbdev
```

The frontend had the expected input devices open:

```text
/proc/2488/fd/4 -> /dev/input/event4
/proc/2488/fd/5 -> /dev/input/event0
```

`/dev/input/event4` is `adc_gamepad` and advertises absolute axes:

```text
Name="adc_gamepad"
Handlers=event4
EV=20000b
ABS=3001b
```

The root cause was that `plumos_controller_ui.c` handled only `EV_KEY` events
from evdev. V90S d-pad directions can arrive as `EV_ABS` axes, so those events
were ignored by the FE even though the input device was open.

The FE input loop now maps these axes to normal navigation actions:

```text
ABS_X / ABS_HAT0X -> left/right
ABS_Y / ABS_HAT0Y -> up/down
```

The same key-repeat path is used for held d-pad directions. The updated app
layer was live deployed over SSH, the old FE process was stopped by validating
`/run/plumos-v90s/frontend.pid`, and the new FE was started as PID `2488`.

Still requiring physical validation:

- confirm V90S d-pad moves the FE cursor
- confirm A/B/START/SELECT still map correctly in the FE
- confirm launching and returning from RetroArch leaves one FE process

User follow-up confirmed that the V90S d-pad moves the FE cursor.

## Formal fbdev Frontend Design Pass

The first V90S frontend screen was still effectively a development text view.
Even though `config/frontend/settings.json` selected `graphic` mode, the V90S
fbdev renderer was not marked as graphic-capable and its renderer drew internal
line protocol text directly.

The fbdev frontend now treats V90S as a graphic frontend target while still
using only `/dev/fb0`. The renderer consumes the existing frontend line protocol
instead of exposing it:

```text
graphic_mode=top
graphic_mode=roms
graphic_mode=favorites
graphic_mode=recent
graphic_mode=gallery
graphic_entry<TAB>selected<TAB>title<TAB>detail<TAB>media
graphic_theme_color<TAB>name<TAB>#rrggbb
```

Visible layout behavior:

```text
TOP       -> plumOS/V90S shell, SYSTEMS heading, selected system tiles
ROM lists -> plumOS/V90S shell, system heading, ROM list, selected detail panel
menus     -> plumOS/V90S shell, formal list view with internal metadata hidden
```

The fbdev renderer intentionally does not draw the old shortcut/help strings or
the `graphic_*` protocol rows. It also does not run a continuous 16 ms refresh
loop on static fbdev screens; periodic refresh is retained only for rescue
network and background ROM scan status.

Host rebuild:

```text
./scripts/docker-build.sh frontend
./scripts/docker-build.sh app-layer --strict
```

Result:

```text
created: output/frontend/v90s
created: output/app-layer/v90s
sha256sum -c output/app-layer/v90s/checksums.sha256: OK
```

The rebuilt frontend binary is still the expected V90S target:

```text
output/app-layer/v90s/bin/plumos-controller-ui-fbdev:
ELF 64-bit LSB pie executable, ARM aarch64
```

Live deployment was not completed during this pass because the previously known
SSH address was no longer reachable:

```text
root@192.0.2.120: port 22 timed out
192.0.2.100: ping OK, port 22 open, but SSH banner timed out
192.0.2.108: ping OK, port 22 refused
```

The next live validation step is to reconnect V90S SSH, copy
`output/app-layer/v90s` to `/mnt/plumos` without deleting ROMs/Saves, restart
only the validated frontend PID from `/run/plumos-v90s/frontend.pid`, and capture
`/dev/fb0` for visual proof.

## Formal fbdev Frontend Live Validation

SSH returned at:

```text
root@192.0.2.120
```

The running image had p7 `SHARE` present but not mounted. It was empty except for
`lost+found`, so p7 was mounted live as:

```text
/dev/mmcblk0p7 -> /mnt/plumos
```

The rebuilt app layer was copied to `/mnt/plumos`. AppleDouble `._*` files from
the macOS tar stream were removed afterward. The app-layer checksum passed on
device:

```text
cd /mnt/plumos
sha256sum -c checksums.sha256: OK
```

The NES test ROM was copied to:

```text
/mnt/plumos/Roms/nes/Super Mario Bros..nes
```

The scanner detected it:

```text
system nes                roms=1 thumbnails=0
wrote: /mnt/plumos/state/frontend/systems/nes.json
```

The frontend was started from SSH:

```text
PLUMOS_ROOT=/mnt/plumos PLUMOS_SDCARD_ROOT=/mnt/plumos \
  nohup /mnt/plumos/bin/plumos-frontend-launch \
  >/mnt/plumos/Logs/frontend-ssh-start.log 2>&1 &
```

Runtime proof:

```text
frontend pid=1061 cmd=/mnt/plumos/bin/plumos-controller-ui-fbdev --renderer fbdev
frontend_count=1
retroarch_count=0
pidfile=1061
pidfile_alive=yes
```

Framebuffer metadata:

```text
virtual_size=640,960
bpp=32
stride=2560
```

The formal frontend was captured from fb page 0:

```text
output/validation/frontend-formal-live/fb0-page0.png
d94eb51c27653d1b6a4d658abf7a9da035360ebde1841a9f0831d9519610f86b
```

The second framebuffer page still contained a stale RetroArch menu image from a
previous run:

```text
output/validation/frontend-formal-live/fb0-page1.png
fecac0e4af0707015fe0ee02b1b78d0f7d1f64388ca7bc027a3b8e2c42409509
```

That stale page was not a live RetroArch process; `/proc` showed
`retroarch_count=0`.

## MMF-Style Graphic TOP Live Validation

The V90S fbdev renderer now follows the MMF graphic TOP contract instead of the
temporary formal mock layout. The controller emits the same line protocol shape:

```text
graphic_mode=top
graphic_theme_motion<TAB>top_layout<TAB>tile_grid
graphic_entry<TAB>selected<TAB>title<TAB>detail<TAB>media
```

Current MMF leaves the TOP `detail` field empty, so the V90S TOP does not draw
ROM counts unless the controller later supplies that field. System logo PNGs are
loaded from the MMF theme-compatible path:

```text
/mnt/plumos/themes/default/logos/systems/<system_id>.png
```

The V90S fbdev controller is built with libpng support:

```text
PLUMOS_FBDEV_ENABLE_PNG=1
NEEDED: libpng16.so.16
```

Host build proof:

```text
./scripts/docker-build.sh image
./scripts/docker-build.sh frontend
./scripts/docker-build.sh app-layer
```

Important hashes:

```text
e935922d60467a0d64de7ff6b27d87522106d2eb130ec00039cf251a957037cf  output/app-layer/v90s/bin/plumos-controller-ui-fbdev
6714edbb4801741076c98395b8dc22b40dd61df954ff0353baffecb4088585f7  output/app-layer/v90s/bin/plumos-frontend-stop
74d1ef74c22479d315f9759b315041e77590b42ce3a1056706d528bbb86ff5a5  output/app-layer/v90s/themes/default/logos/systems/nes.png
```

The same hashes were confirmed on the live V90S:

```text
e935922d60467a0d64de7ff6b27d87522106d2eb130ec00039cf251a957037cf  /mnt/plumos/bin/plumos-controller-ui-fbdev
74d1ef74c22479d315f9759b315041e77590b42ce3a1056706d528bbb86ff5a5  /mnt/plumos/themes/default/logos/systems/nes.png
```

The app-layer checksum passed on both host and live V90S:

```text
cd output/app-layer/v90s && sha256sum -c checksums.sha256: OK
cd /mnt/plumos && sha256sum -c checksums.sha256: OK
```

Process cleanup was required because earlier manual validation had left
multiple frontend instances. After stopping only `plumos-controller-ui-fbdev`
and restarting through `plumos-frontend-launch`, the live device had exactly one
frontend process:

```text
pidof plumos-controller-ui-fbdev: 2245
```

The app layer now includes a frontend-specific stop helper so future FE restarts
do not rely on process-name grep patterns that can match the SSH command line:

```text
/mnt/plumos/bin/plumos-frontend-stop status
plumos-frontend-stop: pid=2245 cmd=/mnt/plumos/bin/plumos-controller-ui-fbdev --renderer fbdev
```

Framebuffer capture confirmed the MMF-style TOP on page 0:

```text
output/validation/frontend-mmf-top-live/fb0-page0-wifi.png
03fb247ce047b8f6df60ed7baf40276439cb31b4c02ed347278ad11ab63eccfc
```

Observed page 0 contents:

```text
PLUMOS V90S GUI
12:36  WIFI  BAT --
NES / FAVORITES / RECENT
MMF-style tile grid
system logo PNGs visible
no TOP ROM counts because detail is empty
STATUS: FBDEV RENDERER READY
```

Framebuffer page 1 still contained a stale RetroArch menu from an earlier run:

```text
output/validation/frontend-mmf-top-live/fb0-page1-wifi.png
448e928f3f797c572a33202229d7c181d4f9834adda49761ca857d1494b65d4b
```

This was only the inactive framebuffer page. The live frontend process count was
one, and the theme directory was cleaned so no AppleDouble `._*` files remain on
the device.
