#!/usr/bin/env bash
set -euo pipefail

source_boot="${PLUMOS_V90S_SOURCE_BOOT_IMAGE:-output/vendor/v90s-stockos-r1/raw-partitions/mmcblk0p4-boot.bin}"
out_dir="${PLUMOS_V90S_BOOT_IMAGE_OUT:-output/boot-image/v90s-four-partition}"
init_script="scripts/v90s-four-partition-init"
progress_generator="scripts/generate-v90s-init-progress.py"
cmdline="console=ttyS0,115200 rootwait init=/init loglevel=4 cma=32M gpt=1"

usage() {
    cat <<EOF
Usage: scripts/build-v90s-provisioning-boot-image.sh [options]

Options:
  --source PATH     captured vendor Android boot image
  --out-dir PATH    output directory
  --init PATH       provisioning init script
  --cmdline TEXT    Android boot command line
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --source) source_boot="$2"; shift 2 ;;
        --out-dir) out_dir="$2"; shift 2 ;;
        --init) init_script="$2"; shift 2 ;;
        --cmdline) cmdline="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'error: unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

for tool in abootimg cpio gzip ldd python3 sha256sum; do
    command -v "$tool" >/dev/null 2>&1 || {
        printf 'error: required tool is unavailable: %s\n' "$tool" >&2
        exit 1
    }
done
[ -f "$source_boot" ] || { printf 'error: source boot image missing: %s\n' "$source_boot" >&2; exit 1; }
[ -x "$init_script" ] || { printf 'error: provisioning init missing: %s\n' "$init_script" >&2; exit 1; }
[ -x "$progress_generator" ] || { printf 'error: progress generator missing: %s\n' "$progress_generator" >&2; exit 1; }
source_boot_abs="$(realpath "$source_boot")"

work_dir="$out_dir/.work"
extract_dir="$work_dir/extracted"
ramdisk_dir="$work_dir/ramdisk"
rm -rf "$out_dir"
mkdir -p "$extract_dir" "$ramdisk_dir" "$out_dir"
extract_dir_abs="$(realpath "$extract_dir")"
ramdisk_dir_abs="$(realpath "$ramdisk_dir")"

(
    cd "$extract_dir_abs"
    abootimg -x "$source_boot_abs" >/dev/null
    gzip -dc initrd.img | (cd "$ramdisk_dir_abs" && cpio -idmu --quiet)
)

install -m 0755 "$init_script" "$ramdisk_dir/init"
python3 "$progress_generator" --output-dir "$ramdisk_dir/progress"
mkdir -p "$ramdisk_dir/tools/bin" "$ramdisk_dir/tools/lib"

copy_tool() {
    src="$1"
    name="$2"
    install -m 0755 "$src" "$ramdisk_dir/tools/bin/$name"
    ldd "$src" | awk '
        /=> \/[^ ]+/ { print $3 }
        /^[[:space:]]*\/[^ ]+ld-linux/ { print $1 }
    ' | sort -u | while read -r lib; do
        [ -n "$lib" ] || continue
        install -m 0755 "$lib" "$ramdisk_dir/tools/lib/$(basename "$lib")"
    done
    cat > "$ramdisk_dir/sbin/$name" <<EOF
#!/bin/sh
exec /tools/lib/ld-linux-aarch64.so.1 --library-path /tools/lib /tools/bin/$name "\$@"
EOF
    chmod 0755 "$ramdisk_dir/sbin/$name"
}

copy_tool /usr/sbin/parted parted
copy_tool /usr/sbin/e2fsck e2fsck
copy_tool /usr/sbin/resize2fs resize2fs
copy_tool /usr/sbin/mkfs.fat mkfs.fat
copy_tool /usr/sbin/fsck.fat fsck.fat

[ -x "$ramdisk_dir/tools/lib/ld-linux-aarch64.so.1" ] || {
    printf 'error: isolated AArch64 dynamic loader was not collected\n' >&2
    exit 1
}

ramdisk_image="$work_dir/initramfs.cpio.gz"
ramdisk_image_abs="$(dirname "$ramdisk_dir_abs")/initramfs.cpio.gz"
(
    cd "$ramdisk_dir_abs"
    find . -print0 | sort -z | cpio --null -o -H newc --quiet | gzip -9 > "$ramdisk_image_abs"
)

cp "$source_boot" "$out_dir/boot.img"
abootimg -u "$out_dir/boot.img" -r "$ramdisk_image" -c "cmdline=$cmdline" >/dev/null

boot_size="$(wc -c < "$out_dir/boot.img" | tr -d ' ')"
[ "$boot_size" -le $((64 * 1024 * 1024)) ] || {
    printf 'error: generated boot image exceeds 64 MiB: %s\n' "$boot_size" >&2
    exit 1
}

source_sha256="$(sha256sum "$source_boot" | awk '{print $1}')"
output_sha256="$(sha256sum "$out_dir/boot.img" | awk '{print $1}')"
init_sha256="$(sha256sum "$init_script" | awk '{print $1}')"
cat > "$out_dir/boot-image.manifest" <<EOF
format=android-boot-image
board=powkiddy-v90s
source=$source_boot
source_sha256=$source_sha256
output=$out_dir/boot.img
output_sha256=$output_sha256
output_size=$boot_size
partition_capacity_mib=64
init=$init_script
init_sha256=$init_sha256
cmdline=$cmdline
p3_seed_mib=1536
p3_target_mib=8192
p4_first_boot=yes
EOF
printf '%s  %s\n' "$output_sha256" boot.img > "$out_dir/SHA256SUMS"
rm -rf "$work_dir"

printf 'created: %s/boot.img\n' "$out_dir"
printf 'manifest: %s/boot-image.manifest\n' "$out_dir"
printf 'sha256: %s\n' "$output_sha256"
