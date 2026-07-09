#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
IMAGE="${PLUMOS_V90S_DOCKER_IMAGE:-plumos-v90s-toolchain:dev}"
PLATFORM="${PLUMOS_V90S_DOCKER_PLATFORM:-linux/arm64}"
DOCKERFILE="${ROOT_DIR}/docker/plumos-v90s-toolchain/Dockerfile"

usage() {
    cat <<EOF
Usage:
  scripts/docker-build.sh COMMAND [ARGS...]

Commands:
  image            Build the V90S toolchain image.
  shell            Open a shell in the V90S toolchain image.
  run CMD...       Run an arbitrary command in the V90S toolchain image.
  stockos-runtime  Prepare artifacts/20260710-stockos-runtime into output/vendor/stockos-runtime.
  quicknes         Build the current QuickNES libretro core.
  sdl2-powervr     Build the patched SDL2 PowerVR runtime.
  sdl2-mali        Deprecated alias for sdl2-powervr.
  retroarch        Build the V90S RetroArch binary with the PowerVR fbdev context.
  rootfs           Build a V90S rootfs payload using scripts/build-step1-rootfs.sh.
  sd-image         Assemble a V90S SD-card image using scripts/assemble-v90s-image.sh.
  picoarch         Reserved for the V90S PicoArch build path.
  standalone       Reserved for V90S standalone emulator builds.
  frontend         Reserved for the V90S frontend build path.

Environment:
  PLUMOS_V90S_DOCKER_IMAGE     Docker image tag. Default: ${IMAGE}
  PLUMOS_V90S_DOCKER_PLATFORM  Docker platform. Default: ${PLATFORM}
  PLUMOS_V90S_STOCKOS_ARTIFACT StockOS extraction input for stockos-runtime.

Porting note:
  This is the V90S equivalent of the MMF Docker build entrypoint. The target
  runtime is StockOS/Batocera-derived Linux 4.9.191 plus PowerVR GE8300 pieces,
  not a full Armbian or Buildroot distribution rebuild.
EOF
}

need_docker() {
    command -v docker >/dev/null 2>&1 || {
        echo "error: docker is required" >&2
        exit 1
    }
}

build_image() {
    need_docker
    docker build \
        --platform "$PLATFORM" \
        -t "$IMAGE" \
        -f "$DOCKERFILE" \
        "$ROOT_DIR"
}

ensure_image() {
    need_docker
    if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
        build_image
    fi
}

docker_env=(
    -e PLUMOS_V90S_STOCKOS_ARTIFACT="${PLUMOS_V90S_STOCKOS_ARTIFACT:-artifacts/20260710-stockos-runtime}"
    -e PLUMOS_V90S_VENDOR_RUNTIME_OUT="${PLUMOS_V90S_VENDOR_RUNTIME_OUT:-output/vendor/stockos-runtime}"
    -e PLUMOS_V90S_WIFI_SSID="${PLUMOS_V90S_WIFI_SSID:-}"
    -e PLUMOS_V90S_WIFI_PSK="${PLUMOS_V90S_WIFI_PSK:-}"
    -e PLUMOS_V90S_SSH_AUTHORIZED_KEYS="${PLUMOS_V90S_SSH_AUTHORIZED_KEYS:-}"
    -e PLUMOS_V90S_SSH_ROOT_PASSWORD="${PLUMOS_V90S_SSH_ROOT_PASSWORD:-}"
    -e PLUMOS_V90S_RETROARCH_START_MODE="${PLUMOS_V90S_RETROARCH_START_MODE:-}"
)

docker_run_user=(
    --rm
    --platform "$PLATFORM"
    --user "$(id -u):$(id -g)"
    "${docker_env[@]}"
    -e HOME=/tmp
    -v "${ROOT_DIR}:/workspace"
    -w /workspace
    "$IMAGE"
)

docker_run_root=(
    --rm
    --platform "$PLATFORM"
    "${docker_env[@]}"
    -v "${ROOT_DIR}:/workspace"
    -w /workspace
    "$IMAGE"
)

cmd="${1:-}"
if [ -n "$cmd" ]; then
    shift || true
fi

case "$cmd" in
    image)
        build_image
        ;;
    shell)
        ensure_image
        docker run -it "${docker_run_root[@]}" /bin/bash
        ;;
    run)
        ensure_image
        if [ "$#" -eq 0 ]; then
            echo "error: run requires a command" >&2
            exit 2
        fi
        docker run "${docker_run_root[@]}" "$@"
        ;;
    stockos-runtime|vendor-runtime)
        "$ROOT_DIR/scripts/prepare-stockos-runtime.sh" "$@"
        ;;
    quicknes|libretro-quicknes)
        ensure_image
        docker run "${docker_run_user[@]}" /workspace/docker/plumos-v90s-toolchain/scripts/build-libretro-quicknes.sh "$@"
        ;;
    sdl2-powervr|sdl2-ge8300)
        ensure_image
        docker run "${docker_run_user[@]}" /workspace/scripts/build-sdl2-powervr.sh "$@"
        ;;
    sdl2-mali)
        echo "warning: sdl2-mali is deprecated; use sdl2-powervr" >&2
        ensure_image
        docker run "${docker_run_user[@]}" /workspace/scripts/build-sdl2-powervr.sh "$@"
        ;;
    retroarch)
        ensure_image
        docker run \
            -e PLUMOS_V90S_BUILD_IN_CONTAINER=1 \
            "${docker_run_user[@]}" \
            /workspace/scripts/build-retroarch-knulli.sh "$@"
        ;;
    rootfs)
        ensure_image
        docker run "${docker_run_root[@]}" /workspace/scripts/build-step1-rootfs.sh "$@"
        ;;
    sd-image|image-assemble)
        ensure_image
        docker run "${docker_run_root[@]}" /workspace/scripts/assemble-v90s-image.sh "$@"
        ;;
    picoarch|standalone|standalone-emulators|frontend)
        echo "error: $cmd is reserved but not implemented yet for V90S" >&2
        echo "hint: add docker/plumos-v90s-toolchain/scripts/build-$cmd.sh when the runtime contract is pinned" >&2
        exit 3
        ;;
    -h|--help|help|"")
        usage
        ;;
    *)
        echo "error: unknown command: $cmd" >&2
        usage >&2
        exit 2
        ;;
esac
