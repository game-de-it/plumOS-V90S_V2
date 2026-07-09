# Step 2 KNULLI RetroArch Image

Date: 2026-07-09

## Output

- image: `output/images/plumos-v90s-armbian-step2-20260709-9-knulli-retroarch.img`
- image sha256: `68af8bc2d8cfc712718805a26ba0d188ff18f10f0b411eaf8840634d0dc86cd9`
- image size: `581M`
- rootfs payload: `output/rootfs-step2-retroarch-knulli-ssh/debian-bookworm-retroarch-knulli-step2.squashfs`
- rootfs sha256: `fa6e7e05d0a198addab0f3f2922fed7ab77295129cdc4438ab465d78535cfb57`
- rootfs size: `447M`
- RetroArch binary: `output/retroarch-knulli/usr/local/bin/retroarch-knulli`
- RetroArch sha256: `96d830e236a92094e5aa77252f9fe7f9cac213158ca61bfab9a3f7efc3e760c5`

## Purpose

This image pivots away from tuning Debian's stock RetroArch video path and tests
a KNULLI-style RetroArch binary instead. It keeps the proven V90S runtime base:

- KNULLI boot chain and Linux 4.9.191
- KNULLI A133/V90S PowerVR modules and firmware
- GE8300 fbdev/glibc EGL/GLES userspace libraries
- patched SDL2 `mali` runtime
- KNULLI asound-state mixer setup
- KNULLI-pinned QuickNES core
- USB Wi-Fi and SSHD for live iteration

The RetroArch route is single and explicit:

```text
PLUMOS_V90S_RETROARCH_BIN=/usr/local/bin/retroarch
PLUMOS_V90S_VIDEO_DRIVER=gl
PLUMOS_V90S_VIDEO_CONTEXT_DRIVER=mali_fbdev
PLUMOS_V90S_VIDEO_THREADED=false
PLUMOS_V90S_INPUT_DRIVER=sdl2
PLUMOS_V90S_JOYPAD_DRIVER=sdl2
PLUMOS_V90S_AUDIO_DRIVER=alsa
PLUMOS_V90S_SDL_VIDEODRIVER=mali
PLUMOS_V90S_SDL_RENDER_DRIVER=software
```

## Build Notes

Wi-Fi credentials and SSH password were provided only at image build time and
are intentionally not recorded in git. The SSH authorized key source was
`/Users/example/.ssh/id_ed25519.pub`.

KNULLI's RetroArch package patches were checked, but the first patch currently
does not replay cleanly against RetroArch `v1.22.2`:

```text
000-input_sort_devices.patch
input/drivers_joypad/udev_joypad.c: patch does not apply
```

For this image, `scripts/build-retroarch-knulli.sh` builds RetroArch `v1.22.2`
without those package patches, but with KNULLI's key V90S graphics contract:

```text
--enable-mali_fbdev
--enable-egl
--enable-opengles
--enable-opengles3
--enable-sdl2
--enable-alsa
--disable-x11
--disable-wayland
--disable-kms
```

Host verification found `mali_fbdev_ctx.c` strings in the resulting ARM64
binary. `readelf` shows:

```text
NEEDED: libasound.so.2
NEEDED: libfreetype.so.6
NEEDED: libxkbcommon.so.0
NEEDED: libudev.so.1
NEEDED: libGLESv2.so.2
NEEDED: libEGL.so.1
NEEDED: libSDL2-2.0.so.0
RUNPATH: /usr/lib/powervr:/usr/local/lib/plumos-sdl2-mali
```

The generated squashfs contains:

```text
/usr/local/bin/retroarch -> retroarch-knulli
/usr/local/bin/retroarch-knulli
/usr/lib/aarch64-linux-gnu/libretro/quicknes_libretro.so
/etc/plumos-v90s-retroarch-route
/etc/plumos-retroarch-knulli-manifest.txt
/usr/local/sbin/v90s-network-ssh-init
/usr/local/sbin/v90s-retroarch-launch
/usr/local/sbin/v90s-retroarch-stop
```

`assemble-v90s-image.sh` reported:

```text
boot.vfat size: 33M
userdata size: 512M
diagnostic init: scripts/v90s-diagnostic-init
```

## Expected Device Test

Boot with the USB Wi-Fi dongle attached.

Check first:

```text
/Volumes/KNULLI/plumos-logs/plumos-v90s-network-ssh.log
/Volumes/KNULLI/plumos-logs/ssh-connect.txt
/Volumes/KNULLI/plumos-logs/plumos-v90s-retroarch-launch.log
/Volumes/KNULLI/plumos-logs/plumos-v90s-retroarch.log
```

The most important result is whether `gl + mali_fbdev` produces visible video
with smoother frame pacing than the previous Debian `sdl2 + mali + software`
route. If it fails before video appears, use the RetroArch log to separate:

- missing shared library
- unavailable `mali_fbdev` context
- PowerVR init regression
- SDL2 input/audio regression
