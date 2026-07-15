#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${PLUMOS_V90S_FRONTEND_OUT:-output/frontend/v90s}"
PACKAGE_DIR="${PLUMOS_V90S_FRONTEND_PACKAGE:-package/frontend-v90s/plumos}"
CC="${CC:-gcc}"
STRIP="${STRIP:-strip}"
BUILD_STATIC="${PLUMOS_V90S_FRONTEND_STATIC:-0}"

SRC_DIR="$ROOT_DIR/src/frontend"
OUT_ROOT="$ROOT_DIR/$OUT_DIR"
PLUMOS_DIR="$OUT_ROOT/plumos"
BIN_DIR="$PLUMOS_DIR/bin"

common_cflags=(
  -std=gnu99
  -Os
  -pipe
  -Wall
  -Wextra
  -D_GNU_SOURCE
)
ldflags=()

if [ "$BUILD_STATIC" = "1" ]; then
  common_cflags+=(-static)
fi

build_c_tool() {
  local src="$1"
  local out="$2"
  shift 2

  "$CC" \
    "${common_cflags[@]}" \
    "$@" \
    "$src" \
    -o "$out" \
    ${ldflags[@]+"${ldflags[@]}"}
  "$STRIP" "$out" 2>/dev/null || true
  chmod 0755 "$out"
}

build_fbdev_controller() {
  local out="$BIN_DIR/plumos-controller-ui-fbdev"
  local png_cflags=""
  local png_libs=""
  local ft_cflags=""
  local ft_libs=""
  local ft_define=""

  if command -v pkg-config >/dev/null 2>&1 && pkg-config --exists libpng; then
    png_cflags="$(pkg-config --cflags libpng)"
    png_libs="$(pkg-config --libs libpng)"
  else
    png_libs="-lpng -lz"
  fi
  if command -v pkg-config >/dev/null 2>&1 && pkg-config --exists freetype2; then
    ft_cflags="$(pkg-config --cflags freetype2)"
    ft_libs="$(pkg-config --libs freetype2)"
    ft_define="-DPLUMOS_FBDEV_ENABLE_FREETYPE=1"
  fi

  # shellcheck disable=SC2086
  "$CC" \
    "${common_cflags[@]}" \
    $png_cflags \
    $ft_cflags \
    -DPLUMOS_ENABLE_FBDEV_RENDERER=1 \
    -DPLUMOS_FBDEV_ENABLE_PNG=1 \
    $ft_define \
    "$SRC_DIR/plumos_controller_ui.c" \
    -o "$out" \
    ${ldflags[@]+"${ldflags[@]}"} \
    $png_libs \
    $ft_libs
  "$STRIP" "$out" 2>/dev/null || true
  chmod 0755 "$out"
}

install_wrapper() {
  local name="$1"
  local path="$BIN_DIR/$name"

  mkdir -p "$BIN_DIR"
  case "$name" in
    plumos-controller-ui-v90s)
      cat > "$path" <<'EOF'
#!/bin/sh
set -eu

PLUMOS_ROOT="${PLUMOS_ROOT:-/mnt/plumos}"
PLUMOS_SDCARD_ROOT="${PLUMOS_SDCARD_ROOT:-$PLUMOS_ROOT}"
export PLUMOS_ROOT PLUMOS_SDCARD_ROOT
export PLUMOS_DEVICE_ID="${PLUMOS_DEVICE_ID:-v90s}"
export PLUMOS_RENDERER="${PLUMOS_RENDERER:-fbdev}"
export PLUMOS_FB="${PLUMOS_FB:-/dev/fb0}"
export PLUMOS_FBDEV_ROTATION="${PLUMOS_FBDEV_ROTATION:-none}"
export PLUMOS_CONTROLLER_CPU_DEFAULT="${PLUMOS_CONTROLLER_CPU_DEFAULT:-1}"

exec "$PLUMOS_ROOT/bin/plumos-controller-ui-fbdev" --renderer fbdev "$@"
EOF
      ;;
    plumos-frontend-launch)
      cat > "$path" <<'EOF'
#!/bin/sh
set -eu

