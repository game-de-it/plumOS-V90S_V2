# Step 2 Stock LCD In-Game RetroArch Menu Image

Date: 2026-07-10

## Output

- image: `output/images/plumos-v90s-armbian-step2-20260710-3-stocklcd-game-menu.img`
- image sha256: `9d1086b464e665c540c519602e7ea0d3a4c8edcac8fb58ce4b771656b911c307`
- image size: `581M`
- rootfs payload: `output/rootfs-step2-retroarch-knulli-game-menu-stocklcd/debian-bookworm-retroarch-knulli-step2.squashfs`
- rootfs sha256: `9d593673f11f7c0694739ee4e67fae154d885f8817ab2d3fca0d1472beb8fda0`
- rootfs size: `447M`
- boot-resource FAT size: `33M`
- userdata size: `512M`

## Why

The two LCD timing images were rejected by device testing:

```text
lcd_ht=812, lcd_vt=514 -> black screen
lcd_ht=825, lcd_vt=506 -> black screen
```

This image restores the stock KNULLI boot package and keeps the game as the
normal RetroArch entrypoint. The new part is an in-game menu path so RetroArch
video/audio options can be changed on the real device while the NES content is
running.

## Runtime Route

The rootfs route is explicit:

```text
PLUMOS_V90S_RETROARCH_START_MODE=content
PLUMOS_V90S_VIDEO_DRIVER=gl
PLUMOS_V90S_VIDEO_CONTEXT_DRIVER=mali_fbdev
PLUMOS_V90S_VIDEO_THREADED=false
```

The generated RetroArch config keeps the existing controller mapping and adds a
menu combo:

```text
input_player1_start = "enter"
input_player1_select = "rshift"
input_enable_hotkey = "rshift"
input_hotkey_block_delay = "5"
input_menu_toggle = "enter"
input_menu_toggle_gamepad_combo = "4"
menu_pause_libretro = "true"
rgui_show_start_screen = "false"
```

`input_menu_toggle_gamepad_combo = "4"` is RetroArch's `Start + Select` combo.
On the V90S key route, the same action is also reachable as `Select + Start`
because Select maps to `rshift` and Start maps to `enter`.

## Stock Boot Package Verification

The image was assembled without `--boot-package`, so it should embed KNULLI's
stock V90S boot package. The raw region from the generated image was extracted
with:

```text
dd if=output/images/plumos-v90s-armbian-step2-20260710-3-stocklcd-game-menu.img \
  of=output/boot-packages/from-image-stocklcd-game-menu.fex \
  bs=512 skip=32800 count=9184
```

It matched the stock package:

```text
stock_boot_package_cmp_rc=0
9138e92d06a77a2844fb101ec2b2fa15ef11770a901b917ccafd82275b35114e  output/boot-packages/from-image-stocklcd-game-menu.fex
9138e92d06a77a2844fb101ec2b2fa15ef11770a901b917ccafd82275b35114e  .cache/knulli-linux/board/allwinner/a133/powkiddy-v90s/partitions/boot_package.fex
```

## Expected Device Test

Write `plumos-v90s-armbian-step2-20260710-3-stocklcd-game-menu.img` to SD and
boot the V90S.

Primary checks:

```text
Does the KNULLI logo and RetroArch game video appear again?
Does audio behave like the previous stock-LCD build?
During gameplay, does Select + Start open the RetroArch menu?
From a USB keyboard, does Right Shift + Enter open the RetroArch menu?
After returning from the menu, do D-pad, A/B, Start, and Select still work?
```

If the menu opens, use it to test display/video sync settings one at a time.
This image intentionally does not change the LCD timing so any new black-screen
or menu behavior should be attributed to RetroArch runtime settings first.
