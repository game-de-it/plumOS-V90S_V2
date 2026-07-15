#!/usr/bin/env bash
set -euo pipefail

ROOT=/workspace
PICOARCH_REPO=https://github.com/shauninman/picoarch.git
PICOARCH_REF=802047c276a5a931b0bf837c4ea4b8e238bdeabe
SDL12_REPO=https://github.com/libsdl-org/sdl12-compat.git
SDL12_REF=fc2ec0c128197f1f5050e48359bc41e618f3abfb
SRC="$ROOT/build/picoarch-v90s"
SDL12_SRC="$ROOT/build/sdl12-compat-v90s-formal"
OUT="$ROOT/output/picoarch/v90s"
JOBS="${JOBS:-$(nproc)}"

checkout_source() {
  local repo="$1" ref="$2" dst="$3"
  if [ ! -d "$dst/.git" ]; then
    rm -rf "$dst"
    git clone "$repo" "$dst"
  fi
  git -C "$dst" fetch --depth 1 origin "$ref"
  git -C "$dst" reset --hard FETCH_HEAD
  git -C "$dst" clean -ffdx
}

checkout_source "$PICOARCH_REPO" "$PICOARCH_REF" "$SRC"
git -C "$SRC" submodule update --init --recursive
git -C "$SRC" submodule foreach --recursive 'git reset --hard; git clean -ffdx'
checkout_source "$SDL12_REPO" "$SDL12_REF" "$SDL12_SRC"

perl -0pi -e 's/scaler_neon\.o/scaler_c.o picoarch_v90s_host.o/ or die "scaler object marker missing\n";
  s/-lpng12/-lpng/ or die "libpng marker missing\n";
  s/else ifeq \(\$\(platform\), unix\)/else ifeq (\$(platform), v90s)\n\tOBJS += plat_linux.o\n\tCFLAGS += -march=armv8-a+crc -mtune=cortex-a53 -pthread -DCONTENT_DIR='"'"'"\/mnt\/plumos\/roms"'"'"'\n\tLDFLAGS += -fPIE -pthread\nelse ifeq (\$(platform), unix)/ or die "platform marker missing\n"' "$SRC/Makefile"

awk 'BEGIN { n=0 } /^ifeq \(\$\(platform\), trimui\)/ { n++; if (n == 2) exit } { print }' \
  "$SRC/Makefile" > "$SRC/Makefile.v90s"
mv "$SRC/Makefile.v90s" "$SRC/Makefile"

{
  printf '%s\n' '#include <stdint.h>' '#include <string.h>' '#include "scaler_neon.h"'
  for scale in 1 2 3 4 5 6; do
    for depth in 16 32; do
      printf 'void scale%sx_n%s(void *src, void *dst, uint32_t sw, uint32_t sh, uint32_t sp, uint32_t dp) { scale%sx_c%s(src, dst, sw, sh, sp, dp); }\n' \
        "$scale" "$depth" "$scale" "$depth"
    done
  done
  awk '/^void scale1x_c16/ { copy=1 } copy { print }' "$SRC/scaler_neon.c"
} > "$SRC/scaler_c.c"

cp "$ROOT/docker/plumos-v90s-toolchain/picoarch/picoarch_v90s_fbdev.h" \
  "$SRC/picoarch_v90s_fbdev.h"
cp "$ROOT/docker/plumos-v90s-toolchain/picoarch/picoarch_v90s_host.c" \
  "$SRC/picoarch_v90s_host.c"
cp "$ROOT/docker/plumos-v90s-toolchain/picoarch/picoarch_v90s_host.h" \
  "$SRC/picoarch_v90s_host.h"

git -C "$SRC" apply \
  "$ROOT/docker/plumos-v90s-toolchain/picoarch/picoarch-v90s-input-aspect.patch"
git -C "$SRC" apply \
  "$ROOT/docker/plumos-v90s-toolchain/picoarch/picoarch-v90s-content-dir.patch"

perl -0pi -e 's/\tjoycount = SDL_NumJoysticks\(\);/\tjoycount = 0; \/\* V90S controller is owned by evdev. \*\// or die "SDL joystick marker missing\n"' \
  "$SRC/libpicofe/in_sdl.c"

