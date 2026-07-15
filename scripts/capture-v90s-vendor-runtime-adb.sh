#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${PLUMOS_V90S_VENDOR_CAPTURE_OUT:-$ROOT_DIR/artifacts/vendor/v90s-stockos-r1}"
ADB_WRAPPER="$ROOT_DIR/scripts/v90s-adb.sh"
REMOTE_P1_MOUNT=/run/plumos/vendor-capture-p1
FORCE=0
export COPYFILE_DISABLE=1

usage() {
    cat <<EOF
Usage: scripts/capture-v90s-vendor-runtime-adb.sh [--out-dir PATH] [--force]

Capture the boot resources, vendor runtime files, raw env/boot partitions, and
raw Allwinner boot chain from the currently running V90S over plumOS ADB.

Default output:
  artifacts/vendor/v90s-stockos-r1
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --out-dir)
            OUT_DIR="$2"
            shift 2
            ;;
        --force)
            FORCE=1
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

case "$OUT_DIR" in
    ""|/|.|..)
        printf 'error: unsafe output path: %s\n' "$OUT_DIR" >&2
        exit 2
        ;;
esac

if [ -e "$OUT_DIR" ] && [ "$FORCE" -ne 1 ]; then
    printf 'error: output already exists: %s\n' "$OUT_DIR" >&2
    printf 'hint: pass --force to replace this ignored capture\n' >&2
    exit 1
fi

