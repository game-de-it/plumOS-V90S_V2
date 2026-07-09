#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage:
  scripts/v90s-collect-runtime-snapshot.sh root@IP LABEL

Collect a tolerant runtime snapshot from a booted V90S over SSH. The output is
written under output/device-logs/runtime-snapshots/LABEL/.

The command is intended for comparing the current plumOS/KNULLI-Armbian runtime
against a StockOS-based image with the same broad evidence surface:
kernel/cmdline, display timing, PowerVR, RetroArch config/logs, ALSA mixer,
input devices, processes, and selected KNULLI/EmulationStation files.
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

out_dir="output/device-logs/runtime-snapshots/$label"
mkdir -p "$out_dir"

run_remote() {
    ssh -o ConnectTimeout=8 "$target" sh -s <<'REMOTE'
set +e

section() {
    printf '\n===== %s =====\n' "$1"
}

run() {
    title="$1"
    shift
    section "$title"
    "$@" 2>&1
    printf '===== %s rc=%s =====\n' "$title" "$?"
}

run_sh() {
    title="$1"
    script="$2"
    section "$title"
    sh -c "$script" 2>&1
    printf '===== %s rc=%s =====\n' "$title" "$?"
}

section "snapshot-meta"
date
hostname 2>/dev/null
id
pwd

run "uname" uname -a
run_sh "os-release" 'cat /etc/os-release 2>/dev/null || cat /usr/lib/os-release 2>/dev/null || true'
run_sh "cmdline" 'cat /proc/cmdline 2>/dev/null || true'
run_sh "mounts" 'cat /proc/mounts 2>/dev/null || mount 2>/dev/null || true'
run_sh "df" 'df -h 2>/dev/null || true'
run_sh "partitions" 'cat /proc/partitions 2>/dev/null || true; lsblk -f 2>/dev/null || true; blkid 2>/dev/null || true'
run_sh "processes" 'ps -eo pid,ppid,stat,comm,args 2>/dev/null || ps 2>/dev/null || true'
run_sh "meminfo" 'cat /proc/meminfo 2>/dev/null || true'
run_sh "cpu" 'cat /proc/cpuinfo 2>/dev/null || true; for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq /sys/devices/system/cpu/cpu*/cpufreq/scaling_min_freq /sys/devices/system/cpu/cpu*/cpufreq/scaling_max_freq; do [ -e "$f" ] && printf "%s=%s\n" "$f" "$(cat "$f" 2>/dev/null)"; done'
run_sh "modules" 'cat /proc/modules 2>/dev/null || lsmod 2>/dev/null || true'
run_sh "interrupts-key" 'cat /proc/interrupts 2>/dev/null | grep -Ei "disp|pvr|rgx|gpu|mali|snd|audio|timer|mmc|usb|ohci|ehci|xhci|gpio|adc" || cat /proc/interrupts 2>/dev/null || true'
run_sh "interrupt-rate-10s" 'sample() { key="$1"; awk -v key="$key" '\''$0 ~ key { s=0; for (i=2; i<=NF; i++) if ($i ~ /^[0-9]+$/) s+=$i; print s; found=1 } END { if (!found) print "" }'\'' /proc/interrupts 2>/dev/null; }; uptime_now() { awk '\''{ print $1 }'\'' /proc/uptime 2>/dev/null; }; d0=$(sample "dispaly|display"); p0=$(sample "pvrsrvkm|pvr|rgx"); t0=$(uptime_now); sleep 10; d1=$(sample "dispaly|display"); p1=$(sample "pvrsrvkm|pvr|rgx"); t1=$(uptime_now); echo "display_before=$d0 display_after=$d1"; echo "pvr_before=$p0 pvr_after=$p1"; awk -v t0="$t0" -v t1="$t1" "BEGIN { printf \"sample_seconds=%.2f\\n\", t1-t0 }"; if [ -n "$d0" ] && [ -n "$d1" ]; then awk -v a="$d0" -v b="$d1" -v t0="$t0" -v t1="$t1" "BEGIN { dt=t1-t0; if (dt > 0) printf \"display_delta=%d display_hz=%.5f\\n\", b-a, (b-a)/dt }"; fi; if [ -n "$p0" ] && [ -n "$p1" ]; then awk -v a="$p0" -v b="$p1" -v t0="$t0" -v t1="$t1" "BEGIN { dt=t1-t0; if (dt > 0) printf \"pvr_delta=%d pvr_hz=%.5f\\n\", b-a, (b-a)/dt }"; fi'
run_sh "display-sysfs" 'for f in /sys/class/graphics/fb*/name /sys/class/graphics/fb*/modes /sys/class/graphics/fb*/mode /sys/class/graphics/fb*/virtual_size /sys/class/graphics/fb*/bits_per_pixel /sys/class/graphics/fb*/stride /sys/class/graphics/fb*/blank /sys/class/drm/*/status /sys/class/drm/*/modes; do [ -e "$f" ] && printf "%s=%s\n" "$f" "$(cat "$f" 2>/dev/null | tr "\n" " ")"; done'
run_sh "framebuffer-devices" 'ls -l /dev/fb* /dev/dri/* 2>/dev/null || true'
run_sh "input-devices" 'cat /proc/bus/input/devices 2>/dev/null || true; ls -l /dev/input 2>/dev/null || true'
run_sh "sound-devices" 'cat /proc/asound/cards 2>/dev/null || true; cat /proc/asound/devices 2>/dev/null || true; cat /proc/asound/pcm 2>/dev/null || true; aplay -l 2>/dev/null || true'
run_sh "alsa-pcm-status" 'for f in /proc/asound/card*/pcm*/sub*/status; do [ -e "$f" ] && echo "--- $f" && cat "$f"; done'
run_sh "amixer" 'amixer contents 2>/dev/null || amixer scontents 2>/dev/null || true'
run_sh "pulse-pipewire" 'command -v pactl >/dev/null 2>&1 && { pactl info 2>&1; pactl list short sinks 2>&1; pactl list short sink-inputs 2>&1; pactl list sink-inputs 2>&1 | sed -n "1,220p"; } || true'
run_sh "pvr-status" 'for d in /lib/modules/$(uname -r) /usr/lib/modules/$(uname -r) /lib/modules/4.9.191; do [ -d "$d" ] && echo "module-dir=$d"; done; command -v pvrsrvctl >/dev/null 2>&1 && pvrsrvctl --status || true; command -v rgx_compute_test >/dev/null 2>&1 && rgx_compute_test -f 1 || true'
run_sh "retroarch-version" 'ra_env="/usr/lib/powervr:/usr/local/lib/plumos-sdl2-mali:/usr/lib/aarch64-linux-gnu:/usr/lib:/usr/local/lib/plumos-sdl2-mali:$LD_LIBRARY_PATH"; for b in retroarch /usr/bin/retroarch /usr/local/bin/retroarch /tmp/retroarch-knulli; do if command -v "$b" >/dev/null 2>&1 || [ -x "$b" ]; then echo "--- $b plain"; "$b" --version 2>&1; echo "--- $b pvr-env"; env LD_LIBRARY_PATH="$ra_env" "$b" --version 2>&1; fi; done'
run_sh "retroarch-features" 'ra_env="/usr/lib/powervr:/usr/local/lib/plumos-sdl2-mali:/usr/lib/aarch64-linux-gnu:/usr/lib:/usr/local/lib/plumos-sdl2-mali:$LD_LIBRARY_PATH"; for b in retroarch /usr/bin/retroarch /usr/local/bin/retroarch /tmp/retroarch-knulli; do if command -v "$b" >/dev/null 2>&1 || [ -x "$b" ]; then echo "--- $b plain"; "$b" --features 2>&1; echo "--- $b pvr-env"; env LD_LIBRARY_PATH="$ra_env" "$b" --features 2>&1; fi; done'
run_sh "retroarch-configs" 'for f in /mnt/share/retroarch/retroarch-v90s.cfg /tmp/retroarch-v90s.cfg /storage/.config/retroarch/retroarch.cfg /userdata/system/configs/retroarch/retroarchcustom.cfg /userdata/system/configs/retroarch/retroarch.cfg /usr/share/knulli/datainit/system/configs/retroarch/retroarch.cfg /etc/retroarch.cfg /root/.config/retroarch/retroarch.cfg; do [ -f "$f" ] && echo "--- $f" && grep -n -E "^(video_driver|video_context_driver|video_refresh_rate|video_vsync|vrr_runloop_enable|video_threaded|video_hard_sync|video_swap_interval|video_shader_enable|audio_driver|audio_device|audio_sync|audio_latency|audio_rate_control|audio_rate_control_delta|audio_max_timing_skew|audio_out_rate|input_driver|input_joypad_driver|fps_show)" "$f"; done'
run_sh "retroarch-logs" 'for f in /boot/plumos-logs/plumos-v90s-retroarch.log /mnt/share/plumos-v90s-retroarch.log /tmp/plumos-v90s-retroarch.log /storage/.config/retroarch/logs/retroarch.log /userdata/system/logs/retroarch.log /var/log/retroarch.log; do [ -f "$f" ] && echo "--- $f" && tail -220 "$f"; done'
run_sh "knulli-configs" 'for f in /etc/plumos-v90s-retroarch-route /etc/asound.conf /root/.asoundrc /boot/asound.state /userdata/system/.asoundrc /userdata/system/configs/emulationstation/es_settings.cfg /storage/.config/emulationstation/es_settings.cfg; do [ -f "$f" ] && echo "--- $f" && sed -n "1,220p" "$f"; done'
run_sh "find-runtime-files" 'for d in /boot /mnt/share /userdata /storage /roms /etc /usr/share/knulli; do [ -d "$d" ] && echo "--- $d" && find "$d" -maxdepth 3 -type f \( -iname "*retroarch*" -o -iname "*asound*" -o -iname "*es_*" -o -iname "*configgen*" \) 2>/dev/null | sort | head -200; done'
run_sh "dmesg-tail" 'dmesg 2>/dev/null | tail -260 || true'
REMOTE
}

snapshot_file="$out_dir/snapshot.txt"
run_remote | tee "$snapshot_file"

sha256sum "$snapshot_file" > "$out_dir/SHA256SUMS"
printf 'snapshot=%s\n' "$snapshot_file"
