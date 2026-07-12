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
PLUMOS_CORE_FILTER="${PLUMOS_CORE_FILTER:-plumos}"
FAIL_ON_CORE_ERROR="${FAIL_ON_CORE_ERROR:-1}"
JOBS="${JOBS:-$(nproc 2>/dev/null || echo 2)}"
BUILD_JOB_FALLBACKS="${BUILD_JOB_FALLBACKS:-1}"
LIBRETRO_SERIAL_CORES="${LIBRETRO_SERIAL_CORES:-nestopia quicknes gambatte gpsp picodrive mednafen_pce_fast mednafen_supergrafx mednafen_ngp mednafen_lynx handy prosystem gw pokemini mednafen_vb dinothawr mrboom tgbdual beetle_saturn flycast mupen64plus_next parallel_n64 yabasanshiro}"
COMMON_CFLAGS="${COMMON_CFLAGS:--O3 -pipe -DNDEBUG -fPIC -fomit-frame-pointer}"
COMMON_CXXFLAGS="${COMMON_CXXFLAGS:-$COMMON_CFLAGS}"
COMMON_LDFLAGS="${COMMON_LDFLAGS:-}"
CC="${CC:-gcc}"
CXX="${CXX:-g++}"
AS="${AS:-$CC -c}"
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
  --filter FILTER      all, v90s, plumos, class-a, class-b, class-o,
                       class-ab, or comma-separated core IDs.
                       Default: plumos.
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
for fallback_job in $BUILD_JOB_FALLBACKS; do
  case "$fallback_job" in
    ''|*[!0-9]*) BUILD_JOB_FALLBACKS=1 ;;
  esac
done

msg() {
  printf '[libretro-cores] %s\n' "$*" >&2
}

append_manifest() {
  printf '%s\n' "$*" >> "$MANIFEST"
}

core_aliases() {
  case "$1" in
    beetle_saturn) printf '%s\n' mednafen_saturn ;;
    mednafen_saturn) printf '%s\n' beetle_saturn ;;
    mednafen_lynx) printf '%s\n' beetle_lynx ;;
    mednafen_ngp) printf '%s\n' beetle_ngp ;;
    mednafen_pce_fast) printf '%s\n' beetle_pce_fast ;;
    mednafen_supergrafx) printf '%s\n' beetle_supergrafx ;;
    mednafen_vb) printf '%s\n' beetle_vb ;;
    mednafen_wswan) printf '%s\n' beetle_wswan ;;
  esac
}

core_output_aliases() {
  case "$1:$2" in
    beetle_saturn:mednafen_saturn_libretro.so)
      printf '%s\n' beetle_saturn_libretro.so
      ;;
  esac
}

core_selected() {
  local id="$1"
  local class="$2"
  local token
  local normalized
  local alias

  IFS=',' read -r -a filters <<< "$PLUMOS_CORE_FILTER"
  for token in "${filters[@]}"; do
    normalized="$(printf '%s' "$token" | tr -d '[:space:]')"
    [ -n "$normalized" ] || continue
    case "$normalized" in
      all|ALL)
        return 0
        ;;
      v90s|plumos|default|class-plumos|Class-plumOS)
        { [ "$class" = "A" ] || [ "$class" = "B" ]; } && return 0
        ;;
      class-a|Class-A|a|A)
        [ "$class" = "A" ] && return 0
        ;;
      class-b|Class-B|b|B)
        [ "$class" = "B" ] && return 0
        ;;
      class-ab|Class-AB|ab|AB)
        { [ "$class" = "A" ] || [ "$class" = "B" ]; } && return 0
        ;;
      class-o|Class-O|o|O|onion-extra|Onion-extra)
        [ "$class" = "O" ] && return 0
        ;;
      "$id")
        return 0
        ;;
    esac
    for alias in $(core_aliases "$id"); do
      [ "$normalized" = "$alias" ] && return 0
    done
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
  for candidate in \
    Makefile.libretro \
    makefile.libretro \
    makefilelibretro \
    libretro/Makefile \
    src/libretro/Makefile \
    platforms/libretro/Makefile \
    platform/libretro/Makefile \
    libretroBuildSystem/Makefile \
    CMakeLists.txt \
    Makefile \
    makefile; do
    if [ -f "$work/$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

cmake_target_from_args() {
  local id="$1"
  local arg

  for arg in "${args[@]}"; do
    case "$arg" in
      target=*)
        printf '%s\n' "${arg#target=}"
        return 0
        ;;
    esac
  done
  printf '%s_libretro\n' "$id"
}

