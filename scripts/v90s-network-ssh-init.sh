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

load_wifi_modules() {
    append_cmd "wifi-firmware-files" sh -c 'ls -l /lib/firmware/*xr829* /lib/firmware/*8723* /lib/firmware/rtlwifi/* 2>/dev/null || true'
    append_cmd "wifi-module-files" sh -c 'find /lib/modules/4.9.191 -name "*.ko" 2>/dev/null | grep -E "8723|8192|88|xradio|rtl|wireless|cfg80211|mac80211" || true'

    if command -v rfkill >/dev/null 2>&1; then
        rfkill unblock all >> "$LOG" 2>&1 || true
    fi

    if command -v depmod >/dev/null 2>&1; then
        depmod -a 4.9.191 >> "$LOG" 2>&1 || true
    fi

    for mod in 8723ds 8723bu 8192eu 8821cu 8812au 88x2bu rtl8192cu rtl8xxxu; do
        modprobe "$mod" >> "$LOG" 2>&1 || true
    done

    for ko in \
        /lib/modules/4.9.191/xradio_mac.ko \
        /lib/modules/4.9.191/xradio_core.ko \
        /lib/modules/4.9.191/xradio_wlan.ko \
        /lib/modules/4.9.191/xradio_mac_tsp.ko \
        /lib/modules/4.9.191/xradio_core_tsp.ko \
        /lib/modules/4.9.191/xradio_wlan_tsp.ko
    do
        [ -f "$ko" ] && insmod "$ko" >> "$LOG" 2>&1 || true
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
start_wifi || true
start_sshd || true
mirror_log
log "network-ssh: finished"
exit 0
