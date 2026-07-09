# Step 1 framebuffer console logged image

Date: 2026-07-09

## Purpose

Device test 13 reached Debian init but showed a black screen after starting the framebuffer console. The console log file existed but was empty, so this image improves failure visibility before changing the overall boot route.

Changes:

- Debian init runs `perl -c` before starting the framebuffer console.
- Debian init redirects framebuffer console stdout/stderr to `plumos-v90s-fb-console.log`.
- Debian init no longer `exec`s the console, so an exit status can be logged if the console returns.
- `v90s-fb-console` no longer imports `Fcntl` for basic open flags.
- `v90s-fb-console` logs immediately at process entry and force-syncs early log lines.
- `v90s-fb-console` draws a large white start marker and a persistent white border before normal text rendering.

## Image

```text
output/images/plumos-v90s-armbian-step1-20260709-14-fb-console-logged.img
sha256: 1b80f2c6067bc22e163f0272d0d5e423cf65fb49c9bde3c8ca068b0228dbbf11
size: 133M
```

The image keeps the compact iteration layout:

- FAT boot-resource: 33MB
- userdata ext4: 64MB

## Build command

```sh
./scripts/run-assembly-tools.sh ./scripts/build-step1-rootfs.sh \
  --out-dir output/rootfs-step1

./scripts/run-assembly-tools.sh ./scripts/assemble-v90s-image.sh \
  --rootfs output/rootfs-step1/stage1-userdata-loader.squashfs \
  --userdata-payload output/rootfs-step1/debian-bookworm-minbase-step1.squashfs \
  --out-dir output/images \
  --name plumos-v90s-armbian-step1-20260709-14-fb-console-logged.img \
  --userdata-size 64M \
  --boot-cmdline 'loglevel=8 ignore_loglevel initcall_debug=0 console=tty0 console=ttyS0,115200 rootwait root=/dev/mmcblk0p4 init=/sbin/init elevator=noop' \
  --diagnostic-init \
  --keep-work
```

## Payloads

```text
stage1-userdata-loader.squashfs:
  compression: zstd
  size: 2875392 bytes
  sha256: b9c7a4a5ee16e64b94ff8081cbc7c3c9d7bb6e42a564050bb95df18cff9ea9ed

debian-bookworm-minbase-step1.squashfs:
  compression: zstd
  size: 43945984 bytes
  sha256: de22009eb734adaeefe206f152c092a51167e1f2dd68b3ac20a004e9fb91432b
```

## Host verification

`abootimg -i` confirmed the diagnostic cmdline:

```text
loglevel=8 ignore_loglevel initcall_debug=0 console=tty0 console=ttyS0,115200 rootwait root=/dev/mmcblk0p4 init=/sbin/init elevator=noop
```

The completed image layout remains compact:

```text
partition 4 boot-resource: 67584 sectors
partition 5 userdata:      131072 sectors
```

The userdata partition extracted from the completed image passes `e2fsck -fn`, and its payload hash matches:

```text
/rootfs/step1-rootfs.squashfs
sha256: de22009eb734adaeefe206f152c092a51167e1f2dd68b3ac20a004e9fb91432b
```

## Expected device evidence

The LCD should show either framebuffer console text or, at minimum, a large white start marker. If the screen stays black, the returned SD should contain a non-empty `plumos-v90s-fb-console.log` with either `perl -c` output, startup progress, or a fatal error.
