# V90S PortMaster FLAC/JPEG Common ABI Validation

Date: 2026-07-20

## Goal

Promote the first common AArch64 ABI candidates found by the PortMaster static
audit into the reproducible V90S adapter runtime, then verify the same installed
ports against the real-device loader contract.

## Packaged Sources

PortMaster adapter version 8 builds and packages:

- FLAC 1.3.3 from the official Xiph archive as `libFLAC.so.8`
- IJG JPEG 8d from the official IJG archive as `libjpeg.so.8`

The source archives are pinned by SHA-256:

```text
213e82bd716c9de6db2f98bcadbc4c24c7e2efe8c75939a1a84e28539c4e1748  flac-1.3.3.tar.xz
fdc4d4c11338ad028a7d23fb53f5bb9354671392a67fb1b52e0c32a7121891f8  jpegsrc.v8d.tar.gz
```

The older IJG source predates AArch64 support in its bundled GNU config files.
The build replaces only `config.guess` and `config.sub` with the copies from the
pinned Debian toolchain image before configuring. It does not patch the JPEG
implementation or ABI.

ELF inspection of the build output confirmed:

```text
libFLAC.so.8: SONAME libFLAC.so.8; needs libogg.so.0, libm.so.6, libc.so.6
libjpeg.so.8: SONAME libjpeg.so.8; needs libc.so.6
```

The Xiph and IJG license texts are included in the app layer. The runtime helper
creates both FAT-safe SONAME links below `/run/plumos/portmaster/lib`; it does
not create persistent symlinks on the user volume.

## Build And Static Audit

The following completed successfully:

```sh
JOBS=4 ./scripts/docker-build.sh portmaster
./scripts/docker-build.sh app-layer --strict
./scripts/docker-build.sh portmaster-audit \
  --offline \
  --port a7xpg \
  --port abombniball \
  --port profadeluxe \
  --fail-on-missing
python3 -m unittest discover -s tests -p 'test_*.py' -v
```

The PortMaster component and complete app-layer checksum sets passed. The
three-port audit changed from two missing SONAME families to:

```text
payloads audited: 3
missing SONAMEs: 0
```

## Device Deployment

The live V90S was reachable at `192.0.2.120`. Its previous app-layer
checksum set was compared with the rebuilt output before deployment. There
were nine changed managed entries and no removed entries:

- two compatibility libraries
- the PortMaster runtime helper
- `installed.json`
- two license files
- the PortMaster component checksum and manifest copies
- the complete app-layer manifest

The complete app-layer `checksums.sha256` was committed last. PortMaster
upstream updates, installed ports, writable state, ROMs, saves, and frontend
state were not replaced. All nine changed entries passed SHA-256 verification
on the device after the switch.

## Hardware Loader Evidence

`plumos-portmaster-runtime prepare` created links for both new SONAMEs. Using
the normal PowerVR, common adapter, app-layer, and port-local search paths,
device-side `ldd` reported zero unresolved libraries for:

- A7Xpg
- Abombniball AArch64
- Abu Simbel Profanation Deluxe
- the packaged `libFLAC.so.8`
- the packaged `libjpeg.so.8`

The frontend remained one validated process throughout the loader checks.

This result closes the deterministic loader failures only. Each port still
requires physical video, audio, control, performance, emergency-exit, and FE
return validation before it can be called fully compatible.
