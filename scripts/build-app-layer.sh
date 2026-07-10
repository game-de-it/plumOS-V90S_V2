#!/usr/bin/env sh
set -eu

out_dir="${PLUMOS_V90S_APP_LAYER_OUT:-output/app-layer/v90s}"
version="${PLUMOS_V90S_APP_LAYER_VERSION:-0.1.0-dev}"
compat_vendor="${PLUMOS_V90S_VENDOR_RUNTIME_ID:-v90s-stockos-r1}"
mount_path="${PLUMOS_V90S_APP_LAYER_MOUNT:-/mnt/plumos}"
retroarch_dir="${PLUMOS_V90S_RETROARCH_DIR:-output/retroarch-powervr}"
retroarch_bin="${PLUMOS_V90S_RETROARCH_BIN_NAME:-retroarch-powervr}"
cores_dir="${PLUMOS_V90S_CORES_DIR:-output/libretro-quicknes}"
sdl2_powervr_dir="${PLUMOS_V90S_SDL2_POWERVR_DIR:-output/sdl2-powervr}"
frontend_dir="${PLUMOS_V90S_FRONTEND_DIR:-output/frontend/v90s}"
retroarch_config_src="${PLUMOS_V90S_RETROARCH_CONFIG_SRC:-configs/retroarch/v90s-powervr-quicknes.cfg}"
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
  --cores-dir PATH       Libretro cores payload; default output/libretro-quicknes.
  --sdl2-powervr-dir PATH
                          SDL2 PowerVR payload; default output/sdl2-powervr.
  --frontend-dir PATH    Frontend payload; default output/frontend/v90s.
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

rm -rf "$out_dir"
mkdir -p \
    "$out_dir/bin" \
    "$out_dir/lib/plumos-sdl2-powervr" \
    "$out_dir/cores" \
    "$out_dir/frontend" \
    "$out_dir/picoarch" \
    "$out_dir/standalone" \
    "$out_dir/config/retroarch" \
    "$out_dir/config/frontend" \
    "$out_dir/config/system" \
    "$out_dir/fonts" \
    "$out_dir/share" \
    "$out_dir/state/frontend" \
    "$out_dir/themes" \
    "$out_dir/media" \
    "$out_dir/Roms" \
    "$out_dir/BIOS" \
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
printf '%s\n' "$mount_path" > "$out_dir/MOUNT_PATH"

cat > "$out_dir/licenses/NOTICE.txt" <<'EOF'
plumOS V90S includes runtime components derived from the POWKIDDY V90S
StockOS/Batocera distribution for device compatibility. Bundled open-source
components retain their upstream licenses.
EOF

record_file "VERSION" "metadata" "generated"
record_file "COMPAT_VENDOR" "metadata" "generated"
record_file "MOUNT_PATH" "metadata" "generated"
record_file "licenses/NOTICE.txt" "notice" "generated"

if require_or_note_missing "$retroarch_config_src" "retroarch-config"; then
    copy_file "$retroarch_config_src" "$out_dir/config/retroarch/v90s-powervr-quicknes.cfg"
    record_file "config/retroarch/v90s-powervr-quicknes.cfg" "retroarch-config" "$retroarch_config_src"
fi

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
if require_or_note_missing "$quicknes_src" "quicknes"; then
    copy_file "$quicknes_src" "$out_dir/cores/quicknes_libretro.so"
    record_file "cores/quicknes_libretro.so" "libretro-core" "$quicknes_src"
    if [ -f "$cores_dir/quicknes-manifest.txt" ]; then
        copy_file "$cores_dir/quicknes-manifest.txt" "$out_dir/licenses/quicknes-manifest.txt"
        record_file "licenses/quicknes-manifest.txt" "libretro-core" "$cores_dir/quicknes-manifest.txt"
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
    copy_tree "$frontend_root" "$out_dir"
    record_tree "$frontend_root" "frontend" "$frontend_root"
    if [ -f "$frontend_dir/frontend.manifest" ]; then
        copy_file "$frontend_dir/frontend.manifest" "$out_dir/licenses/frontend-manifest.txt"
        record_file "licenses/frontend-manifest.txt" "frontend" "$frontend_dir/frontend.manifest"
    fi
fi

generated_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
{
    printf '{\n'
    printf '  "name": "plumOS V90S app layer",\n'
    printf '  "version": "%s",\n' "$(json_escape "$version")"
    printf '  "compat_vendor": "%s",\n' "$(json_escape "$compat_vendor")"
    printf '  "mount_path": "%s",\n' "$(json_escape "$mount_path")"
    printf '  "generated_at": "%s",\n' "$generated_at"
    printf '  "directories": [\n'
    printf '    "bin", "lib", "cores", "frontend", "picoarch", "standalone",\n'
    printf '    "config", "fonts", "share", "state", "themes", "media",\n'
    printf '    "Roms", "BIOS", "Saves", "States", "Screenshots", "Logs",\n'
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
