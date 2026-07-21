#!/usr/bin/env sh
set -eu

out_dir="${PLUMOS_V90S_APP_LAYER_OUT:-output/app-layer/v90s}"
version="${PLUMOS_V90S_APP_LAYER_VERSION:-0.1.0-dev}"
compat_vendor="${PLUMOS_V90S_VENDOR_RUNTIME_ID:-v90s-stockos-r1}"
mount_path="${PLUMOS_V90S_APP_LAYER_MOUNT:-/mnt/plumos}"
retroarch_dir="${PLUMOS_V90S_RETROARCH_DIR:-output/retroarch-powervr}"
retroarch_bin="${PLUMOS_V90S_RETROARCH_BIN_NAME:-retroarch-powervr}"
retroarch_factory_rel="factory-defaults/ra/config/retroarch/retroarch-v90s.cfg"
ppsspp_factory_rel="factory-defaults/sa/state/standalone/ppsspp/config/ppsspp/PSP/SYSTEM"
cores_dir="${PLUMOS_V90S_CORES_DIR:-output/libretro-cores/v90s}"
sdl2_powervr_dir="${PLUMOS_V90S_SDL2_POWERVR_DIR:-output/sdl2-powervr}"
frontend_dir="${PLUMOS_V90S_FRONTEND_DIR:-output/frontend/v90s}"
userland_dir="${PLUMOS_V90S_USERLAND_DIR:-output/userland/v90s}"
network_services_dir="${PLUMOS_V90S_NETWORK_SERVICES_DIR:-output/network-services/v90s}"
audio_router_dir="${PLUMOS_V90S_AUDIO_ROUTER_DIR:-output/audio-router/v90s}"
nextcommander_dir="${PLUMOS_V90S_NEXTCOMMANDER_DIR:-output/nextcommander/v90s}"
music_player_dir="${PLUMOS_V90S_MUSIC_PLAYER_DIR:-output/music-player/v90s}"
pyxel_runtime_dir="${PLUMOS_V90S_PYXEL_RUNTIME_DIR:-output/pyxel-runtime/v90s}"
portmaster_dir="${PLUMOS_V90S_PORTMASTER_DIR:-output/portmaster/v90s}"
standalone_dir="${PLUMOS_V90S_STANDALONE_DIR:-output/standalone-emulators/v90s}"
picoarch_dir="${PLUMOS_V90S_PICOARCH_DIR:-output/picoarch/v90s}"
retroarch_config_src="${PLUMOS_V90S_RETROARCH_CONFIG_SRC:-configs/retroarch/v90s-powervr-quicknes.cfg}"
minimum_core_count="${PLUMOS_V90S_MIN_CORE_COUNT:-118}"
strict=0

