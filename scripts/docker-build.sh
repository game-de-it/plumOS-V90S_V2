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
  boot-package     Build the fixed-env four-partition V90S boot package.
  boot-image       Build the p2 Android boot image with provisioning initramfs.
  preflight        Verify boot, SD2, frontend, checksums, and seed capacity.
  verify-image     Verify a completed four-partition seed image.
  stockos-runtime  Deprecated alias for vendor-runtime.
  sdl2-powervr     Build the patched SDL2 PowerVR runtime.
  sdl2-mali        Deprecated alias for sdl2-powervr.
  retroarch        Build the V90S RetroArch binary with the PowerVR fbdev context.
  retroarch-knulli Deprecated alias for the legacy KNULLI-named RetroArch builder.
  cores            Build supported libretro cores.
  quicknes         Compatibility alias for the current QuickNES-only core build.
  userland         Build plumOS BusyBox and command-line tools.
  network-services Build plumOS FTP/SFTP/Samba service package and FTP userland dependencies.
  audio-router     Build the lightweight ALSA hotplug routing plugin.
  nextcommander    Build the V90S NextCommander file manager app.
  file-manager     Alias for nextcommander.
  music-player     Build the V90S plumOS Music Player app.
  portmaster       Package the pinned official PortMaster GUI with the V90S adapter.
  system-rootfs    Build a V90S system rootfs payload using scripts/build-step1-rootfs.sh.
  rootfs           Transitional alias for system-rootfs.
  app-layer        Assemble the FAT32 plumOS app/update/data layer.
  sd-image         Assemble the compact four-partition provisioning seed image.
  stockos-image    Assemble the legacy StockOS/Batocera-compatible image.
  knulli-image     Assemble a legacy KNULLI-layout V90S SD-card image.
  picoarch         Build the AArch64 V90S PicoArch runtime.
  standalone [ID...] Build all standalone emulators, only selected IDs, or launcher-only.
  frontend         Build the V90S frontend ported from plumOS-MMF.
  release          Assemble update-only release packages from the app layer.
  all              Reserved for the normal release build chain.

Environment:
  PLUMOS_V90S_DOCKER_IMAGE     Docker image tag. Default: ${IMAGE}
  PLUMOS_V90S_DOCKER_PLATFORM  Docker platform. Default: ${PLATFORM}
  PLUMOS_V90S_STOCKOS_ARTIFACT StockOS extraction input for vendor-runtime.
  PLUMOS_V90S_VENDOR_RUNTIME_OUT
                                  Prepared vendor runtime output.
  CORE_RECIPES                  Libretro core recipe TSV inside the container.
  PLUMOS_CORE_FILTER            Libretro core filter: all, v90s, class-a,
                                  class-b, or comma-separated core IDs.
                                  Default: plumos.
  FAIL_ON_CORE_ERROR            Set to 0 to keep partial libretro core builds.
  BUILD_JOB_FALLBACKS           Space- or comma-separated lower -j values to
                                  retry after an initial per-core build failure.
  PLUMOS_STANDALONE_FILTER      Standalone emulator filter used when no IDs are
                                  passed. Default: all.

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
    -e CORE_RECIPES="${CORE_RECIPES:-/workspace/docker/plumos-v90s-toolchain/libretro-core-recipes.tsv}"
    -e PLUMOS_CORE_FILTER="${PLUMOS_CORE_FILTER:-plumos}"
    -e FAIL_ON_CORE_ERROR="${FAIL_ON_CORE_ERROR:-1}"
    -e JOBS="${JOBS:-}"
    -e BUILD_JOB_FALLBACKS="${BUILD_JOB_FALLBACKS:-1}"
    -e YABASANSHIRO_CC="${YABASANSHIRO_CC:-clang}"
    -e YABASANSHIRO_CXX="${YABASANSHIRO_CXX:-clang++}"
    -e YABASANSHIRO_AS="${YABASANSHIRO_AS:-clang -c}"
    -e NEXTCOMMANDER_REF="${NEXTCOMMANDER_REF:-}"
    -e MINIAUDIO_REF="${MINIAUDIO_REF:-}"
    -e PORTMASTER_VERSION="${PORTMASTER_VERSION:-2026.06.23-0015}"
    -e PORTMASTER_URL="${PORTMASTER_URL:-}"
    -e PORTMASTER_MD5="${PORTMASTER_MD5:-41d137e6bb123c755806939831bcce2f}"
    -e PORTMASTER_SHA256="${PORTMASTER_SHA256:-772f2d56fc1abfbf79a3404ca78f240776c81c5a5b92786a0a748ae554339b7b}"
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

