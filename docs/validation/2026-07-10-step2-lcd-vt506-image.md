# Step 2 LCD VT506 Timing Image

Date: 2026-07-10

## Output

- image: `output/images/plumos-v90s-armbian-step2-20260710-2-lcd-vt506.img`
- image sha256: `4dccd1ace2356ef086a8b97190123a30c89742d03bd4cad5061fc676b5bb062d`
- image size: `581M`
- rootfs payload: `output/rootfs-step2-retroarch-knulli-ssh-lcd60/debian-bookworm-retroarch-knulli-step2.squashfs`
- rootfs sha256: `2c3873d17215964064900a4ebd4b759c47ddf0966aac0482c173aa2e5eb10efb`
- boot package: `output/boot-packages/powkiddy-v90s-lcd-vt506.fex`
- boot package sha256: `699cb0f3e6fd8736db593593aba4fe64083fabab68b95b95f9ee6b81b87efbe0`

## Why

The `lcd_ht=812` image produced a black screen and did not provide a reachable
SSH target during the quick check. This image backs out the horizontal timing
change and tests the alternate 60 Hz candidate:

```text
lcd_ht = 825
lcd_vt = 506
```

Using the previously inferred clock, this should be close to 60 Hz while
preserving the original horizontal timing:

```text
estimated refresh = about 59.994 Hz
hfront porch = 825 - 640 - 100 - 20 = 65
vfront porch = 506 - 480 - 16 - 4 = 6
```

## Build Notes

The generated patch log was:

```text
dtb offset=0xaa000 length=153088
patched /soc@03000000/lcd0@01c0c000:lcd_vt 514 -> 506
wrote output/boot-packages/powkiddy-v90s-lcd-vt506.fex
```

Binary comparison against the stock boot package showed exactly two changed
bytes:

```text
old_len=4702208 new_len=4702208 diff_count=2
0x000bbebe: 0x02 -> 0x01
0x000bbebf: 0x02 -> 0xfa
```

The SD image raw boot-package region at offset `16793600` was extracted and
matched the generated boot package:

```text
raw_boot_package_cmp_rc=0
699cb0f3e6fd8736db593593aba4fe64083fabab68b95b95f9ee6b81b87efbe0  output/boot-packages/from-image-lcd-vt506.fex
```

The extracted image boot package also validated as `lcd_vt=506`:

```text
dtb offset=0xaa000 length=153088
patched /soc@03000000/lcd0@01c0c000:lcd_vt 506 -> 506
```

## Expected Device Test

Write `plumos-v90s-armbian-step2-20260710-2-lcd-vt506.img` to SD and boot with
the USB Wi-Fi dongle attached.

Primary checks:

```text
Does the KNULLI boot logo and RetroArch/game video appear?
Does the on-screen FPS move from about 59.05 to about 60?
Does NES audio keep normal pitch without the one-second stutter?
Does the controller mapping remain usable?
```

If the screen is black again, this suggests the BSP LCD timing may not tolerate
small total changes through `boot_package.fex`, and the next step should return
to stock timing and look for a runtime pacing fix instead.
