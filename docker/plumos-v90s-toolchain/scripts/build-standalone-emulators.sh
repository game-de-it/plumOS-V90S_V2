#!/usr/bin/env bash
set -u
set -o pipefail

ROOT_DIR=${ROOT_DIR:-/workspace}
PATCH_DIR=${PATCH_DIR:-"${ROOT_DIR}/docker/plumos-v90s-toolchain/patches"}
BUILD_ROOT=${BUILD_ROOT:-"${ROOT_DIR}/build/standalone-emulators-v90s"}
OUT_DIR=${OUT_DIR:-"${ROOT_DIR}/output/standalone-emulators/v90s"}
SRC_ROOT=${SRC_ROOT:-"${BUILD_ROOT}/src"}
JOBS=${JOBS:-$(nproc 2>/dev/null || echo 2)}
PLUMOS_STANDALONE_FILTER=${PLUMOS_STANDALONE_FILTER:-all}
FAIL_ON_STANDALONE_ERROR=${FAIL_ON_STANDALONE_ERROR:-1}

if [ "$#" -gt 0 ]; then
  PLUMOS_STANDALONE_FILTER=$(IFS=,; printf '%s' "$*")
fi

CC=${CC:-gcc}
CXX=${CXX:-g++}
AR=${AR:-ar}
RANLIB=${RANLIB:-ranlib}
STRIP=${STRIP:-strip}
READELF=${READELF:-readelf}
COMMON_CFLAGS=${COMMON_CFLAGS:-"-O2 -pipe -march=armv8-a+crc -mtune=cortex-a53 -fomit-frame-pointer"}
COMMON_CXXFLAGS=${COMMON_CXXFLAGS:-"${COMMON_CFLAGS}"}
COMMON_LDFLAGS=${COMMON_LDFLAGS:-""}

