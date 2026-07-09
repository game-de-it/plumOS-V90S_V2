#!/usr/bin/env sh
set -eu

with_armbian=0
if [ "${1:-}" = "--with-armbian" ]; then
    with_armbian=1
fi

cache_dir=".cache"
mkdir -p "$cache_dir"

clone_or_update() {
    url="$1"
    ref="$2"
    dest="$3"

    if [ -d "$dest/.git" ]; then
        printf 'Updating %s\n' "$dest"
        git -C "$dest" fetch --depth=1 origin "$ref"
        git -C "$dest" checkout FETCH_HEAD
    else
        printf 'Cloning %s\n' "$url"
        git clone --depth=1 --filter=blob:none --branch "$ref" "$url" "$dest"
    fi

    printf '%s commit: ' "$dest"
    git -C "$dest" rev-parse HEAD
}

clone_or_update \
    "https://github.com/knulli-cfw/knulli-linux.git" \
    "knulli-main" \
    "$cache_dir/knulli-linux"

clone_or_update \
    "https://github.com/game-de-it/plumOS-V90S.git" \
    "main" \
    "$cache_dir/plumOS-V90S-ref"

if [ "$with_armbian" -eq 1 ]; then
    clone_or_update \
        "https://github.com/armbian/build.git" \
        "main" \
        "$cache_dir/armbian-build"
fi

printf '\nReference sources are under %s and are intentionally ignored by git.\n' "$cache_dir"
