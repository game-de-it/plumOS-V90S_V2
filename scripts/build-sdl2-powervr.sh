#!/usr/bin/env sh
set -eu

version="2.30.6"
out_dir="output/sdl2-powervr"
pvr_dir=".cache/ge8300-drivers"
knulli_src=".cache/knulli-linux"
source_cache=".cache/sources"
keep_work=0
script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
repo_root="$(CDPATH= cd -- "$script_dir/.." && pwd)"

usage() {
    cat <<'USAGE'
Usage:
  build-sdl2-powervr.sh [options]

Options:
  --version VERSION    SDL2 release version, default 2.30.6
  --out-dir PATH      output directory, default output/sdl2-powervr
  --pvr-dir PATH      GE8300 driver checkout, default .cache/ge8300-drivers
  --knulli-src PATH   KNULLI source checkout, default .cache/knulli-linux
  --source-cache PATH source tarball cache, default .cache/sources
  --keep-work         keep temporary build directory
USAGE
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --version)
            version="$2"
            shift 2
            ;;
        --out-dir)
            out_dir="$2"
            shift 2
            ;;
        --pvr-dir)
            pvr_dir="$2"
            shift 2
            ;;
        --knulli-src)
            knulli_src="$2"
            shift 2
            ;;
        --source-cache)
            source_cache="$2"
            shift 2
            ;;
        --keep-work)
            keep_work=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf 'error: unknown argument: %s\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [ "$(uname -s)" != "Linux" ]; then
    printf 'error: this script builds Linux arm64 binaries; run it through scripts/docker-build.sh sdl2-powervr\n' >&2
    exit 1
fi

arch="$(dpkg --print-architecture 2>/dev/null || uname -m)"
case "$arch" in
    arm64|aarch64)
        ;;
    *)
        printf 'error: this script expects an arm64/aarch64 Linux build container, got: %s\n' "$arch" >&2
        exit 1
        ;;
esac

for tool in curl tar patch make gcc pkg-config; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        printf 'error: %s is required\n' "$tool" >&2
        exit 1
    fi
done

patch_path="$knulli_src/board/allwinner/a133/powkiddy-v90s/patches/sdl2/001-add-pvr-ge8300-mali-driver.patch"
if [ ! -f "$patch_path" ]; then
    printf 'error: KNULLI V90S SDL2 patch not found: %s\n' "$patch_path" >&2
    exit 1
fi

if [ ! -d "$pvr_dir/3rdparty/include/khronos/EGL" ] || [ ! -f "$pvr_dir/fbdev/glibc/lib64/libEGL.so" ]; then
    printf 'error: GE8300 headers/libs not found under: %s\n' "$pvr_dir" >&2
    exit 1
fi

mkdir -p "$source_cache" "$out_dir"
tarball="$source_cache/SDL2-${version}.tar.gz"
if [ ! -f "$tarball" ]; then
    curl -L --fail -o "$tarball" "https://github.com/libsdl-org/SDL/releases/download/release-${version}/SDL2-${version}.tar.gz"
fi

work_dir="${TMPDIR:-/tmp}/plumos-v90s-sdl2-powervr.$$"
rm -rf "$work_dir"
mkdir -p "$work_dir"

cleanup() {
    if [ "$keep_work" -eq 0 ]; then
        rm -rf "$work_dir"
    else
        printf 'kept work directory: %s\n' "$work_dir"
    fi
}
trap cleanup EXIT INT TERM

tar -C "$work_dir" -xf "$tarball"
src="$work_dir/SDL2-${version}"
filtered_patch="$work_dir/sdl2-powervr-filtered.patch"

# The KNULLI patch carries a generated include/SDL_config.h hunk.  Configure
# regenerates that file for this build, so skip only that brittle section.
awk '
    /^diff .*include\/SDL_config\.h[[:space:]]/ { skip = 1; next }
    /^diff / { skip = 0 }
    !skip { print }
' "$patch_path" > "$filtered_patch"

(
    cd "$src"
    patch -p1 < "$filtered_patch"

    export CPPFLAGS="-I$repo_root/$pvr_dir/3rdparty/include/khronos"
    export LDFLAGS="-L$repo_root/$pvr_dir/fbdev/glibc/lib64 -Wl,-rpath,/usr/lib/powervr"
    export LIBS="-lEGL -lGLESv2"

    ./configure \
        --prefix=/usr \
        --enable-shared \
        --disable-static \
        --enable-video \
        --enable-video-mali \
        --disable-video-x11 \
        --disable-video-wayland \
        --disable-video-kmsdrm \
        --disable-video-vivante \
        --disable-video-vulkan \
        --disable-video-opengl \
        --enable-video-opengles \
        --disable-hidapi

    jobs="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)"
    make -j"$jobs"
    make DESTDIR="$work_dir/stage" install
)

rm -rf "$out_dir"
mkdir -p \
    "$out_dir/usr/local/lib/plumos-sdl2-powervr" \
    "$out_dir/usr/local/include" \
    "$out_dir/usr/local/bin"
cp -a "$work_dir/stage/usr/lib/libSDL2-2.0.so"* "$out_dir/usr/local/lib/plumos-sdl2-powervr/"
cp -a "$work_dir/stage/usr/lib/libSDL2.so" "$out_dir/usr/local/lib/plumos-sdl2-powervr/"
cp -a "$work_dir/stage/usr/include/SDL2" "$out_dir/usr/local/include/"

gcc \
    -I"$work_dir/stage/usr/include/SDL2" \
    -D_REENTRANT \
    "$script_dir/v90s-sdl2-video-probe.c" \
    -L"$work_dir/stage/usr/lib" \
    -Wl,-rpath,/usr/local/lib/plumos-sdl2-powervr \
    -lSDL2 \
    -o "$out_dir/usr/local/bin/v90s-sdl2-video-probe"

strip --strip-unneeded "$out_dir/usr/local/lib/plumos-sdl2-powervr/libSDL2-2.0.so.0.3000.6" 2>/dev/null || true
strip --strip-unneeded "$out_dir/usr/local/bin/v90s-sdl2-video-probe" 2>/dev/null || true

{
    printf 'sdl2_version=%s\n' "$version"
    printf 'patch=%s\n' "$patch_path"
    printf 'pvr_dir=%s\n' "$pvr_dir"
    printf 'built_arch=%s\n' "$arch"
    printf 'video_drivers='
    strings "$out_dir/usr/local/lib/plumos-sdl2-powervr/libSDL2-2.0.so.0" | grep -E '^(mali|x11|wayland|kmsdrm|dummy|offscreen)$' | sort -u | tr '\n' ' '
    printf '\n'
} > "$out_dir/manifest.txt"

find "$out_dir" -type f ! -name SHA256SUMS -print | sort | xargs sha256sum > "$out_dir/SHA256SUMS"

printf 'created: %s\n' "$out_dir"
cat "$out_dir/manifest.txt"
