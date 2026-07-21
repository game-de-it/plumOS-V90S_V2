#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)"
PACKAGE_DIR="${ROOT_DIR}/package/network-services/plumos"
SRC_DIR="${ROOT_DIR}/package/network-services/src"
DIST_DIR="${PLUMOS_V90S_NETWORK_SERVICES_OUT:-${ROOT_DIR}/output/network-services/v90s}"
USERLAND_DIR="${PLUMOS_V90S_USERLAND_OUT:-${ROOT_DIR}/output/userland/v90s}"
USERLAND_BIN_DIR="${USERLAND_DIR}/plumos/bin"
PLUMOS_DIR="${DIST_DIR}/plumos"
BIN_DIR="${PLUMOS_DIR}/bin"
LIB_DIR="${PLUMOS_DIR}/lib"
ADBD_BIN_DIR="${PLUMOS_DIR}/adb/bin"
SSH_LIBEXEC_DIR="${PLUMOS_DIR}/ssh/libexec"
SAMBA_SBIN_DIR="${PLUMOS_DIR}/samba/sbin"
DOC_DIR="${PLUMOS_DIR}/share/doc/network-services"
MANIFEST="${DOC_DIR}/manifest.txt"
ADBD_SOURCE_VERSION="29.0.6"
ADBD_DEBIAN_REVISION="28"
ADBD_SOURCE_PACKAGE="android-platform-tools"
ADBD_SOURCE_DIRNAME="${ADBD_SOURCE_PACKAGE}-${ADBD_SOURCE_VERSION}"
ADBD_SOURCE_BASE_URL="https://deb.debian.org/debian/pool/main/a/android-platform-tools"
ADBD_DSC="${ADBD_SOURCE_PACKAGE}_${ADBD_SOURCE_VERSION}-${ADBD_DEBIAN_REVISION}.dsc"
ADBD_ORIG_TAR="${ADBD_SOURCE_PACKAGE}_${ADBD_SOURCE_VERSION}.orig.tar.gz"
ADBD_DEBIAN_TAR="${ADBD_SOURCE_PACKAGE}_${ADBD_SOURCE_VERSION}-${ADBD_DEBIAN_REVISION}.debian.tar.xz"
ADBD_DSC_SHA256="a322e569f5f4d57c4b7ef1486182431be787895f60dc00b6d3ff489f894f97e4"
ADBD_ORIG_SHA256="dbd241642af17fe545a91c4b54d79867f94abfb64c1f4ed759aea5b85334a633"
ADBD_DEBIAN_SHA256="ae5d25152029cbdfc5c1b846a81d23ea30067a2638a94fa3cb9a8c867cf88bae"

READELF="${READELF:-readelf}"
CC="${CC:-gcc}"
ADBD_CXX="${PLUMOS_V90S_ADBD_CXX:-clang++}"
SAMBA_COMPAT="${LIB_DIR}/plumos-samba-compat.so"

COPIED_RUNTIME_LIBS=""

usage() {
  cat <<'EOF'
Usage:
  build-network-services.sh

Builds the plumOS V90S Wi-Fi/FTP/SFTP/Samba/ADB service package into:
  output/network-services/v90s/

Environment:
  PLUMOS_V90S_NETWORK_SERVICES_OUT  Override output directory.
  PLUMOS_V90S_USERLAND_OUT          BusyBox userland dependency directory.
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
    /usr/lib/aarch64-linux-gnu/android \
    /usr/lib/aarch64-linux-gnu/samba \
    /lib \
    /usr/lib \
    /usr/lib/android \
    /usr/lib/p7zip \
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
  mkdir -p "$BIN_DIR" "$LIB_DIR" "$ADBD_BIN_DIR" "$SSH_LIBEXEC_DIR" "$SAMBA_SBIN_DIR" "$DOC_DIR"
  cp -a "${PACKAGE_DIR}/." "$PLUMOS_DIR/"
  chmod 0755 "${BIN_DIR}/plumos-network-services"
  chmod 0755 "${BIN_DIR}/plumos-network-control"
  chmod 0755 "${BIN_DIR}/plumos-dns-runtime"
  chmod 0755 "${BIN_DIR}/plumos-time-sync"
  chmod 0755 "${BIN_DIR}/plumos-usb-disk-mode"
  chmod 0755 "${BIN_DIR}/plumos-adbd"
  chmod 0755 "${BIN_DIR}/plumos-adb-uevent"
  chmod 0755 "${BIN_DIR}/plumos-wifi-recovery"
  chmod 0755 "${BIN_DIR}/plumos-wifi-uevent"
  chmod 0755 "${BIN_DIR}/plumos-ssh-home"
  chmod 0755 "${BIN_DIR}/plumos-ssh-password"
  chmod 0755 "${PLUMOS_DIR}/ssh/start-ssh.sh" "${PLUMOS_DIR}/ssh/stop-ssh.sh"
  : > "$MANIFEST"
  {
    echo "plumOS V90S network services"
    echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo
  } >> "$MANIFEST"
  copy_loader
}

