#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)"
PACKAGE_DIR="${ROOT_DIR}/package/network-services/plumos"
DIST_DIR="${PLUMOS_V90S_NETWORK_SERVICES_OUT:-${ROOT_DIR}/output/network-services/v90s}"
PLUMOS_DIR="${DIST_DIR}/plumos"
BIN_DIR="${PLUMOS_DIR}/bin"
LIB_DIR="${PLUMOS_DIR}/lib"
SSH_LIBEXEC_DIR="${PLUMOS_DIR}/ssh/libexec"
SAMBA_SBIN_DIR="${PLUMOS_DIR}/samba/sbin"
DOC_DIR="${PLUMOS_DIR}/share/doc/network-services"
MANIFEST="${DOC_DIR}/manifest.txt"

READELF="${READELF:-readelf}"
CC="${CC:-gcc}"
SAMBA_COMPAT="${LIB_DIR}/plumos-samba-compat.so"

COPIED_RUNTIME_LIBS=""

usage() {
  cat <<'EOF'
Usage:
  build-network-services.sh

Builds the plumOS V90S FTP/SFTP/Samba service package into:
  output/network-services/v90s/

Environment:
  PLUMOS_V90S_NETWORK_SERVICES_OUT  Override output directory.
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

find_runtime_lib() {
  local soname="$1"
  local dir

  for dir in \
    /lib/aarch64-linux-gnu \
    /usr/lib/aarch64-linux-gnu \
    /usr/lib/aarch64-linux-gnu/samba \
    /lib \
    /usr/lib \
    /usr/lib/samba; do
    if [ -e "${dir}/${soname}" ]; then
      readlink -f "${dir}/${soname}"
      return 0
    fi
  done

  return 1
}

find_packaged_lib() {
  local soname="$1"
  local dir

  for dir in "$LIB_DIR" "${LIB_DIR}/samba"; do
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

  if lib="$(find_packaged_lib "$soname" 2>/dev/null)"; then
    :
  else
    lib="$(find_runtime_lib "$soname")" || {
      printf 'warning: runtime library not found: %s\n' "$soname" >&2
      return 0
    }
    install -m 0755 "$lib" "${LIB_DIR}/${soname}"
    lib="${LIB_DIR}/${soname}"
  fi

  COPIED_RUNTIME_LIBS="${COPIED_RUNTIME_LIBS} ${soname}"

  while IFS= read -r child; do
    [ -n "$child" ] || continue
    copy_runtime_lib_tree "$child"
  done < <(runtime_needed "$lib")
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
  printf 'warning: aarch64 dynamic loader not found\n' >&2
  return 0
}

find_first() {
  local candidate
  for candidate in "$@"; do
    if [ -e "$candidate" ]; then
      readlink -f "$candidate"
      return 0
    fi
  done
  return 1
}

write_loader_wrapper() {
  local path="$1"
  local binary="$2"
  local prelude="$3"

  {
    printf '%s\n' '#!/bin/sh'
    printf '%s\n' 'PLUMOS_ROOT="${PLUMOS_ROOT:-/mnt/plumos}"'
    printf '%s\n' 'PLUMOS_SDCARD_ROOT="${PLUMOS_SDCARD_ROOT:-${PLUMOS_ROOT}}"'
    if [ -n "$prelude" ]; then
      printf '%s\n' "$prelude"
    fi
    printf '%s\n' 'PLUMOS_LIB="${PLUMOS_ROOT}/lib"'
    printf '%s\n' 'export LD_LIBRARY_PATH="${PLUMOS_LIB}:${PLUMOS_LIB}/samba:${PLUMOS_ROOT}/samba/lib:${LD_LIBRARY_PATH:-}"'
    printf '%s\n' 'exec "${PLUMOS_LIB}/ld-linux-aarch64.so.1" \'
    printf '%s\n' '  --library-path "${LD_LIBRARY_PATH}:/usr/lib/aarch64-linux-gnu:/usr/lib:/lib" \'
    printf '  "%s" "$@"\n' "$binary"
  } > "$path"
  chmod 0755 "$path"
}

assemble_base() {
  log "Assembling network services package"
  rm -rf "$DIST_DIR"
  mkdir -p "$BIN_DIR" "$LIB_DIR" "$SSH_LIBEXEC_DIR" "$SAMBA_SBIN_DIR" "$DOC_DIR"
  cp -a "${PACKAGE_DIR}/." "$PLUMOS_DIR/"
  chmod 0755 "${BIN_DIR}/plumos-network-services"
  : > "$MANIFEST"
  {
    echo "plumOS V90S network services"
    echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo
  } >> "$MANIFEST"
  copy_loader
}

install_sftp_server() {
  local src

  src="$(find_first /usr/lib/openssh/sftp-server /usr/lib/ssh/sftp-server 2>/dev/null || true)"
  if [ -z "$src" ]; then
    {
      echo "sftp-server: not installed in toolchain image"
      echo
    } >> "$MANIFEST"
    return 0
  fi

  log "Installing OpenSSH sftp-server"
  install -m 0755 "$src" "${SSH_LIBEXEC_DIR}/sftp-server.bin"
  copy_runtime_deps "${SSH_LIBEXEC_DIR}/sftp-server.bin"
  write_loader_wrapper \
    "${SSH_LIBEXEC_DIR}/sftp-server" \
    '${PLUMOS_ROOT}/ssh/libexec/sftp-server.bin' \
    'cd "${PLUMOS_SDCARD_ROOT}" 2>/dev/null || true'
  {
    echo "sftp-server: ${src}"
    file "${SSH_LIBEXEC_DIR}/sftp-server.bin"
    echo
  } >> "$MANIFEST"
}

install_samba_daemon() {
  local name="$1"
  local src="$2"
  local dst_bin="${SAMBA_SBIN_DIR}/${name}.bin"
  local dst_wrapper="${SAMBA_SBIN_DIR}/${name}"
  local prelude=""

  if [ -f "$SAMBA_COMPAT" ]; then
    prelude='export LD_PRELOAD="${PLUMOS_ROOT}/lib/plumos-samba-compat.so${LD_PRELOAD:+:${LD_PRELOAD}}"'
  fi

  install -m 0755 "$src" "$dst_bin"
  copy_runtime_deps "$dst_bin"
  write_loader_wrapper "$dst_wrapper" "\${PLUMOS_ROOT}/samba/sbin/${name}.bin" "$prelude"
  {
    echo "${name}: ${src}"
    file "$dst_bin"
    echo
  } >> "$MANIFEST"
}

install_samba_compat() {
  local src="${ROOT_DIR}/package/network-services/src/plumos_samba_compat.c"

  if [ ! -f "$src" ]; then
    return 0
  fi

  log "Building Samba kernel compatibility shim"
  "$CC" -shared -fPIC -O2 -Wall -Wextra -o "$SAMBA_COMPAT" "$src" -ldl
  copy_runtime_deps "$SAMBA_COMPAT"
  {
    echo "samba-compat: ${src}"
    file "$SAMBA_COMPAT"
    echo
  } >> "$MANIFEST"
}

install_samba() {
  local smbd
  local nmbd
  local samba_lib

  smbd="$(find_first /usr/sbin/smbd /usr/bin/smbd 2>/dev/null || true)"
  if [ -z "$smbd" ]; then
    {
      echo "samba: smbd not installed in toolchain image"
      echo
    } >> "$MANIFEST"
    return 0
  fi

  samba_lib="$(find_first /usr/lib/aarch64-linux-gnu/samba /usr/lib/samba 2>/dev/null || true)"
  if [ -n "$samba_lib" ]; then
    log "Copying Samba private libraries/modules"
    mkdir -p "${LIB_DIR}/samba"
    cp -aL "${samba_lib}/." "${LIB_DIR}/samba/"
  fi

  install_samba_compat

  log "Installing Samba smbd"
  install_samba_daemon smbd "$smbd"

  nmbd="$(find_first /usr/sbin/nmbd /usr/bin/nmbd 2>/dev/null || true)"
  if [ -n "$nmbd" ]; then
    log "Installing Samba nmbd"
    install_samba_daemon nmbd "$nmbd"
  fi

  if [ -d "${LIB_DIR}/samba" ]; then
    while IFS= read -r elf; do
      copy_runtime_deps "$elf"
    done < <(find "${LIB_DIR}/samba" -type f -name '*.so*' | sort)
  fi
}

install_fat_tools() {
  local fsck_fat
  local dst_bin="${BIN_DIR}/fsck.fat.bin"

  fsck_fat="$(find_first /usr/sbin/fsck.fat /sbin/fsck.fat 2>/dev/null || true)"
  if [ -z "$fsck_fat" ]; then
    {
      echo "fsck.fat: not installed in toolchain image"
      echo
    } >> "$MANIFEST"
    return 0
  fi

  log "Installing FAT checker"
  install -m 0755 "$fsck_fat" "$dst_bin"
  copy_runtime_deps "$dst_bin"
  write_loader_wrapper "${BIN_DIR}/fsck.fat" '${PLUMOS_ROOT}/bin/fsck.fat.bin' ''
  cp "${BIN_DIR}/fsck.fat" "${BIN_DIR}/dosfsck"
  chmod 0755 "${BIN_DIR}/dosfsck"

  {
    echo "fsck.fat: ${fsck_fat}"
    file "$dst_bin"
    echo
  } >> "$MANIFEST"
}

write_docs() {
  cat > "${DOC_DIR}/README.txt" <<'EOF'
plumOS V90S network services

Default share/home directory:
  /mnt/plumos

Services:
  FTP:
    BusyBox tcpsvd + ftpd, port 21, max 20 concurrent connections.
    Use FileZilla's Force UTF-8 charset setting for Japanese ROM filenames.
  SFTP:
    Installs an OpenSSH sftp-server payload. SSH itself remains managed by the
    V90S system rootfs so app-layer service control never stops SSH.
  Samba:
    Writable SMB share named SDCARD on port 445 for Windows/macOS network-drive
    mounting, max 20 connections. Use smb://V90S_IP/SDCARD or
    \\V90S_IP\SDCARD with:
      username: plumos
      password: plumos

Persistent service state:
  /mnt/plumos/config/network/services.conf

Runtime control:
  /mnt/plumos/bin/plumos-network-services status ftp
  /mnt/plumos/bin/plumos-network-services start ftp
  /mnt/plumos/bin/plumos-network-services stop ftp
  /mnt/plumos/bin/plumos-network-services status samba
  /mnt/plumos/bin/plumos-network-services start samba
  /mnt/plumos/bin/plumos-network-services stop samba
  /mnt/plumos/bin/plumos-network-services start-enabled
EOF

  {
    find "$PLUMOS_DIR" -type f -print
  } | sort | xargs sha256sum > "${DOC_DIR}/SHA256SUMS"
}

write_artifact_manifest() {
  local artifact="${DIST_DIR}/network-services.manifest"
  local generated_at
  generated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  {
    echo "artifact_name=plumos-v90s-network-services"
    echo "artifact_type=network-services"
    echo "target=v90s"
    echo "version_or_git_ref=0.1.0-dev"
    echo "source_url_or_input_path=package/network-services"
    echo "patches=none"
    echo "builder_image=${PLUMOS_V90S_DOCKER_IMAGE:-plumos-v90s-toolchain:dev}"
    echo "build_timestamp_utc=${generated_at}"
    echo "compat_vendor=${PLUMOS_V90S_VENDOR_RUNTIME_ID:-v90s-stockos-r1}"
    echo "output_path=${DIST_DIR}"
  } > "$artifact"

  find "$DIST_DIR" -type f ! -name checksums.sha256 | sort | while IFS= read -r file; do
    rel="${file#"$DIST_DIR"/}"
    sha="$(sha256sum "$file" | awk '{print $1}')"
    printf '%s  %s\n' "$sha" "$rel"
  done > "${DIST_DIR}/checksums.sha256"
}

assemble_base
install_sftp_server
install_samba
install_fat_tools
write_docs
write_artifact_manifest

printf 'created: %s\n' "$DIST_DIR"
find "$DIST_DIR" -maxdepth 5 -type f | sed "s#${DIST_DIR}/##" | sort
