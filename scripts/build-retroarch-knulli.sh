#!/usr/bin/env sh
set -eu

version="v1.22.2"
out_dir="${PLUMOS_V90S_RETROARCH_OUT:-output/retroarch-knulli}"
work_dir="output/build/retroarch-${version}"
knulli_src=".cache/knulli-linux"
pvr_dir=".cache/ge8300-drivers"
sdl2_powervr_dir="output/sdl2-powervr"
local_patch_dir="patches/retroarch"
factory_config="${PLUMOS_V90S_RETROARCH_FACTORY_CONFIG:-package/frontend-v90s/plumos/factory-defaults/ra/config/retroarch/retroarch-v90s.cfg}"
docker_image="${PLUMOS_V90S_RETROARCH_DOCKER_IMAGE:-debian:bookworm}"
binary_name="${PLUMOS_V90S_RETROARCH_BIN_NAME:-retroarch-knulli}"
compat_out="${PLUMOS_V90S_RETROARCH_COMPAT_OUT:-}"
apply_patches=0

usage() {
    cat <<'USAGE'
Usage:
  build-retroarch-knulli.sh [options]

Options:
  --version TAG          RetroArch tag; default v1.22.2 from KNULLI
  --out-dir PATH        output directory; default output/retroarch-knulli
  --work-dir PATH       source/build directory; default output/build/retroarch-TAG
  --binary-name NAME    installed binary name; default retroarch-knulli
  --compat-out PATH     optional compatibility output symlink path
  --knulli-src PATH     KNULLI source checkout; default .cache/knulli-linux
  --pvr-dir PATH        GE8300 driver checkout; default .cache/ge8300-drivers
  --sdl2-powervr-dir PATH
                        patched SDL2/PowerVR payload; default output/sdl2-powervr
  --sdl2-mali-dir PATH  deprecated alias for --sdl2-powervr-dir
  --local-patch-dir PATH
                        local RetroArch patches; default patches/retroarch
  --factory-config PATH V90S factory RetroArch config bundled with the build;
                        default package/frontend-v90s/plumos/factory-defaults/
                        ra/config/retroarch/retroarch-v90s.cfg
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
        --binary-name)
            binary_name="$2"
            shift 2
            ;;
        --compat-out)
            compat_out="$2"
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
        --sdl2-powervr-dir|--sdl2-mali-dir)
            sdl2_powervr_dir="$2"
            shift 2
            ;;
        --local-patch-dir)
            local_patch_dir="$2"
            shift 2
            ;;
        --factory-config)
            factory_config="$2"
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

if [ "${PLUMOS_V90S_BUILD_IN_CONTAINER:-0}" != "1" ] && ! command -v docker >/dev/null 2>&1; then
    printf 'error: docker is required\n' >&2
    exit 1
fi

patch_dir="$knulli_src/package/retroarch/retroarch"
pvr_lib_dir="$pvr_dir/fbdev/glibc/lib64"
sdl2_lib_dir="$sdl2_powervr_dir/usr/local/lib/plumos-sdl2-powervr"

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
    printf 'error: patched SDL2/PowerVR library not found under: %s\n' "$sdl2_lib_dir" >&2
    printf 'hint: run ./scripts/docker-build.sh sdl2-powervr first\n' >&2
    exit 1
fi
if [ ! -f "$factory_config" ]; then
    printf 'error: V90S RetroArch factory config not found: %s\n' "$factory_config" >&2
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
applied_local_patches_file="$work_dir/.plumos-applied-local-patches.txt"
: > "$applied_patches_file"
: > "$applied_local_patches_file"
if [ "$apply_patches" -eq 1 ]; then
    for patch in "$patch_dir"/[0-9][0-9][0-9]-*.patch "$patch_dir"/[0-9][0-9]-*.patch; do
        [ -f "$patch" ] || continue
        printf 'applying patch: %s\n' "$patch"
        git -C "$work_dir" apply --whitespace=nowarn "$(CDPATH= cd -- "$(dirname -- "$patch")" && pwd)/$(basename -- "$patch")"
        printf '%s\n' "$(basename -- "$patch")" >> "$applied_patches_file"
    done
