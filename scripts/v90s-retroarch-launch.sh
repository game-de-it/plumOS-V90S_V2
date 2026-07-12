#!/bin/sh
set -u

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH

FAT_LOG_DIR="${PLUMOS_V90S_FAT_LOG_DIR:-/boot/plumos-logs}"
SHARE_DIR="${PLUMOS_V90S_SHARE_DIR:-/mnt/share}"
LAUNCH_LOG=/tmp/plumos-v90s-retroarch-launch.log
RETROARCH_LOG=/tmp/plumos-v90s-retroarch.log
SHARE_LAUNCH_LOG=
SHARE_RETROARCH_LOG=
RETROARCH_TIMEOUT_SECONDS="${PLUMOS_V90S_RETROARCH_TIMEOUT_SECONDS:-0}"
PERIODIC_LOG_MIRROR="${PLUMOS_V90S_PERIODIC_LOG_MIRROR:-0}"
RETROARCH_CONFIG_SRC="${PLUMOS_V90S_RETROARCH_CONFIG:-}"
RETROARCH_CONFIG_DIR="${PLUMOS_V90S_RETROARCH_CONFIG_DIR:-/mnt/share/retroarch}"
RETROARCH_CONFIG_PATH="${PLUMOS_V90S_RETROARCH_CONFIG_PATH:-}"
RUN_DIR="${PLUMOS_V90S_RUN_DIR:-/run/plumos-v90s}"
ROUTE_CONFIG="${PLUMOS_V90S_ROUTE_CONFIG:-/etc/plumos-v90s-retroarch-route}"
LAUNCHER_PID_FILE="$RUN_DIR/retroarch-launch.pid"
RETROARCH_PID_FILE="$RUN_DIR/retroarch.pid"
RETROARCH_TIMEOUT_FLAG="$RUN_DIR/retroarch.timeout"
RETROARCH_PID=
RETROARCH_WATCHDOG_PID=
LOG_MIRROR_PID=

if [ -r "$ROUTE_CONFIG" ]; then
    . "$ROUTE_CONFIG"
fi
RETROARCH_BIN="${PLUMOS_V90S_RETROARCH_BIN:-retroarch}"

if [ -d "$FAT_LOG_DIR" ] && [ -w "$FAT_LOG_DIR" ]; then
    LAUNCH_LOG="$FAT_LOG_DIR/plumos-v90s-retroarch-launch.log"
    RETROARCH_LOG="$FAT_LOG_DIR/plumos-v90s-retroarch.log"
fi

if [ -d "$SHARE_DIR" ] && [ -w "$SHARE_DIR" ]; then
    SHARE_LAUNCH_LOG="$SHARE_DIR/plumos-v90s-retroarch-launch.log"
    SHARE_RETROARCH_LOG="$SHARE_DIR/plumos-v90s-retroarch.log"
fi

: > "$LAUNCH_LOG" 2>/dev/null || true
: > "$RETROARCH_LOG" 2>/dev/null || true
[ -n "$SHARE_LAUNCH_LOG" ] && : > "$SHARE_LAUNCH_LOG" 2>/dev/null || true
[ -n "$SHARE_RETROARCH_LOG" ] && : > "$SHARE_RETROARCH_LOG" 2>/dev/null || true
sync 2>/dev/null || true

log_count=0

log() {
    line="$*"
    echo "$line"
    echo "$line" >> "$LAUNCH_LOG" 2>/dev/null || true
    if [ -n "$SHARE_LAUNCH_LOG" ] && [ "$SHARE_LAUNCH_LOG" != "$LAUNCH_LOG" ]; then
        echo "$line" >> "$SHARE_LAUNCH_LOG" 2>/dev/null || true
    fi
    log_count=$((log_count + 1))
    if [ "$log_count" -lt 30 ] || [ $((log_count % 10)) -eq 0 ]; then
        sync 2>/dev/null || true
    fi
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

pid_comm_equals() {
    pid="$1"
    expected="$2"
    [ -r "/proc/$pid/comm" ] || return 1
    comm="$(cat "/proc/$pid/comm" 2>/dev/null || true)"
    [ "$comm" = "$expected" ]
}

pid_is_retroarch() {
    pid="$1"
    [ -r "/proc/$pid/comm" ] || return 1
    [ -r "/proc/$pid/cmdline" ] || return 1
    comm="$(cat "/proc/$pid/comm" 2>/dev/null || true)"
    cmdline="$(tr '\000' ' ' < "/proc/$pid/cmdline" 2>/dev/null || true)"

    case "$comm" in
        retroarch|retroarch-knull|retroarch-knulli|retroarch-powervr)
            ;;
        *)
            return 1
            ;;
    esac

    case "$cmdline" in
        *"retroarch-v90s.cfg"*)
            return 0
            ;;
    esac
    return 1
}

