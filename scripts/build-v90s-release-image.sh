#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
VERSION=""
IMAGE_NAME=""
DRY_RUN=0
INCREMENTAL=0
CACHE_HELPER="$ROOT_DIR/scripts/v90s_release_component_cache.py"

usage() {
    cat <<'EOF'
Usage:
  scripts/docker-build.sh release-image --version VERSION [--name NAME]
      [--incremental] [--dry-run]

Materialize the tracked non-emulator release baseline, rebuild the emulator
components, assemble the strict app-layer, and create a verified SD image.
The private update-signing key is not required.

With --incremental, verified emulator outputs are reused when their tracked
inputs and relevant build environment have not changed. The app-layer, boot
payloads, final SD image, and all image verification are always regenerated.
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --version)
            [ "$#" -ge 2 ] || {
                printf 'error: --version requires a value\n' >&2
                exit 2
            }
            VERSION="$2"
            shift 2
            ;;
        --name)
            [ "$#" -ge 2 ] || {
                printf 'error: --name requires a value\n' >&2
                exit 2
            }
            IMAGE_NAME="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --incremental)
            INCREMENTAL=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf 'error: unknown release-image option: %s\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [ -z "$VERSION" ]; then
    printf 'error: --version is required\n' >&2
    usage >&2
    exit 2
fi
case "$VERSION" in
    *[!0-9A-Za-z._+-]*)
        printf 'error: unsafe release version: %s\n' "$VERSION" >&2
        exit 2
        ;;
esac

if [ -z "$IMAGE_NAME" ]; then
    IMAGE_NAME="plumos-v90s-release-${VERSION}-vendor-r1.img"
fi
case "$IMAGE_NAME" in
    */*|""|.|..)
        printf 'error: unsafe image name: %s\n' "$IMAGE_NAME" >&2
        exit 2
        ;;
    *.img)
        ;;
    *)
        printf 'error: image name must end in .img: %s\n' "$IMAGE_NAME" >&2
        exit 2
        ;;
esac

export PLUMOS_V90S_RELEASE_VERSION="$VERSION"
export PLUMOS_V90S_APP_LAYER_VERSION="$VERSION"
export PLUMOS_V90S_SYSTEM_VERSION="$VERSION"

run_local() {
    printf 'release-image: %s\n' "$*"
    [ "$DRY_RUN" -eq 1 ] || "$@"
}

run_target() {
    printf 'release-image: %s\n' "$*"
    [ "$DRY_RUN" -eq 1 ] || "$ROOT_DIR/scripts/docker-build.sh" "$@"
}

run_emulator_component() {
    component="$1"
    shift
    if [ "$DRY_RUN" -eq 1 ]; then
        printf 'release-image: cache-check %s incremental=%s\n' \
            "$component" "$INCREMENTAL"
        run_target "$@"
        return
    fi
    if [ "$INCREMENTAL" -eq 1 ] &&
       "$CACHE_HELPER" check "$component" --version "$VERSION"; then
        printf 'release-image: reused verified %s output\n' "$component"
        return
    fi
    run_target "$@"
    "$CACHE_HELPER" record "$component" --version "$VERSION"
}

run_local "$ROOT_DIR/scripts/prepare-v90s-local-release-inputs.sh" \
    --version "$VERSION"
run_target vendor-runtime

if [ "$DRY_RUN" -eq 1 ]; then
    printf 'release-image: verify-system-version %s\n' "$VERSION"
else
    embedded_system_version="$(
        "$ROOT_DIR/scripts/docker-build.sh" run \
            unsquashfs -cat \
            output/system-rootfs/v90s/plumos-v90s-system-rootfs.squashfs \
            etc/plumos-system-version
    )"
    if [ "$embedded_system_version" != "$VERSION" ]; then
        printf 'error: bundled System version mismatch: expected=%s actual=%s\n' \
            "$VERSION" "$embedded_system_version" >&2
        exit 1
    fi
    printf 'release-image: verified bundled System version %s\n' "$VERSION"
fi

# Only emulator-related components are rebuilt from their pinned upstream
# sources. All other release payloads were materialized from the tracked local
# baseline above.
run_emulator_component retroarch retroarch
run_emulator_component cores cores --filter all
run_emulator_component picoarch picoarch
run_emulator_component standalone standalone

run_target app-layer --strict
run_target boot-package
run_target boot-image
run_target sd-image --name "$IMAGE_NAME"