PPSSPP_REPO=${PPSSPP_REPO:-https://github.com/hrydgard/ppsspp.git}
PPSSPP_REF=${PPSSPP_REF:-v1.20.4}
PPSSPP_FACTORY_DIR=${PLUMOS_V90S_PPSSPP_FACTORY_DIR:-"${ROOT_DIR}/package/frontend-v90s/plumos/factory-defaults/sa/state/standalone/ppsspp/config/ppsspp/PSP/SYSTEM"}
PPSSPP_FACTORY_OUTPUT_REL="plumos/factory-defaults/sa/state/standalone/ppsspp/config/ppsspp/PSP/SYSTEM"
V90S_SDL2_ROOT=${V90S_SDL2_ROOT:-"${ROOT_DIR}/output/sdl2-powervr/usr/local"}
SCUMMVM_REPO=${SCUMMVM_REPO:-https://github.com/scummvm/scummvm.git}
SCUMMVM_REF=${SCUMMVM_REF:-v2026.2.0}
EASYRPG_REPO=${EASYRPG_REPO:-https://github.com/EasyRPG/Player.git}
EASYRPG_REF=${EASYRPG_REF:-0.8.1.1}
OPENBOR_REPO=${OPENBOR_REPO:-https://github.com/DCurrent/openbor.git}
OPENBOR_REF=${OPENBOR_REF:-v6391}
PCSX_REARMED_REPO=${PCSX_REARMED_REPO:-https://github.com/notaz/pcsx_rearmed.git}
PCSX_REARMED_REF=${PCSX_REARMED_REF:-r26l}
PCSX_SDL12_COMPAT_REPO=${PCSX_SDL12_COMPAT_REPO:-https://github.com/libsdl-org/sdl12-compat.git}
PCSX_SDL12_COMPAT_REF=${PCSX_SDL12_COMPAT_REF:-fc2ec0c128197f1f5050e48359bc41e618f3abfb}
FLYCAST_REPO=${FLYCAST_REPO:-https://github.com/flyinghead/flycast.git}
FLYCAST_REF=${FLYCAST_REF:-v2.6}
MUPEN64PLUS_UI_REPO=${MUPEN64PLUS_UI_REPO:-https://github.com/mupen64plus/mupen64plus-ui-console.git}
MUPEN64PLUS_CORE_REPO=${MUPEN64PLUS_CORE_REPO:-https://github.com/mupen64plus/mupen64plus-core.git}
MUPEN64PLUS_AUDIO_REPO=${MUPEN64PLUS_AUDIO_REPO:-https://github.com/mupen64plus/mupen64plus-audio-sdl.git}
MUPEN64PLUS_INPUT_REPO=${MUPEN64PLUS_INPUT_REPO:-https://github.com/mupen64plus/mupen64plus-input-sdl.git}
MUPEN64PLUS_RSP_REPO=${MUPEN64PLUS_RSP_REPO:-https://github.com/mupen64plus/mupen64plus-rsp-hle.git}
MUPEN64PLUS_VIDEO_REPO=${MUPEN64PLUS_VIDEO_REPO:-https://github.com/mupen64plus/mupen64plus-video-rice.git}
MUPEN64PLUS_REF=${MUPEN64PLUS_REF:-2.6.0}
NXENGINE_EVO_REPO=${NXENGINE_EVO_REPO:-https://github.com/nxengine/nxengine-evo.git}
NXENGINE_EVO_REF=${NXENGINE_EVO_REF:-21d8aaf477092b22eceb849c6430c9ce2194c4f7}
YABASANSHIRO_REPO=${YABASANSHIRO_REPO:-https://github.com/libretro/yabause.git}
YABASANSHIRO_REF=${YABASANSHIRO_REF:-8406a5c11d7b6186a44c7fe48f493e6de5f8cb18}
NXENGINE_EVO_DATA_URL=${NXENGINE_EVO_DATA_URL:-https://github.com/PortsMaster/PortMaster-Releases/releases/download/2023-10-12_1508/Cave.Story-evo.zip}
NXENGINE_EVO_DATA_MD5=${NXENGINE_EVO_DATA_MD5:-ca5ff2645f99601d6a60fa8707826e28}
SCUMMVM_ENGINES=${SCUMMVM_ENGINES:-"scumm,agi,agos,sky,sword1,sword2,queen,gob,lure,kyra,sci,cine,drascula,touche,teenagent,tinsel,cruise,parallaction"}

MANIFEST=
LOG_DIR=
SONAME_MAP=
BUILT_COUNT=0
FAILED_COUNT=0
SKIPPED_COUNT=0

msg() { printf '[standalone-v90s] %s\n' "$*" >&2; }
append_manifest() { printf '%s\n' "$*" >>"${MANIFEST}"; }

selected() {
  local id=$1
  case "${PLUMOS_STANDALONE_FILTER}" in
    all|ALL) return 0 ;;
  esac
  case ",${PLUMOS_STANDALONE_FILTER}," in
    *,"${id}",*) return 0 ;;
    *) return 1 ;;
  esac
}

validate_filter() {
  local requested id known
  case "${PLUMOS_STANDALONE_FILTER}" in
    all|ALL) return 0 ;;
  esac
  requested=${PLUMOS_STANDALONE_FILTER//,/ }
  for id in ${requested}; do
    known=0
    case "${id}" in
      launcher-only|ppsspp|scummvm|easyrpg|openbor|pcsx_rearmed|flycast|mupen64plus|nxengine-evo|yabasanshiro)
        known=1
        ;;
    esac
    if [ "${known}" -ne 1 ]; then
      printf 'error: unknown standalone emulator ID: %s\n' "${id}" >&2
      printf 'valid IDs: launcher-only ppsspp scummvm easyrpg openbor pcsx_rearmed flycast mupen64plus nxengine-evo yabasanshiro\n' >&2
      return 2
    fi
  done
}

clone_repo() {
  local id=$1 repo=$2 ref=$3 log=$4 dst
  local actual_commit expected_commit cached_key
  dst="${SRC_ROOT}/${id}"
  local ref_args=()
  if [ -d "${dst}/.git" ]; then
    actual_commit=$(git -C "${dst}" rev-parse HEAD 2>/dev/null || true)
    expected_commit=$(git -C "${dst}" rev-parse "${ref}^{commit}" 2>/dev/null || true)
    cached_key=$(cat "${dst}/.plumos-source-ref" 2>/dev/null || true)
    if [ "${cached_key}" = "${repo} ${ref}" ] ||
       { [ -n "${expected_commit}" ] && [ "${actual_commit}" = "${expected_commit}" ]; }; then
      printf 'Reusing cached source: %s (%s)\n' "${id}" "${ref}" >>"${log}"
      git -C "${dst}" reset --hard --quiet "${actual_commit}" || return 1
      git -C "${dst}" clean -fdx --quiet || return 1
      printf '%s %s\n' "${repo}" "${ref}" >"${dst}/.plumos-source-ref"
      return 0
    fi
  fi
  rm -rf "${dst}"
  case "${ref}" in
    [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]*) ;;
    *) ref_args=(--branch "${ref}") ;;
  esac
  git clone --depth 1 --recurse-submodules --shallow-submodules \
    "${ref_args[@]}" "${repo}" "${dst}" >>"${log}" 2>&1 || return 1
  case "${ref}" in
    [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]*)
      git -C "${dst}" fetch --depth 1 origin "${ref}" >>"${log}" 2>&1 || return 1
      git -C "${dst}" checkout --detach FETCH_HEAD >>"${log}" 2>&1 || return 1
      git -C "${dst}" submodule update --init --recursive --depth 1 >>"${log}" 2>&1 || return 1
      ;;
  esac
  printf '%s %s\n' "${repo}" "${ref}" >"${dst}/.plumos-source-ref"
}

find_binary() {
  local dir=$1 name found
  shift
  for name in "$@"; do
    found=$(find "${dir}" -type f -name "${name}" -perm -111 2>/dev/null | head -n 1)
    if [ -n "${found}" ]; then printf '%s\n' "${found}"; return 0; fi
  done
  return 1
}

copy_runtime_deps() {
  local elf=$1 dep path real soname real_name map_line
  while IFS= read -r path; do
    [ -f "${path}" ] || continue
    soname=$(basename "${path}")
    case "${soname}" in
      ld-linux-aarch64.so.1|libc.so.6|libm.so.6|libpthread.so.0|libdl.so.2|librt.so.1|\
      libEGL.so.*|libGLESv2.so.*|libGL.so.*|libMali.so.*|libSDL2-2.0.so.*)
        continue
        ;;
    esac
    real=$(readlink -f "${path}")
    real_name=$(basename "${real}")
    mkdir -p "${OUT_DIR}/lib"
    if [ ! -f "${OUT_DIR}/lib/${real_name}" ]; then
      install -m 0644 "${real}" "${OUT_DIR}/lib/${real_name}"
      copy_runtime_deps "${real}"
    fi
    map_line=$(printf '%s\t%s' "${soname}" "${real_name}")
    if [ "${soname}" != "${real_name}" ] &&
       ! grep -Fqx "${map_line}" "${SONAME_MAP}"; then
      printf '%s\t%s\n' "${soname}" "${real_name}" >>"${SONAME_MAP}"
    fi
  done < <(
    ldd "${elf}" 2>/dev/null |
      awk '/=> \/[^ ]+/ {print $3} /^[[:space:]]*\// {print $1}' |
      sort -u
  )
}

stage_binary() {
  local id=$1 src=$2 name=$3 dst
  dst="${OUT_DIR}/standalone/${id}/bin/${name}"
  [ -f "${src}" ] || return 1
  mkdir -p "$(dirname "${dst}")"
  install -m 0755 "${src}" "${dst}"
  "${STRIP}" "${dst}" >/dev/null 2>&1 || true
  copy_runtime_deps "${dst}"
  append_manifest "  output=standalone/${id}/bin/${name}"
  append_manifest "  architecture=$(file -b "${dst}")"
}

stage_ppsspp_factory_defaults() {
  local name src dst sha
  dst="${OUT_DIR}/${PPSSPP_FACTORY_OUTPUT_REL}"
  mkdir -p "${dst}"
  rm -f "${OUT_DIR}/config/standalone/ppsspp-v90s-default.ini"
  for name in ppsspp.ini controls.ini; do
    src="${PPSSPP_FACTORY_DIR}/${name}"
    if [ ! -f "${src}" ]; then
      echo "missing V90S PPSSPP factory config: ${src}" >&2
      return 1
    fi
    install -m 0644 "${src}" "${dst}/${name}" || return 1
    sha=$(sha256sum "${dst}/${name}" | awk '{print $1}')
    append_manifest "ppsspp_factory_${name%.ini}_source=${src}"
    append_manifest "ppsspp_factory_${name%.ini}_output=${PPSSPP_FACTORY_OUTPUT_REL}/${name}"
    append_manifest "ppsspp_factory_${name%.ini}_sha256=${sha}"
  done
}

stage_license() {
  local id=$1 src=$2 file
  for file in COPYING COPYING.txt LICENSE LICENSE.txt LICENSE.md COPYING.md LICENSES; do
    if [ -f "${src}/${file}" ]; then
      install -m 0644 "${src}/${file}" "${OUT_DIR}/licenses/${id}-${file}"
      append_manifest "  license=licenses/${id}-${file}"
      return 0
    fi
  done
}

build_ppsspp() {
  local src=$1 build bin
  build="${src}/build-v90s"
  if [ ! -f "${V90S_SDL2_ROOT}/include/SDL2/SDL.h" ] ||
     [ ! -f "${V90S_SDL2_ROOT}/lib/plumos-sdl2-powervr/libSDL2.so" ]; then
    echo "missing V90S SDL2 build under ${V90S_SDL2_ROOT}" >&2
    return 1
  fi
  if patch --dry-run -d "${src}" -p1 <"${PATCH_DIR}/ppsspp-1.20.4-v90s-egl-config.patch" >/dev/null 2>&1; then
    patch -d "${src}" -p1 <"${PATCH_DIR}/ppsspp-1.20.4-v90s-egl-config.patch" || return 1
  elif ! patch --dry-run -R -d "${src}" -p1 <"${PATCH_DIR}/ppsspp-1.20.4-v90s-egl-config.patch" >/dev/null 2>&1; then
    return 1
  fi
  rm -rf "${build}"
  cmake -S "${src}" -B "${build}" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_FLAGS="-I${V90S_SDL2_ROOT}/include/SDL2 -I${V90S_SDL2_ROOT}/include ${COMMON_CFLAGS}" \
    -DCMAKE_CXX_FLAGS="-I${V90S_SDL2_ROOT}/include/SDL2 -I${V90S_SDL2_ROOT}/include ${COMMON_CXXFLAGS} -DPLUMOS_V90S=1" \
    -DCMAKE_EXE_LINKER_FLAGS="${COMMON_LDFLAGS}" \
    -DARM64=ON -DARMV7=OFF \
    -DUSING_EGL=OFF -DUSING_FBDEV=ON -DUSING_GLES2=ON \
    -DPLUMOS_V90S=ON \
    -DUSING_X11_VULKAN=OFF -DUSE_WAYLAND_WSI=OFF \
    -DUSE_VULKAN_DISPLAY_KHR=OFF -DUSE_FFMPEG=ON \
    -DUSE_SYSTEM_FFMPEG=OFF -DUSE_DISCORD=OFF -DUSE_MINIUPNPC=OFF \
    -DUSE_SYSTEM_LIBSDL2=ON -DUSE_SYSTEM_LIBPNG=ON \
    -DSDL2_INCLUDE_DIR="${V90S_SDL2_ROOT}/include/SDL2" \
    -DSDL2_LIBRARY="${V90S_SDL2_ROOT}/lib/plumos-sdl2-powervr/libSDL2.so" \
    -DUSE_SYSTEM_FREETYPE=OFF -DUSE_SYSTEM_LIBCHDR=OFF \
    -DUSE_SYSTEM_LIBZIP=OFF -DUSE_SYSTEM_SNAPPY=OFF -DUSE_SYSTEM_ZSTD=OFF \
    -DHEADLESS=OFF -DUNITTEST=OFF -DATLAS_TOOL=OFF -DUSING_QT_UI=OFF \
    -DMOBILE_DEVICE=OFF -DGOLD=OFF || return 1
  cmake --build "${build}" --target PPSSPPSDL -j"${JOBS}" || return 1
  bin=$(find_binary "${build}" PPSSPPSDL) || return 1
  stage_binary ppsspp "${bin}" PPSSPPSDL || return 1
  rsync -a --delete "${src}/assets/" "${OUT_DIR}/standalone/ppsspp/assets/"
  append_manifest "  data=standalone/ppsspp/assets"
}

build_scummvm() {
  local src=$1 bin data file patch_file
  data="${OUT_DIR}/standalone/scummvm/share/scummvm"
  patch_file="${PATCH_DIR}/scummvm-2026.2.0-v90s-controls.patch"
  if patch --dry-run -d "${src}" -p1 <"${patch_file}" >/dev/null 2>&1; then
    patch -d "${src}" -p1 <"${patch_file}" || return 1
  elif ! patch --dry-run -R -d "${src}" -p1 <"${patch_file}" >/dev/null 2>&1; then
    msg "ScummVM V90S controls patch does not apply cleanly"
    return 1
  fi
  (
    cd "${src}" || exit 1
    env CC="${CC}" CXX="${CXX}" AR="${AR}" RANLIB="${RANLIB}" \
      CFLAGS="${COMMON_CFLAGS}" CXXFLAGS="${COMMON_CXXFLAGS} -DPLUMOS_V90S=1" LDFLAGS="${COMMON_LDFLAGS}" \
      ./configure --backend=sdl --prefix=/mnt/plumos/standalone/scummvm \
        --enable-release --disable-debug --disable-all-engines \
        --enable-engine="${SCUMMVM_ENGINES}" --disable-mt32emu --disable-seq-midi \
        --disable-timidity --disable-lua --disable-nuked-opl --disable-hq-scalers \
        --disable-taskbar --disable-cloud --disable-system-dialogs \
        --disable-eventrecorder --disable-tts --opengl-mode=none --disable-tinygl \
        --disable-fluidsynth --disable-fluidlite --disable-sonivox --disable-gtk \
        --disable-sndio && make -j"${JOBS}"
  ) || return 1
  bin=$(find_binary "${src}" scummvm) || return 1
  stage_binary scummvm "${bin}" scummvm || return 1
  mkdir -p "${data}"
  for file in gui/themes/gui-icons.dat gui/themes/scummclassic.zip gui/themes/scummmodern.zip \
    gui/themes/scummremastered.zip gui/themes/residualvm.zip gui/themes/shaders.dat \
    gui/themes/translations.dat dists/engine-data/encoding.dat dists/engine-data/drascula.dat \
    dists/engine-data/helpdialog.zip dists/engine-data/kyra.dat dists/engine-data/lure.dat \
    dists/engine-data/queen.tbl dists/engine-data/sky.cpt dists/engine-data/teenagent.dat \
    backends/vkeybd/packs/vkeybd_default.zip backends/vkeybd/packs/vkeybd_small.zip; do
    [ ! -f "${src}/${file}" ] || install -m 0644 "${src}/${file}" "${data}/$(basename "${file}")"
  done
  append_manifest "  data=standalone/scummvm/share/scummvm"
}

build_easyrpg() {
  local src=$1 build bin
  build="${src}/build-v90s"
  rm -rf "${build}"
  cmake -S "${src}" -B "${build}" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_FLAGS="${COMMON_CFLAGS}" \
    -DCMAKE_CXX_FLAGS="${COMMON_CXXFLAGS}" -DPLAYER_TARGET_PLATFORM=SDL2 \
    -DPLAYER_AUDIO_BACKEND=SDL2 -DPLAYER_BUILD_EXECUTABLE=ON \
    -DPLAYER_BUILD_LIBLCF=ON -DPLAYER_BUILD_LIBLCF_BRANCH=0.8.1 \
    -DLIBLCF_WITH_ICU=ON -DLIBLCF_WITH_XML=ON \
    -DLIBLCF_ENABLE_TOOLS=OFF -DLIBLCF_ENABLE_TESTS=OFF \
    -DLIBLCF_ENABLE_BENCHMARKS=OFF \
    -DPLAYER_ENABLE_TESTS=OFF -DPLAYER_ENABLE_BENCHMARKS=OFF \
    -DPLAYER_WITH_FREETYPE=ON -DPLAYER_WITH_HARFBUZZ=ON \
    -DPLAYER_WITH_LHASA=ON -DPLAYER_WITH_MPG123=ON \
    -DPLAYER_WITH_LIBSNDFILE=ON -DPLAYER_WITH_OGGVORBIS=ON \
    -DPLAYER_WITH_OPUS=ON -DPLAYER_WITH_XMP=ON \
    -DPLAYER_WITH_SPEEXDSP=ON -DPLAYER_WITH_SAMPLERATE=ON \
    -DPLAYER_ENABLE_FMMIDI=ON -DPLAYER_ENABLE_DRWAV=ON \
    -DPLAYER_WITH_WILDMIDI=OFF \
    -DPLAYER_WITH_FLUIDSYNTH=OFF -DPLAYER_WITH_FLUIDLITE=OFF \
    -DPLAYER_WITH_NATIVE_MIDI=OFF || return 1
  cmake --build "${build}" --target easyrpg-player -j"${JOBS}" || return 1
  bin=$(find_binary "${build}" easyrpg-player) || return 1
  stage_binary easyrpg "${bin}" easyrpg-player
}

build_openbor() {
  local src=$1 engine bin patch_file
  engine="${src}/engine"
  bin="${src}/engine/OpenBOR"
  patch_file="${PATCH_DIR}/openbor-v6391-v90s-video.patch"
  if patch --dry-run -d "${src}" -p1 <"${patch_file}" >/dev/null 2>&1; then
    patch -d "${src}" -p1 <"${patch_file}" || return 1
  elif ! patch --dry-run -R -d "${src}" -p1 <"${patch_file}" >/dev/null 2>&1; then
    echo "OpenBOR V90S video patch does not apply cleanly" >&2
    return 1
  fi
  sed -i 's/-Wall -Werror/-Wall/g' "${engine}/Makefile"
  (
    cd "${engine}" || exit 1
    make clean BUILD_LINUX=1 >/dev/null 2>&1 || true
    make -j"${JOBS}" BUILD_LINUX=1 BUILD_MMX= BUILD_OPENGL= BUILD_LOADGL= \
      BUILD_WEBM= NO_STRIP=1 VERSION_NAME=OpenBOR LNXDEV=/usr/bin PREFIX= \
      GCC_TARGET=aarch64-linux-gnu TARGET_ARCH=aarch64 \
      ARCHFLAGS="${COMMON_CFLAGS} -DPLUMOS_V90S=1 -fcommon -Isource/webmlib" \
      LIBRARIES=/usr/lib/aarch64-linux-gnu CC="${CC}"
  ) || return 1
  stage_binary openbor "${bin}" OpenBOR
}

build_pcsx_rearmed() {
  local src=$1 input_patch libpicofe_patch fbdev_patch fbdev_header compat_src compat_build compat_log compat_lib
  input_patch="${PATCH_DIR}/pcsx-rearmed-r26l-v90s-input.patch"
  libpicofe_patch="${PATCH_DIR}/pcsx-rearmed-r26l-v90s-libpicofe-input.patch"
  fbdev_patch="${PATCH_DIR}/pcsx-rearmed-r26l-v90s-fbdev.patch"
  fbdev_header="${PATCH_DIR}/pcsx_v90s_fbdev.h"
  compat_src="${SRC_ROOT}/pcsx_sdl12_compat"
  compat_build="${compat_src}/build-v90s"
  compat_log="${LOG_DIR}/pcsx_rearmed.log"
  compat_lib="${compat_build}/libSDL-1.2.so.1.2.72"
  if [ ! -f "${V90S_SDL2_ROOT}/include/SDL2/SDL.h" ] ||
     [ ! -f "${V90S_SDL2_ROOT}/lib/plumos-sdl2-powervr/libSDL2.so" ]; then
    echo "missing V90S SDL2 build under ${V90S_SDL2_ROOT}" >&2
    return 1
  fi
  if patch --dry-run -d "${src}" -p1 <"${input_patch}" >/dev/null 2>&1; then
    patch -d "${src}" -p1 <"${input_patch}" || return 1
  elif ! patch --dry-run -R -d "${src}" -p1 <"${input_patch}" >/dev/null 2>&1; then
    echo "PCSX-ReARMed V90S input patch does not apply cleanly" >&2
    return 1
  fi
  if patch --dry-run -d "${src}/frontend/libpicofe" -p1 <"${libpicofe_patch}" >/dev/null 2>&1; then
    patch -d "${src}/frontend/libpicofe" -p1 <"${libpicofe_patch}" || return 1
  elif ! patch --dry-run -R -d "${src}/frontend/libpicofe" -p1 <"${libpicofe_patch}" >/dev/null 2>&1; then
    echo "PCSX-ReARMed V90S libpicofe patch does not apply cleanly" >&2
    return 1
  fi
  if patch --dry-run -d "${src}" -p1 <"${fbdev_patch}" >/dev/null 2>&1; then
    patch -d "${src}" -p1 <"${fbdev_patch}" || return 1
  elif ! patch --dry-run -R -d "${src}" -p1 <"${fbdev_patch}" >/dev/null 2>&1; then
    echo "PCSX-ReARMed V90S fbdev patch does not apply cleanly" >&2
    return 1
  fi
  install -m 0644 "${fbdev_header}" "${src}/frontend/pcsx_v90s_fbdev.h" || return 1
  (
    cd "${src}" || exit 1
    make clean >/dev/null 2>&1 || true
    env CC="${CC}" CXX="${CXX}" AR="${AR}" RANLIB="${RANLIB}" STRIP="${STRIP}" \
      CFLAGS="${COMMON_CFLAGS} -DPLUMOS_V90S=1" \
      CXXFLAGS="${COMMON_CXXFLAGS} -DPLUMOS_V90S=1" LDFLAGS="${COMMON_LDFLAGS}" \
      ./configure --platform=generic --gpu=neon --sound-drivers="alsa sdl" \
        --enable-neon --enable-threads --disable-dynamic --dynarec=ari64 && \
      make -j"${JOBS}"
  ) || return 1
  rm -rf "${OUT_DIR}/standalone/pcsx_rearmed"
  stage_binary pcsx_rearmed "${src}/pcsx" pcsx || return 1

  clone_repo pcsx_sdl12_compat "${PCSX_SDL12_COMPAT_REPO}" \
    "${PCSX_SDL12_COMPAT_REF}" "${compat_log}" || return 1
  cmake -S "${compat_src}" -B "${compat_build}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DSDL2_INCLUDE_DIRS="${V90S_SDL2_ROOT}/include/SDL2" \
    -DSDL12TESTS=OFF || return 1
  cmake --build "${compat_build}" -j"${JOBS}" || return 1
  [ -f "${compat_lib}" ] || return 1
  mkdir -p "${OUT_DIR}/standalone/pcsx_rearmed/lib"
  install -m 0644 "${compat_lib}" \
    "${OUT_DIR}/standalone/pcsx_rearmed/lib/libSDL-1.2.so.0"
  install -m 0644 "${compat_src}/LICENSE.txt" \
    "${OUT_DIR}/licenses/pcsx_rearmed-sdl12-compat-LICENSE.txt"
  append_manifest "  sdl12_compat_repo=${PCSX_SDL12_COMPAT_REPO}"
  append_manifest "  sdl12_compat_ref=${PCSX_SDL12_COMPAT_REF}"
  append_manifest "  runtime=standalone/pcsx_rearmed/lib/libSDL-1.2.so.0"
}

build_flycast() {
  local src=$1 build bin
  build="${src}/build-v90s"
  rm -rf "${build}"
  cmake -S "${src}" -B "${build}" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_FLAGS="${COMMON_CFLAGS}" \
    -DCMAKE_CXX_FLAGS="${COMMON_CXXFLAGS}" \
    -DCMAKE_EXE_LINKER_FLAGS="${COMMON_LDFLAGS}" \
    -DBUILD_TESTING=OFF -DLIBRETRO=OFF \
    -DUSE_GLES2=ON -DUSE_GLES=OFF -DUSE_OPENGL=ON -DUSE_VULKAN=OFF \
    -DUSE_HOST_SDL=ON -DUSE_HOST_LIBZIP=OFF -DUSE_HOST_LIBCHDR=OFF \
    -DUSE_OPENMP=OFF -DUSE_BREAKPAD=OFF -DUSE_LUA=OFF \
    -DUSE_DISCORD=OFF -DUSE_PULSEAUDIO=OFF -DUSE_LIBAO=OFF \
    -DUSE_ALSA=ON || return 1
  cmake --build "${build}" --target flycast -j"${JOBS}" || return 1
  bin=$(find_binary "${build}" flycast) || return 1
  stage_binary flycast "${bin}" flycast
}

clone_mupen64plus_component() {
  local id=$1 repo=$2 dst=$3 log=$4
  if [ -d "${dst}/.git" ] &&
     [ "$(cat "${dst}/.plumos-source-ref" 2>/dev/null || true)" = "${repo} ${MUPEN64PLUS_REF}" ]; then
    printf 'Reusing cached source: %s (%s)\n' "${id}" "${MUPEN64PLUS_REF}" >>"${log}"
    return 0
  fi
  rm -rf "${dst}"
  git clone --depth 1 --branch "${MUPEN64PLUS_REF}" "${repo}" "${dst}" >>"${log}" 2>&1 || return 1
  printf '%s %s\n' "${repo}" "${MUPEN64PLUS_REF}" >"${dst}/.plumos-source-ref"
}

build_mupen64plus() {
  local src=$1 stage prefix api component component_src component_repo log elf input_cfg target hotkey_src hotkey_bin
  stage="${src}/stage-v90s"
  prefix=/mnt/plumos/standalone/mupen64plus
  api="${src}/components/core/src/api"
  log="${LOG_DIR}/mupen64plus.log"
  rm -rf "${stage}"
  mkdir -p "${src}/components" "${stage}"

  for component in core audio-sdl input-sdl rsp-hle video-rice; do
    case "${component}" in
      core) component_repo=${MUPEN64PLUS_CORE_REPO} ;;
      audio-sdl) component_repo=${MUPEN64PLUS_AUDIO_REPO} ;;
      input-sdl) component_repo=${MUPEN64PLUS_INPUT_REPO} ;;
      rsp-hle) component_repo=${MUPEN64PLUS_RSP_REPO} ;;
      video-rice) component_repo=${MUPEN64PLUS_VIDEO_REPO} ;;
    esac
    clone_mupen64plus_component "mupen64plus-${component}" "${component_repo}" \
      "${src}/components/${component}" "${log}" || return 1
  done

  component_src="${src}/components/core"
  make -C "${component_src}/projects/unix" clean >/dev/null 2>&1 || true
  env CFLAGS="${COMMON_CFLAGS}" CXXFLAGS="${COMMON_CXXFLAGS}" LDFLAGS="${COMMON_LDFLAGS}" \
    make -C "${component_src}/projects/unix" -j"${JOBS}" \
      HOST_CPU=aarch64 PIC=1 USE_GLES=1 VULKAN=0 PREFIX="${prefix}" || return 1
  make -C "${component_src}/projects/unix" install \
    HOST_CPU=aarch64 PIC=1 USE_GLES=1 VULKAN=0 PREFIX="${prefix}" DESTDIR="${stage}" || return 1

  for component in audio-sdl input-sdl rsp-hle video-rice; do
    component_src="${src}/components/${component}"
    make -C "${component_src}/projects/unix" clean >/dev/null 2>&1 || true
    env CFLAGS="${COMMON_CFLAGS}" CXXFLAGS="${COMMON_CXXFLAGS}" LDFLAGS="${COMMON_LDFLAGS}" \
      make -C "${component_src}/projects/unix" -j"${JOBS}" \
        HOST_CPU=aarch64 PIC=1 USE_GLES=1 APIDIR="${api}" PREFIX="${prefix}" || return 1
    make -C "${component_src}/projects/unix" install \
      HOST_CPU=aarch64 PIC=1 USE_GLES=1 APIDIR="${api}" PREFIX="${prefix}" \
      DESTDIR="${stage}" || return 1
  done

  make -C "${src}/projects/unix" clean >/dev/null 2>&1 || true
  env CFLAGS="${COMMON_CFLAGS}" CXXFLAGS="${COMMON_CXXFLAGS}" LDFLAGS="${COMMON_LDFLAGS}" \
    make -C "${src}/projects/unix" -j"${JOBS}" \
      HOST_CPU=aarch64 PIC=1 APIDIR="${api}" PREFIX="${prefix}" \
      COREDIR="${prefix}/lib/" PLUGINDIR="${prefix}/lib/mupen64plus" \
      SHAREDIR="${prefix}/share/mupen64plus" || return 1
  make -C "${src}/projects/unix" install \
    HOST_CPU=aarch64 PIC=1 APIDIR="${api}" PREFIX="${prefix}" \
    COREDIR="${prefix}/lib/" PLUGINDIR="${prefix}/lib/mupen64plus" \
    SHAREDIR="${prefix}/share/mupen64plus" DESTDIR="${stage}" || return 1

  rsync -a "${stage}${prefix}/" "${OUT_DIR}/standalone/mupen64plus/"
  hotkey_src="${ROOT_DIR}/docker/plumos-v90s-toolchain/standalone/plumos-mupen64plus-hotkey.c"
  hotkey_bin="${OUT_DIR}/standalone/mupen64plus/bin/plumos-mupen64plus-hotkey"
  [ -f "${hotkey_src}" ] || return 1
  "${CC}" ${COMMON_CFLAGS} -Wall -Wextra -Werror \
    "${hotkey_src}" -o "${hotkey_bin}" || return 1
  input_cfg="${OUT_DIR}/standalone/mupen64plus/share/mupen64plus/InputAutoCfg.ini"
  if ! grep -Fqx '[adc_gamepad]' "${input_cfg}"; then
    cat >>"${input_cfg}" <<'EOF'

; POWKIDDY V90S built-in controls
[adc_gamepad]
plugged = True
mouse = False
AnalogDeadzone = 0,0
AnalogPeak = 32768,32768
DPad R = hat(0 Right)
DPad L = hat(0 Left)
DPad D = hat(0 Down)
DPad U = hat(0 Up)
Start = button(9)
Z Trig = button(8)
B Button = button(1)
A Button = button(0)
C Button R = button(7)
C Button L = button(6)
C Button D = button(2)
C Button U = button(3)
R Trig = button(5)
L Trig = button(4)
Mempak switch =
Rumblepak switch =
X Axis = hat(0 Left Right)
Y Axis = hat(0 Up Down)
EOF
  fi
  while IFS= read -r elf; do
    target=$(readlink -f "${elf}") || return 1
    rm -f "${elf}"
    cp -a "${target}" "${elf}"
  done < <(find "${OUT_DIR}/standalone/mupen64plus" -type l)
  while IFS= read -r elf; do
    "${STRIP}" "${elf}" >/dev/null 2>&1 || true
    copy_runtime_deps "${elf}"
  done < <(find "${OUT_DIR}/standalone/mupen64plus" -type f \
    \( -perm -111 -o -name '*.so' -o -name '*.so.*' \))
  append_manifest "  output=standalone/mupen64plus/bin/mupen64plus"
  append_manifest "  helper=standalone/mupen64plus/bin/plumos-mupen64plus-hotkey"
  append_manifest "  data=standalone/mupen64plus/lib/mupen64plus"
  append_manifest "  data=standalone/mupen64plus/share/mupen64plus"
}

build_nxengine_evo() {
  local src=$1 build archive extract bin
  build="${src}/build-v90s"
  archive="${BUILD_ROOT}/downloads/Cave.Story-evo.zip"
  extract="${BUILD_ROOT}/nxengine-evo-data"

  if patch --dry-run -d "${src}" -p1 <"${PATCH_DIR}/nxengine-evo-2.6.5-v90s.patch" >/dev/null 2>&1; then
    patch -d "${src}" -p1 <"${PATCH_DIR}/nxengine-evo-2.6.5-v90s.patch" || return 1
  elif ! patch --dry-run -R -d "${src}" -p1 <"${PATCH_DIR}/nxengine-evo-2.6.5-v90s.patch" >/dev/null 2>&1; then
    return 1
  fi

  rm -rf "${build}"
  cmake -S "${src}" -B "${build}" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DPORTABLE=ON \
    -DCMAKE_C_FLAGS="${COMMON_CFLAGS}" \
    -DCMAKE_CXX_FLAGS="${COMMON_CXXFLAGS} -DPLUMOS_V90S=1" \
    -DCMAKE_EXE_LINKER_FLAGS="${COMMON_LDFLAGS}" || return 1
  cmake --build "${build}" --target nx -j"${JOBS}" || return 1
  bin=$(find_binary "${build}" nxengine-evo) || return 1
  stage_binary nxengine-evo "${bin}" nxengine-evo || return 1

  mkdir -p "$(dirname "${archive}")"
  if [ ! -f "${archive}" ] ||
     ! printf '%s  %s\n' "${NXENGINE_EVO_DATA_MD5}" "${archive}" | md5sum -c - >/dev/null 2>&1; then
    rm -f "${archive}"
    curl --fail --location --retry 3 --output "${archive}" "${NXENGINE_EVO_DATA_URL}" || return 1
  fi
  printf '%s  %s\n' "${NXENGINE_EVO_DATA_MD5}" "${archive}" | md5sum -c - || return 1
  rm -rf "${extract}"
  mkdir -p "${extract}"
  unzip -q "${archive}" 'nxengine-evo/data/*' 'nxengine-evo/Doukutsu.exe' -d "${extract}" || return 1
  rm -rf "${OUT_DIR}/standalone/nxengine-evo/data" \
    "${OUT_DIR}/standalone/nxengine-evo/share/nxengine/data"
  mkdir -p "${OUT_DIR}/standalone/nxengine-evo/share/nxengine/data"
  rsync -a "${extract}/nxengine-evo/data/" \
    "${OUT_DIR}/standalone/nxengine-evo/share/nxengine/data/" || return 1
  install -m 0644 "${extract}/nxengine-evo/Doukutsu.exe" \
    "${OUT_DIR}/standalone/nxengine-evo/Doukutsu.exe" || return 1
  append_manifest "  data=standalone/nxengine-evo/share/nxengine/data"
  append_manifest "  content=standalone/nxengine-evo/Doukutsu.exe"
  append_manifest "  content_url=${NXENGINE_EVO_DATA_URL}"
  append_manifest "  content_md5=${NXENGINE_EVO_DATA_MD5}"
}

build_yabasanshiro() {
  local src=$1 build bin patch_file standalone_patch input_patch framebuffer_readback_patch readback_patch
  build="${src}/yabause/build-v90s-standalone"
  patch_file="${ROOT_DIR}/docker/plumos-v90s-toolchain/patches/yabasanshiro-2.10.4-arm64-gcc12.patch"
  standalone_patch="${PATCH_DIR}/yabasanshiro-2.10.4-v90s-standalone.patch"
  input_patch="${PATCH_DIR}/yabasanshiro-2.10.4-v90s-input.patch"
  framebuffer_readback_patch="${PATCH_DIR}/yabasanshiro-2.10.4-vdp1-framebuffer-readback.patch"
  readback_patch="${PATCH_DIR}/yabasanshiro-2.10.4-v90s-vdp1-readback.patch"

  if [ ! -f "${V90S_SDL2_ROOT}/include/SDL2/SDL.h" ] ||
     [ ! -f "${V90S_SDL2_ROOT}/lib/plumos-sdl2-powervr/libSDL2.so" ]; then
    echo "missing V90S SDL2 build under ${V90S_SDL2_ROOT}" >&2
    return 1
  fi
  if patch --dry-run -d "${src}" -p1 <"${patch_file}" >/dev/null 2>&1; then
    patch -d "${src}" -p1 <"${patch_file}" || return 1
  elif ! patch --dry-run -R -d "${src}" -p1 <"${patch_file}" >/dev/null 2>&1; then
    echo "YabaSanshiro ARM64 patch does not apply cleanly" >&2
    return 1
  fi
  if patch --dry-run -d "${src}" -p1 <"${standalone_patch}" >/dev/null 2>&1; then
    patch -d "${src}" -p1 <"${standalone_patch}" || return 1
  elif ! patch --dry-run -R -d "${src}" -p1 <"${standalone_patch}" >/dev/null 2>&1; then
    echo "YabaSanshiro V90S standalone patch does not apply cleanly" >&2
    return 1
  fi
  if patch --dry-run -d "${src}" -p1 <"${input_patch}" >/dev/null 2>&1; then
    patch -d "${src}" -p1 <"${input_patch}" || return 1
  elif ! patch --dry-run -R -d "${src}" -p1 <"${input_patch}" >/dev/null 2>&1; then
    echo "YabaSanshiro V90S input patch does not apply cleanly" >&2
    return 1
  fi
  if patch --dry-run -d "${src}" -p1 <"${framebuffer_readback_patch}" >/dev/null 2>&1; then
    patch -d "${src}" -p1 <"${framebuffer_readback_patch}" || return 1
  elif ! patch --dry-run -R -d "${src}" -p1 <"${framebuffer_readback_patch}" >/dev/null 2>&1; then
    echo "YabaSanshiro VDP1 framebuffer-readback patch does not apply cleanly" >&2
    return 1
  fi
  if patch --dry-run -d "${src}" -p1 <"${readback_patch}" >/dev/null 2>&1; then
    patch -d "${src}" -p1 <"${readback_patch}" || return 1
  elif ! patch --dry-run -R -d "${src}" -p1 <"${readback_patch}" >/dev/null 2>&1; then
    echo "YabaSanshiro V90S VDP1 readback patch does not apply cleanly" >&2
    return 1
  fi

  rm -rf "${build}"
  mkdir -p "${build}/compat/libpng12"
  ln -s /usr/include/png.h "${build}/compat/libpng12/png.h"
  cmake -S "${src}/yabause" -B "${build}" -G "Unix Makefiles" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ \
    -DCMAKE_C_FLAGS="-I${build}/compat -I${V90S_SDL2_ROOT}/include/SDL2 -I${V90S_SDL2_ROOT}/include ${COMMON_CFLAGS} -D__RETORO_ARENA__ -Wno-error" \
    -DCMAKE_CXX_FLAGS="-I${build}/compat -I${V90S_SDL2_ROOT}/include/SDL2 -I${V90S_SDL2_ROOT}/include ${COMMON_CXXFLAGS} -D__RETORO_ARENA__ -Wno-error" \
    -DCMAKE_EXE_LINKER_FLAGS="${COMMON_LDFLAGS}" \
    -DYAB_PORTS=retro_arena -DUSE_EGL=ON -DYAB_FORCE_GLES20=ON \
    -DYAB_WANT_VULKAN=OFF -DYAB_WANT_ARM7=ON \
    -DSH2_DYNAREC=OFF -DYAB_WANT_DYNAREC_DEVMIYAX=ON -DYAB_ASYNC_RENDERING=ON \
    -DSH2_TRACE=OFF \
    -DSDL2_INCLUDE_DIR="${V90S_SDL2_ROOT}/include/SDL2" \
    -DSDL2_LIBRARY="${V90S_SDL2_ROOT}/lib/plumos-sdl2-powervr/libSDL2.so" || return 1
  cmake --build "${build}" --target yabause-retro-arena -j"${JOBS}" || return 1
  bin=$(find_binary "${build}" yabasanshiro) || return 1
  stage_binary yabasanshiro "${bin}" yabasanshiro
}

write_launcher() {
  mkdir -p "${OUT_DIR}/bin" "${OUT_DIR}/config/standalone"
  cat >"${OUT_DIR}/bin/plumos-standalone-launch" <<'EOF'
#!/bin/sh
set -u
PLUMOS_ROOT=${PLUMOS_ROOT:-/mnt/plumos}
PLUMOS_RUNTIME_ROOT=${PLUMOS_RUNTIME_ROOT:-/run/plumos}
EMU_ROOT="${PLUMOS_ROOT}/standalone"
LOG_ROOT="${PLUMOS_ROOT}/Logs/standalone"
id=${1:-}
[ "$#" -gt 0 ] && shift
mkdir -p "${LOG_ROOT}"
export HOME="${PLUMOS_ROOT}/state/standalone/${id}"
export XDG_CONFIG_HOME="${HOME}/config"
export XDG_DATA_HOME="${HOME}/data"
export XDG_CACHE_HOME="${PLUMOS_RUNTIME_ROOT}/cache/standalone/${id}"
export PATH="${PLUMOS_ROOT}/bin:${PATH}"
SONAME_MAP="${PLUMOS_ROOT}/config/standalone/soname-links.tsv"
SONAME_DIR="${PLUMOS_RUNTIME_ROOT}/standalone/lib"
mkdir -p "${SONAME_DIR}"
find "${SONAME_DIR}" -type l -delete 2>/dev/null || true
if [ -f "${SONAME_MAP}" ]; then
  while IFS="$(printf '\t')" read -r soname real_name; do
    [ -n "${soname}" ] && [ -f "${PLUMOS_ROOT}/lib/${real_name}" ] || continue
    ln -sf "${PLUMOS_ROOT}/lib/${real_name}" "${SONAME_DIR}/${soname}"
  done <"${SONAME_MAP}"
fi
export LD_LIBRARY_PATH="/usr/lib/powervr:${SONAME_DIR}:${PLUMOS_ROOT}/lib/plumos-sdl2-powervr:${PLUMOS_ROOT}/lib:${LD_LIBRARY_PATH:-}"
export SDL_VIDEODRIVER=${SDL_VIDEODRIVER:-mali}
export SDL_AUDIODRIVER=${SDL_AUDIODRIVER:-alsa}
AUDIO_OUTPUT_HELPER=${PLUMOS_AUDIO_OUTPUT_HELPER:-${PLUMOS_ROOT}/bin/plumos-audio-output}
if [ ! -x "${AUDIO_OUTPUT_HELPER}" ]; then
  echo "plumos-standalone-launch: audio output helper missing: ${AUDIO_OUTPUT_HELPER}" >&2
  exit 49
fi
audio_status=$(${AUDIO_OUTPUT_HELPER} prepare 2>&1) || {
  echo "plumos-standalone-launch: audio output prepare failed: ${audio_status}" >&2
  exit 49
}
export ALSA_CONFIG_PATH=${PLUMOS_ALSA_CONFIG_PATH:-${PLUMOS_RUNTIME_ROOT}/audio/asound.conf}
export ALSA_PLUGIN_DIR=${PLUMOS_ALSA_PLUGIN_DIR:-${PLUMOS_ROOT}/lib/alsa-lib}
export AUDIODEV=${AUDIODEV:-plumos_output}
printf 'audio_device=%s alsa_config=%s %s\n' "${AUDIODEV}" "${ALSA_CONFIG_PATH}" \
  "$(printf '%s' "${audio_status}" | tr '\n' ' ')" >>"${LOG_ROOT}/launcher.log"
mkdir -p "${HOME}" "${XDG_CONFIG_HOME}" "${XDG_DATA_HOME}" "${XDG_CACHE_HOME}"

cpu_index=1
while [ "${cpu_index}" -le 3 ]; do
  online_path="/sys/devices/system/cpu/cpu${cpu_index}/online"
  [ -w "${online_path}" ] && printf '1\n' >"${online_path}" 2>/dev/null || true
  cpu_index=$((cpu_index + 1))
done

cpu_policy=${PLUMOS_STANDALONE_CPU_POLICY:-ondemand}
case "${cpu_policy}" in
  interactive|performance|ondemand|schedutil|conservative)
    for cpufreq in /sys/devices/system/cpu/cpufreq/policy*; do
      [ -w "${cpufreq}/scaling_governor" ] || continue
      cpu_min=$(cat "${cpufreq}/cpuinfo_min_freq" 2>/dev/null || true)
      cpu_max=$(cat "${cpufreq}/cpuinfo_max_freq" 2>/dev/null || true)
      [ -z "${cpu_min}" ] || printf '%s\n' "${cpu_min}" >"${cpufreq}/scaling_min_freq" 2>/dev/null || true
      [ -z "${cpu_max}" ] || printf '%s\n' "${cpu_max}" >"${cpufreq}/scaling_max_freq" 2>/dev/null || true
      grep -qw "${cpu_policy}" "${cpufreq}/scaling_available_governors" 2>/dev/null || continue
      printf '%s\n' "${cpu_policy}" >"${cpufreq}/scaling_governor" 2>/dev/null || true
    done
    ;;
esac

openbor_workdir=
dosbox_workdir=
case "${id}" in
  ppsspp)
    exe="${EMU_ROOT}/ppsspp/bin/PPSSPPSDL"
    workdir="${EMU_ROOT}/ppsspp"
    ppsspp_factory_dir="${PLUMOS_ROOT}/factory-defaults/sa/state/standalone/ppsspp/config/ppsspp/PSP/SYSTEM"
    ppsspp_config_dir="${XDG_CONFIG_HOME}/ppsspp/PSP/SYSTEM"
    ppsspp_config="${ppsspp_config_dir}/ppsspp.ini"
    if [ ! -f "${ppsspp_config}" ]; then
      for ppsspp_name in controls.ini ppsspp.ini; do
        if [ ! -f "${ppsspp_factory_dir}/${ppsspp_name}" ]; then
          echo "plumos-standalone-launch: PPSSPP factory config missing: ${ppsspp_factory_dir}/${ppsspp_name}" >&2
          exit 78
        fi
      done
      mkdir -p "${ppsspp_config_dir}"
      for ppsspp_name in controls.ini ppsspp.ini; do
        ppsspp_config_tmp="${ppsspp_config_dir}/${ppsspp_name}.tmp.$$"
        if ! cp "${ppsspp_factory_dir}/${ppsspp_name}" "${ppsspp_config_tmp}"; then
          rm -f "${ppsspp_config_dir}/controls.ini.tmp.$$" \
            "${ppsspp_config_dir}/ppsspp.ini.tmp.$$"
          exit 78
        fi
      done
      mv -f "${ppsspp_config_dir}/controls.ini.tmp.$$" \
        "${ppsspp_config_dir}/controls.ini"
      mv -f "${ppsspp_config_dir}/ppsspp.ini.tmp.$$" "${ppsspp_config}"
    fi
    if ! pidof PPSSPPSDL >/dev/null 2>&1; then
      rm -f /dev/shm/PPSSPP_ID /run/shm/PPSSPP_ID 2>/dev/null || true
    fi
    set -- --fullscreen --graphics=gles2.0 "$@"
    ;;
  flycast)
    exe="${EMU_ROOT}/flycast/bin/flycast"
    data_dir="${XDG_DATA_HOME}/flycast/data"
    mkdir -p "${data_dir}"
    for bios in dc_boot.bin dc_flash.bin naomi.zip awbios.zip; do
      [ -f "${PLUMOS_ROOT}/bios/${bios}" ] || continue
      [ -f "${data_dir}/${bios}" ] || cp "${PLUMOS_ROOT}/bios/${bios}" "${data_dir}/${bios}"
    done
    set -- -config window:fullscreen=yes "$@"
    ;;
  mupen64plus)
    exe="${EMU_ROOT}/mupen64plus/bin/mupen64plus"
    m64_root="${EMU_ROOT}/mupen64plus"
    m64_config="${XDG_CONFIG_HOME}/mupen64plus"
    mkdir -p "${m64_config}" "${PLUMOS_ROOT}/Screenshots"
    set -- --fullscreen --resolution 640x480 \
      --corelib "${m64_root}/lib/libmupen64plus.so.2" \
      --plugindir "${m64_root}/lib/mupen64plus" \
      --datadir "${m64_root}/share/mupen64plus" \
      --configdir "${m64_config}" --sshotdir "${PLUMOS_ROOT}/Screenshots" \
      --gfx mupen64plus-video-rice.so --audio mupen64plus-audio-sdl.so \
      --input mupen64plus-input-sdl.so --rsp mupen64plus-rsp-hle.so "$@"
    ;;
  nxengine-evo)
    exe="${EMU_ROOT}/nxengine-evo/bin/nxengine-evo"
    workdir="${EMU_ROOT}/nxengine-evo"
    export SDL_RENDER_DRIVER=${SDL_RENDER_DRIVER:-software}
    set --
    ;;
  yabasanshiro)
    exe="${EMU_ROOT}/yabasanshiro/bin/yabasanshiro"
    keymap_source="${PLUMOS_ROOT}/config/standalone/yabasanshiro-keymapv2.json"
    keymap_dir="${HOME}/.yabasanshiro"
    mkdir -p "${keymap_dir}"
    if [ ! -f "${keymap_dir}/keymapv2.json" ] && [ -f "${keymap_source}" ]; then
      cp "${keymap_source}" "${keymap_dir}/keymapv2.json"
    fi
    rom=${1:-}
    [ -n "${rom}" ] || { echo "missing Saturn content path" >&2; exit 2; }
    shift
    set -- --iso "${rom}" --resolution_mode 0 --keep_aspect_rate "$@"
    for bios in \
      "${PLUMOS_ROOT}/bios/saturn_bios.bin" \
      "${PLUMOS_ROOT}/bios/sega_101.bin" \
      "${PLUMOS_ROOT}/bios/mpr-17933.bin" \
      "${PLUMOS_ROOT}/bios/saturn/mpr-17933.bin"; do
      if [ -f "${bios}" ]; then
        set -- --bios "${bios}" "$@"
        break
      fi
    done
    ;;
  scummvm)
    exe="${EMU_ROOT}/scummvm/bin/scummvm"
    content=${1:-}
    [ -n "${content}" ] || { echo "missing ScummVM content path" >&2; exit 2; }
    shift
    if [ -d "${content}" ]; then
      game_dir=${content}
    elif [ -f "${content}" ]; then
      game_dir=${content%/*}
      [ "${game_dir}" != "${content}" ] || game_dir=.
    else
      echo "missing ScummVM content: ${content}" >&2
      exit 2
    fi
    scummvm_config_dir="${XDG_CONFIG_HOME}/scummvm"
    scummvm_save_dir="${XDG_DATA_HOME}/scummvm/saves"
    scummvm_screenshot_dir="${XDG_DATA_HOME}/scummvm/screenshots"
    mkdir -p "${scummvm_config_dir}" "${scummvm_save_dir}" \
      "${scummvm_screenshot_dir}"
    set -- --config="${scummvm_config_dir}/scummvm.ini" \
      --savepath="${scummvm_save_dir}" \
      --screenshotpath="${scummvm_screenshot_dir}" \
      --themepath="${EMU_ROOT}/scummvm/share/scummvm" \
      --extrapath="${EMU_ROOT}/scummvm/share/scummvm" \
      --fullscreen --path="${game_dir}" --auto-detect
    ;;
  easyrpg)
    exe="${EMU_ROOT}/easyrpg/bin/easyrpg-player"
    project=${1:-}
    [ -n "${project}" ] || { echo "missing EasyRPG project path" >&2; exit 2; }
    shift
    case "${project}" in
      *.[lL][dD][bB])
        project_dir=${project%/*}
        [ "${project_dir}" != "${project}" ] || project_dir=.
        project=${project_dir}
        ;;
    esac
    if [ ! -d "${project}" ] && [ ! -f "${project}" ]; then
      echo "missing EasyRPG project: ${project}" >&2
      exit 2
    fi
    set -- --project-path "${project}" "$@"
    ;;
  openbor)
    exe="${EMU_ROOT}/openbor/bin/OpenBOR"
    pak=${1:-}
    [ -n "${pak}" ] || { echo "missing OpenBOR PAK path" >&2; exit 2; }
    [ -f "${pak}" ] || { echo "missing OpenBOR PAK: ${pak}" >&2; exit 2; }
    shift
    openbor_state_dir="${XDG_DATA_HOME}/openbor"
    openbor_workdir="${PLUMOS_RUNTIME_ROOT}/standalone/openbor-work.$$"
    mkdir -p "${openbor_state_dir}/Saves" "${openbor_state_dir}/Logs" \
      "${openbor_state_dir}/ScreenShots" "${openbor_workdir}/Paks"
    for openbor_dir in Saves Logs ScreenShots; do
      ln -s "${openbor_state_dir}/${openbor_dir}" \
        "${openbor_workdir}/${openbor_dir}"
    done
    pak_name=${pak##*/}
    ln -s "${pak}" "${openbor_workdir}/Paks/${pak_name}"
    workdir=${openbor_workdir}
    set --
    ;;
  pcsx_rearmed)
    exe="${EMU_ROOT}/pcsx_rearmed/bin/pcsx"
    pcsx_sdl12_dir="${EMU_ROOT}/pcsx_rearmed/lib"
    pcsx_sdl12="${pcsx_sdl12_dir}/libSDL-1.2.so.0"
    [ -f "${pcsx_sdl12}" ] || {
      echo "missing PCSX-ReARMed V90S SDL12 compatibility runtime: ${pcsx_sdl12}" >&2
      exit 127
    }
    export LD_LIBRARY_PATH="${pcsx_sdl12_dir}:${LD_LIBRARY_PATH}"
    export SDL12COMPAT_OPENGL_SCALING=0
    export SDL12COMPAT_SYNC_TO_VBLANK=0
    export SDL_RENDER_VSYNC=0
    export ALSA_NAME=plumos_hotplug
    export PLUMOS_PCSX_AUDIO_INPUT_RATE=44100
    export PLUMOS_PCSX_REQUIRE_ALSA=1
    pcsx_bios_dir="${HOME}/.pcsx/bios"
    mkdir -p "${pcsx_bios_dir}"
    for bios in psxonpsp660.bin scph5500.bin scph5501.bin scph5502.bin \
      scph1000.bin SCPH1001.BIN; do
      if [ -f "${PLUMOS_ROOT}/bios/${bios}" ]; then
        ln -sf "${PLUMOS_ROOT}/bios/${bios}" "${pcsx_bios_dir}/plumos-default.bin"
        break
      fi
    done
    rom=${1:-}
    [ -n "${rom}" ] || { echo "missing PlayStation content path" >&2; exit 2; }
    shift
    set -- -cdfile "${rom}" "$@"
    ;;
  *) echo "unknown standalone emulator: ${id}" >&2; exit 2 ;;
