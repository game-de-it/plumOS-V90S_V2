#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-/workspace}"
OUT_DIR="${PLUMOS_V90S_PORTMASTER_OUT:-${ROOT_DIR}/output/portmaster/v90s}"
BUILD_DIR="${PLUMOS_V90S_PORTMASTER_BUILD_DIR:-${ROOT_DIR}/build/portmaster}"
CACHE_DIR="${PLUMOS_V90S_PORTMASTER_CACHE_DIR:-${ROOT_DIR}/.cache/portmaster}"
PACKAGE_DIR="${ROOT_DIR}/package/portmaster-v90s"
VERSION="${PORTMASTER_VERSION:-2026.06.23-0015}"
ARCHIVE="PortMaster-${VERSION}.zip"
URL="${PORTMASTER_URL:-https://github.com/PortsMaster/PortMaster-GUI/releases/download/${VERSION}/PortMaster.zip}"
EXPECTED_MD5="${PORTMASTER_MD5:-41d137e6bb123c755806939831bcce2f}"
EXPECTED_SHA256="${PORTMASTER_SHA256:-772f2d56fc1abfbf79a3404ca78f240776c81c5a5b92786a0a748ae554339b7b}"
OPENAL_VERSION="1.23.1"
OPENAL_COMMIT="d3875f333fb6abe2f39d82caca329414871ae53b"
OPENAL_ARCHIVE="openal-soft-${OPENAL_VERSION}.tar.gz"
OPENAL_URL="https://github.com/kcat/openal-soft/archive/refs/tags/${OPENAL_VERSION}.tar.gz"
OPENAL_SHA256="dfddf3a1f61059853c625b7bb03de8433b455f2f79f89548cbcbd5edca3d4a4a"
SQUASHFS_TOOLS_VERSION="1:4.5.1-1"

usage() {
    cat <<EOF
Usage: build-portmaster.sh

Builds the plumOS V90S PortMaster package from a pinned official release.

Environment:
  PLUMOS_V90S_PORTMASTER_OUT       Output directory; default output/portmaster/v90s.
  PORTMASTER_VERSION               Official release version; default ${VERSION}.
  PORTMASTER_URL                   Official archive URL.
  PORTMASTER_MD5                   Expected official MD5.
  PORTMASTER_SHA256                Independently pinned SHA-256.
EOF
}

case "${1:-}" in
    -h|--help|help)
        usage
        exit 0
        ;;
    "") ;;
    *)
        printf 'error: unknown argument: %s\n' "$1" >&2
        usage >&2
        exit 2
        ;;
esac

for tool in cmake curl dpkg-query md5sum ninja sha256sum tar unzip python3 rsync; do
    command -v "$tool" >/dev/null 2>&1 || {
        printf 'error: required tool is unavailable: %s\n' "$tool" >&2
        exit 1
    }
done

actual_squashfs_tools_version="$(dpkg-query -W -f='${Version}' squashfs-tools)"
[ "$actual_squashfs_tools_version" = "$SQUASHFS_TOOLS_VERSION" ] || {
    printf 'error: squashfs-tools version mismatch: expected %s, got %s\n' \
        "$SQUASHFS_TOOLS_VERSION" "$actual_squashfs_tools_version" >&2
    exit 1
}
[ -x /usr/bin/unsquashfs ] || {
    printf 'error: /usr/bin/unsquashfs is unavailable\n' >&2
    exit 1
}
lzo_library="$(find /usr/lib/aarch64-linux-gnu -type f -name 'liblzo2.so.*' | sort | tail -n 1)"
[ -n "$lzo_library" ] && [ -f "$lzo_library" ] || {
    printf 'error: liblzo2 runtime dependency is unavailable\n' >&2
    exit 1
}

mkdir -p "$CACHE_DIR" "$BUILD_DIR"
archive_path="$CACHE_DIR/$ARCHIVE"

if [ ! -f "$archive_path" ] ||
   [ "$(sha256sum "$archive_path" | awk '{print $1}')" != "$EXPECTED_SHA256" ]; then
    archive_tmp="$archive_path.tmp.$$"
    rm -f "$archive_tmp"
    curl --fail --location --retry 3 --output "$archive_tmp" "$URL"
    mv -f "$archive_tmp" "$archive_path"
