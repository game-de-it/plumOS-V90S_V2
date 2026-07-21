#!/usr/bin/env bash
set -euo pipefail

image=""
vendor_runtime="${PLUMOS_V90S_VENDOR_RUNTIME_OUT:-output/vendor/v90s-stockos-r1}"
boot_package="${PLUMOS_V90S_FIXED_BOOT_PACKAGE:-output/boot-package/v90s-four-partition/boot_package.fex}"
boot_image="${PLUMOS_V90S_PROVISIONING_BOOT_IMAGE:-output/boot-image/v90s-four-partition/boot.img}"
system_squashfs="${PLUMOS_V90S_SYSTEM_SQUASHFS:-output/system-rootfs/v90s/plumos-v90s-system-rootfs.squashfs}"
app_runtime="${PLUMOS_V90S_APP_RUNTIME:-output/app-layer/v90s}"
boot_logo="${PLUMOS_V90S_BOOT_LOGO:-package/boot-assets-v90s/bootlogo.bmp}"
report=""

usage() {
    cat <<EOF
Usage: scripts/verify-v90s-four-partition-image.sh --image PATH [options]

Options:
  --report PATH  verification report path
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --image) image="$2"; shift 2 ;;
        --report) report="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'error: unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

[ -n "$image" ] || { usage >&2; exit 2; }
[ -f "$image" ] || { printf 'error: image missing: %s\n' "$image" >&2; exit 1; }
[ -n "$report" ] || report="$image.verify.txt"

for tool in parted dd cmp sha256sum e2fsck dumpe2fs debugfs mdir mcopy python3; do
    command -v "$tool" >/dev/null 2>&1 || {
        printf 'error: required tool unavailable: %s\n' "$tool" >&2
        exit 1
    }
done

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
mkdir -p "$(dirname "$report")"
: > "$report"

pass() {
    printf 'PASS %s\n' "$*" | tee -a "$report"
}

fail() {
    printf 'FAIL %s\n' "$*" | tee -a "$report" >&2
    exit 1
}

[ -f "$boot_logo" ] || fail "boot logo source is missing: $boot_logo"
python3 scripts/verify-v90s-boot-logo.py "$boot_logo" >> "$report" ||
    fail "boot logo source format is invalid"
pass "V90S boot logo source format"

partition_table="$tmp_dir/parted.txt"
parted -sm "$image" unit s print > "$partition_table"
cat "$partition_table" >> "$report"
partition_count="$(awk -F: '$1 ~ /^[0-9]+$/ { count++ } END { print count+0 }' "$partition_table")"
[ "$partition_count" = 3 ] || fail "seed must contain exactly three GPT partitions"

field() {
    number="$1"
    column="$2"
    awk -F: -v number="$number" -v column="$column" \
        '$1 == number { value=$column; sub(/s$/, "", value); print value; exit }' \
        "$partition_table"
}

p1_start="$(field 1 2)"
p1_sectors="$(field 1 4)"
p1_name="$(field 1 6)"
p2_start="$(field 2 2)"
p2_sectors="$(field 2 4)"
p2_name="$(field 2 6)"
p3_start="$(field 3 2)"
p3_sectors="$(field 3 4)"
p3_name="$(field 3 6)"

[ "$p1_start" = 41984 ] || fail "p1 start=$p1_start expected=41984"
[ "$p1_sectors" = $((1024 * 2048)) ] || fail "p1 capacity is not 1024 MiB"
[ "$p1_name" = boot-resource ] || fail "p1 GPT name is not boot-resource"
[ "$p2_start" = $((p1_start + p1_sectors)) ] || fail "p2 is not contiguous after p1"
[ "$p2_sectors" = $((64 * 2048)) ] || fail "p2 capacity is not 64 MiB"
[ "$p2_name" = boot ] || fail "p2 GPT name is not boot"
[ "$p3_start" = $((p2_start + p2_sectors)) ] || fail "p3 is not contiguous after p2"
[ "$p3_sectors" = $((1600 * 2048)) ] || fail "p3 seed capacity is not 1600 MiB"
[ "$p3_name" = runtime ] || fail "p3 GPT name is not runtime"
pass "GPT seed geometry p1=1024MiB p2=64MiB p3=1600MiB p4=absent"

compare_region() {
    source="$1"
    offset_bytes="$2"
    label="$3"
    size="$(wc -c < "$source" | tr -d ' ')"
    dd if="$image" of="$tmp_dir/$label.bin" bs=1 skip="$offset_bytes" count="$size" status=none
    cmp -s "$source" "$tmp_dir/$label.bin" || fail "$label region differs from source"
    pass "$label raw region"
}

