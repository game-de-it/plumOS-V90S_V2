#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SOURCE_ROOT="$ROOT_DIR"
HARDWARE_ROOT="$ROOT_DIR"
VERSION=""

usage() {
    cat <<'EOF'
Usage:
  scripts/package-v90s-local-release-inputs.sh \
    --version VERSION [--source-root PATH] [--hardware-root PATH]

Maintainer helper that packages the validated local non-emulator outputs and
the minimal V90S hardware build inputs used by release-image.
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --version) VERSION="$2"; shift 2 ;;
        --source-root) SOURCE_ROOT="$2"; shift 2 ;;
        --hardware-root) HARDWARE_ROOT="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'error: unknown package option: %s\n' "$1" >&2; exit 2 ;;
    esac
done

[ -n "$VERSION" ] || {
    printf 'error: --version is required\n' >&2
    exit 2
}
SOURCE_ROOT="$(CDPATH= cd -- "$SOURCE_ROOT" && pwd)"
HARDWARE_ROOT="$(CDPATH= cd -- "$HARDWARE_ROOT" && pwd)"
SOURCE_COMMIT="$(git -C "$SOURCE_ROOT" rev-parse HEAD 2>/dev/null || printf unknown)"
OUT_DIR="$ROOT_DIR/artifacts/release-inputs/v90s-$VERSION"
case "$OUT_DIR" in
    "$ROOT_DIR"/artifacts/release-inputs/v90s-*) ;;
    *) printf 'error: unsafe release-input output: %s\n' "$OUT_DIR" >&2; exit 2 ;;
esac

required_paths=(
    output/userland/v90s
    output/network-services/v90s
    output/audio-router/v90s
    output/sdl2-powervr
    output/nextcommander/v90s
    output/music-player/v90s
    output/pyxel-runtime/v90s
    output/portmaster/v90s
    output/frontend/v90s
    output/system-rootfs/v90s
)
for path in "${required_paths[@]}"; do
    [ -e "$SOURCE_ROOT/$path" ] || {
        printf 'error: local release input missing: %s/%s\n' "$SOURCE_ROOT" "$path" >&2
        exit 1
    }
done

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR/licenses"
printf '%s\n' "$VERSION" > "$OUT_DIR/VERSION"

tar_common=(--no-xattrs)
for component in \
    userland network-services audio-router nextcommander pyxel-runtime \
    portmaster frontend; do
    tar "${tar_common[@]}" -czf "$OUT_DIR/$component.tar.gz" \
        -C "$SOURCE_ROOT" "output/$component/v90s"
done
tar "${tar_common[@]}" -czf "$OUT_DIR/sdl2-powervr.tar.gz" \
    -C "$SOURCE_ROOT" output/sdl2-powervr
tar "${tar_common[@]}" -cJf "$OUT_DIR/music-player.tar.xz" \
    -C "$SOURCE_ROOT" output/music-player/v90s
tar "${tar_common[@]}" -czf "$OUT_DIR/system-rootfs.tar.gz" \
    -C "$SOURCE_ROOT" output/system-rootfs/v90s

tar "${tar_common[@]}" -czf "$OUT_DIR/hardware-knulli-a133.tar.gz" \
    -C "$HARDWARE_ROOT" \
    .cache/knulli-linux/board/allwinner/a133/fsoverlay/lib/modules \
    .cache/knulli-linux/board/allwinner/a133/fsoverlay/lib/firmware \
    .cache/knulli-linux/board/allwinner/a133/powkiddy-v90s/patches/sdl2 \
    .cache/knulli-linux/package/retroarch/retroarch
tar "${tar_common[@]}" -czf "$OUT_DIR/hardware-ge8300-glibc.tar.gz" \
    -C "$HARDWARE_ROOT" \
    .cache/ge8300-drivers/3rdparty/include/khronos \
    .cache/ge8300-drivers/fbdev/glibc

cp "$HARDWARE_ROOT/.cache/knulli-linux/COPYING" \
    "$OUT_DIR/licenses/KNULLI-Buildroot-COPYING"
cp "$HARDWARE_ROOT/.cache/ge8300-drivers/LICENSE" \
    "$OUT_DIR/licenses/GE8300-drivers-LICENSE"

cat > "$OUT_DIR/README.md" <<EOF
# plumOS V90S local release inputs $VERSION

This directory contains the validated, non-emulator build baseline consumed by
\`scripts/docker-build.sh release-image --version $VERSION\`.

- component source commit: $SOURCE_COMMIT
- KNULLI commit: ac2ededdd3999443da4ba514dac22145d628f735
- GE8300 commit: 3213ecb88a9e9c6813a7a6aafe78da1f055aa050

RetroArch, libretro cores, PicoArch, and standalone emulators are intentionally
not included. The release-image target rebuilds those emulator-related
components from their existing pinned upstream recipes.
EOF

(
    cd "$OUT_DIR"
    find . -type f ! -name SHA256SUMS -print0 |
        sort -z |
        xargs -0 shasum -a 256 > SHA256SUMS
    shasum -a 256 -c SHA256SUMS
)
printf 'packaged local release inputs: %s\n' "$OUT_DIR"