usage() {
    cat <<'USAGE'
Usage:
  build-app-layer.sh [options]

Options:
  --out-dir PATH          App-layer output directory; default output/app-layer/v90s.
  --version VERSION      App-layer version; default 0.1.0-dev.
  --compat-vendor ID     Compatible vendor runtime; default v90s-stockos-r1.
  --mount-path PATH      On-device mount path; default /mnt/plumos.
  --retroarch-dir PATH   RetroArch payload; default output/retroarch-powervr.
  --retroarch-bin NAME   RetroArch binary name; default retroarch-powervr.
  --cores-dir PATH       Libretro cores payload; default output/libretro-cores/v90s.
  --sdl2-powervr-dir PATH
                          SDL2 PowerVR payload; default output/sdl2-powervr.
  --frontend-dir PATH    Frontend payload; default output/frontend/v90s.
  --userland-dir PATH    BusyBox/command tools payload; default output/userland/v90s.
  --network-services-dir PATH
                          FTP/SFTP/Samba payload; default output/network-services/v90s.
  --audio-router-dir PATH Audio hotplug runtime; default output/audio-router/v90s.
  --nextcommander-dir PATH
                          NextCommander payload; default output/nextcommander/v90s.
  --music-player-dir PATH Music Player payload; default output/music-player/v90s.
  --pyxel-runtime-dir PATH
                          Pyxel venv payload; default output/pyxel-runtime/v90s.
  --portmaster-dir PATH PortMaster payload; default output/portmaster/v90s.
  --standalone-dir PATH  Standalone emulator payload; default output/standalone-emulators/v90s.
  --picoarch-dir PATH    PicoArch payload; default output/picoarch/v90s.
  --retroarch-config PATH
                          RetroArch defaults template; default configs/retroarch/v90s-powervr-quicknes.cfg.
  --strict               Fail if currently supported payloads are missing.
USAGE
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --out-dir)
            out_dir="$2"
            shift 2
            ;;
        --version)
            version="$2"
            shift 2
            ;;
        --compat-vendor)
            compat_vendor="$2"
            shift 2
            ;;
        --mount-path)
            mount_path="$2"
            shift 2
            ;;
        --retroarch-dir)
            retroarch_dir="$2"
            shift 2
            ;;
        --retroarch-bin)
            retroarch_bin="$2"
            shift 2
            ;;
        --cores-dir)
            cores_dir="$2"
            shift 2
            ;;
        --sdl2-powervr-dir)
            sdl2_powervr_dir="$2"
            shift 2
            ;;
        --frontend-dir)
            frontend_dir="$2"
            shift 2
            ;;
        --userland-dir)
            userland_dir="$2"
            shift 2
            ;;
        --network-services-dir)
            network_services_dir="$2"
            shift 2
            ;;
        --audio-router-dir)
            audio_router_dir="$2"
            shift 2
            ;;
        --nextcommander-dir)
            nextcommander_dir="$2"
            shift 2
            ;;
        --music-player-dir)
            music_player_dir="$2"
            shift 2
            ;;
        --pyxel-runtime-dir)
            pyxel_runtime_dir="$2"
            shift 2
            ;;
        --portmaster-dir)
            portmaster_dir="$2"
            shift 2
            ;;
        --standalone-dir)
            standalone_dir="$2"
            shift 2
            ;;
        --picoarch-dir)
            picoarch_dir="$2"
            shift 2
            ;;
        --retroarch-config)
            retroarch_config_src="$2"
            shift 2
            ;;
        --strict)
            strict=1
            shift
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

retroarch_factory_src="$retroarch_dir/plumos/$retroarch_factory_rel"
ppsspp_factory_src="$standalone_dir/plumos/$ppsspp_factory_rel"

case "$minimum_core_count" in
    ''|*[!0-9]*)
        printf 'error: PLUMOS_V90S_MIN_CORE_COUNT must be a non-negative integer\n' >&2
        exit 2
        ;;
esac

json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

file_size() {
    stat -c %s "$1" 2>/dev/null || stat -f %z "$1"
}

copy_file() {
    src="$1"
    dst="$2"
    mkdir -p "$(dirname "$dst")"
    cp -L "$src" "$dst"
    chmod 0644 "$dst"
}

copy_exec() {
    src="$1"
    dst="$2"
    mkdir -p "$(dirname "$dst")"
    cp -L "$src" "$dst"
    chmod 0755 "$dst"
}

copy_tree() {
    src="$1"
    dst="$2"
    mkdir -p "$dst"
    rsync -a --copy-links "$src"/ "$dst"/
}

record_file() {
    rel="$1"
    component="$2"
    source="$3"
    file="$out_dir/$rel"
    sha="$(sha256sum "$file" | awk '{print $1}')"
    size="$(file_size "$file")"
    printf '{"path":"%s","component":"%s","source":"%s","sha256":"%s","size":%s}\n' \
        "$(json_escape "$rel")" \
        "$(json_escape "$component")" \
        "$(json_escape "$source")" \
        "$sha" \
        "$size" >> "$entries_file"
}

require_or_note_missing() {
    path="$1"
    label="$2"
    if [ -e "$path" ]; then
        return 0
    fi
    printf '%s\n' "$label" >> "$missing_file"
    if [ "$strict" -eq 1 ]; then
        printf 'error: missing %s: %s\n' "$label" "$path" >&2
        exit 1
    fi
    return 1
}

record_tree() {
    src_root="$1"
    component="$2"
    source_root="$3"

    find "$src_root" -type f | sort | while IFS= read -r src; do
        rel="${src#"$src_root"/}"
        record_file "$rel" "$component" "$source_root/$rel"
    done
}