cmake_args_without_internal_keys() {
  local arg

  for arg in "${args[@]}"; do
    case "$arg" in
      target=*)
        ;;
      *)
        printf '%s\n' "$arg"
      ;;
    esac
  done
}

core_initial_jobs() {
  local id="$1"
  local serial_cores=" ${LIBRETRO_SERIAL_CORES//,/ } "

  case "$serial_cores" in
    *" $id "*) printf '%s\n' 1 ;;
    *) printf '%s\n' "$JOBS" ;;
  esac
}

run_with_job_retry() {
  local id="$1"
  local log="$2"
  local job
  local seen=" "
  shift 2

  for job in "$(core_initial_jobs "$id")" $BUILD_JOB_FALLBACKS; do
    [ -n "$job" ] || continue
    case "$seen" in
      *" $job "*) continue ;;
    esac
    seen="${seen}${job} "
    printf '\n[plumOS] jobs=%s command=%s\n' "$job" "$*" >> "$log"
    if JOBS_ACTIVE="$job" "$@"; then
      LAST_SUCCESSFUL_JOBS="$job"
      return 0
    fi
    if [ "$job" != "1" ]; then
      msg "$id failed with jobs=$job; retrying lower parallelism"
    fi
  done
  return 1
}

patch_core_source() {
  local id="$1"
  local src="$2"
  local log="$3"
  local patch_dir="$ROOT_DIR/docker/plumos-v90s-toolchain/patches"
  local lua_makefile

  case "$id" in
    mgba)
      if [ -f "$src/src/core/CMakeLists.txt" ]; then
        sed -i -E '/^[[:space:]]+scripting\.c$/d' "$src/src/core/CMakeLists.txt"
        printf '\n[plumOS] patched mgba minimal libretro build to omit core scripting.c\n' >> "$log"
      fi
      if [ -f "$src/CMakeLists.txt" ]; then
        sed -i -E \
          -e 's|add_library\(\$\{BINARY_NAME\}_libretro SHARED \$\{CORE_SRC\} \$\{RETRO_SRC\} \$\{CORE_VFS_SRC\}\)|add_library(${BINARY_NAME}_libretro SHARED ${CORE_SRC} ${RETRO_SRC} ${CORE_VFS_SRC} ${CMAKE_CURRENT_SOURCE_DIR}/src/util/vfs/vfs-fd.c)|' \
          "$src/CMakeLists.txt"
        printf '[plumOS] patched mgba libretro CMake source list for duplicate/missing VFS symbols\n' >> "$log"
      fi
      ;;
    quasi88)
      if [ -f "$patch_dir/quasi88-libretro-monitor-options.patch" ]; then
        if patch --dry-run -d "$src" -p1 < "$patch_dir/quasi88-libretro-monitor-options.patch" >/dev/null 2>> "$log"; then
          patch -d "$src" -p1 < "$patch_dir/quasi88-libretro-monitor-options.patch" >> "$log" 2>&1
          printf '\n[plumOS] patched quasi88 libretro monitor options\n' >> "$log"
        else
          printf '\n[plumOS] skipped quasi88 monitor-options patch: source already patched or layout does not match\n' >> "$log"
        fi
      fi
      ;;
    nekop2)
      if [ -f "$patch_dir/nekop2-libretro-joypad-keyboard.patch" ]; then
        if patch --dry-run -d "$src" -p1 < "$patch_dir/nekop2-libretro-joypad-keyboard.patch" >/dev/null 2>> "$log"; then
          patch -d "$src" -p1 < "$patch_dir/nekop2-libretro-joypad-keyboard.patch" >> "$log" 2>&1
          printf '\n[plumOS] patched nekop2 joypad-to-keyboard mapping\n' >> "$log"
        else
          printf '\n[plumOS] skipped nekop2 joypad patch: source already patched or layout does not match\n' >> "$log"
        fi
      fi
      ;;
    px68k)
      if [ -f "$patch_dir/px68k-libretro-uppercase-bios.patch" ]; then
        if patch --dry-run -d "$src" -p1 < "$patch_dir/px68k-libretro-uppercase-bios.patch" >/dev/null 2>> "$log"; then
          patch -d "$src" -p1 < "$patch_dir/px68k-libretro-uppercase-bios.patch" >> "$log" 2>&1
          printf '\n[plumOS] patched px68k uppercase BIOS filename fallbacks\n' >> "$log"
        else
          printf '\n[plumOS] skipped px68k uppercase BIOS patch: source already patched or layout does not match\n' >> "$log"
        fi
      fi
      ;;
    hatari)
      if [ -f "$patch_dir/hatari-libretro-skip-empty-media-options.patch" ]; then
        if patch --dry-run -d "$src" -p1 < "$patch_dir/hatari-libretro-skip-empty-media-options.patch" >/dev/null 2>> "$log"; then
          patch -d "$src" -p1 < "$patch_dir/hatari-libretro-skip-empty-media-options.patch" >> "$log" 2>&1
          printf '\n[plumOS] patched hatari to skip empty media command-line options\n' >> "$log"
        else
          printf '\n[plumOS] skipped hatari empty-media patch: source layout does not match\n' >> "$log"
        fi
      fi
      ;;
    atari800)
      if [ -f "$patch_dir/atari800-libretro-audio-batch-pacing.patch" ]; then
        perl -0pi -e 's/\r\n/\n/g' "$src/libretro/core-mapper.c" "$src/libretro/libretro-core.c" 2>/dev/null || true
        if patch --dry-run -d "$src" -p1 < "$patch_dir/atari800-libretro-audio-batch-pacing.patch" >/dev/null 2>> "$log"; then
          patch -d "$src" -p1 < "$patch_dir/atari800-libretro-audio-batch-pacing.patch" >> "$log" 2>&1
          printf '\n[plumOS] patched atari800 libretro audio batching for frontend-driven timing\n' >> "$log"
        else
          printf '\n[plumOS] skipped atari800 audio patch: source already patched or layout does not match\n' >> "$log"
        fi
      fi
      ;;
    lutro)
      lua_makefile="$src/deps/lua/src/Makefile"
      if [ -f "$lua_makefile" ]; then
        sed -i -E \
          -e 's/^AR=[[:space:]]*ar rcu/AR= ar/' \
          -e 's/^\t\$\(AR\)[[:space:]]+\$@/\t$(AR) rcu $@/' \
          "$lua_makefile"
        printf '\n[plumOS] patched lutro Lua Makefile for command-line AR override\n' >> "$log"
      fi
      ;;
    fake08)
      if [ -f "$patch_dir/fake08-libretro-persistent-content-buffer.patch" ]; then
        if patch --dry-run -d "$src" -p1 < "$patch_dir/fake08-libretro-persistent-content-buffer.patch" >/dev/null 2>> "$log"; then
          patch -d "$src" -p1 < "$patch_dir/fake08-libretro-persistent-content-buffer.patch" >> "$log" 2>&1
          printf '\n[plumOS] patched fake08 libretro content buffer lifetime\n' >> "$log"
        else
          printf '\n[plumOS] skipped fake08 content buffer patch: source already patched or layout does not match\n' >> "$log"
        fi
      fi
      ;;
    mednafen_ngp|beetle_saturn|flycast|mupen64plus_next|parallel_n64|yabasanshiro)
      while IFS= read -r lua_makefile; do
        [ -f "$lua_makefile" ] || continue
        sed -i -E \
          -e 's/[[:space:]]-flto(=[^[:space:]]+)?//g' \
          -e 's/[[:space:]]-fwhole-program//g' \
          -e 's/[[:space:]]-fuse-linker-plugin//g' \
          "$lua_makefile"
      done <<EOF_HIGH_END_LTO
