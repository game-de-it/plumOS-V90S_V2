#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
HOST="${PLUMOS_V90S_SSH_HOST:-root@192.0.2.120}"
CONTROL_PATH="${PLUMOS_V90S_SSH_CONTROL_PATH:-/tmp/v90s-ssh-master}"
WAIT_SECONDS="${PLUMOS_V90S_PICO_SMOKE_WAIT:-4}"
STARTUP_TIMEOUT="${PLUMOS_V90S_PICO_SMOKE_STARTUP_TIMEOUT:-20}"
PROFILE_FILTER="${PLUMOS_V90S_PICO_SMOKE_FILTER:-}"
TEST_ID="${PLUMOS_V90S_PICO_SMOKE_ID:-$(date '+%Y%m%d-%H%M%S')}"
OUT_DIR="${PLUMOS_V90S_PICO_SMOKE_OUT:-$ROOT_DIR/output/validation/v90s-fe-pico-smoke-$TEST_ID}"
SYSTEMS_JSON="$ROOT_DIR/package/frontend-v90s/plumos/config/frontend/systems.json"

usage() {
    cat <<'USAGE'
Usage: scripts/v90s-fe-pico-smoke-test.sh [options]

Options:
  --host USER@HOST      SSH target; default root@192.0.2.120
  --control-path PATH   OpenSSH ControlMaster socket
  --wait SECONDS        Runtime observation window; default 4
  --startup-timeout N   Maximum seconds to wait for PicoArch; default 20
  --profiles LIST       Test only comma-separated picoarch core IDs
  --out-dir PATH        Host result directory

The test derives the same PicoArch companion profiles as the frontend, keeps
only systems with indexed ROMs, launches every route through plumOS text UI,
stops PicoArch through its PID-aware helper, and restores one frontend process.
USAGE
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --host) HOST="$2"; shift 2 ;;
        --control-path) CONTROL_PATH="$2"; shift 2 ;;
        --wait) WAIT_SECONDS="$2"; shift 2 ;;
        --startup-timeout) STARTUP_TIMEOUT="$2"; shift 2 ;;
        --profiles) PROFILE_FILTER="$2"; shift 2 ;;
        --out-dir) OUT_DIR="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *)
            printf 'error: unknown option: %s\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

case "$WAIT_SECONDS:$STARTUP_TIMEOUT" in
    ''|*[!0-9:]*)
        printf 'error: wait values must be positive integers\n' >&2
        exit 2
        ;;
esac
[ "$WAIT_SECONDS" -gt 0 ] && [ "$STARTUP_TIMEOUT" -gt 0 ] || {
    printf 'error: wait values must be positive integers\n' >&2
    exit 2
}

for tool in jq ssh awk sort tar; do
    command -v "$tool" >/dev/null 2>&1 || {
        printf 'error: required host tool is missing: %s\n' "$tool" >&2
        exit 127
    }
done
[ -r "$SYSTEMS_JSON" ] || {
    printf 'error: systems definition not found: %s\n' "$SYSTEMS_JSON" >&2
    exit 2
}

mkdir -p "$OUT_DIR"
LIBRARY_JSON="$OUT_DIR/library-index.json"
CANDIDATES="$OUT_DIR/candidates.tsv"
SUMMARY="$OUT_DIR/summary.tsv"
REMOTE_ROOT="/tmp/plumos-fe-pico-smoke-$TEST_ID"

ssh_opts=(-o BatchMode=yes -o ConnectTimeout=8)
if [ -S "$CONTROL_PATH" ]; then
    ssh_opts+=(-S "$CONTROL_PATH" -o ControlMaster=no)
fi

remote() {
    ssh "${ssh_opts[@]}" "$HOST" "$@"
}

remote 'cat /mnt/plumos/state/frontend/library-index.json' > "$LIBRARY_JSON"