record_mapped_tree() {
    src_root="$1"
    out_prefix="$2"
    component="$3"
    source_root="$4"

    find "$src_root" -type f | sort | while IFS= read -r src; do
        rel="${src#"$src_root"/}"
        record_file "$out_prefix/$rel" "$component" "$source_root/$rel"
    done
}

rm -rf "$out_dir"
mkdir -p \
    "$out_dir/bin" \
    "$out_dir/gnu/bin" \
    "$out_dir/gnu/libexec" \
    "$out_dir/lib/plumos-sdl2-powervr" \
    "$out_dir/apps" \
    "$out_dir/audio-router" \
    "$out_dir/cores" \
    "$out_dir/info" \
    "$out_dir/frontend" \
    "$out_dir/picoarch" \
    "$out_dir/standalone" \
    "$out_dir/config/retroarch" \
    "$out_dir/config/frontend" \
    "$out_dir/config/system" \
    "$out_dir/fonts" \
    "$out_dir/share" \
    "$out_dir/ssh/libexec" \
    "$out_dir/samba/sbin" \
    "$out_dir/state/frontend" \
    "$out_dir/themes" \
    "$out_dir/Images" \
    "$out_dir/media" \
    "$out_dir/music" \
    "$out_dir/roms" \
    "$out_dir/bios" \
    "$out_dir/Saves" \
    "$out_dir/States" \
    "$out_dir/Screenshots" \
    "$out_dir/Logs" \
    "$out_dir/updates" \
    "$out_dir/licenses"

entries_file="$(mktemp)"
missing_file="$(mktemp)"
trap 'rm -f "$entries_file" "$missing_file"' EXIT
: > "$entries_file"
: > "$missing_file"

printf '%s\n' "$version" > "$out_dir/VERSION"
printf '%s\n' "$compat_vendor" > "$out_dir/COMPAT_VENDOR"
printf '%s\n' '1' > "$out_dir/RUNTIME_ABI"
printf '%s\n' "$mount_path" > "$out_dir/MOUNT_PATH"

cat > "$out_dir/licenses/NOTICE.txt" <<'EOF'
plumOS V90S includes runtime components derived from the POWKIDDY V90S
StockOS/Batocera distribution for device compatibility. Bundled open-source
components retain their upstream licenses.
EOF

record_file "VERSION" "metadata" "generated"
record_file "COMPAT_VENDOR" "metadata" "generated"
record_file "RUNTIME_ABI" "metadata" "generated"
record_file "MOUNT_PATH" "metadata" "generated"
record_file "licenses/NOTICE.txt" "notice" "generated"

userland_root="$userland_dir/plumos"
if require_or_note_missing "$userland_root/bin/busybox" "userland"; then
    copy_tree "$userland_root" "$out_dir"
    record_tree "$userland_root" "userland" "$userland_root"
    if [ -f "$userland_dir/userland.manifest" ]; then
        copy_file "$userland_dir/userland.manifest" "$out_dir/licenses/userland-manifest.txt"
        record_file "licenses/userland-manifest.txt" "userland" "$userland_dir/userland.manifest"
    fi
fi

network_services_root="$network_services_dir/plumos"
if require_or_note_missing "$network_services_root/bin/plumos-network-services" "network-services"; then
    copy_tree "$network_services_root" "$out_dir"
    record_tree "$network_services_root" "network-services" "$network_services_root"
    if [ -f "$network_services_dir/network-services.manifest" ]; then
        copy_file "$network_services_dir/network-services.manifest" "$out_dir/licenses/network-services-manifest.txt"
        record_file "licenses/network-services-manifest.txt" "network-services" "$network_services_dir/network-services.manifest"
    fi
fi