wait_pid_exit() {
    pid="$1"
    limit="${2:-5}"
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

terminate_retroarch_pid() {
    pid="$1"
    reason="$2"

    case "$pid" in
        ''|*[!0-9]*)
            log "retroarch-launch: refusing to stop invalid retroarch pid='$pid'"
            return 1
            ;;
    esac

    if ! kill -0 "$pid" 2>/dev/null; then
        remove_pidfile_if_matches "$RETROARCH_PID_FILE" "$pid"
        return 0
    fi

    if ! pid_is_retroarch "$pid"; then
        comm="$(cat "/proc/$pid/comm" 2>/dev/null || true)"
        cmdline="$(tr '\000' ' ' < "/proc/$pid/cmdline" 2>/dev/null || true)"
        log "retroarch-launch: refusing to stop pid=$pid; comm='$comm' cmdline='$cmdline'"
        return 1
    fi

    log "retroarch-launch: stopping RetroArch pid=$pid reason=$reason"
    kill -TERM "$pid" 2>/dev/null || true
    if ! wait_pid_exit "$pid" 5; then
        log "retroarch-launch: RetroArch pid=$pid still alive after TERM; sending KILL"
        kill -KILL "$pid" 2>/dev/null || true
        wait_pid_exit "$pid" 2 || true
    fi
    remove_pidfile_if_matches "$RETROARCH_PID_FILE" "$pid"
}

stop_fb_console() {
    if [ "${PLUMOS_V90S_STOP_FB_CONSOLE:-1}" != "1" ]; then
        log "retroarch-launch: fb console stop disabled"
        return
    fi

    for proc in /proc/[0-9]*; do
        [ -d "$proc" ] || continue
        pid="${proc#/proc/}"
        case "$pid" in
            ''|*[!0-9]*)
                continue
                ;;
        esac

        [ "$pid" != "$$" ] || continue
        [ -r "$proc/cmdline" ] || continue
        cmdline="$(tr '\000' ' ' < "$proc/cmdline" 2>/dev/null || true)"
        case "$cmdline" in
            *"/usr/local/sbin/v90s-fb-console"*)
                ;;
            *)
                continue
                ;;
        esac

        comm="$(cat "$proc/comm" 2>/dev/null || true)"
        case "$comm" in
            v90s-fb-console)
                ;;
            *)
                log "retroarch-launch: refusing to stop fb console candidate pid=$pid comm='$comm' cmdline='$cmdline'"
                continue
                ;;
        esac

        log "retroarch-launch: stopping fb console pid=$pid before RetroArch"
        kill -TERM "$pid" 2>/dev/null || true
        if ! wait_pid_exit "$pid" 3; then
            log "retroarch-launch: fb console pid=$pid still alive after TERM; sending KILL"
            kill -KILL "$pid" 2>/dev/null || true
            wait_pid_exit "$pid" 1 || true
        fi
    done
}

append_cmd() {
    label="$1"
    shift
    {
        echo ""
        echo "===== $label ====="
        "$@" 2>&1
        echo "===== $label rc=$? ====="
    } >> "$LAUNCH_LOG" 2>/dev/null || true
    if [ -n "$SHARE_LAUNCH_LOG" ] && [ "$SHARE_LAUNCH_LOG" != "$LAUNCH_LOG" ]; then
        cp "$LAUNCH_LOG" "$SHARE_LAUNCH_LOG" 2>/dev/null || true
    fi
    sync 2>/dev/null || true
}

