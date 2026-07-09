#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage:
  scripts/extract-v90s-stockos-runtime.sh root@IP LABEL

Extract the StockOS/Batocera runtime pieces that are useful for the V90S
Armbian migration. The output is written under artifacts/LABEL/.

The extraction intentionally avoids copying the full large squashfs rootfs. It
preserves the raw boot/env partitions and selected files needed for kernel,
driver, PowerVR, RetroArch, SDL2, ALSA, Pulse/PipeWire, and Batocera configgen
comparison.
EOF
}

if [ "$#" -ne 2 ]; then
    usage >&2
    exit 2
fi

target="$1"
label="$2"

case "$label" in
    *[!A-Za-z0-9._-]*|"")
        echo "label must contain only A-Z, a-z, 0-9, dot, underscore, or dash" >&2
        exit 2
        ;;
esac

out_dir="artifacts/$label"
if [ -e "$out_dir" ]; then
    echo "output already exists: $out_dir" >&2
    exit 1
fi

mkdir -p "$out_dir/files" "$out_dir/raw-partitions"

file_list="$out_dir/file-list.txt"
selected_tar="$out_dir/files/stockos-selected-files.tar.gz"

ssh -o ConnectTimeout=8 "$target" sh -s <<'REMOTE' | sort -u > "$file_list"
set -eu

add_existing() {
    for p in "$@"; do
        [ -e "$p" ] && printf '%s\n' "${p#/}"
    done
}

add_existing \
  /media/Volumn \
  /media/BATOCERA/boot \
  /media/BATOCERA/batocera-boot.conf \
  /media/BATOCERA/boot-custom.sh \
  /media/BATOCERA/postshare.sh \
  /media/BATOCERA/preinstall \
  /boot/boot \
  /boot/batocera-boot.conf \
  /boot/boot-custom.sh \
  /boot/postshare.sh \
  /boot/preinstall \
  /lib/modules/4.9.191 \
  /lib/firmware \
  /etc/modprobe.d \
  /etc/modules.conf \
  /etc/asound.conf \
  /etc/pulse \
  /etc/wireplumber \
  /etc/security/limits.d/25-pw-rlimits.conf \
  /usr/share/alsa/alsa.conf.d \
  /usr/share/alsa-card-profile \
  /usr/share/pipewire \
  /usr/share/wireplumber \
  /usr/share/pulseaudio \
  /usr/share/batocera/configgen \
  /usr/share/batocera/datainit/system/batocera.conf \
  /usr/share/batocera/sysconfigs/batocera.conf \
  /usr/share/batocera/batocera.version \
  /usr/share/batocera/batocera.arch \
  /usr/share/batocera/shaders/interpolation \
  /usr/share/batocera/shaders/configs/sharp-bilinear-simple \
  /usr/lib/python3.12/site-packages/configgen \
  /userdata/system/batocera.conf \
  /userdata/system/services/auto_mono_output \
  /userdata/system/configs/retroarch \
  /userdata/system/configs/emulationstation/es_features.cfg \
  /userdata/system/configs/emulationstation/es_input.cfg \
  /userdata/system/configs/emulationstation/es_settings.cfg \
  /userdata/system/logs/es_launch_stdout.log \
  /userdata/system/logs/es_launch_stderr.log

