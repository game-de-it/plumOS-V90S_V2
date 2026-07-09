#!/usr/bin/env sh
set -eu

profile="all"
suite="bookworm"
mirror="http://deb.debian.org/debian"
out_dir="output/rootfs-step1"
knulli_ramdisk=".cache/v90s-ramdisk"
knulli_a133_overlay=".cache/knulli-linux/board/allwinner/a133/fsoverlay"
pvr_dir=".cache/ge8300-drivers"
sdl2_mali_dir="output/sdl2-mali"
quicknes_dir="output/libretro-quicknes"
keep_work=0
rom_path=""
wifi_ssid="${PLUMOS_V90S_WIFI_SSID:-}"
wifi_psk="${PLUMOS_V90S_WIFI_PSK:-}"
ssh_authorized_keys="${PLUMOS_V90S_SSH_AUTHORIZED_KEYS:-}"
ssh_root_password="${PLUMOS_V90S_SSH_ROOT_PASSWORD:-}"
script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

usage() {
    cat <<'USAGE'
Usage:
  build-step1-rootfs.sh [options]

Options:
  --profile NAME        all, stage1, debian-minbase, debian-retroarch,
                        debian-retroarch-pvr-probe, or debian-retroarch-pvr-sdl2; default all
  --suite NAME          Debian suite for debootstrap, default bookworm
  --mirror URL          Debian mirror, default http://deb.debian.org/debian
  --out-dir PATH        output directory, default output/rootfs-step1
  --knulli-ramdisk PATH extracted KNULLI ramdisk, default .cache/v90s-ramdisk
  --knulli-a133-overlay PATH KNULLI a133 fsoverlay, default .cache/knulli-linux/board/allwinner/a133/fsoverlay
  --pvr-dir PATH        GE8300 driver checkout, default .cache/ge8300-drivers
  --sdl2-mali-dir PATH  patched SDL2 payload, default output/sdl2-mali
  --quicknes-dir PATH   QuickNES libretro payload, default output/libretro-quicknes
  --rom PATH            NES ROM to copy into debian-retroarch payload
  --wifi-ssid SSID      configure Wi-Fi SSID in the generated payload
  --wifi-psk PSK        configure Wi-Fi WPA/WPA2 passphrase in the generated payload
  --ssh-authorized-keys PATH
                        copy public keys to /root/.ssh/authorized_keys
  --ssh-root-password PASSWORD
                        set root password for SSH password authentication
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
        --knulli-a133-overlay)
            knulli_a133_overlay="$2"
            shift 2
            ;;
        --pvr-dir)
            pvr_dir="$2"
            shift 2
            ;;
        --sdl2-mali-dir)
            sdl2_mali_dir="$2"
            shift 2
            ;;
        --quicknes-dir)
            quicknes_dir="$2"
            shift 2
            ;;
        --rom)
            rom_path="$2"
            shift 2
            ;;
        --wifi-ssid)
            wifi_ssid="$2"
            shift 2
            ;;
        --wifi-psk)
            wifi_psk="$2"
            shift 2
            ;;
        --ssh-authorized-keys)
            ssh_authorized_keys="$2"
            shift 2
            ;;
        --ssh-root-password)
            ssh_root_password="$2"
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
    all|stage1|debian-minbase|debian-retroarch|debian-retroarch-pvr-probe|debian-retroarch-pvr-sdl2)
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

if [ "$profile" = "all" ] || [ "$profile" = "debian-minbase" ] || [ "$profile" = "debian-retroarch" ] || [ "$profile" = "debian-retroarch-pvr-probe" ] || [ "$profile" = "debian-retroarch-pvr-sdl2" ]; then
    if ! command -v debootstrap >/dev/null 2>&1; then
        printf 'error: debootstrap is required for profile %s\n' "$profile" >&2
        exit 1
    fi
fi