install_ftp_runtime() {
  local name src

  log "Installing BusyBox FTP runtime"
  for name in busybox tcpsvd ftpd; do
    src="${USERLAND_BIN_DIR}/${name}"
    if [ ! -f "$src" ]; then
      printf 'error: FTP dependency missing: %s\n' "$src" >&2
      printf 'hint: run ./scripts/docker-build.sh userland first\n' >&2
      exit 1
    fi
    install -m 0755 "$src" "${BIN_DIR}/${name}"
  done

  {
    echo "ftp-runtime: ${USERLAND_BIN_DIR}"
    sha256sum "${BIN_DIR}/busybox" "${BIN_DIR}/tcpsvd" "${BIN_DIR}/ftpd"
    echo
  } >> "$MANIFEST"
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
  local prelude='SAMBA_RUNTIME_DIR="${PLUMOS_SAMBA_RUNTIME_DIR:-/tmp/plumos-samba}"; export TMPDIR="${SAMBA_RUNTIME_DIR}"; mkdir -p "${SAMBA_RUNTIME_DIR}"; cd "${SAMBA_RUNTIME_DIR}" || exit 1'

  if [ -f "$SAMBA_COMPAT" ]; then
    prelude="${prelude}; export LD_PRELOAD=\"\${PLUMOS_ROOT}/lib/plumos-samba-compat.so\${LD_PRELOAD:+:\${LD_PRELOAD}}\""
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
  local src="${SRC_DIR}/plumos_samba_compat.c"

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

download_adbd_file() {
  local cache_dir="$1"
  local file="$2"
  local url="${ADBD_SOURCE_BASE_URL}/${file}"

  if [ ! -s "${cache_dir}/${file}" ]; then
    log "Downloading ${file}"
    curl -fsSL "$url" -o "${cache_dir}/${file}"
  fi
}

verify_cached_adbd_source() {
  local cache_dir="$1"

  (
    cd "$cache_dir"
    printf '%s  %s\n' "$ADBD_DSC_SHA256" "$ADBD_DSC" | sha256sum -c -
    printf '%s  %s\n' "$ADBD_ORIG_SHA256" "$ADBD_ORIG_TAR" | sha256sum -c -
    printf '%s  %s\n' "$ADBD_DEBIAN_SHA256" "$ADBD_DEBIAN_TAR" | sha256sum -c -
  ) >/dev/null
}

download_adbd_source() {
  local work_dir="$1"
  local src_root="$2"
  local cache_dir="${ROOT_DIR}/.cache/adbd/${ADBD_SOURCE_PACKAGE}_${ADBD_SOURCE_VERSION}-${ADBD_DEBIAN_REVISION}"

  mkdir -p "$cache_dir"
  download_adbd_file "$cache_dir" "$ADBD_DSC"
  download_adbd_file "$cache_dir" "$ADBD_ORIG_TAR"
  download_adbd_file "$cache_dir" "$ADBD_DEBIAN_TAR"
  verify_cached_adbd_source "$cache_dir"

  log "Extracting ${ADBD_SOURCE_PACKAGE} source"
  dpkg-source -x "${cache_dir}/${ADBD_DSC}" "$src_root" >/dev/null
}

patch_adbd_source() {
  local src_root="$1"
  local main_cpp="${src_root}/system/core/adb/daemon/main.cpp"
  local usb_cpp="${src_root}/system/core/adb/daemon/usb.cpp"

  perl -0pi -e \
    's/#if defined\(__ANDROID__\)\n    if \(access\(USB_FFS_ADB_EP0, F_OK\) == 0\) \{/#if defined(__ANDROID__) || defined(PLUMOS_ADBD_USB_FFS)\n    if (access(USB_FFS_ADB_EP0, F_OK) == 0) {/g' \
    "$main_cpp"
  if ! grep -q 'PLUMOS_ADBD_USB_FFS' "$main_cpp"; then
    printf 'error: failed to patch adbd USB FunctionFS guard\n' >&2
    exit 1
  fi

  perl -0pi -e \
    's/bool use_nonblocking = android::base::GetBoolProperty\(\n            "persist\.adb\.nonblocking_ffs",\n            android::base::GetBoolProperty\("ro\.adb\.nonblocking_ffs", true\)\);/#if defined(PLUMOS_ADBD_LEGACY_FFS)\n    bool use_nonblocking = false;\n#else\n    bool use_nonblocking = android::base::GetBoolProperty(\n            "persist.adb.nonblocking_ffs",\n            android::base::GetBoolProperty("ro.adb.nonblocking_ffs", true));\n#endif/g' \
    "$usb_cpp"
  if ! grep -q 'PLUMOS_ADBD_LEGACY_FFS' "$usb_cpp"; then
    printf 'error: failed to patch adbd legacy FunctionFS mode\n' >&2
    exit 1
  fi

  perl -0pi -e \
    's/if \(android::base::GetBoolProperty\("sys\.usb\.ffs\.aio_compat", false\)\) \{/#if defined(PLUMOS_ADBD_SYNC_FFS)\n    if (true) {\n#else\n    if (android::base::GetBoolProperty("sys.usb.ffs.aio_compat", false)) {\n#endif/g' \
    "${src_root}/system/core/adb/daemon/usb_legacy.cpp"
  if ! grep -q 'PLUMOS_ADBD_SYNC_FFS' "${src_root}/system/core/adb/daemon/usb_legacy.cpp"; then
    printf 'error: failed to patch adbd synchronous FunctionFS I/O\n' >&2
    exit 1
  fi
}

install_adbd() {
  local work_dir src_root build_dir dst_bin src src_path obj index
  local objects=()

  if [ "${PLUMOS_V90S_SKIP_ADBD:-0}" = "1" ]; then
    {
      echo "adbd: skipped by PLUMOS_V90S_SKIP_ADBD=1"
      echo
    } >> "$MANIFEST"
    return 0
  fi

  command -v "$ADBD_CXX" >/dev/null 2>&1 || {
    printf 'error: %s is required to build adbd\n' "$ADBD_CXX" >&2
    exit 1
  }
  command -v dpkg-source >/dev/null 2>&1 || {
    printf 'error: dpkg-source is required to build adbd\n' >&2
    exit 1
  }

  work_dir="$(mktemp -d /tmp/plumos-adbd.XXXXXX)"
  src_root="${work_dir}/${ADBD_SOURCE_DIRNAME}"
  download_adbd_source "$work_dir" "$src_root"
  patch_adbd_source "$src_root"
  build_dir="${work_dir}/build"
  mkdir -p "$build_dir"

  log "Building AOSP adbd for V90S FunctionFS"
  local cxxflags=(
    -std=gnu++2a
    -fPIC
    -fno-exceptions
    -fno-strict-aliasing
    -no-canonical-prefixes
    -fmessage-length=0
    -Wno-c++11-narrowing
    -DNDEBUG
    -UDEBUG
    -D_GNU_SOURCE
    -DADB_HOST=0
    -DALLOW_ADBD_ROOT=1
    -DALLOW_ADBD_NO_AUTH
    -DPLUMOS_ADBD_USB_FFS
    -DPLUMOS_ADBD_LEGACY_FFS
    -DPLUMOS_ADBD_SYNC_FFS
    -DPAGE_SIZE=4096
    "-DADB_VERSION=\"${ADBD_SOURCE_VERSION}-plumos\""
    "-DPLATFORM_TOOLS_VERSION=\"${ADBD_SOURCE_VERSION}\""
    -I/usr/include/android
    -Isystem/core/adb
    -Isystem/core/adb/daemon/include
    -Isystem/core/adb/adbconnection/include
    -Isystem/core/diagnose_usb/include
    -Isystem/core/libasyncio/include
    -Isystem/core/base/include
    -Isystem/core/include
  )

  local sources=(
    system/core/libasyncio/AsyncIO.cpp
    system/core/diagnose_usb/diagnose_usb.cpp
    system/core/adb/adb.cpp
    system/core/adb/adb_io.cpp
    system/core/adb/adb_listeners.cpp
    system/core/adb/adb_trace.cpp
    system/core/adb/adb_unique_fd.cpp
    system/core/adb/adb_utils.cpp
    system/core/adb/fdevent/fdevent.cpp
    system/core/adb/fdevent/fdevent_poll.cpp
    system/core/adb/fdevent/fdevent_epoll.cpp
    system/core/adb/services.cpp
    system/core/adb/sockets.cpp
    system/core/adb/socket_spec.cpp
    system/core/adb/sysdeps/errno.cpp
    system/core/adb/sysdeps_unix.cpp
    system/core/adb/sysdeps/posix/network.cpp
    system/core/adb/transport.cpp
    system/core/adb/transport_fd.cpp
    system/core/adb/transport_local.cpp
    system/core/adb/transport_usb.cpp
    system/core/adb/types.cpp
    system/core/adb/adbconnection/adbconnection_server.cpp
    "${SRC_DIR}/adbd_auth_stub.cpp"
    system/core/adb/daemon/jdwp_service.cpp
    system/core/adb/daemon/usb.cpp
    system/core/adb/daemon/usb_ffs.cpp
    system/core/adb/daemon/usb_legacy.cpp
    system/core/adb/daemon/file_sync_service.cpp
    system/core/adb/daemon/services.cpp
    system/core/adb/daemon/shell_service.cpp
    system/core/adb/shell_service_protocol.cpp
    system/core/adb/daemon/main.cpp
  )

  index=0
  for src in "${sources[@]}"; do
    if [[ "$src" = /* ]]; then
      src_path="$src"
    else
      src_path="${src_root}/${src}"
    fi
    [ -f "$src_path" ] || {
      printf 'error: adbd source missing: %s\n' "$src_path" >&2
      exit 1
    }
    obj="${build_dir}/obj-${index}.o"
    (
      cd "$src_root"
      "$ADBD_CXX" "${cxxflags[@]}" -c "$src_path" -o "$obj"
    )
    objects+=("$obj")
    index=$((index + 1))
  done

  dst_bin="${ADBD_BIN_DIR}/adbd.bin"
  "$ADBD_CXX" -o "$dst_bin" "${objects[@]}" \
    -L/usr/lib/aarch64-linux-gnu/android \
    -Wl,-rpath,/mnt/plumos/lib \
    -lbase -lcutils -llog -lcrypto -lutils -lcap -lselinux -lpthread -lresolv -lutil -pie
  strip "$dst_bin" 2>/dev/null || true
  copy_runtime_deps "$dst_bin"
  write_loader_wrapper \
    "${ADBD_BIN_DIR}/adbd" \
    '${PLUMOS_ROOT}/adb/bin/adbd.bin' \
    'cd / 2>/dev/null || true'

  {
    echo "adbd: ${ADBD_SOURCE_PACKAGE}_${ADBD_SOURCE_VERSION}-${ADBD_DEBIAN_REVISION}"
    echo "adbd-source-url: ${ADBD_SOURCE_BASE_URL}/${ADBD_DSC}"
    echo "adbd-source-sha256:"
    echo "  ${ADBD_DSC_SHA256}  ${ADBD_DSC}"
    echo "  ${ADBD_ORIG_SHA256}  ${ADBD_ORIG_TAR}"
    echo "  ${ADBD_DEBIAN_SHA256}  ${ADBD_DEBIAN_TAR}"
    echo "adbd-auth: no-auth development daemon"
    echo "adbd-patch: enable daemon USB FunctionFS init outside Android framework builds"
    echo "adbd-patch: force legacy FunctionFS because V90S kernel lacks FunctionFS AIO"
    echo "adbd-patch: force synchronous FunctionFS I/O for V90S"
    file "$dst_bin"
    echo
  } >> "$MANIFEST"

  rm -rf "$work_dir"
}

write_docs() {
  cat > "${DOC_DIR}/README.txt" <<'EOF'
plumOS V90S network services

Default share/home directory:
  /mnt/plumos

Services:
  Wi-Fi:
    /mnt/plumos/bin/plumos-network-control scans SSIDs and controls the USB
    Wi-Fi runtime used by the frontend. V90S has no internal Wi-Fi; when no USB
    dongle or supported interface is present, scan/connect return with a
    bounded failure stage instead of waiting forever.
    /mnt/plumos/bin/plumos-wifi-recovery blocks on kernel uevents while the
    saved Wi-Fi switch is ON and performs one bounded WPA/DHCP recovery after a
    USB Wi-Fi interface is re-added. It does not poll when a dongle is absent.
  FTP:
    BusyBox tcpsvd + ftpd, port 21, max 20 concurrent connections.
    Use FileZilla's Force UTF-8 charset setting for Japanese ROM filenames.
  SFTP:
    Installs an OpenSSH sftp-server payload. SFTP depends on the same
    plumOS-controlled SSH service.
  SSH:
    Controls the V90S OpenSSH daemon through /mnt/plumos/ssh/start-ssh.sh and
    /mnt/plumos/ssh/stop-ssh.sh. SSH logins prefer /mnt/plumos/bin and then
    /mnt/plumos/gnu/bin in PATH.
  Samba:
    Writable SMB share named SDCARD on port 445 for Windows/macOS network-drive
    mounting, max 20 connections. Use smb://V90S_IP/SDCARD or
    \\V90S_IP\SDCARD with:
      username: plumos
      password: plumos
  ADB:
    AOSP adbd over the kernel's USB FunctionFS/configfs gadget path. This is a
    no-auth development shell intended for local USB debugging on V90S; only
    enable it while connected to a trusted host. While ADB is enabled, a
    netlink uevent listener repairs a detached UDC after an android_usb
    disconnect. It sleeps until a kernel event arrives and does not poll.
  USB Disk Mode:
    Safely unmounts and exposes SD1 p4 PLUMOS as a USB mass-storage drive, so
    ROMs, BIOS, media, and update archives can be transferred without a fixed
    staging-size limit. Eject the drive on the PC, then unplug the USB cable;
    plumOS checks and remounts p4 and restores its content bindings.

Persistent service state:
  /mnt/plumos/config/network/services.conf

Runtime control:
  /mnt/plumos/bin/plumos-network-control --wifi status
  /mnt/plumos/bin/plumos-network-control --scan
  /mnt/plumos/bin/plumos-network-control --wifi on
  /mnt/plumos/bin/plumos-network-control --wifi off
  /mnt/plumos/bin/plumos-network-services status ftp
  /mnt/plumos/bin/plumos-network-services status ssh
  /mnt/plumos/bin/plumos-network-services start ssh
  /mnt/plumos/bin/plumos-network-services stop ssh
  /mnt/plumos/bin/plumos-network-services start ftp
  /mnt/plumos/bin/plumos-network-services stop ftp
  /mnt/plumos/bin/plumos-network-services status samba
  /mnt/plumos/bin/plumos-network-services start samba
  /mnt/plumos/bin/plumos-network-services stop samba
  /mnt/plumos/bin/plumos-network-services status adb
  /mnt/plumos/bin/plumos-network-services start adb
  /mnt/plumos/bin/plumos-network-services stop adb
  /mnt/plumos/bin/plumos-adbd status
  /mnt/plumos/bin/plumos-adbd recover
  /mnt/plumos/bin/plumos-network-services start-enabled
  /mnt/plumos/bin/plumos-usb-disk-mode status
  /mnt/plumos/bin/plumos-usb-disk-mode enter
  /mnt/plumos/bin/plumos-usb-disk-mode leave
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
install_ftp_runtime
install_sftp_server
install_samba
install_fat_tools
install_adbd
write_docs
write_artifact_manifest

printf 'created: %s\n' "$DIST_DIR"
find "$DIST_DIR" -maxdepth 5 -type f | sed "s#${DIST_DIR}/##" | sort
