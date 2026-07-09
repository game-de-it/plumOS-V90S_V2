# V90S Armbian + KNULLI boot-chain research

Date: 2026-07-09

## User goal

POWKIDDY V90S で動く Linux を Armbian ベースで作る。Step 1 は、実機で SD カードから boot し、画面にコンソールを表示し、USB キーボードから `ls` などを実行できるところまで。

## Sources checked

- KNULLI Docker build guide: https://knulli.org/ja/development/building-knulli-with-docker/
- KNULLI current source repository: https://github.com/knulli-cfw/knulli-linux
- KNULLI release page: https://github.com/knulli-cfw/knulli-linux/releases
- Armbian build quick start: https://docs.armbian.com/Developer-Guide_Build-Preparation/
- Armbian Docker build docs: https://docs.armbian.com/Developer-Guide_Building-with-Docker/
- Armbian user configuration docs: https://docs.armbian.com/Developer-Guide_User-Configurations/
- Armbian adding board/family docs: https://docs.armbian.com/Developer-Guide_Adding-Board-Family/
- Powkiddy V90S product/spec page: https://powkiddy.com/products/pre-sale-powkiddy-v90s-handheld-game-console

## Reference snapshots

- `knulli-cfw/knulli-linux` branch `knulli-main`: `ac2ededdd3999443da4ba514dac22145d628f735`
- `knulli-cfw/knulli-linux` latest release observed: `20260511`, release commit `c1c7de479e56691c6665723046d9f25500e5ee74`
- KNULLI V90S release artifact observed: `knulli-a133-powkiddy-v90s-scarab-20260511.img.gz`
- KNULLI V90S release sha256 observed on GitHub release page: `1e8178bbfb1a4d0af4d4300c5e9aaa86f60df42a29ea792fd7dbc36299a0613c`
- `game-de-it/plumOS-V90S` reference README snapshot: `f9ced5e6caf7f287655cf6ba7e3740d33f247f70`

## Hardware facts to treat as working assumptions

- V90S is an Allwinner A133 Plus / ARM Cortex-A53 class device.
- KNULLI target name is `a133`, board image name is `powkiddy-v90s`.
- Display target is 3.5 inch 640x480.
- RAM is 1GB DDR3.
- Storage is dual microSD, with TF1 used for OS and TF2 commonly used for ROM/user data.

These are enough for Step 1 planning, but the real boot contract must still be confirmed from the target image and actual device logs.

## KNULLI findings

KNULLI recommends Docker builds and documents a large build footprint. The public build guide says Linux + Docker is expected and that more than 180GB of free disk space is needed.

Relevant source files in the KNULLI snapshot:

- `configs/knulli-a133.board`
- `package/system/knulli-system/Config.in`
- `package/boot/uboot-a133/uboot-a133.mk`
- `package/boot/uboot-a133/powkiddy-v90s/boot_package/boot_package.cfg`
- `package/boot/uboot-a133/powkiddy-v90s/boot_package/powkiddy-v90s.dts`
- `board/allwinner/a133/powkiddy-v90s/genimage.cfg`
- `board/allwinner/a133/powkiddy-v90s/create-boot-script.sh`
- `board/allwinner/a133/powkiddy-v90s/partitions/boot0.img`
- `board/allwinner/a133/powkiddy-v90s/partitions/boot.img`
- `board/allwinner/a133/powkiddy-v90s/partitions/boot_package.fex`
- `board/allwinner/a133/powkiddy-v90s/partitions/env.img`

`configs/knulli-a133.board` sets:

- `BR2_aarch64=y`
- Cortex-A53 target flags
- Linux/kernel headers version `4.9.191`
- `BR2_PACKAGE_UBOOT_A133=y`
- `BR2_PACKAGE_POWERVR_GE8300_DRIVER=y`
- SquashFS rootfs with zstd

`package/system/knulli-system/Config.in` includes V90S in the A133 image list:

```text
allwinner/a133/trimui-smart-pro allwinner/a133/trimui-brick allwinner/a133/magicx-zero-28 allwinner/a133/powkiddy-v90s allwinner/a133/powkiddy-v20 allwinner/a133/magicx-zero-40
```

`package/boot/uboot-a133/uboot-a133.mk` builds A133 boot packages for:

```text
trimui-smart-pro trimui-brick powkiddy-v20 powkiddy-v90s magicx-zero-28 magicx-zero-40 xu20-v32
```

It compiles the board DTS with `dtc`, then packs `boot_package.fex` with `dragonsecboot`.

## V90S image layout from KNULLI genimage config

`board/allwinner/a133/powkiddy-v90s/genimage.cfg` defines:

