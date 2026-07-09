#!/usr/bin/env sh
set -eu

armbian_dir=".cache/armbian-build"
docker_image="${PLUMOS_V90S_ARMBIAN_DOCKER_IMAGE:-ubuntu:noble}"

usage() {
    cat <<'USAGE'
Usage:
  run-armbian-build.sh [options] [armbian-command ...]

Options:
  --armbian-dir PATH   Armbian build checkout; default .cache/armbian-build
  --image NAME         Docker base image; default ubuntu:noble

Examples:
  ./scripts/run-armbian-build.sh inventory
  ./scripts/run-armbian-build.sh inventory-boards
  ./scripts/run-armbian-build.sh targets TARGETS_FILTER_INCLUDE=powkiddy
USAGE
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --armbian-dir)
            armbian_dir="$2"
            shift 2
            ;;
        --image)
            docker_image="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            break
            ;;
        *)
            break
            ;;
    esac
done

if [ ! -f "$armbian_dir/compile.sh" ]; then
    printf 'error: Armbian build checkout not found: %s\n' "$armbian_dir" >&2
    printf 'hint: run ./scripts/fetch-reference-sources.sh --with-armbian first\n' >&2
    exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
    printf 'error: docker is required\n' >&2
    exit 1
fi

if [ "$#" -eq 0 ]; then
    set -- inventory
fi

armbian_abs="$(CDPATH= cd -- "$armbian_dir" && pwd)"
docker_tty="-i"
if [ -t 0 ]; then
    docker_tty="-it"
fi

# shellcheck disable=SC2086
docker run --rm $docker_tty --privileged \
    -v "$armbian_abs:/armbian" \
    -w /armbian \
    "$docker_image" \
    bash -lc '
        set -euo pipefail
        export DEBIAN_FRONTEND=noninteractive
        printf "%s\n" "Acquire::Retries \"3\";" > /etc/apt/apt.conf.d/80-plumos-retries
        rm -rf /var/lib/apt/lists/*
        apt-get update >/dev/null
        apt-get install -y --no-install-recommends \
            bash ca-certificates curl file git jq locales python3 python3-pip \
            psmisc qemu-user-static rsync sudo uuid-runtime xz-utils >/dev/null
        git config --global --add safe.directory /armbian || true
        rm -rf /armbian/.tmp
        mkdir -p /tmp/armbian-build-tmp /armbian/output/logs
        ln -s /tmp/armbian-build-tmp /armbian/.tmp
        export ALLOW_ROOT=yes
        exec ./compile.sh "$@"
    ' armbian-build "$@"
