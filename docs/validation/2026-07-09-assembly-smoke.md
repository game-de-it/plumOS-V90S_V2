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
- The first inherited KNULLI sizing produced a 5.5GB image, which is too large for repeated SD-card flashing.
- 30MB and 32MB FAT boot-resource attempts failed with KNULLI's FAT32 tooling path: `mtools` could not create directories in the too-small FAT32 image.
- 33MB FAT boot-resource succeeded, so the assembly default is now 33MB FAT plus 64MB userdata.
- Re-run succeeded and produced `output/images/plumos-v90s-smoke.img`.

Generated artifacts:

```text
output/rootfs-smoke/smoke.squashfs  792K
output/images/plumos-v90s-smoke.img 133M
```

Hashes:

```text
f2a2eb31e14c26edf1f7cdd616bb44e2cb7e0de9605cda12fd7be28d9781a513  output/images/plumos-v90s-smoke.img
0ae268f8f400c1b239da50a3e5778fed46a5f52a48636c8923a0b390b8c33119  output/rootfs-smoke/smoke.squashfs
```

`gpt -r show output/images/plumos-v90s-smoke.img` confirmed a PMBR, primary/secondary GPT headers, and five GPT partitions:

```text
   start    size  index  contents
       0       1         PMBR
       1       1         Pri GPT header
       2      32         Pri GPT table
      34   41950
   41984   31744      1  GPT part - 0FC63DAF-8483-4772-8E79-3D69D8477DE4
   73728     256      2  GPT part - 0FC63DAF-8483-4772-8E79-3D69D8477DE4
   73984     256      3  GPT part - 0FC63DAF-8483-4772-8E79-3D69D8477DE4
   74240   67584      4  GPT part - EBD0A0A2-B9E5-4433-87C0-68B6B72699C7
  141824  131072      5  GPT part - EBD0A0A2-B9E5-4433-87C0-68B6B72699C7
  272896       7
  272903      32         Sec GPT table
  272935       1         Sec GPT header
```

Partition 4 is the 33MB FAT boot-resource partition and partition 5 is the 64MB userdata partition.

## Device-test warning

The smoke image is useful only to validate the KNULLI-derived boot chain. If it boots, it should drop to a BusyBox shell, not Armbian. The first Armbian test image still needs a real Armbian-derived aarch64 rootfs.
