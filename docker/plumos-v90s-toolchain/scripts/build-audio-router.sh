#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=/workspace
OUT_DIR="${PLUMOS_V90S_AUDIO_ROUTER_OUT:-${ROOT_DIR}/output/audio-router/v90s}"
SOURCE="${ROOT_DIR}/package/audio-router-v90s/plumos_hotplug.c"
LICENSE="${ROOT_DIR}/package/audio-router-v90s/LICENSE"
PLUGIN_DIR="${OUT_DIR}/plumos/lib/alsa-lib"
PLUGIN="${PLUGIN_DIR}/libasound_module_pcm_plumos_hotplug.so"

rm -rf "${OUT_DIR}"
mkdir -p "${PLUGIN_DIR}" "${OUT_DIR}/licenses"

cc \
  -O3 \
  -DPIC \
  -fPIC \
  -Wall \
  -Wextra \
  -Werror \
  -shared \
  -Wl,-z,relro,-z,now \
  -o "${PLUGIN}" \
  "${SOURCE}" \
  -lasound
strip --strip-unneeded "${PLUGIN}"

install -m 0644 "${LICENSE}" "${OUT_DIR}/licenses/plumos-audio-hotplug-LICENSE"

cat > "${OUT_DIR}/audio-router.manifest" <<EOF
component=plumos-v90s-audio-router
architecture=arm64
implementation=alsa-ioplug
plugin=libasound_module_pcm_plumos_hotplug.so
logical_pcm=plumos_output
internal_route=hw:0,0-mono-mix
usb_route=first-usb-playback-card-stereo
background_processes=none
EOF

find "${OUT_DIR}" -type f ! -name checksums.sha256 -print0 | sort -z | \
  xargs -0 sha256sum | sed "s#  ${OUT_DIR}/#  #" > "${OUT_DIR}/checksums.sha256"

printf 'created: %s\n' "${OUT_DIR}"
printf 'plugin: %s\n' "${PLUGIN}"
