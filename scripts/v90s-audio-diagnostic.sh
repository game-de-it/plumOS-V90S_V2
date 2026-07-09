#!/bin/sh
set -u

PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH

LOG="${PLUMOS_V90S_AUDIO_LOG:-/tmp/plumos-v90s-audio-diagnostic.log}"
FAT_LOG_DIR="${PLUMOS_V90S_FAT_LOG_DIR:-/boot/plumos-logs}"
SHARE_DIR="${PLUMOS_V90S_SHARE_DIR:-/mnt/share}"
CARD="${PLUMOS_V90S_AUDIO_CARD:-0}"
DEVICE="${PLUMOS_V90S_AUDIO_DEVICE:-hw:0,0}"
TONE_SECONDS="${PLUMOS_V90S_AUDIO_TONE_SECONDS:-8}"

log() {
    line="$*"
    printf '%s\n' "$line"
    printf '%s\n' "$line" >> "$LOG" 2>/dev/null || true
}

append_cmd() {
    label="$1"
    shift
    {
        printf '\n===== %s =====\n' "$label"
        "$@" 2>&1
        printf '===== %s rc=%s =====\n' "$label" "$?"
    } >> "$LOG" 2>/dev/null || true
}

mirror_log() {
    if [ -d "$FAT_LOG_DIR" ] && [ -w "$FAT_LOG_DIR" ]; then
        mkdir -p "$FAT_LOG_DIR" 2>/dev/null || true
        cp "$LOG" "$FAT_LOG_DIR/plumos-v90s-audio-diagnostic.log" 2>/dev/null || true
    fi
    if [ -d "$SHARE_DIR" ] && [ -w "$SHARE_DIR" ]; then
        cp "$LOG" "$SHARE_DIR/plumos-v90s-audio-diagnostic.log" 2>/dev/null || true
        if [ -d "$SHARE_DIR/rootfs" ]; then
            cp "$LOG" "$SHARE_DIR/rootfs/plumos-v90s-audio-diagnostic.log" 2>/dev/null || true
        fi
    fi
    sync 2>/dev/null || true
}

amixer_try() {
    if command -v amixer >/dev/null 2>&1; then
        log "amixer $*"
        amixer -c "$CARD" "$@" >> "$LOG" 2>&1 || true
    else
        log "amixer missing"
    fi
}

cset() {
    amixer_try cset "$@"
}

sset() {
    amixer_try sset "$@"
}

write_asoundrc() {
    card="$1"
    device="$2"
    cat > /root/.asoundrc <<EOF
pcm.!default {
    type plug
    slave.pcm "softvol"
}

ctl.!default {
    type hw
    card $card
}

pcm.ddmix {
    ipc_key 1024
    type dmix
    slave {
        pcm "hw:$card,$device"
    }
}

pcm.softvol {
    type softvol
    slave {
        pcm "ddmix"
    }
    control {
        name "Master"
        card $card
    }
}
EOF
    log "wrote /root/.asoundrc for dmix+softvol card=$card device=$device"
}

remove_asoundrc() {
    rm -f /root/.asoundrc 2>/dev/null || true
    log "removed /root/.asoundrc"
}

apply_profile() {
    profile="$1"
    log "audio-diagnostic: applying profile=$profile"

    case "$profile" in
        plumos_current)
            cset numid=1 1
            cset numid=2 0
            cset numid=3 0
            cset numid=4 63
            cset numid=5 31
            cset numid=6 31
            cset numid=7 0
            cset numid=8 160,160
            cset numid=9 0,0
            cset numid=10 0
            cset numid=11 0
            cset numid=14 on
            cset numid=15 on
            cset numid=16 on
            cset numid=17 255,255
            ;;
        knulli_runtime_speaker)
            sset 'HpSpeaker' on
            sset 'Headphone' on
            sset 'Headphone' 0
            sset 'ADC volume' 0
            sset 'LINEOUT volume' 0
            sset 'DAC Swap' Off
            ;;
        knulli_dts_loud)
            cset numid=1 1
            cset numid=2 0
            cset numid=3 0
            cset numid=4 63
            cset numid=7 22
            cset numid=8 160,160
            cset numid=9 0,0
            cset numid=10 0
            cset numid=11 0
            cset numid=14 on
            cset numid=15 on
            cset numid=16 on
            cset numid=17 190,190
            ;;
        knulli_asound_state)
            cset numid=1 1
            cset numid=2 1
            cset numid=3 0
            cset numid=4 0
            cset numid=5 31
            cset numid=6 31
            cset numid=7 26
            cset numid=8 0,0
            cset numid=9 160,160
            cset numid=10 2
            cset numid=11 0
            cset numid=12 on
            cset numid=13 on
            cset numid=14 on
            cset numid=15 on
            cset numid=16 on
            cset numid=17 190,190
            ;;
        all_max)
            cset numid=1 1
            cset numid=2 1
            cset numid=3 1
            cset numid=4 63
            cset numid=5 31
            cset numid=6 31
            cset numid=7 31
            cset numid=8 255,255
            cset numid=9 255,255
            cset numid=10 7
            cset numid=11 1
            cset numid=12 on
            cset numid=13 on
            cset numid=14 on
            cset numid=15 on
            cset numid=16 on
            cset numid=17 255,255
            ;;
        headphone_hotplug)
            sset 'HpSpeaker' on
            sset 'Headphone' on
            sset 'Headphone' 3
            sset 'ADC volume' 0
            sset 'LINEOUT volume' 0
            sset 'DAC Swap' Off
            cset numid=4 63
            cset numid=8 160,160
            cset numid=17 255,255
            ;;
        dmix_softvol)
            write_asoundrc 0 0
            cset numid=1 1
            cset numid=2 0
            cset numid=4 63
            cset numid=8 160,160
            cset numid=10 0
            cset numid=14 on
            cset numid=15 on
            cset numid=16 on
            sset 'Master' 255 2>/dev/null || true
            DEVICE=default
            ;;
        no_softvol)
            remove_asoundrc
            DEVICE=hw:0,0
            ;;
        *)
            log "unknown profile: $profile"
            return 2
            ;;
    esac
}