jq -nr \
    --slurpfile defs "$SYSTEMS_JSON" \
    --slurpfile library "$LIBRARY_JSON" '
    def preferred_rom:
      if .id == "amiga" then
        ([.roms[] | select(.relative_path | contains("Baby Jo"))][0] // .roms[0])
      elif .id == "gb" then
        ([.roms[] | select(.relative_path | endswith("/Super Mario Land [V1.1].gb"))][0]
          // [.roms[] | select(.relative_path | endswith("/ARETHA.gb") | not)][0]
          // .roms[0])
      elif .id == "cavestory" then
        ([.roms[] | select(.relative_path | ascii_downcase | endswith("/doukutsu.exe"))][0] // .roms[0])
      elif .id == "lutro" then
        ([.roms[] | select(.relative_path | ascii_downcase | endswith("/main.lua"))][0] // .roms[0])
      elif .id == "neogeocd" then
        ([.roms[] | select(.relative_path | contains("Fatal Fury WAV"))][0] // .roms[0])
      elif .id == "pcfx" then
        ([.roms[] | select(.relative_path | ascii_downcase | endswith(".cue"))][0] // .roms[0])
      elif .id == "psx" then
        ([.roms[] | select(.relative_path | ascii_downcase | endswith(".cue"))][0] // .roms[0])
      else .roms[0]
      end;
    def pico_allowed($system; $core):
      $system != "n64" and $system != "saturn" and
      $core != "flycast" and $core != "flycast_xtreme" and
      $core != "frodo" and $core != "chailove";
    def frontend_profiles($system; $profiles):
      ($profiles[0:16]) as $original
      | reduce $original[] as $profile
          ({profiles: $original};
           if (.profiles | length) >= 16 or
              ($profile | startswith("retroarch:") | not) then .
           else ($profile | sub("^retroarch:"; "")) as $core
           | ("picoarch:" + $core) as $pico
           | if pico_allowed($system; $core) and
                ((.profiles | index($pico)) == null)
             then .profiles += [$pico]
             else .
             end
           end)
      | .profiles;
    ($library[0].systems
      | map(select(.rom_count > 0))
      | map({key: .id, value: preferred_rom})
      | from_entries) as $roms
    | $defs[0].systems[]
    | select($roms[.id] != null)
    | . as $system
    | frontend_profiles($system.id; ($system.launch_profiles // []))[]
    | select(startswith("picoarch:"))
    | (sub("^picoarch:"; "")) as $core
    | [$core, $system.id, ("picoarch:" + $core), $roms[$system.id].relative_path]
    | @tsv
  ' | sort -t $'\t' -k2,2 -k1,1 -u > "$CANDIDATES"

if [ -n "$PROFILE_FILTER" ]; then
    awk -F'\t' -v filter=",$PROFILE_FILTER," '
      index(filter, "," $1 ",") { print }
    ' "$CANDIDATES" > "$CANDIDATES.filtered"
    mv "$CANDIDATES.filtered" "$CANDIDATES"
fi

{
    printf 'candidate_routes=%s\n' "$(wc -l < "$CANDIDATES" | tr -d ' ')"
    printf 'candidate_systems=%s\n' "$(cut -f2 "$CANDIDATES" | sort -u | wc -l | tr -d ' ')"
    printf 'candidate_cores=%s\n' "$(cut -f1 "$CANDIDATES" | sort -u | wc -l | tr -d ' ')"
    printf 'test_id=%s\n' "$TEST_ID"
    printf 'wait_seconds=%s\n' "$WAIT_SECONDS"
    printf 'startup_timeout=%s\n' "$STARTUP_TIMEOUT"
} > "$OUT_DIR/coverage.txt"

remote "rm -rf '$REMOTE_ROOT'; mkdir -p '$REMOTE_ROOT/cases'; cat > '$REMOTE_ROOT/candidates.tsv'" < "$CANDIDATES"

remote "PLUMOS_TEST_ROOT='$REMOTE_ROOT' PLUMOS_WAIT_SECONDS='$WAIT_SECONDS' PLUMOS_STARTUP_TIMEOUT='$STARTUP_TIMEOUT' sh -s" <<'REMOTE_SCRIPT'
set -u

ROOT=$PLUMOS_TEST_ROOT
WAIT_SECONDS=$PLUMOS_WAIT_SECONDS
STARTUP_TIMEOUT=$PLUMOS_STARTUP_TIMEOUT
SUMMARY=$ROOT/summary.tsv
RUN_DIR=/mnt/plumos/state/picoarch
FRONTEND_STOP=/mnt/plumos/bin/plumos-frontend-stop
FRONTEND_LAUNCH=/mnt/plumos/bin/plumos-frontend-launch
PICOARCH_STOP=/mnt/plumos/bin/plumos-picoarch-stop
TEXT_UI=/mnt/plumos/bin/plumos-text-ui

restore_runtime() {
    set +e
    "$PICOARCH_STOP" >"$ROOT/final-picoarch-stop.log" 2>&1
    "$FRONTEND_STOP" >"$ROOT/final-frontend-stop.log" 2>&1
    nohup "$FRONTEND_LAUNCH" >"/mnt/plumos/Logs/frontend-pico-smoke.log" 2>&1 &
    sleep 3
}
trap restore_runtime EXIT HUP INT TERM

pid_running() {
    pid=$1
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null &&
        [ "$(awk '{print $3}' "/proc/$pid/stat" 2>/dev/null)" != Z ]
}

: > "$SUMMARY"
printf 'core\tsystem\tprofile\trom\tstatus\truntime_pid\tframebuffer_sha256\tframe_changed\tdetail\n' >> "$SUMMARY"
"$FRONTEND_STOP" >"$ROOT/frontend-stop.log" 2>&1 || true
sleep 2
zero_sha=$(dd if=/dev/zero bs=2457600 count=1 2>/dev/null | sha256sum | awk '{print $1}')

while IFS="	" read -r core system profile rom; do
    [ -n "$core" ] || continue
    case_dir="$ROOT/cases/${system}__${core}"
    mkdir -p "$case_dir"
    rm -f "$RUN_DIR/runtime.pid"

    "$TEXT_UI" launch "$system" "$rom" --profile "$profile" --no-scan \
        >"$case_dir/preflight.log" 2>&1
    if ! grep -q '^can_execute: yes$' "$case_dir/preflight.log"; then
        detail=$(sed -n 's/^reason: //p' "$case_dir/preflight.log" | head -n 1 | tr '\t' ' ')
        printf '%s\t%s\t%s\t%s\tPREFLIGHT_FAIL\t\t\t\t%s\n' \
            "$core" "$system" "$profile" "$rom" "${detail:-preflight rejected}" >> "$SUMMARY"
        continue
    fi

    dd if=/dev/zero of=/dev/fb0 bs=2457600 count=1 2>/dev/null || true
    log_file="/mnt/plumos/Logs/picoarch/${system}-${core}.log"
    if [ -r "$log_file" ]; then
        log_lines=$(wc -l < "$log_file")
    else
        log_lines=0
    fi

    nohup "$TEXT_UI" launch "$system" "$rom" --profile "$profile" --no-scan --execute \
        >"$case_dir/execute.log" 2>&1 &
    launcher_pid=$!
    elapsed=0
    runtime_pid=
    actual_core=
    while [ "$elapsed" -lt "$STARTUP_TIMEOUT" ]; do
        runtime_pid=$(sed -n '1p' "$RUN_DIR/runtime.pid" 2>/dev/null | tr -d '[:space:]')
        if pid_running "$runtime_pid"; then
            actual_core=$(tr '\000' '\n' <"/proc/$runtime_pid/cmdline" 2>/dev/null |
                sed -n 's#^.*/\([^/]*\)_libretro\.so$#\1#p' | head -n 1)
            break
        fi
        runtime_pid=
        kill -0 "$launcher_pid" 2>/dev/null || break
        sleep 1
        elapsed=$((elapsed + 1))
    done

    status=EXITED
    detail="PicoArch was not active after startup wait"
    framebuffer_sha=
    frame_changed=no
    if pid_running "$runtime_pid"; then
        observed=0
        while [ "$observed" -lt "$WAIT_SECONDS" ] && pid_running "$runtime_pid"; do
            sleep 1
            observed=$((observed + 1))
        done
        if pid_running "$runtime_pid"; then
            framebuffer_sha=$(dd if=/dev/fb0 bs=2457600 count=1 2>/dev/null | sha256sum | awk '{print $1}')
            [ "$framebuffer_sha" = "$zero_sha" ] || frame_changed=yes
        fi
        if [ "$actual_core" = "$core" ] && pid_running "$runtime_pid"; then
            status=RUNNING
            detail="expected core active"
        elif [ "$actual_core" = "$core" ]; then
            status=EXITED_EARLY
            detail="expected core started but exited during observation"
        else
            status=WRONG_CORE
            detail="expected=$core actual=${actual_core:-unknown}"
        fi
    fi

    if [ -r "$log_file" ]; then
        tail -n "+$((log_lines + 1))" "$log_file" | tail -n 240 > "$case_dir/picoarch.log"
    fi
    if [ "$status" = EXITED ]; then
        error=$(grep -E 'Segmentation fault|unsupported|ERROR|error:|failed|Failed' \
            "$case_dir/picoarch.log" "$case_dir/execute.log" 2>/dev/null | tail -n 1 | tr '\t' ' ')
        [ -n "$error" ] && detail=$error
    fi

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$core" "$system" "$profile" "$rom" "$status" "${runtime_pid:-}" \
        "$framebuffer_sha" "$frame_changed" "$detail" >> "$SUMMARY"

    "$PICOARCH_STOP" >"$case_dir/stop.log" 2>&1 || true
    wait "$launcher_pid" 2>/dev/null || true
    sleep 1
done < "$ROOT/candidates.tsv"

trap - EXIT HUP INT TERM
restore_runtime
printf 'frontend_count=%s\n' "$(ps | grep plumos-controll | grep -v grep | wc -l)" > "$ROOT/final-state.txt"
printf 'picoarch_count=%s\n' "$(ps | grep picoarch | grep -v grep | wc -l)" >> "$ROOT/final-state.txt"
printf 'picoarch_pid_file=%s\n' "$([ -e "$RUN_DIR/runtime.pid" ] && echo present || echo absent)" >> "$ROOT/final-state.txt"
REMOTE_SCRIPT

remote "cat '$REMOTE_ROOT/summary.tsv'" > "$SUMMARY"
remote "cat '$REMOTE_ROOT/final-state.txt'" > "$OUT_DIR/final-state.txt"
remote "cd '$REMOTE_ROOT' && tar -cf - cases frontend-stop.log final-picoarch-stop.log final-frontend-stop.log" \
    | tar -xf - -C "$OUT_DIR"

awk -F'\t' 'NR > 1 {count[$5]++} END {for (status in count) print status "=" count[status]}' \
    "$SUMMARY" | sort > "$OUT_DIR/result-counts.txt"

cat "$OUT_DIR/coverage.txt"
cat "$OUT_DIR/result-counts.txt"
cat "$OUT_DIR/final-state.txt"
printf 'results=%s\n' "$OUT_DIR"
