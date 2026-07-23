# V90S Clean-Clone Release-Image Contract

Date: 2026-07-23
Implementation commit: `0fd362856001af0ea9298996ed1374047388133d`
Host result: PASS
Real-device result: pending

## Purpose

Prove that a Git clone contains every non-emulator input required to build the
V90S 1.0.0 SD image. Network source retrieval remains limited to RetroArch,
libretro cores, PicoArch, standalone emulators, and Docker image dependencies.

## Tracked Local Inputs

The clone contains two checksum-pinned baselines:

- `artifacts/vendor/v90s-stockos-r1/`
- `artifacts/release-inputs/v90s-1.0.0/`

The release-input baseline contains the System SquashFS, frontend, userland,
network services, audio router, NextCommander, music player, Pyxel runtime,
PortMaster, PowerVR SDL2 runtime, and the minimal KNULLI A133 and GE8300
hardware inputs used by the existing build scripts. No ROM, game BIOS, save
data, personal network setting, SSH key, or update-signing key is tracked.

Every tracked artifact blob is smaller than 100,000,000 bytes. The largest is
`system-rootfs.tar.gz` at 96,395,337 bytes.

## Independent Clone Check

An independent local clone was made without local Git hard links:

```text
git clone --no-local SOURCE clean-clone
clone_commit=0fd362856001af0ea9298996ed1374047388133d
preexisting_output=no
preexisting_cache=no
```

The following checks passed in that clone:

```text
python3 -m unittest tests.test_release_image_build
Ran 5 tests
OK

./scripts/docker-build.sh release-image --version 1.0.0 --dry-run
./scripts/prepare-v90s-local-release-inputs.sh --version 1.0.0
./scripts/docker-build.sh vendor-runtime

clean_clone_system_version=1.0.0
clean_clone_vendor_manifest=present
clean_clone_hardware_inputs=present
```

The clean clone then built RetroArch successfully using the materialized local
KNULLI/GE8300/SDL inputs:

```text
created: output/retroarch-powervr/usr/local/bin/retroarch-powervr
clean_clone_retroarch=built
```

This check exposed and fixed a missing license-file materialization step that
had previously been hidden by an existing maintainer cache.

## Full Release Build

The supported command was also run end to end from the same tracked source
state:

```text
./scripts/docker-build.sh release-image --version 1.0.0

libretro_recipes_built=114
libretro_recipes_failed=0
app_layer_libretro_files=118
standalone_built=9
standalone_failed=0
app_layer_version=1.0.0
app_layer_complete=true
system_version=1.0.0
image_verification=PASS
```

Artifact:

```text
path=output/images/plumos-v90s-release-1.0.0-vendor-r1.img
size=2840088576
sha256=a5fbb9deba4660b2a0d18d7ca531052635387532e5a9056061617181df2b702e
```

The independent `.sha256` check, strict app-layer check, license audit,
preflight, GPT geometry, boot regions, A/B System payloads, and p3 runtime
verification all passed.

## Remaining Gate

This is host-side proof of the clean-clone build contract and generated image.
It does not prove physical V90S boot or runtime behavior. Cold boot, display,
controls, audio, representative emulator/App launch and exit, persistence,
reboot, and shutdown remain required before final public release.
