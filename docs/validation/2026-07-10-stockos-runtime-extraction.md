# StockOS Runtime Extraction

Date: 2026-07-10

## Goal

Preserve the user's modified StockOS/Batocera runtime pieces that may be needed
when moving the V90S work toward an Armbian-built userspace. This is especially
important for closed or device-specific pieces:

- Android boot partition with the stock kernel/ramdisk
- U-Boot env partitions
- Linux `4.9.191` modules
- PowerVR firmware and EGL/GLES userspace libraries
- SDL2 and RetroArch runtime binaries
- QuickNES core
- ALSA/Pulse/PipeWire/WirePlumber config and libraries
- Batocera configgen/libretro generator files
- Current generated RetroArch and EmulationStation configs

## Extraction Command

The reproducible helper is:

```sh
scripts/extract-v90s-stockos-runtime.sh root@192.0.2.120 20260710-stockos-runtime
```

The helper writes into `artifacts/`, which is intentionally not tracked by git.

## Output

The current extraction is:

```text
artifacts/20260710-stockos-runtime/
```

Size:

```text
338M
```

Key files:

```text
artifacts/20260710-stockos-runtime/files/stockos-selected-files.tar.gz
artifacts/20260710-stockos-runtime/raw-partitions/mmcblk0p2-env.bin
artifacts/20260710-stockos-runtime/raw-partitions/mmcblk0p3-env-redund.bin
artifacts/20260710-stockos-runtime/raw-partitions/mmcblk0p4-boot.bin
artifacts/20260710-stockos-runtime/file-list.txt
artifacts/20260710-stockos-runtime/SHA256SUMS
```

The selected file tarball is about `273M`. The boot partition is about `65M`.

`file(1)` identifies the raw boot partition as:

```text
Android bootimg, kernel (0x40080000), ramdisk (0x42000000), page size: 2048
```

## Checksums

```text
3bb58d8caa086b1c0ff37df28f08da98fd5d831eafe8cbde3f848dc78980095a  README.txt
e00a552dc24540477011f65343eef2ffdd6428f7f1d78f3da5b38ea86b3028f3  file-list.txt
c118f21a5eadf11d8ec942d67f20375e5c155486f5b7441b4798f9bda802e707  files/stockos-selected-files.tar.gz
1567d9b746eca10ccd02d284faf46d3df7cd763debae994925bbcbc9e6a822c4  raw-partitions/mmcblk0p2-env.bin
1567d9b746eca10ccd02d284faf46d3df7cd763debae994925bbcbc9e6a822c4  raw-partitions/mmcblk0p3-env-redund.bin
7730529b17c85f530fb4b9efc4a2606bcfdae31f0594aaa5a7ed727c7a3d973e  raw-partitions/mmcblk0p4-boot.bin
```

The two env partitions currently have the same hash.

## Confirmed Contents

The tarball includes the expected migration inputs:

```text
media/Volumn/magic.bin
media/Volumn/bootlogo.bmp
lib/firmware/rgx.fw.22.102.54.38
lib/firmware/rgx.sh.22.102.54.38
lib/modules/4.9.191/pvrsrvkm.ko
lib/modules/4.9.191/dc_sunxi.ko
lib/modules/4.9.191/sunxi-backlight.ko
lib/modules/4.9.191/extra/8821cu.ko
usr/lib/libEGL.so.1
usr/lib/libGLESv2.so.2
usr/lib/libIMGegl.so
usr/lib/libsrv_um.so
usr/lib/libusc.so
usr/lib/libSDL2-2.0.so.0.3000.12
usr/bin/retroarch
usr/lib/libretro/quicknes_libretro.so
userdata/system/configs/retroarch/retroarchcustom.cfg
usr/lib/python3.12/site-packages/configgen/generators/libretro/libretroConfig.py
etc/asound.conf
usr/bin/pipewire
usr/bin/wireplumber
usr/share/pipewire/pipewire-pulse.conf
etc/wireplumber/wireplumber.conf.d/51-builtinspeaker.conf
userdata/system/services/auto_mono_output
```

## Scope Limit

The full StockOS squashfs/root filesystem was not copied. That would make the
artifact much larger and would blur which files are actually needed for the
Armbian migration. If a missing dependency appears later, either rerun the
helper with an expanded file list or extract directly from the SD card after it
is connected to the Mac.
