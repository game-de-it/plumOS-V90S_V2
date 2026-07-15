#!/usr/bin/env sh
set -eu

vendor_runtime="${PLUMOS_V90S_VENDOR_RUNTIME_OUT:-output/vendor/v90s-stockos-r1}"
rootfs_squashfs="output/rootfs-step1/stage1-userdata-loader.squashfs"
rootfs_squashfs_was_default=1
out_dir="output/images"
image_name="plumos-v90s-stockos-smoke.img"
volumn_vfat_size="33M"
batocera_boot_size="33M"
share_size="4096M"
app_layer_dir="${PLUMOS_V90S_APP_LAYER_DIR:-}"
boot0_img=""
boot_package_img=""
include_stock_overlay=0
repack_rootfs=1
keep_work=0
allow_knulli_boot_fallback=0
boot0_source=explicit
boot_package_source=explicit

usage() {
    cat <<'USAGE'
Usage:
  assemble-v90s-stockos-image.sh [options]

Options:
  --vendor-runtime PATH
                        prepared StockOS runtime; default output/vendor/v90s-stockos-r1
  --rootfs-squashfs PATH
                        squashfs image for StockOS partition p5 "batocera";
                        default output/rootfs-step1/stage1-userdata-loader.squashfs
  --out-dir PATH        output directory, default output/images
  --name NAME           output image name, default plumos-v90s-stockos-smoke.img
  --volumn-vfat-size N  p1 boot-resource/PLUMBOOT FAT size, default 33M
  --batocera-boot-size N
                        p6 rootfs/BATOCERA ext4 size, default 33M
  --share-size N        p7 rootfs_data/PLUMOS FAT32 size, default 4096M
  --app-layer-dir PATH  copy a built plumOS app layer into p7 PLUMOS
  --boot0 PATH          raw Allwinner boot0 image; default vendor runtime if present,
                        otherwise requires --allow-knulli-boot-fallback
  --boot-package PATH   raw Allwinner boot_package.fex; default vendor runtime if
                        present, otherwise requires --allow-knulli-boot-fallback
  --allow-knulli-boot-fallback
                        allow legacy KNULLI V90S boot0/boot_package fallback
                        when raw StockOS boot-chain captures are absent
  --include-stock-overlay
                        include StockOS /media/BATOCERA/boot/overlay in p6
  --no-rootfs-repack    copy --rootfs-squashfs directly instead of adding
                        StockOS init mountpoint directories
  --keep-work           keep temporary assembly directory

This assembles the StockOS/Batocera partition contract observed on V90S:
  p1 boot-resource / PLUMBOOT vfat
  p2 env
  p3 env-redund
  p4 boot Android boot image
  p5 batocera squashfs
  p6 rootfs / BATOCERA ext4
  p7 rootfs_data / PLUMOS FAT32
USAGE
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --vendor-runtime)
            vendor_runtime="$2"
            shift 2
            ;;
        --rootfs-squashfs)
            rootfs_squashfs="$2"
            rootfs_squashfs_was_default=0
            shift 2
            ;;
        --out-dir)
            out_dir="$2"
            shift 2
            ;;
        --name)
            image_name="$2"
            shift 2
            ;;
        --volumn-vfat-size)
            volumn_vfat_size="$2"
            shift 2
            ;;
        --batocera-boot-size)
            batocera_boot_size="$2"
            shift 2
            ;;
        --share-size)
            share_size="$2"
            shift 2
            ;;
        --app-layer-dir)
            app_layer_dir="$2"
            shift 2
            ;;
        --boot0)
            boot0_img="$2"
            boot0_source=explicit
            shift 2
            ;;
        --boot-package)
            boot_package_img="$2"
            boot_package_source=explicit
            shift 2
            ;;
        --allow-knulli-boot-fallback)
            allow_knulli_boot_fallback=1
            shift
            ;;
        --include-stock-overlay)
            include_stock_overlay=1
            shift
            ;;
        --no-rootfs-repack)
            repack_rootfs=0
            shift
            ;;
        --keep-work)
            keep_work=1
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

if ! command -v genimage >/dev/null 2>&1; then
    printf 'error: genimage is required\n' >&2
    exit 1
fi
if ! command -v rsync >/dev/null 2>&1; then
    printf 'error: rsync is required\n' >&2
    exit 1
