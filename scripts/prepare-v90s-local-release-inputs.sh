#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
VERSION=""

usage() {
    cat <<'EOF'
Usage:
  scripts/prepare-v90s-local-release-inputs.sh --version VERSION

Verify and materialize the tracked, non-emulator release baseline into the
normal .cache/ and output/ paths consumed by the existing V90S build scripts.
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
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf 'error: unknown local-input option: %s\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

[ -n "$VERSION" ] || {
    printf 'error: --version is required\n' >&2
    exit 2
}
case "$VERSION" in
    *[!0-9A-Za-z._+-]*)
        printf 'error: unsafe release version: %s\n' "$VERSION" >&2
        exit 2
        ;;
esac
BUNDLE_DIR="$ROOT_DIR/artifacts/release-inputs/v90s-$VERSION"
[ -d "$BUNDLE_DIR" ] || {
    printf 'error: tracked local release baseline not found: %s\n' "$BUNDLE_DIR" >&2
    exit 1
}
[ -f "$BUNDLE_DIR/SHA256SUMS" ] || {
    printf 'error: local release checksum manifest not found\n' >&2
    exit 1
}
[ "$(tr -d '\r\n' < "$BUNDLE_DIR/VERSION")" = "$VERSION" ] || {
    printf 'error: local release baseline version mismatch\n' >&2
    exit 1
}

(
    cd "$BUNDLE_DIR"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum -c SHA256SUMS
    else
        shasum -a 256 -c SHA256SUMS
    fi
)

required_archives=(
    hardware-knulli-a133.tar.gz
    hardware-ge8300-glibc.tar.gz
    userland.tar.gz
    network-services.tar.gz
    audio-router.tar.gz
    sdl2-powervr.tar.gz
    nextcommander.tar.gz
    music-player.tar.xz
    pyxel-runtime.tar.gz
    portmaster.tar.gz
    frontend.tar.gz
    system-rootfs.tar.gz
)
for archive in "${required_archives[@]}"; do
    [ -f "$BUNDLE_DIR/$archive" ] || {
        printf 'error: local release archive missing: %s\n' "$archive" >&2
        exit 1
    }
done

for target in \
    "$ROOT_DIR/.cache/knulli-linux/board/allwinner/a133/fsoverlay/lib/modules" \
    "$ROOT_DIR/.cache/knulli-linux/board/allwinner/a133/fsoverlay/lib/firmware" \
    "$ROOT_DIR/.cache/knulli-linux/board/allwinner/a133/powkiddy-v90s/patches/sdl2" \
    "$ROOT_DIR/.cache/knulli-linux/package/retroarch/retroarch" \
    "$ROOT_DIR/.cache/ge8300-drivers/3rdparty/include/khronos" \
    "$ROOT_DIR/.cache/ge8300-drivers/fbdev/glibc"; do
    case "$target" in
        "$ROOT_DIR"/.cache/*)
            rm -rf "$target"
            ;;
        *)
            printf 'error: unsafe hardware materialization target: %s\n' "$target" >&2
            exit 2
            ;;
    esac
done
mkdir -p "$ROOT_DIR/.cache"
tar -xzf "$BUNDLE_DIR/hardware-knulli-a133.tar.gz" -C "$ROOT_DIR"
tar -xzf "$BUNDLE_DIR/hardware-ge8300-glibc.tar.gz" -C "$ROOT_DIR"
mkdir -p \
    "$ROOT_DIR/.cache/knulli-linux" \
    "$ROOT_DIR/.cache/ge8300-drivers"
cp "$BUNDLE_DIR/licenses/KNULLI-Buildroot-COPYING" \
    "$ROOT_DIR/.cache/knulli-linux/COPYING"
cp "$BUNDLE_DIR/licenses/GE8300-drivers-LICENSE" \
    "$ROOT_DIR/.cache/ge8300-drivers/LICENSE"

for component in \
    userland network-services audio-router sdl2-powervr nextcommander \
    pyxel-runtime portmaster frontend system-rootfs; do
    target="$ROOT_DIR/output/$component"
    case "$target" in
        "$ROOT_DIR"/output/*)
            rm -rf "$target"
            ;;
        *)
            printf 'error: unsafe materialization target: %s\n' "$target" >&2
            exit 2
            ;;
    esac
done
rm -rf "$ROOT_DIR/output/music-player"

for archive in \
    userland.tar.gz network-services.tar.gz audio-router.tar.gz \
    sdl2-powervr.tar.gz nextcommander.tar.gz pyxel-runtime.tar.gz \
    portmaster.tar.gz frontend.tar.gz system-rootfs.tar.gz; do
    tar -xzf "$BUNDLE_DIR/$archive" -C "$ROOT_DIR"
done
tar -xJf "$BUNDLE_DIR/music-player.tar.xz" -C "$ROOT_DIR"

for required in \
    .cache/knulli-linux/COPYING \
    .cache/ge8300-drivers/LICENSE \
    output/userland/v90s/userland.manifest \
    output/network-services/v90s/network-services.manifest \
    output/audio-router/v90s/audio-router.manifest \
    output/sdl2-powervr/manifest.txt \
    output/nextcommander/v90s/nextcommander.manifest \
    output/music-player/v90s/music-player.manifest \
    output/pyxel-runtime/v90s/pyxel-runtime.manifest \
    output/portmaster/v90s/portmaster.manifest \
    output/frontend/v90s/frontend.manifest \
    output/system-rootfs/v90s/plumos-v90s-system-rootfs.squashfs; do
    [ -f "$ROOT_DIR/$required" ] || {
        printf 'error: materialized release input missing: %s\n' "$required" >&2
        exit 1
    }
done

printf 'materialized local non-emulator baseline: %s\n' "$VERSION"
