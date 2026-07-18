#!/bin/sh
set -u

PLUMOS_ROOT="${PLUMOS_ROOT:-/mnt/plumos}"
PLUMOS_SDCARD_ROOT="${PLUMOS_SDCARD_ROOT:-$PLUMOS_ROOT}"
PLUMOS_USER_ROOT="${PLUMOS_USER_ROOT:-/mnt/plumos-user}"
PLUMOS_BOOT_ROOT="${PLUMOS_BOOT_ROOT:-/mnt/plumos-boot}"
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH PLUMOS_ROOT PLUMOS_SDCARD_ROOT
cd / 2>/dev/null || true

LOG_FILE="${PLUMOS_POWER_ACTION_LOG:-/run/plumos/power-action.log}"
LOCK_DIR="${PLUMOS_POWER_ACTION_LOCK:-/run/plumos/power-action.lock}"

ACTION=shutdown
POWER_OFF=0
DRY_RUN=0
POWER_BACKEND="${PLUMOS_POWER_ACTION_POWER_BACKEND:-${PLUMOS_SAFE_SHUTDOWN_POWER_BACKEND:-auto}}"
SLEEP_BACKEND="${PLUMOS_POWER_ACTION_SLEEP_BACKEND:-${PLUMOS_SAFE_SHUTDOWN_SLEEP_BACKEND:-mem}}"
WAKEUP_SEC="${PLUMOS_POWER_ACTION_SLEEP_WAKEUP_SEC:-${PLUMOS_SAFE_SLEEP_WAKEUP_SEC:-0}}"
WAIT_SEC="${PLUMOS_POWER_ACTION_WAIT_SEC:-${PLUMOS_SAFE_SHUTDOWN_WAIT_SEC:-1}}"
FINAL_UNMOUNT="${PLUMOS_POWER_ACTION_FINAL_UNMOUNT:-${PLUMOS_SAFE_SHUTDOWN_FINAL_UNMOUNT:-1}}"
MIRROR_LOG="${PLUMOS_POWER_ACTION_MIRROR_LOG:-1}"
QUIESCE_CLEAN=0
CLEAN_MARKERS_RECORDED=0

usage() {
  cat <<'USAGE'
Usage: plumos-power-action [options]

Options:
  --shutdown             Run the shutdown action. Default.
  --reboot               Sync and reboot the OS.
  --sleep                Sync and enter sleep when supported.
  --poweroff             Power off after shutdown sync.
  --no-poweroff          Do not power off. Default.
  --power-backend NAME   Power backend: auto, sysrq, none. Other names are accepted as sysrq.
  --sleep-backend NAME   Sleep backend: mem, standby, freeze, none.
  --wakeup-sec N         Set RTC wakealarm before sleep when available.
  --hold-resume          Accepted for compatibility; no-op.
  --no-hold-resume       Accepted for compatibility; no-op.
  --dry-run              Log actions without rebooting, sleeping, powering off, or unmounting.
  --wait-sec N           Small delay after sync before final action. Default: 1.
  --unmount              Unmount all persistent plumOS filesystems before final sysrq. Default.
  --no-unmount           Skip final persistent-storage unmount for diagnostics.
  --quiesce              Compatibility alias for --unmount.
  --no-quiesce           Compatibility alias for --no-unmount.
  -h, --help             Show this help.
USAGE
}

mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true

uptime_now() {
  if [ -r /proc/uptime ]; then
    read -r up _ < /proc/uptime || up=unknown
    printf '%s' "$up"
  else
    printf '%s' unknown
  fi
}

log() {
  printf '%s uptime=%s %s\n' \
    "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo unknown-time)" \
    "$(uptime_now)" "$*" >> "$LOG_FILE" 2>/dev/null || true
}

is_non_negative_int() {
  case "$1" in
    ""|*[!0-9]*)
      return 1
      ;;
  esac
  return 0
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --shutdown)
      ACTION=shutdown
      ;;
    --reboot)
      ACTION=reboot
      ;;
    --sleep)
      ACTION=sleep
      ;;
    --poweroff)
      POWER_OFF=1
      ;;
    --no-poweroff)
      POWER_OFF=0
      ;;
    --power-backend)
      shift
      [ "$#" -gt 0 ] || { echo "error: --power-backend expects a value" >&2; exit 2; }
      POWER_BACKEND="$1"
      ;;
    --sleep-backend)
      shift
      [ "$#" -gt 0 ] || { echo "error: --sleep-backend expects a value" >&2; exit 2; }
      SLEEP_BACKEND="$1"
      ;;
    --wakeup-sec)
      shift
      if [ "$#" -eq 0 ] || ! is_non_negative_int "$1"; then
        echo "error: --wakeup-sec expects a non-negative integer" >&2
        exit 2
      fi
      WAKEUP_SEC="$1"
      ;;
    --wait-sec)
      shift
      if [ "$#" -eq 0 ] || ! is_non_negative_int "$1"; then
        echo "error: --wait-sec expects a non-negative integer" >&2
        exit 2
      fi
      WAIT_SEC="$1"
      ;;
    --hold-resume|--no-hold-resume)
      :
      ;;
    --dry-run)
      DRY_RUN=1
      ;;
    --unmount|--quiesce)
      FINAL_UNMOUNT=1
      ;;
    --no-unmount|--no-quiesce)
      FINAL_UNMOUNT=0
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