esac
[ -x "${exe}" ] || { echo "missing standalone emulator: ${exe}" >&2; exit 127; }
PID_ROOT="${PLUMOS_RUNTIME_ROOT}/standalone"
pid_file="${PID_ROOT}/${id}.pid"
exe_file="${PID_ROOT}/${id}.exe"
mkdir -p "${PID_ROOT}"
if [ -f "${pid_file}" ] && [ -f "${exe_file}" ]; then
  old_pid=$(cat "${pid_file}" 2>/dev/null || true)
  old_exe=$(cat "${exe_file}" 2>/dev/null || true)
  if [ -n "${old_pid}" ] && [ -r "/proc/${old_pid}/exe" ] &&
     [ "$(readlink "/proc/${old_pid}/exe" 2>/dev/null || true)" = "${old_exe}" ]; then
    echo "standalone emulator already running: ${id} pid=${old_pid}" >&2
    exit 75
  fi
fi
rm -f "${pid_file}" "${exe_file}"

child_pid=
hotkey_pid=
cleanup_pid_records() {
  if [ -n "${hotkey_pid}" ]; then
    kill "${hotkey_pid}" 2>/dev/null || true
    wait "${hotkey_pid}" 2>/dev/null || true
    hotkey_pid=
  fi
  recorded_pid=$(cat "${pid_file}" 2>/dev/null || true)
  if [ -n "${child_pid}" ] && [ "${recorded_pid}" = "${child_pid}" ]; then
    rm -f "${pid_file}" "${exe_file}"
  fi
  if [ -n "${openbor_workdir}" ]; then
    find "${openbor_workdir}" -mindepth 1 -maxdepth 2 -type l -delete \
      2>/dev/null || true
    rmdir "${openbor_workdir}/Paks" "${openbor_workdir}" 2>/dev/null || true
  fi
  if [ -n "${dosbox_workdir}" ]; then
    rm -rf "${dosbox_workdir}" 2>/dev/null || true
  fi
}
trap cleanup_pid_records EXIT