audio_router_root="$audio_router_dir/plumos"
if require_or_note_missing "$audio_router_root/lib/alsa-lib/libasound_module_pcm_plumos_hotplug.so" "audio-router"; then
    copy_tree "$audio_router_root" "$out_dir"
    record_tree "$audio_router_root" "audio-router" "$audio_router_root"
    if [ -f "$audio_router_dir/audio-router.manifest" ]; then
        copy_file "$audio_router_dir/audio-router.manifest" "$out_dir/licenses/audio-router-manifest.txt"
        record_file "licenses/audio-router-manifest.txt" "audio-router" "$audio_router_dir/audio-router.manifest"
    fi
    if [ -d "$audio_router_dir/licenses" ]; then
        copy_tree "$audio_router_dir/licenses" "$out_dir/licenses/audio-router"
        record_mapped_tree "$audio_router_dir/licenses" "licenses/audio-router" "audio-router-license" "$audio_router_dir/licenses"
    fi
fi

if require_or_note_missing "$retroarch_config_src" "retroarch-config"; then
    copy_file "$retroarch_config_src" "$out_dir/config/retroarch/v90s-powervr-quicknes.cfg"
    record_file "config/retroarch/v90s-powervr-quicknes.cfg" "retroarch-config" "$retroarch_config_src"
fi

cat > "$out_dir/config/retroarch/plumos-v90s-retroarch-route" <<'EOF'
# plumOS V90S app-layer RetroArch route defaults.
#
# This file is sourced by bin/v90s-retroarch-launch when FE/app-layer launchers
# set PLUMOS_V90S_ROUTE_CONFIG. Use default assignments so explicit user or
# launcher environment overrides remain possible.

: "${PLUMOS_V90S_RETROARCH_BIN:=${PLUMOS_ROOT:-/mnt/plumos}/bin/retroarch}"
: "${PLUMOS_V90S_VIDEO_DRIVER:=gl}"
: "${PLUMOS_V90S_VIDEO_CONTEXT_DRIVER:=mali_fbdev}"
: "${PLUMOS_V90S_VIDEO_THREADED:=true}"
: "${PLUMOS_V90S_VIDEO_REFRESH_RATE:=58.917103}"
: "${PLUMOS_V90S_VRR_RUNLOOP_ENABLE:=true}"
: "${PLUMOS_V90S_INPUT_DRIVER:=sdl2}"
: "${PLUMOS_V90S_JOYPAD_DRIVER:=sdl2}"
: "${PLUMOS_V90S_AUDIO_DRIVER:=alsa}"
: "${PLUMOS_V90S_AUDIO_DEVICE:=plumos_output}"
: "${PLUMOS_V90S_AUDIO_LATENCY:=64}"
: "${PLUMOS_V90S_SDL_VIDEODRIVER:=mali}"
: "${PLUMOS_V90S_SDL_RENDER_DRIVER:=software}"
EOF
chmod 0644 "$out_dir/config/retroarch/plumos-v90s-retroarch-route"
record_file "config/retroarch/plumos-v90s-retroarch-route" "retroarch-route" "generated"

retroarch_src="$retroarch_dir/usr/local/bin/$retroarch_bin"
if require_or_note_missing "$retroarch_src" "retroarch"; then
    copy_exec "$retroarch_src" "$out_dir/bin/retroarch"
    record_file "bin/retroarch" "retroarch" "$retroarch_src"
    if [ -f "$retroarch_dir/manifest.txt" ]; then
        copy_file "$retroarch_dir/manifest.txt" "$out_dir/licenses/retroarch-powervr-manifest.txt"
        record_file "licenses/retroarch-powervr-manifest.txt" "retroarch" "$retroarch_dir/manifest.txt"
    fi
fi

