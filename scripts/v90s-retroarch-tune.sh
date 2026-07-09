#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage:
  scripts/v90s-retroarch-tune.sh root@IP --profile PROFILE
  scripts/v90s-retroarch-tune.sh root@IP --refresh HZ [options]

Profiles:
  dts               58.95531 Hz, Exact off, latency 64
  dts-exact-fat     58.95531 Hz, Exact on,  latency 192
  panel             59.06063 Hz, Exact off, latency 64
  panel-exact-fat   59.06063 Hz, Exact on,  latency 192
  hybrid-5925       59.25000 Hz, Exact off, latency 128
  hybrid-5950       59.50000 Hz, Exact off, latency 128
  stockos-exact     59.04900 Hz, Exact on,  latency 128
  stockos-generated 58.917103 Hz, Exact on, latency 64, video_threaded on
  sixty             60.00000 Hz, Exact off, latency 128
  knulli-threaded   60.00000 Hz, Exact off, latency 64, video_threaded on

Options:
  --refresh HZ      Set RetroArch video_refresh_rate
  --exact BOOL      Set vrr_runloop_enable, true or false
  --latency N       Set audio_latency
  --delta N         Set audio_rate_control_delta
  --skew N          Set audio_max_timing_skew
  --threaded BOOL   Set video_threaded, true or false
  --no-restart      Only edit config, do not restart RetroArch

The script edits /mnt/share/retroarch/retroarch-v90s.cfg on the device, creates
a timestamped backup next to it, and restarts only the managed V90S RetroArch
launcher/RetroArch process.
EOF
}

if [ "$#" -lt 2 ]; then
    usage >&2
    exit 2
fi

target="$1"
shift

profile=""
refresh=""
exact=""
latency=""
delta="0.005000"
skew="0.050000"
threaded="false"
restart="true"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --profile)
            profile="${2:?missing value for --profile}"
            shift 2
            ;;
        --refresh)
            refresh="${2:?missing value for --refresh}"
            shift 2
            ;;
        --exact)
            exact="${2:?missing value for --exact}"
            shift 2
            ;;
        --latency)
            latency="${2:?missing value for --latency}"
            shift 2
            ;;
        --delta)
            delta="${2:?missing value for --delta}"
            shift 2
            ;;
        --skew)
            skew="${2:?missing value for --skew}"
            shift 2
            ;;
        --threaded)
            threaded="${2:?missing value for --threaded}"
            shift 2
            ;;
        --no-restart)
            restart="false"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

case "$profile" in
    "")
        ;;
    dts)
        refresh="58.95531"
        exact="false"
        latency="64"
        threaded="false"
        ;;
    dts-exact-fat)
        refresh="58.95531"
        exact="true"
        latency="192"
        threaded="false"
        ;;
    panel)
        refresh="59.06063"
        exact="false"
        latency="64"
        threaded="false"
        ;;
    panel-exact-fat)
        refresh="59.06063"
        exact="true"
        latency="192"
        threaded="false"
        ;;
    hybrid-5925)
        refresh="59.25000"
        exact="false"
        latency="128"
        threaded="false"
        ;;
    hybrid-5950)
        refresh="59.50000"
        exact="false"
        latency="128"
        threaded="false"
        ;;
    stockos-exact)
        refresh="59.04900"
        exact="true"
        latency="128"
        threaded="false"
        ;;
    stockos-generated)
        refresh="58.917103"
        exact="true"
        latency="64"
        threaded="true"
        ;;
    sixty)
        refresh="60.00000"
        exact="false"
        latency="128"
        threaded="false"
        ;;
    knulli-threaded)
        refresh="60.00000"
        exact="false"
        latency="64"
        threaded="true"
        ;;
    *)
        echo "unknown profile: $profile" >&2
        usage >&2
        exit 2
        ;;
esac

if [ -z "$refresh" ] || [ -z "$exact" ] || [ -z "$latency" ]; then
    echo "--refresh, --exact, and --latency are required without a complete profile" >&2
    usage >&2
    exit 2
fi

case "$exact" in true|false) ;; *) echo "--exact must be true or false" >&2; exit 2 ;; esac
case "$threaded" in true|false) ;; *) echo "--threaded must be true or false" >&2; exit 2 ;; esac