$(find "$src" -maxdepth 4 -type f \( \
  -name 'Makefile' -o \
  -name 'Makefile.*' -o \
  -name 'makefile' -o \
  -name 'makefile.*' -o \
  -name '*.mk' -o \
  -name '*.mak' \
\) -print)
EOF_HIGH_END_LTO
      printf '\n[plumOS] patched LTO-sensitive Makefiles for native V90S feedback builds\n' >> "$log"
      ;;
    easyrpg)
      if [ -f "$src/builds/libretro/CMakeLists.txt" ]; then
        sed -i -E \
          -e 's/include\(ConfigureWindows\)/include(PlayerConfigureWindows OPTIONAL)/' \
          "$src/builds/libretro/CMakeLists.txt"
        printf '\n[plumOS] patched EasyRPG libretro CMake to avoid a Windows-only include on Linux\n' >> "$log"
      fi
      ;;
    tic80)
      if [ -f "$src/core/vendor/zip/CMakeLists.txt" ]; then
        sed -i -E \
          -e 's/cmake_minimum_required\(VERSION 3\.14\)/cmake_minimum_required(VERSION 3.13)/' \
          "$src/core/vendor/zip/CMakeLists.txt"
        printf '\n[plumOS] patched tic80 vendored zip CMake minimum\n' >> "$log"
      fi
      ;;
  esac
}

