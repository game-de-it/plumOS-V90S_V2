#!/usr/bin/env bash
set -euo pipefail

source_package="${PLUMOS_V90S_SOURCE_BOOT_PACKAGE:-output/vendor/v90s-stockos-r1/raw-boot-chain/boot-package-offset-16793600.bin}"
out_dir="${PLUMOS_V90S_BOOT_PACKAGE_OUT:-output/boot-package/v90s-four-partition}"
dragonsecboot="${PLUMOS_DRAGONSECBOOT:-dragonsecboot}"

usage() {
    cat <<EOF
Usage: scripts/build-v90s-fixed-boot-package.sh [options]

Options:
  --source PATH   captured vendor boot_package.fex
  --out-dir PATH  output directory

The generated package has no external env dependency. Its fixed default U-Boot
command reads the GPT partition named boot and boots its Android boot image.
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --source) source_package="$2"; shift 2 ;;
        --out-dir) out_dir="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'error: unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

for tool in cmp head python3 sha256sum "$dragonsecboot"; do
    command -v "$tool" >/dev/null 2>&1 || {
        printf 'error: required tool is unavailable: %s\n' "$tool" >&2
        exit 1
    }
done
[ -f "$source_package" ] || {
    printf 'error: source boot package not found: %s\n' "$source_package" >&2
    exit 1
}

work_dir="$out_dir/.work"
component_dir="$work_dir/components"
extract_manifest="$work_dir/extract-manifest.json"
rm -rf "$out_dir"
mkdir -p "$component_dir"

python3 scripts/patch-v90s-uboot-default-env.py \
    --input "$source_package" \
    --output-dir "$component_dir" \
    --manifest "$extract_manifest"

cat > "$component_dir/boot_package.cfg" <<'EOF'
[package]
item=u-boot,                 u-boot.bin
item=monitor,                monitor.bin
item=scp,                    scp.bin
item=dtb,                    dtb.bin
EOF

baseline_dir="$work_dir/baseline"
mkdir -p "$baseline_dir"
cp "$component_dir/boot_package.cfg" "$component_dir/monitor.bin" \
    "$component_dir/scp.bin" "$component_dir/dtb.bin" "$baseline_dir/"
cp "$component_dir/u-boot.source.bin" "$baseline_dir/u-boot.bin"
(
    cd "$baseline_dir"
    "$dragonsecboot" -pack boot_package.cfg
)
baseline_size="$(wc -c < "$baseline_dir/boot_package.fex" | tr -d ' ')"
head -c "$baseline_size" "$source_package" > "$work_dir/source-package-prefix.bin"
cmp -s "$baseline_dir/boot_package.fex" "$work_dir/source-package-prefix.bin" || {
    printf 'error: unmodified component repack differs from vendor package prefix\n' >&2
    exit 1
}
rm -f "$component_dir/u-boot.source.bin"

(
    cd "$component_dir"
    "$dragonsecboot" -pack boot_package.cfg
)

generated="$component_dir/boot_package.fex"
[ -f "$generated" ] || {
    printf 'error: dragonsecboot did not create boot_package.fex\n' >&2
    exit 1
}

source_size="$(wc -c < "$source_package" | tr -d ' ')"
generated_size="$(wc -c < "$generated" | tr -d ' ')"
[ "$generated_size" -le "$source_size" ] || {
    printf 'error: generated package grew beyond captured raw allocation: %s > %s\n' \
        "$generated_size" "$source_size" >&2
    exit 1
}

mv "$generated" "$out_dir/boot_package.fex"
mv "$extract_manifest" "$out_dir/components.json"
rm -rf "$work_dir"

source_sha256="$(sha256sum "$source_package" | awk '{print $1}')"
output_sha256="$(sha256sum "$out_dir/boot_package.fex" | awk '{print $1}')"
cat > "$out_dir/boot-package.manifest" <<EOF
format=allwinner-boot-package
board=powkiddy-v90s
source=$source_package
source_sha256=$source_sha256
source_size=$source_size
output=$out_dir/boot_package.fex
output_sha256=$output_sha256
output_size=$generated_size
environment=fixed-default
bootcmd=sunxi_flash read 45000000 boot;bootm 45000000
external_env_required=no
unmodified_repack_matches_source_prefix=yes
unmodified_repack_size=$baseline_size
EOF
printf '%s  %s\n' "$output_sha256" boot_package.fex > "$out_dir/SHA256SUMS"

printf 'created: %s/boot_package.fex\n' "$out_dir"
printf 'manifest: %s/boot-package.manifest\n' "$out_dir"
printf 'sha256: %s\n' "$output_sha256"