case "$SLEEP_BACKEND" in
  mem|standby|freeze|none)
    ;;
  *)
    echo "error: invalid sleep backend: $SLEEP_BACKEND" >&2
    exit 2
    ;;
esac

if [ "$ACTION" = sleep ] && [ "$POWER_OFF" -eq 1 ]; then
  echo "error: --sleep cannot be combined with --poweroff" >&2
  exit 2
fi

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  log "already_running action=$ACTION"
  echo "result=already_running"
  exit 0
fi
trap 'rmdir "$LOCK_DIR" 2>/dev/null || true; exit 143' INT TERM
trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT

mount_source_for_path() {
  wanted="$1"
  while read -r source mount_target fstype opts rest; do
    [ "$mount_target" = "$wanted" ] || continue
    printf '%s %s %s\n' "$source" "$fstype" "$opts"
    return 0
  done < /proc/mounts
  return 1
}

is_mounted_path() {
  mount_source_for_path "$1" >/dev/null 2>&1
}

safe_sync() {
  log "sync: begin"
  sync 2>/dev/null || true
  if [ "$WAIT_SEC" -gt 0 ]; then
    sleep "$WAIT_SEC" 2>/dev/null || true
  fi
  sync 2>/dev/null || true
  log "sync: done"
}

sync_once() {
  log "sync: begin"
  sync 2>/dev/null || true
  log "sync: done"
}

wait_pids_exit() {
  WAIT_ALIVE="$1"
  attempts="$2"
  while [ "$attempts" -gt 0 ]; do
    alive=""
    for pid in $WAIT_ALIVE; do
      if kill -0 "$pid" 2>/dev/null; then
        alive="${alive}${alive:+ }$pid"
      fi
    done
    WAIT_ALIVE="$alive"
    [ -n "$WAIT_ALIVE" ] || return 0
    sleep 0.1 2>/dev/null || true
    attempts=$((attempts - 1))
  done
  return 1
}

pid_cmdline() {
  pid="$1"
  tr '\000' ' ' < "/proc/$pid/cmdline" 2>/dev/null || true
}

pid_matches_app_layer_writer() {
  pid="$1"
  cmdline="$(pid_cmdline "$pid")"
  case "$cmdline" in
    *"$PLUMOS_ROOT/bin/plumos-controller-ui-fbdev"*|\
    *"$PLUMOS_ROOT/bin/plumos-controller-ui-v90s"*|\
    *"$PLUMOS_ROOT/bin/plumos-frontend-launch"*|\
    *"$PLUMOS_ROOT/bin/busybox tcpsvd "*|\
    *"$PLUMOS_ROOT/bin/tcpsvd "*|\
    *"$PLUMOS_ROOT/bin/busybox ftpd "*|\
    *"$PLUMOS_ROOT/bin/ftpd "*|\
    *"$PLUMOS_ROOT/samba/sbin/smbd.bin"*|\
    *"$PLUMOS_ROOT/samba/sbin/nmbd"*|\
    *"$PLUMOS_ROOT/bin/v90s-retroarch-launch"*|\
    *"$PLUMOS_ROOT/bin/retroarch"*|\
    *" --config $PLUMOS_ROOT/config/retroarch/retroarch-v90s.cfg "*)
      return 0
      ;;
  esac
  return 1
}

stop_app_layer_writers() {
  pids=""
  for proc in /proc/[0-9]*; do
    pid="${proc##*/}"
    [ "$pid" != "$$" ] || continue
    [ -e "$proc/exe" ] || continue
    [ -r "$proc/cmdline" ] || continue
    if pid_matches_app_layer_writer "$pid"; then
      pids="${pids}${pids:+ }$pid"
    fi
  done

  if [ -z "$pids" ]; then
    log "quiesce: no app-layer writers found"
    return 0
  fi

  log "quiesce: TERM pids=$pids"
  for pid in $pids; do
    kill -TERM "$pid" 2>/dev/null || true
  done
  wait_pids_exit "$pids" 10 || true
  still_alive="$WAIT_ALIVE"
  if [ -n "$still_alive" ]; then
    log "quiesce: KILL pids=$still_alive"
    for pid in $still_alive; do
      kill -KILL "$pid" 2>/dev/null || true
    done
    wait_pids_exit "$still_alive" 5 || true
  fi
}

