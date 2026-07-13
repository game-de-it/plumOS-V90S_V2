#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
HOST="${PLUMOS_V90S_SSH_HOST:-root@192.0.2.120}"
CONTROL_PATH="${PLUMOS_V90S_SSH_CONTROL_PATH:-/tmp/v90s-ssh-master}"
WAIT_SECONDS="${PLUMOS_V90S_CORE_SMOKE_WAIT:-6}"
STARTUP_TIMEOUT="${PLUMOS_V90S_CORE_SMOKE_STARTUP_TIMEOUT:-30}"
CORE_FILTER="${PLUMOS_V90S_CORE_SMOKE_FILTER:-}"
TEST_ID="${PLUMOS_V90S_CORE_SMOKE_ID:-$(date '+%Y%m%d-%H%M%S')}"
OUT_DIR="${PLUMOS_V90S_CORE_SMOKE_OUT:-$ROOT_DIR/output/validation/v90s-fe-core-smoke-$TEST_ID}"
SYSTEMS_JSON="$ROOT_DIR/package/frontend-v90s/plumos/config/frontend/systems.json"

usage() {
    cat <<'USAGE'
Usage: scripts/v90s-fe-core-smoke-test.sh [options]

Options:
  --host USER@HOST      SSH target; default root@192.0.2.120
  --control-path PATH   OpenSSH ControlMaster socket
  --wait SECONDS        Runtime observation window; default 6
  --startup-timeout N   Maximum seconds to wait for RetroArch; default 30
  --cores LIST          Test only comma-separated core names
  --out-dir PATH        Host result directory

The test uses only frontend-declared RetroArch profiles for systems which have
indexed ROMs. It stops the frontend once, launches every reachable unique core
through plumOS text UI, stops RetroArch through its PID-aware helper, and
restores exactly one frontend process when the run finishes.
USAGE
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --host)
            HOST="$2"
            shift 2
            ;;
        --control-path)
            CONTROL_PATH="$2"
            shift 2
            ;;
        --wait)
            WAIT_SECONDS="$2"
            shift 2
            ;;
        --startup-timeout)
            STARTUP_TIMEOUT="$2"
            shift 2
            ;;
        --cores)
            CORE_FILTER="$2"
            shift 2
            ;;
        --out-dir)
            OUT_DIR="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
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

for tool in jq ssh awk sort; do
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
DEVICE_CORES="$OUT_DIR/device-cores.txt"
PLAN="$OUT_DIR/plan.tsv"
SUMMARY="$OUT_DIR/summary.tsv"
REMOTE_ROOT="/tmp/plumos-fe-core-smoke-$TEST_ID"

ssh_opts=(-o BatchMode=yes -o ConnectTimeout=8)
if [ -S "$CONTROL_PATH" ]; then
    ssh_opts+=(-S "$CONTROL_PATH" -o ControlMaster=no)
fi

remote() {
    ssh "${ssh_opts[@]}" "$HOST" "$@"
}

remote 'cat /mnt/plumos/state/frontend/library-index.json' > "$LIBRARY_JSON"
remote 'find /mnt/plumos/cores -maxdepth 1 -type f -name "*_libretro.so" -exec basename {} _libretro.so \; | sort' > "$DEVICE_CORES"