dump_status() {
    append_cmd "date" date
    append_cmd "uname" uname -a
    append_cmd "cmdline" sh -c 'cat /proc/cmdline 2>/dev/null || true'
    append_cmd "sound-cards" sh -c 'cat /proc/asound/cards 2>/dev/null || true; cat /proc/asound/devices 2>/dev/null || true; aplay -l 2>&1 || true'
    append_cmd "mixer" sh -c 'amixer -c 0 scontents 2>&1 || true'
    append_cmd "pcm-status" sh -c 'cat /proc/asound/card0/pcm0p/sub0/status 2>/dev/null || true'
    append_cmd "debug-gpio" sh -c 'mkdir -p /sys/kernel/debug; mountpoint -q /sys/kernel/debug 2>/dev/null || mount -t debugfs debugfs /sys/kernel/debug 2>/dev/null || true; cat /sys/kernel/debug/gpio 2>/dev/null | grep -E "gpio-230|SPK|PH6" || cat /sys/kernel/debug/gpio 2>/dev/null || true'
    append_cmd "debug-asoc" sh -c 'find /sys/kernel/debug/asoc -maxdepth 5 -type f 2>/dev/null | sort | while read p; do case "$p" in */dapm/*|*/codec_reg|*/platform_reg|*/dai_reg) echo "--- $p"; cat "$p" 2>/dev/null | head -120;; esac; done'
    if command -v v90s-mmio-rmw >/dev/null 2>&1; then
        append_cmd "codec-regs" sh -c 'for off in 0x000 0x004 0x010 0x024 0x0f0 0x310 0x324; do v90s-mmio-rmw 0x05096000 "$off" 2>&1 || true; done'
    fi
}

run_tone() {
    seconds="${1:-$TONE_SECONDS}"
    device="${2:-$DEVICE}"
    log "audio-diagnostic: tone seconds=$seconds device=$device"

    if ! command -v speaker-test >/dev/null 2>&1; then
        log "speaker-test missing"
        return 1
    fi

    if command -v timeout >/dev/null 2>&1; then
        timeout "$seconds" speaker-test -D "$device" -c 2 -r 48000 -F S16_LE -t sine -f 880 >> "$LOG" 2>&1 || true
    else
        speaker-test -D "$device" -c 2 -r 48000 -F S16_LE -t sine -f 880 >> "$LOG" 2>&1 &
        tone_pid=$!
        sleep "$seconds"
        kill "$tone_pid" 2>/dev/null || true
        wait "$tone_pid" 2>/dev/null || true
    fi
}

usage() {
    cat <<EOF
Usage:
  v90s-audio-diagnostic.sh status
  v90s-audio-diagnostic.sh profile <name> [seconds]
  v90s-audio-diagnostic.sh tone [seconds] [device]
  v90s-audio-diagnostic.sh sweep [seconds]

Profiles:
  plumos_current
  knulli_runtime_speaker
  knulli_dts_loud
  knulli_asound_state
  all_max
  headphone_hotplug
  dmix_softvol
  no_softvol
EOF
}

main() {
    action="${1:-status}"
    : > "$LOG" 2>/dev/null || true
    log "audio-diagnostic: action=$action log=$LOG"

    case "$action" in
        status)
            dump_status
            ;;
        profile)
            profile="${2:-}"
            seconds="${3:-$TONE_SECONDS}"
            if [ -z "$profile" ]; then
                usage >&2
                exit 2
            fi
            apply_profile "$profile"
            dump_status
            run_tone "$seconds" "$DEVICE"
            dump_status
            ;;
        tone)
            run_tone "${2:-$TONE_SECONDS}" "${3:-$DEVICE}"
            dump_status
            ;;
        sweep)
            seconds="${2:-$TONE_SECONDS}"
            for profile in plumos_current knulli_runtime_speaker knulli_dts_loud headphone_hotplug dmix_softvol knulli_asound_state all_max no_softvol; do
                log ""
                log "audio-diagnostic: sweep profile=$profile listen_now=${seconds}s"
                apply_profile "$profile" || true
                dump_status
                run_tone "$seconds" "$DEVICE"
                dump_status
                mirror_log
                sleep 1
            done
            ;;
        *)
            usage >&2
            exit 2
            ;;
    esac

    mirror_log
}

main "$@"
