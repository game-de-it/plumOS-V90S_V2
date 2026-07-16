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

for tool in curl md5sum sha256sum unzip python3 rsync; do
    command -v "$tool" >/dev/null 2>&1 || {
        printf 'error: required tool is unavailable: %s\n' "$tool" >&2
        exit 1
    }
done

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

rsync -a --copy-links "$PACKAGE_DIR/plumos/" "$stage_dir/plumos/"
mkdir -p \
    "$stage_dir/plumos/state/portmaster/config" \
    "$stage_dir/plumos/state/portmaster/libs" \
    "$stage_dir/plumos/state/portmaster/themes" \
    "$stage_dir/plumos/state/portmaster/home" \
    "$stage_dir/plumos/Logs/apps"

cat > "$stage_dir/plumos/apps/portmaster/installed.json" <<EOF
{
  "adapter_version": 1,
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
adapter_version=1
upstream=PortMaster-GUI
version=${VERSION}
channel=stable
url=${URL}
md5=${actual_md5}
sha256=${actual_sha256}
update_policy=plumos-staged-switch
EOF

find "$OUT_DIR" -type f ! -name checksums.sha256 -print0 | sort -z | \
    xargs -0 sha256sum | sed "s#  $OUT_DIR/#  #" > "$OUT_DIR/checksums.sha256"

rm -rf "$stage_dir"
printf 'created: %s\n' "$OUT_DIR"
printf 'PortMaster: %s (%s)\n' "$VERSION" "$actual_sha256"