jq -nr \
    --slurpfile defs "$SYSTEMS_JSON" \
    --slurpfile library "$LIBRARY_JSON" '
    def preferred_rom:
      if .id == "gb" then
        ([.roms[] | select(.relative_path | endswith("/ARETHA.gb") | not)][0] // .roms[0])
      elif .id == "cavestory" then
        ([.roms[] | select(.relative_path | endswith("/Doukutsu.exe"))][0] // .roms[0])
      elif .id == "lutro" then
        ([.roms[] | select(.relative_path | ascii_downcase | endswith("/main.lua"))][0] // .roms[0])
      elif .id == "neogeocd" then
        ([.roms[] | select(.relative_path | contains("Fatal Fury WAV"))][0] // .roms[0])
      elif .id == "n64" then
        ([.roms[] | select(.relative_path | ascii_downcase | endswith("/supermario64.z64"))][0] // .roms[0])
      elif .id == "pcfx" then
        ([.roms[] | select(.relative_path | ascii_downcase | endswith(".cue"))][0] // .roms[0])
      else .roms[0]
      end;
    ($library[0].systems
      | map(select(.rom_count > 0))
      | map({key: .id, value: preferred_rom})
      | from_entries) as $roms
    | $defs[0].systems[]
    | select($roms[.id] != null)
    | .id as $system
    | .launch_profiles[]?
    | select(startswith("retroarch:"))
    | (sub("^retroarch:"; "")) as $core
    | [$core, $system, ("retroarch:" + $core), $roms[$system].relative_path]
    | @tsv
  ' | sort -t $'\t' -k1,1 -u > "$PLAN"

if [ -n "$CORE_FILTER" ]; then
    awk -F'\t' -v filter=",$CORE_FILTER," '
      index(filter, "," $1 ",") { print }
    ' "$PLAN" > "$PLAN.filtered"
    mv "$PLAN.filtered" "$PLAN"
fi

{
    printf 'device_cores=%s\n' "$(wc -l < "$DEVICE_CORES" | tr -d ' ')"
    printf 'planned_cores=%s\n' "$(wc -l < "$PLAN" | tr -d ' ')"
    printf 'unplanned_cores=%s\n' "$(comm -23 "$DEVICE_CORES" <(cut -f1 "$PLAN" | sort -u) | wc -l | tr -d ' ')"
    printf 'test_id=%s\n' "$TEST_ID"
    printf 'wait_seconds=%s\n' "$WAIT_SECONDS"
    printf 'startup_timeout=%s\n' "$STARTUP_TIMEOUT"
} > "$OUT_DIR/coverage.txt"
comm -23 "$DEVICE_CORES" <(cut -f1 "$PLAN" | sort -u) > "$OUT_DIR/unplanned-cores.txt"

remote "rm -rf '$REMOTE_ROOT'; mkdir -p '$REMOTE_ROOT/cases'; cat > '$REMOTE_ROOT/plan.tsv'" < "$PLAN"

remote "PLUMOS_TEST_ROOT='$REMOTE_ROOT' PLUMOS_WAIT_SECONDS='$WAIT_SECONDS' PLUMOS_STARTUP_TIMEOUT='$STARTUP_TIMEOUT' sh -s" <<'REMOTE_SCRIPT'
set -u

ROOT=$PLUMOS_TEST_ROOT
WAIT_SECONDS=$PLUMOS_WAIT_SECONDS
STARTUP_TIMEOUT=$PLUMOS_STARTUP_TIMEOUT
SUMMARY=$ROOT/summary.tsv
RUN_DIR=/run/plumos-v90s
FRONTEND_STOP=/mnt/plumos/bin/plumos-frontend-stop
FRONTEND_LAUNCH=/mnt/plumos/bin/plumos-frontend-launch
RETROARCH_STOP=/mnt/plumos/bin/v90s-retroarch-stop
TEXT_UI=/mnt/plumos/bin/plumos-text-ui

restore_runtime() {
    set +e
    "$RETROARCH_STOP" >"$ROOT/final-retroarch-stop.log" 2>&1
    "$FRONTEND_STOP" >"$ROOT/final-frontend-stop.log" 2>&1
    nohup "$FRONTEND_LAUNCH" >"/mnt/plumos/Logs/frontend-core-smoke.log" 2>&1 &
    sleep 3
}
trap restore_runtime EXIT HUP INT TERM

: > "$SUMMARY"
printf 'core\tsystem\tprofile\trom\tstatus\truntime_pid\tframebuffer_sha256\tdetail\n' >> "$SUMMARY"
"$FRONTEND_STOP" >"$ROOT/frontend-stop.log" 2>&1 || true
sleep 2

while IFS="	" read -r core system profile rom; do
    [ -n "$core" ] || continue
    case_dir="$ROOT/cases/$core"
    mkdir -p "$case_dir"
    rm -f "$RUN_DIR/retroarch.pid" "$RUN_DIR/retroarch-launch.pid"

    "$TEXT_UI" launch "$system" "$rom" --profile "$profile" --no-scan \
        >"$case_dir/preflight.log" 2>&1
    if ! grep -q '^can_execute: yes$' "$case_dir/preflight.log"; then
        detail=$(sed -n 's/^reason: //p' "$case_dir/preflight.log" | head -n 1 | tr '\t' ' ')
        printf '%s\t%s\t%s\t%s\tPREFLIGHT_FAIL\t\t\t%s\n' \
            "$core" "$system" "$profile" "$rom" "${detail:-preflight rejected}" >> "$SUMMARY"
        continue
    fi

    nohup "$TEXT_UI" launch "$system" "$rom" --profile "$profile" --no-scan --execute \
        >"$case_dir/execute.log" 2>&1 &
    launcher_pid=$!
    elapsed=0
    runtime_pid=
    actual_core=
    while [ "$elapsed" -lt "$STARTUP_TIMEOUT" ]; do
        runtime_pid=$(sed -n '1p' "$RUN_DIR/retroarch.pid" 2>/dev/null | tr -d '[:space:]')
        if [ -n "$runtime_pid" ] && kill -0 "$runtime_pid" 2>/dev/null; then
            actual_core=$(tr '\000' '\n' <"/proc/$runtime_pid/cmdline" 2>/dev/null | sed -n 's#^.*/\([^/]*\)_libretro\.so$#\1#p' | head -n 1)
            break
        fi
        runtime_pid=
        kill -0 "$launcher_pid" 2>/dev/null || break
        sleep 1
        elapsed=$((elapsed + 1))
    done

    status=EXITED
    detail="RetroArch was not active after startup wait"
    framebuffer_sha=
    if [ -n "$runtime_pid" ] && kill -0 "$runtime_pid" 2>/dev/null; then
        observed=0
        while [ "$observed" -lt "$WAIT_SECONDS" ] && kill -0 "$runtime_pid" 2>/dev/null; do
            sleep 1
            observed=$((observed + 1))
        done
        if kill -0 "$runtime_pid" 2>/dev/null; then
            framebuffer_sha=$(dd if=/dev/fb0 bs=2457600 count=1 2>/dev/null | sha256sum | awk '{print $1}')
        fi
        if [ "$actual_core" = "$core" ] && kill -0 "$runtime_pid" 2>/dev/null; then
            status=RUNNING
            detail="expected core active"
        elif [ "$actual_core" = "$core" ]; then
            status=EXITED_EARLY
            detail="expected core started but exited during observation"
        else
            status=WRONG_CORE
            detail="expected=$core actual=${actual_core:-unknown}"
        fi
        cp /mnt/plumos/Logs/plumos-v90s-retroarch.log "$case_dir/retroarch.log" 2>/dev/null || true
    else
        "$RETROARCH_STOP" >"$case_dir/startup-timeout-stop.log" 2>&1 || true
        wait "$launcher_pid" 2>/dev/null || true
        cp /mnt/plumos/Logs/plumos-v90s-retroarch.log "$case_dir/retroarch.log" 2>/dev/null || true
        error=$(grep -E '\[ERROR\]|error:|failed|Failed' "$case_dir/retroarch.log" "$case_dir/execute.log" 2>/dev/null | tail -n 1 | tr '\t' ' ')
        [ -n "$error" ] && detail=$error
    fi

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$core" "$system" "$profile" "$rom" "$status" "${runtime_pid:-}" \
        "$framebuffer_sha" "$detail" >> "$SUMMARY"

    "$RETROARCH_STOP" >"$case_dir/stop.log" 2>&1 || true
    sleep 2
done < "$ROOT/plan.tsv"

trap - EXIT HUP INT TERM
restore_runtime
printf 'frontend_count=%s\n' "$(ps | grep plumos-controll | grep -v grep | wc -l)" > "$ROOT/final-state.txt"
printf 'retroarch_count=%s\n' "$(ps | grep retroarch | grep -v grep | wc -l)" >> "$ROOT/final-state.txt"
REMOTE_SCRIPT

remote "cat '$REMOTE_ROOT/summary.tsv'" > "$SUMMARY"
remote "cat '$REMOTE_ROOT/final-state.txt'" > "$OUT_DIR/final-state.txt"
remote "cd '$REMOTE_ROOT' && tar -cf - cases frontend-stop.log final-retroarch-stop.log final-frontend-stop.log" \
    | tar -xf - -C "$OUT_DIR"

awk -F'\t' 'NR > 1 {count[$5]++} END {for (status in count) print status "=" count[status]}' \
    "$SUMMARY" | sort > "$OUT_DIR/result-counts.txt"

cat "$OUT_DIR/coverage.txt"
cat "$OUT_DIR/result-counts.txt"
cat "$OUT_DIR/final-state.txt"
printf 'results=%s\n' "$OUT_DIR"
