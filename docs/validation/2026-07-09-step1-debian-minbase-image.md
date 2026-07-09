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

After device test 8 still showed no stage1 log, the stage1 payload was rebuilt to use a pre-mounted `/mnt/share` handoff from diagnostic init:

```text
output/rootfs-step1/stage1-userdata-loader.squashfs        2.7M
sha256: b4eac7d084bc1a66a411a353737c1b9211f75f2127619265ef84228a9a7030a9
compression: zstd

output/rootfs-step1/debian-bookworm-minbase-step1.squashfs 42M
sha256: 58704d22bd72960f2bf2d4224453366bf0257db810edddf158194c2b3adeef9e
compression: zstd
```

After device test 9 still showed no stage1 log, the payloads were rebuilt to mount tmpfs on `/tmp` and `/run` before writing stage1/Debian logs:

```text
output/rootfs-step1/stage1-userdata-loader.squashfs        2.7M
sha256: 055d78005fab725fd83efbe7f2db15d533159919fa8047fee6acd987429b5006
compression: zstd

output/rootfs-step1/debian-bookworm-minbase-step1.squashfs 42M
sha256: d9f2918f1e29234dce44eb70e89dea4a1a87943a1be1a09f86b6e65b5fff708a
compression: zstd
```

After device test 10 showed that stage1 could mount the Debian payload but did not reach Debian init logs, the payloads were rebuilt to preserve the moved `/dev` tree and repair `/dev/fb0` when sysfs exposes fb0:

```text
output/rootfs-step1/stage1-userdata-loader.squashfs        2.7M
sha256: 316f279e1d192dfdd2efd75350ba0c1acd565b44b75b0a7ff0c307fa26d4776f
compression: zstd

output/rootfs-step1/debian-bookworm-minbase-step1.squashfs 42M
sha256: dccb0e4b95967b5b93521166befdf4edc50bb3e8c313a4ac34f043bb51ad400c
compression: zstd
```

After device test 11 reached Debian init and proved `/dev/fb0` writes return success, the payloads were rebuilt with a stronger full-virtual-framebuffer probe:

```text
output/rootfs-step1/stage1-userdata-loader.squashfs        2.7M
sha256: 4546df08d5a2b56f835096d5f430e035d7c56ac862fe9ba6542373bac8a4da62
compression: zstd

output/rootfs-step1/debian-bookworm-minbase-step1.squashfs 42M
sha256: 2b85f6c827ff067e606a232bfd5b796a6b6dce44f04a7013fb7c4308ef9bc120
compression: zstd
```

After device test 12 proved that `/dev/fb0` userspace writes are visible on the LCD, the payloads were rebuilt with a small userspace framebuffer console:

```text
output/rootfs-step1/stage1-userdata-loader.squashfs        2.7M
sha256: 6e74bc431acc26e7ea1eb96ac533cf13f83a00f9a3d9f8bce6298b8095bbaa81
compression: zstd

output/rootfs-step1/debian-bookworm-minbase-step1.squashfs 42M
sha256: 56cc7e4a3700b60977b3fcde1a3b7301ed48ae4b0ddfd42731d0329d0638a721
compression: zstd
```

After device test 13 showed a black screen and an empty framebuffer console log, the payloads were rebuilt to capture console stdout/stderr, force-flush startup logs, and draw a large visible start marker:

```text
output/rootfs-step1/stage1-userdata-loader.squashfs        2.7M
sha256: b9c7a4a5ee16e64b94ff8081cbc7c3c9d7bb6e42a564050bb95df18cff9ea9ed
compression: zstd

output/rootfs-step1/debian-bookworm-minbase-step1.squashfs 42M
sha256: de22009eb734adaeefe206f152c092a51167e1f2dd68b3ac20a004e9fb91432b
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

The Debian rootfs uses a small `/sbin/init` shell wrapper, not systemd. The current test image starts a userspace framebuffer console because the V90S/KNULLI kernel does not expose a kernel framebuffer console. Expected final console text:

```text
plumOS V90S framebuffer console
$ uname -a
$ ls /
$ ls /dev/input
```

If framebuffer text appears but USB keyboard input does not, the next target is `/dev/input/event*` enumeration and HID event decoding. If framebuffer text does not appear, inspect `plumos-v90s-debian-init.log` and `plumos-v90s-fb-console.log` from userdata.