perl -0pi -e 's{// begin miyoo hardware scaling support.*?// end miyoo hardware scaling support}{static void buffer_init(void) {}\nstatic void buffer_quit(void) {}\nstatic void buffer_scale(unsigned w, unsigned h, size_t pitch, const void *src) {\n\tscale(w, h, pitch, src, screen->pixels);\n}}s or die "Miyoo video block marker missing\n";
  s{static SDL_Surface\* screen;}{static SDL_Surface* screen;\nstatic SDL_Surface* display;\n#include "picoarch_v90s_fbdev.h"} or die "screen marker missing\n";
  s{static void \*fb_flip\(void\)\n\{\n\tSDL_Flip\(screen\);\n\treturn screen->pixels;\n\}}{static void *fb_flip(void)\n{\n\tv90s_fb_present(screen);\n\treturn screen->pixels;\n}} or die "flip marker missing\n";
  s{screen = SDL_SetVideoMode\(SCREEN_WIDTH, SCREEN_HEIGHT, SCREEN_BPP \* 8, SDL_SWSURFACE\);\n\tif \(screen == NULL\) \{\n\t\tPA_ERROR\("%s, failed to set video mode\\n", __func__\);\n\t\treturn -1;\n\t\}}{display = SDL_SetVideoMode(SCREEN_WIDTH, SCREEN_HEIGHT, 32, SDL_SWSURFACE);\n\tif (display == NULL) {\n\t\tPA_ERROR("%s, failed to set video mode\\n", __func__);\n\t\treturn -1;\n\t}\n\tscreen = SDL_CreateRGBSurface(SDL_SWSURFACE, SCREEN_WIDTH, SCREEN_HEIGHT, 16,\n\t                              0xF800, 0x07E0, 0x001F, 0x0000);\n\tif (screen == NULL || v90s_fb_init() < 0) {\n\t\tPA_ERROR("%s, failed to create V90S RGB565 framebuffer\\n", __func__);\n\t\treturn -1;\n\t}} or die "video init marker missing\n";
  s{\tSDL_FreeSurface\(screen\);\n\tscreen = NULL;}{\tSDL_FreeSurface(screen);\n\tSDL_FreeSurface(display);\n\tv90s_fb_finish();\n\tscreen = NULL;\n\tdisplay = NULL;} or die "video finish marker missing\n"' "$SRC/plat_sdl.c"

perl -0pi -e 's{static void get_tag_name\(const char\* in_path, char\* out_tag\) \{.*?\n\}\n\nint main}{static void get_tag_name(const char* in_path, char* out_tag) {\n\tconst char *system = getenv("PLUMOS_PICOARCH_SYSTEM");\n\tif (system && system[0]) {\n\t\tsnprintf(out_tag, MAX_PATH, "%s", system);\n\t\treturn;\n\t}\n\tconst char *slash = strrchr(in_path, '\''/'\'');\n\tsize_t len = slash ? (size_t)(slash - in_path) : strlen(in_path);\n\twhile (len > 0 && in_path[len - 1] == '\''/'\'') len--;\n\tconst char *start = in_path;\n\tfor (size_t i = 0; i < len; i++) if (in_path[i] == '\''/'\'') start = in_path + i + 1;\n\tsnprintf(out_tag, MAX_PATH, "%.*s", (int)(in_path + len - start), start);\n}\n\nint main}s or die "tag function marker missing\n"' "$SRC/main.c"

perl -0pi -e 's{static void set_directories\(const char \*core_name, const char \*tag_name\) \{.*?\n\}\n\n// based on eggs}{static void set_directories(const char *core_name, const char *tag_name) {\n\tconst char *home = getenv("HOME");\n\tconst char *save_root = getenv("PLUMOS_PICOARCH_SAVE_ROOT");\n\tconst char *bios_dir = getenv("PLUMOS_PICOARCH_BIOS_DIR");\n\tif (home) {\n\t\tsnprintf(config_dir, MAX_PATH, "%s/.picoarch-%s-%s/", home, core_name, tag_name);\n\t\tmkdir(config_dir, 0755);\n\t}\n\tif (!save_root || !save_root[0]) save_root = "/mnt/plumos/Saves";\n\tif (!bios_dir || !bios_dir[0]) bios_dir = "/mnt/plumos/bios";\n\tsnprintf(save_dir, MAX_PATH, "%s/%s/", save_root, tag_name);\n\tmkdir(save_root, 0755);\n\tmkdir(save_dir, 0755);\n\tsnprintf(system_dir, MAX_PATH, "%s", bios_dir);\n}\n\n// based on eggs}s or die "directory function marker missing\n"' "$SRC/core.c"

perl -0pi -e 's{options_init\(\*\(const struct retro_core_option_definition \*\*\)data\);}{options_init((const struct retro_core_option_definition *)data);} or die "core options pointer marker missing\n"' \
  "$SRC/core.c"

git -C "$SRC" apply \
  "$ROOT/docker/plumos-v90s-toolchain/picoarch/picoarch-v90s-pixel-format.patch"
