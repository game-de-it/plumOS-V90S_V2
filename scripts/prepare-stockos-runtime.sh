#!/usr/bin/env bash
set -euo pipefail

src_dir="${PLUMOS_V90S_STOCKOS_ARTIFACT:-artifacts/20260710-stockos-runtime}"
out_dir="${PLUMOS_V90S_VENDOR_RUNTIME_OUT:-output/vendor/stockos-runtime}"

usage() {
    cat <<'EOF'
Usage:
  scripts/prepare-stockos-runtime.sh [options]

Options:
  --src-dir PATH   StockOS extraction directory; default artifacts/20260710-stockos-runtime
  --out-dir PATH   Prepared vendor runtime directory; default output/vendor/stockos-runtime

The prepared directory is a build input for the V90S Docker flow. It contains an
unpacked selected StockOS/Batocera runtime tree plus raw boot/env partitions.
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --src-dir)
            src_dir="$2"
            shift 2
            ;;
        --out-dir)
            out_dir="$2"
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

if [ -f "$src_dir/file-list.txt" ]; then
    cp "$src_dir/file-list.txt" "$out_dir/source-file-list.txt"
fi
if [ -f "$src_dir/SHA256SUMS" ]; then
    cp "$src_dir/SHA256SUMS" "$out_dir/source-SHA256SUMS"
fi

find "$out_dir" -type f ! -name SHA256SUMS -print0 |
    sort -z |
    xargs -0 shasum -a 256 > "$out_dir/SHA256SUMS"

cat > "$out_dir/manifest.txt" <<EOF
source=$src_dir
selected_tar=$selected_tar
prepared_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
root=$out_dir/root
raw_partitions=$out_dir/raw-partitions
notice=Includes files derived from the user's POWKIDDY V90S StockOS/Batocera image for plumOS V90S runtime compatibility.
EOF

printf 'prepared: %s\n' "$out_dir"
du -sh "$out_dir"
