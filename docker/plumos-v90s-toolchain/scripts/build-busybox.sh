#!/usr/bin/env bash
set -euo pipefail

BUSYBOX_VERSION="${BUSYBOX_VERSION:-1.38.0}"
BUSYBOX_SHA256="${BUSYBOX_SHA256:-34f9ea6ff8636f2c9241153b9114eefa9e65674a45318ae1ef95bb5f31c53bb2}"
BUSYBOX_URL="https://busybox.net/downloads/busybox-${BUSYBOX_VERSION}.tar.bz2"

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)"
DOWNLOAD_DIR="${ROOT_DIR}/build/downloads"
BUILD_DIR="${ROOT_DIR}/build/v90s-busybox-${BUSYBOX_VERSION}"
SRC_DIR="${BUILD_DIR}/src"
PATCH_DIR="${ROOT_DIR}/docker/plumos-v90s-toolchain/patches"
DIST_DIR="${PLUMOS_V90S_USERLAND_OUT:-${ROOT_DIR}/output/userland/v90s}"
PLUMOS_DIR="${DIST_DIR}/plumos"
BIN_DIR="${PLUMOS_DIR}/bin"
GNU_BIN_DIR="${PLUMOS_DIR}/gnu/bin"
GNU_LIBEXEC_DIR="${PLUMOS_DIR}/gnu/libexec"
LIB_DIR="${PLUMOS_DIR}/lib"
DOC_DIR="${PLUMOS_DIR}/share/doc/busybox"
GNU_DOC_DIR="${PLUMOS_DIR}/share/doc/gnu-userland"
TARBALL="${DOWNLOAD_DIR}/busybox-${BUSYBOX_VERSION}.tar.bz2"
JOBS="${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}"
READELF="${READELF:-readelf}"
STRIP_BIN="${STRIP:-strip}"

COPIED_RUNTIME_LIBS=""

usage() {
  cat <<'EOF'
Usage:
  build-busybox.sh

Builds the plumOS V90S userland package into:
  output/userland/v90s/

Environment:
  PLUMOS_V90S_USERLAND_OUT  Override output directory.
  BUSYBOX_VERSION           BusyBox source version.
  BUSYBOX_SHA256            BusyBox source archive SHA-256.
  JOBS                      Parallel build job count.
EOF
}

case "${1:-}" in
  -h|--help|help)
    usage
    exit 0
    ;;
  "")
    ;;
  *)
    printf 'error: unknown argument: %s\n' "$1" >&2
    usage >&2
    exit 2
    ;;
esac

log() {
  printf '%s\n' "==> $*"
}

die() {
  printf '%s\n' "error: $*" >&2
  exit 1
}

sha256_of() {
  sha256sum "$1" | awk '{print $1}'
}

download_busybox() {
  mkdir -p "$DOWNLOAD_DIR"

  if [ -f "$TARBALL" ] && [ "$(sha256_of "$TARBALL")" = "$BUSYBOX_SHA256" ]; then
    log "Using cached BusyBox tarball"
    return
  fi

  log "Downloading BusyBox ${BUSYBOX_VERSION}"
  curl -fsSL "$BUSYBOX_URL" -o "$TARBALL"

  actual_sha="$(sha256_of "$TARBALL")"
  [ "$actual_sha" = "$BUSYBOX_SHA256" ] || die "BusyBox SHA-256 mismatch: ${actual_sha}"
}

set_config() {
  local symbol="$1"
  local value="$2"
  local key="CONFIG_${symbol}"

  case "$value" in
    y|n) ;;
    *) die "invalid config value for ${symbol}: ${value}" ;;
  esac

  if grep -q "^${key}=" "${SRC_DIR}/.config"; then
    sed -i "s/^${key}=.*/${key}=${value}/" "${SRC_DIR}/.config"
  elif grep -q "^# ${key} is not set" "${SRC_DIR}/.config"; then
    sed -i "s/^# ${key} is not set/${key}=${value}/" "${SRC_DIR}/.config"
  else
    printf '%s=%s\n' "$key" "$value" >> "${SRC_DIR}/.config"
  fi
}

