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
LOG=/tmp/plumos-v90s-stage1.log

log() {
    echo "$*"
    echo "$*" >> "$LOG"
}

persist_stage1_log() {
    if [ -d /mnt/share ]; then
        $bb cp "$LOG" /mnt/share/plumos-v90s-stage1.log 2>/dev/null || true
        if [ -d /mnt/share/rootfs ]; then
            $bb cp "$LOG" /mnt/share/rootfs/plumos-v90s-stage1.log 2>/dev/null || true
        fi
        $bb sync
    fi
}

ensure_fb0_node() {
    if [ ! -c /dev/fb0 ] && [ -d /sys/class/graphics/fb0 ]; then
        $bb mknod /dev/fb0 c 29 0 2>/dev/null || true
        $bb chmod 600 /dev/fb0 2>/dev/null || true
    fi
}

fb_probe() {
    log "stage1: fb0 probe begin"
    ensure_fb0_node
    for info in /sys/class/graphics/fb0/name /sys/class/graphics/fb0/modes /sys/class/graphics/fb0/virtual_size /sys/class/graphics/fb0/bits_per_pixel /sys/class/graphics/fb0/stride; do
        if [ -r "$info" ]; then
            log "stage1: $($bb basename "$info")=$($bb cat "$info" 2>/dev/null)"
        fi
    done

    if [ ! -c /dev/fb0 ]; then
        log "stage1: /dev/fb0 not present"
        return
    fi

    if [ -w /sys/class/graphics/fb0/blank ]; then
        echo 0 > /sys/class/graphics/fb0/blank 2>/dev/null || true
        log "stage1: fb0 unblank requested"
    fi

    virtual_size="$($bb cat /sys/class/graphics/fb0/virtual_size 2>/dev/null || echo 640,480)"
    fb_width="${virtual_size%,*}"
    fb_height="${virtual_size#*,}"
    bpp="$($bb cat /sys/class/graphics/fb0/bits_per_pixel 2>/dev/null || echo 32)"
    stride="$($bb cat /sys/class/graphics/fb0/stride 2>/dev/null || echo 0)"
    case "$fb_width:$fb_height:$bpp:$stride" in
        *[!0-9:]*|*::*)
            fb_width=640
            fb_height=480
            bpp=32
            stride=2560
            ;;
    esac
    if [ "$stride" -eq 0 ]; then
        stride=$((fb_width * ((bpp + 7) / 8)))
    fi

    mode_line="$($bb cat /sys/class/graphics/fb0/modes 2>/dev/null | $bb head -n 1)"
    mode_height="${mode_line#*x}"
    mode_height="${mode_height%%[pi-]*}"
    case "$mode_height" in
        ''|*[!0-9]*) visible_height="$fb_height" ;;
    esac
    if [ -n "${mode_height:-}" ] && [ "$mode_height" -gt 0 ] 2>/dev/null; then
        visible_height="$mode_height"
    fi

    fb_bytes=$((stride * fb_height))
    fb_blocks=$((fb_bytes / 4096))
    frame_blocks=$(((stride * visible_height) / 4096))
    [ "$fb_blocks" -lt 1 ] && fb_blocks=1
    [ "$frame_blocks" -lt 1 ] && frame_blocks=1

    if $bb dd if=/dev/zero of=/dev/fb0 bs=4096 count="$fb_blocks" conv=notrunc >> "$LOG" 2>&1; then
        log "stage1: fb0 full black wrote blocks=$fb_blocks bytes=$fb_bytes"
    else
        log "stage1: fb0 full black failed"
    fi

    : > /tmp/fb-white
    i=0
    while [ "$i" -lt 32768 ]; do
        printf '\377\377\377\377' >> /tmp/fb-white
        i=$((i + 1))
    done

    if $bb dd if=/tmp/fb-white of=/dev/fb0 bs=4096 count=32 conv=notrunc >> "$LOG" 2>&1; then
        log "stage1: fb0 white band page0 wrote"
    else
        log "stage1: fb0 white band page0 failed"
    fi
    if [ "$fb_height" -gt "$visible_height" ]; then
        if $bb dd if=/tmp/fb-white of=/dev/fb0 bs=4096 count=32 seek="$frame_blocks" conv=notrunc >> "$LOG" 2>&1; then
            log "stage1: fb0 white band page1 wrote seek_blocks=$frame_blocks"
        else
            log "stage1: fb0 white band page1 failed seek_blocks=$frame_blocks"
        fi
    fi
    $bb sync
}

$bb mount -t proc proc /proc 2>/dev/null || true
$bb mount -t sysfs sysfs /sys 2>/dev/null || true
if [ ! -c /dev/console ]; then
    $bb mount -t devtmpfs devtmpfs /dev 2>/dev/null || $bb mount -t tmpfs dev /dev 2>/dev/null || true
