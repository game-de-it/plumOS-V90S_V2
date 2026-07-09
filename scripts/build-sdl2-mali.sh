#!/usr/bin/env sh
set -eu

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

printf 'warning: build-sdl2-mali.sh is deprecated; use build-sdl2-powervr.sh\n' >&2
exec "$script_dir/build-sdl2-powervr.sh" "$@"
