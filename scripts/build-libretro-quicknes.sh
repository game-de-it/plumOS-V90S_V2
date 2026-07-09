#!/usr/bin/env sh
set -eu

version="058d66516ed3f1260b69e5b71cd454eb7e9234a3"
out_dir="output/libretro-quicknes"
work_dir="output/build/quicknes-${version}"
docker_image="${PLUMOS_V90S_QUICKNES_DOCKER_IMAGE:-debian:bookworm}"

usage() {
    cat <<'USAGE'
Usage:
  build-libretro-quicknes.sh [options]

Options:
  --version COMMIT   QuickNES_Core commit; defaults to KNULLI's pinned commit
  --out-dir PATH     output directory; default output/libretro-quicknes
  --work-dir PATH    source/build directory; default output/build/quicknes-COMMIT
USAGE
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

if ! command -v docker >/dev/null 2>&1; then
    printf 'error: docker is required\n' >&2
    exit 1
fi

mkdir -p "$(dirname "$work_dir")" "$out_dir"
if [ ! -d "$work_dir/.git" ]; then
    rm -rf "$work_dir"
    git clone https://github.com/libretro/QuickNES_Core.git "$work_dir"
fi

git -C "$work_dir" fetch --tags --quiet origin
git -C "$work_dir" checkout --quiet "$version"

docker run --rm \
    -v "$(CDPATH= cd -- "$work_dir" && pwd):/src" \
    -w /src \
    "$docker_image" \
    sh -c 'set -eu; apt-get update >/dev/null; DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends build-essential ca-certificates make g++ >/dev/null; make -j"$(nproc)" -f Makefile platform=unix GIT_VERSION=-'"$(printf '%s' "$version" | cut -c 1-7)"''

install -m 0644 "$work_dir/quicknes_libretro.so" "$out_dir/quicknes_libretro.so"
sha256sum "$out_dir/quicknes_libretro.so" > "$out_dir/quicknes_libretro.so.sha256"
cat > "$out_dir/quicknes-manifest.txt" <<EOF
source=https://github.com/libretro/QuickNES_Core.git
version=$version
platform=unix
output=$out_dir/quicknes_libretro.so
sha256=$(awk '{print $1}' "$out_dir/quicknes_libretro.so.sha256")
EOF

printf 'created: %s/quicknes_libretro.so\n' "$out_dir"