"$ADB_WRAPPER" recover >/dev/null

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/plumos-v90s-vendor-capture.XXXXXX")"
CAPTURE_DIR="$WORK_DIR/capture"
cleanup() {
    "$ADB_WRAPPER" shell "umount '$REMOTE_P1_MOUNT' 2>/dev/null || true; rmdir '$REMOTE_P1_MOUNT' 2>/dev/null || true" \
        >/dev/null 2>&1 || true
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

mkdir -p \
    "$WORK_DIR/root/media/Volumn" \
    "$WORK_DIR/root/media/BATOCERA" \
    "$CAPTURE_DIR/files" \
    "$CAPTURE_DIR/raw-partitions" \
    "$CAPTURE_DIR/raw-boot-chain"

"$ADB_WRAPPER" shell \
    "mkdir -p '$REMOTE_P1_MOUNT'; mountpoint -q '$REMOTE_P1_MOUNT' || mount -t vfat -o ro /dev/mmcblk0p1 '$REMOTE_P1_MOUNT'"

"$ADB_WRAPPER" exec-out sh -c \
    "tar -czf - -C '$REMOTE_P1_MOUNT' ." > "$WORK_DIR/volumn.tar.gz"
tar --no-xattrs -xzf "$WORK_DIR/volumn.tar.gz" -C "$WORK_DIR/root/media/Volumn"
rm -rf \
    "$WORK_DIR/root/media/Volumn/.fseventsd" \
    "$WORK_DIR/root/media/Volumn/System Volume Information" \
    "$WORK_DIR/root/media/Volumn/ROMS"

"$ADB_WRAPPER" exec-out sh -c \
    'tar -czf - -C /boot .' > "$WORK_DIR/batocera-boot.tar.gz"
tar --no-xattrs -xzf "$WORK_DIR/batocera-boot.tar.gz" -C "$WORK_DIR/root/media/BATOCERA"
rm -rf "$WORK_DIR/root/media/BATOCERA/lost+found"

"$ADB_WRAPPER" exec-out sh -c \
    'tar -czf - -C / usr/lib/powervr lib/modules/4.9.191 lib/firmware etc/modprobe.d usr/local/lib/plumos-sdl2-powervr usr/local/sbin/v90s-pvr-probe' \
    > "$WORK_DIR/vendor-files.tar.gz"
tar --no-xattrs -xzf "$WORK_DIR/vendor-files.tar.gz" -C "$WORK_DIR/root"

tar --no-xattrs -czf "$CAPTURE_DIR/files/stockos-selected-files.tar.gz" -C "$WORK_DIR/root" .
tar -tzf "$CAPTURE_DIR/files/stockos-selected-files.tar.gz" | sort > "$CAPTURE_DIR/file-list.txt"

capture_raw() {
    destination="$1"
    expected_size="$2"
    shift 2
    "$ADB_WRAPPER" exec-out sh -c "$*" > "$destination"
    actual_size="$(stat -f %z "$destination" 2>/dev/null || stat -c %s "$destination")"
    if [ "$actual_size" -ne "$expected_size" ]; then
        printf 'error: capture size mismatch: %s expected=%s actual=%s\n' \
            "$destination" "$expected_size" "$actual_size" >&2
        exit 1
    fi
}

capture_raw "$CAPTURE_DIR/raw-partitions/mmcblk0p2-env.bin" 262144 \
    'dd if=/dev/mmcblk0p2 bs=262144 count=1 2>/dev/null'
capture_raw "$CAPTURE_DIR/raw-partitions/mmcblk0p3-env-redund.bin" 262144 \
    'dd if=/dev/mmcblk0p3 bs=262144 count=1 2>/dev/null'
capture_raw "$CAPTURE_DIR/raw-partitions/mmcblk0p4-boot.bin" 67108864 \
    'dd if=/dev/mmcblk0p4 bs=1048576 count=64 2>/dev/null'
capture_raw "$CAPTURE_DIR/raw-boot-chain/boot0-offset-131072.bin" 65536 \
    'dd if=/dev/mmcblk0 bs=512 skip=256 count=128 2>/dev/null'
capture_raw "$CAPTURE_DIR/raw-boot-chain/boot-package-offset-16793600.bin" 4702208 \
    'dd if=/dev/mmcblk0 bs=512 skip=32800 count=9184 2>/dev/null'

BOOT0_SHA="$(shasum -a 256 "$CAPTURE_DIR/raw-boot-chain/boot0-offset-131072.bin" | awk '{print $1}')"
BOOT_PACKAGE_SHA="$(shasum -a 256 "$CAPTURE_DIR/raw-boot-chain/boot-package-offset-16793600.bin" | awk '{print $1}')"
KNULLI_BOOT0_SHA=not-present
if [ -f "$ROOT_DIR/.cache/knulli-linux/board/allwinner/a133/powkiddy-v90s/partitions/boot0.img" ]; then
    KNULLI_BOOT0_SHA="$(shasum -a 256 "$ROOT_DIR/.cache/knulli-linux/board/allwinner/a133/powkiddy-v90s/partitions/boot0.img" | awk '{print $1}')"
fi

cat > "$CAPTURE_DIR/README.txt" <<EOF
plumOS V90S vendor runtime capture
Captured: $(date -u '+%Y-%m-%dT%H:%M:%SZ')
Source: currently running, known-good V90S SD1 through plumOS ADB
Kernel: Linux 4.9.191
Boot layout: StockOS/Batocera-compatible p1-p7

This capture preserves the exact raw boot chain and p2/p3/p4 partitions from
the running SD. It also includes p1 boot resources, p6 boot configuration,
PowerVR userspace, Linux 4.9.191 modules, firmware, and SDL2 PowerVR runtime.

boot0_sha256=$BOOT0_SHA
boot_package_capture_sha256=$BOOT_PACKAGE_SHA
knulli_cache_boot0_sha256=$KNULLI_BOOT0_SHA
boot0_matches_knulli_cache=$([ "$BOOT0_SHA" = "$KNULLI_BOOT0_SHA" ] && printf yes || printf no)

The captured boot0 may match the KNULLI cache because the currently running
baseline used that compatible V90S boot component. Image assembly consumes this
captured vendor input and does not invoke the KNULLI fallback path.
EOF

(
    cd "$CAPTURE_DIR"
    find . -type f ! -name SHA256SUMS -print0 |
        sort -z |
        xargs -0 shasum -a 256 > SHA256SUMS
)

mkdir -p "$(dirname -- "$OUT_DIR")"
rm -rf "$OUT_DIR"
mv "$CAPTURE_DIR" "$OUT_DIR"

printf 'created: %s\n' "$OUT_DIR"
du -sh "$OUT_DIR"
