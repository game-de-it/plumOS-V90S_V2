#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
ARTIFACT_DIR="${1:-$ROOT_DIR/artifacts/vendor/v90s-stockos-r1}"
ARCHIVE="$ARTIFACT_DIR/files/stockos-selected-files.tar.gz"
export COPYFILE_DISABLE=1

case "$ARTIFACT_DIR" in
    ""|/|.|..)
        printf 'error: unsafe artifact directory: %s\n' "$ARTIFACT_DIR" >&2
        exit 2
        ;;
esac
[ -f "$ARCHIVE" ] || {
    printf 'error: vendor archive not found: %s\n' "$ARCHIVE" >&2
    exit 1
}

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/plumos-v90s-vendor-sanitize.XXXXXX")"
cleanup() {
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

mkdir -p "$WORK_DIR/root"
tar --no-xattrs -xzf "$ARCHIVE" -C "$WORK_DIR/root"

sanitize_config() {
    config_path="$1"
    [ -f "$config_path" ] || return 0
    temp_path="$config_path.sanitized"
    awk '
        /^[[:space:]#]*rootshadowpassword=/ {
            print "# rootshadowpassword removed from redistributable vendor artifact"
            next
        }
        /^[[:space:]]*randomseed=/ {
            print "# randomseed removed from redistributable vendor artifact"
            next
        }
        /^[[:space:]]*wifi([0-9]+)?\.(ssid|key)=/ {
            split($0, parts, "=")
            print parts[1] "="
            next
        }
        { print }
    ' "$config_path" > "$temp_path"
    mv "$temp_path" "$config_path"
}

sanitize_config "$WORK_DIR/root/media/BATOCERA/batocera-boot.conf"
sanitize_config "$WORK_DIR/root/media/BATOCERA/preinstall/batocera.conf"

tar --no-xattrs -czf "$ARCHIVE" -C "$WORK_DIR/root" .
tar -tzf "$ARCHIVE" | sort > "$ARTIFACT_DIR/file-list.txt"

if ! grep -q '^Sanitized for redistribution:' "$ARTIFACT_DIR/README.txt"; then
    {
        printf '\n'
        printf 'Sanitized for redistribution: yes\n'
        printf 'Removed fields: active rootshadowpassword, randomseed, Wi-Fi SSID/key values\n'
        printf 'ROM, BIOS, save, SSH key, and personal network content: not included\n'
    } >> "$ARTIFACT_DIR/README.txt"
fi

(
    cd "$ARTIFACT_DIR"
    find . -type f ! -name SHA256SUMS -print0 |
        sort -z |
        xargs -0 shasum -a 256 > SHA256SUMS
    shasum -a 256 -c SHA256SUMS
)

for config_path in \
    "$WORK_DIR/root/media/BATOCERA/batocera-boot.conf" \
    "$WORK_DIR/root/media/BATOCERA/preinstall/batocera.conf"; do
    [ -f "$config_path" ] || continue
    if grep -Eq '^[[:space:]#]*(rootshadowpassword|randomseed)=.+$' "$config_path" ||
       grep -Eq '^[[:space:]]*wifi([0-9]+)?\.(ssid|key)=.+$' \
        "$config_path"; then
        printf 'error: sensitive StockOS setting remains: %s\n' "$config_path" >&2
        exit 1
    fi
done

printf 'sanitized: %s\n' "$ARTIFACT_DIR"
