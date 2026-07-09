#!/usr/bin/env bash
set -euo pipefail

version="${PLUMOS_V90S_QUICKNES_REF:-058d66516ed3f1260b69e5b71cd454eb7e9234a3}"
out_dir="${PLUMOS_V90S_QUICKNES_OUT:-output/libretro-quicknes}"
work_dir="${PLUMOS_V90S_QUICKNES_WORK:-output/build/quicknes-${version}}"

usage() {
    cat <<'EOF'
Usage:
  docker/plumos-v90s-toolchain/scripts/build-libretro-quicknes.sh [options]

Options:
  --version COMMIT   QuickNES_Core commit; default is the current V90S pin.
  --out-dir PATH     Output directory; default output/libretro-quicknes.
  --work-dir PATH    Source/build directory; default output/build/quicknes-COMMIT.
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --version)
            version="$2"
            work_dir="output/build/quicknes-${version}"
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

mkdir -p "$(dirname "$work_dir")" "$out_dir"
if [ ! -d "$work_dir/.git" ]; then
    rm -rf "$work_dir"
    git clone https://github.com/libretro/QuickNES_Core.git "$work_dir"
fi

git -C "$work_dir" fetch --tags --quiet origin
git -C "$work_dir" checkout --quiet "$version"
git -C "$work_dir" clean -fdx --quiet

make -C "$work_dir" -j"$(nproc)" -f Makefile platform=unix GIT_VERSION=-"$(printf '%s' "$version" | cut -c 1-7)"

install -m 0644 "$work_dir/quicknes_libretro.so" "$out_dir/quicknes_libretro.so"
sha256sum "$out_dir/quicknes_libretro.so" > "$out_dir/quicknes_libretro.so.sha256"
cat > "$out_dir/quicknes-manifest.txt" <<EOF
source=https://github.com/libretro/QuickNES_Core.git
version=$version
platform=unix
builder=plumos-v90s-toolchain
output=$out_dir/quicknes_libretro.so
sha256=$(awk '{print $1}' "$out_dir/quicknes_libretro.so.sha256")
EOF

printf 'created: %s/quicknes_libretro.so\n' "$out_dir"
