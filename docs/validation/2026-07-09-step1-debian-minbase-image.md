# Step 1 Debian minbase image

Date: 2026-07-09

## Purpose

Create the first V90S Step 1 image that goes beyond the BusyBox smoke test while keeping the FAT boot-resource partition small.

This is still not a full native Armbian board build. It is a Debian Bookworm arm64 minbase rootfs used as the first Armbian-path boot proof: KNULLI-derived V90S boot assets start a small stage1 rootfs, then stage1 mounts the Debian payload from userdata and switches into it.

## Host capacity

`./scripts/check-host.sh` reported:

- Docker is available and reachable.
- Host has about 128GiB free.
- This is enough to continue rootfs and Armbian-oriented work.
- This is still below the 220GiB target for a realistic full KNULLI source build.

## Rootfs decision

Use a temporary Debian/Armbian-like arm64 console rootfs first, not a full Armbian board image, because:

- V90S native Armbian board support is not established yet.
- The immediate proof needed is kernel/console/USB-keyboard behavior on real hardware.
- KNULLI is being used only as the V90S boot-chain reference.

The first direct Debian minbase squashfs was larger than the 33MB FAT target, so the image now uses:

- FAT boot-resource: 33MB, holds KNULLI boot assets and `stage1-userdata-loader.squashfs`
- userdata ext4: 64MB, holds `rootfs/step1-rootfs.squashfs`

## Commands

```sh
./scripts/run-assembly-tools.sh ./scripts/build-step1-rootfs.sh \
  --out-dir output/rootfs-step1

./scripts/run-assembly-tools.sh ./scripts/assemble-v90s-image.sh \
  --rootfs output/rootfs-step1/stage1-userdata-loader.squashfs \
  --userdata-payload output/rootfs-step1/debian-bookworm-minbase-step1.squashfs \
  --out-dir output/images \
  --name plumos-v90s-armbian-step1-20260709-1.img \
  --userdata-size 64M \
  --keep-work
```

## Generated artifacts

```text
output/rootfs-step1/stage1-userdata-loader.squashfs        3.0M
output/rootfs-step1/debian-bookworm-minbase-step1.squashfs 42M
output/images/plumos-v90s-armbian-step1-20260709-1.img     133M
```

Hashes:

```text
ab4aeebb376243a4ad10930935050f43609a2bc4e0d7956f8c0f677657673d42  output/rootfs-step1/stage1-userdata-loader.squashfs
b435bbffebf43fe383cc57028f69bd2180c101d9bd14b8c4ad4fc4bb1b284840  output/rootfs-step1/debian-bookworm-minbase-step1.squashfs
d5ee904e669a5b0d292815cf2700f176f93bcb88b8f11d7946737ae1b94e850b  output/images/plumos-v90s-armbian-step1-20260709-1.img
```

## Later payload compression updates

After device test 4, the Debian minbase payload was rebuilt with gzip squashfs compression for closer compatibility with the V90S/KNULLI 4.9 kernel path:

```text
output/rootfs-step1/debian-bookworm-minbase-step1.squashfs 45M
sha256: d94c08bd3b331eee0503c0cba9da04f26e5a030d9c9f4cd0471536f57eab411b
compression: gzip
```

Device test 5 showed that the gzip stage1 squashfs was readable and loop-attached, but squashfs mount still failed with `Invalid argument`. The payloads were then rebuilt with zstd compression to match KNULLI's a133 board setting:

```text
output/rootfs-step1/stage1-userdata-loader.squashfs        2.7M
sha256: ee7730474e43f8e9fcda5486c73888a707c5b9c1b47b802166c3201bdd6bb799
compression: zstd

output/rootfs-step1/debian-bookworm-minbase-step1.squashfs 42M
sha256: c1ecd25e75b9b0da6cdb2b0a53fde33140b0885598f4b50e02e7cd479e2013b1
compression: zstd
```

After device test 6 confirmed the zstd stage1 mount path, the payloads were rebuilt again with userdata-persisted stage1/Debian logs and direct `/dev/fb0` write probes:

```text
output/rootfs-step1/stage1-userdata-loader.squashfs        2.7M
sha256: d3a8ac80776bfaac8a36f9e1e51d95a3f7214eed461b16731e45b47908f46a78
compression: zstd

output/rootfs-step1/debian-bookworm-minbase-step1.squashfs 42M
sha256: 36a6e1c3156cbc6e6761f92c5d7bad76f5807527f35cdd1c134e64b73f27cb20
compression: zstd
```

After device test 7 showed no stage1 log, the payloads were rebuilt with `/bin/sh -> busybox` in stage1 and with log persistence before framebuffer writes:

```text
output/rootfs-step1/stage1-userdata-loader.squashfs        2.7M
sha256: 82e5c48e7d0876cf8b96aa28323199bc1723adf3cba1048d31ab2e3179eef818
compression: zstd

output/rootfs-step1/debian-bookworm-minbase-step1.squashfs 42M
sha256: 58704d22bd72960f2bf2d4224453366bf0257db810edddf158194c2b3adeef9e
compression: zstd
```

The original `-1` image hash above still refers to the first generated image. Later test images record their own image hashes separately.

## Layout check

`gpt -r show output/images/plumos-v90s-armbian-step1-20260709-1.img`:

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

Partition 4 is the 33MB FAT boot-resource partition. Partition 5 is the 64MB userdata ext4 partition.

## Content check

FAT boot-resource contains:

```text
/boot/knulli       3121152 bytes
/boot/knulli.board 14 bytes
/boot/autoresize   0 bytes
```

FAT free space after assembly was about 8.5MB.

userdata ext4 contains:

```text
/rootfs/step1-rootfs.squashfs 43941888 bytes
```

## Expected device behavior

If the KNULLI-derived boot path reaches `/boot/boot/knulli`, stage1 should print:

```text
plumOS V90S stage1: looking for userdata rootfs payload
```

Then it searches likely V90S userdata partitions, mounts the ext4 partition read-only, loop-mounts `/rootfs/step1-rootfs.squashfs`, and switches into the Debian minbase rootfs.

The Debian rootfs uses a small `/sbin/init` shell wrapper, not systemd. Expected final console text:

```text
plumOS V90S Step1 Debian minbase console
```

If stage1 appears but the final console does not, the next target is userdata device enumeration or squashfs loop mounting. If even stage1 does not appear, the next target remains the KNULLI ramdisk boot-root selection and real kernel cmdline.
