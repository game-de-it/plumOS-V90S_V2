# V90S Pyxel runtime bring-up

Date: 2026-07-16

## Initial failure

The FE selected `pyxel:v90s` and found the ROM and launcher, but execution
stopped before Python was started:

```text
error: Pyxel environment is not installed: /mnt/plumos/venvs/pyxel
run Apps -> Pyxel Setup first
```

The Pyxel-enabled squashfs was live and provided Python 3.11.2. SD2 was mounted
over `/mnt/plumos/roms`, however, and did not contain
`pyxel/requirements.txt`. The setup app therefore could not create the venv.

The installer now selects inputs in this order:

```text
PLUMOS_PYXEL_REQUIREMENTS override
/mnt/plumos/roms/pyxel/requirements.txt
/mnt/plumos/share/pyxel/requirements.txt
```

The packaged default is the supplied v1.0.0 requirements file with SHA-256
`f91ace4e987f2a57fffa9a61cc63e8dba49b29988e79c88ec82e7d5a939fec3d`.

Because the device had no IP route during this session, the four AArch64 wheels
were copied through ADB and installed offline. The live result was:

```text
Successfully installed Pillow-12.3.0 numpy-2.4.6 pygame-2.6.1 pyxel-2.9.3
No broken requirements found.
verified pyxel=2.9.3
verified pygame=2.6.1
verified numpy=2.4.6
verified Pillow=12.3.0
RESULT: Pyxel environment installed successfully
```

## Video failure and fix

After the venv was installed, `pyxel.init()` reported:

```text
Failed to create window: Could not initialize OpenGL / GLES library
```

The V90S launcher exposed the custom SDL2 directory but omitted the vendor GL
directory. Adding `/usr/lib/powervr` to `LD_LIBRARY_PATH` allowed the process to
load all of the intended libraries:

```text
/usr/lib/powervr/libEGL.so
/usr/lib/powervr/libGLESv2.so
/mnt/plumos/lib/plumos-sdl2-powervr/libSDL2-2.0.so.0
```

### Native window geometry fix

The first visible Pyxel frame exposed a second video defect: the left half was
black, the game was shifted to the right, and its right edge was clipped. Both
640x480 pages of the V90S 640x960 virtual framebuffer contained the same bad
frame, so this was not stale frontend content or a page-flip mismatch.

The KNULLI-derived GE8300 SDL2 patch forced every native window to 1280x720.
Pyxel therefore centered its game surface in a window twice as wide as the
V90S LCD, while the physical framebuffer still exposed only 640x480. The local
V90S follow-up patch now reports the active SDL display mode instead:

```c
window->w = _this->displays[0].current_mode.w;
window->h = _this->displays[0].current_mode.h;
```

The rebuilt SDL2 probe confirmed the corrected geometry on hardware:

```text
sdl2-probe: current_video_driver=mali
sdl2-probe: window_size=640x480
sdl2-probe: drawable_size=640x480
sdl2-probe: ok
```

The fixed `dungeon-antiqua.pyxapp` capture fills the expected viewport without
the previous horizontal displacement or clipping. Both framebuffer pages were
again identical:

```text
4e579b110381ec4023842830fee6802ae3179a3156e7fe60b539be4120a67a79  title-page0.png
4e579b110381ec4023842830fee6802ae3179a3156e7fe60b539be4120a67a79  title-page1.png
```

The generated and deployed SDL2 library has SHA-256
`2a574a9b495f8c68aac3f3696003aab7f31d55afd5d93ee2700be65444605bb0`.

## Audio failure and fix

Pyxel 2.9.3 requests 22.05 kHz, signed 16-bit, mono audio and does not allow SDL
to change the obtained format. The hotplug router previously advertised only
two-channel input, so SDL reported `Failed to initialize audio device`.

The router now accepts one- or two-channel input. Mono samples are duplicated
to its stereo physical stream before the existing internal mono mix, software
volume, and USB routing behavior. The existing stereo path is unchanged.

The exact Pyxel format then opened successfully:

```text
format: S16_LE
channels: 1
rate: 22050
plumos-hotplug: route=internal_mono card=0
```

A separate 48 kHz stereo open through `plumos_output` also succeeded after the
change.

## Runtime proof

`finardry.pyxapp` ran for the complete bounded hardware test. While running:

```text
python: /mnt/plumos/venvs/pyxel/bin/python3 -m pyxel play .../finardry.pyxapp
framebuffer sha256: 9a5759a1792875578accbdf6fcc369db925cb8b1bbae648323bf8ae0f5113be9
audio route: internal_mono, pcm=plumos_output, physical_pcm=hw:0,0
log: plumos-hotplug: route=internal_mono card=0
```

The process maps contained the PowerVR EGL/GLES libraries, the V90S SDL2
library, and the plumOS ALSA hotplug plugin. The bounded stop returned zero,
and exactly one `plumos-controller-ui-fbdev` process was restored.

The FE backend also resolves both content forms:

```text
.pyxapp -> plumos-pyxel-v90s-launch -m pyxel play
.py     -> plumos-pyxel-v90s-launch -m pyxel run
```

## Build validation

The following official targets completed:

```text
./scripts/docker-build.sh sdl2-powervr
./scripts/docker-build.sh audio-router
./scripts/docker-build.sh frontend
./scripts/docker-build.sh app-layer
```

All 4,069 entries in the regenerated app-layer `checksums.sha256` passed. The
live device hashes match the generated setup, launcher, audio helper, router,
and default requirements files.

## Remaining user validation

Visible output and audible game audio are now physically confirmed. Gamepad
controls and game-owned exit back to FE still require physical confirmation.
The loose `pyxel_midi-keybord.py` additionally imports `mido`; its project must
provide that dependency in `roms/pyxel/requirements.txt` before it is a valid
`.py` runtime test.
