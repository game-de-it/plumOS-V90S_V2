# Step 2 Persistent RetroArch Config Image

Date: 2026-07-10

## Problem

RetroArch settings saved from the menu were reverting after restart. The active
launcher generated:

```text
/tmp/retroarch-v90s.cfg
config_save_on_exit = "false"
```

That config path is volatile, so even a successful menu save only affected the
current boot.

## Live Fix

The running V90S at `192.0.2.119` was updated without reflashing:

```text
/tmp/v90s-retroarch-launch
/tmp/v90s-retroarch-stop.sh
```

The current `/tmp/retroarch-v90s.cfg` was copied to:

```text
/mnt/share/retroarch/retroarch-v90s.cfg
```

The live RetroArch process was restarted with the persistent config:

```text
retroarch --verbose --config /mnt/share/retroarch/retroarch-v90s.cfg -L /usr/lib/aarch64-linux-gnu/libretro/quicknes_libretro.so /roms/nes/Super Mario Bros..nes
```

The persistent config now has:

```text
config_save_on_exit = "true"
```

## Code Changes

`v90s-retroarch-launch` now chooses a writable persistent config path by default:

```text
PLUMOS_V90S_RETROARCH_CONFIG_DIR=/mnt/share/retroarch
/mnt/share/retroarch/retroarch-v90s.cfg
```

If a persistent config already exists, the launcher reuses it instead of
regenerating defaults. If it does not exist, it creates a default config there.
In either case, it ensures:

```text
config_save_on_exit = "true"
```

`v90s-retroarch-stop` now matches any RetroArch process using
`retroarch-v90s.cfg`, not only `/tmp/retroarch-v90s.cfg`, so safe stop still
works after moving the config to `/mnt/share`.

## Output

- image: `output/images/plumos-v90s-armbian-step2-20260710-5-stocklcd-persistent-ra-config.img`
- image sha256: `1edf7964972a0019e619f32a1559c948f196798e9d7192d062df2054619fdc6a`
- image size: `581M`
- rootfs payload: `output/rootfs-step2-retroarch-knulli-stocklcd-persistent-ra-config/debian-bookworm-retroarch-knulli-step2.squashfs`
- rootfs sha256: `992703ca75d036a0e6e0dc7a233d558efc076c0711a1b210a595d591619e8510`
- rootfs size: `447M`
- boot-resource FAT size: `33M`
- userdata size: `512M`

## Verification

The rootfs was inspected directly from squashfs and contains:

```text
RETROARCH_CONFIG_DIR="${PLUMOS_V90S_RETROARCH_CONFIG_DIR:-/mnt/share/retroarch}"
config_save_on_exit = "true"
prepare_config_path()
retroarch-launch: reusing persistent RetroArch config
retroarch-launch: config_path=$cfg
*"retroarch-v90s.cfg"*
```

The generated image still embeds the stock KNULLI V90S boot package:

```text
stock_boot_package_cmp_rc=0
9138e92d06a77a2844fb101ec2b2fa15ef11770a901b917ccafd82275b35114e  output/boot-packages/from-image-stocklcd-persistent-ra-config.fex
9138e92d06a77a2844fb101ec2b2fa15ef11770a901b917ccafd82275b35114e  .cache/knulli-linux/board/allwinner/a133/powkiddy-v90s/partitions/boot_package.fex
```

## Expected Device Test

On the live boot or after flashing the new image:

```text
1. Open the RetroArch menu during gameplay.
2. Change one harmless visible option, such as FPS display.
3. Save the current configuration from the RetroArch menu.
4. Restart RetroArch.
5. Confirm the option remains changed.
```

The saved config should remain at:

```text
/mnt/share/retroarch/retroarch-v90s.cfg
```