PLUMOS_ROOT="${PLUMOS_ROOT:-/mnt/plumos}"
PLUMOS_SDCARD_ROOT="${PLUMOS_SDCARD_ROOT:-$PLUMOS_ROOT}"
PLUMOS_RUNTIME_ROOT="${PLUMOS_RUNTIME_ROOT:-/run/plumos}"
export PLUMOS_ROOT PLUMOS_SDCARD_ROOT PLUMOS_RUNTIME_ROOT

mkdir -p \
  "$PLUMOS_RUNTIME_ROOT/frontend" \
  "$PLUMOS_RUNTIME_ROOT/tmp" \
  "$PLUMOS_ROOT/Logs" \
  "$PLUMOS_ROOT/state/frontend" \
  "$PLUMOS_ROOT/config/frontend" \
  "$PLUMOS_ROOT/config/system" \
  "$PLUMOS_ROOT/roms" \
  "$PLUMOS_ROOT/bios"

log="$PLUMOS_ROOT/Logs/frontend.log"
printf 'plumos-frontend-launch: starting V90S frontend\n' >> "$log"
printf 'plumos-frontend-launch: PLUMOS_ROOT=%s\n' "$PLUMOS_ROOT" >> "$log"

if [ -x "$PLUMOS_ROOT/bin/plumos-sd2-content-mount" ]; then
  sd2_mode="${PLUMOS_FRONTEND_SD2_MODE:-sync}"
  case "$sd2_mode" in
    off|disabled|0)
      printf 'plumos-frontend-launch: SD2 mount skipped mode=%s\n' "$sd2_mode" >> "$log"
      ;;
    background|bg)
      (
        export PLUMOS_SD2_FSCK="${PLUMOS_SD2_BOOT_FSCK:-auto}"
        printf 'plumos-frontend-launch: SD2 mount background fsck=%s\n' "$PLUMOS_SD2_FSCK" >> "$log"
        "$PLUMOS_ROOT/bin/plumos-sd2-content-mount" start >> "$log" 2>&1 || true
      ) &
      ;;
    sync|"")
      export PLUMOS_SD2_FSCK="${PLUMOS_SD2_BOOT_FSCK:-auto}"
      printf 'plumos-frontend-launch: SD2 mount sync fsck=%s\n' "$PLUMOS_SD2_FSCK" >> "$log"
      "$PLUMOS_ROOT/bin/plumos-sd2-content-mount" start >> "$log" 2>&1 || true
      ;;
    *)
      export PLUMOS_SD2_FSCK="${PLUMOS_SD2_BOOT_FSCK:-auto}"
      printf 'plumos-frontend-launch: unknown SD2 mode=%s; using sync fsck=%s\n' "$sd2_mode" "$PLUMOS_SD2_FSCK" >> "$log"
      "$PLUMOS_ROOT/bin/plumos-sd2-content-mount" start >> "$log" 2>&1 || true
      ;;
  esac
fi

exec "$PLUMOS_ROOT/bin/plumos-controller-ui-v90s" >> "$log" 2>&1
EOF
      ;;
    plumos-frontend-stop)
      cat > "$path" <<'EOF'
#!/bin/sh
set -eu

action="${1:-stop}"

frontend_pids() {
  {
    pidof plumos-controller-ui-fbdev 2>/dev/null || true
    pidof plumos-controller-ui-v90s 2>/dev/null || true
  } | tr ' ' '\n' | awk 'NF && !seen[$1]++ { print $1 }'
}

print_status() {
  pids="$(frontend_pids)"
  if [ -z "$pids" ]; then
    printf 'plumos-frontend-stop: frontend not running\n'
    return 0
  fi
  for pid in $pids; do
    cmd="$(tr '\000' ' ' < "/proc/$pid/cmdline" 2>/dev/null || true)"
    printf 'plumos-frontend-stop: pid=%s cmd=%s\n' "$pid" "$cmd"
  done
}

