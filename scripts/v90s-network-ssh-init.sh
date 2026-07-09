#!/bin/sh
set -u

PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH

LOG=/tmp/plumos-v90s-network-ssh.log
FAT_LOG_DIR=/boot/plumos-logs
FAT_LOG=
SHARE_LOG=
SSHD_LOG=/tmp/plumos-v90s-sshd.log
WPA_CONF=/etc/wpa_supplicant/wpa_supplicant.conf

if [ -d "$FAT_LOG_DIR" ] && [ -w "$FAT_LOG_DIR" ]; then
    FAT_LOG="$FAT_LOG_DIR/plumos-v90s-network-ssh.log"
    : > "$FAT_LOG" 2>/dev/null || true
fi

if [ -d /mnt/share ] && [ -w /mnt/share ]; then
    SHARE_LOG=/mnt/share/plumos-v90s-network-ssh.log
    : > "$SHARE_LOG" 2>/dev/null || true
fi

: > "$LOG" 2>/dev/null || true

mirror_log() {
    [ -n "$FAT_LOG" ] && cp "$LOG" "$FAT_LOG" 2>/dev/null || true
    [ -n "$SHARE_LOG" ] && cp "$LOG" "$SHARE_LOG" 2>/dev/null || true
    if [ -d /mnt/share/rootfs ]; then
        cp "$LOG" /mnt/share/rootfs/plumos-v90s-network-ssh.log 2>/dev/null || true
    fi
    sync 2>/dev/null || true
}

