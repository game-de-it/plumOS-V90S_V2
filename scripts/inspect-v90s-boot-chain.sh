#!/usr/bin/env sh
set -eu

knulli_src="${KNULLI_SRC:-.cache/knulli-linux}"
board_dir="$knulli_src/board/allwinner/a133/powkiddy-v90s"
uboot_dir="$knulli_src/package/boot/uboot-a133/powkiddy-v90s"

if [ ! -d "$board_dir" ]; then
    printf 'error: KNULLI V90S board directory not found: %s\n' "$board_dir" >&2
    printf 'hint: run ./scripts/fetch-reference-sources.sh first\n' >&2
    exit 1
fi

printf 'KNULLI source: %s\n' "$knulli_src"
printf 'KNULLI commit: '
git -C "$knulli_src" rev-parse HEAD
printf '\n'

printf 'Board files:\n'
find "$board_dir" -maxdepth 2 -type f | sort
printf '\n'

printf 'Partition assets:\n'
ls -lh "$board_dir/partitions"
printf '\n'

printf 'Android boot image:\n'
file "$board_dir/partitions/boot.img"
printf '\n'

printf 'Boot image cmdline source:\n'
if [ -f "$uboot_dir/boot/boot.img-cmdline" ]; then
    cat "$uboot_dir/boot/boot.img-cmdline"
    printf '\n'
else
    printf 'missing: %s\n' "$uboot_dir/boot/boot.img-cmdline"
fi
printf '\n'

printf 'Kernel version strings:\n'
strings -a "$board_dir/partitions/boot.img" | grep 'Linux version' | head -3 || true
printf '\n'

printf 'Image layout excerpt:\n'
sed -n '38,90p' "$board_dir/genimage.cfg"