stop_frontend() {
  pids="$(frontend_pids)"
  if [ -z "$pids" ]; then
    printf 'plumos-frontend-stop: frontend not running\n'
    return 0
  fi
  for pid in $pids; do
    printf 'plumos-frontend-stop: TERM pid=%s\n' "$pid"
    kill -TERM "$pid" 2>/dev/null || true
  done
  for _ in 1 2 3; do
    sleep 1
    [ -z "$(frontend_pids)" ] && return 0
  done
  for pid in $(frontend_pids); do
    printf 'plumos-frontend-stop: KILL pid=%s\n' "$pid"
    kill -KILL "$pid" 2>/dev/null || true
  done
}

case "$action" in
  status)
    print_status
    ;;
  stop)
    stop_frontend
    ;;
  *)
    printf 'Usage: plumos-frontend-stop [stop|status]\n' >&2
    exit 64
    ;;
esac
EOF
      ;;
    plumos-retroarch-launch)
      cat > "$path" <<'EOF'
#!/bin/sh
set -eu

PLUMOS_ROOT="${PLUMOS_ROOT:-/mnt/plumos}"
PLUMOS_SDCARD_ROOT="${PLUMOS_SDCARD_ROOT:-$PLUMOS_ROOT}"
export PLUMOS_ROOT PLUMOS_SDCARD_ROOT

system_id=""
core=""
rom=""
cpu_policy=""
audio_driver_override=""
audio_latency_override=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --system)
      system_id="$2"
      shift 2
      ;;
    --core)
      core="$2"
      shift 2
      ;;
    --rom)
      rom="$2"
      shift 2
      ;;
    --cpu)
      cpu_policy="$2"
      shift 2
      ;;
    --freq)
      echo "plumos-retroarch-launch: fixed CPU frequencies are no longer supported" >&2
      exit 2
      ;;
    --audio)
      audio_driver_override="$2"
      shift 2
      ;;
    --audio-latency)
      audio_latency_override="$2"
      shift 2
      ;;
    --safe-exit|--dosbox-pure-force60fps|--dosbox-pure-cycles)
      shift 2
      ;;
    *)
      echo "plumos-retroarch-launch: unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if [ -z "$core" ] || [ -z "$rom" ]; then
  echo "plumos-retroarch-launch: --core and --rom are required" >&2
  exit 2
fi

case "$audio_driver_override" in
  ""|oss|alsa|alsathread|mmf_ao) ;;
  *)
    echo "plumos-retroarch-launch: unsupported audio driver: $audio_driver_override" >&2
    exit 2
    ;;
esac
case "$audio_latency_override" in
  "") ;;
  *[!0-9]*|0)
    echo "plumos-retroarch-launch: invalid audio latency: $audio_latency_override" >&2
    exit 2
    ;;
  *)
    if [ "$audio_latency_override" -gt 1000 ]; then
      echo "plumos-retroarch-launch: invalid audio latency: $audio_latency_override" >&2
      exit 2
    fi
    ;;
esac

mkdir -p \
  "$PLUMOS_ROOT/Logs" \
  "$PLUMOS_ROOT/config/retroarch" \
  "$PLUMOS_ROOT/bios" \
  "$PLUMOS_ROOT/Saves/${system_id:-content}" \
  "$PLUMOS_ROOT/States/${system_id:-content}"

cpu_index=1
while [ "$cpu_index" -le 3 ]; do
  online_path="/sys/devices/system/cpu/cpu${cpu_index}/online"
  [ -w "$online_path" ] && printf '1\n' > "$online_path" 2>/dev/null || true
  cpu_index=$((cpu_index + 1))
done

case "$cpu_policy" in
  interactive|performance|ondemand|schedutil|conservative)
    for cpufreq in /sys/devices/system/cpu/cpufreq/policy*; do
      [ -w "$cpufreq/scaling_governor" ] || continue
      cpu_min="$(cat "$cpufreq/cpuinfo_min_freq" 2>/dev/null || true)"
      cpu_max="$(cat "$cpufreq/cpuinfo_max_freq" 2>/dev/null || true)"
      [ -z "$cpu_min" ] || printf '%s\n' "$cpu_min" > "$cpufreq/scaling_min_freq" 2>/dev/null || true
      [ -z "$cpu_max" ] || printf '%s\n' "$cpu_max" > "$cpufreq/scaling_max_freq" 2>/dev/null || true
      grep -qw "$cpu_policy" "$cpufreq/scaling_available_governors" 2>/dev/null || continue
      printf '%s\n' "$cpu_policy" > "$cpufreq/scaling_governor" 2>/dev/null || true
    done
    ;;
  "") ;;
  *)
    echo "plumos-retroarch-launch: unsupported CPU governor: $cpu_policy" >&2
    exit 2
    ;;