if [ "$profile" = "debian-retroarch" ] || [ "$profile" = "debian-retroarch-pvr-probe" ] || [ "$profile" = "debian-retroarch-pvr-sdl2" ]; then
    if [ -z "$rom_path" ]; then
        printf 'error: --rom is required for profile %s\n' "$profile" >&2
        exit 2
    fi
    if [ ! -f "$rom_path" ]; then
        printf 'error: ROM not found: %s\n' "$rom_path" >&2
        exit 1
    fi
    if [ ! -f "$quicknes_dir/quicknes_libretro.so" ]; then
        printf 'error: QuickNES libretro core not found: %s/quicknes_libretro.so\n' "$quicknes_dir" >&2
        printf 'hint: run ./scripts/build-libretro-quicknes.sh first\n' >&2
        exit 1
    fi
fi

if [ "$profile" = "debian-retroarch-pvr-probe" ] || [ "$profile" = "debian-retroarch-pvr-sdl2" ]; then
    if [ ! -d "$pvr_dir/fbdev/glibc/lib64" ] || [ ! -x "$pvr_dir/fbdev/glibc/bin/pvrsrvctl" ]; then
        printf 'error: GE8300 fbdev/glibc driver payload not found under: %s\n' "$pvr_dir" >&2
        exit 1
    fi
    if [ ! -f "$knulli_a133_overlay/lib/modules/4.9.191_v90s/pvrsrvkm.ko" ] || [ ! -f "$knulli_a133_overlay/lib/modules/4.9.191_v90s/dc_sunxi.ko" ]; then
        printf 'error: KNULLI a133 PowerVR modules not found under: %s\n' "$knulli_a133_overlay" >&2
        exit 1
    fi
fi

if [ "$profile" = "debian-retroarch-pvr-sdl2" ]; then
    if [ ! -f "$sdl2_mali_dir/usr/local/lib/plumos-sdl2-mali/libSDL2-2.0.so.0" ] || [ ! -x "$sdl2_mali_dir/usr/local/bin/v90s-sdl2-video-probe" ]; then
        printf 'error: patched SDL2 mali payload not found under: %s\n' "$sdl2_mali_dir" >&2
        printf 'hint: run ./scripts/run-assembly-tools.sh ./scripts/build-sdl2-mali.sh first\n' >&2
        exit 1
    fi
fi

if { [ -n "$wifi_ssid" ] && [ -z "$wifi_psk" ]; } || { [ -z "$wifi_ssid" ] && [ -n "$wifi_psk" ]; }; then
    printf 'error: --wifi-ssid and --wifi-psk must be provided together\n' >&2
    exit 2
fi

if [ -n "$ssh_authorized_keys" ] && [ ! -f "$ssh_authorized_keys" ]; then
    printf 'error: SSH authorized_keys source not found: %s\n' "$ssh_authorized_keys" >&2
    exit 1
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
FAT_LOG_DIR=

log() {
    echo "$*"
    echo "$*" >> "$LOG"
}

prepare_fat_logs() {
    mkdir -p /boot 2>/dev/null || true

    if [ -f /boot/knulli-boot.conf ] || [ -f /boot/boot/knulli ]; then
        mount -o remount,rw /boot 2>/dev/null || true
    else
        for dev in /dev/mmcblk0p4 /dev/mmcblk1p4; do
            [ -b "$dev" ] || continue
            mount -t vfat -o rw "$dev" /boot 2>/dev/null && break
        done
    fi

    if mkdir -p /boot/plumos-logs 2>/dev/null; then
        FAT_LOG_DIR=/boot/plumos-logs
        rm -f "$FAT_LOG_DIR"/plumos-v90s-*.log 2>/dev/null || true
        {
            echo "plumOS V90S boot log session"
            date 2>/dev/null || true
        } > "$FAT_LOG_DIR/session.txt" 2>/dev/null || true
        sync
    fi
}

