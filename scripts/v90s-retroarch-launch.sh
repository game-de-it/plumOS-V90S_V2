#!/bin/sh
set -u

PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH

FAT_LOG_DIR=/boot/plumos-logs
SHARE_DIR=/mnt/share
LAUNCH_LOG=/tmp/plumos-v90s-retroarch-launch.log
RETROARCH_LOG=/tmp/plumos-v90s-retroarch.log
SHARE_LAUNCH_LOG=
SHARE_RETROARCH_LOG=
RETROARCH_TIMEOUT_SECONDS="${PLUMOS_V90S_RETROARCH_TIMEOUT_SECONDS:-0}"
LOG_MIRROR_PID=

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

run_retroarch() {
    cfg="$1"

    if [ "${RETROARCH_TIMEOUT_SECONDS:-0}" = "0" ]; then
        if command -v stdbuf >/dev/null 2>&1; then
            stdbuf -oL -eL retroarch --verbose --config "$cfg" -L "$core" "$rom" >> "$RETROARCH_LOG" 2>&1
        else
            retroarch --verbose --config "$cfg" -L "$core" "$rom" >> "$RETROARCH_LOG" 2>&1
        fi
    elif command -v timeout >/dev/null 2>&1; then
        if command -v stdbuf >/dev/null 2>&1; then
            timeout -s KILL "$RETROARCH_TIMEOUT_SECONDS" stdbuf -oL -eL retroarch --verbose --config "$cfg" -L "$core" "$rom" >> "$RETROARCH_LOG" 2>&1
        else
            timeout -s KILL "$RETROARCH_TIMEOUT_SECONDS" retroarch --verbose --config "$cfg" -L "$core" "$rom" >> "$RETROARCH_LOG" 2>&1
        fi
    else
        echo "retroarch-launch: timeout command missing; running RetroArch without enforced timeout" >> "$RETROARCH_LOG" 2>/dev/null || true
        if command -v stdbuf >/dev/null 2>&1; then
            stdbuf -oL -eL retroarch --verbose --config "$cfg" -L "$core" "$rom" >> "$RETROARCH_LOG" 2>&1
        else
            retroarch --verbose --config "$cfg" -L "$core" "$rom" >> "$RETROARCH_LOG" 2>&1
        fi
    fi
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

setup_audio_mixer() {
    if ! command -v amixer >/dev/null 2>&1; then
        log "retroarch-launch: amixer missing; skipping audio mixer setup"
        return
    fi

    log "retroarch-launch: applying V90S audio mixer setup"

    # A133/V90S KNULLI uses these controls for the internal codec path.
    adc_volume="${PLUMOS_V90S_ADC_VOLUME:-0}"
    dac_volume="${PLUMOS_V90S_DAC_VOLUME:-160}"
    soft_volume="${PLUMOS_V90S_SOFT_VOLUME:-255}"

    amixer_try cset numid=1 1
    amixer_try cset numid=2 0
    amixer_try cset numid=4 "${PLUMOS_V90S_DIGITAL_VOLUME:-63}"
    amixer_try cset numid=7 "${PLUMOS_V90S_LINEOUT_VOLUME:-0}"
    amixer_try cset numid=8 "$dac_volume,$dac_volume"
    amixer_try cset numid=9 "$adc_volume,$adc_volume"
    amixer_try cset numid=10 "${PLUMOS_V90S_HEADPHONE_VOLUME:-0}"
    amixer_try cset numid=11 "${PLUMOS_V90S_LINEOUT_OUTPUT_SELECT:-0}"
    amixer_try cset numid=14 on
    amixer_try cset numid=15 on
    amixer_try cset numid=16 on
    amixer_try cset numid=17 "$soft_volume,$soft_volume"
}

write_config() {
    cfg="$1"
    video_driver="$2"
    input_driver="$3"
    joypad_driver="$4"
    audio_driver="$5"

    cat > "$cfg" <<EOF
config_save_on_exit = "false"
libretro_directory = "/usr/lib/aarch64-linux-gnu/libretro"
libretro_info_path = "/usr/share/libretro/info"
assets_directory = "/usr/share/libretro/assets"
system_directory = "/root/.config/retroarch/system"
savefile_directory = "/tmp"
savestate_directory = "/tmp"
content_database_path = "/usr/share/libretro/database/rdb"

log_verbosity = "true"
libretro_log_level = "0"
fps_show = "true"
fps_update_interval = "256"
video_font_enable = "true"
video_font_size = "16.000000"

menu_driver = "rgui"
video_driver = "$video_driver"
video_fullscreen = "true"
video_windowed_fullscreen = "true"
video_vsync = "true"
video_refresh_rate = "60.000000"
video_threaded = "true"
video_smooth = "false"
video_scale_integer = "false"
video_force_aspect = "true"
video_aspect_ratio = "1.333333"

audio_enable = "true"
audio_driver = "$audio_driver"
audio_device = "hw:0,0"
audio_sync = "true"
audio_latency = "64"

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

pause_nonactive = "false"
run_ahead_enabled = "false"
rewind_enable = "false"
cheevos_enable = "false"
network_cmd_enable = "false"
EOF
}

log "retroarch-launch: entered"
log "retroarch-launch: launch_log=$LAUNCH_LOG"
log "retroarch-launch: retroarch_log=$RETROARCH_LOG"
log "retroarch-launch: retroarch_timeout_seconds=$RETROARCH_TIMEOUT_SECONDS"
log "retroarch-launch: uname=$(uname -a 2>/dev/null || true)"
log "retroarch-launch: cmdline=$(read_file /proc/cmdline)"

for info in /sys/class/graphics/fb0/name /sys/class/graphics/fb0/modes /sys/class/graphics/fb0/virtual_size /sys/class/graphics/fb0/bits_per_pixel /sys/class/graphics/fb0/stride; do
    if [ -r "$info" ]; then
        log "retroarch-launch: fb0 $(basename "$info")=$(read_file "$info")"
    fi
done

append_cmd "mount" mount
append_cmd "framebuffer-devices" sh -c 'ls -l /dev/fb* /dev/dri/* 2>/dev/null || true'
append_cmd "input-devices" sh -c 'cat /proc/bus/input/devices 2>/dev/null || true; ls -l /dev/input 2>/dev/null || true; command -v lsinput >/dev/null 2>&1 && lsinput 2>&1 || true'
append_cmd "sound-devices" sh -c 'cat /proc/asound/cards 2>/dev/null || true; cat /proc/asound/devices 2>/dev/null || true; command -v aplay >/dev/null 2>&1 && aplay -l 2>&1 || true; ls -l /dev/snd 2>/dev/null || true'
append_cmd "sound-mixer-before" sh -c 'command -v amixer >/dev/null 2>&1 && amixer -c 0 scontents 2>&1 || true'
setup_audio_mixer
append_cmd "sound-mixer-after" sh -c 'command -v amixer >/dev/null 2>&1 && amixer -c 0 scontents 2>&1 || true'
if [ -d /usr/local/lib/plumos-sdl2-mali ]; then
    export LD_LIBRARY_PATH="/usr/local/lib/plumos-sdl2-mali${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    log "retroarch-launch: custom SDL2 mali runtime detected"
    append_cmd "custom-sdl2-mali-files" sh -c 'ls -l /usr/local/lib/plumos-sdl2-mali /usr/local/bin/v90s-sdl2-video-probe /etc/plumos-sdl2-mali-manifest.txt 2>/dev/null || true; cat /etc/plumos-sdl2-mali-manifest.txt 2>/dev/null || true'
fi
if [ -d /usr/lib/powervr ]; then
    if [ -d /usr/local/lib/plumos-sdl2-mali ]; then
        export LD_LIBRARY_PATH="/usr/lib/powervr:/usr/local/lib/plumos-sdl2-mali:/usr/lib/aarch64-linux-gnu:/usr/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    else
        export LD_LIBRARY_PATH="/usr/lib/powervr:/usr/lib/aarch64-linux-gnu:/usr/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    fi
    log "retroarch-launch: LD_LIBRARY_PATH=$LD_LIBRARY_PATH"
    append_cmd "powervr-runtime" sh -c 'ls -l /usr/bin/pvrsrvctl /usr/lib/powervr/libEGL.so /usr/lib/powervr/libGLESv2.so /lib/modules/4.9.191/pvrsrvkm.ko /lib/modules/4.9.191/dc_sunxi.ko /dev/pvr* /dev/pvrsrvkm /dev/dri/* 2>/dev/null || true; cat /proc/modules 2>/dev/null | grep -E "pvr|dc_sunxi|sunxi" || true'
fi
if [ -x /usr/local/bin/v90s-sdl2-video-probe ] && [ "${PLUMOS_V90S_RUN_SDL2_PROBE:-0}" = "1" ]; then
    append_cmd "sdl2-video-probe-mali" env SDL_VIDEODRIVER=mali SDL_AUDIODRIVER=alsa /usr/local/bin/v90s-sdl2-video-probe
elif [ -x /usr/local/bin/v90s-sdl2-video-probe ]; then
    log "retroarch-launch: skipping SDL2 video probe; set PLUMOS_V90S_RUN_SDL2_PROBE=1 for diagnostics"
fi
append_cmd "retroarch-version" retroarch --version
append_cmd "retroarch-features" retroarch --features
append_cmd "dmesg-tail" sh -c 'dmesg 2>/dev/null | tail -120 || true'

core="$(find /usr/lib /usr/local/lib -type f \( -name '*nestopia*_libretro.so' -o -name '*nestopia*.so' -o -name '*fceumm*_libretro.so' -o -name '*fceumm*.so' \) 2>/dev/null | sort | head -n 1)"
rom="${PLUMOS_V90S_ROM:-/roms/nes/Super Mario Bros..nes}"

log "retroarch-launch: selected_core=${core:-missing}"
log "retroarch-launch: selected_rom=$rom"

if [ -z "$core" ]; then
    log "retroarch-launch: no NES libretro core found"
    mirror_logs
    exit 41
fi

if [ ! -f "$rom" ]; then
    log "retroarch-launch: ROM missing: $rom"
    mirror_logs
    exit 42
fi

append_cmd "rom-sha256" sha256sum "$rom"

export HOME=/root
export USER=root
export LOGNAME=root
export XDG_CONFIG_HOME=/root/.config
export XDG_CACHE_HOME=/tmp/retroarch-cache
export XDG_RUNTIME_DIR=/run
mkdir -p /root/.config/retroarch/system /tmp/retroarch-cache /run 2>/dev/null || true

attempt=0
if [ -d /usr/local/lib/plumos-sdl2-mali ]; then
    if [ "${PLUMOS_V90S_ENABLE_VIDEO_FALLBACKS:-0}" = "1" ]; then
        set -- \
            sdl2:sdl2:sdl2:alsa:mali:software \
            sdl2:sdl2:sdl2:alsa:mali:opengles2 \
            gl:sdl2:sdl2:alsa:mali:none \
            fbdev:linuxraw:linuxraw:alsa:none:none \
            fbdev:udev:udev:alsa:none:none \
            sdl2:sdl2:sdl2:alsa:kmsdrm:opengles2
    else
        set -- sdl2:sdl2:sdl2:alsa:mali:software
    fi
else
    if [ "${PLUMOS_V90S_ENABLE_VIDEO_FALLBACKS:-0}" = "1" ]; then
        set -- \
            fbdev:linuxraw:linuxraw:alsa:none:none \
            fbdev:udev:udev:alsa:none:none \
            gl:udev:udev:alsa:none:none \
            sdl2:sdl2:sdl2:alsa:mali:opengles2 \
            sdl2:sdl2:sdl2:alsa:kmsdrm:opengles2
    else
        set -- fbdev:linuxraw:linuxraw:alsa:none:none
    fi
fi

for spec do
    attempt=$((attempt + 1))
    old_ifs="$IFS"
    IFS=:
    set -- $spec
    IFS="$old_ifs"
    video_driver="$1"
    input_driver="$2"
    joypad_driver="$3"
    audio_driver="$4"
    sdl_video="$5"
    sdl_render="${6:-none}"
    cfg="/tmp/retroarch-v90s-${attempt}.cfg"

    write_config "$cfg" "$video_driver" "$input_driver" "$joypad_driver" "$audio_driver"

    log "retroarch-launch: attempt=$attempt video=$video_driver input=$input_driver joypad=$joypad_driver audio=$audio_driver sdl_video=$sdl_video sdl_render=$sdl_render"
    {
        echo ""
        echo "===== attempt $attempt config ====="
        cat "$cfg"
        echo "===== attempt $attempt runtime ====="
    } >> "$RETROARCH_LOG" 2>/dev/null || true
    mirror_logs

    if [ "$sdl_video" = "none" ]; then
        unset SDL_VIDEODRIVER
    else
        export SDL_VIDEODRIVER="$sdl_video"
    fi
    if [ "$sdl_render" = "none" ]; then
        unset SDL_RENDER_DRIVER
    else
        export SDL_RENDER_DRIVER="$sdl_render"
    fi
    export SDL_AUDIODRIVER=alsa
    log "retroarch-launch: attempt=$attempt pre-launch sync complete"
    mirror_logs

    start_periodic_log_mirror
    run_retroarch "$cfg"
    rc=$?
    stop_periodic_log_mirror
    log "retroarch-launch: attempt=$attempt exited rc=$rc"
    if [ "$rc" -eq 124 ]; then
        log "retroarch-launch: attempt=$attempt timed out after ${RETROARCH_TIMEOUT_SECONDS}s"
    fi
    append_cmd "processes-after-attempt-$attempt" sh -c 'ps w 2>/dev/null | grep -E "[r]etroarch|[p]vrsrv|[s]dl" || true'
    mirror_logs

    if [ "$rc" -eq 0 ]; then
        log "retroarch-launch: retroarch exited cleanly"
        mirror_logs
        exit 0
    fi
done

log "retroarch-launch: all attempts failed"
mirror_logs
exit 43