esac

export PLUMOS_V90S_RETROARCH_BIN="${PLUMOS_V90S_RETROARCH_BIN:-/usr/local/bin/retroarch}"
export PLUMOS_V90S_CORE="$core"
export PLUMOS_V90S_ROM="$rom"
export PLUMOS_V90S_RETROARCH_START_MODE=content
export PLUMOS_V90S_ROUTE_CONFIG="${PLUMOS_V90S_ROUTE_CONFIG:-$PLUMOS_ROOT/config/retroarch/plumos-v90s-retroarch-route}"
export PLUMOS_V90S_RETROARCH_CONFIG_DIR="${PLUMOS_V90S_RETROARCH_CONFIG_DIR:-$PLUMOS_ROOT/config/retroarch}"
export PLUMOS_V90S_RETROARCH_CONFIG_PATH="${PLUMOS_V90S_RETROARCH_CONFIG_PATH:-$PLUMOS_ROOT/config/retroarch/retroarch-v90s.cfg}"
export PLUMOS_V90S_FAT_LOG_DIR="${PLUMOS_V90S_FAT_LOG_DIR:-$PLUMOS_ROOT/Logs}"
export PLUMOS_V90S_SHARE_DIR="${PLUMOS_V90S_SHARE_DIR:-$PLUMOS_ROOT/Logs}"
export PLUMOS_V90S_LIBRETRO_DIR="${PLUMOS_V90S_LIBRETRO_DIR:-$PLUMOS_ROOT/cores}"
export PLUMOS_V90S_LIBRETRO_INFO_DIR="${PLUMOS_V90S_LIBRETRO_INFO_DIR:-$PLUMOS_ROOT/info}"
export PLUMOS_V90S_SYSTEM_DIR="${PLUMOS_V90S_SYSTEM_DIR:-$PLUMOS_ROOT/bios}"
export PLUMOS_V90S_SAVEFILE_DIR="${PLUMOS_V90S_SAVEFILE_DIR:-$PLUMOS_ROOT/Saves/${system_id:-content}}"
export PLUMOS_V90S_SAVESTATE_DIR="${PLUMOS_V90S_SAVESTATE_DIR:-$PLUMOS_ROOT/States/${system_id:-content}}"
export PLUMOS_V90S_SDL2_POWERVR_DIR="${PLUMOS_V90S_SDL2_POWERVR_DIR:-$PLUMOS_ROOT/lib/plumos-sdl2-powervr}"

export PLUMOS_V90S_VIDEO_DRIVER="${PLUMOS_V90S_VIDEO_DRIVER:-gl}"
export PLUMOS_V90S_VIDEO_CONTEXT_DRIVER="${PLUMOS_V90S_VIDEO_CONTEXT_DRIVER:-mali_fbdev}"
export PLUMOS_V90S_VIDEO_THREADED="${PLUMOS_V90S_VIDEO_THREADED:-true}"
export PLUMOS_V90S_VIDEO_REFRESH_RATE="${PLUMOS_V90S_VIDEO_REFRESH_RATE:-58.917103}"
export PLUMOS_V90S_VRR_RUNLOOP_ENABLE="${PLUMOS_V90S_VRR_RUNLOOP_ENABLE:-true}"
export PLUMOS_V90S_AUDIO_DRIVER="${PLUMOS_V90S_AUDIO_DRIVER:-alsa}"
export PLUMOS_V90S_AUDIO_LATENCY="${PLUMOS_V90S_AUDIO_LATENCY:-64}"
[ -z "$audio_driver_override" ] || \
  export PLUMOS_V90S_AUDIO_DRIVER_OVERRIDE="$audio_driver_override"
