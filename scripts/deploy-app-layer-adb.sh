#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
APP_LAYER_DIR="${PLUMOS_V90S_APP_LAYER_DIR:-$ROOT_DIR/output/app-layer/v90s}"
ADB_WRAPPER="${PLUMOS_V90S_ADB_WRAPPER:-$ROOT_DIR/scripts/v90s-adb.sh}"
PLUMOS_ROOT="${PLUMOS_ROOT:-/mnt/plumos}"
CHUNK_FILES="${PLUMOS_DEPLOY_CHUNK_FILES:-128}"
VERIFY_HOST="${PLUMOS_DEPLOY_VERIFY_HOST:-1}"
RESTART_FRONTEND=1
DEVICE_RUN_DIR=/run/plumos/app-layer-deploy
device_quiesced=0

usage() {
    cat <<EOF
Usage: $(basename "$0") [--no-restart]

Deploys only files changed since the device's installed app-layer manifest.
The helper keeps ADB and SSH available, quiesces other known p7 writers, and
installs verified payload chunks before committing app-layer metadata.

Environment:
  PLUMOS_V90S_APP_LAYER_DIR  App-layer build output.
  PLUMOS_V90S_ADB_WRAPPER    ADB wrapper; defaults to scripts/v90s-adb.sh.
  PLUMOS_ROOT                Device app-layer mount; default /mnt/plumos.
  PLUMOS_DEPLOY_CHUNK_FILES  Files per synced payload chunk; default 128.
  PLUMOS_DEPLOY_VERIFY_HOST  Verify the complete host artifact first; default 1.
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

case "$CHUNK_FILES" in
    ''|*[!0-9]*|0) printf 'error: invalid PLUMOS_DEPLOY_CHUNK_FILES: %s\n' "$CHUNK_FILES" >&2; exit 2 ;;
esac

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
device_checksums="$tmp_dir/device-checksums.sha256"
changed_paths="$tmp_dir/changed-paths.txt"
payload_paths="$tmp_dir/payload-paths.txt"

