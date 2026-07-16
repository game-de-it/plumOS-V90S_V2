#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
APP_LAYER_DIR="${PLUMOS_V90S_APP_LAYER_DIR:-$ROOT_DIR/output/app-layer/v90s}"
ADB_WRAPPER="${PLUMOS_V90S_ADB_WRAPPER:-$ROOT_DIR/scripts/v90s-adb.sh}"
PLUMOS_ROOT="${PLUMOS_ROOT:-/mnt/plumos}"
RESTART_FRONTEND=1

usage() {
    cat <<EOF
Usage: $(basename "$0") [--no-restart]

Deploys only files changed since the device's installed app-layer manifest.
Payload files are transferred first; manifest.json and checksums.sha256 are
installed last so the boot-time integrity contract describes one complete set.

Environment:
  PLUMOS_V90S_APP_LAYER_DIR  App-layer build output.
  PLUMOS_V90S_ADB_WRAPPER    ADB wrapper; defaults to scripts/v90s-adb.sh.
  PLUMOS_ROOT                Device app-layer mount; default /mnt/plumos.
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --no-restart) RESTART_FRONTEND=0 ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'error: unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

for path in "$APP_LAYER_DIR/manifest.json" "$APP_LAYER_DIR/checksums.sha256"; do
    [ -f "$path" ] || {
        printf 'error: required app-layer file is missing: %s\n' "$path" >&2
        exit 1
    }
done
[ -x "$ADB_WRAPPER" ] || {
    printf 'error: ADB wrapper is not executable: %s\n' "$ADB_WRAPPER" >&2
    exit 1
}

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/plumos-app-layer-adb.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT HUP INT TERM
device_checksums="$tmp_dir/device-checksums.sha256"
changed_paths="$tmp_dir/changed-paths.txt"
changed_checksums="$tmp_dir/changed-checksums.sha256"
payload_paths="$tmp_dir/payload-paths.txt"
payload_tar="$tmp_dir/app-layer-payload.tar"

mount_line="$($ADB_WRAPPER shell "awk '\$2 == \"$PLUMOS_ROOT\" { print; exit }' /proc/mounts")"
[ -n "$mount_line" ] || {
    printf 'error: %s is not mounted on the device\n' "$PLUMOS_ROOT" >&2
    exit 1
}
case " $mount_line " in
    *" ro,"*|*",ro,"*|*",ro "*)
        printf 'error: %s is read-only; safely reboot so boot fsck can repair p7\n' \
            "$PLUMOS_ROOT" >&2
        exit 1
        ;;
esac

if ! $ADB_WRAPPER pull "$PLUMOS_ROOT/checksums.sha256" "$device_checksums" >/dev/null 2>&1; then
    : > "$device_checksums"
fi

awk '
  NR == FNR {
    if (length($0) >= 67) old[substr($0, 67)] = substr($0, 1, 64)
    next
  }
  length($0) >= 67 {
    path = substr($0, 67)
    hash = substr($0, 1, 64)
    if (!(path in old) || old[path] != hash) print path
  }
' "$device_checksums" "$APP_LAYER_DIR/checksums.sha256" > "$changed_paths"

awk '
  NR == FNR { wanted[$0] = 1; next }
  length($0) >= 67 && substr($0, 67) in wanted { print }
' "$changed_paths" "$APP_LAYER_DIR/checksums.sha256" > "$changed_checksums"
grep -v '^manifest\.json$' "$changed_paths" > "$payload_paths" || true

changed_count="$(wc -l < "$changed_paths" | tr -d ' ')"
payload_count="$(wc -l < "$payload_paths" | tr -d ' ')"
printf 'app_layer=%s\nchanged_files=%s\npayload_files=%s\n' \
    "$APP_LAYER_DIR" "$changed_count" "$payload_count"

if [ "$changed_count" -eq 0 ]; then
    printf 'deploy=up-to-date\nfrontend_restart=not-needed\n'
    exit 0
fi

if [ "$payload_count" -gt 0 ]; then
    tar -C "$APP_LAYER_DIR" -cf "$payload_tar" -T "$payload_paths"
    $ADB_WRAPPER push "$payload_tar" /run/plumos/app-layer-payload.tar >/dev/null
fi
$ADB_WRAPPER push "$APP_LAYER_DIR/manifest.json" /run/plumos/manifest.json.new >/dev/null
$ADB_WRAPPER push "$APP_LAYER_DIR/checksums.sha256" /run/plumos/checksums.sha256.new >/dev/null
$ADB_WRAPPER push "$changed_checksums" /run/plumos/app-layer-changed.sha256 >/dev/null

$ADB_WRAPPER shell "
set -e
if [ -x '$PLUMOS_ROOT/bin/plumos-frontend-stop' ]; then
  '$PLUMOS_ROOT/bin/plumos-frontend-stop' stop >/dev/null 2>&1 || true
fi
if [ -s /run/plumos/app-layer-payload.tar ]; then
  tar -C '$PLUMOS_ROOT' -xf /run/plumos/app-layer-payload.tar
fi
cp /run/plumos/manifest.json.new '$PLUMOS_ROOT/manifest.json'
cp /run/plumos/checksums.sha256.new '$PLUMOS_ROOT/checksums.sha256'
sync
cd '$PLUMOS_ROOT'
sha256sum -c /run/plumos/app-layer-changed.sha256
rm -f /run/plumos/app-layer-payload.tar /run/plumos/manifest.json.new \
  /run/plumos/checksums.sha256.new /run/plumos/app-layer-changed.sha256
"

if [ "$RESTART_FRONTEND" -eq 1 ]; then
    $ADB_WRAPPER shell "
rm -f /run/plumos/app-layer-error
nohup '$PLUMOS_ROOT/bin/plumos-frontend-launch' >/dev/null 2>&1 &
"
fi

printf 'deploy=ok\nfrontend_restart=%s\n' "$RESTART_FRONTEND"
