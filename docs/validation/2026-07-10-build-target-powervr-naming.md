# Build Target PowerVR Naming Validation

Date: 2026-07-10

## Purpose

Record the build-system cleanup that makes the normal plumOS-facing V90S
RetroArch route use StockOS/PowerVR naming instead of KNULLI naming.

KNULLI remains a reference source where the code still consumes KNULLI patches
or historical validation paths, but the default distribution-facing names are:

- `retroarch`
- `retroarch-powervr`
- `output/retroarch-powervr`
- `live-transfer-retroarch-powervr.sh`
- `debian-retroarch-powervr`

## Commands Run

```sh
sh -n scripts/build-retroarch-knulli.sh
sh -n scripts/build-retroarch-powervr.sh
sh -n scripts/live-transfer-retroarch-knulli.sh
sh -n scripts/live-transfer-retroarch-powervr.sh
sh -n scripts/v90s-retroarch-launch.sh
sh -n scripts/v90s-retroarch-stop.sh
sh -n scripts/build-step1-rootfs.sh
bash -n scripts/docker-build.sh

./scripts/docker-build.sh retroarch --help
./scripts/docker-build.sh cores --help
./scripts/docker-build.sh system-rootfs --help
./scripts/docker-build.sh app-layer

./scripts/docker-build.sh rootfs --help
./scripts/docker-build.sh quicknes --help
./scripts/docker-build.sh stockos-image --help
./scripts/docker-build.sh retroarch-knulli --help

./scripts/docker-build.sh cores
./scripts/docker-build.sh sdl2-powervr
./scripts/docker-build.sh retroarch
```

## Results

- Syntax checks passed.
- `retroarch`, `cores`, and `system-rootfs` are reachable through
  `scripts/docker-build.sh`.
- `app-layer` is exposed as an official reserved target and exits with status
  `3` until implemented.
- `rootfs`, `quicknes`, `stockos-image`, and `retroarch-knulli` print explicit
  transitional or legacy warnings.
- The managed RetroArch launcher/stop helpers accept `retroarch-powervr` while
  retaining the PID-file plus `/proc` validation path.
- `cores` built the current QuickNES core.
- `sdl2-powervr` built the patched SDL2 payload.
- `retroarch` built the new preferred binary:

```text
output/retroarch-powervr/usr/local/bin/retroarch-powervr
```

SHA256:

```text
b37b9afc692453407d3453d88c72a6f914550cd096abfde3f3204a77178cb459
```

The generated output also contains:

```text
output/retroarch-powervr/usr/local/bin/retroarch-knulli -> retroarch-powervr
```

This keeps old rootfs/live-transfer references usable when the new output
directory is selected explicitly. The older `output/retroarch-knulli` directory
already existed in this checkout, so the compatibility output symlink was not
created over it.

QuickNES SHA256:

```text
da48490d5aab244bc0c13e6381555ac2003b438336dafe7db122043503686c68
```

## Notes

No real-device validation was performed for this change. The change is a build
entrypoint and artifact-naming cleanup only.
