#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=${ROOT_DIR:-/workspace}
BUILD_ROOT=${BUILD_ROOT:-"${ROOT_DIR}/build"}
TARGET_DIR=${TARGET_DIR:-"${ROOT_DIR}/output/nextcommander/v90s"}
SRC_ROOT=${SRC_ROOT:-"${BUILD_ROOT}/nextcommander/src"}
PATCH_DIR=${PATCH_DIR:-"${ROOT_DIR}/docker/plumos-v90s-toolchain/patches"}
JOBS=${JOBS:-$(nproc 2>/dev/null || echo 2)}

NEXTCOMMANDER_REPO=${NEXTCOMMANDER_REPO:-https://github.com/LoveRetro/NextCommander.git}
NEXTCOMMANDER_REF=${NEXTCOMMANDER_REF:-49c24bb67c12aea8078f48c833815f9ef2dcc5e2}

CC=${CC:-gcc}
CXX=${CXX:-g++}
STRIP=${STRIP:-strip}
READELF=${READELF:-readelf}

msg() {
  printf '[nextcommander] %s\n' "$*" >&2
}

tool_path() {
  command -v "$1" 2>/dev/null || printf '%s\n' "$1"
}

find_target_lib() {
  local name=$1
  local dir
  for dir in \
    /lib/aarch64-linux-gnu \
    /usr/lib/aarch64-linux-gnu \
    /lib \
    /usr/lib; do
    if [ -e "${dir}/${name}" ]; then
      printf '%s/%s\n' "${dir}" "${name}"
      return 0
    fi
  done
  return 1
}

copy_if_present() {
  local src=$1
  local dst=$2
  local soname=${3:-$(basename "${src}")}
  local real_src
  local real_base

  [ -e "${src}" ] || return 0
  mkdir -p "${dst}"
  real_src=$(readlink -f "${src}")
  real_base=$(basename "${real_src}")
  if [ ! -f "${dst}/${real_base}" ]; then
    install -m 0644 "${real_src}" "${dst}/${real_base}"
  fi
  if [ "${soname}" != "${real_base}" ] && [ ! -f "${dst}/${soname}" ]; then
    cp -f "${dst}/${real_base}" "${dst}/${soname}"
    chmod 0644 "${dst}/${soname}"
  fi
}

copy_dep_tree() {
  local elf=$1
  local lib_dir=$2
  local dep
  local path

  [ -f "${elf}" ] || return 0
  "${READELF}" -d "${elf}" 2>/dev/null |
    awk -F"[][]" '/NEEDED/ {print $2}' |
    while IFS= read -r dep; do
      [ -n "${dep}" ] || continue
      case "${dep}" in
        ld-linux-aarch64.so.1|libc.so.6|libm.so.6|libpthread.so.0|libdl.so.2|librt.so.1|libgcc_s.so.1|libstdc++.so.6)
          continue
          ;;
        libSDL2-2.0.so*)
          continue
          ;;
        libEGL.so*|libGLESv2.so*|libGL.so*)
          continue
          ;;
      esac
      path=$(find_target_lib "${dep}" || true)
      if [ -z "${path}" ]; then
        msg "warning: could not locate runtime dependency ${dep}"
        continue
      fi
      if [ ! -f "${lib_dir}/${dep}" ]; then
        copy_if_present "${path}" "${lib_dir}" "${dep}"
        copy_dep_tree "$(readlink -f "${path}")" "${lib_dir}"
      fi
    done
}

clone_nextcommander() {
  local src=$1

  rm -rf "${src}"
  mkdir -p "$(dirname "${src}")"
  msg "cloning ${NEXTCOMMANDER_REPO} (${NEXTCOMMANDER_REF})"
  git clone --depth 1 "${NEXTCOMMANDER_REPO}" "${src}"
  git -C "${src}" fetch --depth 1 origin "${NEXTCOMMANDER_REF}"
  git -C "${src}" checkout --detach FETCH_HEAD
}