log_plumos_blockers() {
  count=0
  for proc in /proc/[0-9]*; do
    pid="${proc##*/}"
    [ "$pid" != "$$" ] || continue
    hit=0
    for link in "$proc/cwd" "$proc/root" "$proc/exe" "$proc"/fd/*; do
      target="$(readlink "$link" 2>/dev/null || true)"
      case "$target" in
        "$PLUMOS_ROOT"|"$PLUMOS_ROOT"/*)
          hit=1
          break
          ;;
      esac
    done
    [ "$hit" -eq 1 ] || continue
    log "quiesce: blocker pid=$pid cmd=$(pid_cmdline "$pid")"
    count=$((count + 1))
    [ "$count" -lt 20 ] || break
  done
  [ "$count" -gt 0 ] || log "quiesce: no /mnt/plumos blockers found"
}

pid_uses_persistent_storage() {
  pid="$1"
  for link in "/proc/$pid/cwd" "/proc/$pid/root" "/proc/$pid/exe" "/proc/$pid"/fd/*; do
    target="$(readlink "$link" 2>/dev/null || true)"
    case "$target" in
      "$PLUMOS_ROOT"|"$PLUMOS_ROOT"/*|\
      "$PLUMOS_USER_ROOT"|"$PLUMOS_USER_ROOT"/*|\
      "$PLUMOS_BOOT_ROOT"|"$PLUMOS_BOOT_ROOT"/*|\
      /boot|/boot/*|/run/plumos/sd2|/run/plumos/sd2/*)
        return 0
        ;;
    esac
  done
  return 1
}

stop_persistent_storage_users() {
  pids=""
  for proc in /proc/[0-9]*; do
    pid="${proc##*/}"
    [ "$pid" != 1 ] || continue
    [ "$pid" != "$$" ] || continue
    [ -e "$proc/exe" ] || continue
    if pid_uses_persistent_storage "$pid"; then
      pids="${pids}${pids:+ }$pid"
    fi
  done

  if [ -z "$pids" ]; then
    log "quiesce: no persistent-storage users found"
    return 0
  fi

  log "quiesce: persistent TERM pids=$pids"
  for pid in $pids; do
    kill -TERM "$pid" 2>/dev/null || true
  done
  wait_pids_exit "$pids" 10 || true
  still_alive="$WAIT_ALIVE"
  if [ -n "$still_alive" ]; then
    log "quiesce: persistent KILL pids=$still_alive"
    for pid in $still_alive; do
      kill -KILL "$pid" 2>/dev/null || true
    done
    wait_pids_exit "$still_alive" 5 || true
  fi
}

unmount_if_mounted() {
  target="$1"
  if ! is_mounted_path "$target"; then
    log "umount: skip target=$target reason=not_mounted"
    return 0
  fi
  log "umount: begin target=$target source=$(mount_source_for_path "$target" || true)"
  if umount "$target" 2>> "$LOG_FILE"; then
    log "umount: done target=$target"
    return 0
  fi
  log "umount: failed target=$target"
  return 1
}

stop_sd2_mounts() {
  log "sd2: stopping content mounts"
  unmount_if_mounted "$PLUMOS_ROOT/bios" || true
  unmount_if_mounted "$PLUMOS_ROOT/roms" || true
  unmount_if_mounted /run/plumos/sd2 || true
}

mirror_log_to_app_layer() {
  [ "$MIRROR_LOG" = "1" ] || return 0
  if [ -d "$PLUMOS_ROOT/Logs" ]; then
    cp "$LOG_FILE" "$PLUMOS_ROOT/Logs/power-action-rootfs.log" 2>/dev/null || true
  fi
  if [ -d "$PLUMOS_USER_ROOT/Logs" ]; then
    cp "$LOG_FILE" "$PLUMOS_USER_ROOT/Logs/power-action-rootfs.log" 2>/dev/null || true
  fi
}

