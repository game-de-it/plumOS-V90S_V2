#!/usr/bin/env sh
set -eu

rootfs=""
knulli_src=".cache/knulli-linux"
out_dir="output/images"
image_name="plumos-v90s-armbian-step1.img"
keep_work=0
boot_vfat_size="33M"
userdata_size="64M"
userdata_payload=""
boot_cmdline=""
diagnostic_init=0
diagnostic_init_path="scripts/v90s-diagnostic-init"
ramdisk_root=".cache/v90s-ramdisk"

usage() {
    cat <<'USAGE'
Usage:
  assemble-v90s-image.sh --rootfs ROOTFS.squashfs [options]

Options:
  --rootfs PATH       squashfs root filesystem to place at /boot/boot/knulli
  --knulli-src PATH   KNULLI source checkout, default .cache/knulli-linux
  --out-dir PATH      output directory, default output/images
  --name NAME         output image name, default plumos-v90s-armbian-step1.img
  --boot-vfat-size N  FAT boot-resource size, default 33M
  --userdata-size N   userdata partition size, default 64M
  --userdata-payload PATH
                     copy PATH to userdata:/rootfs/step1-rootfs.squashfs
  --boot-cmdline TEXT
                     replace Android boot.img kernel cmdline
  --diagnostic-init  replace Android boot.img ramdisk /init with SD logging init
  --diagnostic-init-path PATH
                     diagnostic init script, default scripts/v90s-diagnostic-init
  --ramdisk-root PATH
                     extracted V90S ramdisk root, default .cache/v90s-ramdisk
  --keep-work         keep temporary assembly directory
USAGE
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --rootfs)
            rootfs="$2"
            shift 2
            ;;
        --knulli-src)
            knulli_src="$2"
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
        --boot-vfat-size)
            boot_vfat_size="$2"
            shift 2
            ;;
        --userdata-size)
            userdata_size="$2"
            shift 2
            ;;
        --userdata-payload)
            userdata_payload="$2"
            shift 2
            ;;
        --boot-cmdline)
            boot_cmdline="$2"
            shift 2
            ;;
        --diagnostic-init)
            diagnostic_init=1
            shift
            ;;
        --diagnostic-init-path)
            diagnostic_init_path="$2"
            shift 2
            ;;
        --ramdisk-root)
            ramdisk_root="$2"
            shift 2
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

if [ -z "$rootfs" ]; then
    printf 'error: --rootfs is required\n' >&2
    usage >&2
    exit 2
fi

if [ ! -f "$rootfs" ]; then
    printf 'error: rootfs not found: %s\n' "$rootfs" >&2
    exit 1
fi

if [ -n "$userdata_payload" ] && [ ! -f "$userdata_payload" ]; then
    printf 'error: userdata payload not found: %s\n' "$userdata_payload" >&2
    exit 1
fi

if ! command -v genimage >/dev/null 2>&1; then
    printf 'error: genimage is required\n' >&2
    exit 1
fi

if [ -n "$boot_cmdline" ] && ! command -v abootimg >/dev/null 2>&1; then
    printf 'error: abootimg is required when --boot-cmdline is used\n' >&2
    exit 1
fi

if [ "$diagnostic_init" -eq 1 ]; then
    for tool in abootimg cpio gzip; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            printf 'error: %s is required when --diagnostic-init is used\n' "$tool" >&2
            exit 1
        fi
    done
    if [ ! -d "$ramdisk_root" ]; then
        printf 'error: ramdisk root not found: %s\n' "$ramdisk_root" >&2
        exit 1
    fi
    if [ ! -f "$diagnostic_init_path" ]; then
        printf 'error: diagnostic init not found: %s\n' "$diagnostic_init_path" >&2
        exit 1
    fi
fi

board_dir="$knulli_src/board/allwinner/a133/powkiddy-v90s"
if [ ! -d "$board_dir" ]; then
    printf 'error: KNULLI V90S board directory not found: %s\n' "$board_dir" >&2
    printf 'hint: run ./scripts/fetch-reference-sources.sh first\n' >&2
    exit 1
fi

mkdir -p "$out_dir"
work_dir="$out_dir/.work-v90s-image"
boot_dir="$work_dir/boot"
root_dir="$work_dir/root"
genimage_tmp="$work_dir/genimage.tmp"
generated_cfg="$work_dir/genimage.cfg"

rm -rf "$work_dir"
mkdir -p "$boot_dir/boot" "$root_dir/userdata"
rm -f "$out_dir/knulli.img" "$out_dir/$image_name" "$out_dir/boot.vfat" "$out_dir/userdata.ext4"