- GPT image
- raw `boot0.img` bootloader outside the partition table at offset `131072`
- raw `powkiddy-v90s_boot_package.fex` outside the partition table at offset `16793600`
- raw Android-style `boot.img` partition at offset `21495808`
- two env partitions using `env.img`
- FAT32 boot-resource partition labelled `KNULLI`
- ext4 userdata partition labelled `SHARE`

The V90S prebuilt partition assets in KNULLI source were:

- `boot0.img`: 64 KiB
- `boot_package.fex`: about 4.5 MiB
- `boot.img`: about 16 MiB
- `env.img`: 128 KiB

## V90S boot.img / ramdisk notes

`file` reports the KNULLI V90S `boot.img` as Android boot image:

```text
Android bootimg, kernel (0x40080000), ramdisk (0x42000000), page size: 2048
```

Observed boot image cmdline:

```text
loglevel=0 initcall_debug=0 console=tty0 console=ttyS0,115200 rootwait root=/dev/mmcblk0p1 init=/sbin/init
```

Extracted kernel string:

```text
Linux version 4.9.191 ... #17 SMP PREEMPT Tue May 13 18:14:09 UTC 2025
```

The extracted V90S ramdisk `init` accepts `dev=`, `root=`, `label=`, and `uuid=` kernel parameters, mounts the selected boot/root device at `/boot_root`, then expects the real rootfs at:

```text
/boot_root/boot/knulli
```

It mounts that squashfs into `/overlay_root/base`, creates a tmpfs overlay, moves `/boot_root` to `/new_root/boot`, then `switch_root`s to `$INIT`, defaulting to `/sbin/init`.

This means a Step 1 image can likely keep the V90S kernel and ramdisk, then replace `/boot/boot/knulli` with an Armbian-derived squashfs that provides `/sbin/init`.

## Armbian findings

Armbian build framework can build full images, kernels, DTBs, and custom user configurations. Official docs state:

- host should be x86_64/aarch64/riscv64 class
- minimum memory is around 8GB
- disk need is around 50GB for VM/container/bare-metal usage
- Docker-capable Linux is supported for container builds
- `userpatches/` can inject custom configs, patches, overlays, and image customization without forking the build tree

The Armbian docs also currently say there are no detailed instructions for adding a completely new board or board family, only example PRs. For V90S Step 1, adding a native Armbian board is therefore higher risk than using Armbian for rootfs generation and KNULLI for boot.

## Proposed Step 1 path

1. Reproduce the V90S boot chain as an assembly step:
   - use KNULLI V90S `boot0.img`, `boot_package.fex`, `boot.img`, and `env.img`
   - generate an image with the same partition offsets and labels
   - put a known rootfs squashfs at `/boot/boot/knulli`

2. Generate or obtain an Armbian aarch64 rootfs:
   - initial target should be minimal console, not desktop
   - use Debian/Ubuntu rootfs compatible with aarch64 and Linux 4.9 userspace expectations
   - enable a deterministic console path and root login/autologin for test builds

3. Adapt the rootfs for the V90S boot environment:
   - ensure `/sbin/init` exists
   - ensure `/dev`, `/proc`, and `/sys` are normal mount points
   - enable getty on a visible console, likely `tty1`/`tty0` and serial `ttyS0`
   - avoid depending on kernel features not present in 4.9.191
   - include V90S kernel modules from KNULLI/stock if later USB/input/display proof requires them

4. Assemble SD image:
   - create FAT32 boot-resource partition labelled `KNULLI`
   - include `/boot/boot/knulli`
   - include `knulli.board` with `powkiddy-v90s`
   - retain raw boot offsets from KNULLI

5. User performs real-device test:
   - boot screen visible?
   - login prompt or shell visible?
   - USB keyboard input works?
   - `ls`, `uname -a`, `cat /proc/cmdline`, and `mount` output collected

## Current blockers

- Local disk free space was about 15GiB, below both KNULLI and Armbian practical build requirements.
- `genimage`, `mksquashfs`, `qemu-aarch64-static`, and `debootstrap` were not installed on this macOS host at first check.
- The V90S kernel/boot assets are prebuilt. Treat kernel provenance, module matching, and GPL/source availability as separate follow-up risks.

## First practical checkpoint

Before attempting full Armbian build:

1. Free at least 80GB for minimal rootfs/image work, preferably 220GB+ if building KNULLI from source.
2. Install image tooling, either on a Linux build host/container or via Homebrew/Docker as appropriate.
3. Use `scripts/assemble-v90s-image.sh` with a tiny known-good squashfs first, then swap in Armbian rootfs.
