#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=${ROOT_DIR:-/workspace}
BUILD_ROOT=${BUILD_ROOT:-"${ROOT_DIR}/build"}
TARGET_DIR=${TARGET_DIR:-"${ROOT_DIR}/output/music-player/v90s"}
DEPS_ROOT=${DEPS_ROOT:-"${BUILD_ROOT}/music-player/deps"}

MINIAUDIO_REPO=${MINIAUDIO_REPO:-https://github.com/mackron/miniaudio.git}
MINIAUDIO_REF=${MINIAUDIO_REF:-9634bedb5b5a2ca38c1ee7108a9358a4e233f14d}
MINIAUDIO_RAW_URL=${MINIAUDIO_RAW_URL:-https://raw.githubusercontent.com/mackron/miniaudio/${MINIAUDIO_REF}/miniaudio.h}

CC=${CC:-gcc}
STRIP=${STRIP:-strip}
READELF=${READELF:-readelf}
PKG_CONFIG=${PKG_CONFIG:-pkg-config}

msg() {
  printf '[music-player] %s\n' "$*" >&2
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
        ld-linux-aarch64.so.1|libc.so.6|libm.so.6|libpthread.so.0|libdl.so.2|librt.so.1|libgcc_s.so.1)
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

fetch_miniaudio() {
  local include_dir="${DEPS_ROOT}/miniaudio"
  local header="${include_dir}/miniaudio.h"
  mkdir -p "${include_dir}"
  if [ ! -f "${header}" ]; then
    msg "fetching miniaudio ${MINIAUDIO_REF}"
    curl -LfsS "${MINIAUDIO_RAW_URL}" -o "${header}"
  fi
  printf '%s\n' "${include_dir}"
}

write_launcher() {
  local out=$1
  cat >"${out}" <<'EOF'
#!/bin/sh
set -u

PLUMOS_ROOT="${PLUMOS_ROOT:-/mnt/plumos}"
APP_ROOT="${PLUMOS_MUSIC_PLAYER_ROOT:-${PLUMOS_ROOT}/apps/music-player}"
STATE_DIR="${PLUMOS_MUSIC_PLAYER_STATE:-${PLUMOS_ROOT}/state/apps/music-player}"
LOG_DIR="${PLUMOS_MUSIC_PLAYER_LOG_DIR:-${PLUMOS_ROOT}/Logs/apps}"

mkdir -p "${STATE_DIR}" "${LOG_DIR}" 2>/dev/null || true

if [ ! -x "${APP_ROOT}/bin/plumos-music-player.bin" ]; then
  echo "error: missing music player binary: ${APP_ROOT}/bin/plumos-music-player.bin" >&2
  exit 127
fi

export HOME="${STATE_DIR}"
export XDG_CONFIG_HOME="${STATE_DIR}/.config"
export PLUMOS_ROOT
export PLUMOS_MUSIC_FONT="${PLUMOS_MUSIC_FONT:-${PLUMOS_ROOT}/fonts/default.otf}"
export PLUMOS_MUSIC_FALLBACK_FONT="${PLUMOS_MUSIC_FALLBACK_FONT:-${PLUMOS_ROOT}/fonts/cjk-fallback.ttc}"
export PLUMOS_MUSIC_ALSA_DEVICE="${PLUMOS_MUSIC_ALSA_DEVICE:-${PLUMOS_MUSIC_PLAYER_AUDIO_DEVICE:-hw:0,0}}"
export PATH="${PLUMOS_ROOT}/bin:${PLUMOS_ROOT}/gnu/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export LD_LIBRARY_PATH="${APP_ROOT}/lib:${PLUMOS_ROOT}/lib:${LD_LIBRARY_PATH:-}"

cd "${APP_ROOT}" || exit 1
exec "${APP_ROOT}/bin/plumos-music-player.bin" >>"${LOG_DIR}/music-player.log" 2>&1
EOF
  chmod 0755 "${out}"
}

main() {
  local include_dir
  local app_dir="${TARGET_DIR}/plumos/apps/music-player"
  local bin_dir="${app_dir}/bin"
  local lib_dir="${app_dir}/lib"
  local root_lib_dir="${TARGET_DIR}/plumos/lib"
  local doc_dir="${TARGET_DIR}/plumos/share/doc/plumos-music-player"
  local log_dir="${TARGET_DIR}/docs/build-logs"
  local build_log="${log_dir}/music-player.log"
  local out_bin="${bin_dir}/plumos-music-player.bin"
  local av_cflags
  local av_libs

  rm -rf "${TARGET_DIR}"
  mkdir -p "${bin_dir}" "${lib_dir}" "${root_lib_dir}" "${doc_dir}" "${log_dir}" \
    "${TARGET_DIR}/plumos/bin"

  include_dir=$(fetch_miniaudio)
  av_cflags=$("${PKG_CONFIG}" --cflags libavformat libavcodec libavutil libswresample)
  av_libs=$("${PKG_CONFIG}" --libs libavformat libavcodec libavutil libswresample)

  msg "building plumOS Music Player"
  {
    "$(tool_path "${CC}")" \
      -std=c11 -O2 -pipe \
      -DPLUMOS_FBDEV_ENABLE_FREETYPE=1 \
      -DPLUMOS_MUSIC_ENABLE_ALSA=1 \
      -DPLUMOS_MUSIC_ENABLE_FFMPEG=1 \
      -I"${include_dir}" \
      -I"${ROOT_DIR}/src/apps" \
      -I"${ROOT_DIR}/src/frontend" \
      $("${PKG_CONFIG}" --cflags freetype2 libpng alsa) \
      ${av_cflags} \
      -o "${out_bin}" \
      "${ROOT_DIR}/src/apps/plumos_music_player.c" \
      -lasound -ldl -lfreetype -lpng -ljpeg -lz -lm -lpthread \
      ${av_libs}
  } >"${build_log}" 2>&1

  "${STRIP}" "${out_bin}" 2>/dev/null || true
  copy_dep_tree "${out_bin}" "${root_lib_dir}"
  write_launcher "${TARGET_DIR}/plumos/bin/plumos-music-player-launch"

  {
    printf 'plumOS Music Player for V90S\n'
    printf 'source=src/apps/plumos_music_player.c imported from plumOS-MMF and adapted for V90S fbdev/ALSA\n'
    printf 'binary=plumos/apps/music-player/bin/plumos-music-player.bin\n'
    printf 'launcher=plumos/bin/plumos-music-player-launch\n'
    printf 'music_roots=/mnt/plumos/music,/mnt/plumos/MUSIC,/mnt/plumos/roms/music,/run/plumos/sd2/music,/run/plumos/sd2/roms/music\n'
    printf 'audio_output=ALSA hw:0,0 S16 stereo 48000Hz\n'
    printf 'decoder=miniaudio for mp3/flac/wav; FFmpeg/libav fallback for additional formats\n'
    printf 'miniaudio_repo=%s\n' "${MINIAUDIO_REPO}"
    printf 'miniaudio_ref=%s\n' "${MINIAUDIO_REF}"
    printf 'controls=A play/pause; B or Function exit; Left/Right seek 5 seconds; X/Y track; Select EQ; L/R volume\n'
    printf '\n[needed]\n'
    "${READELF}" -d "${out_bin}" 2>/dev/null |
      awk -F"[][]" '/NEEDED/ {print $2}' || true
  } >"${doc_dir}/manifest.txt"
  cp -f "${build_log}" "${doc_dir}/build.log"

  msg "staged ${TARGET_DIR}"
}

main "$@"
