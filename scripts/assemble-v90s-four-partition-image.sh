#!/usr/bin/env bash
set -euo pipefail

vendor_runtime="${PLUMOS_V90S_VENDOR_RUNTIME_OUT:-output/vendor/v90s-stockos-r1}"
boot_package="${PLUMOS_V90S_FIXED_BOOT_PACKAGE:-output/boot-package/v90s-four-partition/boot_package.fex}"
boot_image="${PLUMOS_V90S_PROVISIONING_BOOT_IMAGE:-output/boot-image/v90s-four-partition/boot.img}"
system_squashfs="${PLUMOS_V90S_SYSTEM_SQUASHFS:-output/system-rootfs/v90s/plumos-v90s-system-rootfs.squashfs}"
app_runtime="${PLUMOS_V90S_APP_RUNTIME:-output/app-layer/v90s}"
out_dir="output/images"
image_name="plumos-v90s-four-partition-seed.img"
keep_work=0

P1_SIZE_MIB=1024
P2_SIZE_MIB=64
P3_SEED_MIB=1536
P3_TARGET_MIB=8192
P3_MINIMUM_FREE_MIB=256

usage() {
    cat <<EOF
Usage: scripts/assemble-v90s-four-partition-image.sh [options]

Options:
  --vendor-runtime PATH  prepared v90s-stockos-r1 runtime
  --boot-package PATH    fixed-env boot_package.fex
  --boot-image PATH      provisioning Android boot.img
  --system-squashfs PATH signed/read-only system rootfs source
  --app-runtime PATH     p3 plumOS runtime tree
  --out-dir PATH         output directory
  --name NAME            image filename
  --keep-work            preserve assembler work directory

The seed image contains p1-p3 only. First boot expands p3 to 8192 MiB and
creates p4 FAT32 through the final usable SD-card sector.
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --vendor-runtime) vendor_runtime="$2"; shift 2 ;;
        --boot-package) boot_package="$2"; shift 2 ;;
        --boot-image) boot_image="$2"; shift 2 ;;
        --system-squashfs) system_squashfs="$2"; shift 2 ;;
        --app-runtime) app_runtime="$2"; shift 2 ;;
        --out-dir) out_dir="$2"; shift 2 ;;
        --name) image_name="$2"; shift 2 ;;
        --keep-work) keep_work=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'error: unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

for tool in genimage rsync sha256sum du; do
    command -v "$tool" >/dev/null 2>&1 || {
        printf 'error: required tool is unavailable: %s\n' "$tool" >&2
        exit 1
    }
done

boot0="$vendor_runtime/raw-boot-chain/boot0-offset-131072.bin"
volumn_src="$vendor_runtime/root/media/Volumn"
for file in "$boot0" "$boot_package" "$boot_image" "$system_squashfs"; do
    [ -f "$file" ] || { printf 'error: required input missing: %s\n' "$file" >&2; exit 1; }
done
for dir in "$volumn_src" "$app_runtime"; do
    [ -d "$dir" ] || { printf 'error: required input directory missing: %s\n' "$dir" >&2; exit 1; }
done

boot_package_size="$(wc -c < "$boot_package" | tr -d ' ')"
boot_package_capacity=$((21495808 - 16793600))
[ "$boot_package_size" -le "$boot_package_capacity" ] || {
    printf 'error: boot package exceeds raw pre-p1 allocation: %s > %s\n' \
        "$boot_package_size" "$boot_package_capacity" >&2
    exit 1
}
boot_image_size="$(wc -c < "$boot_image" | tr -d ' ')"
[ "$boot_image_size" -le $((P2_SIZE_MIB * 1024 * 1024)) ] || {
    printf 'error: boot image exceeds p2 capacity\n' >&2
    exit 1
}

mkdir -p "$out_dir"
work_dir="$out_dir/.work-v90s-four-partition"
root_dir="$work_dir/root"
input_dir="$work_dir/input"
genimage_tmp="$work_dir/genimage.tmp"
generated_cfg="$work_dir/genimage.cfg"
manifest="$out_dir/$image_name.manifest.txt"

rm -rf "$work_dir" "$out_dir/$image_name" "$manifest" \
    "$out_dir/plumos-v90s-four-partition.img" "$out_dir/plumboot.vfat" \
    "$out_dir/plumos-sys.ext4"
mkdir -p "$root_dir/plumboot/System" "$root_dir/plumos-sys" "$input_dir"

rsync -a "$volumn_src/" "$root_dir/plumboot/"
rm -rf "$root_dir/plumboot/Logs"
cp "$system_squashfs" "$root_dir/plumboot/System/system-a.squashfs"
cp "$system_squashfs" "$root_dir/plumboot/System/system-b.squashfs"
(
    cd "$root_dir/plumboot/System"
    sha256sum system-a.squashfs > system-a.sha256
    sha256sum system-b.squashfs > system-b.sha256
    printf 'a\n' > active-slot
)

