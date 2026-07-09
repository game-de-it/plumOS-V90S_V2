#!/usr/bin/env sh
set -eu

profile="all"
suite="bookworm"
mirror="http://deb.debian.org/debian"
out_dir="output/rootfs-step1"
knulli_ramdisk=".cache/v90s-ramdisk"
keep_work=0

usage() {
    cat <<'USAGE'
Usage:
  build-step1-rootfs.sh [options]

Options:
  --profile NAME        all, stage1, or debian-minbase; default all
  --suite NAME          Debian suite for debootstrap, default bookworm
  --mirror URL          Debian mirror, default http://deb.debian.org/debian
  --out-dir PATH        output directory, default output/rootfs-step1
  --knulli-ramdisk PATH extracted KNULLI ramdisk, default .cache/v90s-ramdisk
  --keep-work           keep temporary build directory
USAGE
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --profile)
            profile="$2"
            shift 2
            ;;
        --suite)
            suite="$2"
            shift 2
            ;;
        --mirror)
            mirror="$2"
            shift 2
            ;;
        --out-dir)
            out_dir="$2"
            shift 2
            ;;
        --knulli-ramdisk)
            knulli_ramdisk="$2"
            shift 2
            ;;
        --keep-work)
            keep_work=1
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

case "$profile" in
    all|stage1|debian-minbase)
        ;;
    *)
        printf 'error: unknown profile: %s\n' "$profile" >&2
        exit 2
        ;;
esac

if ! command -v mksquashfs >/dev/null 2>&1; then
    printf 'error: mksquashfs is required\n' >&2
    exit 1
fi

if [ "$profile" = "all" ] || [ "$profile" = "debian-minbase" ]; then
    if ! command -v debootstrap >/dev/null 2>&1; then
        printf 'error: debootstrap is required for profile %s\n' "$profile" >&2
        exit 1
    fi
fi

mkdir -p "$out_dir"
# Docker Desktop bind mounts can be nodev; debootstrap needs device nodes.
work_dir="${TMPDIR:-/tmp}/plumos-v90s-step1-rootfs.$$"
rm -rf "$work_dir"
mkdir -p "$work_dir"

cleanup() {
    if [ "$keep_work" -eq 0 ]; then
        rm -rf "$work_dir"
    else
        printf 'kept work directory: %s\n' "$work_dir"
    fi
}
trap cleanup EXIT INT TERM

write_stage1_init() {
    init_path="$1"
    cat > "$init_path" <<'EOF'
#!/bin/sh
bb=/bin/busybox
PATH=/bin:/sbin:/usr/bin:/usr/sbin
export PATH

$bb mount -t proc proc /proc 2>/dev/null || true
$bb mount -t sysfs sysfs /sys 2>/dev/null || true
$bb mount -t devtmpfs devtmpfs /dev 2>/dev/null || $bb mount -t tmpfs dev /dev 2>/dev/null || true
$bb mkdir -p /dev/pts /dev/shm /run /tmp /mnt/share /new_root
$bb mount -t devpts devpts /dev/pts 2>/dev/null || true
$bb chmod 1777 /tmp

for tty in /dev/tty0 /dev/tty1 /dev/console /dev/ttyS0; do
    if [ -c "$tty" ]; then
        exec < "$tty" > "$tty" 2>&1
        break
    fi
done

echo "plumOS V90S stage1: looking for userdata rootfs payload"

payload=""
for dev in /dev/mmcblk0p5 /dev/mmcblk1p5 /dev/mmcblk2p5 /dev/mmcblk0p4 /dev/mmcblk1p4 /dev/mmcblk2p4; do
    [ -b "$dev" ] || continue
    $bb umount /mnt/share 2>/dev/null || true
    if $bb mount -t ext4 -o ro "$dev" /mnt/share 2>/dev/null; then
        if [ -f /mnt/share/rootfs/step1-rootfs.squashfs ]; then
            payload="/mnt/share/rootfs/step1-rootfs.squashfs"
            echo "stage1: found payload on $dev"
            break
        fi
        $bb umount /mnt/share 2>/dev/null || true
    fi
done

if [ -z "$payload" ]; then
    echo "stage1: payload not found; dropping to shell"
    exec /bin/busybox sh
fi

[ -b /dev/loop0 ] || $bb mknod /dev/loop0 b 7 0
$bb losetup /dev/loop0 "$payload" || {
    echo "stage1: losetup failed"
    exec /bin/busybox sh
}

$bb mount -t squashfs -o ro /dev/loop0 /new_root || {
    echo "stage1: rootfs squashfs mount failed"
    exec /bin/busybox sh
}

$bb mount --move /proc /new_root/proc 2>/dev/null || true
$bb mount --move /sys /new_root/sys 2>/dev/null || true
$bb mount --move /dev /new_root/dev 2>/dev/null || true
$bb mount --move /boot /new_root/boot 2>/dev/null || true
$bb mkdir -p /new_root/mnt/share
$bb mount --move /mnt/share /new_root/mnt/share 2>/dev/null || true

echo "stage1: switching to payload rootfs"
exec $bb switch_root /new_root /sbin/init
echo "stage1: switch_root failed"
exec /bin/busybox sh
EOF
    chmod 0755 "$init_path"
}