fi
if [ "$repack_rootfs" -eq 1 ]; then
    for tool in unsquashfs mksquashfs; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            printf 'error: %s is required when rootfs repack is enabled\n' "$tool" >&2
            exit 1
        fi
    done
fi

vendor_root="$vendor_runtime/root"
raw_dir="$vendor_runtime/raw-partitions"
raw_boot_chain_dir="$vendor_runtime/raw-boot-chain"

if [ ! -d "$vendor_root" ]; then
    printf 'error: vendor runtime root not found: %s\n' "$vendor_root" >&2
    printf 'hint: run ./scripts/docker-build.sh vendor-runtime first\n' >&2
    exit 1
fi
if [ ! -f "$rootfs_squashfs" ]; then
    printf 'error: rootfs squashfs not found: %s\n' "$rootfs_squashfs" >&2
    exit 1
fi
if [ -n "$app_layer_dir" ] && [ ! -d "$app_layer_dir" ]; then
    printf 'error: app-layer directory not found: %s\n' "$app_layer_dir" >&2
    exit 1
fi
if [ -n "$app_layer_dir" ] && [ "$rootfs_squashfs_was_default" -eq 1 ]; then
    printf 'error: --app-layer-dir requires an explicit --rootfs-squashfs with /mnt/plumos init support\n' >&2
    printf 'hint: build a current system rootfs first, then pass --rootfs-squashfs output/rootfs-step2-appfat/debian-bookworm-retroarch-knulli-step2.squashfs\n' >&2
    exit 2
fi
for f in \
    "$raw_dir/mmcblk0p2-env.bin" \
    "$raw_dir/mmcblk0p3-env-redund.bin" \
    "$raw_dir/mmcblk0p4-boot.bin"
do
    if [ ! -f "$f" ]; then
        printf 'error: required StockOS raw partition is missing: %s\n' "$f" >&2
        exit 1
    fi
done

if [ -z "$boot0_img" ]; then
    if [ -f "$raw_boot_chain_dir/boot0-offset-131072.bin" ]; then
        boot0_img="$raw_boot_chain_dir/boot0-offset-131072.bin"
        boot0_source=vendor-runtime
    elif [ "$allow_knulli_boot_fallback" -eq 1 ]; then
        boot0_img=".cache/knulli-linux/board/allwinner/a133/powkiddy-v90s/partitions/boot0.img"
        boot0_source=knulli-fallback
    else
        printf 'error: StockOS raw boot0 capture not found: %s/boot0-offset-131072.bin\n' "$raw_boot_chain_dir" >&2
        printf 'hint: extract raw boot-chain captures or pass --allow-knulli-boot-fallback for a legacy diagnostic image\n' >&2
        exit 1
    fi
fi
if [ -z "$boot_package_img" ]; then
    if [ -f "$raw_boot_chain_dir/boot-package-offset-16793600.bin" ]; then
        boot_package_img="$raw_boot_chain_dir/boot-package-offset-16793600.bin"
        boot_package_source=vendor-runtime
    elif [ "$allow_knulli_boot_fallback" -eq 1 ]; then
        boot_package_img=".cache/knulli-linux/board/allwinner/a133/powkiddy-v90s/partitions/boot_package.fex"
        boot_package_source=knulli-fallback
    else
        printf 'error: StockOS raw boot_package capture not found: %s/boot-package-offset-16793600.bin\n' "$raw_boot_chain_dir" >&2
        printf 'hint: extract raw boot-chain captures or pass --allow-knulli-boot-fallback for a legacy diagnostic image\n' >&2
        exit 1
    fi
fi
if [ ! -f "$boot0_img" ]; then
    printf 'error: boot0 image not found: %s\n' "$boot0_img" >&2
    exit 1
fi
if [ ! -f "$boot_package_img" ]; then
    printf 'error: boot package image not found: %s\n' "$boot_package_img" >&2
    exit 1
fi

volumn_src="$vendor_root/media/Volumn"
batocera_src="$vendor_root/media/BATOCERA"
if [ ! -d "$volumn_src" ]; then
    printf 'error: StockOS Volumn files not found: %s\n' "$volumn_src" >&2
    exit 1
