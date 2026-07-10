#!/usr/bin/env sh
set -eu

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    cat <<'USAGE'
Usage:
  live-transfer-retroarch-powervr.sh IP [--config PATH] [--refresh-rate RATE] [--menu|--content] [--transfer-only]

Copies the locally built V90S PowerVR RetroArch binary, QuickNES core, and
V90S launcher/stop scripts to a running device over SSH.

Default RetroArch source:
  output/retroarch-powervr/usr/local/bin/retroarch-powervr

The remaining options are passed through to live-transfer-retroarch-knulli.sh,
which remains as the legacy implementation helper.
USAGE
    exit 0
fi

export PLUMOS_V90S_RETROARCH_BIN_SRC="${PLUMOS_V90S_RETROARCH_BIN_SRC:-output/retroarch-powervr/usr/local/bin/retroarch-powervr}"

exec "$script_dir/live-transfer-retroarch-knulli.sh" "$@"
