#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
DEFAULT_ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/../../.." && pwd)"
ROOT_DIR="${ROOT_DIR:-$DEFAULT_ROOT_DIR}"
OUT_DIR="${PLUMOS_V90S_CORES_OUT:-output/libretro-cores/v90s}"
SRC_ROOT="${PLUMOS_V90S_CORES_SRC:-output/build/libretro-cores/src}"
CORE_RECIPES="${CORE_RECIPES:-${ROOT_DIR}/docker/plumos-v90s-toolchain/libretro-core-recipes.tsv}"
CORE_INFO_REPO="${CORE_INFO_REPO:-https://github.com/libretro/libretro-core-info.git}"
CORE_INFO_REF="${CORE_INFO_REF:-HEAD}"
PLUMOS_CORE_FILTER="${PLUMOS_CORE_FILTER:-v90s}"
FAIL_ON_CORE_ERROR="${FAIL_ON_CORE_ERROR:-1}"
JOBS="${JOBS:-$(nproc 2>/dev/null || echo 2)}"
CC="${CC:-gcc}"
CXX="${CXX:-g++}"
AR="${AR:-ar}"
RANLIB="${RANLIB:-ranlib}"
STRIP="${STRIP:-strip}"
READELF="${READELF:-readelf}"

usage() {
  cat <<'EOF'
Usage:
  docker/plumos-v90s-toolchain/scripts/build-libretro-cores.sh [options]

Options:
  --out-dir PATH       Output directory; default output/libretro-cores/v90s.
  --src-root PATH      Source/build root; default output/build/libretro-cores/src.
  --recipes PATH       Recipe TSV; default docker/plumos-v90s-toolchain/libretro-core-recipes.tsv.
  --filter FILTER      v90s, plumos, class-a, class-b, all, or comma-separated core IDs.
                       Default: v90s.
  --jobs N             Per-core make jobs; default nproc.
  --fail-on-error 0|1  Fail if any selected core fails; default 1.
  --list               Print selected recipes and exit.

Environment:
  PLUMOS_CORE_FILTER   Same as --filter.
  CORE_INFO_REPO/REF   libretro-core-info source used for .info files.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --out-dir)
      OUT_DIR="$2"
      shift 2
      ;;
    --src-root)
      SRC_ROOT="$2"
      shift 2
      ;;
    --recipes)
      CORE_RECIPES="$2"
      shift 2
      ;;
    --filter)
      PLUMOS_CORE_FILTER="$2"
      shift 2
      ;;
    --jobs)
      JOBS="$2"
      shift 2
      ;;
    --fail-on-error)
      FAIL_ON_CORE_ERROR="$2"
      shift 2
      ;;
    --list)
      LIST_ONLY=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'error: unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

LIST_ONLY="${LIST_ONLY:-0}"
case "$JOBS" in
  ''|*[!0-9]*) JOBS=2 ;;
esac
[ "$JOBS" -gt 0 ] || JOBS=1

msg() {
  printf '[libretro-cores] %s\n' "$*" >&2
}

append_manifest() {
  printf '%s\n' "$*" >> "$MANIFEST"
}

core_selected() {
  local id="$1"
  local class="$2"
  local token
  local normalized

  IFS=',' read -r -a filters <<< "$PLUMOS_CORE_FILTER"
  for token in "${filters[@]}"; do
    normalized="$(printf '%s' "$token" | tr -d '[:space:]')"
    [ -n "$normalized" ] || continue
    case "$normalized" in
      all|ALL)
        return 0
        ;;
      v90s|plumos|default|class-a|Class-A|a|A)
        [ "$class" = "A" ] && return 0
        ;;
      class-b|Class-B|b|B)
        [ "$class" = "B" ] && return 0
        ;;
      class-ab|Class-AB|ab|AB)
        { [ "$class" = "A" ] || [ "$class" = "B" ]; } && return 0
        ;;
      "$id")
        return 0
        ;;
    esac
  done
  return 1
}