for p in \
  /usr/bin/retroarch /usr/bin/emulatorlauncher /usr/bin/evmapy /usr/bin/hotkeygen \
  /usr/bin/pipewire /usr/bin/wireplumber /usr/bin/pactl /usr/bin/pw-cli /usr/bin/pw-top \
  /usr/bin/pvrsrvctl /usr/bin/rgx_compute_test /usr/bin/eglinfo \
  /usr/lib/libretro/quicknes_libretro.so \
  /usr/lib/libEGL.so /usr/lib/libEGL.so.1 /usr/lib/libGLESv2.so /usr/lib/libGLESv2.so.2 \
  /usr/lib/libGLES_CM.so /usr/lib/libGLES_CM.so.1 /usr/lib/libIMGegl.so \
  /usr/lib/libPVROCL.so /usr/lib/libPVROCL.so.1 /usr/lib/libPVRScopeServices.so \
  /usr/lib/libpvrNULL_WSEGL.so /usr/lib/libsrv_um.so /usr/lib/libusc.so \
  /usr/lib/libdrm.so /usr/lib/libdrm.so.2 /usr/lib/libgbm.so /usr/lib/libgbm.so.1 \
  /usr/lib/libSDL2-2.0.so.0 /usr/lib/libSDL2-2.0.so.0.3000.12 \
  /usr/lib/libSDL2_gfx-1.0.so.0 /usr/lib/libSDL2_image-2.0.so.0 \
  /usr/lib/libSDL2_mixer-2.0.so.0 /usr/lib/libSDL2_net-2.0.so.0 /usr/lib/libSDL2_ttf-2.0.so.0 \
  /usr/lib/libasound.so /usr/lib/libasound.so.2 /usr/lib/libasound.so.2.0.0 \
  /usr/lib/libpulse.so /usr/lib/libpulse.so.0 /usr/lib/libpulse-simple.so.0 /usr/lib/libpulse-mainloop-glib.so.0 \
  /usr/lib/libpipewire-0.3.so /usr/lib/libpipewire-0.3.so.0
do
    if [ -e "$p" ]; then
        printf '%s\n' "${p#/}"
        if [ -L "$p" ]; then
            target_path="$(readlink -f "$p" 2>/dev/null || true)"
            [ -n "$target_path" ] && [ -e "$target_path" ] && printf '%s\n' "${target_path#/}"
        fi
    fi
done

add_existing \
  /usr/lib/alsa-lib \
  /usr/lib/pipewire-0.3 \
  /usr/lib/pulseaudio \
  /usr/lib/spa-0.2
REMOTE

ssh -o ConnectTimeout=8 "$target" "tar -czf - -C / -T -" < "$file_list" > "$selected_tar"

ssh -o ConnectTimeout=8 "$target" 'dd if=/dev/mmcblk0p2 bs=256K count=1 2>/dev/null' \
    > "$out_dir/raw-partitions/mmcblk0p2-env.bin"
ssh -o ConnectTimeout=8 "$target" 'dd if=/dev/mmcblk0p3 bs=256K count=1 2>/dev/null' \
    > "$out_dir/raw-partitions/mmcblk0p3-env-redund.bin"
ssh -o ConnectTimeout=8 "$target" 'dd if=/dev/mmcblk0p4 bs=1M count=64 2>/dev/null' \
    > "$out_dir/raw-partitions/mmcblk0p4-boot.bin"

cat > "$out_dir/README.txt" <<EOF
StockOS runtime extraction for plumOS V90S Armbian migration
Created: $(date -u '+%Y-%m-%dT%H:%M:%SZ')
Source: $target, modified StockOS / Batocera 42-dev

Contents:
- files/stockos-selected-files.tar.gz: selected boot-resource files, modules,
  firmware, PowerVR/EGL/GLES libs, SDL2, RetroArch/QuickNES,
  PipeWire/Pulse/ALSA config/libs, Batocera configgen/runtime config.
- raw-partitions/mmcblk0p2-env.bin: raw env partition.
- raw-partitions/mmcblk0p3-env-redund.bin: raw redundant env partition.
- raw-partitions/mmcblk0p4-boot.bin: raw Android boot partition.
- file-list.txt: tar member source paths.
- SHA256SUMS: checksums for this extraction.

The complete StockOS root filesystem was not copied to avoid pulling the large
squashfs image. If a missing runtime dependency appears later, extract from the
SD card or rerun SSH extraction with an expanded file list.
EOF

find "$out_dir" -type f ! -name SHA256SUMS -print0 |
    sort -z |
    xargs -0 shasum -a 256 > "$out_dir/SHA256SUMS"

printf 'created %s\n' "$out_dir"
wc -l "$file_list"
du -sh "$out_dir"
