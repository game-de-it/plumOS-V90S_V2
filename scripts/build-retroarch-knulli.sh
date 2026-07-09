#!/usr/bin/env sh
set -eu

version="v1.22.2"
out_dir="output/retroarch-knulli"
work_dir="output/build/retroarch-${version}"
knulli_src=".cache/knulli-linux"
pvr_dir=".cache/ge8300-drivers"
sdl2_mali_dir="output/sdl2-mali"
docker_image="${PLUMOS_V90S_RETROARCH_DOCKER_IMAGE:-debian:bookworm}"
apply_patches=0

usage() {
    cat <<'USAGE'
Usage:
  build-retroarch-knulli.sh [options]

Options:
  --version TAG          RetroArch tag; default v1.22.2 from KNULLI
  --out-dir PATH        output directory; default output/retroarch-knulli
  --work-dir PATH       source/build directory; default output/build/retroarch-TAG
  --knulli-src PATH     KNULLI source checkout; default .cache/knulli-linux
  --pvr-dir PATH        GE8300 driver checkout; default .cache/ge8300-drivers
  --sdl2-mali-dir PATH  patched SDL2 payload; default output/sdl2-mali
  --apply-patches       also replay KNULLI package patches before building
  --skip-patches        accepted for compatibility; this is the default
USAGE
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --version)
            version="$2"
            work_dir="output/build/retroarch-${version}"
            shift 2
            ;;
        --out-dir)
            out_dir="$2"
            shift 2
            ;;
        --work-dir)
            work_dir="$2"
            shift 2
            ;;
        --knulli-src)
            knulli_src="$2"
            shift 2
            ;;
        --pvr-dir)
            pvr_dir="$2"
            shift 2
            ;;
        --sdl2-mali-dir)
            sdl2_mali_dir="$2"
            shift 2
            ;;
        --skip-patches)
            apply_patches=0
            shift
            ;;
        --apply-patches)
            apply_patches=1
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

if ! command -v docker >/dev/null 2>&1; then
    printf 'error: docker is required\n' >&2
    exit 1
fi

patch_dir="$knulli_src/package/retroarch/retroarch"
pvr_lib_dir="$pvr_dir/fbdev/glibc/lib64"
sdl2_lib_dir="$sdl2_mali_dir/usr/local/lib/plumos-sdl2-mali"

if [ ! -d "$patch_dir" ]; then
    printf 'error: KNULLI RetroArch package directory not found: %s\n' "$patch_dir" >&2
    printf 'hint: run ./scripts/fetch-reference-sources.sh first\n' >&2
    exit 1
fi
if [ ! -f "$pvr_lib_dir/libEGL.so" ] || [ ! -f "$pvr_lib_dir/libGLESv2.so" ]; then
    printf 'error: GE8300 fbdev/glibc EGL/GLES libraries not found under: %s\n' "$pvr_lib_dir" >&2
    exit 1
fi
if [ ! -f "$sdl2_lib_dir/libSDL2-2.0.so.0" ]; then
    printf 'error: patched SDL2 mali library not found under: %s\n' "$sdl2_lib_dir" >&2
    printf 'hint: run ./scripts/run-assembly-tools.sh ./scripts/build-sdl2-mali.sh first\n' >&2
    exit 1
fi

mkdir -p "$(dirname "$work_dir")" "$out_dir"
if [ ! -d "$work_dir/.git" ]; then
    rm -rf "$work_dir"
    git clone https://github.com/libretro/RetroArch.git "$work_dir"
fi

git -C "$work_dir" fetch --tags --quiet origin
git -C "$work_dir" reset --hard --quiet "$version"
git -C "$work_dir" clean -fdx --quiet

applied_patches_file="$work_dir/.plumos-applied-patches.txt"
: > "$applied_patches_file"
if [ "$apply_patches" -eq 1 ]; then
    for patch in "$patch_dir"/[0-9][0-9][0-9]-*.patch "$patch_dir"/[0-9][0-9]-*.patch; do
        [ -f "$patch" ] || continue
        printf 'applying patch: %s\n' "$patch"
        git -C "$work_dir" apply --whitespace=nowarn "$(CDPATH= cd -- "$(dirname -- "$patch")" && pwd)/$(basename -- "$patch")"
        printf '%s\n' "$(basename -- "$patch")" >> "$applied_patches_file"
    done
