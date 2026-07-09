#!/usr/bin/env sh
set -eu

ip="${1:-}"
user="${PLUMOS_V90S_SSH_USER:-root}"
port="${PLUMOS_V90S_SSH_PORT:-22}"
launch=1
config_src=""

retroarch_src="${PLUMOS_V90S_RETROARCH_BIN_SRC:-output/retroarch-knulli/usr/local/bin/retroarch-knulli}"
quicknes_src="${PLUMOS_V90S_QUICKNES_SRC:-output/libretro-quicknes/quicknes_libretro.so}"
launcher_src="${PLUMOS_V90S_LAUNCHER_SRC:-scripts/v90s-retroarch-launch.sh}"
stop_src="${PLUMOS_V90S_STOP_SRC:-scripts/v90s-retroarch-stop.sh}"

usage() {
    cat <<'USAGE'
Usage:
  live-transfer-retroarch-knulli.sh IP [--config PATH] [--transfer-only]

Copies the locally built KNULLI-style RetroArch binary, QuickNES core, and
V90S launcher/stop scripts to a running device over SSH. By default it safely
stops the managed RetroArch PID and starts the explicit mali_fbdev route.

Environment:
  PLUMOS_V90S_SSH_USER=root
  PLUMOS_V90S_SSH_PORT=22
  PLUMOS_V90S_RETROARCH_BIN_SRC=output/retroarch-knulli/usr/local/bin/retroarch-knulli
  PLUMOS_V90S_QUICKNES_SRC=output/libretro-quicknes/quicknes_libretro.so
USAGE
}

if [ "$ip" = "-h" ] || [ "$ip" = "--help" ]; then
    usage
    exit 0
fi
if [ -z "$ip" ]; then
    usage
    exit 2
fi
shift
while [ "$#" -gt 0 ]; do
    case "$1" in
        --transfer-only)
            launch=0
            shift
            ;;
        --config)
            if [ "$#" -lt 2 ]; then
                printf 'error: --config requires a path\n' >&2
                usage >&2
                exit 2
            fi
            config_src="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf 'error: unknown argument: %s\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

for src in "$retroarch_src" "$quicknes_src" "$launcher_src" "$stop_src"; do
    if [ ! -f "$src" ]; then
        printf 'error: missing source file: %s\n' "$src" >&2
        exit 1
    fi
done
if [ -n "$config_src" ] && [ ! -f "$config_src" ]; then
    printf 'error: missing config file: %s\n' "$config_src" >&2
    exit 1
fi

remote="$user@$ip"
ssh_opts="-p $port -o ConnectTimeout=8 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
scp_opts="-P $port -o ConnectTimeout=8 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
remote_config_path=

printf 'transfer target: %s\n' "$remote"
printf 'retroarch: %s\n' "$(sha256sum "$retroarch_src" | awk '{print $1}')"
printf 'quicknes:   %s\n' "$(sha256sum "$quicknes_src" | awk '{print $1}')"

ssh $ssh_opts "$remote" 'sh -s' <<'REMOTE_PRESTOP'
set -eu
if [ -x /tmp/v90s-retroarch-stop.sh ]; then
    /tmp/v90s-retroarch-stop.sh stop || true
elif command -v v90s-retroarch-stop >/dev/null 2>&1; then
    v90s-retroarch-stop stop || true
else
    echo "no existing v90s-retroarch-stop found; continuing transfer"
fi
REMOTE_PRESTOP

scp $scp_opts \
    "$retroarch_src" "$quicknes_src" "$launcher_src" "$stop_src" \
    "$remote:/tmp/"
if [ -n "$config_src" ]; then
    remote_config_path="/tmp/$(basename "$config_src")"
    scp $scp_opts "$config_src" "$remote:$remote_config_path"
    ssh $ssh_opts "$remote" "printf '%s\n' '$remote_config_path' > /tmp/plumos-v90s-live-config-path"
else
    ssh $ssh_opts "$remote" "rm -f /tmp/plumos-v90s-live-config-path"
fi

ssh $ssh_opts "$remote" 'sh -s' <<'REMOTE_SETUP'
set -eu
chmod 0755 /tmp/retroarch-knulli /tmp/v90s-retroarch-launch.sh /tmp/v90s-retroarch-stop.sh
sha256sum /tmp/retroarch-knulli /tmp/quicknes_libretro.so
REMOTE_SETUP

if [ "$launch" -eq 0 ]; then
    printf 'transfer-only complete\n'
    exit 0
fi

ssh $ssh_opts "$remote" 'sh -s' <<'REMOTE_LAUNCH'
set -eu
/tmp/v90s-retroarch-stop.sh status || true
/tmp/v90s-retroarch-stop.sh stop
cat > /tmp/plumos-v90s-live-env.sh <<'ENV'
export PLUMOS_V90S_RETROARCH_BIN=/tmp/retroarch-knulli
export PLUMOS_V90S_CORE=/tmp/quicknes_libretro.so
export PLUMOS_V90S_ROM='/roms/nes/Super Mario Bros..nes'
export PLUMOS_V90S_VIDEO_DRIVER=gl
export PLUMOS_V90S_VIDEO_CONTEXT_DRIVER=mali_fbdev
export PLUMOS_V90S_VIDEO_THREADED=false
export PLUMOS_V90S_INPUT_DRIVER=sdl2
export PLUMOS_V90S_JOYPAD_DRIVER=sdl2
export PLUMOS_V90S_AUDIO_DRIVER=alsa
export PLUMOS_V90S_SDL_VIDEODRIVER=mali
export PLUMOS_V90S_SDL_RENDER_DRIVER=software
ENV
if [ -s /tmp/plumos-v90s-live-config-path ]; then
    live_config="$(sed -n '1p' /tmp/plumos-v90s-live-config-path)"
    echo "export PLUMOS_V90S_RETROARCH_CONFIG=$live_config" >> /tmp/plumos-v90s-live-env.sh
fi
nohup sh -c '. /tmp/plumos-v90s-live-env.sh; exec /tmp/v90s-retroarch-launch.sh' \
    >/tmp/plumos-v90s-live-transfer-ssh.log 2>&1 &
echo "launch_pid=$!"
sleep 2
/tmp/v90s-retroarch-stop.sh status || true
tail -80 /tmp/plumos-v90s-retroarch.log 2>/dev/null || true
REMOTE_LAUNCH
