# StockOS Layout RetroArch Image

Date: 2026-07-10

## Purpose

Create a first RetroArch-capable SD-card image using the StockOS/Batocera
partition contract. This keeps the StockOS-derived p2/p3 env partitions and p4
Android boot partition, but replaces p5 `batocera` with the current
RetroArch-capable plumOS squashfs payload.

This is the next real-device test candidate after the smaller layout smoke
image.

## Build

```sh
./scripts/docker-build.sh stockos-image \
  --rootfs-squashfs output/rootfs-step2-retroarch-knulli-stocklcd-persistent-ra-config/debian-bookworm-retroarch-knulli-step2.squashfs \
  --name plumos-v90s-stockos-ra-20260710-1.img
```

Output:

```text
output/images/plumos-v90s-stockos-ra-20260710-1.img
output/images/plumos-v90s-stockos-ra-20260710-1.img.manifest.txt
```

Image:

```text
size: 662M
sha256: ebc2c500c1a4175da74bcab80e4a08f96a0e29ba0c365dee363e9cc097931945
```

## Layout

The generated GPT layout is:

```text
p1 boot-resource  fat16   33M
p2 env                    256K
p3 env-redund            256K
p4 boot                   64M
p5 batocera        zstd   446.6M
p6 rootfs          ext4   33M
p7 rootfs_data     ext4   64M
```

## Verified

- p5 hash matches the generated manifest:
  `c72f40fa81da1c3e418a65b671c8941d8f061dfc7824a193488872163274a77c`.
- p5 contains `/boot`, `/overlay`, `/dev`, `/proc`, `/sys`, `/tmp`, `/run`,
  `/mnt/share`, `/etc/retroarch.cfg`, and
  `/usr/local/bin/retroarch-knulli`.
- p4 is the StockOS-derived Android boot image named `a133-b6` with an empty
  cmdline.
- p1 remains intentionally small at 33M for repeated write tests.
- p7 remains 64M for logs, config, and save data during the first RA layout
  test.

## Notes

The source RetroArch rootfs contains real `/dev/*` character devices. Docker
Desktop cannot create those device nodes on the bind-mounted workspace, so the
assembler now tolerates those extraction warnings, removes the unpacked `/dev`,
and recreates an empty `/dev` directory. The target kernel/devtmpfs is expected
to populate device nodes at runtime.

## Next Test

Flash `output/images/plumos-v90s-stockos-ra-20260710-1.img` and boot it on the
V90S. The key question is whether the StockOS/Batocera partition layout reaches
the existing RetroArch-capable p5 payload.