cmake_build_command() {
  local source_dir="$1"
  local build_dir="$2"
  local target="$3"
  local build_type="$4"
  local log="$5"
  shift 5

  (
    rm -rf "$build_dir"
    env CC="$CC" CXX="$CXX" AR="$AR" RANLIB="$RANLIB" \
      cmake -S "$source_dir" -B "$build_dir" -G Ninja \
        -DCMAKE_BUILD_TYPE="$build_type" \
        -DCMAKE_C_FLAGS="$COMMON_CFLAGS" \
        -DCMAKE_CXX_FLAGS="$COMMON_CXXFLAGS" \
        -DCMAKE_SHARED_LINKER_FLAGS="$COMMON_LDFLAGS" \
        "$@"
    cmake --build "$build_dir" --parallel "$JOBS_ACTIVE" --target "$target"
  ) >> "$log" 2>&1
}

build_inih_for_easyrpg() {
  local src="$1"
  local log="$2"
  local inih_dir="$src/lib/inih"

  rm -rf "$inih_dir"
  mkdir -p "$(dirname "$inih_dir")"
  git clone --depth 1 https://github.com/benhoyt/inih.git "$inih_dir" >> "$log" 2>&1 || return 1
  (
    cd "$inih_dir"
    env CC="$CC" CFLAGS="$COMMON_CFLAGS -fPIC" "$CC" -c ini.c -o ini.o
    "$AR" rcs libinih.a ini.o
    "$RANLIB" libinih.a
  ) >> "$log" 2>&1
}

prepare_liblcf_for_easyrpg() {
  local src="$1"
  local log="$2"
  local liblcf_dir="$src/lib/liblcf"
  local liblcf_ref="${EASYRPG_LIBLCF_REF:-abc215345ba962a031f2b8c645f4357cf1bece85}"

  rm -rf "$liblcf_dir"
  mkdir -p "$(dirname "$liblcf_dir")"
  git clone --depth 1 https://github.com/EasyRPG/liblcf.git "$liblcf_dir" >> "$log" 2>&1 || return 1
  (
    cd "$liblcf_dir"
    git fetch --depth 1 origin "$liblcf_ref"
    git checkout --detach FETCH_HEAD
  ) >> "$log" 2>&1
}

run_scummvm_build() {
  local src="$1"
  local log="$2"

  (
    cd "$src/backends/platform/libretro"
    env CC="$CC" CXX="$CXX" AR="$AR" RANLIB="$RANLIB" \
      CFLAGS="$COMMON_CFLAGS" CXXFLAGS="$COMMON_CXXFLAGS" LDFLAGS="$COMMON_LDFLAGS" \
      make clean >/dev/null 2>&1 || true
    env CC="$CC" CXX="$CXX" AR="$AR" RANLIB="$RANLIB" \
      CFLAGS="$COMMON_CFLAGS" CXXFLAGS="$COMMON_CXXFLAGS" LDFLAGS="$COMMON_LDFLAGS" \
      make -j"$JOBS_ACTIVE" \
        platform=unix \
        LITE=1 \
        NO_WIP=1 \
        FORCE_OPENGLNONE=1 \
        USE_MT32EMU= \
        USE_VORBIS= \
        USE_THEORADEC= \
        USE_FLUIDSYNTH= \
        USE_FREETYPE2= \
        USE_MPEG2= \
        USE_IMGUI=
  ) >> "$log" 2>&1
}