run_system_rootfs() {
    local arg has_profile=0 has_out_dir=0

    for arg in "$@"; do
        [ "$arg" = "--profile" ] && has_profile=1
        [ "$arg" = "--out-dir" ] && has_out_dir=1
    done
    [ "$has_profile" -eq 1 ] || set -- --profile release-system "$@"
    [ "$has_out_dir" -eq 1 ] || set -- --out-dir output/system-rootfs/v90s "$@"

    docker run "${docker_run_root[@]}" /workspace/scripts/build-step1-rootfs.sh "$@"
}

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
    boot-package)
        need_docker
        boot_tools_image="${PLUMOS_V90S_BOOT_TOOLS_IMAGE:-plumos-v90s-boot-package-tools:dev}"
        boot_tools_platform="${PLUMOS_V90S_BOOT_TOOLS_PLATFORM:-linux/amd64}"
        if ! docker image inspect "$boot_tools_image" >/dev/null 2>&1; then
            docker build \
                --platform "$boot_tools_platform" \
                -t "$boot_tools_image" \
                -f "$ROOT_DIR/docker/v90s-boot-package-tools/Dockerfile" \
                "$ROOT_DIR"
        fi
        docker run --rm \
            --platform "$boot_tools_platform" \
            --user "$(id -u):$(id -g)" \
            -e HOME=/tmp \
            -v "$ROOT_DIR:/workspace" \
            -w /workspace \
            "$boot_tools_image" \
            /workspace/scripts/build-v90s-fixed-boot-package.sh "$@"
        ;;
    boot-image)
        ensure_image
        docker run "${docker_run_root[@]}" \
            /workspace/scripts/build-v90s-provisioning-boot-image.sh "$@"
        ;;
    preflight)
        ensure_image
        docker run "${docker_run_root[@]}" \
            /workspace/scripts/preflight-v90s-four-partition-image.sh "$@"
        ;;
    verify-image)
        ensure_image
        docker run "${docker_run_root[@]}" \
            /workspace/scripts/verify-v90s-four-partition-image.sh "$@"
        ;;
    stockos-runtime)
        echo "warning: stockos-runtime is deprecated; use vendor-runtime" >&2
        ensure_image
        docker run "${docker_run_user[@]}" /workspace/scripts/prepare-stockos-runtime.sh "$@"
        ;;
    cores|libretro-cores)
        ensure_image
        docker run "${docker_run_user[@]}" /workspace/docker/plumos-v90s-toolchain/scripts/build-libretro-cores.sh "$@"
        ;;
    quicknes|libretro-quicknes)
        echo "warning: quicknes is a one-core development alias; use cores for normal core builds" >&2
        ensure_image
        docker run "${docker_run_user[@]}" /workspace/docker/plumos-v90s-toolchain/scripts/build-libretro-quicknes.sh "$@"
        ;;
    userland|busybox)
        ensure_image
        docker run "${docker_run_user[@]}" /workspace/docker/plumos-v90s-toolchain/scripts/build-busybox.sh "$@"
        ;;
    network-services|net-services)
        ensure_image
        case "${1:-}" in
            -h|--help|help) ;;
            *) docker run "${docker_run_user[@]}" /workspace/docker/plumos-v90s-toolchain/scripts/build-busybox.sh ;;
        esac
        docker run "${docker_run_user[@]}" /workspace/docker/plumos-v90s-toolchain/scripts/build-network-services.sh "$@"
        ;;
    audio-router|audio-output)
        ensure_image
        docker run "${docker_run_user[@]}" /workspace/docker/plumos-v90s-toolchain/scripts/build-audio-router.sh "$@"
        ;;
    nextcommander|file-manager|filemanager)
        ensure_image
        docker run "${docker_run_user[@]}" /workspace/docker/plumos-v90s-toolchain/scripts/build-nextcommander.sh "$@"
        ;;
    music-player|musicplayer)
        ensure_image
        docker run "${docker_run_user[@]}" /workspace/docker/plumos-v90s-toolchain/scripts/build-music-player.sh "$@"
        ;;
    portmaster)
        ensure_image
        docker run "${docker_run_user[@]}" /workspace/docker/plumos-v90s-toolchain/scripts/build-portmaster.sh "$@"
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
        run_system_rootfs "$@"
        ;;
    rootfs)
        echo "warning: rootfs is a transitional alias; use system-rootfs" >&2
        ensure_image
        run_system_rootfs "$@"
        ;;
    sd-image)
        ensure_image
        docker run "${docker_run_root[@]}" \
            /workspace/scripts/preflight-v90s-four-partition-image.sh
        docker run "${docker_run_root[@]}" /workspace/scripts/assemble-v90s-four-partition-image.sh "$@"
        ;;
    stockos-image|stockos-sd-image|image-assemble)
        echo "warning: stockos-image uses the legacy seven-partition development layout" >&2
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
    frontend)
        ensure_image
        docker run "${docker_run_user[@]}" /workspace/scripts/build-frontend.sh "$@"
        ;;
    release)
        ensure_image
        docker run "${docker_run_user[@]}" /workspace/scripts/build-release.sh "$@"
        ;;
    standalone|standalone-emulators)
        ensure_image
        docker run \
            -e JOBS="${JOBS:-}" \
            -e PLUMOS_STANDALONE_FILTER="${PLUMOS_STANDALONE_FILTER:-all}" \
            -e FAIL_ON_STANDALONE_ERROR="${FAIL_ON_STANDALONE_ERROR:-1}" \
            "${docker_run_user[@]}" \
            /workspace/docker/plumos-v90s-toolchain/scripts/build-standalone-emulators.sh "$@"
        ;;
    picoarch)
        ensure_image
        docker run \
            -e JOBS="${JOBS:-}" \
            "${docker_run_user[@]}" \
            /workspace/docker/plumos-v90s-toolchain/scripts/build-picoarch.sh "$@"
        ;;
    all)
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
