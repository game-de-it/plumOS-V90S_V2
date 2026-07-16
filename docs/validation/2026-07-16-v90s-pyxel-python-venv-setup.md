# V90S Pyxel Python and p7 venv setup

Date: 2026-07-16

Runtime follow-up: the first real-device boot found that SD2 can hide the
user-owned requirements path. The current installer therefore falls back to a
packaged default. See
`docs/validation/2026-07-16-v90s-pyxel-runtime-bringup.md` for the live Pyxel,
PowerVR, and mono-audio result. The sections below preserve the original
pre-hardware build validation.

## Goal

Prepare the first V90S Pyxel runtime boundary:

- Python itself belongs in the read-only p5 system squashfs.
- pip-installed project modules belong in a venv on p7.
- `Apps -> Pyxel Setup` consumes
  `/mnt/plumos/roms/pyxel/requirements.txt` and displays its result.
- V90S Pyxel content uses a V90S launcher rather than an MMF launcher name.

Real-device rendering, audio, input, and exit behavior remain a separate
validation step after booting the new squashfs.

## Requirements input

The supplied v1.0.0 file contains:

```text
pyxel==2.9.3
pygame>=2.6,<3
numpy>=2.0,<3
Pillow>=10,<13
```

Its SHA-256 is:

```text
f91ace4e987f2a57fffa9a61cc63e8dba49b29988e79c88ec82e7d5a939fec3d
```

The installer does not download or replace `requirements.txt`. It runs only
when that user-owned file exists at the path above.

## Runtime layout

```text
p5 squashfs:
  /usr/bin/python3
  Python 3.11 standard library
  python3-venv
  python3-pip

p7 FAT32:
  /mnt/plumos/roms/pyxel/requirements.txt
  /mnt/plumos/venvs/pyxel
  /mnt/plumos/cache/pip
  /mnt/plumos/cache/pip-tmp
  /mnt/plumos/logs/frontend-apps-latest.log
```

The setup app uses binary wheels only and has a default 900-second timeout.
It builds the venv with copied interpreter files and suppresses CPython's
optional `lib64 -> lib` alias because FAT32 cannot create symbolic links.
Before replacing an existing venv it preserves it as `.previous`; any venv,
pip, dependency, or import failure restores that previous environment.

## Build validation

The official entry points completed successfully:

```text
./scripts/docker-build.sh frontend
./scripts/docker-build.sh system-rootfs
./scripts/docker-build.sh app-layer
```

The generated AArch64 rootfs reported:

```text
Python 3.11.2
pip 23.0.1
rootfs squashfs: 92.05 MiB
sha256: 635f591b43878ae6b2ab2f4b8db54dc397622f24d0cf7ec5bbf788ed572825b0
```

The app-layer manifest includes:

```text
bin/plumos-pyxel-setup
bin/plumos-pyxel-v90s-launch
```

The Pyxel system definition now selects `pyxel:v90s`; the text UI resolves it
to `/mnt/plumos/bin/plumos-pyxel-v90s-launch` for both `.py` and `.pyxapp`.

A synthetic `.py` launch plan reported:

```text
launch_profile: pyxel:v90s
pyxel_launcher: /mnt/plumos/bin/plumos-pyxel-v90s-launch (exists)
rom_exists: yes
can_execute: yes
```

## FAT32 install simulation

A privileged AArch64 toolchain container mounted a newly formatted 768 MiB
FAT32 loop volume at `/mnt/plumos`, then ran the packaged setup script through
the generated rootfs. The result was:

```text
Successfully installed Pillow-12.3.0 numpy-2.4.6 pygame-2.6.1 pyxel-2.9.3
No broken requirements found.
verified pyxel=2.9.3
verified pygame=2.6.1
verified numpy=2.4.6
verified Pillow=12.3.0
RESULT: Pyxel environment installed successfully
symlink_count=0
FAT usage after venv plus wheel cache: 250 MiB
```

Running `plumos-pyxel-setup status` against the same FAT volume repeated the
dependency and import checks successfully.

A separate interrupted-update simulation started with both a partial current
venv and a `.previous` venv marker. Forced setup failure removed the partial
tree, restored the previous marker, removed the temporary backup name, and
returned nonzero.

## Frontend action validation

The controller script drove the same action path as physical controls:

```text
START -> Apps -> Pyxel Setup -> A
```

With no test `requirements.txt` in the app-layer build directory, the expected
bounded error was displayed as:

```text
plumOS controller UI - Pyxel Setup Results
ERROR: requirements.txt not found: /mnt/plumos/roms/pyxel/requirements.txt
finished rc=1
```

The result view shows generic setup/pip output rather than discarding it as
scraper-only data. Pressing B returns to Apps with `Pyxel Setup` selected.

## SD image

The policy-aligned image containing the new rootfs and complete app layer is:

```text
output/images/plumos-v90s-pyxel-20260716-3.img
output/images/plumos-v90s-pyxel-20260716-3.img.manifest.txt
size: 4,549,849,088 bytes
sha256: e53ab4ad4147a5442643396ea58c730f1d51b2e4410ad67cec3f1c20c621931f
p5 sha256: 635f591b43878ae6b2ab2f4b8db54dc397622f24d0cf7ec5bbf788ed572825b0
p7 app manifest sha256: 9f29c962b3c053c7df2dd513f0cbf85157826a50716ce94c45143a21f64c7fcd
```

The image uses captured StockOS boot0 and boot-package data with KNULLI
fallback disabled. macOS mounted it read-only and reported clean p1/p7 FAT
structures. All 4,068 entries in p7 `checksums.sha256` passed. The mounted
image contained:

```text
Apps action: shell:/mnt/plumos/bin/plumos-pyxel-setup install
Pyxel default: pyxel:v90s
plumos-pyxel-setup sha256:
  16b0aa8105179a8256aee59eaa9c70a6a5577c25477ff415af0f4e498d4add45
plumos-pyxel-v90s-launch sha256:
  61e494076df521b2e307b61ec93ababb3eb4c76e8b0fc4c801766a039acba80d
```

## Remaining hardware validation

The currently running V90S image predates this rootfs and has no `python3`.
After writing the new image, validate:

1. Pyxel Setup installation over the V90S network path.
2. `.py` and `.pyxapp` video through SDL2 PowerVR.
3. built-in controls and an exit path back to FE.
4. internal mono and USB-DAC audio through `plumos_output`.
