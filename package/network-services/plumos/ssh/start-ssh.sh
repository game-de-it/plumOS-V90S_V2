#!/bin/sh
set -u

BASE_DIR="${PLUMOS_SSH_HOME:-$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)}"
PLUMOS_ROOT="${PLUMOS_ROOT:-/mnt/plumos}"
PLUMOS_SDCARD_ROOT="${PLUMOS_SDCARD_ROOT:-$PLUMOS_ROOT}"
RUNTIME_ROOT="${PLUMOS_RUNTIME_ROOT:-/run/plumos}"
ETC_DIR="${BASE_DIR}/etc"
RUN_DIR="${PLUMOS_SSH_RUN_DIR:-$RUNTIME_ROOT/ssh}"
LOG_DIR="${BASE_DIR}/log"
PORT="${PLUMOS_SSH_PORT:-22}"
LISTEN="${PLUMOS_SSH_LISTEN:-0.0.0.0}"
SSHD_BIN="${PLUMOS_SSHD_BIN:-/usr/sbin/sshd}"
PID_FILE="${RUN_DIR}/sshd.pid"
LOG_FILE="${LOG_DIR}/sshd.log"
SSHD_CONFIG="${ETC_DIR}/sshd_config"
ENV_PATH="${PLUMOS_SSH_PATH:-${PLUMOS_ROOT}/bin:${PLUMOS_ROOT}/gnu/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin}"

PATH="$ENV_PATH"
export PATH PLUMOS_ROOT PLUMOS_SDCARD_ROOT

mkdir -p "$ETC_DIR" "$RUN_DIR" "$LOG_DIR"

log() {
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || true)" "$*" >> "$LOG_FILE"
}

pid_running() {
  pid="$1"
  [ -n "$pid" ] || return 1
  kill -0 "$pid" 2>/dev/null || return 1
  cmdline="$(tr '\000' ' ' < "/proc/${pid}/cmdline" 2>/dev/null || true)"
  comm="$(cat "/proc/${pid}/comm" 2>/dev/null || true)"
  case "${cmdline} ${comm}" in
    *sshd*"[listener]"*) return 0 ;;
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
      *sshd*"[listener]"*)
        printf '%s\n' "$pid"
        return 0
        ;;
    esac
  done
  return 1
}

install_login_environment() {
  mkdir -p /root/.ssh /etc/profile.d 2>/dev/null || true
  chmod 0700 /root/.ssh 2>/dev/null || true

  cat > /root/.ssh/environment 2>/dev/null <<EOF || true
PLUMOS_ROOT=${PLUMOS_ROOT}
PLUMOS_SDCARD_ROOT=${PLUMOS_SDCARD_ROOT}
PATH=${ENV_PATH}
EOF
  chmod 0600 /root/.ssh/environment 2>/dev/null || true

  cat > /etc/profile.d/plumos-path.sh 2>/dev/null <<EOF || true
export PLUMOS_ROOT="\${PLUMOS_ROOT:-${PLUMOS_ROOT}}"
export PLUMOS_SDCARD_ROOT="\${PLUMOS_SDCARD_ROOT:-${PLUMOS_SDCARD_ROOT}}"
export PATH="${PLUMOS_ROOT}/bin:${PLUMOS_ROOT}/gnu/bin:\${PATH}"
EOF
  chmod 0644 /etc/profile.d/plumos-path.sh 2>/dev/null || true

  cat > /root/.profile 2>/dev/null <<'EOF' || true
if [ -f /etc/profile ]; then
  . /etc/profile
fi
export PLUMOS_ROOT="${PLUMOS_ROOT:-/mnt/plumos}"
export PLUMOS_SDCARD_ROOT="${PLUMOS_SDCARD_ROOT:-$PLUMOS_ROOT}"
case ":$PATH:" in
  *":${PLUMOS_ROOT}/bin:"*) ;;
  *) PATH="${PLUMOS_ROOT}/bin:${PLUMOS_ROOT}/gnu/bin:${PATH}" ;;
esac
export PATH
EOF

  cat > /root/.bashrc 2>/dev/null <<'EOF' || true
export PLUMOS_ROOT="${PLUMOS_ROOT:-/mnt/plumos}"
export PLUMOS_SDCARD_ROOT="${PLUMOS_SDCARD_ROOT:-$PLUMOS_ROOT}"
case ":$PATH:" in
  *":${PLUMOS_ROOT}/bin:"*) ;;
  *) PATH="${PLUMOS_ROOT}/bin:${PLUMOS_ROOT}/gnu/bin:${PATH}" ;;