copy_to_fat_logs() {
    [ -n "$FAT_LOG_DIR" ] || return 0
    [ -d "$FAT_LOG_DIR" ] || return 0

    cp "$LOG" "$FAT_LOG_DIR/plumos-v90s-debian-init.log" 2>/dev/null || true
    if [ -f /mnt/share/plumos-v90s-diag.log ]; then
        cp /mnt/share/plumos-v90s-diag.log "$FAT_LOG_DIR/plumos-v90s-diag.log" 2>/dev/null || true
    fi
    if [ -f /mnt/share/plumos-v90s-fb-console.log ]; then
        cp /mnt/share/plumos-v90s-fb-console.log "$FAT_LOG_DIR/plumos-v90s-fb-console.log" 2>/dev/null || true
    fi
    if [ -f /mnt/share/plumos-v90s-retroarch-launch.log ]; then
        cp /mnt/share/plumos-v90s-retroarch-launch.log "$FAT_LOG_DIR/plumos-v90s-retroarch-launch.log" 2>/dev/null || true
    fi
    if [ -f /mnt/share/plumos-v90s-retroarch.log ]; then
        cp /mnt/share/plumos-v90s-retroarch.log "$FAT_LOG_DIR/plumos-v90s-retroarch.log" 2>/dev/null || true
    fi
    if [ -f /mnt/share/plumos-v90s-pvr-probe.log ]; then
        cp /mnt/share/plumos-v90s-pvr-probe.log "$FAT_LOG_DIR/plumos-v90s-pvr-probe.log" 2>/dev/null || true
    fi
    if [ -f /mnt/share/plumos-v90s-network-ssh.log ]; then
        cp /mnt/share/plumos-v90s-network-ssh.log "$FAT_LOG_DIR/plumos-v90s-network-ssh.log" 2>/dev/null || true
    fi
    sync
}

