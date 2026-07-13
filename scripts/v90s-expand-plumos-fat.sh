#!/bin/sh
set -u

DEVICE=${PLUMOS_BLOCK_DEVICE:-/dev/mmcblk0}
PARTITION_NUMBER=${PLUMOS_PARTITION_NUMBER:-7}
PARTITION=${PLUMOS_PARTITION_DEVICE:-${DEVICE}p${PARTITION_NUMBER}}
PLUMOS_ROOT=${PLUMOS_ROOT:-/mnt/plumos}
TARGET_SIZE_MIB=${PLUMOS_TARGET_SIZE_MIB:-4096}
PARTED=${PLUMOS_PARTED:-parted}
PARTPROBE=${PLUMOS_PARTPROBE:-partprobe}
FATRESIZE=${PLUMOS_FATRESIZE:-fatresize}
FSCK_FAT=${PLUMOS_FSCK_FAT:-fsck.fat}
MKFS_FAT=${PLUMOS_MKFS_FAT:-mkfs.fat}
FUSER=${PLUMOS_FUSER:-fuser}
MOUNT=${PLUMOS_MOUNT:-/bin/mount}
UMOUNT=${PLUMOS_UMOUNT:-/bin/umount}
LOG=${PLUMOS_RESIZE_LOG:-/tmp/plumos-fat-resize.log}
REFORMAT=${PLUMOS_REFORMAT:-0}

log() {
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || true)" "$*" >>"$LOG"
}

run() {
    log "run: $*"
    "$@" >>"$LOG" 2>&1
}

mount_plumos() {
    grep -q " ${PLUMOS_ROOT} " /proc/mounts 2>/dev/null && return 0
    mkdir -p "$PLUMOS_ROOT"
    "$MOUNT" -t vfat -o rw,fmask=0022,dmask=0022,shortname=mixed,utf8,errors=remount-ro \
        "$PARTITION" "$PLUMOS_ROOT" >>"$LOG" 2>&1
}

finish_and_reboot() {
    status=$1
    set +e
    mount_plumos
    if grep -q " ${PLUMOS_ROOT} " /proc/mounts 2>/dev/null; then
        mkdir -p "${PLUMOS_ROOT}/Logs"
        cp "$LOG" "${PLUMOS_ROOT}/Logs/plumos-fat-resize.log"
    fi
    sync
    if [ "$status" -eq 0 ]; then
        log "resize complete; rebooting"
    else
        log "resize failed rc=${status}; rebooting for recovery"
    fi
    if [ -x /sbin/reboot ]; then
        /sbin/reboot -f
    elif [ -x /bin/busybox ]; then
        /bin/busybox reboot -f
    else
        log "reboot command unavailable"
    fi
    exit "$status"
}

fail() {
    rc=$1
    log "failure rc=${rc}"
    finish_and_reboot "$rc"
}

: >"$LOG"
log "device=${DEVICE} partition=${PARTITION} target_mib=${TARGET_SIZE_MIB}"

required_tools="$PARTED $FSCK_FAT $FUSER"
if [ "$REFORMAT" = 1 ]; then
    required_tools="$required_tools $MKFS_FAT"
else
    required_tools="$required_tools $FATRESIZE"
fi
for required in $required_tools; do
    [ -x "$required" ] || command -v "$required" >/dev/null 2>&1 || {
        log "missing tool: ${required}"
        exit 127
    }
done

start_sector=$(
    "$PARTED" -sm "$DEVICE" unit s print 2>>"$LOG" |
        awk -F: -v number="$PARTITION_NUMBER" '$1 == number {sub(/s$/, "", $2); print $2}'
)
[ -n "$start_sector" ] || fail 2

target_sectors=$((TARGET_SIZE_MIB * 2048))
target_end_sector=$((start_sector + target_sectors - 1))
disk_sectors=$(cat "/sys/class/block/$(basename "$DEVICE")/size" 2>/dev/null || echo 0)
[ "$target_end_sector" -lt "$disk_sectors" ] || fail 2
log "start_sector=${start_sector} target_end_sector=${target_end_sector}"

if [ -x "${PLUMOS_ROOT}/bin/plumos-frontend-stop" ]; then
    run "${PLUMOS_ROOT}/bin/plumos-frontend-stop" || true
fi
if [ -x "${PLUMOS_ROOT}/bin/plumos-network-services" ]; then
    for service in ftp sftp samba adb; do
        run "${PLUMOS_ROOT}/bin/plumos-network-services" stop "$service" || true
    done
fi

sync
cd /

for submount in "${PLUMOS_ROOT}/usb-transfer" "${PLUMOS_ROOT}/bios" \
    "${PLUMOS_ROOT}/roms"; do
    grep -q " ${submount} " /proc/mounts 2>/dev/null && run "$UMOUNT" "$submount" || true
done

# Wi-Fi/DHCP, SSH, or init helpers can briefly recreate a p7 user after the
# first stop pass. Drain exact fuser-reported PIDs and retry the unmount.
unmounted=0
attempt=1
while [ "$attempt" -le 10 ]; do
    pids=$($FUSER -m "$PLUMOS_ROOT" 2>/dev/null || true)
    for pid in $pids; do
        [ "$pid" = "$$" ] && continue
        cmdline=$(tr '\000' ' ' <"/proc/${pid}/cmdline" 2>/dev/null || true)
        log "holder attempt=${attempt} pid=${pid} cmd=${cmdline}"
        kill -TERM "$pid" 2>/dev/null || true
    done
    sleep 1
    pids=$($FUSER -m "$PLUMOS_ROOT" 2>/dev/null || true)
    for pid in $pids; do
        [ "$pid" = "$$" ] && continue
        kill -KILL "$pid" 2>/dev/null || true
    done
    sleep 1
    if "$UMOUNT" "$PLUMOS_ROOT" >>"$LOG" 2>&1; then
        unmounted=1
        break
    fi
    attempt=$((attempt + 1))
done
[ "$unmounted" -eq 1 ] || fail 1

current_sectors=$(cat "/sys/class/block/$(basename "$PARTITION")/size" 2>/dev/null || echo 0)
if [ "$current_sectors" -lt "$target_sectors" ]; then
    run "$PARTED" -s "$DEVICE" unit s resizepart "$PARTITION_NUMBER" "${target_end_sector}s" || fail $?
    run "$PARTPROBE" "$DEVICE" || true
fi

kernel_sectors=$(cat "/sys/class/block/$(basename "$PARTITION")/size" 2>/dev/null || echo 0)
log "kernel_partition_sectors=${kernel_sectors}"
[ "$kernel_sectors" -ge "$target_sectors" ] || fail 3

if [ "$REFORMAT" = 1 ]; then
    log "reformatting ${PARTITION} as FAT32 label=PLUMOS"
    run "$MKFS_FAT" -F 32 -n PLUMOS "$PARTITION" || fail $?
else
    run "$FSCK_FAT" -a "$PARTITION" || true
    run "$FATRESIZE" -s max -f "$PARTITION" || fail $?
    run "$FSCK_FAT" -a "$PARTITION" || true
fi
run mount_plumos || fail $?

filesystem_kib=$(df -k "$PLUMOS_ROOT" 2>/dev/null | awk 'NR == 2 {print $2}')
log "filesystem_kib=${filesystem_kib:-unknown}"
case "${filesystem_kib:-0}" in
    ''|*[!0-9]*) fail 4 ;;
esac
[ "$filesystem_kib" -ge 4000000 ] || fail 4

finish_and_reboot 0