fi

actual_md5="$(md5sum "$archive_path" | awk '{print $1}')"
actual_sha256="$(sha256sum "$archive_path" | awk '{print $1}')"
[ "$actual_md5" = "$EXPECTED_MD5" ] || {
    printf 'error: PortMaster MD5 mismatch: expected %s, got %s\n' \
        "$EXPECTED_MD5" "$actual_md5" >&2
    exit 1
}
[ "$actual_sha256" = "$EXPECTED_SHA256" ] || {
    printf 'error: PortMaster SHA-256 mismatch: expected %s, got %s\n' \
        "$EXPECTED_SHA256" "$actual_sha256" >&2
    exit 1
}

openal_archive_path="$CACHE_DIR/$OPENAL_ARCHIVE"
if [ ! -f "$openal_archive_path" ] ||
   [ "$(sha256sum "$openal_archive_path" | awk '{print $1}')" != "$OPENAL_SHA256" ]; then
    openal_archive_tmp="$openal_archive_path.tmp.$$"
    rm -f "$openal_archive_tmp"
    curl --fail --location --retry 3 --output "$openal_archive_tmp" "$OPENAL_URL"
    mv -f "$openal_archive_tmp" "$openal_archive_path"
fi

actual_openal_sha256="$(sha256sum "$openal_archive_path" | awk '{print $1}')"
[ "$actual_openal_sha256" = "$OPENAL_SHA256" ] || {
    printf 'error: OpenAL Soft SHA-256 mismatch: expected %s, got %s\n' \
        "$OPENAL_SHA256" "$actual_openal_sha256" >&2
    exit 1
}

openal_src="$BUILD_DIR/openal-soft-src"
openal_build="$BUILD_DIR/openal-soft-build"
rm -rf "$openal_src" "$openal_build"
mkdir -p "$openal_src" "$openal_build"
tar -xzf "$openal_archive_path" --strip-components=1 -C "$openal_src"
cmake -S "$openal_src" -B "$openal_build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DALSOFT_BACKEND_ALSA=ON \
    -DALSOFT_REQUIRE_ALSA=ON \
    -DALSOFT_BACKEND_PIPEWIRE=OFF \
    -DALSOFT_BACKEND_PULSEAUDIO=OFF \
    -DALSOFT_BACKEND_JACK=OFF \
    -DALSOFT_BACKEND_OSS=OFF \
    -DALSOFT_BACKEND_SNDIO=OFF \
    -DALSOFT_BACKEND_PORTAUDIO=OFF \
    -DALSOFT_BACKEND_SDL2=OFF \
    -DALSOFT_BACKEND_SDL3=OFF \
    -DALSOFT_BACKEND_WAVE=OFF \
    -DALSOFT_DLOPEN=OFF \
    -DALSOFT_EMBED_HRTF_DATA=OFF \
    -DALSOFT_UTILS=OFF \
    -DALSOFT_NO_CONFIG_UTIL=ON \
    -DALSOFT_EXAMPLES=OFF \
    -DALSOFT_TESTS=OFF \
    -DALSOFT_INSTALL=OFF
cmake --build "$openal_build" --parallel "${JOBS:-2}" --target OpenAL
openal_library="$(find "$openal_build" -type f -name 'libopenal.so.*' | sort | tail -n 1)"
[ -n "$openal_library" ] && [ -f "$openal_library" ] || {
    printf 'error: OpenAL Soft shared library was not produced\n' >&2
    exit 1
}

python3 - "$archive_path" <<'PY'
import stat
import sys
import zipfile
from pathlib import PurePosixPath

archive = sys.argv[1]
required = {
    "PortMaster/pugwash",
    "PortMaster/pylibs.zip",
    "PortMaster/control.txt",
    "PortMaster/device_info.txt",
    "PortMaster/funcs.txt",
    "PortMaster/gptokeyb",
    "PortMaster/gptokeyb2",
    "PortMaster/version",
}

with zipfile.ZipFile(archive) as zf:
    names = set()
    for entry in zf.infolist():
        path = PurePosixPath(entry.filename)
        if path.is_absolute() or ".." in path.parts:
            raise SystemExit(f"unsafe archive path: {entry.filename}")
        mode = entry.external_attr >> 16
        if stat.S_ISLNK(mode):
            raise SystemExit(f"symlink is not allowed in release archive: {entry.filename}")
        names.add(entry.filename.rstrip("/"))