git -C "$SRC" apply \
  "$ROOT/docker/plumos-v90s-toolchain/picoarch/picoarch-v90s-libretro-env.patch"
git -C "$SRC" apply \
  "$ROOT/docker/plumos-v90s-toolchain/picoarch/picoarch-v90s-controller-init.patch"
git -C "$SRC" apply \
  "$ROOT/docker/plumos-v90s-toolchain/picoarch/picoarch-v90s-frame-audio-callback.patch"
git -C "$SRC" apply --recount \
  "$ROOT/docker/plumos-v90s-toolchain/picoarch/picoarch-v90s-async-audio-callback.patch"
git -C "$SRC" apply --recount --unidiff-zero \
  "$ROOT/docker/plumos-v90s-toolchain/picoarch/picoarch-v90s-display-audio-rate.patch"

perl -0pi -e 's{#include "core\.h"}{#include "core.h"\n#include "picoarch_v90s_host.h"} or die "host interface include marker missing\n";
  s~\tcase RETRO_ENVIRONMENT_GET_CORE_ASSETS_DIRECTORY: \{ /\* 30 \*/~\tcase RETRO_ENVIRONMENT_GET_PERF_INTERFACE: { /* 28 */\n\t\treturn v90s_get_perf_interface(data);\n\t}\n\tcase RETRO_ENVIRONMENT_GET_VFS_INTERFACE: { /* 45 | experimental */\n\t\treturn v90s_get_vfs_interface(data, core_path);\n\t}\n\tcase RETRO_ENVIRONMENT_GET_CORE_ASSETS_DIRECTORY: { /* 30 */~ or die "host interface environment marker missing\n"' \
  "$SRC/core.c"

# Upstream does not order the libpicofe patch stamp before every parallel
# object consumer, so resolve it before starting the parallel build.
make -C "$SRC" platform=v90s MMENU=0 libpicofe/.patched
make -C "$SRC" platform=v90s MMENU=0 -j"$JOBS" picoarch

cmake -S "$SDL12_SRC" -B "$SDL12_SRC/build-v90s" \
  -DCMAKE_BUILD_TYPE=Release -DSDL2_INCLUDE_DIRS=/usr/include/SDL2 \
  -DSDL12TESTS=OFF
cmake --build "$SDL12_SRC/build-v90s" -j"$JOBS"

rm -rf "$OUT"
mkdir -p "$OUT/picoarch/bin" "$OUT/picoarch/lib" "$OUT/bin" \
  "$OUT/config/standalone" "$OUT/licenses"
install -m 0755 "$SRC/picoarch" "$OUT/picoarch/bin/picoarch"
install -m 0644 "$SDL12_SRC/build-v90s/libSDL-1.2.so.1.2.72" \
  "$OUT/picoarch/lib/libSDL-1.2.so.0"
install -m 0644 "$(ldconfig -p | awk '/libpng16\.so\.16 \(/{print $NF; exit}')" \
  "$OUT/picoarch/lib/libpng16.so.16"
install -m 0644 "$(ldconfig -p | awk '/libz\.so\.1 \(/{print $NF; exit}')" \
  "$OUT/picoarch/lib/libz.so.1"
install -m 0755 "$ROOT/package/picoarch-v90s/bin/plumos-picoarch-launch" "$OUT/bin/"
install -m 0755 "$ROOT/package/picoarch-v90s/bin/plumos-picoarch-stop" "$OUT/bin/"
install -m 0644 "$ROOT/package/picoarch-v90s/config/standalone/picoarch.env" \
  "$OUT/config/standalone/"
install -m 0644 "$SRC/LICENSE" "$OUT/licenses/picoarch-LICENSE"
install -m 0644 "$SDL12_SRC/LICENSE.txt" "$OUT/licenses/sdl12-compat-LICENSE.txt"

cat > "$OUT/picoarch.manifest" <<EOF
name=plumOS V90S PicoArch
picoarch_repo=$PICOARCH_REPO
picoarch_ref=$PICOARCH_REF
sdl12_compat_repo=$SDL12_REPO
sdl12_compat_ref=$SDL12_REF
architecture=aarch64
core_route=/mnt/plumos/cores/*_libretro.so
video_route=V90S-fbdev-RGB565-to-BGRA8888-double-buffer
EOF

find "$OUT" -type f ! -name checksums.sha256 -print0 | sort -z | \
  xargs -0 sha256sum | sed "s|  $OUT/|  |" > "$OUT/checksums.sha256"
printf 'created: %s\n' "$OUT"
