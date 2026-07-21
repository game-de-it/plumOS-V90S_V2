# V90S standalone DOSBox Staging validation

Date: 2026-07-21

## Scope

This validation covers DOSBox Staging 0.82.2 on the physical V90S using:

```text
/mnt/plumos/roms/DOS/DOSBOX_DOOM.ZIP
```

The archive contains a valid DOS4GW `DOOM.EXE` and `DOOM1.WAD`. The executable
hash is `b8020523561a5ad9706e009a52d61c578f37faafd85ac471962308406292ce27`.

## Display failure

DOSBox was running, initialized the PowerVR SDL2 video driver, and produced a
valid RGB image in `/dev/fb0`, but every framebuffer alpha byte was zero. The
StockOS display path consumes that alpha, so the physical LCD was black.

The V90S DOSBox patch updates 32-bit SDL texture uploads by ORing SDL's alpha
mask into every source pixel. It preserves RGB and makes the scanout image
opaque. After rebuilding, the DOSBox shell was visible on the physical LCD.

## Executable launch failure

The first launcher revision extracted ZIP content correctly and selected
`DOOM.EXE`, but invoked it through this DOS shell command sequence:

```text
-c 'mount c ...' -c 'c:' -c '"DOOM.EXE"' -c 'exit'
```

DOSBox accepted and displayed the quoted command but did not start either
`DOOM.EXE` or the archive's `SETUP.EXE`. It returned to `C:\>` after about
0.8 seconds, and the early-exit guard left DOSBox open.

DOSBox Staging already defines a native positional `PATH` contract: when PATH
is a BAT, COM, or EXE, its parent is mounted as C:, the executable is run, and
DOSBox exits after the program ends. The generated plumOS launcher now passes
the selected extracted executable through that contract. ZIP extraction,
exact stem matching, ambiguous-entry rejection, and process-owned cleanup are
unchanged; no alternate-emulator or alternate-entry fallback was added.

## Build and deployment

```text
bash -n docker/plumos-v90s-toolchain/scripts/build-standalone-emulators.sh
./scripts/docker-build.sh standalone launcher-only
./scripts/docker-build.sh app-layer --strict
./scripts/deploy-app-layer-adb.sh
```

The strict deployment changed two payload files plus app-layer metadata. Host
and device hashes matched:

```text
7a988cfcda035f469a449181f260db97e70a520ee6757ba25ee7b270184f8218  bin/plumos-standalone-launch
b6787ac54c7c1b0d2c19b55238ec1655c86c82fd91957c0da69e1e2544b9c207  standalone/dosbox-staging/bin/dosbox
05a3a4636e7e75f883eb0a4dc9f746914390212f3d44da1701a03f9eb40f8a48  manifest.json
```

The selected checksum entries passed on the V90S before launch.

## Physical result

The deployed command was:

```text
dosbox -noconsole --fullscreen /run/plumos/cache/standalone/dosbox-staging/content/DOSBOX_DOOM.PID/DOOM.EXE
```

The process stayed active, changed to VGA 320x200 256-colour mode, initialized
the Sound Blaster 16 path, and the physical framebuffer showed the DOOM title
screen. This proves archive selection, extraction, executable startup, and LCD
output. Physical controller, audio, normal exit, and FE return are still open
acceptance checks.
