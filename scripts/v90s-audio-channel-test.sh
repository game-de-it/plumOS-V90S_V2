#!/bin/sh
set -eu

ADB="${ADB:-adb}"
SERIAL="${PLUMOS_ADB_SERIAL:-}"
MODE=managed
REMOTE_WAV="${PLUMOS_AUDIO_TEST_REMOTE_WAV:-/run/plumos/audio-channel-test.wav}"

usage() {
  cat <<'EOF'
Usage: scripts/v90s-audio-channel-test.sh [--raw] [--serial SERIAL]

Plays a stereo identification pattern on a connected V90S:
  left:  one continuous 660 Hz tone
  right: six short 880 Hz tones

The default managed test uses plumOS output routing. --raw bypasses the route
and opens hw:0,0 directly for diagnosis.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --raw) MODE=raw ;;
    --serial)
      [ "$#" -ge 2 ] || { usage >&2; exit 2; }
      SERIAL=$2
      shift
      ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
  shift
done

command -v "$ADB" >/dev/null 2>&1 || {
  echo "error: adb not found: $ADB" >&2
  exit 127
}
command -v ffmpeg >/dev/null 2>&1 || {
  echo "error: ffmpeg is required to generate the channel test" >&2
  exit 127
}

set -- "$ADB"
[ -z "$SERIAL" ] || set -- "$@" -s "$SERIAL"

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/plumos-audio-test.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT HUP INT TERM
wav="$tmp_dir/plumos-v90s-lr-test.wav"

ffmpeg -hide_banner -loglevel error -y \
  -f lavfi -i "aevalsrc=if(between(t\,2\,5)\,0.28*sin(2*PI*660*t)\,0)|if(lt(mod(t-6.2\,0.5)\,0.18)*between(t\,6.2\,9.18)\,0.28*sin(2*PI*880*t)\,0):s=48000:d=10.2" \
  -c:a pcm_s16le "$wav"

"$@" push "$wav" "$REMOTE_WAV" >/dev/null
echo "Playing left continuous tone, then right short tones (mode=$MODE)."
if [ "$MODE" = raw ]; then
  "$@" shell "aplay -q -D hw:0,0 '$REMOTE_WAV'"
else
  "$@" shell "/mnt/plumos/bin/plumos-audio-output prepare && ALSA_CONFIG_PATH=/run/plumos/audio/asound.conf ALSA_PLUGIN_DIR=/mnt/plumos/lib/alsa-lib aplay -q -D plumos_output '$REMOTE_WAV'"
fi
