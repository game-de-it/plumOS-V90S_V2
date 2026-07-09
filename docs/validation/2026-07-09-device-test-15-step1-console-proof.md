# Device test 15: Step 1 console proof

Date: 2026-07-09

## Tested image

```text
output/images/plumos-v90s-armbian-step1-20260709-15-fb-text-fat-logs.img
sha256: f26b6391af990a7b4637054d5558d3794fd50250674fb3b9ec68ed94e1d52f24
```

## User-observed result

- Framebuffer console text appeared on the internal LCD.
- USB keyboard input worked.
- User typed `df` and pressed Enter.
- Command output appeared on screen.
- SD card was returned to the Mac.

Photo:

```text
/Users/example/Downloads/IMG_4350.JPG
```

## FAT log inspection

The SD mounted on macOS as `/Volumes/KNULLI`.

The FAT stage1 root matched the expected `-15` payload:

```text
/Volumes/KNULLI/boot/knulli
sha256: d5f3a5a4328a9517fdbe480d5bfbcbdce46dab2b0acc4cb3996fa5bd1da0fabc
```

Logs were readable directly from FAT without ext4 extraction:

```text
/Volumes/KNULLI/plumos-logs/session.txt
sha256: eed2eba66ed8ca46ad12c5afdb241bd6e228988cf77a8702ea291c7685d49304

/Volumes/KNULLI/plumos-logs/plumos-v90s-diag.log
sha256: c2a44b79378547558a1a5fd0fccf18e571d53f740ae4f9612fe66770b27796d4

/Volumes/KNULLI/plumos-logs/plumos-v90s-debian-init.log
sha256: 661ed782709abde5fa013afb03c58979fc9564f260023332f7ded5297c37b597

/Volumes/KNULLI/plumos-logs/plumos-v90s-fb-console.log
sha256: af51f0de0d32084c766f2be9a9484c337e19744844601bafc03a13d97ebc2203
```

Recovered FAT logs stored in this repository:

```text
docs/validation/logs/2026-07-09-plumos-v90s-fat-session-fb-text.txt
docs/validation/logs/2026-07-09-plumos-v90s-diag-fat-fb-text.log
docs/validation/logs/2026-07-09-plumos-v90s-debian-init-fat-fb-text.log
docs/validation/logs/2026-07-09-plumos-v90s-fb-console-fat-fb-text.log
```

## Key evidence

Debian init reached the framebuffer console:

```text
debian-init: framebuffer console perl-check rc=0
debian-init: starting framebuffer console
```

Framebuffer console startup and automatic commands:

```text
fb-console: process entered
fb-console: fb0 640x960 visible=480 stride=2560 bpp=32
fb-console: fb opened
plumOS V90S framebuffer console
$ uname -a
$ ls /
$ ls /dev/input
input opened: /dev/input/event6
```

The user-entered command was captured and executed:

```text
> df
$ df
Filesystem     1K-blocks  Used Available Use% Mounted on
/dev/mmcblk0p4     33256 24717      8539  75% /boot
/dev/mmcblk0p5     56037 43014     11713  79% /mnt/share
/dev/loop2         43008 43008         0 100% /
```

The FAT log path also verifies that `/boot` is the boot-resource partition:

```text
/dev/mmcblk0p4 ... /boot
```

## Interpretation

Step 1 is achieved for the current boot-proof architecture: the V90S boots a generated SD image, displays a Linux framebuffer console on the internal LCD, accepts USB keyboard input, and runs basic commands.

This is still a KNULLI/stock-kernel boot chain with a Debian/Armbian-path minbase userspace payload, not a native Armbian board build. The next work can move from boot proof to either usability polish for the framebuffer console or a more native Armbian rootfs/build integration.