mirror_logs() {
    if [ -n "$SHARE_LAUNCH_LOG" ] && [ "$SHARE_LAUNCH_LOG" != "$LAUNCH_LOG" ]; then
        cp "$LAUNCH_LOG" "$SHARE_LAUNCH_LOG" 2>/dev/null || true
    fi
    if [ -n "$SHARE_RETROARCH_LOG" ] && [ "$SHARE_RETROARCH_LOG" != "$RETROARCH_LOG" ]; then
        cp "$RETROARCH_LOG" "$SHARE_RETROARCH_LOG" 2>/dev/null || true
    fi
    if [ -d "$SHARE_DIR/rootfs" ]; then
        cp "$LAUNCH_LOG" "$SHARE_DIR/rootfs/plumos-v90s-retroarch-launch.log" 2>/dev/null || true
        cp "$RETROARCH_LOG" "$SHARE_DIR/rootfs/plumos-v90s-retroarch.log" 2>/dev/null || true
    fi
    sync 2>/dev/null || true
}

start_periodic_log_mirror() {
    if [ "$PERIODIC_LOG_MIRROR" != "1" ]; then
        log "retroarch-launch: periodic log mirror disabled"
        return
    fi

    (
        while :; do
            sleep 5
            mirror_logs
        done
    ) &
    LOG_MIRROR_PID=$!
}

stop_periodic_log_mirror() {
    if [ -n "$LOG_MIRROR_PID" ]; then
        kill "$LOG_MIRROR_PID" 2>/dev/null || true
        wait "$LOG_MIRROR_PID" 2>/dev/null || true
        LOG_MIRROR_PID=
    fi
    mirror_logs
}

cleanup_launcher_pidfile() {
    remove_pidfile_if_matches "$LAUNCHER_PID_FILE" "$$"
}

cleanup_retroarch_pidfile() {
    if [ -n "$RETROARCH_PID" ]; then
        remove_pidfile_if_matches "$RETROARCH_PID_FILE" "$RETROARCH_PID"
    fi
}

on_launcher_exit() {
    if [ -n "$RETROARCH_WATCHDOG_PID" ]; then
        kill "$RETROARCH_WATCHDOG_PID" 2>/dev/null || true
        wait "$RETROARCH_WATCHDOG_PID" 2>/dev/null || true
        RETROARCH_WATCHDOG_PID=
    fi
    stop_periodic_log_mirror
    cleanup_retroarch_pidfile
    cleanup_launcher_pidfile
}

on_launcher_signal() {
    sig="$1"
    log "retroarch-launch: caught $sig; stopping managed RetroArch process"
    if [ -n "$RETROARCH_PID" ]; then
        terminate_retroarch_pid "$RETROARCH_PID" "launcher-$sig"
    elif pid="$(read_pidfile "$RETROARCH_PID_FILE" 2>/dev/null || true)"; [ -n "$pid" ]; then
        terminate_retroarch_pid "$pid" "launcher-$sig"
    fi
    exit 128
}

run_retroarch() {
    cfg="$1"
    start_mode="$2"

    rm -f "$RETROARCH_TIMEOUT_FLAG" 2>/dev/null || true

    case "$start_mode" in
        menu)
            "$RETROARCH_BIN" --verbose --config "$cfg" --menu >> "$RETROARCH_LOG" 2>&1 &
            ;;
        content)
            "$RETROARCH_BIN" --verbose --config "$cfg" -L "$core" "$rom" >> "$RETROARCH_LOG" 2>&1 &
            ;;
        *)
            log "retroarch-launch: unsupported start mode: $start_mode"
            return 47
            ;;
    esac
    RETROARCH_PID=$!
    printf '%s\n' "$RETROARCH_PID" > "$RETROARCH_PID_FILE" 2>/dev/null || true
    log "retroarch-launch: started RetroArch pid=$RETROARCH_PID mode=$start_mode"

    if [ "${RETROARCH_TIMEOUT_SECONDS:-0}" != "0" ]; then
        (
            sleep "$RETROARCH_TIMEOUT_SECONDS"
            if pidfile_matches_pid "$RETROARCH_PID_FILE" "$RETROARCH_PID" && pid_is_retroarch "$RETROARCH_PID"; then
                : > "$RETROARCH_TIMEOUT_FLAG" 2>/dev/null || true
                terminate_retroarch_pid "$RETROARCH_PID" "timeout-${RETROARCH_TIMEOUT_SECONDS}s"
            fi
        ) &
        RETROARCH_WATCHDOG_PID=$!
    fi

    wait "$RETROARCH_PID"
    rc=$?

    if [ -n "$RETROARCH_WATCHDOG_PID" ]; then
        kill "$RETROARCH_WATCHDOG_PID" 2>/dev/null || true
        wait "$RETROARCH_WATCHDOG_PID" 2>/dev/null || true
        RETROARCH_WATCHDOG_PID=
    fi
    if [ -f "$RETROARCH_TIMEOUT_FLAG" ]; then
        rc=124
        rm -f "$RETROARCH_TIMEOUT_FLAG" 2>/dev/null || true
    fi
    cleanup_retroarch_pidfile
    RETROARCH_PID=
    return "$rc"
}

