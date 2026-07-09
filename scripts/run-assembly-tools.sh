#!/usr/bin/env sh
set -eu

image="${PLUMOS_V90S_TOOLS_IMAGE:-plumos-v90s-assembly-tools}"

if [ "$#" -eq 0 ]; then
    set -- /bin/bash
fi

if [ -t 0 ]; then
    docker run --rm -it \
        -v "$(pwd)":/work \
        -w /work \
        "$image" \
        "$@"
else
    docker run --rm -i \
        -v "$(pwd)":/work \
        -w /work \
        "$image" \
        "$@"
fi