cd "${workdir:-$(dirname "${exe}")}" || exit 1
"${exe}" "$@" >>"${LOG_ROOT}/${id}.log" 2>&1 &
child_pid=$!
printf '%s\n' "${child_pid}" >"${pid_file}"
printf '%s\n' "${exe}" >"${exe_file}"
if [ "${id}" = mupen64plus ]; then
  hotkey_helper="${EMU_ROOT}/mupen64plus/bin/plumos-mupen64plus-hotkey"
  if [ -x "${hotkey_helper}" ]; then
    "${hotkey_helper}" "${child_pid}" "${exe}" >>"${LOG_ROOT}/${id}.log" 2>&1 &
    hotkey_pid=$!
  fi
fi
wait "${child_pid}"
rc=$?
exit "${rc}"
EOF
  chmod 0755 "${OUT_DIR}/bin/plumos-standalone-launch"

  cat >"${OUT_DIR}/bin/plumos-standalone-stop" <<'EOF'
#!/bin/sh
set -u
PLUMOS_ROOT=${PLUMOS_ROOT:-/mnt/plumos}
PLUMOS_RUNTIME_ROOT=${PLUMOS_RUNTIME_ROOT:-/run/plumos}
id=${1:-}
[ -n "${id}" ] || { echo "usage: plumos-standalone-stop EMULATOR_ID" >&2; exit 2; }
case "${id}" in
  *[!A-Za-z0-9_.-]*) echo "invalid emulator ID: ${id}" >&2; exit 2 ;;
