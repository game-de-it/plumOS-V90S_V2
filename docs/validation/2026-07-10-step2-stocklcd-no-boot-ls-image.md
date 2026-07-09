# Step 2 Stock LCD No Boot LS Image

Date: 2026-07-10

## Live Device Restart

The running V90S moved to:

```text
192.0.2.119
```

RetroArch had exited and only the old framebuffer console was still running:

```text
v90s-fb-console /usr/bin/perl /usr/local/sbin/v90s-fb-console
```

Restart was done over SSH with the safe stop helper followed by the launcher.
After restart:

```text
v90s-retroarch-launch
retroarch --verbose --config /tmp/retroarch-v90s.cfg -L /usr/lib/aarch64-linux-gnu/libretro/quicknes_libretro.so /roms/nes/Super Mario Bros..nes
```

The active config still contains the in-game menu bindings:

```text
input_player1_start = "enter"
input_player1_select = "rshift"
input_enable_hotkey = "rshift"
input_menu_toggle = "enter"
input_menu_toggle_gamepad_combo = "4"
```

The live rootfs is squashfs and read-only, so the updated launcher was copied to
`/tmp/v90s-retroarch-launch` for this boot only. Persistent changes require a
new SD image.

## Output

- image: `output/images/plumos-v90s-armbian-step2-20260710-4-stocklcd-no-boot-ls.img`
- image sha256: `3a2970159d6628f70323005a95dd3e39e4032cd5d32d15a9362a53ee1b657a40`
- image size: `581M`
- rootfs payload: `output/rootfs-step2-retroarch-knulli-stocklcd-no-boot-ls/debian-bookworm-retroarch-knulli-step2.squashfs`
- rootfs sha256: `9e28dcf7f4a4e8ff93a06f11849cf618f458a60a56853db2938fff67dee945d5`
- rootfs size: `447M`
- boot-resource FAT size: `33M`
- userdata size: `512M`

## Changes

The automatic framebuffer console fallback was removed from the generated
Debian `/sbin/init`. If RetroArch exits, PID 1 now logs the exit and enters an
idle loop instead of drawing a console over the display:

```text
debian-init: entering idle loop; framebuffer console fallback disabled
```

The framebuffer console script no longer runs startup commands automatically.
The previous automatic commands were removed:

```text
uname -a
ls /
ls /dev/input
```

Boot-time diagnostic scripts no longer run `ls` for directory dumps. The
remaining automatic device/path diagnostics use `find`, direct path checks, or
`/proc` reads instead.

## Verification

Syntax checks passed for the touched scripts:

```text
build-step1-rootfs.sh
v90s-diagnostic-init
v90s-retroarch-launch.sh
v90s-network-ssh-init.sh
v90s-pvr-probe.sh
v90s-fb-console.pl
```

Search over `scripts/` found no remaining automatic boot-path `ls` calls. The
only remaining match was a host-side manual inspection helper:

```text
scripts/inspect-v90s-boot-chain.sh
```

The generated rootfs was inspected directly from squashfs. The expected idle
loop was present, and the removed patterns were absent:

```text
debian-init: entering idle loop; framebuffer console fallback disabled
```

The generated image still embeds the stock KNULLI V90S boot package:

```text
stock_boot_package_cmp_rc=0
9138e92d06a77a2844fb101ec2b2fa15ef11770a901b917ccafd82275b35114e  output/boot-packages/from-image-stocklcd-no-boot-ls.fex
9138e92d06a77a2844fb101ec2b2fa15ef11770a901b917ccafd82275b35114e  .cache/knulli-linux/board/allwinner/a133/powkiddy-v90s/partitions/boot_package.fex
```

## Expected Device Test

Write `plumos-v90s-armbian-step2-20260710-4-stocklcd-no-boot-ls.img` to SD and
boot the V90S.

Primary checks:

```text
Does the KNULLI logo and RetroArch game video appear?
Does Select + Start open the RetroArch menu during gameplay?
If RetroArch exits, does the screen stay free of the old framebuffer console output?
Do FAT logs still appear under /boot/plumos-logs/?
```