prepare_source() {
  rm -rf "$BUILD_DIR"
  mkdir -p "$SRC_DIR"
  tar -C "$SRC_DIR" --strip-components=1 -xf "$TARBALL"
  patch -d "$SRC_DIR" -p1 < "${PATCH_DIR}/busybox-1.38.0-ftpd-utf8-feat.patch"

  (
    cd "$SRC_DIR"
    make defconfig >/dev/null

    set_config STATIC y
    set_config FEATURE_INSTALLER y
    set_config FEATURE_VERBOSE_USAGE y
    set_config SHOW_USAGE y
    set_config LONG_OPTS y
    set_config FEATURE_HUMAN_READABLE y
    set_config FEATURE_PREFER_APPLETS n
    set_config FEATURE_SH_STANDALONE n

    set_config ASH y
    set_config SH_IS_ASH y
    set_config BASH_IS_NONE y
    set_config HUSH n

    set_config TCPSVD y
    set_config FTPD y
    set_config FEATURE_FTPD_WRITE y
    set_config FEATURE_FTPD_ACCEPT_BROKEN_LIST y

    set_config PS y
    set_config FEATURE_PS_WIDE y
    set_config FEATURE_PS_LONG y
    set_config FEATURE_PS_TIME y
    set_config FEATURE_PS_ADDITIONAL_COLUMNS y

    set_config TOP y
    set_config FEATURE_TOP_CPU_USAGE_PERCENTAGE y
    set_config FEATURE_TOP_CPU_GLOBAL_PERCENTS y
    set_config FEATURE_TOP_SMP_CPU y
    set_config FEATURE_TOP_DECIMALS y
    set_config FEATURE_TOPMEM y

    set_config DF y
    set_config FEATURE_DF_FANCY y
    set_config FREE y
    set_config FUSER y
    set_config LSOF y
    set_config WATCH y
    set_config TIMEOUT y
    set_config FIND y
    set_config FEATURE_FIND_MAXDEPTH y
    set_config AWK y
    set_config SED y
    set_config GREP y
    set_config TAR y
    set_config GZIP y
    set_config UNZIP y
    set_config VI y
    set_config NETSTAT y

    set +o pipefail
    yes "" | make oldconfig >/dev/null
    oldconfig_status="${PIPESTATUS[1]}"
    set -o pipefail
    [ "$oldconfig_status" -eq 0 ] || exit "$oldconfig_status"
  )
}

build_busybox() {
  log "Building BusyBox ${BUSYBOX_VERSION} (${JOBS} jobs)"
  (
    cd "$SRC_DIR"
    make -j"$JOBS" busybox > "${BUILD_DIR}/make.log" 2>&1
  ) || {
    tail -160 "${BUILD_DIR}/make.log" >&2 || true
    die "BusyBox build failed"
  }

  "$STRIP_BIN" "${SRC_DIR}/busybox" 2>/dev/null || true
}

write_busybox_wrapper() {
  local applet="$1"
  local path="${BIN_DIR}/${applet}"

  mkdir -p "$(dirname "$path")"
  {
    printf '%s\n' '#!/bin/sh'
    printf '%s\n' 'PLUMOS_ROOT="${PLUMOS_ROOT:-/mnt/plumos}"'
    printf 'exec "${PLUMOS_ROOT}/bin/busybox" %s "$@"\n' "$applet"
  } > "$path"
  chmod 0755 "$path"
}

find_runtime_lib() {
  local soname="$1"
  local dir

  for dir in \
    /lib/aarch64-linux-gnu \
    /usr/lib/aarch64-linux-gnu \
    /lib \
    /usr/lib; do
    if [ -e "${dir}/${soname}" ]; then
      readlink -f "${dir}/${soname}"
      return 0
    fi
  done

  return 1
}

runtime_needed() {
  local elf="$1"
  "$READELF" -d "$elf" 2>/dev/null | awk '/NEEDED/ { gsub(/[][]/, "", $5); print $5 }'
}

copy_runtime_lib_tree() {
  local soname="$1"
  local lib

  case " ${COPIED_RUNTIME_LIBS} " in
    *" ${soname} "*) return 0 ;;
  esac

  lib="$(find_runtime_lib "$soname")" || die "runtime library not found: ${soname}"
  install -m 0755 "$lib" "${LIB_DIR}/${soname}"
  COPIED_RUNTIME_LIBS="${COPIED_RUNTIME_LIBS} ${soname}"

  while IFS= read -r child; do
    [ -n "$child" ] || continue
    copy_runtime_lib_tree "$child"
  done < <(runtime_needed "${LIB_DIR}/${soname}")
}