esac
PID_ROOT="${PLUMOS_RUNTIME_ROOT}/standalone"
pid_file="${PID_ROOT}/${id}.pid"
exe_file="${PID_ROOT}/${id}.exe"
pid=$(cat "${pid_file}" 2>/dev/null || true)
expected_exe=$(cat "${exe_file}" 2>/dev/null || true)
case "${expected_exe}" in
  "${PLUMOS_ROOT}/standalone/${id}/"*) ;;
  *) echo "standalone stop refused: invalid executable record for ${id}" >&2; exit 1 ;;
esac
if [ -z "${pid}" ] || [ ! -r "/proc/${pid}/exe" ]; then
  rm -f "${pid_file}" "${exe_file}"
  echo "standalone not running: ${id}"
  exit 0
fi
if [ "$(readlink "/proc/${pid}/exe" 2>/dev/null || true)" != "${expected_exe}" ]; then
  echo "standalone stop refused: pid ${pid} ownership mismatch" >&2
  exit 1
fi
echo "standalone stop: TERM id=${id} pid=${pid}"
kill -TERM "${pid}"
tries=0
while [ "${tries}" -lt 3 ] && [ -r "/proc/${pid}/exe" ]; do
  sleep 1
  tries=$((tries + 1))
done
if [ -r "/proc/${pid}/exe" ] &&
   [ "$(readlink "/proc/${pid}/exe" 2>/dev/null || true)" = "${expected_exe}" ]; then
  echo "standalone stop: KILL id=${id} pid=${pid}"
  kill -KILL "${pid}"