ssh "$target" \
    PLUMOS_TUNE_PROFILE="${profile:-custom}" \
    PLUMOS_TUNE_REFRESH="$refresh" \
    PLUMOS_TUNE_EXACT="$exact" \
    PLUMOS_TUNE_LATENCY="$latency" \
    PLUMOS_TUNE_DELTA="$delta" \
    PLUMOS_TUNE_SKEW="$skew" \
    PLUMOS_TUNE_THREADED="$threaded" \
    PLUMOS_TUNE_RESTART="$restart" \
    sh -s <<'REMOTE'
set -eu

cfg="/mnt/share/retroarch/retroarch-v90s.cfg"
history="/mnt/share/retroarch/tune-history.log"

if [ ! -f "$cfg" ]; then
    echo "missing RetroArch config: $cfg" >&2
    exit 1
fi

stamp="$(date '+%Y%m%d-%H%M%S')"
backup="$cfg.before-tune-$PLUMOS_TUNE_PROFILE.$stamp"
stop_bin=""
launch_bin=""
if [ "$PLUMOS_TUNE_RESTART" = "true" ]; then
    if [ -x /tmp/v90s-retroarch-stop.sh ]; then
        stop_bin="/tmp/v90s-retroarch-stop.sh"
    elif command -v v90s-retroarch-stop >/dev/null 2>&1; then
        stop_bin="$(command -v v90s-retroarch-stop)"
    fi
    if [ -x /tmp/v90s-retroarch-launch ]; then
        launch_bin="/tmp/v90s-retroarch-launch"
    elif [ -x /tmp/v90s-retroarch-launch.sh ]; then
        launch_bin="/tmp/v90s-retroarch-launch.sh"
    elif command -v v90s-retroarch-launch >/dev/null 2>&1; then
        launch_bin="$(command -v v90s-retroarch-launch)"
    fi
    if [ -z "$stop_bin" ] || [ -z "$launch_bin" ]; then
        echo "missing managed stop/launch helper; config was not edited" >&2
        exit 1
    fi
    "$stop_bin" stop || true
    sleep 1
fi

cp "$cfg" "$backup"

set_key() {
    key="$1"
    value="$2"
    tmp="$cfg.tmp.$$"
    if grep -q "^${key}[[:space:]]*=" "$cfg"; then
        sed "s|^${key}[[:space:]]*=.*|${key} = \"${value}\"|" "$cfg" > "$tmp"
    else
        cp "$cfg" "$tmp"
        printf '%s = "%s"\n' "$key" "$value" >> "$tmp"
    fi
    mv "$tmp" "$cfg"
}

set_key video_refresh_rate "$PLUMOS_TUNE_REFRESH"
set_key vrr_runloop_enable "$PLUMOS_TUNE_EXACT"
set_key video_vsync "true"
set_key video_threaded "$PLUMOS_TUNE_THREADED"
set_key audio_sync "true"
set_key audio_rate_control "true"
set_key audio_rate_control_delta "$PLUMOS_TUNE_DELTA"
set_key audio_max_timing_skew "$PLUMOS_TUNE_SKEW"
set_key audio_latency "$PLUMOS_TUNE_LATENCY"
sync

printf '%s profile=%s refresh=%s exact=%s latency=%s delta=%s skew=%s threaded=%s backup=%s\n' \
    "$(date '+%Y-%m-%dT%H:%M:%S%z')" \
    "$PLUMOS_TUNE_PROFILE" \
    "$PLUMOS_TUNE_REFRESH" \
    "$PLUMOS_TUNE_EXACT" \
    "$PLUMOS_TUNE_LATENCY" \
    "$PLUMOS_TUNE_DELTA" \
    "$PLUMOS_TUNE_SKEW" \
    "$PLUMOS_TUNE_THREADED" \
    "$backup" >> "$history"

if [ "$PLUMOS_TUNE_RESTART" = "true" ]; then
    nohup "$launch_bin" >/tmp/plumos-v90s-retroarch-tune.out 2>&1 </dev/null &
    sleep 4
fi

grep -n -E '^(video_refresh_rate|video_vsync|vrr_runloop_enable|audio_sync|audio_rate_control|audio_rate_control_delta|audio_max_timing_skew|audio_latency|video_threaded)' "$cfg" || true
ps -eo pid,ppid,comm,args | grep -E 'retroarch|v90s-retroarch' | grep -v grep || true
echo "backup=$backup"
echo "history=$history"
REMOTE