cp "$rootfs" "$boot_dir/boot/knulli"
cp "$board_dir/knulli-boot.conf" "$boot_dir/knulli-boot.conf"
cp "$board_dir/bootlogo.bmp" "$boot_dir/bootlogo.bmp"
cp -R "$board_dir/partitions" "$boot_dir/partitions"
printf 'powkiddy-v90s\n' > "$boot_dir/boot/knulli.board"
touch "$boot_dir/boot/autoresize"

if [ -n "$boot_cmdline" ]; then
    abootimg -u "$boot_dir/partitions/boot.img" -c "cmdline=$boot_cmdline" >/dev/null
fi

if [ "$diagnostic_init" -eq 1 ]; then
    diagnostic_ramdisk_dir="$work_dir/diagnostic-ramdisk"
    diagnostic_ramdisk_img="$work_dir/diagnostic-ramdisk.gz"
    mkdir -p "$diagnostic_ramdisk_dir"
    cp -a "$ramdisk_root/." "$diagnostic_ramdisk_dir/"
    cp "$diagnostic_init_path" "$diagnostic_ramdisk_dir/init"
    chmod 0755 "$diagnostic_ramdisk_dir/init"
    (
        cd "$diagnostic_ramdisk_dir"
        find . | cpio -o -H newc 2>"../diagnostic-cpio.log" | gzip -9 > "../diagnostic-ramdisk.gz"
    )
    abootimg -u "$boot_dir/partitions/boot.img" -r "$diagnostic_ramdisk_img" >/dev/null
fi

if [ -n "$userdata_payload" ]; then
    mkdir -p "$root_dir/userdata/rootfs"
    cp "$userdata_payload" "$root_dir/userdata/rootfs/step1-rootfs.squashfs"
fi

sed -n '1,/@files/p' "$board_dir/genimage.cfg" | sed '/@files/d' > "$generated_cfg"
find "$boot_dir" -type f | sort | while IFS= read -r file; do
    rel=${file#"$boot_dir/"}
    printf '                        file "%s" { image = "%s" }\n' "$rel" "$rel"
done >> "$generated_cfg"
sed -n '/@files/,$p' "$board_dir/genimage.cfg" | sed '1d' >> "$generated_cfg"

tmp_cfg="$generated_cfg.tmp"
sed 's#../../a133-boot-packages/powkiddy-v90s_boot_package.fex#partitions/boot_package.fex#' "$generated_cfg" > "$tmp_cfg"
mv "$tmp_cfg" "$generated_cfg"

tmp_cfg="$generated_cfg.tmp"
awk -v boot_vfat_size="$boot_vfat_size" -v userdata_size="$userdata_size" '
    /^image boot\.vfat[[:space:]]*\{/ {
        section = "boot"
    }
    /^image userdata\.ext4[[:space:]]*\{/ {
        section = "userdata"
    }
    /^image [^[:space:]]+[[:space:]]*\{/ &&
        $2 != "boot.vfat" &&
        $2 != "userdata.ext4" {
        section = ""
    }
    section == "boot" && /^[[:space:]]*size[[:space:]]*=/ {
        print "        size = \"" boot_vfat_size "\""
        next
    }
    section == "userdata" && /^[[:space:]]*size[[:space:]]*=/ {
        print "        size = \"" userdata_size "\""
        next
    }
    {
        print
    }
' "$generated_cfg" > "$tmp_cfg"
mv "$tmp_cfg" "$generated_cfg"

genimage \
    --rootpath="$root_dir" \
    --inputpath="$boot_dir" \
    --outputpath="$out_dir" \
    --config="$generated_cfg" \
    --tmppath="$genimage_tmp"

if [ -f "$out_dir/knulli.img" ]; then
    mv "$out_dir/knulli.img" "$out_dir/$image_name"
fi

rm -f "$out_dir/boot.vfat" "$out_dir/userdata.ext4"

printf 'created: %s/%s\n' "$out_dir" "$image_name"
printf 'boot.vfat size: %s\n' "$boot_vfat_size"
printf 'userdata size: %s\n' "$userdata_size"
if [ -n "$boot_cmdline" ]; then
    printf 'boot cmdline: %s\n' "$boot_cmdline"
fi
if [ "$diagnostic_init" -eq 1 ]; then
    printf 'diagnostic init: %s\n' "$diagnostic_init_path"
fi

if [ "$keep_work" -eq 0 ]; then
    rm -rf "$work_dir"
else
    printf 'kept work directory: %s\n' "$work_dir"
fi