quicknes_src="$cores_dir/quicknes_libretro.so"
cores_stage_dir="$cores_dir/cores"
info_stage_dir="$cores_dir/info"
core_count=0
if [ -d "$cores_stage_dir" ]; then
    for core_src in "$cores_stage_dir"/*_libretro.so; do
        [ -f "$core_src" ] || continue
        core_name="$(basename "$core_src")"
        copy_file "$core_src" "$out_dir/cores/$core_name"
        record_file "cores/$core_name" "libretro-core" "$core_src"
        core_count=$((core_count + 1))
    done
    if [ "$core_count" -eq 0 ]; then
        printf '%s\n' "libretro-cores" >> "$missing_file"
        if [ "$strict" -eq 1 ]; then
            printf 'error: missing libretro cores: %s/*_libretro.so\n' "$cores_stage_dir" >&2
            exit 1
        fi
    fi
    if [ -d "$info_stage_dir" ]; then
        for info_src in "$info_stage_dir"/*.info; do
            [ -f "$info_src" ] || continue
            info_name="$(basename "$info_src")"
            copy_file "$info_src" "$out_dir/info/$info_name"
            record_file "info/$info_name" "libretro-info" "$info_src"
        done
    fi
    if [ -d "$cores_dir/lib" ]; then
        copy_tree "$cores_dir/lib" "$out_dir/lib"
        record_mapped_tree "$cores_dir/lib" "lib" "libretro-runtime" "$cores_dir/lib"
    fi
    if [ -f "$cores_dir/libretro-cores.manifest" ]; then
        copy_file "$cores_dir/libretro-cores.manifest" "$out_dir/licenses/libretro-cores-manifest.txt"
        record_file "licenses/libretro-cores-manifest.txt" "libretro-core" "$cores_dir/libretro-cores.manifest"
    fi
    if [ -f "$cores_dir/checksums.sha256" ]; then
        copy_file "$cores_dir/checksums.sha256" "$out_dir/licenses/libretro-cores-checksums.sha256"
        record_file "licenses/libretro-cores-checksums.sha256" "libretro-core" "$cores_dir/checksums.sha256"
    fi
elif require_or_note_missing "$quicknes_src" "quicknes"; then
    copy_file "$quicknes_src" "$out_dir/cores/quicknes_libretro.so"
    record_file "cores/quicknes_libretro.so" "libretro-core" "$quicknes_src"
    core_count=1
    if [ -f "$cores_dir/quicknes-manifest.txt" ]; then
        copy_file "$cores_dir/quicknes-manifest.txt" "$out_dir/licenses/quicknes-manifest.txt"
        record_file "licenses/quicknes-manifest.txt" "libretro-core" "$cores_dir/quicknes-manifest.txt"
    fi
fi
if [ "$core_count" -lt "$minimum_core_count" ]; then
    printf 'libretro-core-count:%s<%s\n' \
        "$core_count" "$minimum_core_count" >> "$missing_file"
    if [ "$strict" -eq 1 ]; then
        printf 'error: incomplete libretro core set: found %s, require at least %s\n' \
            "$core_count" "$minimum_core_count" >&2
        exit 1
    fi
fi

sdl2_lib_dir="$sdl2_powervr_dir/usr/local/lib/plumos-sdl2-powervr"
if require_or_note_missing "$sdl2_lib_dir/libSDL2-2.0.so.0.3000.6" "sdl2-powervr"; then
    for lib in libSDL2-2.0.so.0.3000.6 libSDL2-2.0.so.0 libSDL2.so; do
        if [ -e "$sdl2_lib_dir/$lib" ]; then
            copy_file "$sdl2_lib_dir/$lib" "$out_dir/lib/plumos-sdl2-powervr/$lib"
            record_file "lib/plumos-sdl2-powervr/$lib" "sdl2-powervr" "$sdl2_lib_dir/$lib"
        fi
    done
    if [ -f "$sdl2_powervr_dir/manifest.txt" ]; then
        copy_file "$sdl2_powervr_dir/manifest.txt" "$out_dir/licenses/sdl2-powervr-manifest.txt"
        record_file "licenses/sdl2-powervr-manifest.txt" "sdl2-powervr" "$sdl2_powervr_dir/manifest.txt"
    fi
fi

frontend_root="$frontend_dir/plumos"
if require_or_note_missing "$frontend_root/bin/plumos-frontend-launch" "frontend"; then
    require_or_note_missing "$frontend_root/bin/plumos-audio-output" "frontend:audio-output" || true
    for frontend_lib in \
        libpng16.so.16 \
        libfreetype.so.6 \
        libbrotlidec.so.1 \
        libbrotlicommon.so.1; do
        require_or_note_missing \
            "$frontend_root/frontend/lib/$frontend_lib" \
            "frontend-runtime:$frontend_lib" || true
    done
    copy_tree "$frontend_root" "$out_dir"
    record_tree "$frontend_root" "frontend" "$frontend_root"
    if [ -f "$frontend_dir/frontend.manifest" ]; then
        copy_file "$frontend_dir/frontend.manifest" "$out_dir/licenses/frontend-manifest.txt"
        record_file "licenses/frontend-manifest.txt" "frontend" "$frontend_dir/frontend.manifest"
    fi
fi

if require_or_note_missing "$retroarch_factory_src" "retroarch:factory-config"; then
    retroarch_factory_dst="$out_dir/$retroarch_factory_rel"
    if [ -f "$retroarch_factory_dst" ]; then
        if ! cmp -s "$retroarch_factory_src" "$retroarch_factory_dst"; then
            printf 'error: frontend and RetroArch factory configs do not match:\n  %s\n  %s\n' \
                "$retroarch_factory_src" "$retroarch_factory_dst" >&2
            exit 1
        fi
    else
        copy_file "$retroarch_factory_src" "$retroarch_factory_dst"
        record_file "$retroarch_factory_rel" "retroarch-factory-config" "$retroarch_factory_src"
    fi
fi

nextcommander_root="$nextcommander_dir/plumos"
if require_or_note_missing "$nextcommander_root/apps/nextcommander/bin/NextCommander" "nextcommander"; then
    copy_tree "$nextcommander_root" "$out_dir"
    record_tree "$nextcommander_root" "nextcommander" "$nextcommander_root"
fi

music_player_root="$music_player_dir/plumos"
if require_or_note_missing "$music_player_root/apps/music-player/bin/plumos-music-player.bin" "music-player"; then
    copy_tree "$music_player_root" "$out_dir"
    record_tree "$music_player_root" "music-player" "$music_player_root"
fi

portmaster_root="$portmaster_dir/plumos"
if require_or_note_missing "$portmaster_root/apps/portmaster/upstream/PortMaster/pugwash" "portmaster"; then
    require_or_note_missing "$portmaster_root/bin/plumos-portmaster-launch" "portmaster:launcher" || true
    require_or_note_missing "$portmaster_root/bin/plumos-portmaster-update" "portmaster:updater" || true
    require_or_note_missing "$portmaster_root/bin/plumos-portmaster-port-stop" "portmaster:port-stop" || true
    require_or_note_missing "$portmaster_root/apps/portmaster/adapter/control.txt" "portmaster:adapter" || true
    copy_tree "$portmaster_root" "$out_dir"
    record_tree "$portmaster_root" "portmaster" "$portmaster_root"
    if [ -f "$portmaster_dir/portmaster.manifest" ]; then
        copy_file "$portmaster_dir/portmaster.manifest" "$out_dir/licenses/portmaster-manifest.txt"
        record_file "licenses/portmaster-manifest.txt" "portmaster" "$portmaster_dir/portmaster.manifest"
    fi
    if [ -f "$portmaster_dir/checksums.sha256" ]; then
        copy_file "$portmaster_dir/checksums.sha256" "$out_dir/licenses/portmaster-checksums.sha256"
        record_file "licenses/portmaster-checksums.sha256" "portmaster" "$portmaster_dir/checksums.sha256"
    fi
fi

if require_or_note_missing "$standalone_dir/bin/plumos-standalone-launch" "standalone-emulators"; then
    if [ -d "$standalone_dir/standalone" ]; then
        copy_tree "$standalone_dir/standalone" "$out_dir/standalone"
        record_mapped_tree "$standalone_dir/standalone" "standalone" "standalone-emulator" "$standalone_dir/standalone"
    fi
    copy_exec "$standalone_dir/bin/plumos-standalone-launch" "$out_dir/bin/plumos-standalone-launch"
    record_file "bin/plumos-standalone-launch" "standalone-launcher" "$standalone_dir/bin/plumos-standalone-launch"
    if [ -x "$standalone_dir/bin/plumos-standalone-stop" ]; then
        copy_exec "$standalone_dir/bin/plumos-standalone-stop" "$out_dir/bin/plumos-standalone-stop"
        record_file "bin/plumos-standalone-stop" "standalone-stop-helper" "$standalone_dir/bin/plumos-standalone-stop"
    fi
    if [ -d "$standalone_dir/config/standalone" ]; then
        copy_tree "$standalone_dir/config/standalone" "$out_dir/config/standalone"
        record_mapped_tree "$standalone_dir/config/standalone" "config/standalone" "standalone-config" "$standalone_dir/config/standalone"
    fi
    if [ -d "$standalone_dir/licenses" ]; then
        mkdir -p "$out_dir/licenses/standalone"
        copy_tree "$standalone_dir/licenses" "$out_dir/licenses/standalone"
        record_mapped_tree "$standalone_dir/licenses" "licenses/standalone" "standalone-license" "$standalone_dir/licenses"
    fi
    if [ -d "$standalone_dir/lib" ]; then
        copy_tree "$standalone_dir/lib" "$out_dir/lib"
        record_mapped_tree "$standalone_dir/lib" "lib" "standalone-library" "$standalone_dir/lib"
    fi
    if [ -f "$standalone_dir/standalone-emulators.manifest" ]; then
        copy_file "$standalone_dir/standalone-emulators.manifest" "$out_dir/licenses/standalone-emulators-manifest.txt"
        record_file "licenses/standalone-emulators-manifest.txt" "standalone-emulator" "$standalone_dir/standalone-emulators.manifest"
    fi
fi

ppsspp_factory_ready=1
for ppsspp_factory_name in ppsspp.ini controls.ini; do
    require_or_note_missing \
        "$ppsspp_factory_src/$ppsspp_factory_name" \
        "standalone:ppsspp-factory-$ppsspp_factory_name" || ppsspp_factory_ready=0
done
if [ "$ppsspp_factory_ready" -eq 1 ]; then
    for ppsspp_factory_name in ppsspp.ini controls.ini; do
        ppsspp_factory_file_src="$ppsspp_factory_src/$ppsspp_factory_name"
        ppsspp_factory_file_rel="$ppsspp_factory_rel/$ppsspp_factory_name"
        ppsspp_factory_file_dst="$out_dir/$ppsspp_factory_file_rel"
        if [ -f "$ppsspp_factory_file_dst" ]; then
            if ! cmp -s "$ppsspp_factory_file_src" "$ppsspp_factory_file_dst"; then
                printf 'error: frontend and PPSSPP factory configs do not match:\n  %s\n  %s\n' \
                    "$ppsspp_factory_file_src" "$ppsspp_factory_file_dst" >&2
                exit 1
            fi
        else
            copy_file "$ppsspp_factory_file_src" "$ppsspp_factory_file_dst"
            record_file "$ppsspp_factory_file_rel" \
                "ppsspp-factory-config" "$ppsspp_factory_file_src"
        fi
    done
fi

retroarch_soname_map="$out_dir/config/standalone/soname-links.tsv"
if require_or_note_missing "$retroarch_soname_map" "retroarch-runtime-soname-map"; then
    while IFS="$(printf '\t')" read -r soname real_name; do
        [ -n "$soname" ] || continue
        require_or_note_missing \
            "$out_dir/lib/$real_name" \
            "retroarch-runtime:$soname" || true
    done < "$retroarch_soname_map"
fi

if require_or_note_missing "$picoarch_dir/bin/plumos-picoarch-launch" "picoarch"; then
    copy_tree "$picoarch_dir/picoarch" "$out_dir/picoarch"
    record_mapped_tree "$picoarch_dir/picoarch" "picoarch" "picoarch-runtime" "$picoarch_dir/picoarch"
    for launcher in plumos-picoarch-launch plumos-picoarch-stop; do
        copy_exec "$picoarch_dir/bin/$launcher" "$out_dir/bin/$launcher"
        record_file "bin/$launcher" "picoarch-launcher" "$picoarch_dir/bin/$launcher"
    done
    if [ -d "$picoarch_dir/config/standalone" ]; then
        copy_tree "$picoarch_dir/config/standalone" "$out_dir/config/standalone"
        record_mapped_tree "$picoarch_dir/config/standalone" "config/standalone" "picoarch-config" "$picoarch_dir/config/standalone"
    fi
    if [ -d "$picoarch_dir/licenses" ]; then
        mkdir -p "$out_dir/licenses/picoarch"
        copy_tree "$picoarch_dir/licenses" "$out_dir/licenses/picoarch"
        record_mapped_tree "$picoarch_dir/licenses" "licenses/picoarch" "picoarch-license" "$picoarch_dir/licenses"
    fi
    if [ -f "$picoarch_dir/picoarch.manifest" ]; then
        copy_file "$picoarch_dir/picoarch.manifest" "$out_dir/licenses/picoarch-manifest.txt"
        record_file "licenses/picoarch-manifest.txt" "picoarch-runtime" "$picoarch_dir/picoarch.manifest"
    fi
fi

pyxel_runtime_root="$pyxel_runtime_dir/plumos"
if require_or_note_missing "$pyxel_runtime_root/venvs/pyxel/bin/python3" "pyxel-runtime"; then
    copy_tree "$pyxel_runtime_root" "$out_dir"
    record_tree "$pyxel_runtime_root" "pyxel-runtime" "$pyxel_runtime_root"
    if [ -f "$pyxel_runtime_dir/pyxel-runtime.manifest" ]; then
        copy_file "$pyxel_runtime_dir/pyxel-runtime.manifest" "$out_dir/licenses/pyxel-runtime-manifest.txt"
        record_file "licenses/pyxel-runtime-manifest.txt" "pyxel-runtime" "$pyxel_runtime_dir/pyxel-runtime.manifest"
    fi
    if [ -f "$pyxel_runtime_dir/checksums.sha256" ]; then
        copy_file "$pyxel_runtime_dir/checksums.sha256" "$out_dir/licenses/pyxel-runtime-checksums.sha256"
        record_file "licenses/pyxel-runtime-checksums.sha256" "pyxel-runtime" "$pyxel_runtime_dir/checksums.sha256"
    fi
fi

generated_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
if [ -s "$missing_file" ]; then
    complete=false
else
    complete=true
fi
{
    printf '{\n'
    printf '  "name": "plumOS V90S app layer",\n'
    printf '  "version": "%s",\n' "$(json_escape "$version")"
    printf '  "compat_vendor": "%s",\n' "$(json_escape "$compat_vendor")"
    printf '  "mount_path": "%s",\n' "$(json_escape "$mount_path")"
    printf '  "generated_at": "%s",\n' "$generated_at"
    printf '  "complete": %s,\n' "$complete"
    printf '  "libretro_core_count": %s,\n' "$core_count"
    printf '  "minimum_libretro_core_count": %s,\n' "$minimum_core_count"
    printf '  "directories": [\n'
    printf '    "bin", "lib", "apps", "audio-router", "cores", "info", "frontend", "picoarch", "standalone",\n'
    printf '    "config", "fonts", "share", "state", "themes", "Images", "media",\n'
    printf '    "roms", "bios", "Saves", "States", "Screenshots", "Logs",\n'
    printf '    "updates", "licenses"\n'
    printf '  ],\n'
    printf '  "missing_optional": ['
    first=1
    while IFS= read -r missing; do
        [ -n "$missing" ] || continue
        if [ "$first" -eq 0 ]; then
            printf ', '
        fi
        printf '"%s"' "$(json_escape "$missing")"
        first=0
    done < "$missing_file"
    printf '],\n'
    printf '  "files": [\n'
    first=1
    while IFS= read -r entry; do
        [ -n "$entry" ] || continue
        if [ "$first" -eq 0 ]; then
            printf ',\n'
        fi
        printf '    %s' "$entry"
        first=0
    done < "$entries_file"
    printf '\n  ]\n'
    printf '}\n'
} > "$out_dir/manifest.json"

find "$out_dir" -type f ! -name checksums.sha256 | sort | while IFS= read -r file; do
    rel="${file#"$out_dir"/}"
    sha="$(sha256sum "$file" | awk '{print $1}')"
    printf '%s  %s\n' "$sha" "$rel"
done > "$out_dir/checksums.sha256"

printf 'created: %s\n' "$out_dir"
printf 'version: %s\n' "$version"
printf 'compat_vendor: %s\n' "$compat_vendor"
printf 'mount_path: %s\n' "$mount_path"