fi
rm -f "${pid_file}" "${exe_file}"
EOF
  chmod 0755 "${OUT_DIR}/bin/plumos-standalone-stop"

  cat >"${OUT_DIR}/config/standalone/yabasanshiro-keymapv2.json" <<'EOF'
{
  "player1": {
    "DeviceID": 0,
    "padmode": 0,
    "deviceGUID": "1900c50a330100009011000000000000",
    "deviceName": "adc_gamepad"
  },
  "0_adc_gamepad_1900c50a330100009011000000000000": {
    "up": {"type": "hat", "id": 0, "value": 1},
    "right": {"type": "hat", "id": 0, "value": 2},
    "down": {"type": "hat", "id": 0, "value": 4},
    "left": {"type": "hat", "id": 0, "value": 8},
    "a": {"type": "button", "id": 3, "value": 1},
    "b": {"type": "button", "id": 1, "value": 1},
    "c": {"type": "button", "id": 0, "value": 1},
    "x": {"type": "button", "id": 2, "value": 1},
    "y": {"type": "button", "id": 4, "value": 1},
    "z": {"type": "button", "id": 5, "value": 1},
    "l": {"type": "button", "id": 6, "value": 1},
    "r": {"type": "button", "id": 7, "value": 1},
    "select": {"type": "button", "id": 8, "value": 1},
    "start": {"type": "button", "id": 9, "value": 1}
  }
}
EOF
}