copy_runtime_deps() {
  local elf="$1"
  local soname

  while IFS= read -r soname; do
    [ -n "$soname" ] || continue
    copy_runtime_lib_tree "$soname"
  done < <(runtime_needed "$elf")
}

copy_loader() {
  local loader

  for loader in \
    /lib/ld-linux-aarch64.so.1 \
    /lib/aarch64-linux-gnu/ld-linux-aarch64.so.1; do
    if [ -e "$loader" ]; then
      install -m 0755 "$(readlink -f "$loader")" "$LIB_DIR/ld-linux-aarch64.so.1"
      return 0
    fi
  done
  die "aarch64 dynamic loader not found"
}

write_loader_wrapper() {
  local name="$1"
  local binary="$2"
  local path="${GNU_BIN_DIR}/${name}"

  mkdir -p "$(dirname "$path")"
  {
    printf '%s\n' '#!/bin/sh'
    printf '%s\n' 'PLUMOS_ROOT="${PLUMOS_ROOT:-/mnt/plumos}"'
    printf '%s\n' 'PLUMOS_LIB="${PLUMOS_ROOT}/lib"'
    printf '%s\n' 'exec "${PLUMOS_LIB}/ld-linux-aarch64.so.1" \'
    printf '%s\n' '  --library-path "${PLUMOS_LIB}:${PLUMOS_LIB}/samba:/usr/lib/aarch64-linux-gnu:/usr/lib:/lib" \'
    printf '  "${PLUMOS_ROOT}/gnu/libexec/%s" "$@"\n' "$binary"
  } > "$path"
  chmod 0755 "$path"
}

install_gnu_tool() {
  local name="$1"
  shift
  local candidate
  local src=""
  local dst="${GNU_LIBEXEC_DIR}/${name}.bin"

  for candidate in "$@"; do
    if [ -e "$candidate" ]; then
      src="$(readlink -f "$candidate")"
      break
    fi
  done

  [ -n "$src" ] || die "${name}: binary not found; rebuild the Docker image"
  file "$src" | grep -Eq 'aarch64|ARM aarch64' || die "${name}: ${src} is not an aarch64 binary"

  install -m 0755 "$src" "$dst"
  copy_runtime_deps "$dst"
  write_loader_wrapper "$name" "$(basename "$dst")"

  {
    echo "== ${name} =="
    echo "source: ${src}"
    file "$dst"
    echo
    "$READELF" -d "$dst" | grep NEEDED || true
    echo
  } >> "${GNU_DOC_DIR}/manifest.txt"
}

assemble_gnu_tools() {
  log "Assembling GNU/iproute2 userland tools"
  mkdir -p "$GNU_BIN_DIR" "$GNU_LIBEXEC_DIR" "$LIB_DIR" "$GNU_DOC_DIR"
  : > "${GNU_DOC_DIR}/manifest.txt"
  copy_loader

  install_gnu_tool ip /bin/ip /sbin/ip /usr/sbin/ip
  install_gnu_tool rsync /usr/bin/rsync /bin/rsync
  install_gnu_tool ss /bin/ss /usr/bin/ss /sbin/ss /usr/sbin/ss
  install_gnu_tool strace /usr/bin/strace /bin/strace

  {
    echo "plumOS V90S GNU-style userland tools"
    echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo
    echo "Debian package versions:"
    dpkg-query -W -f='${binary:Package}\t${Version}\n' \
      iproute2 strace rsync 2>/dev/null || true
  } > "${GNU_DOC_DIR}/versions.txt"

  {
    find "$GNU_BIN_DIR" "$GNU_LIBEXEC_DIR" -type f -print
    find "$LIB_DIR" -maxdepth 1 -type f -print
  } | sort | xargs sha256sum > "${GNU_DOC_DIR}/SHA256SUMS"

  find "$LIB_DIR" -maxdepth 1 -type f -printf '%f\n' | sort > "${GNU_DOC_DIR}/runtime-libs.txt"

  cat > "${GNU_DOC_DIR}/README.txt" <<'EOF'
GNU-style userland tools for plumOS V90S

Installed wrappers:
  /mnt/plumos/gnu/bin/ip
  /mnt/plumos/gnu/bin/rsync
  /mnt/plumos/gnu/bin/ss
  /mnt/plumos/gnu/bin/strace

The wrappers run aarch64 Debian binaries from:
  /mnt/plumos/gnu/libexec

They explicitly use the plumOS dynamic loader and library path:
  /mnt/plumos/lib/ld-linux-aarch64.so.1
  /mnt/plumos/lib
EOF
}