fi
$bb mkdir -p /dev/pts /dev/shm /run /tmp /mnt/share /new_root
$bb mount -t tmpfs tmpfs /run 2>/dev/null || true
$bb mount -t tmpfs tmpfs /tmp 2>/dev/null || true
$bb mount -t devpts devpts /dev/pts 2>/dev/null || true
$bb chmod 1777 /tmp

log "stage1: init entered before tty setup"
persist_stage1_log

for tty in /dev/tty0 /dev/tty1 /dev/console /dev/ttyS0; do
    if [ -c "$tty" ]; then
        exec < "$tty" > "$tty" 2>&1
        break
    fi
done

log "plumOS V90S stage1: looking for userdata rootfs payload"

payload=""
if [ -f /mnt/share/rootfs/step1-rootfs.squashfs ]; then
    payload="/mnt/share/rootfs/step1-rootfs.squashfs"
    log "stage1: using pre-mounted payload on /mnt/share"
    persist_stage1_log
    fb_probe
    persist_stage1_log
fi

for dev in /dev/mmcblk0p5 /dev/mmcblk1p5 /dev/mmcblk2p5 /dev/mmcblk0p4 /dev/mmcblk1p4 /dev/mmcblk2p4; do
    [ -z "$payload" ] || break
    [ -b "$dev" ] || continue
    $bb umount /mnt/share 2>/dev/null || true
    if $bb mount -t ext4 -o rw "$dev" /mnt/share 2>> "$LOG" || $bb mount -t ext4 -o ro "$dev" /mnt/share 2>> "$LOG"; then
        if [ -f /mnt/share/rootfs/step1-rootfs.squashfs ]; then
            payload="/mnt/share/rootfs/step1-rootfs.squashfs"
            log "stage1: found payload on $dev"
            persist_stage1_log
            fb_probe
            persist_stage1_log
            break
        fi
        $bb umount /mnt/share 2>/dev/null || true
    fi
done

if [ -z "$payload" ]; then
    log "stage1: payload not found; dropping to shell"
    persist_stage1_log
    exec /bin/busybox sh
fi

payload_loop=/dev/loop1
[ -b "$payload_loop" ] || $bb mknod "$payload_loop" b 7 1
$bb losetup -d "$payload_loop" >/dev/null 2>&1 || true
$bb losetup "$payload_loop" "$payload" >> "$LOG" 2>&1 || {
    log "stage1: losetup failed on $payload_loop"
    persist_stage1_log
    exec /bin/busybox sh
}
log "stage1: attached payload to $payload_loop"

$bb mount -t squashfs -o ro "$payload_loop" /new_root >> "$LOG" 2>&1 || {
    log "stage1: rootfs squashfs mount failed"
    persist_stage1_log
    exec /bin/busybox sh
}
log "stage1: mounted payload rootfs"

$bb mount --move /proc /new_root/proc 2>/dev/null || true
$bb mount --move /sys /new_root/sys 2>/dev/null || true
$bb mount --move /dev /new_root/dev 2>/dev/null || true
$bb mount --move /boot /new_root/boot 2>/dev/null || true
$bb mkdir -p /new_root/mnt/share
$bb mount --move /mnt/share /new_root/mnt/share 2>/dev/null || true

log "stage1: switching to payload rootfs"
if [ -d /new_root/mnt/share ]; then
    $bb cp "$LOG" /new_root/mnt/share/plumos-v90s-stage1.log 2>/dev/null || true
    if [ -d /new_root/mnt/share/rootfs ]; then
        $bb cp "$LOG" /new_root/mnt/share/rootfs/plumos-v90s-stage1.log 2>/dev/null || true
    fi
    $bb sync
fi
exec $bb switch_root /new_root /sbin/init
log "stage1: switch_root failed"
exec /bin/busybox sh
EOF
    chmod 0755 "$init_path"
}

