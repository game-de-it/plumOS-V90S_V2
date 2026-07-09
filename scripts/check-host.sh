#!/usr/bin/env sh
set -eu

min_free_gib_armbian=80
min_free_gib_knulli=220

printf 'Host: %s\n' "$(uname -a)"
printf 'Working directory: %s\n' "$(pwd)"
printf '\n'

check_cmd() {
    name="$1"
    if command -v "$name" >/dev/null 2>&1; then
        printf 'ok: %s -> %s\n' "$name" "$(command -v "$name")"
    else
        printf 'missing: %s\n' "$name"
    fi
}

printf 'Tools:\n'
for tool in git docker curl python3 genimage mksquashfs unsquashfs qemu-aarch64-static debootstrap mkbootimg abootimg; do
    check_cmd "$tool"
done
printf '\n'

if command -v docker >/dev/null 2>&1; then
    printf 'Docker:\n'
    docker --version || true
    if docker info >/dev/null 2>&1; then
        printf 'ok: docker daemon reachable\n'
    else
        printf 'warn: docker command exists, but daemon is not reachable\n'
    fi
    printf '\n'
fi

free_kib=$(df -Pk . | awk 'NR == 2 { print $4 }')
free_gib=$((free_kib / 1024 / 1024))

printf 'Disk:\n'
df -h .
printf 'Approx free GiB: %s\n' "$free_gib"
if [ "$free_gib" -lt "$min_free_gib_armbian" ]; then
    printf 'warn: below %sGiB; minimal Armbian/rootfs image work will be tight\n' "$min_free_gib_armbian"
fi
if [ "$free_gib" -lt "$min_free_gib_knulli" ]; then
    printf 'warn: below %sGiB; full KNULLI source build is not realistic here\n' "$min_free_gib_knulli"
fi