make_build_command() {
  local work="$1"
  local makefile="$2"
  local log="$3"
  local commit="$4"
  shift 4

  (
    cd "$work"
    make -f "$makefile" clean >/dev/null 2>&1 || true
    env \
      CC="$CC" \
      CXX="$CXX" \
      AS="$AS" \
      AR="$AR" \
      RANLIB="$RANLIB" \
      CFLAGS="$COMMON_CFLAGS" \
      CXXFLAGS="$COMMON_CXXFLAGS" \
      LDFLAGS="$COMMON_LDFLAGS" \
      make -f "$makefile" -j"$JOBS_ACTIVE" "$@" \
        CC="$CC" CXX="$CXX" AS="$AS" AR="$AR" RANLIB="$RANLIB" \
        GIT_VERSION=-"$(printf '%s' "$commit" | cut -c 1-7)"
  ) >> "$log" 2>&1
}

build_special_core() {
  local id="$1"
  local src="$2"
  local log="$3"
  local tic80_src

  case "$id" in
    mgba)
      run_with_job_retry "$id" "$log" cmake_build_command "$src" "$src/build-libretro" mgba_libretro Release "$log" \
        -DBUILD_LIBRETRO=ON \
        -DBUILD_SDL=OFF \
        -DBUILD_QT=OFF \
        -DBUILD_GL=OFF \
        -DBUILD_GLES2=OFF \
        -DBUILD_PGO=OFF \
        -DBUILD_LTO=OFF \
        -DBUILD_PERF=OFF \
        -DBUILD_TEST=OFF \
        -DBUILD_DOCGEN=OFF \
        -DENABLE_SCRIPTING=OFF \
        -DUSE_LUA=OFF \
        -DUSE_JSON_C=OFF \
        -DUSE_FREETYPE=OFF \
        -DUSE_FFMPEG=OFF \
        -DUSE_DISCORD_RPC=OFF \
        -DUSE_EDITLINE=OFF
      ;;
    tic80)
      tic80_src="$src"
      [ ! -f "$src/core/CMakeLists.txt" ] || tic80_src="$src/core"
      run_with_job_retry "$id" "$log" cmake_build_command "$tic80_src" "$src/build-libretro" tic80_libretro MinSizeRel "$log" \
        -DBUILD_STATIC=ON \
        -DBUILD_PLAYER=OFF \
        -DBUILD_SDL=OFF \
        -DBUILD_SDLGPU=OFF \
        -DBUILD_TOOLS=OFF \
        -DBUILD_LIBRETRO=ON \
        -DBUILD_WITH_MRUBY=OFF
      ;;
    easyrpg)
      prepare_liblcf_for_easyrpg "$src" "$log" || return 1
      build_inih_for_easyrpg "$src" "$log" || return 1
      run_with_job_retry "$id" "$log" cmake_build_command "$src" "$src/build-libretro" easyrpg_libretro Release "$log" \
        -DPLAYER_TARGET_PLATFORM=libretro \
        -DPLAYER_BUILD_LIBLCF=ON \
        -DINIH_INCLUDE_DIR="$src/lib/inih" \
        -DINIH_LIBRARY="$src/lib/inih/libinih.a" \
        -DLIBLCF_WITH_ICU=OFF \
        -DLIBLCF_WITH_XML=OFF \
        -DLIBLCF_ENABLE_TOOLS=OFF \
        -DLIBLCF_ENABLE_TESTS=OFF \
        -DLIBLCF_ENABLE_BENCHMARKS=OFF \
        -DBUILD_SHARED_LIBS=ON \
        -DPLAYER_WITH_FREETYPE=OFF \
        -DPLAYER_WITH_HARFBUZZ=OFF \
        -DPLAYER_WITH_LHASA=OFF \
        -DPLAYER_WITH_MPG123=OFF \
        -DPLAYER_WITH_LIBSNDFILE=OFF \
        -DPLAYER_WITH_OGGVORBIS=OFF \
        -DPLAYER_WITH_OPUS=OFF \
        -DPLAYER_WITH_WILDMIDI=OFF \
        -DPLAYER_WITH_FLUIDSYNTH=OFF \
        -DPLAYER_WITH_FLUIDLITE=OFF \
        -DPLAYER_WITH_XMP=OFF \
        -DPLAYER_WITH_SPEEXDSP=OFF \
        -DPLAYER_WITH_SAMPLERATE=OFF
      ;;
    scummvm)
      run_with_job_retry "$id" "$log" run_scummvm_build "$src" "$log"
      ;;
    squirreljme)
      [ -f "$src/nanocoat/CMakeLists.txt" ] || return 99
      run_with_job_retry "$id" "$log" cmake_build_command "$src/nanocoat" "$src/nanocoat/build-libretro" squirreljme_libretro Release "$log" \
        -DSQUIRRELJME_ENABLE_FRONTEND_LIBRETRO=ON \
        -DSQUIRRELJME_ENABLE_FRONTEND_JRI=OFF \
        -DSQUIRRELJME_ENABLE_DYLIB=ON \
        -DSQUIRRELJME_ENABLE_PACKING=OFF \
        -DLIBRETRO_REALLY_STATIC=OFF
      ;;
    *)
      return 99
      ;;
  esac
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
  local source_base
  local base
  local stem
  local alias

  while IFS= read -r so; do
    [ -n "$so" ] || continue
    if ! "$READELF" -h "$so" >/dev/null 2>&1; then
      continue
    fi
    source_base="$(basename "$so")"
    base="$source_base"
    case "$base" in
      *_libretro.dll) base="${base%.dll}.so" ;;
    esac
    stem="${base%.so}"
    cp "$so" "$OUT_DIR/cores/$base"
    "$STRIP" "$OUT_DIR/cores/$base" >/dev/null 2>&1 || true
    copy_core_info "$stem" "$src"
    append_manifest "  output=cores/$base"
    if [ "$source_base" != "$base" ]; then
      append_manifest "  source_output=$source_base"
    fi
    for alias in $(core_output_aliases "$id" "$base"); do
      [ ! -f "$OUT_DIR/cores/$alias" ] || continue
      cp "$OUT_DIR/cores/$base" "$OUT_DIR/cores/$alias"
      copy_core_info "${alias%.so}" "$src"
      append_manifest "  alias_output=cores/$alias"
      append_manifest "  alias_of=cores/$base"
    done
    count=$((count + 1))
  done <<EOF_STAGE