read_file() {
    path="$1"
    if [ -r "$path" ]; then
        tr '\n' ' ' < "$path" 2>/dev/null
    else
        printf 'missing'
    fi
}

amixer_try() {
    if command -v amixer >/dev/null 2>&1; then
        amixer -c 0 "$@" >> "$LAUNCH_LOG" 2>&1 || true
    fi
}

setup_cpu_performance() {
    if [ "${PLUMOS_V90S_CPU_PERFORMANCE:-0}" != "1" ]; then
        log "retroarch-launch: CPU performance setup disabled"
        return
    fi

    log "retroarch-launch: applying CPU performance governor"
    for cpufreq in /sys/devices/system/cpu/cpu[0-9]*/cpufreq; do
        [ -d "$cpufreq" ] || continue

        if [ -w "$cpufreq/scaling_governor" ] &&
            grep -qw performance "$cpufreq/scaling_available_governors" 2>/dev/null; then
            echo performance > "$cpufreq/scaling_governor" 2>/dev/null || true
        fi

        if [ -r "$cpufreq/scaling_max_freq" ] && [ -w "$cpufreq/scaling_min_freq" ]; then
            cat "$cpufreq/scaling_max_freq" > "$cpufreq/scaling_min_freq" 2>/dev/null || true
        fi
    done

    append_cmd "cpufreq-after-setup" sh -c 'for d in /sys/devices/system/cpu/cpu[0-9]*/cpufreq; do [ -d "$d" ] || continue; echo "${d%/cpufreq}: governor=$(cat "$d/scaling_governor" 2>/dev/null) cur=$(cat "$d/scaling_cur_freq" 2>/dev/null) min=$(cat "$d/scaling_min_freq" 2>/dev/null) max=$(cat "$d/scaling_max_freq" 2>/dev/null)"; done'
}

setup_audio_mixer() {
    if ! command -v amixer >/dev/null 2>&1; then
        log "retroarch-launch: amixer missing; skipping audio mixer setup"
        return
    fi

    log "retroarch-launch: applying V90S KNULLI asound-state mixer setup"

    # These defaults match the live RetroArch run that produced game audio
    # after the KNULLI asound-state diagnostic proved the speaker path.
    adc_swap="${PLUMOS_V90S_ADC_SWAP:-0}"
    dac_swap="${PLUMOS_V90S_DAC_SWAP:-1}"
    adc_volume="${PLUMOS_V90S_ADC_VOLUME:-160}"
    dac_volume="${PLUMOS_V90S_DAC_VOLUME:-160}"
    digital_volume="${PLUMOS_V90S_DIGITAL_VOLUME:-0}"
    headphone_volume="${PLUMOS_V90S_HEADPHONE_VOLUME:-2}"
    lineout_volume="${PLUMOS_V90S_LINEOUT_VOLUME:-26}"
    lineout_select="${PLUMOS_V90S_LINEOUT_OUTPUT_SELECT:-0}"
    mic_boost="${PLUMOS_V90S_MIC_BOOST:-on}"

    amixer_try cset numid=1 1
    amixer_try cset numid=2 "$dac_swap"
    amixer_try cset numid=3 "$adc_swap"
    amixer_try cset numid=4 "$digital_volume"
    amixer_try cset numid=5 31
    amixer_try cset numid=6 31
    amixer_try cset numid=7 "$lineout_volume"
    amixer_try cset numid=8 "$dac_volume,$dac_volume"
    amixer_try cset numid=9 "$adc_volume,$adc_volume"
    amixer_try cset numid=10 "$headphone_volume"
    amixer_try cset numid=11 "$lineout_select"
    amixer_try cset numid=12 "$mic_boost"
    amixer_try cset numid=13 "$mic_boost"
    amixer_try cset numid=14 on
    amixer_try cset numid=15 on
    amixer_try cset numid=16 on
}