missing = sorted(required - names)
if missing:
    raise SystemExit("missing required release files: " + ", ".join(missing))
PY

stage_dir="$BUILD_DIR/stage.$$"
rm -rf "$stage_dir"
mkdir -p "$stage_dir/plumos/apps/portmaster/upstream"
unzip -q "$archive_path" -d "$stage_dir/plumos/apps/portmaster/upstream"

release_version="$(tr -d '\r\n' < "$stage_dir/plumos/apps/portmaster/upstream/PortMaster/version")"
[ "$release_version" = "$VERSION" ] || {
    printf 'error: archive version mismatch: expected %s, got %s\n' \
        "$VERSION" "$release_version" >&2
    rm -rf "$stage_dir"
    exit 1
}

chmod 0755 \
    "$stage_dir/plumos/apps/portmaster/upstream/PortMaster/gptokeyb" \
    "$stage_dir/plumos/apps/portmaster/upstream/PortMaster/gptokeyb2"

rsync -a --copy-links --exclude='__pycache__/' --exclude='*.pyc' \
    "$PACKAGE_DIR/plumos/" "$stage_dir/plumos/"
mkdir -p \
    "$stage_dir/plumos/apps/portmaster/adapter/bin/aarch64" \
    "$stage_dir/plumos/apps/portmaster/adapter/lib/aarch64" \
    "$stage_dir/plumos/licenses"
install -m 0755 /usr/bin/unsquashfs \
    "$stage_dir/plumos/apps/portmaster/adapter/bin/aarch64/unsquashfs"
install -m 0644 "$openal_library" \
    "$stage_dir/plumos/apps/portmaster/adapter/lib/aarch64/libopenal.so.1"
install -m 0644 "$lzo_library" \
    "$stage_dir/plumos/apps/portmaster/adapter/lib/aarch64/liblzo2.so.2"
install -m 0644 "$openal_src/COPYING" \
    "$stage_dir/plumos/licenses/openal-soft-LGPL-2.0-or-later.txt"
install -m 0644 /usr/share/doc/squashfs-tools/copyright \
    "$stage_dir/plumos/licenses/squashfs-tools-copyright.txt"
install -m 0644 /usr/share/doc/liblzo2-2/copyright \
    "$stage_dir/plumos/licenses/liblzo2-copyright.txt"
mkdir -p \
    "$stage_dir/plumos/state/portmaster/config" \
    "$stage_dir/plumos/state/portmaster/libs" \
    "$stage_dir/plumos/state/portmaster/themes" \
    "$stage_dir/plumos/state/portmaster/home" \
    "$stage_dir/plumos/Logs/apps"

cat > "$stage_dir/plumos/apps/portmaster/installed.json" <<EOF
{
  "adapter_version": 6,
  "channel": "stable",
  "official_md5": "${actual_md5}",
  "official_sha256": "${actual_sha256}",
  "source_url": "${URL}",
  "version": "${VERSION}"
}
EOF

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"
rsync -a "$stage_dir/plumos/" "$OUT_DIR/plumos/"

cat > "$OUT_DIR/portmaster.manifest" <<EOF
component=portmaster
target=powkiddy-v90s
adapter_version=6
upstream=PortMaster-GUI
version=${VERSION}
channel=stable
url=${URL}
md5=${actual_md5}
sha256=${actual_sha256}
update_policy=plumos-staged-switch
openal_soft_version=${OPENAL_VERSION}
openal_soft_commit=${OPENAL_COMMIT}
openal_soft_sha256=${actual_openal_sha256}
squashfs_tools_version=${actual_squashfs_tools_version}
unsquashfs_sha256=$(sha256sum /usr/bin/unsquashfs | awk '{print $1}')
EOF

find "$OUT_DIR" -type f ! -name checksums.sha256 -print0 | sort -z | \
    xargs -0 sha256sum | sed "s#  $OUT_DIR/#  #" > "$OUT_DIR/checksums.sha256"

rm -rf "$stage_dir"
printf 'created: %s\n' "$OUT_DIR"
printf 'PortMaster: %s (%s)\n' "$VERSION" "$actual_sha256"