[ -z "$audio_latency_override" ] || \
  export PLUMOS_V90S_AUDIO_LATENCY_OVERRIDE="$audio_latency_override"
export PLUMOS_V90S_INPUT_DRIVER="${PLUMOS_V90S_INPUT_DRIVER:-sdl2}"
export PLUMOS_V90S_JOYPAD_DRIVER="${PLUMOS_V90S_JOYPAD_DRIVER:-sdl2}"
export PLUMOS_V90S_SDL_VIDEODRIVER="${PLUMOS_V90S_SDL_VIDEODRIVER:-mali}"
export PLUMOS_V90S_SDL_RENDER_DRIVER="${PLUMOS_V90S_SDL_RENDER_DRIVER:-software}"

exec "$PLUMOS_ROOT/bin/v90s-retroarch-launch"
EOF
      ;;
    plumos-retroarch-menu-launch)
      cat > "$path" <<'EOF'
#!/bin/sh
set -eu

PLUMOS_ROOT="${PLUMOS_ROOT:-/mnt/plumos}"
PLUMOS_SDCARD_ROOT="${PLUMOS_SDCARD_ROOT:-$PLUMOS_ROOT}"
export PLUMOS_ROOT PLUMOS_SDCARD_ROOT

mkdir -p "$PLUMOS_ROOT/Logs" "$PLUMOS_ROOT/config/retroarch" "$PLUMOS_ROOT/bios"

export PLUMOS_V90S_RETROARCH_BIN="${PLUMOS_V90S_RETROARCH_BIN:-/usr/local/bin/retroarch}"
export PLUMOS_V90S_RETROARCH_START_MODE=menu
export PLUMOS_V90S_ROUTE_CONFIG="${PLUMOS_V90S_ROUTE_CONFIG:-$PLUMOS_ROOT/config/retroarch/plumos-v90s-retroarch-route}"
export PLUMOS_V90S_RETROARCH_CONFIG_DIR="${PLUMOS_V90S_RETROARCH_CONFIG_DIR:-$PLUMOS_ROOT/config/retroarch}"
export PLUMOS_V90S_RETROARCH_CONFIG_PATH="${PLUMOS_V90S_RETROARCH_CONFIG_PATH:-$PLUMOS_ROOT/config/retroarch/retroarch-v90s.cfg}"
export PLUMOS_V90S_FAT_LOG_DIR="${PLUMOS_V90S_FAT_LOG_DIR:-$PLUMOS_ROOT/Logs}"
export PLUMOS_V90S_SHARE_DIR="${PLUMOS_V90S_SHARE_DIR:-$PLUMOS_ROOT/Logs}"
export PLUMOS_V90S_LIBRETRO_DIR="${PLUMOS_V90S_LIBRETRO_DIR:-$PLUMOS_ROOT/cores}"
export PLUMOS_V90S_LIBRETRO_INFO_DIR="${PLUMOS_V90S_LIBRETRO_INFO_DIR:-$PLUMOS_ROOT/info}"
export PLUMOS_V90S_SYSTEM_DIR="${PLUMOS_V90S_SYSTEM_DIR:-$PLUMOS_ROOT/bios}"
export PLUMOS_V90S_SDL2_POWERVR_DIR="${PLUMOS_V90S_SDL2_POWERVR_DIR:-$PLUMOS_ROOT/lib/plumos-sdl2-powervr}"
export PLUMOS_V90S_VIDEO_DRIVER="${PLUMOS_V90S_VIDEO_DRIVER:-gl}"
export PLUMOS_V90S_VIDEO_CONTEXT_DRIVER="${PLUMOS_V90S_VIDEO_CONTEXT_DRIVER:-mali_fbdev}"
export PLUMOS_V90S_VIDEO_THREADED="${PLUMOS_V90S_VIDEO_THREADED:-true}"
export PLUMOS_V90S_VIDEO_REFRESH_RATE="${PLUMOS_V90S_VIDEO_REFRESH_RATE:-58.917103}"
export PLUMOS_V90S_VRR_RUNLOOP_ENABLE="${PLUMOS_V90S_VRR_RUNLOOP_ENABLE:-true}"
export PLUMOS_V90S_AUDIO_DRIVER="${PLUMOS_V90S_AUDIO_DRIVER:-alsa}"
export PLUMOS_V90S_AUDIO_LATENCY="${PLUMOS_V90S_AUDIO_LATENCY:-64}"
export PLUMOS_V90S_INPUT_DRIVER="${PLUMOS_V90S_INPUT_DRIVER:-sdl2}"
export PLUMOS_V90S_JOYPAD_DRIVER="${PLUMOS_V90S_JOYPAD_DRIVER:-sdl2}"
export PLUMOS_V90S_SDL_VIDEODRIVER="${PLUMOS_V90S_SDL_VIDEODRIVER:-mali}"
export PLUMOS_V90S_SDL_RENDER_DRIVER="${PLUMOS_V90S_SDL_RENDER_DRIVER:-software}"