apply_plumos_volume() {
    volume_helper="${PLUMOS_ROOT:-/mnt/plumos}/bin/plumos-volume-control"
    if [ ! -x "$volume_helper" ]; then
        log "retroarch-launch: plumOS volume helper missing; keeping mixer defaults"
        return
    fi
    log "retroarch-launch: applying plumOS system volume"
    PLUMOS_ROOT="${PLUMOS_ROOT:-/mnt/plumos}" "$volume_helper" apply >> "$LAUNCH_LOG" 2>&1 || \
        log "retroarch-launch: plumOS volume apply failed"
}

write_config() {
    cfg="$1"
    video_driver="$2"
    input_driver="$3"
    joypad_driver="$4"
    audio_driver="$5"
    video_context_driver="$6"
    video_threaded="$7"

    cat > "$cfg" <<EOF
config_save_on_exit = "true"
libretro_directory = "${PLUMOS_V90S_LIBRETRO_DIR:-/usr/lib/aarch64-linux-gnu/libretro}"
libretro_info_path = "${PLUMOS_V90S_LIBRETRO_INFO_DIR:-/usr/share/libretro/info}"
assets_directory = "${PLUMOS_V90S_RETROARCH_ASSETS_DIR:-/usr/share/libretro/assets}"
system_directory = "${PLUMOS_V90S_SYSTEM_DIR:-/root/.config/retroarch/system}"
savefile_directory = "${PLUMOS_V90S_SAVEFILE_DIR:-/tmp}"
savestate_directory = "${PLUMOS_V90S_SAVESTATE_DIR:-/tmp}"
content_database_path = "${PLUMOS_V90S_CONTENT_DATABASE_DIR:-/usr/share/libretro/database/rdb}"

log_verbosity = "true"
libretro_log_level = "0"
fps_show = "true"
fps_update_interval = "256"
video_font_enable = "true"
video_font_size = "16.000000"

menu_driver = "rgui"
video_driver = "$video_driver"
EOF
    if [ -n "$video_context_driver" ]; then
        printf 'video_context_driver = "%s"\n' "$video_context_driver" >> "$cfg"
    fi
    cat >> "$cfg" <<EOF
video_fullscreen = "true"
video_windowed_fullscreen = "true"
video_vsync = "true"
video_refresh_rate = "${PLUMOS_V90S_VIDEO_REFRESH_RATE:-58.917103}"
video_threaded = "$video_threaded"
threaded_data_runloop_enable = "true"
vrr_runloop_enable = "${PLUMOS_V90S_VRR_RUNLOOP_ENABLE:-true}"
video_smooth = "false"
video_scale_integer = "false"
video_force_aspect = "true"
video_aspect_ratio = "1.333333"

audio_enable = "true"
audio_driver = "$audio_driver"
audio_device = "hw:0,0"
audio_sync = "true"
audio_latency = "${PLUMOS_V90S_AUDIO_LATENCY:-64}"

input_driver = "$input_driver"
input_joypad_driver = "$joypad_driver"
input_autodetect_enable = "true"
input_player1_analog_dpad_mode = "1"
input_player1_up = "up"
input_player1_down = "down"
input_player1_left = "left"
input_player1_right = "right"
input_player1_a = "x"
input_player1_b = "z"
input_player1_start = "enter"
input_player1_select = "rshift"
input_exit_emulator = "escape"
input_enable_hotkey = "rshift"
input_hotkey_block_delay = "5"
input_menu_toggle = "enter"
input_menu_toggle_gamepad_combo = "4"
all_users_control_menu = "true"
menu_pause_libretro = "true"
rgui_show_start_screen = "false"

pause_nonactive = "false"
run_ahead_enabled = "false"
rewind_enable = "false"
cheevos_enable = "false"
network_cmd_enable = "false"
EOF
}

prepare_config_path() {
    if [ -n "$RETROARCH_CONFIG_PATH" ]; then
        cfg="$RETROARCH_CONFIG_PATH"
        cfg_dir="$(dirname "$cfg")"
        mkdir -p "$cfg_dir" 2>/dev/null || true
        if [ -d "$cfg_dir" ] && [ -w "$cfg_dir" ]; then
            printf '%s\n' "$cfg"
            return 0
        fi
        log "retroarch-launch: configured persistent config dir is not writable: $cfg_dir"
    fi

    if [ -d "$RETROARCH_CONFIG_DIR" ] || mkdir -p "$RETROARCH_CONFIG_DIR" 2>/dev/null; then
        if [ -w "$RETROARCH_CONFIG_DIR" ]; then
            printf '%s/retroarch-v90s.cfg\n' "$RETROARCH_CONFIG_DIR"
            return 0
        fi
    fi

    log "retroarch-launch: persistent config unavailable; using volatile /tmp config"
    printf '/tmp/retroarch-v90s.cfg\n'
}