persist_final_log_to_user_storage() {
  source="$1"
  debug_mount=/run/plumos-power-log

  [ "$MIRROR_LOG" = "1" ] || return 0
  if is_mounted_path "$PLUMOS_USER_ROOT"; then
    mkdir -p "$PLUMOS_USER_ROOT/Logs" 2>/dev/null || true
    cp "$LOG_FILE" "$PLUMOS_USER_ROOT/Logs/power-action-rootfs-final.log" \
      2>/dev/null || true
    sync 2>/dev/null || true
    return 0
  fi
  [ -n "$source" ] && [ -b "$source" ] || return 0
  mkdir -p "$debug_mount" 2>/dev/null || true
  if mount -t vfat -o rw,utf8,shortname=mixed "$source" "$debug_mount" \
      2>> "$LOG_FILE"; then
    mkdir -p "$debug_mount/Logs" 2>/dev/null || true
    cp "$LOG_FILE" "$debug_mount/Logs/power-action-rootfs-final.log" \
      2>/dev/null || true
    sync 2>/dev/null || true
    umount "$debug_mount" 2>> "$LOG_FILE" || true
  fi
}

record_clean_shutdown() {
  verified="$PLUMOS_ROOT/provision/system-a.verified.sha256"
  complete="$PLUMOS_ROOT/provision/complete"
  ready="$PLUMOS_USER_ROOT/.plumos-ready"
  if [ ! -s "$verified" ] || [ ! -f "$complete" ] || [ ! -f "$ready" ]; then
    log "quiesce: clean-shutdown marker skipped reason=runtime_not_verified"
    return 0
  fi
  if ! : > "$PLUMOS_ROOT/provision/clean-shutdown"; then
    log "quiesce: clean-shutdown marker failed target=p3"
    return 0
  fi
  if ! : > "$PLUMOS_USER_ROOT/.plumos-clean-shutdown"; then
    log "quiesce: clean-shutdown marker failed target=p4"
    rm -f "$PLUMOS_ROOT/provision/clean-shutdown" 2>/dev/null || true
    return 0
  fi
  CLEAN_MARKERS_RECORDED=1
  log "quiesce: clean-shutdown markers recorded p3=1 p4=1"
}

retry_persistent_unmount() {
  target="$1"
  log "umount: retry target=$target after refreshing persistent users"
  stop_persistent_storage_users
  sleep 0.2 2>/dev/null || true
  unmount_if_mounted "$target"
}

remount_app_layer_ro() {
  is_mounted_path "$PLUMOS_ROOT" || return 0
  log "quiesce: remount-ro begin source=$(mount_source_for_path "$PLUMOS_ROOT" || true)"
  mount -o remount,ro "$PLUMOS_ROOT" 2>> "$LOG_FILE" && {
    log "quiesce: remount-ro done"
    return 0
  }
  log "quiesce: remount-ro failed"
  return 1
}

unmount_persistent_storage_for_final_action() {
  p4_clean=1
  p3_clean=1
  user_storage_mount=""
  user_storage_source=""

  [ "$FINAL_UNMOUNT" = "1" ] || { log "quiesce: unmount disabled"; return 0; }
  [ "$DRY_RUN" -eq 0 ] || { log "quiesce: dry-run"; return 0; }

  QUIESCE_CLEAN=0
  user_storage_mount="$(mount_source_for_path "$PLUMOS_USER_ROOT" || true)"
  user_storage_source="${user_storage_mount%% *}"
  log "quiesce: begin root=$PLUMOS_ROOT"
  stop_sd2_mounts
  stop_app_layer_writers
  stop_persistent_storage_users
  record_clean_shutdown
  mirror_log_to_app_layer
  sync_once

  unmount_if_mounted "$PLUMOS_ROOT/themes-user" || true
  unmount_if_mounted "$PLUMOS_ROOT/Images" || true
  unmount_if_mounted "$PLUMOS_ROOT/bios" || true
  unmount_if_mounted "$PLUMOS_ROOT/roms" || true
  unmount_if_mounted /boot || true
  mirror_log_to_app_layer
  if ! unmount_if_mounted "$PLUMOS_USER_ROOT"; then
    if ! retry_persistent_unmount "$PLUMOS_USER_ROOT"; then
      p4_clean=0
      rm -f "$PLUMOS_USER_ROOT/.plumos-clean-shutdown" 2>/dev/null || true
      sync 2>/dev/null || true
    fi
  fi

  if ! unmount_if_mounted "$PLUMOS_ROOT"; then
    log_plumos_blockers
    mirror_log_to_app_layer
    if ! retry_persistent_unmount "$PLUMOS_ROOT"; then
      p3_clean=0
      rm -f "$PLUMOS_ROOT/provision/clean-shutdown" 2>/dev/null || true
      sync 2>/dev/null || true
      log_plumos_blockers
      mirror_log_to_app_layer
      remount_app_layer_ro || true
    fi
  fi
  unmount_if_mounted "$PLUMOS_BOOT_ROOT" || true
  if [ "$CLEAN_MARKERS_RECORDED" -eq 1 ] &&
     [ "$p4_clean" -eq 1 ] && [ "$p3_clean" -eq 1 ]; then
    QUIESCE_CLEAN=1
    log "quiesce: clean unmount complete"
  else
    log "quiesce: clean unmount failed p4=$p4_clean p3=$p3_clean"
    persist_final_log_to_user_storage "$user_storage_source"
  fi
}