rsync -aH --numeric-ids "$app_runtime/" "$root_dir/plumos-sys/"
mkdir -p "$root_dir/plumos-sys/provision" "$root_dir/plumos-sys/releases"
printf 'seed\n' > "$root_dir/plumos-sys/provision/state"

app_used_kib="$(du -sk "$root_dir/plumos-sys" | awk '{print $1}')"
app_capacity_kib=$((P3_SEED_MIB * 1024))
app_minimum_free_kib=$((P3_MINIMUM_FREE_MIB * 1024))
[ "$app_used_kib" -le $((app_capacity_kib - app_minimum_free_kib)) ] || {
    printf 'error: p3 seed requires %s KiB and leaves less than %s MiB free\n' \
        "$app_used_kib" "$P3_MINIMUM_FREE_MIB" >&2
    exit 1
}

cp "$boot0" "$input_dir/boot0.img"
cp "$boot_package" "$input_dir/boot_package.fex"
cp "$boot_image" "$input_dir/boot.img"

cat > "$generated_cfg" <<EOF
image plumboot.vfat {
        vfat {
                extraargs = "-F 16 -n PLUMBOOT"
        }
        size = "${P1_SIZE_MIB}M"
        mountpoint = "/plumboot"
}

image plumos-sys.ext4 {
        ext4 {
                label = "PLUMOS_SYS"
                use-mke2fs = "true"
                extraargs = "-m 0 -O ^metadata_csum,^64bit"
        }
        size = "${P3_SEED_MIB}M"
        mountpoint = "/plumos-sys"
}

image plumos-v90s-four-partition.img {
        hdimage {
                partition-table-type = "gpt"
                gpt-location = 1024
        }

        partition bootloader {
                in-partition-table = "no"
                image = "boot0.img"
                offset = 131072
        }

        partition boot-package {
                in-partition-table = "no"
                image = "boot_package.fex"
                offset = 16793600
        }

        partition boot-resource {
                partition-type-uuid = "F"
                bootable = "true"
                image = "plumboot.vfat"
                offset = 21495808
        }

        partition boot {
                image = "boot.img"
                size = "${P2_SIZE_MIB}M"
        }

        partition runtime {
                image = "plumos-sys.ext4"
        }
}
EOF

genimage \
    --rootpath="$root_dir" \
    --inputpath="$input_dir" \
    --outputpath="$out_dir" \
    --config="$generated_cfg" \
    --tmppath="$genimage_tmp"

mv "$out_dir/plumos-v90s-four-partition.img" "$out_dir/$image_name"
rm -f "$out_dir/plumboot.vfat" "$out_dir/plumos-sys.ext4"

image_sha256="$(sha256sum "$out_dir/$image_name" | awk '{print $1}')"
boot0_sha256="$(sha256sum "$boot0" | awk '{print $1}')"
boot_package_sha256="$(sha256sum "$boot_package" | awk '{print $1}')"
boot_image_sha256="$(sha256sum "$boot_image" | awk '{print $1}')"
system_sha256="$(sha256sum "$system_squashfs" | awk '{print $1}')"
app_manifest_sha256="$(sha256sum "$app_runtime/manifest.json" | awk '{print $1}')"
image_size="$(wc -c < "$out_dir/$image_name" | tr -d ' ')"

cat > "$manifest" <<EOF
image=$out_dir/$image_name
image_sha256=$image_sha256
image_size=$image_size
layout=plumos-v90s-four-partition-seed-v1
raw_boot_area_end=21495808
boot0=$boot0
boot0_sha256=$boot0_sha256
boot_package=$boot_package
boot_package_sha256=$boot_package_sha256
boot_package_external_env_required=no
boot_image=$boot_image
boot_image_sha256=$boot_image_sha256
system_squashfs=$system_squashfs
system_squashfs_sha256=$system_sha256
app_runtime=$app_runtime
app_runtime_manifest_sha256=$app_manifest_sha256
p1_name=boot-resource
p1_label=PLUMBOOT
p1_seed_mib=$P1_SIZE_MIB
p2_name=boot
p2_mib=$P2_SIZE_MIB
p3_name=runtime
p3_label=PLUMOS_SYS
p3_seed_mib=$P3_SEED_MIB
p3_target_mib=$P3_TARGET_MIB
p3_seed_used_kib=$app_used_kib
p3_minimum_free_mib=$P3_MINIMUM_FREE_MIB
p4_name=userdata
p4_label=PLUMOS
p4_in_seed=no
minimum_sd_gb=16
EOF
printf '%s  %s\n' "$image_sha256" "$image_name" > "$out_dir/$image_name.sha256"

printf 'created: %s/%s\n' "$out_dir" "$image_name"
printf 'manifest: %s\n' "$manifest"
printf 'sha256: %s\n' "$image_sha256"

scripts/verify-v90s-four-partition-image.sh \
    --image "$out_dir/$image_name" \
    --report "$out_dir/$image_name.verify.txt"

if [ "$keep_work" -eq 0 ]; then
    rm -rf "$work_dir"
else
    printf 'kept work directory: %s\n' "$work_dir"
fi
