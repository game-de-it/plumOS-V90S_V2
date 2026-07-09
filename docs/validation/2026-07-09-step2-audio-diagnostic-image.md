# Step 2 Audio Diagnostic Image

Date: 2026-07-09

## Output

- image: `output/images/plumos-v90s-armbian-step2-20260709-8-audio-diagnostic.img`
- image sha256: `21dc57e4107669b1ce28be87412d93cc2fa62181b06619e5a64d94458c2fef9e`
- image size: `581M`
- rootfs payload: `output/rootfs-step2-pvr-sdl2-audio-diag/debian-bookworm-retroarch-pvr-sdl2-step2.squashfs`
- rootfs sha256: `730362205e69a92dee287c319e9542e615a01db510ade8d2c04815730d26eac3`
- rootfs size: `449M`

## Purpose

This image keeps the proven Step 2 route:

```text
video_driver=sdl2
SDL_VIDEODRIVER=mali
SDL_RENDER_DRIVER=software
```

It adds an explicit SSH audio diagnostic command without adding automatic
runtime fallbacks:

```text
/usr/local/sbin/v90s-audio-diagnostic
```

The tool applies named KNULLI-derived mixer profiles, runs a short
`speaker-test` tone, and saves `plumos-v90s-audio-diagnostic.log` to FAT/SHARE
when those mounts are available.

## Build Notes

Wi-Fi credentials and SSH password were provided only at image build time and
are intentionally not recorded in git. The SSH authorized key source was
`/Users/example/.ssh/id_ed25519.pub`.

## Host Verification

The generated squashfs contains:

```text
/usr/local/sbin/v90s-audio-diagnostic
/usr/local/sbin/v90s-retroarch-launch
/usr/local/sbin/v90s-retroarch-stop
```

GPT layout keeps the small FAT test partition:

```text
boot-resource: 67584 sectors
userdata:      1048576 sectors
```

## Expected Live Test

After booting this image with the USB Wi-Fi dongle attached, stop RetroArch
without touching SSH:

```sh
v90s-retroarch-stop stop
```

Then run the first explicit audio checks:

```sh
v90s-audio-diagnostic profile knulli_dts_loud 10
v90s-audio-diagnostic profile headphone_hotplug 10
v90s-audio-diagnostic profile dmix_softvol 10
```

If one profile produces sustained sound, keep that profile and retest
RetroArch audio. If all profiles are silent, compare the saved codec/DAPM/GPIO
log against a real KNULLI boot or move to a boot-package codec-default patch.