write_launcher() {
  local out=$1
  cat >"${out}" <<'EOF'
#!/bin/sh
set -u

PLUMOS_ROOT="${PLUMOS_ROOT:-/mnt/plumos}"
APP_ROOT="${PLUMOS_NEXTCOMMANDER_ROOT:-${PLUMOS_ROOT}/apps/nextcommander}"
STATE_DIR="${PLUMOS_NEXTCOMMANDER_STATE:-${PLUMOS_ROOT}/state/apps/nextcommander}"
LOG_DIR="${PLUMOS_NEXTCOMMANDER_LOG_DIR:-${PLUMOS_ROOT}/Logs/apps}"
SESSION_ID="${PLUMOS_NEXTCOMMANDER_SESSION_ID:-nextcommander-$$}"

mkdir -p "${STATE_DIR}/.config" "${LOG_DIR}" 2>/dev/null || true

if [ ! -x "${APP_ROOT}/bin/NextCommander" ]; then
  echo "error: missing NextCommander binary: ${APP_ROOT}/bin/NextCommander" >&2
  exit 127
fi

export HOME="${STATE_DIR}"
export XDG_CONFIG_HOME="${STATE_DIR}/.config"
export SDL_VIDEODRIVER="${SDL_VIDEODRIVER:-mali}"
export SDL_RENDER_DRIVER="${SDL_RENDER_DRIVER:-opengles2}"
export SDL_AUDIODRIVER="${SDL_AUDIODRIVER:-dummy}"
export SDL_NOMOUSE=1
export PLUMOS_NEXTCOMMANDER_SESSION_ID="${SESSION_ID}"
export PATH="${PLUMOS_ROOT}/bin:${PLUMOS_ROOT}/gnu/bin:/usr/sbin:/usr/bin:/sbin:/bin"
if [ -x /usr/bin/pvrsrvctl ]; then
  (cd /lib/modules/4.9.191 2>/dev/null && /usr/bin/pvrsrvctl --start) >>"${LOG_DIR}/nextcommander.log" 2>&1 || true
fi
export LD_LIBRARY_PATH="/usr/lib/powervr:${PLUMOS_ROOT}/lib/plumos-sdl2-powervr:${APP_ROOT}/lib:${PLUMOS_ROOT}/lib:/usr/lib/aarch64-linux-gnu:/usr/lib:${LD_LIBRARY_PATH:-}"

cd "${APP_ROOT}" || exit 1
exec "${APP_ROOT}/bin/NextCommander" \
  --config "${APP_ROOT}/config/v90s.cfg" \
  --res-dir "${APP_ROOT}/res" \
  >>"${LOG_DIR}/nextcommander.log" 2>&1
EOF
  chmod 0755 "${out}"
}

main() {
  local src="${SRC_ROOT}/nextcommander"
  local app_dir="${TARGET_DIR}/plumos/apps/nextcommander"
  local bin_dir="${app_dir}/bin"
  local lib_dir="${app_dir}/lib"
  local doc_dir="${TARGET_DIR}/plumos/share/doc/nextcommander"
  local log_dir="${TARGET_DIR}/docs/build-logs"
  local build_log="${log_dir}/nextcommander.log"

  rm -rf "${TARGET_DIR}"
  mkdir -p "${bin_dir}" "${lib_dir}" "${doc_dir}" "${log_dir}" \
    "${TARGET_DIR}/plumos/bin"

  clone_nextcommander "${src}" >"${build_log}" 2>&1
  patch -d "${src}" -p1 <"${PATCH_DIR}/nextcommander-v90s.patch" >>"${build_log}" 2>&1

  msg "building NextCommander"
  make -C "${src}" clean >>"${build_log}" 2>&1 || true
  make -C "${src}" -j"${JOBS}" \
    PLATFORM=v90s \
    PREFIX=/usr \
    CC="$(tool_path "${CC}")" \
    CXX="$(tool_path "${CXX}")" >>"${build_log}" 2>&1

  install -m 0755 "${src}/output/NextCommander" "${bin_dir}/NextCommander"
  "${STRIP}" "${bin_dir}/NextCommander" 2>/dev/null || true
  cp -a "${src}/res" "${app_dir}/"
  install -m 0644 "${ROOT_DIR}/package/frontend-v90s/plumos/fonts/cjk-fallback.ttc" \
    "${app_dir}/res/font1.ttf"

  mkdir -p "${app_dir}/config"
  cat >"${app_dir}/config/v90s.cfg" <<'EOF'
disp_width=320
disp_height=240
disp_bpp=32
disp_ppu_x=2
disp_ppu_y=2
disp_autoscale=false
disp_autoscale_dpi=false
path_default=/mnt/plumos
path_default_right=/mnt/plumos/roms
path_default_right_fallback=/run/plumos/sd2/roms
res_dir=/mnt/plumos/apps/nextcommander/res
EOF

  write_launcher "${TARGET_DIR}/plumos/bin/plumos-nextcommander-launch"
  copy_dep_tree "${bin_dir}/NextCommander" "${lib_dir}"

  {
    printf 'NextCommander for plumOS V90S\n'
    printf 'repo=%s\n' "${NEXTCOMMANDER_REPO}"
    printf 'ref=%s\n' "${NEXTCOMMANDER_REF}"
    printf 'patch=nextcommander-v90s.patch\n'
    printf 'binary=plumos/apps/nextcommander/bin/NextCommander\n'
    printf 'launcher=plumos/bin/plumos-nextcommander-launch\n'
    printf 'note=Upstream/source reference: https://github.com/LoveRetro/NextCommander. No separate LICENSE file was present in the inspected upstream repository.\n'
    printf '\n[needed]\n'
    "${READELF}" -d "${bin_dir}/NextCommander" 2>/dev/null |
      awk -F"[][]" '/NEEDED/ {print $2}' || true
  } >"${doc_dir}/manifest.txt"
  cp -f "${build_log}" "${doc_dir}/build.log"

  msg "staged ${TARGET_DIR}"
}

main "$@"