fi
for patch in "$local_patch_dir"/*.patch; do
    [ -f "$patch" ] || continue
    printf 'applying local patch: %s\n' "$patch"
    git -C "$work_dir" apply --whitespace=nowarn "$(CDPATH= cd -- "$(dirname -- "$patch")" && pwd)/$(basename -- "$patch")"
    printf '%s\n' "$(basename -- "$patch")" >> "$applied_local_patches_file"
done

work_abs="$(CDPATH= cd -- "$work_dir" && pwd)"
pvr_abs="$(CDPATH= cd -- "$pvr_lib_dir" && pwd)"
sdl2_abs="$(CDPATH= cd -- "$sdl2_lib_dir" && pwd)"

if [ "${PLUMOS_V90S_BUILD_IN_CONTAINER:-0}" = "1" ]; then
    (
        cd "$work_abs"
        set -eu
        export CPPFLAGS="-DEGL_API_FB -DLINUX"
        export CFLAGS="-O2 -pipe -fPIC ${CPPFLAGS}"
        export CXXFLAGS="${CFLAGS}"
        export LDFLAGS="-L$pvr_abs -L$sdl2_abs -Wl,-rpath-link,$pvr_abs -Wl,-rpath,/usr/lib/powervr -Wl,-rpath,/usr/local/lib/plumos-sdl2-powervr"
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
            --disable-pipewire \
            --disable-jack \
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
        make DESTDIR="$work_abs/.stage" install
        file .stage/usr/bin/retroarch
    )
else
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
            export LDFLAGS="-L/pvr -L/sdl2 -Wl,-rpath-link,/pvr -Wl,-rpath,/usr/lib/powervr -Wl,-rpath,/usr/local/lib/plumos-sdl2-powervr"
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
                --disable-pipewire \
                --disable-jack \
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
fi

mkdir -p "$out_dir/usr/local/bin"
install -m 0755 "$work_dir/.stage/usr/bin/retroarch" "$out_dir/usr/local/bin/$binary_name"
mkdir -p "$out_dir/licenses"
install -m 0644 "$work_dir/COPYING" "$out_dir/licenses/RetroArch-COPYING"
if [ "$binary_name" != "retroarch-knulli" ]; then
    ln -sfn "$binary_name" "$out_dir/usr/local/bin/retroarch-knulli"
fi
if [ -d "$work_dir/.stage/usr/share/retroarch" ]; then
    mkdir -p "$out_dir/usr/local/share"
    rm -rf "$out_dir/usr/local/share/retroarch"
    cp -a "$work_dir/.stage/usr/share/retroarch" "$out_dir/usr/local/share/retroarch"
fi

factory_config_rel="plumos/factory-defaults/ra/config/retroarch/retroarch-v90s.cfg"
factory_config_out="$out_dir/$factory_config_rel"
mkdir -p "$(dirname "$factory_config_out")"
install -m 0644 "$factory_config" "$factory_config_out"

sha256sum "$out_dir/usr/local/bin/$binary_name" > "$out_dir/$binary_name.sha256"
if [ "$binary_name" != "retroarch-knulli" ]; then
    sha256sum "$out_dir/usr/local/bin/retroarch-knulli" > "$out_dir/retroarch-knulli.sha256"
fi
sha256sum "$factory_config_out" > "$out_dir/retroarch-v90s-factory.cfg.sha256"

compat_note=none
if [ -n "$compat_out" ] && [ "$compat_out" != "$out_dir" ]; then
    if [ -L "$compat_out" ]; then
        rm -f "$compat_out"
    fi
    if [ -e "$compat_out" ]; then
        compat_note="skipped-existing:$compat_out"
        printf 'warning: compatibility output path already exists, not replacing: %s\n' "$compat_out" >&2
    else
        mkdir -p "$(dirname "$compat_out")"
        out_parent="$(dirname "$out_dir")"
        compat_parent="$(dirname "$compat_out")"
        if [ "$out_parent" = "$compat_parent" ]; then
            compat_target="$(basename "$out_dir")"
        else
            compat_target="$(CDPATH= cd -- "$out_dir" && pwd)"
        fi
        ln -s "$compat_target" "$compat_out"
        compat_note="$compat_out->$compat_target"
    fi
fi

cat > "$out_dir/manifest.txt" <<EOF
source=https://github.com/libretro/RetroArch.git
version=$version
knulli_patch_dir=$patch_dir
patches=$([ "$apply_patches" -eq 1 ] && tr '\n' ' ' < "$applied_patches_file" || printf none)
local_patch_dir=$local_patch_dir
local_patches=$([ -s "$applied_local_patches_file" ] && tr '\n' ' ' < "$applied_local_patches_file" || printf none)
pvr_lib_dir=$pvr_lib_dir
sdl2_powervr_dir=$sdl2_powervr_dir
configure=--enable-mali_fbdev --enable-egl --enable-opengles --enable-opengles3 --enable-sdl2 --enable-alsa --disable-x11 --disable-wayland --disable-kms
binary_name=$binary_name
compat_binary=retroarch-knulli
compat_output=$compat_note
output=$out_dir/usr/local/bin/$binary_name
sha256=$(awk '{print $1}' "$out_dir/$binary_name.sha256")
factory_config_source=$factory_config
factory_config_output=$factory_config_rel
factory_config_sha256=$(awk '{print $1}' "$out_dir/retroarch-v90s-factory.cfg.sha256")
license=licenses/RetroArch-COPYING
EOF

printf 'created: %s/usr/local/bin/%s\n' "$out_dir" "$binary_name"
