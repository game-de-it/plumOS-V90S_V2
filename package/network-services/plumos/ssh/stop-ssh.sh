#!/bin/sh
set -u

BASE_DIR="${PLUMOS_SSH_HOME:-$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)}"
RUN_DIR="${BASE_DIR}/run"
LOG_DIR="${BASE_DIR}/log"
PID_FILE="${RUN_DIR}/sshd.pid"
LOG_FILE="${LOG_DIR}/sshd.log"

mkdir -p "$RUN_DIR" "$LOG_DIR"

log() {
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || true)" "$*" >> "$LOG_FILE"
}

pid_matches_sshd() {
  pid="$1"
  [ -n "$pid" ] || return 1
  kill -0 "$pid" 2>/dev/null || return 1
  cmdline="$(tr '\000' ' ' < "/proc/${pid}/cmdline" 2>/dev/null || true)"
  comm="$(cat "/proc/${pid}/comm" 2>/dev/null || true)"
  case "${cmdline} ${comm}" in
    *sshd*) return 0 ;;
  esac
  return 1
}

find_existing_sshd() {
  for proc in /proc/[0-9]*; do
    [ -d "$proc" ] || continue
    pid="${proc##*/}"
    cmdline="$(tr '\000' ' ' < "$proc/cmdline" 2>/dev/null || true)"
    comm="$(cat "$proc/comm" 2>/dev/null || true)"
    case "${cmdline} ${comm}" in
      *sshd*listener*|*"sshd -"*|*"/usr/sbin/sshd"*|*" sshd"*)
        printf '%s\n' "$pid"
        return 0
        ;;
    esac
  done
  return 1
}

pid=""
if [ -s "$PID_FILE" ]; then
  pid="$(sed -n '1p' "$PID_FILE" 2>/dev/null | tr -d '[:space:]')"
fi
if ! pid_matches_sshd "$pid"; then
  pid="$(find_existing_sshd 2>/dev/null || true)"
fi

if [ -z "$pid" ]; then
  log "no sshd pid found"
  rm -f "$PID_FILE"
  exit 0
fi

if pid_matches_sshd "$pid"; then
  kill "$pid" 2>/dev/null || true
  sleep 1
  if kill -0 "$pid" 2>/dev/null; then
    kill -9 "$pid" 2>/dev/null || true
  fi
  log "stopped sshd pid=${pid}"
fi

rm -f "$PID_FILE"
