#!/bin/sh
set -u

PLUMOS_ROOT="${PLUMOS_ROOT:-/mnt/plumos}"
RUNTIME_ROOT="${PLUMOS_RUNTIME_ROOT:-/run/plumos}"
EXPECTED_VENDOR_FILE="${PLUMOS_VENDOR_ID_FILE:-/etc/plumos-v90s-vendor-id}"
LOG_FILE="${PLUMOS_BOOTSTRAP_LOG:-${RUNTIME_ROOT}/app-layer-bootstrap.log}"
ERROR_FILE="${RUNTIME_ROOT}/app-layer-error"

export PLUMOS_ROOT
export PLUMOS_SDCARD_ROOT="${PLUMOS_SDCARD_ROOT:-$PLUMOS_ROOT}"
export PLUMOS_RUNTIME_ROOT="$RUNTIME_ROOT"
export PATH="${PLUMOS_ROOT}/bin:${PLUMOS_ROOT}/gnu/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

prepare_runtime() {
  mkdir -p \
    "$RUNTIME_ROOT" \
    "$RUNTIME_ROOT/frontend" \
    "$RUNTIME_ROOT/network-services" \
    "$RUNTIME_ROOT/picoarch" \
    "$RUNTIME_ROOT/retroarch" \
    "$RUNTIME_ROOT/standalone" \
    "$RUNTIME_ROOT/tmp" 2>/dev/null || return 1
  chmod 0755 "$RUNTIME_ROOT" 2>/dev/null || true
}

log() {
  prepare_runtime >/dev/null 2>&1 || true
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo unknown-time)" "$*" \
    >> "$LOG_FILE" 2>/dev/null || true
}

report_error() {
  reason="$1"
  prepare_runtime >/dev/null 2>&1 || true
  printf '%s\n' "$reason" > "$ERROR_FILE" 2>/dev/null || true
  log "error=$reason"
  printf 'plumOS app layer error: %s\n' "$reason" >&2
  printf 'plumOS app layer error: %s\n' "$reason" > /dev/console 2>/dev/null || true
  return 1
}

is_mounted() {
  awk -v target="$PLUMOS_ROOT" '$2 == target { found = 1 } END { exit !found }' \
    /proc/mounts 2>/dev/null
}

checksum_file() {
  relative="$1"
  entry="$(awk -v path="$relative" '$2 == path { print; exit }' \
    "$PLUMOS_ROOT/checksums.sha256" 2>/dev/null || true)"
  [ -n "$entry" ] || return 1
  printf '%s\n' "$entry" | (cd "$PLUMOS_ROOT" && sha256sum -c - >/dev/null 2>&1)
}

validate_app_layer() {
  prepare_runtime || return 1
  rm -f "$ERROR_FILE" 2>/dev/null || true

  is_mounted || { report_error "${PLUMOS_ROOT} is not mounted"; return 1; }
  [ -r "$PLUMOS_ROOT/manifest.json" ] || { report_error "manifest.json is missing"; return 1; }
  [ -r "$PLUMOS_ROOT/checksums.sha256" ] || { report_error "checksums.sha256 is missing"; return 1; }
  [ -r "$PLUMOS_ROOT/COMPAT_VENDOR" ] || { report_error "COMPAT_VENDOR is missing"; return 1; }
  [ -r "$PLUMOS_ROOT/VERSION" ] || { report_error "VERSION is missing"; return 1; }
  [ -x "$PLUMOS_ROOT/bin/plumos-frontend-launch" ] || { report_error "frontend launcher is missing"; return 1; }
  [ -x "$PLUMOS_ROOT/bin/plumos-controller-ui-fbdev" ] || { report_error "frontend binary is missing"; return 1; }
  command -v sha256sum >/dev/null 2>&1 || { report_error "sha256sum is unavailable in system rootfs"; return 1; }

  expected_vendor=""
  [ ! -r "$EXPECTED_VENDOR_FILE" ] || expected_vendor="$(sed -n '1p' "$EXPECTED_VENDOR_FILE")"
  actual_vendor="$(sed -n '1p' "$PLUMOS_ROOT/COMPAT_VENDOR")"
  if [ -n "$expected_vendor" ] && [ "$actual_vendor" != "$expected_vendor" ]; then
    report_error "vendor mismatch: app=${actual_vendor:-missing} system=$expected_vendor"
    return 1
  fi

  for relative in \
    COMPAT_VENDOR \
    VERSION \
    bin/plumos-frontend-launch \
    bin/plumos-controller-ui-v90s \
    bin/plumos-controller-ui-fbdev \
    bin/plumos-text-ui \
    frontend/lib/libpng16.so.16 \
    frontend/lib/libfreetype.so.6 \
    frontend/lib/libbrotlidec.so.1 \
    frontend/lib/libbrotlicommon.so.1; do
    checksum_file "$relative" || {
      report_error "critical checksum failed: $relative"
      return 1
    }
  done

  version="$(sed -n '1p' "$PLUMOS_ROOT/VERSION")"
  rm -f "$ERROR_FILE" 2>/dev/null || true
  log "validated version=$version vendor=$actual_vendor"
  printf 'app_layer=ready\nversion=%s\nvendor=%s\nruntime_root=%s\n' \
    "$version" "$actual_vendor" "$RUNTIME_ROOT"
}

start_frontend() {
  validate_app_layer >/dev/null || return 1
  log "starting frontend launcher=$PLUMOS_ROOT/bin/plumos-frontend-launch"
  exec "$PLUMOS_ROOT/bin/plumos-frontend-launch"
}

status() {
  if [ -r "$ERROR_FILE" ]; then
    printf 'app_layer=error\nreason=%s\n' "$(sed -n '1p' "$ERROR_FILE")"
    return 1
  fi
  validate_app_layer
}

case "${1:-start}" in
  start) start_frontend ;;
  validate) validate_app_layer ;;
  status) status ;;
  *)
    printf 'usage: %s [start|validate|status]\n' "$0" >&2
    exit 2
    ;;
esac
