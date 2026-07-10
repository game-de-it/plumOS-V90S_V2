#!/usr/bin/env bash
set -euo pipefail

vendor_id="${PLUMOS_V90S_VENDOR_RUNTIME_ID:-v90s-stockos-r1}"
default_src_dir="artifacts/vendor/$vendor_id"
legacy_src_dir="artifacts/20260710-stockos-runtime"
src_dir="${PLUMOS_V90S_STOCKOS_ARTIFACT:-$default_src_dir}"
out_dir="${PLUMOS_V90S_VENDOR_RUNTIME_OUT:-output/vendor/$vendor_id}"
compat_out="${PLUMOS_V90S_VENDOR_RUNTIME_COMPAT_OUT:-output/vendor/stockos-runtime}"
captured_at="${PLUMOS_V90S_VENDOR_CAPTURED_AT:-2026-07-10}"
src_dir_explicit=0
out_dir_explicit=0
compat_out_explicit=0

if [ -n "${PLUMOS_V90S_STOCKOS_ARTIFACT:-}" ]; then
    src_dir_explicit=1
fi
if [ -n "${PLUMOS_V90S_VENDOR_RUNTIME_OUT:-}" ]; then
    out_dir_explicit=1
fi
if [ -n "${PLUMOS_V90S_VENDOR_RUNTIME_COMPAT_OUT:-}" ]; then
    compat_out_explicit=1
fi

usage() {
    cat <<EOF
Usage:
  scripts/prepare-stockos-runtime.sh [options]

Options:
  --src-dir PATH        StockOS extraction directory; default $default_src_dir
  --out-dir PATH        Prepared vendor runtime directory; default output/vendor/$vendor_id
  --compat-out PATH     Compatibility alias; default output/vendor/stockos-runtime
  --vendor-id ID        Vendor runtime ID; default $vendor_id

The prepared directory is a build input for the V90S Docker flow. It contains an
unpacked selected StockOS/Batocera runtime tree plus raw boot/env partitions.
EOF
}

sha256_value() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

write_sha256sums() {
    dest="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        find "$dest" -type f ! -name SHA256SUMS -print0 |
            sort -z |
            xargs -0 sha256sum > "$dest/SHA256SUMS"
    else
        find "$dest" -type f ! -name SHA256SUMS -print0 |
            sort -z |
            xargs -0 shasum -a 256 > "$dest/SHA256SUMS"
    fi
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --src-dir)
            src_dir="$2"
            src_dir_explicit=1
            shift 2
            ;;
        --out-dir)
            out_dir="$2"
            out_dir_explicit=1
            shift 2
            ;;
        --compat-out)
            compat_out="$2"
            compat_out_explicit=1
            shift 2
            ;;
        --vendor-id)
            vendor_id="$2"
            default_src_dir="artifacts/vendor/$vendor_id"
            if [ "$src_dir_explicit" -eq 0 ]; then
                src_dir="$default_src_dir"
            fi
            if [ "$out_dir_explicit" -eq 0 ]; then
                out_dir="output/vendor/$vendor_id"
            fi
            if [ "$compat_out_explicit" -eq 0 ]; then
                compat_out="output/vendor/stockos-runtime"
            fi
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

if [ "$src_dir_explicit" -eq 0 ] &&
    [ ! -f "$src_dir/files/stockos-selected-files.tar.gz" ] &&
    [ -f "$legacy_src_dir/files/stockos-selected-files.tar.gz" ]; then
    printf 'warning: default vendor source not found: %s\n' "$src_dir" >&2
    printf 'warning: using legacy source for this run: %s\n' "$legacy_src_dir" >&2
    printf 'warning: move or copy it to %s for the policy-aligned layout\n' "$default_src_dir" >&2
    src_dir="$legacy_src_dir"
fi

selected_tar="$src_dir/files/stockos-selected-files.tar.gz"
raw_dir="$src_dir/raw-partitions"

if [ ! -f "$selected_tar" ]; then
    printf 'error: selected StockOS file tarball not found: %s\n' "$selected_tar" >&2
    exit 1
fi
if [ ! -d "$raw_dir" ]; then
    printf 'error: raw StockOS partition directory not found: %s\n' "$raw_dir" >&2
    exit 1
fi

rm -rf "$out_dir"
mkdir -p "$out_dir/root" "$out_dir/raw-partitions"

tar -C "$out_dir/root" -xzf "$selected_tar"
cp -a "$raw_dir/." "$out_dir/raw-partitions/"
if [ -d "$src_dir/raw-boot-chain" ]; then
    mkdir -p "$out_dir/raw-boot-chain"
    cp -a "$src_dir/raw-boot-chain/." "$out_dir/raw-boot-chain/"
fi

if [ -f "$src_dir/file-list.txt" ]; then
    cp "$src_dir/file-list.txt" "$out_dir/source-file-list.txt"
fi
if [ -f "$src_dir/SHA256SUMS" ]; then
    cp "$src_dir/SHA256SUMS" "$out_dir/source-SHA256SUMS"
fi

manifest="$out_dir/vendor-runtime.manifest"
selected_tar_sha256="$(sha256_value "$selected_tar")"
source_sha256sums_sha256=none
if [ -f "$src_dir/SHA256SUMS" ]; then
    source_sha256sums_sha256="$(sha256_value "$src_dir/SHA256SUMS")"
fi

cat > "$manifest" <<EOF
id=$vendor_id
source=$src_dir
selected_tar=$selected_tar
selected_tar_sha256=$selected_tar_sha256
source_sha256sums=$src_dir/SHA256SUMS
source_sha256sums_sha256=$source_sha256sums_sha256
captured_at=$captured_at
prepared_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
kernel=Linux 4.9.191
boot_model=a133-b6
gpu=PowerVR GE8300
display_route=mali_fbdev
known_good_step2=yes
known_good_doc=docs/validation/2026-07-10-step2-stockos-video-perfect-runtime.md
root=$out_dir/root
raw_partitions=$out_dir/raw-partitions
raw_boot_chain=$out_dir/raw-boot-chain
compat_alias=$compat_out
notice=Includes files derived from the user's POWKIDDY V90S StockOS/Batocera image for plumOS V90S runtime compatibility.
EOF
cp "$manifest" "$out_dir/manifest.txt"

write_sha256sums "$out_dir"

if [ -n "$compat_out" ] && [ "$compat_out" != "$out_dir" ]; then
    compat_parent="$(dirname -- "$compat_out")"
    out_parent="$(dirname -- "$out_dir")"
    mkdir -p "$compat_parent"
    if [ "$compat_parent" = "$out_parent" ]; then
        rm -rf "$compat_out"
        ln -s "$(basename -- "$out_dir")" "$compat_out"
    else
        printf 'warning: not creating compatibility alias across different parents: %s -> %s\n' "$compat_out" "$out_dir" >&2
    fi
fi

printf 'prepared: %s\n' "$out_dir"
printf 'manifest: %s\n' "$manifest"
printf 'compat alias: %s\n' "$compat_out"
du -sh "$out_dir"