persist_debian_log() {
    if [ -d /mnt/share ]; then
        cp "$LOG" /mnt/share/plumos-v90s-debian-init.log 2>/dev/null || true
        if [ -d /mnt/share/rootfs ]; then
            cp "$LOG" /mnt/share/rootfs/plumos-v90s-debian-init.log 2>/dev/null || true
        fi
        sync
    fi
    copy_to_fat_logs
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
prepare_fat_logs

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

if [ -x /usr/local/sbin/v90s-pvr-probe ]; then
    log "debian-init: starting PowerVR probe"
    persist_debian_log
    sync
    /usr/local/sbin/v90s-pvr-probe
    rc=$?
    log "debian-init: PowerVR probe exited rc=$rc"
    persist_debian_log
fi

if [ -x /usr/local/sbin/v90s-network-ssh-init ]; then
    log "debian-init: starting network/SSH init"
    persist_debian_log
    sync
    /usr/local/sbin/v90s-network-ssh-init
    rc=$?
    log "debian-init: network/SSH init exited rc=$rc"
    persist_debian_log
fi

if [ -x /usr/local/sbin/v90s-retroarch-launch ]; then
    log "debian-init: starting RetroArch launcher"
    persist_debian_log
    sync
    /usr/local/sbin/v90s-retroarch-launch
    rc=$?
    log "debian-init: RetroArch launcher exited rc=$rc"
    persist_debian_log
fi

if [ -x /usr/local/sbin/v90s-fb-console ]; then
    console_log=/tmp/plumos-v90s-fb-console.log
    if [ -d /mnt/share ]; then
        console_log=/mnt/share/plumos-v90s-fb-console.log
        : > "$console_log" 2>/dev/null || true
        if [ -d /mnt/share/rootfs ]; then
            : > /mnt/share/rootfs/plumos-v90s-fb-console.log 2>/dev/null || true
        fi
    fi
    if [ -n "$FAT_LOG_DIR" ]; then
        : > "$FAT_LOG_DIR/plumos-v90s-fb-console.log" 2>/dev/null || true
    fi

    log "debian-init: checking framebuffer console"
    if command -v perl >/dev/null 2>&1; then
        /usr/bin/perl -c /usr/local/sbin/v90s-fb-console >> "$console_log" 2>&1
        log "debian-init: framebuffer console perl-check rc=$?"
    else
        log "debian-init: perl not found"
    fi
    if [ -f "$console_log" ] && [ -d /mnt/share/rootfs ]; then
        cp "$console_log" /mnt/share/rootfs/plumos-v90s-fb-console.log 2>/dev/null || true
    fi
    copy_to_fat_logs

    log "debian-init: starting framebuffer console"
    persist_debian_log
    sync
    /usr/local/sbin/v90s-fb-console >> "$console_log" 2>&1
    rc=$?
    log "debian-init: framebuffer console exited rc=$rc"
    if [ -f "$console_log" ] && [ -d /mnt/share/rootfs ]; then
        cp "$console_log" /mnt/share/rootfs/plumos-v90s-fb-console.log 2>/dev/null || true
    fi
    persist_debian_log
fi

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
    install -D -m 0755 "$script_dir/v90s-fb-console.pl" "$root/usr/local/sbin/v90s-fb-console"
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

install_pvr_probe() {
    root="$1"
    pvr_standard_module_src="$knulli_a133_overlay/lib/modules/4.9.191"
    pvr_module_src="$knulli_a133_overlay/lib/modules/4.9.191_v90s"

    install -D -m 0755 "$script_dir/v90s-pvr-probe.sh" "$root/usr/local/sbin/v90s-pvr-probe"

    mkdir -p "$root/usr/bin" "$root/usr/lib/powervr" "$root/lib/firmware" "$root/lib/modules/4.9.191"
    cp -a "$pvr_dir/fbdev/glibc/lib64/." "$root/usr/lib/powervr/"
    install -m 0755 "$pvr_dir/fbdev/glibc/bin/pvrsrvctl" "$root/usr/bin/pvrsrvctl"
    if [ -x "$pvr_dir/fbdev/glibc/bin/ocl_unit_test" ]; then
        install -m 0755 "$pvr_dir/fbdev/glibc/bin/ocl_unit_test" "$root/usr/bin/ocl_unit_test"
    fi

    cp -a "$pvr_dir/fbdev/glibc/lib64/firmware/." "$root/lib/firmware/" 2>/dev/null || true
    cp -a "$knulli_a133_overlay/lib/firmware/." "$root/lib/firmware/" 2>/dev/null || true

    if [ -d "$pvr_standard_module_src" ]; then
        cp -a "$pvr_standard_module_src/." "$root/lib/modules/4.9.191/"
        [ -f "$pvr_standard_module_src/modules.alias" ] && install -m 0644 "$pvr_standard_module_src/modules.alias" "$root/lib/modules/4.9.191/modules.alias.standard"
    fi
    cp -a "$pvr_module_src/." "$root/lib/modules/4.9.191/"
    [ -f "$pvr_module_src/modules.alias" ] && install -m 0644 "$pvr_module_src/modules.alias" "$root/lib/modules/4.9.191/modules.alias.v90s"

    mkdir -p "$root/etc/ld.so.conf.d"
    printf '/usr/lib/powervr\n' > "$root/etc/ld.so.conf.d/powervr.conf"
}

install_sdl2_mali() {
    root="$1"

    mkdir -p "$root/usr/local" "$root/etc"
    cp -a "$sdl2_mali_dir/usr/local/." "$root/usr/local/"
    if [ -f "$sdl2_mali_dir/manifest.txt" ]; then
        install -m 0644 "$sdl2_mali_dir/manifest.txt" "$root/etc/plumos-sdl2-mali-manifest.txt"
    fi
    if [ -f "$sdl2_mali_dir/SHA256SUMS" ]; then
        install -m 0644 "$sdl2_mali_dir/SHA256SUMS" "$root/etc/plumos-sdl2-mali-SHA256SUMS"
    fi
}

escape_wpa_value() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

install_network_ssh() {
    root="$1"

    install -D -m 0755 "$script_dir/v90s-network-ssh-init.sh" "$root/usr/local/sbin/v90s-network-ssh-init"

    mkdir -p "$root/etc/ssh/sshd_config.d" "$root/root/.ssh" "$root/etc/plumos-network"
    cat > "$root/etc/ssh/sshd_config.d/plumos-v90s.conf" <<'EOF'
PermitRootLogin yes
PasswordAuthentication yes
PubkeyAuthentication yes
KbdInteractiveAuthentication yes
UsePAM no
PermitEmptyPasswords no
AuthorizedKeysFile .ssh/authorized_keys
EOF

    if [ -n "$ssh_authorized_keys" ]; then
        install -m 0600 "$ssh_authorized_keys" "$root/root/.ssh/authorized_keys"
    fi
    chmod 0700 "$root/root/.ssh"

    if [ -n "$ssh_root_password" ]; then
        root_hash="$(openssl passwd -6 "$ssh_root_password")"
        awk -F: -v OFS=: -v hash="$root_hash" '
            $1 == "root" { $2 = hash }
            { print }
        ' "$root/etc/shadow" > "$root/etc/shadow.tmp"
        mv "$root/etc/shadow.tmp" "$root/etc/shadow"
        chmod 0640 "$root/etc/shadow"
    fi

    if [ -n "$wifi_ssid" ]; then
        mkdir -p "$root/etc/wpa_supplicant"
        escaped_ssid="$(escape_wpa_value "$wifi_ssid")"
        escaped_psk="$(escape_wpa_value "$wifi_psk")"
        cat > "$root/etc/wpa_supplicant/wpa_supplicant.conf" <<EOF
ctrl_interface=/run/wpa_supplicant
update_config=0
country=JP

network={
    ssid="$escaped_ssid"
    psk="$escaped_psk"
    key_mgmt=WPA-PSK
}
EOF
        chmod 0600 "$root/etc/wpa_supplicant/wpa_supplicant.conf"
    fi

    cat > "$root/etc/plumos-network-release" <<EOF
name=plumOS V90S network SSH payload
wifi_configured=$([ -n "$wifi_ssid" ] && printf yes || printf no)
ssh_authorized_keys=$([ -n "$ssh_authorized_keys" ] && printf yes || printf no)
ssh_password_auth=$([ -n "$ssh_root_password" ] && printf yes || printf no)
EOF
}

build_debian_retroarch_payload() {
    payload_suffix="$1"
    profile_name="$2"
    include_pvr="$3"
    include_sdl2_mali="${4:-0}"
    root="$work_dir/${profile_name}-root"
    rm -rf "$root"
    mkdir -p "$root"

    retroarch_packages="retroarch,alsa-utils,input-utils,procps,psmisc,kmod"
    if [ -n "$wifi_ssid" ] || [ -n "$ssh_authorized_keys" ] || [ -n "$ssh_root_password" ]; then
        retroarch_packages="${retroarch_packages},openssh-server,wpasupplicant,isc-dhcp-client,iproute2,rfkill,iw,usbutils,wireless-regdb,ca-certificates"
    fi
    debootstrap --arch=arm64 --variant=minbase --include="$retroarch_packages" "$suite" "$root" "$mirror"

    mkdir -p "$root/proc" "$root/sys" "$root/dev" "$root/run" "$root/tmp" "$root/boot" "$root/mnt/share" "$root/root" "$root/roms/nes"
    write_debian_init "$root/sbin/init"
    install -D -m 0755 "$script_dir/v90s-fb-console.pl" "$root/usr/local/sbin/v90s-fb-console"
    install -D -m 0755 "$script_dir/v90s-retroarch-launch.sh" "$root/usr/local/sbin/v90s-retroarch-launch"
    install -D -m 0755 "$script_dir/v90s-retroarch-stop.sh" "$root/usr/local/sbin/v90s-retroarch-stop"
    install -D -m 0755 "$script_dir/v90s-audio-diagnostic.sh" "$root/usr/local/sbin/v90s-audio-diagnostic"
    install -D -m 0644 "$quicknes_dir/quicknes_libretro.so" "$root/usr/lib/aarch64-linux-gnu/libretro/quicknes_libretro.so"
    if [ -f "$quicknes_dir/quicknes-manifest.txt" ]; then
        install -D -m 0644 "$quicknes_dir/quicknes-manifest.txt" "$root/etc/plumos-libretro-quicknes-manifest.txt"
    fi
    if [ "$include_pvr" -eq 1 ]; then
        install_pvr_probe "$root"
    fi
    if [ "$include_sdl2_mali" -eq 1 ]; then
        install_sdl2_mali "$root"
    fi
    if [ -n "$wifi_ssid" ] || [ -n "$ssh_authorized_keys" ] || [ -n "$ssh_root_password" ]; then
        install_network_ssh "$root"
    fi
    install -m 0644 "$rom_path" "$root/roms/nes/Super Mario Bros..nes"
    printf 'plumos-v90s-step2\n' > "$root/etc/hostname"
    rom_sha256="$(sha256sum "$rom_path" | awk '{print $1}')"
    quicknes_sha256="$(sha256sum "$quicknes_dir/quicknes_libretro.so" | awk '{print $1}')"
    cat > "$root/etc/plumos-step2-release" <<EOF
name=plumOS V90S Step2 RetroArch Debian payload
suite=$suite
mirror=$mirror
rootfs_profile=$profile_name
packages=$retroarch_packages
power_pvr_probe=$include_pvr
custom_sdl2_mali=$include_sdl2_mali
quicknes_core=/usr/lib/aarch64-linux-gnu/libretro/quicknes_libretro.so
quicknes_sha256=$quicknes_sha256
rom_path=/roms/nes/Super Mario Bros..nes
rom_sha256=$rom_sha256
EOF

    rm -rf "$root/var/cache/apt/archives/"*.deb "$root/var/lib/apt/lists/"*
    rm -rf "$root/usr/share/doc" "$root/usr/share/man" "$root/usr/share/info" "$root/usr/share/lintian" "$root/usr/share/locale"

    mksquashfs "$root" "$out_dir/debian-${suite}-${payload_suffix}.squashfs" -noappend -comp zstd -b 131072
    sha256sum "$out_dir/debian-${suite}-${payload_suffix}.squashfs" > "$out_dir/debian-${suite}-${payload_suffix}.squashfs.sha256"
    du -sh "$root" > "$out_dir/debian-${suite}-${payload_suffix}-root.du.txt"
    find "$root" -maxdepth 2 -type f | sed "s#^$root/##" | sort > "$out_dir/debian-${suite}-${payload_suffix}-manifest-depth2.txt"
    find "$root/usr/lib" "$root/usr/share/libretro" -maxdepth 5 -type f 2>/dev/null | sed "s#^$root/##" | sort > "$out_dir/debian-${suite}-${payload_suffix}-runtime-files.txt"
    printf 'created: %s/debian-%s-%s.squashfs\n' "$out_dir" "$suite" "$payload_suffix"
}

build_debian_retroarch() {
    build_debian_retroarch_payload "retroarch-step2" "debian-retroarch" 0 0
}

build_debian_retroarch_pvr_probe() {
    build_debian_retroarch_payload "retroarch-pvr-probe-step2" "debian-retroarch-pvr-probe" 1 0
}

build_debian_retroarch_pvr_sdl2() {
    build_debian_retroarch_payload "retroarch-pvr-sdl2-step2" "debian-retroarch-pvr-sdl2" 1 1
}

if [ "$profile" = "all" ] || [ "$profile" = "stage1" ]; then
    build_stage1
fi

if [ "$profile" = "all" ] || [ "$profile" = "debian-minbase" ]; then
    build_debian_minbase
fi

if [ "$profile" = "debian-retroarch" ]; then
    build_debian_retroarch
fi

if [ "$profile" = "debian-retroarch-pvr-probe" ]; then
    build_debian_retroarch_pvr_probe
fi

if [ "$profile" = "debian-retroarch-pvr-sdl2" ]; then
    build_debian_retroarch_pvr_sdl2
fi
