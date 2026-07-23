#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
ENTRYPOINT="$ROOT_DIR/scripts/docker-build.sh"
DRY_RUN=0
RELEASE_VERSION="${PLUMOS_V90S_RELEASE_VERSION:-${PLUMOS_V90S_APP_LAYER_VERSION:-0.1.0-dev}}"

export PLUMOS_V90S_RELEASE_VERSION="$RELEASE_VERSION"
export PLUMOS_V90S_APP_LAYER_VERSION="$RELEASE_VERSION"
export PLUMOS_V90S_SYSTEM_VERSION="$RELEASE_VERSION"

usage() {
    cat <<'EOF'
Usage:
  scripts/docker-build.sh all [--dry-run]

Options:
  --dry-run  Print the ordered release build graph without running it.
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf 'error: unknown all option: %s\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

run_target() {
    printf 'all: %s\n' "$*"
    [ "$DRY_RUN" -eq 1 ] || "$ENTRYPOINT" "$@"
}

run_target vendor-runtime
run_target userland
run_target network-services
run_target audio-router
run_target sdl2-powervr
run_target retroarch
run_target cores --filter all
run_target picoarch
run_target standalone
run_target nextcommander
run_target music-player
run_target pyxel-runtime
run_target portmaster
run_target frontend
run_target system-rootfs
run_target app-layer --strict
run_target update-package --type runtime \
    --input output/app-layer/v90s \
    --base-version '*' \
    --version "$RELEASE_VERSION" \
    --output-dir dist/updates
run_target update-package --type system \
    --input output/system-rootfs/v90s/plumos-v90s-system-rootfs.squashfs \
    --base-version '*' \
    --version "$RELEASE_VERSION" \
    --output-dir dist/updates
run_target boot-package
run_target boot-image
run_target sd-image
run_target release