log() {
    echo "$*"
    echo "$*" >> "$LOG" 2>/dev/null || true
    mirror_log
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

run_limited_cmd() {
    label="$1"
    seconds="$2"
    shift 2

    {
        echo ""
        echo "===== $label ====="
        if command -v timeout >/dev/null 2>&1; then
            timeout "$seconds" "$@" 2>&1
        else
            "$@" 2>&1
        fi
        rc=$?
        echo "===== $label rc=$rc ====="
    } >> "$LOG" 2>/dev/null || true
    mirror_log
}

load_module_file() {
    ko="$1"
    [ -f "$ko" ] || {
        log "network-ssh: module file missing: $ko"
        return 0
    }
    run_limited_cmd "insmod-$(basename "$ko")" 8 insmod "$ko"
}

detect_usb_wifi_modules() {
    tmp=/tmp/plumos-v90s-usb-wifi-modules.txt
    : > "$tmp" 2>/dev/null || true

    for dev in /sys/bus/usb/devices/*; do
        [ -r "$dev/idVendor" ] || continue
        [ -r "$dev/idProduct" ] || continue
        vendor="$(tr '[:lower:]' '[:upper:]' < "$dev/idVendor" 2>/dev/null || true)"
        product="$(tr '[:lower:]' '[:upper:]' < "$dev/idProduct" 2>/dev/null || true)"
        [ -n "$vendor" ] || continue
        [ -n "$product" ] || continue

        for alias_file in /lib/modules/4.9.191/modules.alias /lib/modules/4.9.191/modules.alias.standard /lib/modules/4.9.191/modules.alias.v90s; do
            [ -r "$alias_file" ] || continue
            grep -i "usb:v${vendor}p${product}" "$alias_file" 2>/dev/null | awk '{ print $3 }' >> "$tmp" 2>/dev/null || true
        done
    done

    grep -E '^(rtl8192cu|rtl8xxxu|8192eu|8723bu|8812au|8821cu|88x2bu|8188eu)$' "$tmp" 2>/dev/null | sort -u
}

load_wifi_driver() {
    driver="$1"

    case "$driver" in
        rtl8192cu)
            load_module_file /lib/modules/4.9.191/rtlwifi.ko
            load_module_file /lib/modules/4.9.191/rtl_usb.ko
            load_module_file /lib/modules/4.9.191/rtl8192c-common.ko
            load_module_file /lib/modules/4.9.191/rtl8192cu.ko
            ;;
        rtl8xxxu)
            load_module_file /lib/modules/4.9.191/rtl8xxxu.ko
            ;;
        8192eu|8723bu|8812au|8821cu|88x2bu)
            load_module_file "/lib/modules/4.9.191/extra/${driver}.ko"
            ;;
        8188eu)
            if [ -f /lib/modules/4.9.191/extra/8188eu.ko ]; then
                load_module_file /lib/modules/4.9.191/extra/8188eu.ko
            else
                log "network-ssh: KNULLI service mentions 8188eu, but this V90S overlay only has 8192eu"
                load_module_file /lib/modules/4.9.191/extra/8192eu.ko
            fi
            ;;
        *)
            log "network-ssh: unsupported wifi driver candidate: $driver"
            ;;
    esac
}

load_wifi_modules() {
    append_cmd "usb-devices-before-wifi" sh -c 'command -v lsusb >/dev/null 2>&1 && lsusb 2>&1 || true; cat /proc/bus/usb/devices 2>/dev/null || true; find /sys/bus/usb/devices -maxdepth 2 -type f \( -name idVendor -o -name idProduct -o -name manufacturer -o -name product \) -print -exec cat {} \; 2>/dev/null || true'
    append_cmd "wifi-firmware-files" sh -c 'ls -l /lib/firmware/*xr829* /lib/firmware/*8723* /lib/firmware/rtlwifi/* 2>/dev/null || true'
    append_cmd "wifi-module-files" sh -c 'find /lib/modules/4.9.191 -name "*.ko" 2>/dev/null | grep -E "8723|8192|88|xradio|rtl|wireless|cfg80211|mac80211" || true'

    if command -v rfkill >/dev/null 2>&1; then
        rfkill unblock all >> "$LOG" 2>&1 || true
    fi

    log "network-ssh: loading USB Wi-Fi modules"

    drivers="$(detect_usb_wifi_modules | tr '\n' ' ')"
    if [ -z "$drivers" ]; then
        log "network-ssh: no USB Wi-Fi module alias matched; leaving module load disabled for this run"
        return 0
    fi

    log "network-ssh: usb_wifi_driver_candidates=$drivers"
    for driver in $drivers; do
        load_wifi_driver "$driver"
    done

    mirror_log
}

find_wifi_iface() {
    for net in /sys/class/net/*; do
        [ -e "$net" ] || continue
        iface="$(basename "$net")"
        [ "$iface" = "lo" ] && continue
        if [ -d "$net/wireless" ] || [ -e "$net/phy80211" ]; then
            printf '%s\n' "$iface"
            return 0
        fi
    done

    for iface in wlan0 wlan1 mlan0 p2p0; do
        [ -e "/sys/class/net/$iface" ] && printf '%s\n' "$iface" && return 0
    done

    return 1
}

wait_wifi_iface() {
    i=0
    while [ "$i" -lt 30 ]; do
        if iface="$(find_wifi_iface 2>/dev/null)"; then
            printf '%s\n' "$iface"
            return 0
        fi
        sleep 1
        i=$((i + 1))
    done
    return 1
}

start_wifi() {
    if [ ! -f "$WPA_CONF" ]; then
        log "network-ssh: no WPA config present"
        return 0
    fi

    if ! command -v wpa_supplicant >/dev/null 2>&1; then
        log "network-ssh: wpa_supplicant missing"
        return 1
    fi

    load_wifi_modules
    append_cmd "net-after-module-load" sh -c 'ip link 2>/dev/null || true; cat /proc/modules 2>/dev/null | grep -E "8723|8192|88|xradio|rtl|cfg80211|mac80211" || true; dmesg 2>/dev/null | tail -80 || true'

    if ! iface="$(wait_wifi_iface 2>/dev/null)"; then
        log "network-ssh: no Wi-Fi interface found"
        return 1
    fi

    log "network-ssh: wifi_iface=$iface"
    ip link set "$iface" up >> "$LOG" 2>&1 || true
    mkdir -p /run/wpa_supplicant
    killall wpa_supplicant >> "$LOG" 2>&1 || true
    wpa_supplicant -B -i "$iface" -c "$WPA_CONF" >> "$LOG" 2>&1 || true
    mirror_log

    i=0
    while [ "$i" -lt 30 ]; do
        if command -v wpa_cli >/dev/null 2>&1; then
            wpa_cli -i "$iface" status >> "$LOG" 2>&1 || true
            if wpa_cli -i "$iface" status 2>/dev/null | grep -q 'wpa_state=COMPLETED'; then
                log "network-ssh: WPA completed"
                break
            fi
        fi
        sleep 1
        i=$((i + 1))
    done

    if command -v dhclient >/dev/null 2>&1; then
        if command -v timeout >/dev/null 2>&1; then
            timeout 35 dhclient -v -1 "$iface" >> "$LOG" 2>&1 || true
        else
            dhclient -v -1 "$iface" >> "$LOG" 2>&1 || true
        fi
    fi

    append_cmd "net-final" sh -c 'ip addr 2>/dev/null || true; ip route 2>/dev/null || true; cat /etc/resolv.conf 2>/dev/null || true'
    write_connect_hint "$iface"
}

prepare_sshd_host_keys() {
    SSHD_HOST_ARGS=
    for type in rsa ecdsa ed25519; do
        key="/etc/ssh/ssh_host_${type}_key"
        if [ -s "$key" ]; then
            SSHD_HOST_ARGS="$SSHD_HOST_ARGS -h $key"
        fi
    done

    if [ -n "$SSHD_HOST_ARGS" ]; then
        return 0
    fi

    if [ -d /mnt/share ] && [ -w /mnt/share ] && command -v ssh-keygen >/dev/null 2>&1; then
        mkdir -p /mnt/share/ssh-host-keys
        [ -s /mnt/share/ssh-host-keys/ssh_host_rsa_key ] || ssh-keygen -q -t rsa -N '' -f /mnt/share/ssh-host-keys/ssh_host_rsa_key >> "$LOG" 2>&1 || true
        [ -s /mnt/share/ssh-host-keys/ssh_host_ecdsa_key ] || ssh-keygen -q -t ecdsa -N '' -f /mnt/share/ssh-host-keys/ssh_host_ecdsa_key >> "$LOG" 2>&1 || true
        [ -s /mnt/share/ssh-host-keys/ssh_host_ed25519_key ] || ssh-keygen -q -t ed25519 -N '' -f /mnt/share/ssh-host-keys/ssh_host_ed25519_key >> "$LOG" 2>&1 || true
        for type in rsa ecdsa ed25519; do
            key="/mnt/share/ssh-host-keys/ssh_host_${type}_key"
            [ -s "$key" ] && SSHD_HOST_ARGS="$SSHD_HOST_ARGS -h $key"
        done
    fi
}

start_sshd() {
    if ! command -v sshd >/dev/null 2>&1; then
        log "network-ssh: sshd missing"
        return 1
    fi

    mkdir -p /run/sshd
    prepare_sshd_host_keys
    if [ -z "$SSHD_HOST_ARGS" ]; then
        log "network-ssh: no SSH host keys available"
        return 1
    fi

    killall sshd >> "$LOG" 2>&1 || true
    # shellcheck disable=SC2086
    /usr/sbin/sshd $SSHD_HOST_ARGS -E "$SSHD_LOG" >> "$LOG" 2>&1 || true
    append_cmd "sshd-state" sh -c 'ps w 2>/dev/null | grep -E "[s]shd" || true; cat /tmp/plumos-v90s-sshd.log 2>/dev/null || true'
}

write_connect_hint() {
    iface="$1"
    [ -n "$FAT_LOG_DIR" ] || return 0
    [ -d "$FAT_LOG_DIR" ] || return 0

    hint="$FAT_LOG_DIR/ssh-connect.txt"
    {
        echo "plumOS V90S SSH"
        echo "interface=$iface"
        ip -4 addr show "$iface" 2>/dev/null | awk '/inet / { sub(/\/.*/, "", $2); print "ssh root@" $2 }'
        echo "user=root"
        echo "auth=public-key-or-password"
    } > "$hint" 2>/dev/null || true
    sync 2>/dev/null || true
}

log "network-ssh: entered"
append_cmd "network-release" sh -c 'cat /etc/plumos-network-release 2>/dev/null || true'
start_sshd || true
start_wifi || true
mirror_log
log "network-ssh: finished"
exit 0