write_manifest() {
  local manifest="${DIST_DIR}/userland.manifest"
  local generated_at
  generated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  {
    echo "artifact_name=plumos-v90s-userland"
    echo "artifact_type=userland-tools"
    echo "target=v90s"
    echo "version_or_git_ref=busybox-${BUSYBOX_VERSION}"
    echo "source_url_or_input_path=${BUSYBOX_URL}"
    echo "patches=busybox-1.38.0-ftpd-utf8-feat.patch"
    echo "builder_image=${PLUMOS_V90S_DOCKER_IMAGE:-plumos-v90s-toolchain:dev}"
    echo "build_timestamp_utc=${generated_at}"
    echo "compat_vendor=${PLUMOS_V90S_VENDOR_RUNTIME_ID:-v90s-stockos-r1}"
    echo "output_path=${DIST_DIR}"
    echo "busybox_sha256=${BUSYBOX_SHA256}"
  } > "$manifest"

  find "$DIST_DIR" -type f ! -name checksums.sha256 | sort | while IFS= read -r file; do
    rel="${file#"$DIST_DIR"/}"
    sha="$(sha256sum "$file" | awk '{print $1}')"
    printf '%s  %s\n' "$sha" "$rel"
  done > "${DIST_DIR}/checksums.sha256"
}

assemble_package() {
  log "Assembling plumOS V90S userland package"
  rm -rf "$DIST_DIR"
  mkdir -p "$BIN_DIR" "$DOC_DIR"

  install -m 0755 "${SRC_DIR}/busybox" "${BIN_DIR}/busybox"

  if [ ! -s "${SRC_DIR}/busybox.links" ]; then
    (cd "$SRC_DIR" && make busybox.links >/dev/null)
  fi

  sort -u "${SRC_DIR}/busybox.links" | while IFS= read -r link; do
    [ -n "$link" ] || continue
    applet="$(basename "$link")"
    case "$applet" in
      busybox) continue ;;
    esac
    write_busybox_wrapper "$applet"
  done

  assemble_gnu_tools

  cat > "${BIN_DIR}/plumos-env" <<'EOF'
#!/bin/sh
export PLUMOS_ROOT="${PLUMOS_ROOT:-/mnt/plumos}"
export PLUMOS_SDCARD_ROOT="${PLUMOS_SDCARD_ROOT:-${PLUMOS_ROOT}}"
export PATH="${PLUMOS_ROOT}/bin:${PLUMOS_ROOT}/gnu/bin:${PATH}"
if [ "$#" -eq 0 ]; then
  exec "${PLUMOS_ROOT}/bin/sh"
fi
exec "$@"
EOF
  chmod 0755 "${BIN_DIR}/plumos-env"

  cat > "${DOC_DIR}/README.txt" <<EOF
BusyBox ${BUSYBOX_VERSION} for plumOS V90S

Installed under:
  /mnt/plumos/bin

Use:
  /mnt/plumos/bin/plumos-env sh
  PATH=/mnt/plumos/bin:\$PATH ps --help

Source:
  ${BUSYBOX_URL}

Patches:
  busybox-1.38.0-ftpd-utf8-feat.patch

SHA-256:
  ${BUSYBOX_SHA256}
EOF

  sort -u "${SRC_DIR}/busybox.links" > "${DOC_DIR}/applets.txt"
  sha256sum "${BIN_DIR}/busybox" > "${DOC_DIR}/busybox.sha256"

  {
    echo "plumOS V90S userland package"
    echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "busybox_version: ${BUSYBOX_VERSION}"
    echo "busybox_source_sha256: ${BUSYBOX_SHA256}"
    echo "patch: busybox-1.38.0-ftpd-utf8-feat.patch"
    echo
    file "${BIN_DIR}/busybox"
    echo
    "$READELF" -h "${BIN_DIR}/busybox"
  } > "${DOC_DIR}/manifest.txt"

  write_manifest

  printf 'created: %s\n' "$DIST_DIR"
  printf 'busybox_wrappers: %s\n' "$(find "$BIN_DIR" -type f | wc -l)"
  printf 'gnu_wrappers: %s\n' "$(find "$GNU_BIN_DIR" -type f | wc -l)"
}

download_busybox
prepare_source
build_busybox
assemble_package
