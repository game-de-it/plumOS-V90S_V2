#!/usr/bin/env bash
set -euo pipefail

boot_package="${PLUMOS_V90S_FIXED_BOOT_PACKAGE:-output/boot-package/v90s-four-partition/boot_package.fex}"
boot_package_manifest="${PLUMOS_V90S_BOOT_PACKAGE_MANIFEST:-output/boot-package/v90s-four-partition/boot-package.manifest}"
boot_image="${PLUMOS_V90S_PROVISIONING_BOOT_IMAGE:-output/boot-image/v90s-four-partition/boot.img}"
boot_image_manifest="${PLUMOS_V90S_BOOT_IMAGE_MANIFEST:-output/boot-image/v90s-four-partition/boot-image.manifest}"
system_squashfs="${PLUMOS_V90S_SYSTEM_SQUASHFS:-output/system-rootfs/v90s/plumos-v90s-system-rootfs.squashfs}"
app_runtime="${PLUMOS_V90S_APP_RUNTIME:-output/app-layer/v90s}"
report="${PLUMOS_V90S_PREFLIGHT_REPORT:-output/preflight/v90s-four-partition.txt}"

fail() {
    printf 'preflight: FAIL: %s\n' "$*" >&2
    exit 1
}

pass() {
    printf 'PASS %s\n' "$*" | tee -a "$report"
}

manifest_value() {
    key="$1"
    file="$2"
    awk -F= -v key="$key" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' "$file"
}

verify_manifest_hash() {
    payload="$1"
    manifest="$2"
    key="$3"
    expected="$(manifest_value "$key" "$manifest")"
    actual="$(sha256sum "$payload" | awk '{print $1}')"
    [ -n "$expected" ] || fail "$manifest lacks $key"
    [ "$actual" = "$expected" ] || fail "$payload hash mismatch"
}

mkdir -p "$(dirname "$report")"
: > "$report"
printf 'plumOS V90S four-partition image preflight\n' >> "$report"
printf 'generated_at=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" >> "$report"

for tool in abootimg cpio gzip python3 sha256sum unsquashfs; do
    command -v "$tool" >/dev/null 2>&1 || fail "required tool unavailable: $tool"
done
for file in "$boot_package" "$boot_package_manifest" "$boot_image" \
    "$boot_image_manifest" "$system_squashfs" "$app_runtime/manifest.json" \
    "$app_runtime/checksums.sha256"; do
    [ -f "$file" ] || fail "required input missing: $file"
done

verify_manifest_hash "$boot_package" "$boot_package_manifest" output_sha256
[ "$(manifest_value external_env_required "$boot_package_manifest")" = no ] ||
    fail "boot package still requires external env"
python3 scripts/patch-v90s-uboot-default-env.py --input "$boot_package" --verify-fixed \
    >> "$report"
pass "boot package fixed environment"

verify_manifest_hash "$boot_image" "$boot_image_manifest" output_sha256
[ "$(wc -c < "$boot_image" | tr -d ' ')" -le $((64 * 1024 * 1024)) ] ||
    fail "boot image exceeds 64 MiB"
boot_image_abs="$(realpath "$boot_image")"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
(
    cd "$tmp_dir"
    abootimg -x "$boot_image_abs" >/dev/null
    mkdir ramdisk
    gzip -dc initrd.img | (cd ramdisk && cpio -idmu --quiet)
)
grep -Fq 'cmdline = console=ttyS0,115200 rootwait init=/init' "$tmp_dir/bootimg.cfg" ||
    fail "boot image cmdline does not enter provisioning init"
cmp -s scripts/v90s-four-partition-init "$tmp_dir/ramdisk/init" ||
    fail "boot image /init differs from repository provisioning init"
grep -Fq 'verify_sha256 "$SYSTEM_IMAGE" "$SYSTEM_HASH"' "$tmp_dir/ramdisk/init" ||
    fail "initramfs does not use BusyBox-compatible system hash verification"
