# Step 2 LCD HT812 Timing Image

Date: 2026-07-10

## Output

- image: `output/images/plumos-v90s-armbian-step2-20260710-1-lcd-ht812.img`
- image sha256: `0a13d68e7cf8589b2a43518bd0cd3e8a9d1e08dde16220266abb387be846ce05`
- image size: `581M`
- rootfs payload: `output/rootfs-step2-retroarch-knulli-ssh-lcd60/debian-bookworm-retroarch-knulli-step2.squashfs`
- rootfs sha256: `2c3873d17215964064900a4ebd4b759c47ddf0966aac0482c173aa2e5eb10efb`
- boot package: `output/boot-packages/powkiddy-v90s-lcd-ht812.fex`
- boot package sha256: `8fbcace05bbd23b09fbbf141f857791c7864856b49d71b1bcb1b31608f21ac4e`
- RetroArch binary sha256: `d377e9ed983290d3829dc17e551561558e75b16ebf55bad49d0b0449178f1664`
- QuickNES core sha256: `da48490d5aab244bc0c13e6381555ac2003b438336dafe7db122043503686c68`

## Why

The previous live test matched RetroArch to the measured display cadence:

```text
video_refresh_rate = "59.06063"
```

That removed the repeating audio stutter, but the user reported that the pitch
felt slightly low. This confirms that the panel is really running near 59.06 Hz
and RetroArch is slowing audio/video to follow it. The proper test is to move
the LCD timing closer to 60 Hz and return RetroArch to normal 60 Hz pacing.

## Timing Change

The source KNULLI V90S LCD timing is:

```text
lcd_dclk_freq = 25
lcd_hbp = 100
lcd_ht = 825
lcd_hspw = 20
lcd_vbp = 16
lcd_vt = 514
lcd_vspw = 4
```

With the measured clock inferred from the display interrupt cadence, changing
only `lcd_ht` from `825` to `812` should move the panel close to 60 Hz while
leaving vertical timing unchanged:

```text
lcd_ht = 812
lcd_vt = 514
estimated refresh = about 60.006 Hz
hfront porch = 812 - 640 - 100 - 20 = 52
vfront porch = 514 - 480 - 16 - 4 = 14
```

## Build Notes

`scripts/patch-v90s-boot-package-lcd-timing.py` patches the embedded DTB cell
inside the known-good KNULLI `boot_package.fex` by copy. It preserves the boot
package size, headers, component offsets, and padding.

The generated patch log was:

```text
dtb offset=0xaa000 length=153088
patched /soc@03000000/lcd0@01c0c000:lcd_ht 825 -> 812
wrote output/boot-packages/powkiddy-v90s-lcd-ht812.fex
```

Binary comparison against the stock boot package showed exactly one changed
byte:

```text
old_len=4702208 new_len=4702208 diff_count=1
0x000bbe8f: 0x39 -> 0x2c
```

The SD image raw boot-package region at offset `16793600` was extracted and
matched the generated boot package:

```text
raw_boot_package_cmp_rc=0
8fbcace05bbd23b09fbbf141f857791c7864856b49d71b1bcb1b31608f21ac4e  output/boot-packages/from-image-lcd-ht812.fex
```

The regenerated rootfs contains the current KNULLI-style RetroArch binary and
the current launcher. The launcher default is back to normal 60 Hz:

```text
video_refresh_rate = "${PLUMOS_V90S_VIDEO_REFRESH_RATE:-60.000000}"
audio_device = "hw:0,0"
```

## Expected Device Test

Write `plumos-v90s-armbian-step2-20260710-1-lcd-ht812.img` to SD and boot with
the USB Wi-Fi dongle attached.

Primary checks:

```text
Does the panel boot and show RetroArch/game video?
Does the on-screen FPS move from about 59.05 to about 60?
Does NES audio keep normal pitch without the one-second stutter?
Does the controller mapping remain usable?
```

If SSH is reachable, measure the display interrupt cadence again for 15 to 30
seconds and compare it to the previous 59.06 Hz measurement.

## Device Result

User result:

```text
The screen was black.
```

An SSH check against the previously known address did not connect:

```text
ssh root@192.0.2.118
ssh: connect to host 192.0.2.118 port 22: Operation timed out
```

A quick LAN scan did not find a new obvious V90S SSH target. This does not prove
the OS failed to boot, but it means this test cannot be treated as "LCD only
failed while Linux kept running normally".

Conclusion: `lcd_ht=812` is rejected as too risky for the panel/boot path. The
next candidate should leave the horizontal timing unchanged and only adjust the
vertical total.
