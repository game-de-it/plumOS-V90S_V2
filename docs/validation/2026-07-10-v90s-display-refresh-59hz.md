# V90S Display Refresh Is About 59.06 Hz

Date: 2026-07-10

## Context

The user confirmed that the previous minimal RetroArch route restored both
controls and audio. The remaining problem is that RetroArch's on-screen FPS
counter appears fixed around `59.05fps`.

The live route at the time of this check was:

```text
RetroArch: pid=5920 running comm='retroarch-knull'
video_driver = "gl"
video_context_driver = "mali_fbdev"
video_threaded = "false"
audio_driver = "alsa"
audio_device = "hw:0,0"
input_driver = "sdl2"
input_joypad_driver = "sdl2"
input_autodetect_enable = "true"
```

RetroArch logs confirmed that the emulator is still using the patched PowerVR
GE8300 route:

```text
[Mali] Native fbdev window rejected; retrying EGL surface with NULL native window.
[GL] Found GL context: "fbdev_mali".
[ALSA] Initialized PLAYBACK device "hw:0,0".
```

## Framebuffer Report

The framebuffer reports a rounded 60 Hz mode:

```text
/sys/class/graphics/fb0/modes=U:640x480p-60
/sys/class/graphics/fb0/virtual_size=640,960
/sys/class/graphics/fb0/bits_per_pixel=32
/sys/class/graphics/fb0/stride=2560
```

That string is not precise enough to prove the real panel refresh.

## Interrupt Measurement

The Allwinner display interrupt line is visible as `dispaly` in
`/proc/interrupts`, and the PowerVR interrupt line is visible as `pvrsrvkm`.
Sampling those counters while RetroArch was running gave:

```text
duration=15.01s display_delta=888  display_hz=59.16056 pvr_delta=1776 pvr_hz=118.32112 pvr_per_display=2.00000
duration=30.02s display_delta=1773 display_hz=59.06063 pvr_delta=3547 pvr_hz=118.15456 pvr_per_display=2.00056
```

This matches the user's `59.05fps` observation closely. The FPS is therefore
very likely being limited by the real display/vsync cadence, not by CPU load,
USB/Wi-Fi, or the NES core.

At the same time the CPU was not pinned:

```text
load average: 0.55, 0.54, 0.46
cpu0 governor=ondemand cur=1008000 min=408000 max=1800000
```

## KNULLI Boot Timing

The KNULLI V90S boot package DTS contains these LCD timings:

```text
lcd_driver_name = "RGP35_NV3051";
lcd_x = <0x280>;          // 640
lcd_y = <0x1e0>;          // 480
lcd_dclk_freq = <0x19>;   // 25 MHz nominal
lcd_hbp = <0x64>;         // 100
lcd_ht = <0x339>;         // 825
lcd_hspw = <0x14>;        // 20
lcd_vbp = <0x10>;         // 16
lcd_vt = <0x202>;         // 514
lcd_vspw = <0x04>;        // 4
```

The nominal timing works out to:

```text
25,000,000 / (825 * 514) = 58.95531 Hz
```

The measured `59.06063 Hz` implies the actual pixel clock is about:

```text
59.06063 * 825 * 514 = 25.04466 MHz
```

To get true 60 Hz with the current totals, the pixel clock would need to be:

```text
60 * 825 * 514 = 25.443 MHz
```

That is about `1.59%` above the measured clock.

## SDL/KNULLI Mismatch

KNULLI's A133 SDL2 Mali fbdev patch does not read the actual refresh rate. It
hardcodes `current_mode.refresh_rate = 60` with this source comment:

```text
FIXME: Is there a way to tell the actual refresh rate?
```

So an SDL/RetroArch-facing mode can say 60 Hz while the real display interrupt
cadence is about 59.06 Hz.

KNULLI's libretro configgen does not appear to set a board-specific
`video_refresh_rate`; the A133 default that stood out is `video_threaded=true`.
This means a KNULLI-like userspace may still be running on the same underlying
59 Hz panel timing, unless KNULLI applies a runtime calibration elsewhere.

## Interpretation

The current `59.05fps` symptom is not evidence that QuickNES, CPU frequency, or
audio are too slow. The display timing itself is about 59.06 Hz.

There are two separate next experiments:

1. Match RetroArch to the real panel refresh.

   Set `video_refresh_rate` close to `59.06063` and test whether scrolling/audio
   pacing feels smoother. This will not make the FPS counter read 60; it should
   make RetroArch stop assuming a 60.000 Hz host when the panel is actually
   around 59.06 Hz.

2. Change the LCD timing in the boot package.

   This requires a new SD image because the timing is in the KNULLI boot package
   DTS/FEX. With the measured clock, these candidate totals are near 60 Hz:

```text
lcd_ht=812, lcd_vt=514 -> about 60.006 Hz, hfront porch 52, vfront porch 14
lcd_ht=825, lcd_vt=506 -> about 59.994 Hz, hfront porch 65, vfront porch 6
```

The second path is more direct if true 60 Hz is required, but it is also riskier:
bad LCD timing can produce a blank or unstable panel. It should be tested as a
small dedicated image change.