$(find "$src" -type f \( -name '*_libretro.so' -o -name '*_libretro.dll' \) | sort)
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
  local special_status
  local LAST_SUCCESSFUL_JOBS=""

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
  patch_core_source "$id" "$src" "$log"

  if build_special_core "$id" "$src" "$log"; then
    special_status=0
  else
    special_status=$?
  fi
  if [ "$special_status" -eq 0 ]; then
    append_manifest "builder=special"
    append_manifest "jobs=${LAST_SUCCESSFUL_JOBS:-$JOBS}"
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
    return 0
  elif [ "$special_status" -ne 99 ]; then
    msg "FAILED special build $id"
    append_manifest "builder=special"
    append_manifest "status=failed"
    append_manifest "reason=special_build_failed"
    FAILED_COUNT=$((FAILED_COUNT + 1))
    return 0
  fi

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
  if [ "$makefile" = "CMakeLists.txt" ]; then
    local cmake_build_dir="$src/.plumos-cmake-build"
    local cmake_target
    local cmake_args=()

    cmake_target="$(cmake_target_from_args "$id")"
    while IFS= read -r arg; do
      [ -n "$arg" ] || continue
      cmake_args+=("$arg")
    done <<EOF_CMAKE_ARGS
$(cmake_args_without_internal_keys)
EOF_CMAKE_ARGS

    append_manifest "build_system=cmake"
    append_manifest "cmake_target=$cmake_target"
    if ! run_with_job_retry "$id" "$log" cmake_build_command "$work" "$cmake_build_dir" "$cmake_target" Release "$log" "${cmake_args[@]}"; then
      msg "FAILED build $id"
      append_manifest "status=failed"
      append_manifest "reason=cmake_build_failed"
      FAILED_COUNT=$((FAILED_COUNT + 1))
      return 0
    fi
  else
    append_manifest "build_system=make"
    if ! run_with_job_retry "$id" "$log" make_build_command "$work" "$makefile" "$log" "$commit" "${args[@]}"; then
      msg "FAILED build $id"
      append_manifest "status=failed"
      append_manifest "reason=build_failed"
      FAILED_COUNT=$((FAILED_COUNT + 1))
      return 0
    fi
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
  printf 'common_cflags=%s\n' "$COMMON_CFLAGS"
  printf 'common_cxxflags=%s\n' "$COMMON_CXXFLAGS"
  printf 'common_ldflags=%s\n' "$COMMON_LDFLAGS"
  printf 'jobs=%s\n' "$JOBS"
  printf 'job_fallbacks=%s\n' "$BUILD_JOB_FALLBACKS"
  printf 'serial_cores=%s\n' "$LIBRETRO_SERIAL_CORES"
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