fi

work_abs="$(CDPATH= cd -- "$work_dir" && pwd)"
pvr_abs="$(CDPATH= cd -- "$pvr_lib_dir" && pwd)"
sdl2_abs="$(CDPATH= cd -- "$sdl2_lib_dir" && pwd)"

docker run --rm --platform linux/arm64 \
    -v "$work_abs:/src" \
    -v "$pvr_abs:/pvr:ro" \
    -v "$sdl2_abs:/sdl2:ro" \
    -w /src \
    "$docker_image" \
    sh -c '
        set -eu
        export DEBIAN_FRONTEND=noninteractive
        printf "%s\n" "Acquire::Retries \"3\";" > /etc/apt/apt.conf.d/80-plumos-retries
        rm -rf /var/lib/apt/lists/*
        apt-get update >/dev/null
        apt-get install -y --no-install-recommends \
            build-essential ca-certificates file git make pkg-config \
            libasound2-dev libegl-dev libfreetype6-dev libgles-dev \
            libsdl2-dev libudev-dev zlib1g-dev >/dev/null

        export CPPFLAGS="-DEGL_API_FB -DLINUX"
        export CFLAGS="-O2 -pipe -fPIC ${CPPFLAGS}"
        export CXXFLAGS="${CFLAGS}"
        export LDFLAGS="-L/pvr -L/sdl2 -Wl,-rpath-link,/pvr -Wl,-rpath,/usr/lib/powervr -Wl,-rpath,/usr/local/lib/plumos-sdl2-mali"
        export LIBS="-lIMGegl -lsrv_um -lglslcompiler -lusc"
        export PKG_CONFIG_PATH="/usr/lib/aarch64-linux-gnu/pkgconfig:/usr/lib/pkgconfig:/usr/share/pkgconfig"

        ./configure \
            --prefix=/usr \
            --disable-oss \
            --enable-zlib \
            --disable-qt \
            --enable-threads \
            --enable-rgui \
            --enable-sdl2 \
            --disable-sdl \
            --disable-videocore \
            --disable-kms \
            --disable-x11 \
            --enable-alsa \
            --disable-pulse \
            --enable-opengles \
            --enable-opengles3 \
            --enable-opengles3_1 \
            --enable-egl \
            --disable-wayland \
            --disable-vulkan \
            --enable-freetype \
            --disable-ffmpeg \
            --disable-discord \
            --disable-cdrom \
            --enable-mali_fbdev

        make -j"$(nproc)"
        rm -rf .stage
        make DESTDIR=/src/.stage install
        file .stage/usr/bin/retroarch
    '

mkdir -p "$out_dir/usr/local/bin"
install -m 0755 "$work_dir/.stage/usr/bin/retroarch" "$out_dir/usr/local/bin/retroarch-knulli"
if [ -d "$work_dir/.stage/usr/share/retroarch" ]; then
    mkdir -p "$out_dir/usr/local/share"
    rm -rf "$out_dir/usr/local/share/retroarch"
    cp -a "$work_dir/.stage/usr/share/retroarch" "$out_dir/usr/local/share/retroarch"
fi

sha256sum "$out_dir/usr/local/bin/retroarch-knulli" > "$out_dir/retroarch-knulli.sha256"
cat > "$out_dir/manifest.txt" <<EOF
source=https://github.com/libretro/RetroArch.git
version=$version
knulli_patch_dir=$patch_dir
patches=$([ "$apply_patches" -eq 1 ] && tr '\n' ' ' < "$applied_patches_file" || printf none)
pvr_lib_dir=$pvr_lib_dir
sdl2_mali_dir=$sdl2_mali_dir
configure=--enable-mali_fbdev --enable-egl --enable-opengles --enable-opengles3 --enable-sdl2 --enable-alsa --disable-x11 --disable-wayland --disable-kms
output=$out_dir/usr/local/bin/retroarch-knulli
sha256=$(awk '{print $1}' "$out_dir/retroarch-knulli.sha256")
EOF

printf 'created: %s/usr/local/bin/retroarch-knulli\n' "$out_dir"
