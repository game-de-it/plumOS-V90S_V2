# V90S image assembly smoke test

Date: 2026-07-09

## Purpose

Validate that the local scripts can assemble a V90S-style SD image using the KNULLI boot chain and a supplied squashfs rootfs.

This is not an Armbian image. It is a minimal BusyBox smoke rootfs built only to test the image generation path.

## Inputs

- KNULLI source: `.cache/knulli-linux`
- KNULLI commit: `ac2ededdd3999443da4ba514dac22145d628f735`
- Rootfs source: V90S ramdisk BusyBox copied into `output/rootfs-smoke/root`
- Rootfs init: minimal `/sbin/init` that mounts proc/sys/devtmpfs, prints a message, then execs `/bin/sh`

## Commands

```sh
docker build -f docker/assembly-tools/Dockerfile -t plumos-v90s-assembly-tools .

./scripts/run-assembly-tools.sh mksquashfs \
  output/rootfs-smoke/root \
  output/rootfs-smoke/smoke.squashfs \
  -noappend \
  -comp gzip

./scripts/run-assembly-tools.sh ./scripts/assemble-v90s-image.sh \
  --rootfs output/rootfs-smoke/smoke.squashfs \
  --out-dir output/images \
  --name plumos-v90s-smoke.img \
  --keep-work
```

## Results

- `docker build` succeeded.
- Tool container provides `genimage`, `mksquashfs`, `abootimg`, and `debootstrap`.
- `mksquashfs` succeeded.
- `assemble-v90s-image.sh` initially failed because the empty `userdata` mountpoint was missing from the genimage rootpath.
- Fixed by creating `root_dir/userdata` before calling `genimage`.
- Re-run succeeded and produced `output/images/plumos-v90s-smoke.img`.

Generated artifacts:

```text
output/rootfs-smoke/smoke.squashfs  792K
output/images/plumos-v90s-smoke.img 5.5G
```

Hashes:

```text
c4aca60cbc7d71ece31920d807ebd095b174109f26246931ef7a25337f902904  output/images/plumos-v90s-smoke.img
0ae268f8f400c1b239da50a3e5778fed46a5f52a48636c8923a0b390b8c33119  output/rootfs-smoke/smoke.squashfs
```

`gpt -r show output/images/plumos-v90s-smoke.img` confirmed a PMBR, primary/secondary GPT headers, and five GPT partitions. Partition 4 is the FAT boot-resource-sized partition and partition 5 is the userdata-sized partition.

## Device-test warning

The smoke image is useful only to validate the KNULLI-derived boot chain. If it boots, it should drop to a BusyBox shell, not Armbian. The first Armbian test image still needs a real Armbian-derived aarch64 rootfs.