ensure_config_save_enabled() {
    cfg="$1"

    if grep -q '^config_save_on_exit[[:space:]]*=' "$cfg" 2>/dev/null; then
        sed -i 's/^config_save_on_exit[[:space:]]*=.*/config_save_on_exit = "true"/' "$cfg" 2>/dev/null || true
    else
        printf '\nconfig_save_on_exit = "true"\n' >> "$cfg" 2>/dev/null || true
    fi
}

if ! mkdir -p "$RUN_DIR" 2>/dev/null; then
    log "retroarch-launch: cannot create run directory: $RUN_DIR"
    mirror_logs
    exit 40
fi
printf '%s\n' "$$" > "$LAUNCHER_PID_FILE" 2>/dev/null || true
trap on_launcher_exit EXIT
trap 'on_launcher_signal TERM' TERM
trap 'on_launcher_signal INT' INT
trap 'on_launcher_signal HUP' HUP

log "retroarch-launch: entered"
log "retroarch-launch: launch_log=$LAUNCH_LOG"
log "retroarch-launch: retroarch_log=$RETROARCH_LOG"
log "retroarch-launch: retroarch_timeout_seconds=$RETROARCH_TIMEOUT_SECONDS"
log "retroarch-launch: periodic_log_mirror=$PERIODIC_LOG_MIRROR"
log "retroarch-launch: external_config=${RETROARCH_CONFIG_SRC:-none}"
log "retroarch-launch: start_mode=${PLUMOS_V90S_RETROARCH_START_MODE:-content}"
log "retroarch-launch: run_dir=$RUN_DIR"
log "retroarch-launch: route_config=$ROUTE_CONFIG present=$([ -r "$ROUTE_CONFIG" ] && printf yes || printf no)"
log "retroarch-launch: uname=$(uname -a 2>/dev/null || true)"
log "retroarch-launch: cmdline=$(read_file /proc/cmdline)"
stop_fb_console

for info in /sys/class/graphics/fb0/name /sys/class/graphics/fb0/modes /sys/class/graphics/fb0/virtual_size /sys/class/graphics/fb0/bits_per_pixel /sys/class/graphics/fb0/stride; do
    if [ -r "$info" ]; then
        log "retroarch-launch: fb0 $(basename "$info")=$(read_file "$info")"
    fi
done

append_cmd "mount" mount
append_cmd "framebuffer-devices" sh -c 'find /dev -maxdepth 1 -name "fb*" -print 2>/dev/null; find /dev/dri -maxdepth 1 -print 2>/dev/null || true'
append_cmd "input-devices" sh -c 'cat /proc/bus/input/devices 2>/dev/null || true; find /dev/input -maxdepth 1 -print 2>/dev/null || true; command -v lsinput >/dev/null 2>&1 && lsinput 2>&1 || true'
append_cmd "sound-devices" sh -c 'cat /proc/asound/cards 2>/dev/null || true; cat /proc/asound/devices 2>/dev/null || true; command -v aplay >/dev/null 2>&1 && aplay -l 2>&1 || true; find /dev/snd -maxdepth 1 -print 2>/dev/null || true'
append_cmd "sound-mixer-before" sh -c 'command -v amixer >/dev/null 2>&1 && amixer -c 0 scontents 2>&1 || true'
setup_cpu_performance
setup_audio_mixer
apply_plumos_volume
append_cmd "sound-mixer-after" sh -c 'command -v amixer >/dev/null 2>&1 && amixer -c 0 scontents 2>&1 || true'

resolved_retroarch="$(command -v "$RETROARCH_BIN" 2>/dev/null || true)"
if [ -z "$resolved_retroarch" ]; then
    log "retroarch-launch: RetroArch binary missing: $RETROARCH_BIN"
    mirror_logs
    exit 45
fi
RETROARCH_BIN="$resolved_retroarch"
log "retroarch-launch: retroarch_bin=$RETROARCH_BIN"

