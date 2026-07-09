# Step 1 boot-console plan

## Target

V90S 実機で SD カードから boot し、画面に Linux コンソールを出し、USB キーボードで入力し、`ls` などの基本コマンドを実行できること。

## Success criteria

- Boot reaches a visible text console or shell on the internal display.
- USB keyboard input is accepted.
- The following commands run on the device:

```sh
uname -a
cat /proc/cmdline
mount
ls /
ls /dev/input
dmesg | tail -80
```

## Build tracks

### Track A: boot-chain reproduction

Use KNULLI V90S prebuilt boot assets and reproduce its SD image layout.

Inputs:

- `boot0.img`
- `boot_package.fex`
- `boot.img`
- `env.img`
- V90S `genimage.cfg`
- a rootfs squashfs placed as `/boot/boot/knulli`

Output:

- flashable `.img` or `.img.gz`

This track proves that our assembly mechanism matches the V90S boot contract before Armbian complexity is added.

Keep the iteration image small. The KNULLI source config reserves a multi-GB FAT boot-resource partition, but Step 1 only needs enough room for boot assets and the test rootfs. The current assembly default is a 33MB FAT boot-resource partition plus a 64MB userdata partition; 30MB/32MB failed with the FAT32 tooling used by the KNULLI config, while 33MB assembled successfully.

### Track B: minimal Armbian rootfs

Generate an aarch64 Armbian-derived console rootfs and pack it as squashfs.

Initial rootfs requirements:

- `/sbin/init` exists
- system boots without network
- root shell or root login is available for bring-up
- getty is enabled on visible VT and serial console
- no desktop stack

### Track C: device-specific rootfs adaptation

Only add V90S-specific pieces when test evidence requires them.

Likely candidates:

- kernel modules matching KNULLI V90S `4.9.191`
- framebuffer permissions or console font settings
- USB host/input modules if keyboard does not appear
- a simpler init path if systemd is too heavy for first boot proof

## Test image naming

Use monotonic names so device reports are easy to correlate:

```text
plumos-v90s-armbian-step1-YYYYMMDD-N.img.gz
```

## Device test report template

```text
image:
sha256:
SD card:

boot result:
screen:
USB keyboard:

commands:
- uname -a:
- cat /proc/cmdline:
- mount:
- ls /:
- ls /dev/input:

notes:
photo/log:
```

## Open questions

- Does the KNULLI V90S bootloader append or override the boot image cmdline on real hardware?
- Which partition becomes mountable as `/boot_root` in the actual `/proc/cmdline`?
- Are USB keyboard and framebuffer console drivers built into the kernel, or do they require modules from the KNULLI/stock rootfs?
- Is systemd acceptable for the first proof, or should the first Armbian-flavored image use a tiny init/getty wrapper?