core_table() {
  awk '
    /^[[:space:]]*($|#)/ { next }
    { print }
  ' "$CORE_RECIPES"
}

clone_or_update_repo() {
  local id="$1"
  local repo="$2"
  local ref="$3"
  local dst="$4"
  local log="$5"

  if [ ! -d "$dst/.git" ]; then
    rm -rf "$dst"
    mkdir -p "$(dirname "$dst")"
    msg "cloning $id"
    git clone --recursive "$repo" "$dst" >> "$log" 2>&1
  fi

  (
    cd "$dst"
    git fetch --tags --quiet origin
    if [ "$ref" = "HEAD" ]; then
      branch="$(git remote show origin 2>/dev/null | awk '/HEAD branch/ {print $NF; exit}')"
      if [ -n "$branch" ]; then
        git checkout --quiet "$branch"
        git reset --hard --quiet "origin/$branch"
      else
        git checkout --quiet HEAD
      fi
    else
      git checkout --quiet "$ref"
    fi
    git submodule update --init --recursive >> "$log" 2>&1 || true
    git clean -fdx --quiet
  ) >> "$log" 2>&1
}

find_makefile() {
  local work="$1"
  local hint="$2"
  local candidate

  if [ -n "$hint" ] && [ -f "$work/$hint" ]; then
    printf '%s\n' "$hint"
    return 0
  fi
  for candidate in Makefile.libretro Makefile libretro/Makefile src/libretro/Makefile; do
    if [ -f "$work/$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

copy_core_info() {
  local base="$1"
  local src="$2"
  local info=""

  if [ -f "$SRC_ROOT/core-info/$base.info" ]; then
    info="$SRC_ROOT/core-info/$base.info"
  else
    info="$(find "$src" -type f -name "$base.info" | sort | head -n 1 || true)"
  fi
  if [ -n "$info" ] && [ -f "$info" ]; then
    cp "$info" "$OUT_DIR/info/$base.info"
  fi
}

stage_outputs() {
  local id="$1"
  local src="$2"
  local count=0
  local so
  local base
  local stem

  while IFS= read -r so; do
    [ -n "$so" ] || continue
    if ! "$READELF" -h "$so" >/dev/null 2>&1; then
      continue
    fi
    base="$(basename "$so")"
    stem="${base%.so}"
    cp "$so" "$OUT_DIR/cores/$base"
    "$STRIP" "$OUT_DIR/cores/$base" >/dev/null 2>&1 || true
    copy_core_info "$stem" "$src"
    append_manifest "  output=cores/$base"
    count=$((count + 1))
  done <<EOF_STAGE
$(find "$src" -type f -name '*_libretro.so' | sort)
EOF_STAGE

  [ "$count" -gt 0 ]
}

build_one_core() {
  local id="$1"
  local class="$2"
  local repo="$3"
  local ref="$4"
  local subdir="$5"
  local makefile_hint="$6"
  local make_args="$7"
  local src="$SRC_ROOT/$id"
  local work
  local log="$LOG_DIR_ABS/$id.log"
  local makefile
  local commit

  if ! core_selected "$id" "$class"; then
    SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
    return 0
  fi

  : > "$log"
  append_manifest ""
  append_manifest "[$id]"
  append_manifest "class=$class"
  append_manifest "repo=$repo"
  append_manifest "ref=$ref"
  append_manifest "log=logs/$id.log"

  if ! clone_or_update_repo "$id" "$repo" "$ref" "$src" "$log"; then
    msg "FAILED clone $id"
    append_manifest "status=failed"
    append_manifest "reason=clone_failed"
    FAILED_COUNT=$((FAILED_COUNT + 1))
    return 0
  fi

  commit="$(git -C "$src" rev-parse HEAD 2>/dev/null || printf unknown)"
  append_manifest "commit=$commit"

  work="$src"
  if [ -n "$subdir" ]; then
    work="$src/$subdir"
  fi
  if [ ! -d "$work" ]; then
    msg "FAILED $id: missing subdir $subdir"
    append_manifest "status=failed"
    append_manifest "reason=missing_subdir:$subdir"
    FAILED_COUNT=$((FAILED_COUNT + 1))
    return 0
  fi
  if ! makefile="$(find_makefile "$work" "$makefile_hint")"; then
    msg "FAILED $id: no libretro makefile"
    append_manifest "status=failed"
    append_manifest "reason=no_makefile"
    FAILED_COUNT=$((FAILED_COUNT + 1))
    return 0
  fi

  append_manifest "makefile=${subdir:+$subdir/}$makefile"
  append_manifest "make_args=$make_args"
  append_manifest "jobs=$JOBS"

  read -r -a args <<< "$make_args"
  if ! (
    cd "$work"
    make -f "$makefile" clean >/dev/null 2>&1 || true
    env CC="$CC" CXX="$CXX" AR="$AR" RANLIB="$RANLIB" \
      make -f "$makefile" -j"$JOBS" "${args[@]}" GIT_VERSION=-"$(printf '%s' "$commit" | cut -c 1-7)"
  ) >> "$log" 2>&1; then
    msg "FAILED build $id"
    append_manifest "status=failed"
    append_manifest "reason=build_failed"
    FAILED_COUNT=$((FAILED_COUNT + 1))
    return 0
  fi

  if stage_outputs "$id" "$src"; then
    append_manifest "status=built"
    BUILT_COUNT=$((BUILT_COUNT + 1))
    msg "built $id"
  else
    msg "FAILED $id: no *_libretro.so output"
    append_manifest "status=failed"
    append_manifest "reason=no_output"
    FAILED_COUNT=$((FAILED_COUNT + 1))
  fi
}

if [ ! -f "$CORE_RECIPES" ]; then
  printf 'error: recipe file not found: %s\n' "$CORE_RECIPES" >&2
  exit 1
fi

if [ "$LIST_ONLY" = "1" ]; then
  while IFS='|' read -r id class repo ref subdir makefile make_args; do
    if core_selected "$id" "$class"; then
      printf '%s\t%s\t%s\t%s\n' "$id" "$class" "$ref" "$make_args"
    fi
  done <<EOF_LIST
$(core_table)
EOF_LIST
  exit 0
fi

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR/cores" "$OUT_DIR/info" "$OUT_DIR/logs" "$(dirname "$SRC_ROOT")"
LOG_DIR="$OUT_DIR/logs"
LOG_DIR_ABS="$(CDPATH= cd -- "$LOG_DIR" && pwd)"
MANIFEST="$OUT_DIR/libretro-cores.manifest"
BUILT_COUNT=0
FAILED_COUNT=0
SKIPPED_COUNT=0

{
  printf 'name=plumOS V90S libretro cores\n'
  printf 'generated_at=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  printf 'target=v90s-aarch64-linux-gnu\n'
  printf 'recipes=%s\n' "$CORE_RECIPES"
  printf 'filter=%s\n' "$PLUMOS_CORE_FILTER"
  printf 'cc=%s\n' "$CC"
  printf 'cxx=%s\n' "$CXX"
  printf 'jobs=%s\n' "$JOBS"
} > "$MANIFEST"

core_info_log="$LOG_DIR_ABS/core-info.log"
: > "$core_info_log"
if clone_or_update_repo core-info "$CORE_INFO_REPO" "$CORE_INFO_REF" "$SRC_ROOT/core-info" "$core_info_log"; then
  append_manifest ""
  append_manifest "[core-info]"
  append_manifest "repo=$CORE_INFO_REPO"
  append_manifest "ref=$CORE_INFO_REF"
  append_manifest "commit=$(git -C "$SRC_ROOT/core-info" rev-parse HEAD 2>/dev/null || printf unknown)"
  append_manifest "log=logs/core-info.log"
  append_manifest "status=available"
else
  append_manifest ""
  append_manifest "[core-info]"
  append_manifest "status=failed"
  append_manifest "reason=clone_failed"
  append_manifest "log=logs/core-info.log"
fi

while IFS='|' read -r id class repo ref subdir makefile make_args; do
  build_one_core "$id" "$class" "$repo" "$ref" "$subdir" "$makefile" "$make_args"
done <<EOF_CORES
$(core_table)
EOF_CORES

append_manifest ""
append_manifest "[summary]"
append_manifest "built=$BUILT_COUNT"
append_manifest "failed=$FAILED_COUNT"
append_manifest "skipped=$SKIPPED_COUNT"

find "$OUT_DIR" -type f ! -name checksums.sha256 | sort | while IFS= read -r file; do
  rel="${file#"$OUT_DIR"/}"
  sha256sum "$file" | awk -v rel="$rel" '{print $1 "  " rel}'
done > "$OUT_DIR/checksums.sha256"

printf 'created: %s\n' "$OUT_DIR"
printf 'built: %s\n' "$BUILT_COUNT"
printf 'failed: %s\n' "$FAILED_COUNT"
printf 'skipped: %s\n' "$SKIPPED_COUNT"

if [ "$FAILED_COUNT" -gt 0 ] && [ "$FAIL_ON_CORE_ERROR" = "1" ]; then
  exit 1
fi