sdl2_runtime_dir=""
sdl2_runtime_label=""
if [ -n "${PLUMOS_V90S_SDL2_POWERVR_DIR:-}" ] && [ -d "$PLUMOS_V90S_SDL2_POWERVR_DIR" ]; then
    sdl2_runtime_dir="$PLUMOS_V90S_SDL2_POWERVR_DIR"
    sdl2_runtime_label="powervr-env"
elif [ -d /usr/local/lib/plumos-sdl2-powervr ]; then
    sdl2_runtime_dir="/usr/local/lib/plumos-sdl2-powervr"
    sdl2_runtime_label="powervr"
elif [ -d /usr/local/lib/plumos-sdl2-mali ]; then
    sdl2_runtime_dir="/usr/local/lib/plumos-sdl2-mali"
    sdl2_runtime_label="mali-compat"
fi

if [ -n "$sdl2_runtime_dir" ]; then
    export LD_LIBRARY_PATH="$sdl2_runtime_dir${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    log "retroarch-launch: custom SDL2 PowerVR runtime detected: $sdl2_runtime_dir ($sdl2_runtime_label)"
    append_cmd "custom-sdl2-powervr-files" sh -c 'for d in "${PLUMOS_V90S_SDL2_POWERVR_DIR:-}" /usr/local/lib/plumos-sdl2-powervr /usr/local/lib/plumos-sdl2-mali; do [ -n "$d" ] && [ -d "$d" ] && find "$d" -maxdepth 1 -print 2>/dev/null; done; find /usr/local/bin -maxdepth 1 -name v90s-sdl2-video-probe -print 2>/dev/null || true; for f in /etc/plumos-sdl2-powervr-manifest.txt /etc/plumos-sdl2-mali-manifest.txt; do [ -f "$f" ] && echo "--- $f" && cat "$f"; done'
fi
if [ -d /usr/lib/powervr ]; then
    if [ -n "$sdl2_runtime_dir" ]; then
        export LD_LIBRARY_PATH="/usr/lib/powervr:$sdl2_runtime_dir:/usr/lib/aarch64-linux-gnu:/usr/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    else
        export LD_LIBRARY_PATH="/usr/lib/powervr:/usr/lib/aarch64-linux-gnu:/usr/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    fi
    log "retroarch-launch: LD_LIBRARY_PATH=$LD_LIBRARY_PATH"
    append_cmd "powervr-runtime" sh -c 'for p in /usr/bin/pvrsrvctl /usr/lib/powervr/libEGL.so /usr/lib/powervr/libGLESv2.so /lib/modules/4.9.191/pvrsrvkm.ko /lib/modules/4.9.191/dc_sunxi.ko /dev/pvr* /dev/pvrsrvkm /dev/dri/*; do [ -e "$p" ] && printf "%s\n" "$p"; done; cat /proc/modules 2>/dev/null | grep -E "pvr|dc_sunxi|sunxi" || true'
fi
if [ -x /usr/local/bin/v90s-sdl2-video-probe ] && [ "${PLUMOS_V90S_RUN_SDL2_PROBE:-0}" = "1" ]; then
    append_cmd "sdl2-video-probe-mali" env SDL_VIDEODRIVER=mali SDL_AUDIODRIVER=alsa /usr/local/bin/v90s-sdl2-video-probe
elif [ -x /usr/local/bin/v90s-sdl2-video-probe ]; then
    log "retroarch-launch: skipping SDL2 video probe; set PLUMOS_V90S_RUN_SDL2_PROBE=1 for diagnostics"
fi
append_cmd "retroarch-version" "$RETROARCH_BIN" --version
append_cmd "retroarch-features" "$RETROARCH_BIN" --features
append_cmd "dmesg-tail" sh -c 'dmesg 2>/dev/null | tail -120 || true'

core="${PLUMOS_V90S_CORE:-/usr/lib/aarch64-linux-gnu/libretro/quicknes_libretro.so}"
rom="${PLUMOS_V90S_ROM:-/roms/nes/Super Mario Bros..nes}"
start_mode="${PLUMOS_V90S_RETROARCH_START_MODE:-content}"

case "$start_mode" in
    content|menu)
        ;;
    *)
        log "retroarch-launch: unsupported start mode: $start_mode"
        mirror_logs
        exit 47
        ;;
esac