write_debian_init() {
    init_path="$1"
    cat > "$init_path" <<'EOF'
#!/bin/sh
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
LOG=/tmp/plumos-v90s-debian-init.log

log() {
    echo "$*"
    echo "$*" >> "$LOG"
}

persist_debian_log() {
    if [ -d /mnt/share ]; then
        cp "$LOG" /mnt/share/plumos-v90s-debian-init.log 2>/dev/null || true
        if [ -d /mnt/share/rootfs ]; then
            cp "$LOG" /mnt/share/rootfs/plumos-v90s-debian-init.log 2>/dev/null || true
        fi
        sync
    fi
}

ensure_fb0_node() {
    if [ ! -c /dev/fb0 ] && [ -d /sys/class/graphics/fb0 ]; then
        mknod /dev/fb0 c 29 0 2>/dev/null || true
        chmod 600 /dev/fb0 2>/dev/null || true
    fi
}

fb_probe() {
    log "debian-init: fb0 probe begin"
    ensure_fb0_node
    for info in /sys/class/graphics/fb0/name /sys/class/graphics/fb0/modes /sys/class/graphics/fb0/virtual_size /sys/class/graphics/fb0/bits_per_pixel /sys/class/graphics/fb0/stride; do
        if [ -r "$info" ]; then
            log "debian-init: $(basename "$info")=$(cat "$info" 2>/dev/null)"
        fi
    done

    if [ ! -c /dev/fb0 ]; then
        log "debian-init: /dev/fb0 not present"
        return
    fi

    if [ -w /sys/class/graphics/fb0/blank ]; then
        echo 0 > /sys/class/graphics/fb0/blank 2>/dev/null || true
        log "debian-init: fb0 unblank requested"
    fi

    virtual_size="$(cat /sys/class/graphics/fb0/virtual_size 2>/dev/null || echo 640,480)"
    fb_width="${virtual_size%,*}"
    fb_height="${virtual_size#*,}"
    bpp="$(cat /sys/class/graphics/fb0/bits_per_pixel 2>/dev/null || echo 32)"
    stride="$(cat /sys/class/graphics/fb0/stride 2>/dev/null || echo 0)"
    case "$fb_width:$fb_height:$bpp:$stride" in
        *[!0-9:]*|*::*)
            fb_width=640
            fb_height=480
            bpp=32
            stride=2560
            ;;
    esac
    if [ "$stride" -eq 0 ]; then
        stride=$((fb_width * ((bpp + 7) / 8)))
    fi

    mode_line="$(cat /sys/class/graphics/fb0/modes 2>/dev/null | head -n 1)"
    mode_height="${mode_line#*x}"
    mode_height="${mode_height%%[pi-]*}"
    case "$mode_height" in
        ''|*[!0-9]*) visible_height="$fb_height" ;;
    esac
    if [ -n "${mode_height:-}" ] && [ "$mode_height" -gt 0 ] 2>/dev/null; then
        visible_height="$mode_height"
    fi

    fb_bytes=$((stride * fb_height))
    fb_blocks=$((fb_bytes / 4096))
    frame_blocks=$(((stride * visible_height) / 4096))
    [ "$fb_blocks" -lt 1 ] && fb_blocks=1
    [ "$frame_blocks" -lt 1 ] && frame_blocks=1

    if dd if=/dev/zero of=/dev/fb0 bs=4096 count="$fb_blocks" conv=notrunc >> "$LOG" 2>&1; then
        log "debian-init: fb0 full black wrote blocks=$fb_blocks bytes=$fb_bytes"
    else
        log "debian-init: fb0 full black failed"
    fi

    : > /tmp/fb-white
    i=0
    while [ "$i" -lt 32768 ]; do
        printf '\377\377\377\377' >> /tmp/fb-white
        i=$((i + 1))
    done

    if dd if=/tmp/fb-white of=/dev/fb0 bs=4096 count=32 conv=notrunc >> "$LOG" 2>&1; then
        log "debian-init: fb0 white band page0 wrote"
    else
        log "debian-init: fb0 white band page0 failed"
    fi
    if [ "$fb_height" -gt "$visible_height" ]; then
        if dd if=/tmp/fb-white of=/dev/fb0 bs=4096 count=32 seek="$frame_blocks" conv=notrunc >> "$LOG" 2>&1; then
            log "debian-init: fb0 white band page1 wrote seek_blocks=$frame_blocks"
        else
            log "debian-init: fb0 white band page1 failed seek_blocks=$frame_blocks"
        fi
    fi
    sync
}

mount -t proc proc /proc 2>/dev/null || true
mount -t sysfs sysfs /sys 2>/dev/null || true
if [ ! -c /dev/console ]; then
    mount -t devtmpfs devtmpfs /dev 2>/dev/null || mount -t tmpfs dev /dev 2>/dev/null || true
fi
mkdir -p /dev/pts /dev/shm /run /tmp
mount -t tmpfs tmpfs /run 2>/dev/null || true
mount -t tmpfs tmpfs /tmp 2>/dev/null || true
mount -t devpts devpts /dev/pts 2>/dev/null || true
chmod 1777 /tmp

log "debian-init: init entered before tty setup"
persist_debian_log

for tty in /dev/tty0 /dev/tty1 /dev/console /dev/ttyS0; do
    if [ -c "$tty" ]; then
        exec < "$tty" > "$tty" 2>&1
        break
    fi
done

log "plumOS V90S Step1 Debian minbase console"
persist_debian_log
fb_probe
persist_debian_log

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
    ln -sf busybox "$root/bin/sh"
    cp -a "$knulli_ramdisk/lib/." "$root/lib/"
    if [ -d "$knulli_ramdisk/usr/lib" ]; then
        cp -a "$knulli_ramdisk/usr/lib/." "$root/usr/lib/"
    fi

    write_stage1_init "$root/sbin/init"

    mksquashfs "$root" "$out_dir/stage1-userdata-loader.squashfs" -noappend -comp zstd -b 131072 >/dev/null
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

    mksquashfs "$root" "$out_dir/debian-${suite}-minbase-step1.squashfs" -noappend -comp zstd -b 131072
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
