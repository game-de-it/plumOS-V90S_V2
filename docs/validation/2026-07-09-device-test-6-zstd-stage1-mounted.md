# Device test 6: zstd stage1 mounted

Date: 2026-07-09

## Tested image

```text
output/images/plumos-v90s-armbian-step1-20260709-6-diag-zstd.img
sha256: 21ebb95f828bd4fd293ac53ba213480628f7c2761871937037c558f7acb623ea
```

## User-observed result

- V90S again stayed visually at the KNULLI boot logo.
- No Linux console appeared on the internal display.
- SD card was returned to the Mac for log inspection.

## FAT inspection

The FAT boot-resource partition mounted as:

```text
/Volumes/KNULLI
```

The expected diagnostic files were not present on FAT:

```text
plumos-v90s-diag.log
boot/plumos-v90s-diag.log
rootfs/plumos-v90s-diag.log
```

## Userdata inspection

The userdata partition was read from the SD card and inspected offline.

Source partition:

```text
/dev/rdisk4s5
```

Extracted image:

```text
output/device-logs/v90s-disk4s5-userdata-after-zstd.img
sha256: 935edab51a339185e9ae63b4480f934de99b99a8e3bebcdf270b7af3cecbfb27
```

Recovered diagnostic logs:

```text
/plumos-v90s-diag.log
/rootfs/plumos-v90s-diag.log
sha256: 10310593099adb2fcc675769f879cfbae0583ca8860b10203afe5074fafe59ff
```

The log copy stored for this repository is:

```text
docs/validation/logs/2026-07-09-plumos-v90s-diag-userdata-zstd.log
```

The userdata image also still contained the Debian payload:

```text
/rootfs/step1-rootfs.squashfs 43941888 bytes
sha256: c1ecd25e75b9b0da6cdb2b0a53fde33140b0885598f4b50e02e7cd479e2013b1
compression: zstd
```

## Key evidence

The kernel and diagnostic initramfs path are active:

```text
Linux version 4.9.191
plumOS V90S diagnostic init started
root=/dev/mmcblk0p4
```

The V90S boot-resource partition was found:

```text
scan: mounted /dev/mmcblk0p4 as vfat
scan: found /boot/knulli on /dev/mmcblk0p4
boot: mounted /dev/mmcblk0p4 as vfat on /boot_root
```

The zstd stage1 squashfs mounted successfully:

```text
boot: trying KNULLI-style file mount
boot: mounted /boot_root/boot/knulli with KNULLI-style file mount
boot: mounted /boot_root/boot/knulli as stage1 root
```

The diagnostic init listed the stage1 root:

```text
## ls -la /new_root
drwxr-xr-x    3        26 usr
drwxr-xr-x    2        27 sbin
drwxr-xr-x    2        30 bin
```

The diagnostic log was then persisted to userdata:

```text
persist: mounted /dev/mmcblk0p5 as ext4
```

USB/input support is present in the kernel log:

```text
usbcore: registered new interface driver usbhid
usbhid: USB HID core driver
input: adc_gamepad
```

## Framebuffer console finding

The KNULLI V90S kernel config has VT support but no framebuffer console:

```text
CONFIG_VT_CONSOLE=y
CONFIG_DUMMY_CONSOLE=y
# CONFIG_FRAMEBUFFER_CONSOLE is not set
```

This means `console=tty0` is not expected to draw a Linux text console on the LCD with this closed kernel. The screen remaining at the boot logo is therefore not proof that Linux or stage1 failed.

## Interpretation

Device test 6 is the first test where `/boot/knulli` mounted as the stage1 root. This confirms the previous failures were caused by squashfs format/compression mismatch, and zstd matches the V90S/KNULLI kernel path.

The next failure point is after diagnostic init switches into stage1. Because the visible LCD cannot rely on framebuffer console, the next image needs stage1-side logging and a direct `/dev/fb0` write probe. The stage1 payload should also avoid reusing `/dev/loop0`, because diagnostic init already consumed it while mounting `/boot/knulli`.