resume_device() {
    $ADB_WRAPPER shell "
state='$DEVICE_RUN_DIR/state'
if [ -r \"\$state\" ]; then
  if grep -qx hardware_keys \"\$state\" && [ -x '$PLUMOS_ROOT/bin/plumos-hardware-keys-service' ]; then
    '$PLUMOS_ROOT/bin/plumos-hardware-keys-service' start >/dev/null 2>&1 || true
  fi
  if grep -qx ftp \"\$state\" && [ -x '$PLUMOS_ROOT/bin/plumos-network-services' ]; then
    '$PLUMOS_ROOT/bin/plumos-network-services' start ftp >/dev/null 2>&1 || true
  fi
  if grep -qx samba \"\$state\" && [ -x '$PLUMOS_ROOT/bin/plumos-network-services' ]; then
    '$PLUMOS_ROOT/bin/plumos-network-services' start samba >/dev/null 2>&1 || true
  fi
  if [ '$RESTART_FRONTEND' -eq 1 ] && grep -qx frontend \"\$state\" &&
     [ -x '$PLUMOS_ROOT/bin/plumos-frontend-launch' ]; then
    rm -f /run/plumos/app-layer-error
    nohup '$PLUMOS_ROOT/bin/plumos-frontend-launch' >/dev/null 2>&1 &
  fi
fi
rm -rf '$DEVICE_RUN_DIR'
" >/dev/null 2>&1 || true
}

cleanup() {
    rc=$?
    trap - EXIT HUP INT TERM
    if [ "$device_quiesced" -eq 1 ]; then
        resume_device
    fi
    rm -rf "$tmp_dir"
    exit "$rc"
}
trap cleanup EXIT HUP INT TERM

if [ "$VERIFY_HOST" != 0 ]; then
    printf 'host_verify=running\n'
    (cd "$APP_LAYER_DIR" && sha256sum -c checksums.sha256 >/dev/null)
    printf 'host_verify=ok\n'
fi

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

grep -v '^manifest\.json$' "$changed_paths" > "$payload_paths" || true

changed_count="$(wc -l < "$changed_paths" | tr -d ' ')"
payload_count="$(wc -l < "$payload_paths" | tr -d ' ')"
printf 'app_layer=%s\nchanged_files=%s\npayload_files=%s\n' \
    "$APP_LAYER_DIR" "$changed_count" "$payload_count"

if [ "$changed_count" -eq 0 ]; then
    printf 'deploy=up-to-date\nfrontend_restart=not-needed\n'
    exit 0
fi

device_quiesced=1
$ADB_WRAPPER shell "
set -e
run_dir='$DEVICE_RUN_DIR'
state=\"\$run_dir/state\"
rm -rf \"\$run_dir\"
mkdir -p \"\$run_dir\"
: > \"\$state\"

record_state() {
  grep -qx \"\$1\" \"\$state\" 2>/dev/null || printf '%s\\n' \"\$1\" >> \"\$state\"
}

if [ -x '$PLUMOS_ROOT/bin/plumos-frontend-stop' ] &&
   '$PLUMOS_ROOT/bin/plumos-frontend-stop' status 2>/dev/null | grep -q 'pid='; then
  record_state frontend
fi
if [ -x '$PLUMOS_ROOT/bin/plumos-hardware-keys-service' ] &&
   '$PLUMOS_ROOT/bin/plumos-hardware-keys-service' status >/dev/null 2>&1; then
  record_state hardware_keys
fi

for proc in /proc/[0-9]*; do
  [ \"\${proc##*/}\" != \"\$\$\" ] || continue
  [ -r \"\$proc/cmdline\" ] || continue
  cmd=\$(tr '\\000' ' ' < \"\$proc/cmdline\" 2>/dev/null || true)
  case \"\$cmd\" in
    *'$PLUMOS_ROOT/bin/busybox tcpsvd '*|*'$PLUMOS_ROOT/bin/tcpsvd '*) record_state ftp ;;
    *'$PLUMOS_ROOT/samba/sbin/smbd.bin'*|*'$PLUMOS_ROOT/samba/sbin/nmbd'*) record_state samba ;;
  esac
done

[ ! -x '$PLUMOS_ROOT/bin/plumos-portmaster-port-stop' ] ||
  '$PLUMOS_ROOT/bin/plumos-portmaster-port-stop' stop >/dev/null 2>&1 || true
[ ! -x '$PLUMOS_ROOT/bin/plumos-portmaster-stop' ] ||
  '$PLUMOS_ROOT/bin/plumos-portmaster-stop' >/dev/null 2>&1 || true
[ ! -x '$PLUMOS_ROOT/bin/v90s-retroarch-stop' ] ||
  '$PLUMOS_ROOT/bin/v90s-retroarch-stop' stop >/dev/null 2>&1 || true
[ ! -x '$PLUMOS_ROOT/bin/plumos-picoarch-stop' ] ||
  '$PLUMOS_ROOT/bin/plumos-picoarch-stop' >/dev/null 2>&1 || true
if [ -x '$PLUMOS_ROOT/bin/plumos-standalone-stop' ]; then
  for pid_file in /run/plumos/standalone/*.pid; do
    [ -e \"\$pid_file\" ] || continue
    id=\${pid_file##*/}
    id=\${id%.pid}
    '$PLUMOS_ROOT/bin/plumos-standalone-stop' \"\$id\" >/dev/null 2>&1 || true
  done
fi

if [ -x '$PLUMOS_ROOT/bin/plumos-frontend-stop' ] &&
   '$PLUMOS_ROOT/bin/plumos-frontend-stop' status 2>/dev/null | grep -q 'pid='; then
  record_state frontend
  '$PLUMOS_ROOT/bin/plumos-frontend-stop' stop >/dev/null 2>&1 || true
fi
[ ! -x '$PLUMOS_ROOT/bin/plumos-hardware-keys-service' ] ||
  '$PLUMOS_ROOT/bin/plumos-hardware-keys-service' stop >/dev/null 2>&1 || true

pids=''
for proc in /proc/[0-9]*; do
  pid=\${proc##*/}
  [ \"\$pid\" != \"\$\$\" ] || continue
  [ -r \"\$proc/cmdline\" ] || continue
  cmd=\$(tr '\\000' ' ' < \"\$proc/cmdline\" 2>/dev/null || true)
  case \"\$cmd\" in
    *'$PLUMOS_ROOT/bin/busybox tcpsvd '*|*'$PLUMOS_ROOT/bin/tcpsvd '*|\
    *'$PLUMOS_ROOT/samba/sbin/smbd.bin'*|*'$PLUMOS_ROOT/samba/sbin/nmbd'*)
      pids=\"\${pids}\${pids:+ }\$pid\"
      ;;
  esac
done
for pid in \$pids; do kill -TERM \"\$pid\" 2>/dev/null || true; done
sleep 1
for pid in \$pids; do kill -0 \"\$pid\" 2>/dev/null && kill -KILL \"\$pid\" 2>/dev/null || true; done
sync
sleep 1
sync
awk '\$2 == \"$PLUMOS_ROOT\" && \$4 ~ /(^|,)rw(,|$)/ { ok=1 } END { exit !ok }' /proc/mounts
"

$ADB_WRAPPER push "$APP_LAYER_DIR/manifest.json" "$DEVICE_RUN_DIR/manifest.json.new" >/dev/null
$ADB_WRAPPER push "$APP_LAYER_DIR/checksums.sha256" "$DEVICE_RUN_DIR/checksums.sha256.new" >/dev/null

if [ "$payload_count" -gt 0 ]; then
    split -l "$CHUNK_FILES" -a 4 "$payload_paths" "$tmp_dir/chunk."
    chunk_number=0
    for chunk_paths in "$tmp_dir"/chunk.*; do
        chunk_number=$((chunk_number + 1))
        chunk_tar="$tmp_dir/payload.$chunk_number.tar"
        chunk_checksums="$tmp_dir/checksums.$chunk_number.sha256"
        COPYFILE_DISABLE=1 tar -C "$APP_LAYER_DIR" -cf "$chunk_tar" -T "$chunk_paths"
        awk '
          NR == FNR { wanted[$0] = 1; next }
          length($0) >= 67 && substr($0, 67) in wanted { print }
        ' "$chunk_paths" "$APP_LAYER_DIR/checksums.sha256" > "$chunk_checksums"
        $ADB_WRAPPER push "$chunk_tar" "$DEVICE_RUN_DIR/payload.tar" >/dev/null
        $ADB_WRAPPER push "$chunk_checksums" "$DEVICE_RUN_DIR/payload.sha256" >/dev/null
        $ADB_WRAPPER shell "
set -e
awk '\$2 == \"$PLUMOS_ROOT\" && \$4 ~ /(^|,)rw(,|$)/ { ok=1 } END { exit !ok }' /proc/mounts
tar -C '$PLUMOS_ROOT' -xf '$DEVICE_RUN_DIR/payload.tar'
sync
cd '$PLUMOS_ROOT'
sha256sum -c '$DEVICE_RUN_DIR/payload.sha256'
rm -f '$DEVICE_RUN_DIR/payload.tar' '$DEVICE_RUN_DIR/payload.sha256'
"
        rm -f "$chunk_tar" "$chunk_checksums"
        printf 'chunk=%s verified\n' "$chunk_number"
    done
fi

$ADB_WRAPPER shell "
set -e
awk '\$2 == \"$PLUMOS_ROOT\" && \$4 ~ /(^|,)rw(,|$)/ { ok=1 } END { exit !ok }' /proc/mounts
cp '$DEVICE_RUN_DIR/manifest.json.new' '$PLUMOS_ROOT/manifest.json.tmp.deploy'
sync
mv -f '$PLUMOS_ROOT/manifest.json.tmp.deploy' '$PLUMOS_ROOT/manifest.json'
sync
cp '$DEVICE_RUN_DIR/checksums.sha256.new' '$PLUMOS_ROOT/checksums.sha256.tmp.deploy'
sync
mv -f '$PLUMOS_ROOT/checksums.sha256.tmp.deploy' '$PLUMOS_ROOT/checksums.sha256'
sync
cd '$PLUMOS_ROOT'
grep '  manifest.json\$' checksums.sha256 | sha256sum -c -
awk '\$2 == \"$PLUMOS_ROOT\" && \$4 ~ /(^|,)rw(,|$)/ { ok=1 } END { exit !ok }' /proc/mounts
"

resume_device
device_quiesced=0

printf 'deploy=ok\nchunks=%s\nfrontend_restart=%s\n' "${chunk_number:-0}" "$RESTART_FRONTEND"