if grep -Fq 'sha256sum -c' "$tmp_dir/ramdisk/init"; then
    fail "initramfs uses unsupported BusyBox sha256sum -c"
fi
grep -Fq '"$target/Logs/boot/$BOOT_LOG_NAME"' "$tmp_dir/ramdisk/init" ||
    fail "initramfs does not mirror boot diagnostics to PLUMOS FAT32"
grep -Fq 'BOOT_LOG_NAME=last-boot.log' "$tmp_dir/ramdisk/init" ||
    fail "initramfs does not preserve first-boot diagnostics on normal boots"
grep -Fq 'normal boot: userdata provisioning is complete' "$tmp_dir/ramdisk/init" ||
    fail "initramfs does not have a completed-provisioning fast path"
for file in tools/bin/parted tools/bin/e2fsck tools/bin/resize2fs tools/bin/mkfs.fat \
    tools/bin/fsck.fat tools/lib/ld-linux-aarch64.so.1; do
    [ -x "$tmp_dir/ramdisk/$file" ] || fail "initramfs tool missing: $file"
done
for file in progress/boot.raw progress/prepare.raw progress/resize.raw progress/userdata.raw \
    progress/verify.raw progress/mount.raw progress/start.raw progress/error.raw; do
    [ -f "$tmp_dir/ramdisk/$file" ] || fail "initramfs progress frame missing: $file"