build_one() {
  local id=$1 repo=$2 ref=$3 func=$4 log src commit
  log="${LOG_DIR}/${id}.log"
  src="${SRC_ROOT}/${id}"
  if ! selected "${id}"; then
    append_manifest "${id}: status=skipped reason=filtered"
    SKIPPED_COUNT=$((SKIPPED_COUNT + 1)); return 0
  fi
  append_manifest "${id}:"
  append_manifest "  repo=${repo}"
  append_manifest "  ref=${ref}"
  : >"${log}"
  if ! clone_repo "${id}" "${repo}" "${ref}" "${log}"; then
    append_manifest "  status=failed phase=clone log=logs/${id}.log"
    FAILED_COUNT=$((FAILED_COUNT + 1)); return 0
  fi
  commit=$(git -C "${src}" rev-parse --short=12 HEAD 2>/dev/null || echo unknown)
  append_manifest "  commit=${commit}"
  msg "building ${id}"
  if "${func}" "${src}" >>"${log}" 2>&1; then
    stage_license "${id}" "${src}"
    append_manifest "  status=built"
    BUILT_COUNT=$((BUILT_COUNT + 1)); msg "built ${id}"
  else
    append_manifest "  status=failed phase=build log=logs/${id}.log"
    FAILED_COUNT=$((FAILED_COUNT + 1)); msg "failed ${id}; see ${log}"
  fi
}