fi
if [ ! -d "$batocera_src" ]; then
    if [ -d "$vendor_root/boot" ]; then
        batocera_src="$vendor_root/boot"
    else
        printf 'error: StockOS BATOCERA boot files not found under: %s\n' "$vendor_root" >&2
        exit 1
    fi
fi

mkdir -p "$out_dir"
work_dir="$out_dir/.work-v90s-stockos-image"
root_dir="$work_dir/root"
input_dir="$work_dir/input"
genimage_tmp="$work_dir/genimage.tmp"
generated_cfg="$work_dir/genimage.cfg"
manifest="$out_dir/$image_name.manifest.txt"

rm -rf "$work_dir"
mkdir -p "$root_dir/volumn" "$root_dir/batocera" "$root_dir/share" "$input_dir"
rm -f "$out_dir/$image_name" "$manifest" \
    "$out_dir/plumos-v90s-stockos.img" \
    "$out_dir/volumn.vfat" \
    "$out_dir/batocera-boot.ext4" \
    "$out_dir/share.vfat"

rsync -a "$volumn_src"/ "$root_dir/volumn"/
if [ "$include_stock_overlay" -eq 1 ]; then
    rsync -a "$batocera_src"/ "$root_dir/batocera"/
else
    rsync -a --exclude 'boot/overlay' "$batocera_src"/ "$root_dir/batocera"/
fi

if [ "$repack_rootfs" -eq 1 ]; then
    rootfs_unpack="$work_dir/rootfs-unpacked"
    rm -rf "$rootfs_unpack"
    # Docker Desktop cannot always create rootfs device nodes on bind mounts.
    # Preserve the payload files and let the target kernel/devtmpfs repopulate /dev.
    unsquashfs -q -no-progress -ignore-errors -no-exit-code \
        -d "$rootfs_unpack" "$rootfs_squashfs"
    rm -rf "$rootfs_unpack/dev"
    mkdir -p "$rootfs_unpack/boot" "$rootfs_unpack/overlay" \
        "$rootfs_unpack/proc" "$rootfs_unpack/sys" "$rootfs_unpack/dev" \
        "$rootfs_unpack/tmp" "$rootfs_unpack/run"
    mksquashfs "$rootfs_unpack" "$input_dir/batocera-rootfs.squashfs" \
        -noappend -comp zstd -b 131072 -all-root >/dev/null
else
    rootfs_listing="$(unsquashfs -ll "$rootfs_squashfs")"
    for required_dir in boot overlay proc sys dev; do
        if ! printf '%s\n' "$rootfs_listing" |
            grep -Eq "^d.*[[:space:]]squashfs-root/$required_dir$"; then
            printf 'error: --no-rootfs-repack requires /%s in rootfs: %s\n' \
                "$required_dir" "$rootfs_squashfs" >&2
            printf 'hint: rebuild the release-system rootfs or omit --no-rootfs-repack\n' >&2
            exit 1
        fi
    done
    cp "$rootfs_squashfs" "$input_dir/batocera-rootfs.squashfs"
fi
app_layer_manifest_sha256=none
if [ -n "$app_layer_dir" ]; then
    rsync -a --copy-links "$app_layer_dir"/ "$root_dir/share"/
    if [ -f "$app_layer_dir/manifest.json" ]; then
        app_layer_manifest_sha256="$(sha256sum "$app_layer_dir/manifest.json" | awk '{print $1}')"
    fi
fi
cp "$boot0_img" "$input_dir/boot0.img"
cp "$boot_package_img" "$input_dir/boot_package.fex"
cp "$raw_dir/mmcblk0p2-env.bin" "$input_dir/env.bin"
cp "$raw_dir/mmcblk0p3-env-redund.bin" "$input_dir/env-redund.bin"
cp "$raw_dir/mmcblk0p4-boot.bin" "$input_dir/boot.img"

cat > "$generated_cfg" <<EOF
image volumn.vfat {
        vfat {
                extraargs = "-F 16 -n PLUMBOOT"
        }
        size = "$volumn_vfat_size"
        mountpoint = "/volumn"
}

image batocera-boot.ext4 {
        ext4 {
                label = "BATOCERA"
                use-mke2fs = "true"
                extraargs = "-m 0 -O ^metadata_csum"
        }
        size = "$batocera_boot_size"
        mountpoint = "/batocera"
}

