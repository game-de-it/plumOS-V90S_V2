# Device test 13: framebuffer console black screen

Date: 2026-07-09

## Tested image

```text
output/images/plumos-v90s-armbian-step1-20260709-13-fb-console.img
sha256: e81b77a18d3530ab094be55896c69e48ba9647bc61c59efac7caa2a24d7d18b6
```

## User-observed result

- The KNULLI boot logo disappeared.
- The screen stayed black after the logo.
- USB keyboard key presses did not visibly affect the screen.
- Caps Lock LED did not turn on.
- SD card was returned to the Mac for log inspection.

## FAT inspection

The FAT boot-resource partition mounted as `/Volumes/KNULLI`.

The FAT stage1 root matched the expected `-13` payload:

```text
/Volumes/KNULLI/boot/knulli
sha256: 6e74bc431acc26e7ea1eb96ac533cf13f83a00f9a3d9f8bce6298b8095bbaa81
```

No diagnostic, Debian, or framebuffer console logs were present on FAT.

## Userdata inspection

The userdata partition was read from the SD card and inspected offline.

Source partition:

```text
/dev/rdisk4s5
```

Extracted image:

```text
output/device-logs/v90s-disk4s5-userdata-after-fb-console.img
sha256: a4305f9ecb3bc2827ebfaef70db294e63b75382dd8b8ba761341a793d17ab45f
```

The root directory contained:

```text
/plumos-v90s-diag.log             40107 bytes
/plumos-v90s-debian-init.log        774 bytes
/plumos-v90s-fb-console.log           0 bytes
/rootfs/step1-rootfs.squashfs  43945984 bytes
/rootfs/plumos-v90s-diag.log
/rootfs/plumos-v90s-debian-init.log
/rootfs/plumos-v90s-fb-console.log
```

Recovered logs stored in this repository:

```text
docs/validation/logs/2026-07-09-plumos-v90s-diag-userdata-fb-console.log
sha256: 4f1f257d164afc92064e4089c4069363064c6c2b645094b618b6f1246cc8e178

docs/validation/logs/2026-07-09-plumos-v90s-debian-init-fb-console.log
sha256: afe359582ba6924452aa18594cc9c2dba17a87d55f81df5ffbb3c409175a10ca

docs/validation/logs/2026-07-09-plumos-v90s-fb-console-empty.log
sha256: e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
```

## Key evidence

The direct payload route still reached Debian init:

```text
payload-share: mounted /dev/mmcblk0p5 as ext4 on /payload_share
payload-root: attached payload to /dev/loop2
payload-root: mounted Debian payload rootfs
boot: switching directly to payload /sbin/init
```

Debian init started the framebuffer console:

```text
debian-init: fb0 full black wrote blocks=600 bytes=2457600
debian-init: fb0 white band page0 wrote
debian-init: fb0 white band page1 wrote seek_blocks=300
debian-init: starting framebuffer console
```

The framebuffer console log files were present but empty, so no startup lines from `v90s-fb-console` were persisted.

The USB keyboard was detected by the kernel:

```text
usb 2-1: new low-speed USB device number 2 using sunxi-ohci
input: ELECOM ELECOM TK-FCP096
hid-generic 0003:056E:1062.0001: input,hidraw0: USB HID v1.10 Keyboard
hid-generic 0003:056E:1062.0002: input,hidraw1: USB HID v1.10 Device
usbcore: registered new interface driver usbhid
```

## Interpretation

Device test 13 still proves the direct Debian payload route is alive, but the userspace framebuffer console did not produce visible text. The black screen is consistent with the console clearing fb0 and then failing or hanging before persistent output was flushed.

Caps Lock LED not toggling is not enough to conclude USB failure. The kernel did enumerate the ELECOM USB keyboard, and the userspace console does not currently drive keyboard LED state.

The next image should capture console stdout/stderr to userdata, force-flush startup logs, and draw a large visible marker before normal text rendering.