ROOT_DIR=$(cd "${ROOT_DIR}" && pwd)
validate_filter || exit $?
BUILD_ROOT=$(mkdir -p "${BUILD_ROOT}" && cd "${BUILD_ROOT}" && pwd)
OUT_PARENT=$(dirname "${OUT_DIR}")
mkdir -p "${OUT_PARENT}"
OUT_PARENT=$(cd "${OUT_PARENT}" && pwd)
OUT_DIR="${OUT_PARENT}/$(basename "${OUT_DIR}")"
SRC_ROOT="${BUILD_ROOT}/src"
case "${PLUMOS_STANDALONE_FILTER}" in
  all|ALL) rm -rf "${OUT_DIR}" ;;
esac
mkdir -p "${OUT_DIR}/logs" "${OUT_DIR}/licenses" "${SRC_ROOT}"
MANIFEST="${OUT_DIR}/standalone-emulators.manifest"
LOG_DIR="${OUT_DIR}/logs"
mkdir -p "${OUT_DIR}/config/standalone"
SONAME_MAP="${OUT_DIR}/config/standalone/soname-links.tsv"
case "${PLUMOS_STANDALONE_FILTER}" in
  all|ALL) : >"${SONAME_MAP}" ;;
  *) touch "${SONAME_MAP}" ;;
esac
{
  echo 'plumOS V90S standalone emulator build'
  echo "date=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo 'architecture=aarch64'
  echo 'reference=plumOS-MMF final package plus plumOS-A30 PPSSPP'
  echo "filter=${PLUMOS_STANDALONE_FILTER}"
  case "${PLUMOS_STANDALONE_FILTER}" in
    all|ALL) echo 'mode=full' ;;
    *) echo 'mode=incremental' ;;
  esac
  echo "cflags=${COMMON_CFLAGS}"
} >"${MANIFEST}"
stage_ppsspp_factory_defaults || exit 1
write_launcher
build_one ppsspp "${PPSSPP_REPO}" "${PPSSPP_REF}" build_ppsspp
build_one scummvm "${SCUMMVM_REPO}" "${SCUMMVM_REF}" build_scummvm
build_one easyrpg "${EASYRPG_REPO}" "${EASYRPG_REF}" build_easyrpg
build_one openbor "${OPENBOR_REPO}" "${OPENBOR_REF}" build_openbor
build_one pcsx_rearmed "${PCSX_REARMED_REPO}" "${PCSX_REARMED_REF}" build_pcsx_rearmed
build_one flycast "${FLYCAST_REPO}" "${FLYCAST_REF}" build_flycast
build_one mupen64plus "${MUPEN64PLUS_UI_REPO}" "${MUPEN64PLUS_REF}" build_mupen64plus
build_one nxengine-evo "${NXENGINE_EVO_REPO}" "${NXENGINE_EVO_REF}" build_nxengine_evo
build_one yabasanshiro "${YABASANSHIRO_REPO}" "${YABASANSHIRO_REF}" build_yabasanshiro
{
  echo 'summary:'
  echo "  built=${BUILT_COUNT}"
  echo "  failed=${FAILED_COUNT}"
  echo "  skipped=${SKIPPED_COUNT}"
} >>"${MANIFEST}"
(
  cd "${OUT_DIR}" || exit 1
  find . -type f ! -name checksums.sha256 -print0 | sort -z | xargs -0 sha256sum >checksums.sha256
)
msg "done: built=${BUILT_COUNT} failed=${FAILED_COUNT} skipped=${SKIPPED_COUNT}"
if [ "${FAILED_COUNT}" -gt 0 ] && [ "${FAIL_ON_STANDALONE_ERROR}" = 1 ]; then exit 1; fi
