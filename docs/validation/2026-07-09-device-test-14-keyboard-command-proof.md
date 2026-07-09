# Device test 14: keyboard command proof with invisible text

Date: 2026-07-09

## Tested image

```text
output/images/plumos-v90s-armbian-step1-20260709-14-fb-console-logged.img
sha256: 1b80f2c6067bc22e163f0272d0d5e423cf65fb49c9bde3c8ca068b0228dbbf11
```

## User-observed result

- A white frame or border appeared on the LCD.
- Typed `ls` on a USB keyboard and pressed Enter.
- The white frame blinked after Enter.
- This suggested keyboard input was being received.
- SD card was returned to the Mac for log inspection.

Photo:

```text
/Users/example/Downloads/IMG_4349.JPG
```

## FAT inspection

The FAT boot-resource partition mounted as `/Volumes/KNULLI`.

The FAT stage1 root matched the expected `-14` payload:

```text
/Volumes/KNULLI/boot/knulli
sha256: b9c7a4a5ee16e64b94ff8081cbc7c3c9d7bb6e42a564050bb95df18cff9ea9ed
```

No logs were present on FAT in this image.

## Userdata inspection

The userdata partition was read from the SD card and inspected offline.

Extracted image:

```text
output/device-logs/v90s-disk4s5-userdata-after-fb-console-logged.img
sha256: 6d39bc8cc22427627a666ff8d59708262deff32923a87b344b01ed2a5fd6b90b
```

Recovered logs stored in this repository:

```text
docs/validation/logs/2026-07-09-plumos-v90s-diag-userdata-fb-console-logged.log
sha256: cbea077e4ccf4e61b4b439cdc006274a0290a9077eedcc696394bd3527c4a87c

docs/validation/logs/2026-07-09-plumos-v90s-debian-init-fb-console-logged.log
sha256: 060fd054320aabf3e6c0955c108d951970312c10b7cf5da3f6b8a1ad4629be77

docs/validation/logs/2026-07-09-plumos-v90s-fb-console-logged.log
sha256: 21204576a772aca50c37be677ef5263172bc870914840e045c566afb0d4e4afe
```

## Key evidence

Debian init started the framebuffer console successfully:

```text
debian-init: framebuffer console perl-check rc=0
debian-init: starting framebuffer console
```

The framebuffer console ran startup commands:

```text
$ uname -a
Linux (none) 4.9.191 #17 SMP PREEMPT Tue May 13 18:14
$ ls /
bin
boot
dev
etc
home
lib
media
mnt
opt
proc
root
run
sbin
srv
sys
tmp
usr
var
$ ls /dev/input
event0
event1
event2
event3
event4
event5
event6
```

The framebuffer console opened all input event devices and received the user's keyboard input:

```text
input opened: /dev/input/event0
input opened: /dev/input/event1
input opened: /dev/input/event2
input opened: /dev/input/event3
input opened: /dev/input/event4
input opened: /dev/input/event5
input opened: /dev/input/event6
> ls
$ ls
bin
boot
dev
etc
home
lib
media
mnt
opt
proc
root
run
sbin
srv
sys
tmp
usr
var
```

## Interpretation

Device test 14 proves that the Step 1 userspace path can boot Debian, access fb0, enumerate USB keyboard input, accept typed characters, execute `ls`, and capture command output.

The remaining visible-screen issue is not input or command execution. It is the framebuffer console text renderer. The white border and blink came from rectangle drawing, but text glyphs did not appear because `%FONT` was assigned after the infinite event loop and therefore remained empty during rendering.

The next image should initialize the font table before entering the main loop and should copy logs to FAT so macOS can read them without ext4 extraction.
