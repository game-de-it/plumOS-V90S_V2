# plumOS V90S local release inputs 1.0.0

This directory contains the validated, non-emulator build baseline consumed by
`scripts/docker-build.sh release-image --version 1.0.0`.

- component source commit: 5cd2c914229405e75fed43802aaf5f4809d1ca4c
- KNULLI commit: ac2ededdd3999443da4ba514dac22145d628f735
- GE8300 commit: 3213ecb88a9e9c6813a7a6aafe78da1f055aa050

RetroArch, libretro cores, PicoArch, and standalone emulators are intentionally
not included. The release-image target rebuilds those emulator-related
components from their existing pinned upstream recipes.
