#!/usr/bin/env sh
set -eu

root_dir="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
app_layer="${1:-$root_dir/output/app-layer/v90s}"
recipes="${PLUMOS_V90S_CORE_RECIPES:-$root_dir/docker/plumos-v90s-toolchain/libretro-core-recipes.tsv}"
failures=0

fail() {
    printf 'license-audit: FAIL: %s\n' "$*" >&2
    failures=$((failures + 1))
}

require_file() {
    path="$app_layer/$1"
    [ -s "$path" ] || fail "missing or empty: $1"
}

require_glob() {
    pattern="$1"
    label="$2"
    find "$app_layer" -type f -path "$app_layer/$pattern" -print -quit 2>/dev/null |
        grep -q . || fail "missing $label: $pattern"
}

[ -d "$app_layer" ] || {
    printf 'license-audit: app-layer not found: %s\n' "$app_layer" >&2
    exit 1
}

for path in \
    licenses/plumOS-MIT.txt \
    licenses/NOTICE.txt \
    licenses/THIRD_PARTY_NOTICES.md \
    licenses/THIRD_PARTY_NOTICES.ja.md \
    licenses/v90s-stockos-vendor-runtime-NOTICE.txt \
    licenses/retroarch/RetroArch-COPYING \
    licenses/retroarch-powervr-manifest.txt \
    licenses/libretro-cores-manifest.txt \
    licenses/standalone-emulators-manifest.txt \
    licenses/portmaster-manifest.txt \
    share/doc/plumos-frontend/NotoSansJP-OFL.txt \
    share/doc/plumos-frontend/WQYMicroHei-Apache-2.0.txt; do
    require_file "$path"
done

[ -f "$recipes" ] || fail "core recipe inventory is missing: $recipes"
if [ -f "$recipes" ]; then
    while IFS='|' read -r id class repo ref rest; do
        case "$id" in ''|'#'*) continue ;; esac
        [ -n "$repo" ] || continue
        require_glob "licenses/libretro-cores/${id}-*" "libretro core license material for $id"
    done < "$recipes"
fi

for id in ppsspp scummvm easyrpg openbor pcsx_rearmed flycast mupen64plus nxengine-evo yabasanshiro; do
    require_glob "licenses/standalone/${id}-*" "standalone license material for $id"
done

require_glob "licenses/picoarch/*LICENSE*" "PicoArch license material"
require_glob "apps/portmaster/upstream/PortMaster/licenses/LICENSE-*" "PortMaster upstream licenses"
for path in \
    licenses/openal-soft-LGPL-2.0-or-later.txt \
    licenses/ffmpeg-compat-LGPL-2.1-or-later.txt \
    licenses/libevdev-MIT.txt \
    licenses/flac-compat-Xiph-BSD.txt \
    licenses/libjpeg-compat-IJG.txt \
    licenses/readline-compat-GPL-3.0-or-later.txt; do
    require_file "$path"
done
require_glob "venvs/pyxel/lib/python*/site-packages/pyxel/LICENSE" "Pyxel license"

if [ "$failures" -ne 0 ]; then
    printf 'license-audit: failed=%s\n' "$failures" >&2
    exit 1
fi

core_license_count="$(find "$app_layer/licenses/libretro-cores" -type f 2>/dev/null | wc -l | tr -d '[:space:]')"
standalone_license_count="$(find "$app_layer/licenses/standalone" -type f 2>/dev/null | wc -l | tr -d '[:space:]')"
portmaster_license_count="$(find "$app_layer/apps/portmaster/upstream/PortMaster/licenses" -type f 2>/dev/null | wc -l | tr -d '[:space:]')"
printf 'license-audit: PASS\n'
printf 'app_layer=%s\n' "$app_layer"
printf 'libretro_core_license_files=%s\n' "$core_license_count"
printf 'standalone_license_files=%s\n' "$standalone_license_count"
printf 'portmaster_upstream_license_files=%s\n' "$portmaster_license_count"