done
for frame in "$tmp_dir"/ramdisk/progress/*.raw; do
    [ "$(wc -c < "$frame" | tr -d ' ')" -eq 2457600 ] ||
        fail "initramfs progress frame has unexpected size: $frame"
done
grep -Fq 'show_progress error' "$tmp_dir/ramdisk/init" ||
    fail "initramfs recovery progress screen is missing"
p3_start=2270208
p3_target_sectors=$((8192 * 2048))
p4_alignment_sectors=2048
p4_unaligned=$((p3_start + p3_target_sectors))
p4_aligned=$((((p4_unaligned + p4_alignment_sectors - 1) / p4_alignment_sectors) * p4_alignment_sectors))
[ $((p4_aligned % p4_alignment_sectors)) -eq 0 ] ||
    fail "calculated p4 start is not 1 MiB aligned"
grep -Fq 'if [ "$P4_CREATED" = 1 ]' "$tmp_dir/ramdisk/init" ||
    fail "newly created p4 is not forced through clean FAT32 formatting"
pass "initramfs progress screens and aligned clean p4 provisioning"
pass "p2 provisioning initramfs and storage tools"

rootfs_listing="$tmp_dir/system-rootfs.list"
unsquashfs -ll "$system_squashfs" > "$rootfs_listing"
for path in sbin usr/sbin/init usr/sbin/plumos-app-layer-bootstrap \
    etc/plumos-v90s-vendor-id mnt/plumos mnt/plumos-boot mnt/plumos-user; do
    grep -Eq "squashfs-root/$path( -> .*)?$" "$rootfs_listing" ||
        fail "system SquashFS path missing: /$path"
done
unsquashfs -cat "$system_squashfs" usr/sbin/plumos-app-layer-bootstrap \
    > "$tmp_dir/system-app-layer-bootstrap"
cmp -s scripts/plumos-app-layer-bootstrap.sh "$tmp_dir/system-app-layer-bootstrap" ||
    fail "system SquashFS app-layer bootstrap differs from repository source"
unsquashfs -cat "$system_squashfs" usr/sbin/plumos-power-action \
    > "$tmp_dir/system-power-action"
cmp -s scripts/plumos-power-action-rootfs.sh "$tmp_dir/system-power-action" ||
    fail "system SquashFS power action differs from repository source"
grep -Fq 'stop_persistent_storage_users' "$tmp_dir/system-power-action" ||
    fail "system power action does not stop p3/p4 users"
grep -Fq 'unmount_if_mounted "$PLUMOS_USER_ROOT"' "$tmp_dir/system-power-action" ||
    fail "system power action does not unmount p4"
grep -Fq 'prepare_sysrq_final_action' "$tmp_dir/system-power-action" ||
    fail "system power action does not sync and remount filesystems read-only"
pass "system SquashFS init, app bootstrap, and four-partition power action"

python3 - "$app_runtime/manifest.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    manifest = json.load(stream)
if not manifest.get("complete"):
    raise SystemExit("app runtime manifest is incomplete")
if manifest.get("mount_path") != "/mnt/plumos":
    raise SystemExit("app runtime mount path is not /mnt/plumos")
if manifest.get("libretro_core_count", 0) < manifest.get("minimum_libretro_core_count", 118):
    raise SystemExit("app runtime core inventory is incomplete")
PY
(
    cd "$app_runtime"
    sha256sum -c checksums.sha256 >/dev/null
) || fail "app runtime checksum verification failed"
pass "complete app runtime and checksums"

frontend_launch="$app_runtime/bin/plumos-frontend-launch"
sd2_mount="$app_runtime/bin/plumos-sd2-content-mount"
bootstrap="scripts/plumos-app-layer-bootstrap.sh"
for file in "$frontend_launch" "$sd2_mount" "$bootstrap" \
    "$app_runtime/bin/plumos-controller-ui-v90s"; do
    [ -x "$file" ] || fail "frontend contract executable missing: $file"
done
for file in "$frontend_launch" "$sd2_mount" "$bootstrap"; do
    sh -n "$file" 2>/dev/null || fail "shell syntax failed: $file"
done
grep -Fq 'PLUMOS_SD2_FSCK_TIMEOUT' "$sd2_mount" || fail "SD2 fsck timeout is missing"
grep -Fq '/dev/mmcblk[1-9]p*' "$sd2_mount" || fail "SD2 device scan is missing"
grep -Fq 'bind_content_dir "$rom_src" "$PLUMOS_ROOT/roms"' "$sd2_mount" ||
    fail "SD2 ROM bind contract is missing"
grep -Fq 'bind_content_dir "$bios_src" "$PLUMOS_ROOT/bios"' "$sd2_mount" ||
    fail "SD2 BIOS bind contract is missing"
grep -Fq 'restore_userdata_dir "$USERDATA_ROOT/roms" "$PLUMOS_ROOT/roms" roms' "$sd2_mount" ||
    fail "SD2 stop does not restore p4 ROM content"
grep -Fq 'bind_userdata_dir "$USERDATA_ROOT/roms" "$PLUMOS_ROOT/roms"' "$bootstrap" ||
    fail "p4 ROM bind contract is missing"
grep -Fq 'bind_userdata_dir "$USERDATA_ROOT/bios" "$PLUMOS_ROOT/bios"' "$bootstrap" ||
    fail "p4 BIOS bind contract is missing"
grep -Fq 'plumos-sd2-content-mount" start' "$frontend_launch" ||
    fail "frontend launcher does not start SD2 mounting"
grep -Fq 'exec "$PLUMOS_ROOT/bin/plumos-controller-ui-v90s"' "$frontend_launch" ||
    fail "frontend launcher does not exec the validated UI"
grep -Fq 'exec "$PLUMOS_ROOT/bin/plumos-frontend-launch"' "$bootstrap" ||
    fail "system bootstrap does not exec the frontend launcher"
pass "bounded SD2 mount and single frontend exec chain"

app_used_kib="$(du -sk "$app_runtime" | awk '{print $1}')"
[ "$app_used_kib" -le $(((1536 - 256) * 1024)) ] ||
    fail "app runtime leaves less than 256 MiB in p3 seed"
pass "p3 seed capacity used_kib=$app_used_kib"

printf 'result=PASS\n' >> "$report"
printf 'preflight: PASS\n'
printf 'report: %s\n' "$report"
