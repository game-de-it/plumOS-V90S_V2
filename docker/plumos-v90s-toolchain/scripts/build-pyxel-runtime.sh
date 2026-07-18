#!/usr/bin/env sh
set -eu

out_dir="${PLUMOS_V90S_PYXEL_RUNTIME_OUT:-output/pyxel-runtime/v90s}"
requirements="${PLUMOS_V90S_PYXEL_RUNTIME_REQUIREMENTS:-package/frontend-v90s/plumos/share/pyxel/requirements.lock.txt}"
install_root="${PLUMOS_V90S_PYXEL_INSTALL_ROOT:-/mnt/plumos}"
sdl2_dir="${PLUMOS_V90S_PYXEL_SDL2_DIR:-output/sdl2-powervr/usr/local/lib/plumos-sdl2-powervr}"
pvr_dir="${PLUMOS_V90S_PYXEL_PVR_DIR:-output/vendor/v90s-stockos-r1/root/usr/lib/powervr}"
fit_source="${PLUMOS_V90S_PYXEL_FIT_SOURCE:-package/pyxel-v90s/plumos_pyxel_fit.c}"

usage() {
    cat <<'USAGE'
Usage:
  build-pyxel-runtime.sh [--out-dir PATH] [--requirements PATH]
                         [--sdl2-dir PATH] [--pvr-dir PATH]

Builds the pinned AArch64 Pyxel virtual environment packaged at
plumos/venvs/pyxel. The deployed environment remains user-updatable through
Apps -> Pyxel Setup.
USAGE
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --out-dir)
            out_dir="$2"
            shift 2
            ;;
        --requirements)
            requirements="$2"
            shift 2
            ;;
        --sdl2-dir)
            sdl2_dir="$2"
            shift 2
            ;;
        --pvr-dir)
            pvr_dir="$2"
            shift 2
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

[ -r "$requirements" ] || {
    printf 'error: Pyxel lock file is missing: %s\n' "$requirements" >&2
    exit 1
}
[ -r "$sdl2_dir/libSDL2-2.0.so.0" ] || {
    printf 'error: V90S SDL2 runtime is missing: %s\n' "$sdl2_dir/libSDL2-2.0.so.0" >&2
    exit 1
}
[ -r "$fit_source" ] || {
    printf 'error: V90S Pyxel display fit source is missing: %s\n' "$fit_source" >&2
    exit 1
}
python3 -m venv --help >/dev/null 2>&1 || {
    printf 'error: python3-venv is required in the toolchain image\n' >&2
    exit 1
}

venv_rel="venvs/pyxel"
venv_dir="$out_dir/plumos/$venv_rel"
rm -rf "$out_dir"
mkdir -p "$out_dir/plumos/venvs" "$out_dir/licenses"

mkdir -p "$out_dir/plumos/lib"
${CC:-cc} -O2 -fPIC -Wall -Wextra -Werror -shared \
    -Wl,-soname,plumos-pyxel-fit.so \
    -o "$out_dir/plumos/lib/plumos-pyxel-fit.so" "$fit_source" -ldl

python3 -m venv --copies "$venv_dir"
PYTHONDONTWRITEBYTECODE=1 PIP_DISABLE_PIP_VERSION_CHECK=1 \
    "$venv_dir/bin/python3" -m pip install \
    --only-binary=:all: \
    --no-compile \
    --requirement "$requirements"

PYTHONDONTWRITEBYTECODE=1 PYGAME_HIDE_SUPPORT_PROMPT=1 \
    "$venv_dir/bin/python3" -m pip check

site_packages="$venv_dir/lib/python3.11/site-packages"
rm -rf \
    "$site_packages/pygame/docs" \
    "$site_packages/pygame/examples" \
    "$site_packages/pyxel/examples"
find "$site_packages" -type d \( -name test -o -name tests \) -prune \
    -exec rm -rf {} +

validation_library_path="$sdl2_dir"
if [ -d "$pvr_dir" ]; then
    validation_library_path="$validation_library_path:$pvr_dir"
fi
package_versions="$(
    PYTHONDONTWRITEBYTECODE=1 PYGAME_HIDE_SUPPORT_PROMPT=1 \
        LD_LIBRARY_PATH="$validation_library_path${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
        "$venv_dir/bin/python3" - <<'PY'
from importlib import import_module, metadata

for distribution, module in (
    ("pyxel", "pyxel"),
    ("pygame", "pygame"),
    ("numpy", "numpy"),
    ("Pillow", "PIL"),
):
    import_module(module)
    print(f"{distribution}={metadata.version(distribution)}")
PY
)"

find "$venv_dir" -type d -name __pycache__ -prune -exec rm -rf {} +
# app-layer packaging dereferences links for FAT-compatible payloads. Python
# does not need the lib64 -> lib convenience link, so omit its 149 MB duplicate.
rm -f "$venv_dir/lib64"
find "$venv_dir/bin" -type f | while IFS= read -r executable; do
    first_line="$(sed -n '1p' "$executable" 2>/dev/null || true)"
    case "$first_line" in
        '#!'*"$venv_dir"*)
            sed -i "1s|^#!.*$venv_dir/bin/python[0-9.]*|#!$install_root/$venv_rel/bin/python3|" "$executable"
            ;;
    esac
done
for activate_script in activate activate.csh activate.fish; do
    [ -f "$venv_dir/bin/$activate_script" ] || continue
    sed -i "s|$venv_dir|$install_root/$venv_rel|g" "$venv_dir/bin/$activate_script"
done
sed -i \
    "s|^command = .*|command = /usr/bin/python3 -m venv --copies $install_root/$venv_rel|" \
    "$venv_dir/pyvenv.cfg"

requirements_sha256="$(sha256sum "$requirements" | awk '{print $1}')"
fit_sha256="$(sha256sum "$fit_source" | awk '{print $1}')"
file_count="$(find "$venv_dir" -type f | wc -l | tr -d ' ')"
cat > "$out_dir/pyxel-runtime.manifest" <<EOF
component=pyxel-runtime
target=aarch64-v90s
install_root=$install_root
venv=$install_root/$venv_rel
python=$(python3 --version 2>&1)
requirements=$requirements
requirements_sha256=$requirements_sha256
display_fit=$install_root/lib/plumos-pyxel-fit.so
display_fit_source=$fit_source
display_fit_sha256=$fit_sha256
$package_versions
file_count=$file_count
EOF

find "$out_dir/plumos" -type f | sort | while IFS= read -r file; do
    rel="${file#"$out_dir/"}"
    sha256sum "$file" | sed "s|  .*|  $rel|"
done > "$out_dir/checksums.sha256"

printf 'created: %s\n' "$out_dir"
printf '%s\n' "$package_versions"