exec "$PLUMOS_ROOT/bin/v90s-retroarch-launch"
EOF
      ;;
    *)
      echo "error: unknown wrapper: $name" >&2
      exit 2
      ;;
  esac
  chmod 0755 "$path"
}

rm -rf "$OUT_ROOT"
mkdir -p "$BIN_DIR"

rsync -a "$ROOT_DIR/$PACKAGE_DIR/" "$PLUMOS_DIR/"
mkdir -p \
  "$BIN_DIR" \
  "$PLUMOS_DIR/state/frontend" \
  "$PLUMOS_DIR/Logs" \
  "$PLUMOS_DIR/roms" \
  "$PLUMOS_DIR/bios" \
  "$PLUMOS_DIR/Saves" \
  "$PLUMOS_DIR/States"

build_c_tool "$SRC_DIR/plumos_frontend.c" "$BIN_DIR/plumos-frontend"
build_c_tool "$SRC_DIR/plumos_library_scan.c" "$BIN_DIR/plumos-library-scan"
build_c_tool "$SRC_DIR/plumos_text_ui.c" "$BIN_DIR/plumos-text-ui"
build_c_tool "$SRC_DIR/plumos_controller_ui.c" "$BIN_DIR/plumos-controller-ui"
build_fbdev_controller

install_wrapper plumos-controller-ui-v90s
install_wrapper plumos-frontend-launch
install_wrapper plumos-frontend-stop
install_wrapper plumos-retroarch-launch
install_wrapper plumos-retroarch-menu-launch

install -m 0755 "$ROOT_DIR/scripts/v90s-retroarch-launch.sh" "$BIN_DIR/v90s-retroarch-launch"
install -m 0755 "$ROOT_DIR/scripts/v90s-retroarch-stop.sh" "$BIN_DIR/v90s-retroarch-stop"

generated_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
{
  printf 'name=plumOS V90S frontend\n'
  printf 'generated_at=%s\n' "$generated_at"
  printf 'source=plumOS-MMF frontend port\n'
  printf 'plumos_root=/mnt/plumos\n'
  printf 'renderer=fbdev\n'
  printf 'launcher=bin/plumos-frontend-launch\n'
  printf 'frontend_stop=bin/plumos-frontend-stop\n'
  printf 'retroarch_bridge=bin/plumos-retroarch-launch\n'
  printf 'picoarch_bridge=provided-by-picoarch-target\n'
  printf 'standalone_bridge=provided-by-standalone-target\n'
} > "$OUT_ROOT/frontend.manifest"

find "$PLUMOS_DIR" -type f | sort | while IFS= read -r file; do
  rel="${file#"$OUT_ROOT"/}"
  sha256sum "$file" | awk -v rel="$rel" '{print $1 "  " rel}'
done > "$OUT_ROOT/checksums.sha256"
sha256sum "$OUT_ROOT/frontend.manifest" | awk '{print $1 "  frontend.manifest"}' >> "$OUT_ROOT/checksums.sha256"

printf 'created: %s\n' "$OUT_DIR"
printf 'launcher: %s\n' "$OUT_DIR/plumos/bin/plumos-frontend-launch"