compare_region "$vendor_runtime/raw-boot-chain/boot0-offset-131072.bin" 131072 boot0
compare_region "$boot_package" 16793600 boot-package

dd if="$image" of="$tmp_dir/p2.img" bs=512 skip="$p2_start" count="$p2_sectors" status=none
cmp -s "$boot_image" "$tmp_dir/p2.img" || fail "p2 differs from provisioning boot image"
pass "p2 provisioning Android boot image"

p1_offset=$((p1_start * 512))
mdir -i "$image@@$p1_offset" ::/System >> "$report" || fail "cannot read p1 System directory"
mcopy -i "$image@@$p1_offset" ::/bootlogo.bmp "$tmp_dir/bootlogo.bmp" >/dev/null 2>&1 ||
    fail "p1 bootlogo.bmp is missing"
cmp -s "$boot_logo" "$tmp_dir/bootlogo.bmp" || fail "p1 bootlogo.bmp differs from source"
pass "p1 V90S boot logo"
for slot in a b; do
    slot_sha="$(mcopy -i "$image@@$p1_offset" "::/System/system-$slot.squashfs" - | sha256sum | awk '{print $1}')"
    expected_sha="$(sha256sum "$system_squashfs" | awk '{print $1}')"
    [ "$slot_sha" = "$expected_sha" ] || fail "p1 system-$slot hash mismatch"
done
pass "p1 PLUMBOOT boot resources and A/B system SquashFS"

dd if="$image" of="$tmp_dir/p3.ext4" bs=512 skip="$p3_start" count="$p3_sectors" status=none
e2fsck -fn "$tmp_dir/p3.ext4" >> "$report" 2>&1 || fail "p3 ext4 check failed"
volume_name="$(dumpe2fs -h "$tmp_dir/p3.ext4" 2>/dev/null | awk -F: '/Filesystem volume name/ {gsub(/^[ \t]+/, "", $2); print $2}')"
[ "$volume_name" = PLUMOS_SYS ] || fail "p3 filesystem label is $volume_name"
block_count="$(dumpe2fs -h "$tmp_dir/p3.ext4" 2>/dev/null | awk -F: '/^Block count/ {gsub(/[ \t]/, "", $2); print $2}')"
free_blocks="$(dumpe2fs -h "$tmp_dir/p3.ext4" 2>/dev/null | awk -F: '/^Free blocks/ {gsub(/[ \t]/, "", $2); print $2}')"
block_size="$(dumpe2fs -h "$tmp_dir/p3.ext4" 2>/dev/null | awk -F: '/^Block size/ {gsub(/[ \t]/, "", $2); print $2}')"
free_mib=$((free_blocks * block_size / 1024 / 1024))
[ "$free_mib" -ge 256 ] || fail "p3 image leaves only $free_mib MiB free"

debugfs -R "dump -p /manifest.json $tmp_dir/p3-manifest.json" "$tmp_dir/p3.ext4" >/dev/null 2>&1 ||
    fail "p3 manifest.json is missing"
debugfs -R "dump -p /bin/plumos-frontend-launch $tmp_dir/p3-frontend-launch" "$tmp_dir/p3.ext4" >/dev/null 2>&1 ||
    fail "p3 frontend launcher is missing"
debugfs -R "dump -p /RUNTIME_ABI $tmp_dir/p3-runtime-abi" "$tmp_dir/p3.ext4" >/dev/null 2>&1 ||
    fail "p3 RUNTIME_ABI is missing"
[ "$(tr -d '\r\n' < "$tmp_dir/p3-runtime-abi")" = 1 ] ||
    fail "p3 RUNTIME_ABI is not 1"
cmp -s "$app_runtime/manifest.json" "$tmp_dir/p3-manifest.json" || fail "p3 app manifest differs"
cmp -s "$app_runtime/bin/plumos-frontend-launch" "$tmp_dir/p3-frontend-launch" ||
    fail "p3 frontend launcher differs"
pass "p3 PLUMOS_SYS ext4 runtime free_mib=$free_mib and frontend payload"

image_sha256="$(sha256sum "$image" | awk '{print $1}')"
printf 'image_sha256=%s\n' "$image_sha256" >> "$report"
printf 'result=PASS\n' >> "$report"
printf 'verification: PASS\n'
printf 'report: %s\n' "$report"