image share.vfat {
        vfat {
                extraargs = "-F 32 -n PLUMOS"
        }
        size = "$share_size"
        mountpoint = "/share"
}

image plumos-v90s-stockos.img {
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
                image = "volumn.vfat"
        }

        partition env {
                image = "env.bin"
        }

        partition env-redund {
                image = "env-redund.bin"
        }

        partition boot {
                image = "boot.img"
        }

        partition batocera {
                image = "batocera-rootfs.squashfs"
        }

        partition rootfs {
                image = "batocera-boot.ext4"
        }

        partition rootfs_data {
                partition-type-uuid = "F"
                image = "share.vfat"
        }
}
EOF

genimage \
    --rootpath="$root_dir" \
    --inputpath="$input_dir" \
    --outputpath="$out_dir" \
    --config="$generated_cfg" \
    --tmppath="$genimage_tmp"

if [ -f "$out_dir/plumos-v90s-stockos.img" ]; then
    mv "$out_dir/plumos-v90s-stockos.img" "$out_dir/$image_name"
fi

rm -f "$out_dir/volumn.vfat" "$out_dir/batocera-boot.ext4" "$out_dir/share.vfat"

sha256_img="$(sha256sum "$out_dir/$image_name" | awk '{print $1}')"
sha256_rootfs="$(sha256sum "$rootfs_squashfs" | awk '{print $1}')"
sha256_p5="$(sha256sum "$input_dir/batocera-rootfs.squashfs" | awk '{print $1}')"
sha256_boot="$(sha256sum "$raw_dir/mmcblk0p4-boot.bin" | awk '{print $1}')"
sha256_boot0="$(sha256sum "$boot0_img" | awk '{print $1}')"
sha256_boot_package="$(sha256sum "$boot_package_img" | awk '{print $1}')"
vendor_runtime_id=unknown
vendor_manifest="$vendor_runtime/vendor-runtime.manifest"
vendor_manifest_sha256=none
if [ -f "$vendor_manifest" ]; then
    vendor_runtime_id="$(awk -F= '$1 == "id" { print $2; exit }' "$vendor_manifest")"
    vendor_manifest_sha256="$(sha256sum "$vendor_manifest" | awk '{print $1}')"
fi

cat > "$manifest" <<EOF
image=$out_dir/$image_name
sha256=$sha256_img
layout=stockos-batocera-v90s
vendor_runtime=$vendor_runtime
vendor_runtime_id=$vendor_runtime_id
vendor_runtime_manifest=$vendor_manifest
vendor_runtime_manifest_sha256=$vendor_manifest_sha256
rootfs_squashfs=$rootfs_squashfs
rootfs_squashfs_sha256=$sha256_rootfs
p5_batocera_squashfs_sha256=$sha256_p5
rootfs_repacked_for_stockos_init=$repack_rootfs
boot0=$boot0_img
boot0_source=$boot0_source
boot0_sha256=$sha256_boot0
boot_package=$boot_package_img
boot_package_source=$boot_package_source
boot_package_sha256=$sha256_boot_package
allow_knulli_boot_fallback=$allow_knulli_boot_fallback
stockos_boot_partition=$raw_dir/mmcblk0p4-boot.bin
stockos_boot_partition_sha256=$sha256_boot
volumn_vfat_size=$volumn_vfat_size
batocera_boot_size=$batocera_boot_size
share_size=$share_size
app_layer_dir=${app_layer_dir:-none}
app_layer_manifest_sha256=$app_layer_manifest_sha256
include_stock_overlay=$include_stock_overlay
partitions=p1:boot-resource/PLUMBOOT,p2:env,p3:env-redund,p4:boot,p5:batocera,p6:rootfs/BATOCERA,p7:rootfs_data/PLUMOS-FAT32
notice=Uses POWKIDDY V90S StockOS/Batocera-derived runtime inputs. KNULLI boot0/boot_package assets are used only when --allow-knulli-boot-fallback is passed and raw StockOS boot-chain captures are absent.
EOF

printf 'created: %s/%s\n' "$out_dir" "$image_name"
printf 'manifest: %s\n' "$manifest"
printf 'sha256: %s\n' "$sha256_img"

if [ "$keep_work" -eq 0 ]; then
    rm -rf "$work_dir"
else
    printf 'kept work directory: %s\n' "$work_dir"
fi