write_debian_init() {
    init_path="$1"
    cat > "$init_path" <<'EOF'
#!/bin/sh
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

mount -t proc proc /proc 2>/dev/null || true
mount -t sysfs sysfs /sys 2>/dev/null || true
mount -t devtmpfs devtmpfs /dev 2>/dev/null || mount -t tmpfs dev /dev 2>/dev/null || true
mkdir -p /dev/pts /dev/shm /run /tmp
mount -t devpts devpts /dev/pts 2>/dev/null || true
chmod 1777 /tmp

for tty in /dev/tty0 /dev/tty1 /dev/console /dev/ttyS0; do
    if [ -c "$tty" ]; then
        exec < "$tty" > "$tty" 2>&1
        break
    fi
done

cat <<MSG
plumOS V90S Step1 Debian minbase console
Try:
  uname -a
  cat /proc/cmdline
  mount
  ls /
  ls /dev/input
  dmesg | tail -80
MSG

if command -v setsid >/dev/null 2>&1; then
    exec setsid /bin/sh
fi

exec /bin/sh
EOF
    chmod 0755 "$init_path"
}

build_stage1() {
    if [ ! -x "$knulli_ramdisk/bin/busybox" ]; then
        printf 'error: KNULLI ramdisk busybox not found: %s/bin/busybox\n' "$knulli_ramdisk" >&2
        printf 'hint: extract the V90S boot.img ramdisk before building stage1\n' >&2
        exit 1
    fi

    root="$work_dir/stage1-root"
    rm -rf "$root"
    mkdir -p "$root/bin" "$root/sbin" "$root/lib" "$root/usr/lib" "$root/proc" "$root/sys" "$root/dev" "$root/run" "$root/tmp" "$root/boot" "$root/mnt/share" "$root/new_root"

    cp -a "$knulli_ramdisk/bin/busybox" "$root/bin/busybox"
    cp -a "$knulli_ramdisk/lib/." "$root/lib/"
    if [ -d "$knulli_ramdisk/usr/lib" ]; then
        cp -a "$knulli_ramdisk/usr/lib/." "$root/usr/lib/"
    fi

    write_stage1_init "$root/sbin/init"

    mksquashfs "$root" "$out_dir/stage1-userdata-loader.squashfs" -noappend -comp gzip >/dev/null
    sha256sum "$out_dir/stage1-userdata-loader.squashfs" > "$out_dir/stage1-userdata-loader.squashfs.sha256"
    du -sh "$root" > "$out_dir/stage1-root.du.txt"
    printf 'created: %s/stage1-userdata-loader.squashfs\n' "$out_dir"
}

build_debian_minbase() {
    root="$work_dir/debian-minbase-root"
    rm -rf "$root"
    mkdir -p "$root"

    debootstrap --arch=arm64 --variant=minbase "$suite" "$root" "$mirror"

    mkdir -p "$root/proc" "$root/sys" "$root/dev" "$root/run" "$root/tmp" "$root/boot" "$root/mnt/share" "$root/root"
    write_debian_init "$root/sbin/init"
    printf 'plumos-v90s-step1\n' > "$root/etc/hostname"
    cat > "$root/etc/plumos-step1-release" <<EOF
name=plumOS V90S Step1 Debian minbase
suite=$suite
mirror=$mirror
rootfs_profile=debian-minbase
EOF

    rm -rf "$root/var/cache/apt/archives/"*.deb "$root/var/lib/apt/lists/"*

    mksquashfs "$root" "$out_dir/debian-${suite}-minbase-step1.squashfs" -noappend -comp gzip -b 131072
    sha256sum "$out_dir/debian-${suite}-minbase-step1.squashfs" > "$out_dir/debian-${suite}-minbase-step1.squashfs.sha256"
    du -sh "$root" > "$out_dir/debian-${suite}-minbase-root.du.txt"
    find "$root" -maxdepth 2 -type f | sed "s#^$root/##" | sort > "$out_dir/debian-${suite}-minbase-manifest-depth2.txt"
    printf 'created: %s/debian-%s-minbase-step1.squashfs\n' "$out_dir" "$suite"
}

if [ "$profile" = "all" ] || [ "$profile" = "stage1" ]; then
    build_stage1
fi

if [ "$profile" = "all" ] || [ "$profile" = "debian-minbase" ]; then
    build_debian_minbase
fi
