#!/bin/sh
set -u

PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH

FAT_LOG_DIR=/boot/plumos-logs
SHARE_DIR=/mnt/share
LOG=/tmp/plumos-v90s-pvr-probe.log
SHARE_LOG=

if [ -d "$FAT_LOG_DIR" ] && [ -w "$FAT_LOG_DIR" ]; then
    LOG="$FAT_LOG_DIR/plumos-v90s-pvr-probe.log"
fi

if [ -d "$SHARE_DIR" ] && [ -w "$SHARE_DIR" ]; then
    SHARE_LOG="$SHARE_DIR/plumos-v90s-pvr-probe.log"
fi

: > "$LOG" 2>/dev/null || true
[ -n "$SHARE_LOG" ] && : > "$SHARE_LOG" 2>/dev/null || true

log_count=0

log() {
    line="$*"
    echo "$line"
    echo "$line" >> "$LOG" 2>/dev/null || true
    if [ -n "$SHARE_LOG" ] && [ "$SHARE_LOG" != "$LOG" ]; then
        echo "$line" >> "$SHARE_LOG" 2>/dev/null || true
    fi
    log_count=$((log_count + 1))
    if [ "$log_count" -lt 30 ] || [ $((log_count % 10)) -eq 0 ]; then
        sync 2>/dev/null || true
    fi
}

mirror_log() {
    if [ -n "$SHARE_LOG" ] && [ "$SHARE_LOG" != "$LOG" ]; then
        cp "$LOG" "$SHARE_LOG" 2>/dev/null || true
    fi
    if [ -d "$SHARE_DIR/rootfs" ]; then
        cp "$LOG" "$SHARE_DIR/rootfs/plumos-v90s-pvr-probe.log" 2>/dev/null || true
    fi
    sync 2>/dev/null || true
}

append_cmd() {
    label="$1"
    shift
    {
        echo ""
        echo "===== $label ====="
        "$@" 2>&1
        echo "===== $label rc=$? ====="
    } >> "$LOG" 2>/dev/null || true
    mirror_log
}

run_timeout() {
    label="$1"
    seconds="$2"
    shift 2
    if command -v timeout >/dev/null 2>&1; then
        append_cmd "$label" timeout "$seconds" "$@"
    else
        append_cmd "$label" "$@"
    fi
}

start_pvrsrvctl() {
    label="$1"
    run_timeout "$label" 8 sh -c 'cd /lib/modules/4.9.191 && /usr/bin/pvrsrvctl --start'
}

module_loaded() {
    name="$1"
    grep -qw "^$name" /proc/modules 2>/dev/null
}

try_insmod() {
    module="$1"
    name="$(basename "$module" .ko)"
    if module_loaded "$name"; then
        log "pvr-probe: module already loaded: $name"
        return 0
    fi
    if [ ! -f "$module" ]; then
        log "pvr-probe: module missing: $module"
        return 0
    fi
    append_cmd "insmod-$name" insmod "$module"
}

dump_tree() {
    path="$1"
    if [ -e "$path" ]; then
        append_cmd "tree-$path" sh -c 'p="$1"; find "$p" -maxdepth 3 -print 2>/dev/null | sort; for f in "$p"/* "$p"/*/*; do [ -f "$f" ] && [ -r "$f" ] && { echo "--- $f"; head -80 "$f" 2>/dev/null || true; }; done' sh "$path"
    else
        log "pvr-probe: missing tree path: $path"
    fi
}

log "pvr-probe: entered"
log "pvr-probe: log=$LOG"
log "pvr-probe: uname=$(uname -a 2>/dev/null || true)"

if [ -d /usr/lib/powervr ]; then
    export LD_LIBRARY_PATH="/usr/lib/powervr:/usr/lib/aarch64-linux-gnu:/usr/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    log "pvr-probe: LD_LIBRARY_PATH=$LD_LIBRARY_PATH"
fi

append_cmd "cmdline" cat /proc/cmdline
append_cmd "mount" mount
append_cmd "fb-devices" sh -c 'ls -l /dev/fb* /sys/class/graphics/fb0/* 2>/dev/null || true'
append_cmd "pvr-files" sh -c 'ls -l /usr/bin/pvrsrvctl /usr/lib/powervr/libEGL.so /usr/lib/powervr/libGLESv2.so /usr/lib/powervr/firmware/* /lib/firmware/rgx.* /lib/modules/4.9.191/*.ko 2>/dev/null || true'
append_cmd "pvr-strings" sh -c 'command -v strings >/dev/null 2>&1 && strings /usr/bin/pvrsrvctl 2>/dev/null | grep -E "pvrsrv|/proc/pvr|/sys/kernel/debug/pvr|DriverMode|RGXBVNC" || true'
append_cmd "debugfs-mount" sh -c 'mkdir -p /sys/kernel/debug; mountpoint -q /sys/kernel/debug 2>/dev/null || mount -t debugfs debugfs /sys/kernel/debug 2>/dev/null || true; mount | grep debug || true'
append_cmd "devices-before" sh -c 'ls -l /dev/pvr* /dev/pvrsrvkm /dev/dri/* 2>/dev/null || true; cat /proc/devices 2>/dev/null | grep -E "pvr|drm|fb" || true; cat /proc/modules 2>/dev/null | grep -E "pvr|dc_sunxi|sunxi" || true'
append_cmd "dmesg-before" sh -c 'dmesg 2>/dev/null | tail -160 || true'

if [ -x /usr/bin/pvrsrvctl ]; then
    start_pvrsrvctl "pvrsrvctl-start-cwd-moddir"
else
    log "pvr-probe: /usr/bin/pvrsrvctl is missing or not executable"
fi

if ! module_loaded pvrsrvkm || ! module_loaded dc_sunxi; then
    try_insmod /lib/modules/4.9.191/pvrsrvkm.ko
    try_insmod /lib/modules/4.9.191/dc_sunxi.ko
    if [ -x /usr/bin/pvrsrvctl ]; then
        start_pvrsrvctl "pvrsrvctl-start-after-insmod-cwd-moddir"
    fi
fi

append_cmd "devices-after-insmod" sh -c 'ls -l /dev/pvr* /dev/pvrsrvkm /dev/dri/* 2>/dev/null || true; cat /proc/devices 2>/dev/null | grep -E "pvr|drm|fb" || true; cat /proc/modules 2>/dev/null | grep -E "pvr|dc_sunxi|sunxi" || true'
append_cmd "dmesg-after-insmod" sh -c 'dmesg 2>/dev/null | tail -220 || true'

if [ -x /usr/bin/pvrsrvctl ]; then
    run_timeout "pvrsrvctl-help" 8 /usr/bin/pvrsrvctl --help
fi

append_cmd "devices-after-pvrsrvctl" sh -c 'ls -l /dev/pvr* /dev/pvrsrvkm /dev/dri/* 2>/dev/null || true; cat /proc/devices 2>/dev/null | grep -E "pvr|drm|fb" || true; cat /proc/modules 2>/dev/null | grep -E "pvr|dc_sunxi|sunxi" || true'
dump_tree /proc/pvr
dump_tree /sys/kernel/debug/pvr
append_cmd "dmesg-final" sh -c 'dmesg 2>/dev/null | tail -260 || true'

log "pvr-probe: finished"
mirror_log
exit 0