esac
export PATH
EOF
}

install_sshd_config() {
  source_config=/etc/ssh/sshd_config
  tmp_config="${SSHD_CONFIG}.tmp"

  if [ -r "$source_config" ]; then
    sed 's|^[[:space:]]*Subsystem[[:space:]][[:space:]]*sftp[[:space:]].*$|Subsystem sftp /mnt/plumos/ssh/libexec/sftp-server|' \
      "$source_config" > "$tmp_config"
  else
    : > "$tmp_config"
  fi
  if ! grep -q '^[[:space:]]*Subsystem[[:space:]][[:space:]]*sftp[[:space:]]' "$tmp_config"; then
    printf '%s\n' 'Subsystem sftp /mnt/plumos/ssh/libexec/sftp-server' >> "$tmp_config"
  fi
  mv "$tmp_config" "$SSHD_CONFIG"
  chmod 0600 "$SSHD_CONFIG" 2>/dev/null || true
}

host_key_args() {
  args=""
  found=0
  for type in rsa ecdsa ed25519; do
    key="/etc/ssh/ssh_host_${type}_key"
    if [ -s "$key" ]; then
      args="$args -h $key"
      found=1
    fi
  done

  if [ "$found" -eq 0 ] && command -v ssh-keygen >/dev/null 2>&1; then
    for type in rsa ecdsa ed25519; do
      key="${ETC_DIR}/ssh_host_${type}_key"
      [ -s "$key" ] || ssh-keygen -q -t "$type" -N '' -f "$key" >> "$LOG_FILE" 2>&1 || true
      [ -s "$key" ] && args="$args -h $key"
    done
  fi

  printf '%s\n' "$args"
}

install_login_environment
install_sshd_config

if [ -s "$PID_FILE" ]; then
  pid="$(sed -n '1p' "$PID_FILE" 2>/dev/null | tr -d '[:space:]')"
  if pid_running "$pid"; then
    log "sshd already running pid=${pid}"
    exit 0
  fi
fi

if [ -s "$RUNTIME_ROOT/network-recovery/sshd.pid" ]; then
  pid="$(sed -n '1p' "$RUNTIME_ROOT/network-recovery/sshd.pid" 2>/dev/null | tr -d '[:space:]')"
  if pid_running "$pid"; then
    printf '%s\n' "$pid" > "$PID_FILE"
    log "adopted system sshd pid=${pid}"
    exit 0
  fi
fi

existing_pid="$(find_existing_sshd 2>/dev/null || true)"
if [ -n "$existing_pid" ] && pid_running "$existing_pid"; then
  printf '%s\n' "$existing_pid" > "$PID_FILE"
  log "adopted existing sshd pid=${existing_pid}"
  exit 0
fi

if [ ! -x "$SSHD_BIN" ]; then
  log "sshd missing: $SSHD_BIN"
  exit 1
fi

mkdir -p /run/sshd
chown 0:0 /run/sshd 2>/dev/null || true
chmod 0755 /run/sshd
host_args="$(host_key_args)"
if [ -z "$host_args" ]; then
  log "no SSH host keys available"
  exit 1
fi

rm -f "$PID_FILE"
log "starting sshd listen=${LISTEN} port=${PORT}"
# shellcheck disable=SC2086
"$SSHD_BIN" -f "$SSHD_CONFIG" $host_args \
  -E "$LOG_FILE" \
  -o "PidFile=$PID_FILE" \
  -o "ListenAddress=$LISTEN" \
  -o "Port=$PORT" \
  -o "PermitRootLogin=yes" \
  -o "PasswordAuthentication=yes" \
  -o "PubkeyAuthentication=yes" \
  -o "KbdInteractiveAuthentication=yes" \
  -o "UsePAM=no" \
  -o "PermitUserEnvironment=yes" \
  -o "AuthorizedKeysFile=.ssh/authorized_keys" \
  -o "SetEnv=PLUMOS_ROOT=${PLUMOS_ROOT} PLUMOS_SDCARD_ROOT=${PLUMOS_SDCARD_ROOT} PATH=${ENV_PATH}" \
  >> "$LOG_FILE" 2>&1

status=$?
if [ "$status" -eq 0 ]; then
  log "sshd started"
else
  log "sshd failed status=${status}"
fi
exit "$status"
