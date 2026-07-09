# StockOS Layout Smoke Image

Date: 2026-07-10

## Purpose

Create the first small V90S SD-card image using the StockOS/Batocera partition
contract instead of the older KNULLI/Armbian-named layout.

This is a boot-chain and partition-layout smoke image. It puts the existing
small stage1 squashfs on StockOS partition `p5` (`batocera`) and uses the
StockOS-derived env and Android boot partition from the prepared vendor runtime.

## Build

```sh
./scripts/docker-build.sh image
./scripts/docker-build.sh stockos-image \
  --name plumos-v90s-stockos-smoke-20260710-1.img
```

Output:

```text
output/images/plumos-v90s-stockos-smoke-20260710-1.img
output/images/plumos-v90s-stockos-smoke-20260710-1.img.manifest.txt
```

Image:

```text
size: 218M
sha256: 3ef2e2f1350e5266d59e1650a98852935cf43fbe4b737d242b6789c58cb9aa35
```

## Layout

The generated GPT layout is:

```text
p1 boot-resource  fat16  33M
p2 env                   256K
p3 env-redund           256K
p4 boot                  64M
p5 batocera              2.7M
p6 rootfs         ext4   33M
p7 rootfs_data    ext4   64M
```

This mirrors the StockOS partition names and order:

```text
boot-resource@mmcblk0p1
env@mmcblk0p2
env-redund@mmcblk0p3
boot@mmcblk0p4
batocera@mmcblk0p5
rootfs@mmcblk0p6
rootfs_data@mmcblk0p7
```

p1 is intentionally smaller than StockOS for repeated SD-card write tests.

## Verified

- p2 matches `output/vendor/stockos-runtime/raw-partitions/mmcblk0p2-env.bin`.
- p3 matches `output/vendor/stockos-runtime/raw-partitions/mmcblk0p3-env-redund.bin`.
- p4 matches `output/vendor/stockos-runtime/raw-partitions/mmcblk0p4-boot.bin`.
- p4 is an Android boot image named `a133-b6` with an empty cmdline.
- raw `boot0` and `boot_package` regions match the current KNULLI V90S fallback
  assets used by the assembler.
- p5 is a zstd squashfs and includes `/boot`, `/overlay`, `/dev`, `/proc`,
  `/sys`, `/tmp`, `/run`, and `/sbin/init` for StockOS init handoff.

## Boundary

The current `artifacts/20260710-stockos-runtime` extraction does not yet contain
raw StockOS `boot0` or `boot_package` captures. The assembler therefore falls
back to the compatible KNULLI V90S files and records that in the image manifest.
The extraction script has been extended so future StockOS captures can replace
that fallback.

## Next Test

Flash `output/images/plumos-v90s-stockos-smoke-20260710-1.img` and boot it on
the V90S. Expected result is not full RetroArch yet; the first check is whether
the StockOS boot chain reaches the p5 stage1 rootfs without the old KNULLI p4
FAT root convention.
