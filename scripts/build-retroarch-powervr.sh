#!/usr/bin/env sh
set -eu

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    cat <<'USAGE'
Usage:
  build-retroarch-powervr.sh [options]

Builds the V90S RetroArch binary for the PowerVR GE8300 fbdev route.

Defaults:
  output directory: output/retroarch-powervr
  binary name:      retroarch-powervr
  compatibility:   output/retroarch-knulli symlink when possible

The remaining options are passed through to build-retroarch-knulli.sh, which
still contains the historical KNULLI reference-source integration.
USAGE
    exit 0
fi

export PLUMOS_V90S_RETROARCH_OUT="${PLUMOS_V90S_RETROARCH_OUT:-output/retroarch-powervr}"
export PLUMOS_V90S_RETROARCH_BIN_NAME="${PLUMOS_V90S_RETROARCH_BIN_NAME:-retroarch-powervr}"
export PLUMOS_V90S_RETROARCH_COMPAT_OUT="${PLUMOS_V90S_RETROARCH_COMPAT_OUT:-output/retroarch-knulli}"

exec "$script_dir/build-retroarch-knulli.sh" "$@"