log "retroarch-launch: selected_core=$core"
log "retroarch-launch: selected_rom=$rom"
log "retroarch-launch: selected_start_mode=$start_mode"

if [ "$start_mode" = "content" ] && [ ! -f "$core" ]; then
    log "retroarch-launch: RetroArch core missing: $core"
    mirror_logs
    exit 41
fi

if [ "$start_mode" = "content" ] && [ ! -f "$rom" ]; then
    log "retroarch-launch: ROM missing: $rom"
    mirror_logs
    exit 42
fi

if [ "$start_mode" = "content" ]; then
    append_cmd "rom-sha256" sha256sum "$rom"
fi

export HOME=/root
export USER=root
export LOGNAME=root
export XDG_CONFIG_HOME=/root/.config
export XDG_CACHE_HOME=/tmp/retroarch-cache
export XDG_RUNTIME_DIR=/run
mkdir -p /root/.config/retroarch/system /tmp/retroarch-cache /run 2>/dev/null || true

if [ -z "$sdl2_runtime_dir" ]; then
    log "retroarch-launch: required SDL2 PowerVR runtime missing: ${PLUMOS_V90S_SDL2_POWERVR_DIR:-/usr/local/lib/plumos-sdl2-powervr}"
    mirror_logs
    exit 44
fi

video_driver="${PLUMOS_V90S_VIDEO_DRIVER:-sdl2}"
video_context_driver="${PLUMOS_V90S_VIDEO_CONTEXT_DRIVER:-}"
video_threaded="${PLUMOS_V90S_VIDEO_THREADED:-true}"
input_driver="${PLUMOS_V90S_INPUT_DRIVER:-sdl2}"
joypad_driver="${PLUMOS_V90S_JOYPAD_DRIVER:-sdl2}"
audio_driver="${PLUMOS_V90S_AUDIO_DRIVER:-alsa}"
sdl_video="${PLUMOS_V90S_SDL_VIDEODRIVER:-mali}"
sdl_render="${PLUMOS_V90S_SDL_RENDER_DRIVER:-software}"
cfg="$(prepare_config_path)"
cfg_dir="$(dirname "$cfg")"
mkdir -p "$cfg_dir" 2>/dev/null || true

if [ -n "$RETROARCH_CONFIG_SRC" ]; then
    if [ ! -f "$RETROARCH_CONFIG_SRC" ]; then
        log "retroarch-launch: external RetroArch config missing: $RETROARCH_CONFIG_SRC"
        mirror_logs
        exit 46
    fi
    if [ "$RETROARCH_CONFIG_SRC" != "$cfg" ]; then
        cp "$RETROARCH_CONFIG_SRC" "$cfg"
        log "retroarch-launch: copied external RetroArch config from $RETROARCH_CONFIG_SRC to $cfg"
    else
        log "retroarch-launch: using external RetroArch config in place: $cfg"
    fi
else
    if [ -f "$cfg" ]; then
        log "retroarch-launch: reusing persistent RetroArch config: $cfg"
    else
        write_config "$cfg" "$video_driver" "$input_driver" "$joypad_driver" "$audio_driver" "$video_context_driver" "$video_threaded"
        log "retroarch-launch: created RetroArch config: $cfg"
    fi
fi
ensure_config_save_enabled "$cfg"
log "retroarch-launch: config_path=$cfg"

log "retroarch-launch: route video=$video_driver context=$video_context_driver threaded=$video_threaded input=$input_driver joypad=$joypad_driver audio=$audio_driver sdl_video=$sdl_video sdl_render=$sdl_render"
{
    echo ""
    echo "===== config ====="
    cat "$cfg"
    echo "===== runtime ====="
} >> "$RETROARCH_LOG" 2>/dev/null || true
mirror_logs

export SDL_VIDEODRIVER="$sdl_video"
export SDL_RENDER_DRIVER="$sdl_render"
export SDL_AUDIODRIVER=alsa
log "retroarch-launch: pre-launch sync complete"
mirror_logs

start_periodic_log_mirror
run_retroarch "$cfg" "$start_mode"
rc=$?
stop_periodic_log_mirror
log "retroarch-launch: retroarch exited rc=$rc"
if [ "$rc" -eq 124 ]; then
    log "retroarch-launch: retroarch timed out after ${RETROARCH_TIMEOUT_SECONDS}s"
fi
mirror_logs
exit "$rc"
