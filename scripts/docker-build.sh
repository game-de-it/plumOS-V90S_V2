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
  vendor-runtime   Prepare artifacts/vendor/v90s-stockos-r1 into output/vendor/v90s-stockos-r1.
  stockos-runtime  Deprecated alias for vendor-runtime.
  sdl2-powervr     Build the patched SDL2 PowerVR runtime.
  sdl2-mali        Deprecated alias for sdl2-powervr.
  retroarch        Build the V90S RetroArch binary with the PowerVR fbdev context.
  retroarch-knulli Deprecated alias for the legacy KNULLI-named RetroArch builder.
  cores            Build supported libretro cores.
  quicknes         Compatibility alias for the current QuickNES-only core build.
  system-rootfs    Build a V90S system rootfs payload using scripts/build-step1-rootfs.sh.
  rootfs           Transitional alias for system-rootfs.
  app-layer        Assemble the FAT32 plumOS app/update/data layer.
  sd-image         Assemble a StockOS/Batocera-compatible V90S SD-card image.
  stockos-image    Transitional alias for sd-image.
  knulli-image     Assemble a legacy KNULLI-layout V90S SD-card image.
  picoarch         Reserved for the V90S PicoArch build path.
  standalone       Reserved for V90S standalone emulator builds.
  frontend         Reserved for the V90S frontend build path.
  release          Assemble update-only release packages from the app layer.
  all              Reserved for the normal release build chain.

Environment:
  PLUMOS_V90S_DOCKER_IMAGE     Docker image tag. Default: ${IMAGE}
  PLUMOS_V90S_DOCKER_PLATFORM  Docker platform. Default: ${PLATFORM}
  PLUMOS_V90S_STOCKOS_ARTIFACT StockOS extraction input for vendor-runtime.
  PLUMOS_V90S_VENDOR_RUNTIME_OUT
                                  Prepared vendor runtime output.

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
    -e PLUMOS_V90S_VENDOR_RUNTIME_ID="${PLUMOS_V90S_VENDOR_RUNTIME_ID:-v90s-stockos-r1}"
    -e PLUMOS_V90S_VENDOR_RUNTIME_OUT="${PLUMOS_V90S_VENDOR_RUNTIME_OUT:-output/vendor/v90s-stockos-r1}"
    -e PLUMOS_V90S_VENDOR_RUNTIME_COMPAT_OUT="${PLUMOS_V90S_VENDOR_RUNTIME_COMPAT_OUT:-output/vendor/stockos-runtime}"
    -e PLUMOS_V90S_WIFI_SSID="${PLUMOS_V90S_WIFI_SSID:-}"
    -e PLUMOS_V90S_WIFI_PSK="${PLUMOS_V90S_WIFI_PSK:-}"
    -e PLUMOS_V90S_SSH_AUTHORIZED_KEYS="${PLUMOS_V90S_SSH_AUTHORIZED_KEYS:-}"
    -e PLUMOS_V90S_SSH_ROOT_PASSWORD="${PLUMOS_V90S_SSH_ROOT_PASSWORD:-}"
    -e PLUMOS_V90S_RETROARCH_START_MODE="${PLUMOS_V90S_RETROARCH_START_MODE:-}"
)
if [ -n "${PLUMOS_V90S_STOCKOS_ARTIFACT:-}" ]; then
    docker_env+=(-e PLUMOS_V90S_STOCKOS_ARTIFACT="$PLUMOS_V90S_STOCKOS_ARTIFACT")
fi

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
    vendor-runtime)
        ensure_image
        docker run "${docker_run_user[@]}" /workspace/scripts/prepare-stockos-runtime.sh "$@"
        ;;
    stockos-runtime)
        echo "warning: stockos-runtime is deprecated; use vendor-runtime" >&2
        ensure_image
        docker run "${docker_run_user[@]}" /workspace/scripts/prepare-stockos-runtime.sh "$@"
        ;;
    cores|libretro-cores)
        ensure_image
        docker run "${docker_run_user[@]}" /workspace/docker/plumos-v90s-toolchain/scripts/build-libretro-quicknes.sh "$@"
        ;;
    quicknes|libretro-quicknes)
        echo "warning: quicknes is a one-core development alias; use cores for normal core builds" >&2
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
            /workspace/scripts/build-retroarch-powervr.sh "$@"
        ;;
    retroarch-knulli)
        echo "warning: retroarch-knulli is a legacy investigation alias; use retroarch" >&2
        ensure_image
        docker run \
            -e PLUMOS_V90S_BUILD_IN_CONTAINER=1 \
            "${docker_run_user[@]}" \
            /workspace/scripts/build-retroarch-knulli.sh "$@"
        ;;
    system-rootfs)
        ensure_image
        docker run "${docker_run_root[@]}" /workspace/scripts/build-step1-rootfs.sh "$@"
        ;;
    rootfs)
        echo "warning: rootfs is a transitional alias; use system-rootfs" >&2
        ensure_image
        docker run "${docker_run_root[@]}" /workspace/scripts/build-step1-rootfs.sh "$@"
        ;;
    sd-image)
        ensure_image
        docker run "${docker_run_root[@]}" /workspace/scripts/assemble-v90s-stockos-image.sh "$@"
        ;;
    stockos-image|stockos-sd-image|image-assemble)
        echo "warning: stockos-image is a transitional alias; use sd-image" >&2
        ensure_image
        docker run "${docker_run_root[@]}" /workspace/scripts/assemble-v90s-stockos-image.sh "$@"
        ;;
    knulli-image|knulli-sd-image)
        ensure_image
        docker run "${docker_run_root[@]}" /workspace/scripts/assemble-v90s-image.sh "$@"
        ;;
    app-layer)
        ensure_image
        docker run "${docker_run_user[@]}" /workspace/scripts/build-app-layer.sh "$@"
        ;;
    release)
        ensure_image
        docker run "${docker_run_user[@]}" /workspace/scripts/build-release.sh "$@"
        ;;
    picoarch|standalone|standalone-emulators|frontend|all)
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
