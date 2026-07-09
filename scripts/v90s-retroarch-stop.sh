#!/bin/sh
set -u

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH

RUN_DIR="${PLUMOS_V90S_RUN_DIR:-/run/plumos-v90s}"
RETROARCH_PID_FILE="$RUN_DIR/retroarch.pid"
LAUNCHER_PID_FILE="$RUN_DIR/retroarch-launch.pid"
STOP_WAIT_SECONDS="${PLUMOS_V90S_STOP_WAIT_SECONDS:-5}"
ACTION="${1:-stop}"

log() {
    echo "retroarch-stop: $*"
}

read_pidfile() {
    pidfile="$1"
    [ -r "$pidfile" ] || return 1
    pid="$(sed -n '1p' "$pidfile" 2>/dev/null | tr -d '[:space:]')"
    case "$pid" in
        ''|*[!0-9]*)
            return 1
            ;;
    esac
    printf '%s\n' "$pid"
}

pid_cmdline() {
    pid="$1"
    [ -r "/proc/$pid/cmdline" ] || return 1
    tr '\000' ' ' < "/proc/$pid/cmdline" 2>/dev/null
}

pid_comm() {
    pid="$1"
    [ -r "/proc/$pid/comm" ] || return 1
    cat "/proc/$pid/comm" 2>/dev/null
}

process_matches() {
    pid="$1"
    matcher="$2"

    case "$matcher" in
        retroarch-runtime)
            comm="$(pid_comm "$pid" 2>/dev/null || true)"
            cmdline="$(pid_cmdline "$pid" 2>/dev/null || true)"
            case "$comm" in
                retroarch|retroarch-knull|retroarch-knulli)
                    ;;
                *)
                    return 1
                    ;;
            esac
            case "$cmdline" in
                *"/tmp/retroarch-v90s.cfg"*)
                    return 0
                    ;;
            esac
            return 1
            ;;
        comm:*)
            expected="${matcher#comm:}"
            comm="$(pid_comm "$pid" 2>/dev/null || true)"
            [ "$comm" = "$expected" ]
            return $?
            ;;
        cmdline:*)
            needle="${matcher#cmdline:}"
            ;;
        *)
            return 1
            ;;
    esac

    cmdline="$(pid_cmdline "$pid" 2>/dev/null || true)"
    case "$cmdline" in
        *"$needle"*)
            return 0
            ;;
    esac
    return 1
}

pidfile_matches_pid() {
    pidfile="$1"
    expected="$2"
    current="$(read_pidfile "$pidfile" 2>/dev/null || true)"
    [ "$current" = "$expected" ]
}

remove_pidfile_if_matches() {
    pidfile="$1"
    expected="$2"
    if pidfile_matches_pid "$pidfile" "$expected"; then
        rm -f "$pidfile" 2>/dev/null || true
    fi
}

wait_pid_exit() {
    pid="$1"
    limit="$2"
    i=0
    while [ "$i" -lt "$limit" ]; do
        if ! kill -0 "$pid" 2>/dev/null; then
            return 0
        fi
        sleep 1
        i=$((i + 1))
    done
    return 1
}

describe_process() {
    pid="$1"
    comm="$(pid_comm "$pid" 2>/dev/null || true)"
    cmdline="$(pid_cmdline "$pid" 2>/dev/null || true)"
    printf "comm='%s' cmdline='%s'" "$comm" "$cmdline"
}

status_pidfile() {
    pidfile="$1"
    matcher="$2"
    label="$3"

    pid="$(read_pidfile "$pidfile" 2>/dev/null || true)"
    if [ -z "$pid" ]; then
        log "$label: no pidfile"
        return 1
    fi

    if ! kill -0 "$pid" 2>/dev/null; then
        log "$label: pid=$pid not running"
        return 1
    fi

    if ! process_matches "$pid" "$matcher"; then
        detail="$(describe_process "$pid")"
        log "$label: pid=$pid refused; $detail"
        return 1
    fi

    detail="$(describe_process "$pid")"
    log "$label: pid=$pid running $detail"
    return 0
}

stop_pidfile() {
    pidfile="$1"
    matcher="$2"
    label="$3"

    pid="$(read_pidfile "$pidfile" 2>/dev/null || true)"
    if [ -z "$pid" ]; then
        log "$label: no pidfile"
        return 0
    fi

    if ! kill -0 "$pid" 2>/dev/null; then
        log "$label: pid=$pid already stopped"
        remove_pidfile_if_matches "$pidfile" "$pid"
        return 0
    fi

    if ! process_matches "$pid" "$matcher"; then
        detail="$(describe_process "$pid")"
        log "$label: refusing to stop pid=$pid; $detail"
        return 1
    fi

    log "$label: sending TERM to pid=$pid"
    kill -TERM "$pid" 2>/dev/null || true
    if ! wait_pid_exit "$pid" "$STOP_WAIT_SECONDS"; then
        log "$label: sending KILL to pid=$pid"
        kill -KILL "$pid" 2>/dev/null || true
        wait_pid_exit "$pid" 2 || true
    fi
    remove_pidfile_if_matches "$pidfile" "$pid"
}

case "$ACTION" in
    status)
        status_pidfile "$RETROARCH_PID_FILE" "retroarch-runtime" "RetroArch" || true
        status_pidfile "$LAUNCHER_PID_FILE" "cmdline:v90s-retroarch-launch" "launcher" || true
        ;;
    stop)
        stop_pidfile "$RETROARCH_PID_FILE" "retroarch-runtime" "RetroArch"
        stop_pidfile "$LAUNCHER_PID_FILE" "cmdline:v90s-retroarch-launch" "launcher"
        ;;
    *)
        echo "Usage: v90s-retroarch-stop.sh [stop|status]" >&2
        exit 2
        ;;
esac
