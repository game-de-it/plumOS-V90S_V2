#!/usr/bin/env sh
set -eu

rootfs=""
knulli_src=".cache/knulli-linux"
out_dir="output/images"
image_name="plumos-v90s-armbian-step1.img"
keep_work=0

usage() {
    cat <<'USAGE'
Usage:
  assemble-v90s-image.sh --rootfs ROOTFS.squashfs [options]

Options:
  --rootfs PATH       squashfs root filesystem to place at /boot/boot/knulli
  --knulli-src PATH   KNULLI source checkout, default .cache/knulli-linux
  --out-dir PATH      output directory, default output/images
  --name NAME         output image name, default plumos-v90s-armbian-step1.img
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

if ! command -v genimage >/dev/null 2>&1; then
    printf 'error: genimage is required\n' >&2
    exit 1
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
mkdir -p "$boot_dir/boot" "$root_dir"

cp "$rootfs" "$boot_dir/boot/knulli"
cp "$board_dir/knulli-boot.conf" "$boot_dir/knulli-boot.conf"
cp "$board_dir/bootlogo.bmp" "$boot_dir/bootlogo.bmp"
cp -R "$board_dir/partitions" "$boot_dir/partitions"
printf 'powkiddy-v90s\n' > "$boot_dir/boot/knulli.board"
touch "$boot_dir/boot/autoresize"

sed -n '1,/@files/p' "$board_dir/genimage.cfg" | sed '/@files/d' > "$generated_cfg"
find "$boot_dir" -type f | sort | while IFS= read -r file; do
    rel=${file#"$boot_dir/"}
    printf '                        file "%s" { image = "%s" }\n' "$rel" "$rel"
done >> "$generated_cfg"
sed -n '/@files/,$p' "$board_dir/genimage.cfg" | sed '1d' >> "$generated_cfg"

tmp_cfg="$generated_cfg.tmp"
sed 's#../../a133-boot-packages/powkiddy-v90s_boot_package.fex#partitions/boot_package.fex#' "$generated_cfg" > "$tmp_cfg"
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

printf 'created: %s/%s\n' "$out_dir" "$image_name"

if [ "$keep_work" -eq 0 ]; then
    rm -rf "$work_dir"
else
    printf 'kept work directory: %s\n' "$work_dir"
fi
