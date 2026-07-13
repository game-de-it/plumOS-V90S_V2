#!/usr/bin/env sh
set -eu

app_layer_dir="${PLUMOS_V90S_APP_LAYER_DIR:-output/app-layer/v90s}"
dist_dir="${PLUMOS_V90S_DIST_DIR:-dist}"
version="${PLUMOS_V90S_RELEASE_VERSION:-}"
compat_vendor="${PLUMOS_V90S_VENDOR_RUNTIME_ID:-v90s-stockos-r1}"
make_zip=1

usage() {
    cat <<'USAGE'
Usage:
  build-release.sh [options]

Options:
  --app-layer-dir PATH  App-layer input directory; default output/app-layer/v90s.
  --dist-dir PATH       Release output directory; default dist.
  --version VERSION     Release version; default reads app-layer VERSION.
  --compat-vendor ID    Compatible vendor runtime; default v90s-stockos-r1.
  --no-zip              Do not generate a zip archive.
USAGE
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --app-layer-dir)
            app_layer_dir="$2"
            shift 2
            ;;
        --dist-dir)
            dist_dir="$2"
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
        --no-zip)
            make_zip=0
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

if [ ! -d "$app_layer_dir" ]; then
    printf 'error: app-layer input not found: %s\n' "$app_layer_dir" >&2
    printf 'hint: run ./scripts/docker-build.sh app-layer --strict first\n' >&2
    exit 1
fi
if [ ! -f "$app_layer_dir/manifest.json" ]; then
    printf 'error: app-layer manifest missing: %s/manifest.json\n' "$app_layer_dir" >&2
    printf 'hint: run ./scripts/docker-build.sh app-layer --strict first\n' >&2
    exit 1
fi
if ! python3 - "$app_layer_dir/manifest.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    manifest = json.load(handle)
missing = manifest.get("missing_optional", [])
complete = manifest.get("complete", not missing)
if missing or not complete:
    print(
        "error: app-layer is incomplete; missing: " + ", ".join(missing),
        file=sys.stderr,
    )
    sys.exit(1)
PY
then
    printf 'hint: rebuild every app-layer input, then run app-layer --strict\n' >&2
    exit 1
fi
if [ -z "$version" ]; then
    if [ ! -f "$app_layer_dir/VERSION" ]; then
        printf 'error: --version is required when app-layer VERSION is missing\n' >&2
        exit 2
    fi
    version="$(sed -n '1p' "$app_layer_dir/VERSION")"
fi
if [ -z "$version" ]; then
    printf 'error: release version is empty\n' >&2
    exit 2
fi

if [ -f "$app_layer_dir/COMPAT_VENDOR" ]; then
    app_compat_vendor="$(sed -n '1p' "$app_layer_dir/COMPAT_VENDOR")"
    if [ "$app_compat_vendor" != "$compat_vendor" ]; then
        printf 'error: app-layer COMPAT_VENDOR mismatch: %s != %s\n' "$app_compat_vendor" "$compat_vendor" >&2
        exit 1
    fi
fi

if find "$app_layer_dir/roms" -type f 2>/dev/null | grep -q .; then
    printf 'error: app-layer roms/ contains files; release packages must not contain ROMs\n' >&2
    exit 1
fi

release_name="plumos-v90s-update-$version"
release_root="$dist_dir/$release_name"
archive_tgz="$dist_dir/$release_name.tar.gz"
archive_zip="$dist_dir/$release_name.zip"

rm -rf "$release_root" "$archive_tgz" "$archive_zip"
mkdir -p "$release_root" "$dist_dir"
rsync -a --delete "$app_layer_dir"/ "$release_root"/

if find "$release_root" -type l | grep -q .; then
    printf 'error: release output contains symlinks, not FAT32-safe:\n' >&2
    find "$release_root" -type l >&2
    exit 1
fi

app_manifest_sha=missing
if [ -f "$app_layer_dir/manifest.json" ]; then
    app_manifest_sha="$(sha256sum "$app_layer_dir/manifest.json" | awk '{print $1}')"
fi
generated_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
cat > "$release_root/release-manifest.json" <<EOF
{
  "name": "plumOS V90S update package",
  "type": "update-only",
  "version": "$(json_escape "$version")",
  "compat_vendor": "$(json_escape "$compat_vendor")",
  "app_layer": "$(json_escape "$app_layer_dir")",
  "app_layer_manifest_sha256": "$app_manifest_sha",
  "copy_target": "/mnt/plumos",
  "generated_at": "$generated_at"
}
EOF

find "$release_root" -type f ! -name release-checksums.sha256 | sort | while IFS= read -r file; do
    rel="${file#"$release_root"/}"
    sha="$(sha256sum "$file" | awk '{print $1}')"
    printf '%s  %s\n' "$sha" "$rel"
done > "$release_root/release-checksums.sha256"

tar -czf "$archive_tgz" -C "$dist_dir" "$release_name"

archive_checksums="$dist_dir/$release_name-SHA256SUMS"
: > "$archive_checksums"
sha="$(sha256sum "$archive_tgz" | awk '{print $1}')"
printf '%s  %s\n' "$sha" "$(basename "$archive_tgz")" >> "$archive_checksums"

if [ "$make_zip" -eq 1 ]; then
    if command -v zip >/dev/null 2>&1; then
        (
            cd "$dist_dir"
            zip -qr "$(basename "$archive_zip")" "$release_name"
        )
        sha="$(sha256sum "$archive_zip" | awk '{print $1}')"
        printf '%s  %s\n' "$sha" "$(basename "$archive_zip")" >> "$archive_checksums"
    else
        printf 'warning: zip not found; skipped zip archive\n' >&2
    fi
fi

printf 'created: %s\n' "$release_root"
printf 'created: %s\n' "$archive_tgz"
if [ -f "$archive_zip" ]; then
    printf 'created: %s\n' "$archive_zip"
fi
printf 'created: %s\n' "$archive_checksums"
printf 'version: %s\n' "$version"
printf 'compat_vendor: %s\n' "$compat_vendor"
printf 'files: %s\n' "$(find "$release_root" -type f | wc -l | tr -d '[:space:]')"