prepare_sysrq_final_action() {
  [ "$DRY_RUN" -eq 0 ] || return 0
  [ -w /proc/sysrq-trigger ] || return 0
  if [ "$QUIESCE_CLEAN" -eq 1 ]; then
    log "sysrq: extra sync/remount skipped after clean unmount"
    return 0
  fi
  log "sysrq: syncing filesystems"
  echo 1 >/proc/sys/kernel/sysrq 2>/dev/null || true
  echo s >/proc/sysrq-trigger 2>/dev/null || true
  sleep 1 2>/dev/null || true
  log "sysrq: remounting filesystems read-only"
  echo u >/proc/sysrq-trigger 2>/dev/null || true
  sleep 1 2>/dev/null || true
}

set_wakealarm() {
  [ "$WAKEUP_SEC" -gt 0 ] || return 0
  [ -e /sys/class/rtc/rtc0/wakealarm ] || return 0
  if [ "$DRY_RUN" -eq 1 ]; then
    log "sleep: dry-run wakealarm +$WAKEUP_SEC"
    return 0
  fi
  echo 0 >/sys/class/rtc/rtc0/wakealarm 2>/dev/null || true
  echo "+$WAKEUP_SEC" >/sys/class/rtc/rtc0/wakealarm 2>/dev/null || true
}

trigger_sysrq() {
  key="$1"
  name="$2"
  if [ "$DRY_RUN" -eq 1 ]; then
    log "sysrq: dry-run action=$name key=$key"
    echo "result=dry_run_$name"
    return 0
  fi
  if [ ! -w /proc/sysrq-trigger ]; then
    log "sysrq: unavailable action=$name"
    echo "result=${name}_failed"
    return 1
  fi
  log "sysrq: trigger action=$name key=$key"
  echo 1 >/proc/sys/kernel/sysrq 2>/dev/null || true
  echo "$key" >/proc/sysrq-trigger
  sleep 2 2>/dev/null || true
  log "sysrq: returned action=$name"
  echo "result=${name}_returned"
  return 1
}

sleep_action() {
  safe_sync
  case "$SLEEP_BACKEND" in
    none)
      log "sleep: backend=none"
      echo "result=sleep_backend_none"
      return 0
      ;;
    mem|standby|freeze)
      if ! grep -qw "$SLEEP_BACKEND" /sys/power/state 2>/dev/null; then
        log "sleep: unsupported backend=$SLEEP_BACKEND states=$(cat /sys/power/state 2>/dev/null || echo none)"
        echo "result=sleep_unsupported"
        return 1
      fi
      set_wakealarm
      log "sleep: backend=$SLEEP_BACKEND"
      if [ "$DRY_RUN" -eq 1 ]; then
        echo "result=dry_run_sleep"
        return 0
      fi
      echo "$SLEEP_BACKEND" >/sys/power/state
      echo "result=sleep_returned"
      return 0
      ;;
  esac
}

reboot_action() {
  log "reboot: requested backend=$POWER_BACKEND"
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "result=dry_run_reboot"
    return 0
  fi
  unmount_persistent_storage_for_final_action
  prepare_sysrq_final_action
  trigger_sysrq b reboot
}

shutdown_action() {
  if [ "$POWER_OFF" -eq 0 ]; then
    safe_sync
    log "shutdown: sync-only no-poweroff"
    echo "result=shutdown_sync_only"
    return 0
  fi
  log "poweroff: requested backend=$POWER_BACKEND"
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "result=dry_run_poweroff"
    return 0
  fi
  unmount_persistent_storage_for_final_action
  prepare_sysrq_final_action
  trigger_sysrq o poweroff
}

log "start action=$ACTION poweroff=$POWER_OFF dry_run=$DRY_RUN power_backend=$POWER_BACKEND sleep_backend=$SLEEP_BACKEND root=$PLUMOS_ROOT"

case "$ACTION" in
  sleep)
    sleep_action
    ;;
  reboot)
    reboot_action
    ;;
  shutdown)
    shutdown_action
    ;;
esac
