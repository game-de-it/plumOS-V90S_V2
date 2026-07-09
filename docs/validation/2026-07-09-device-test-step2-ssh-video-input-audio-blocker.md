# Device Test: Step 2 SSH RetroArch Video/Input OK, Audio Still Blocked

Date: 2026-07-09

## Image

- `output/images/plumos-v90s-armbian-step2-20260709-7-usb-wifi-ssh.img`
- sha256: `a340674105a9a0ef115833e78c9c84b391b31bc49226ccab943b793997150130`

## User Reports

- RetroArch video appeared on the internal LCD.
- V90S built-in controls operated the game.
- Audio did not play.
- The speaker made only a short pop.
- The device has no analog volume control and no headphone jack.

## Working Runtime Route

Live SSH iteration found the stable visible route to be:

```text
video_driver=sdl2
SDL_VIDEODRIVER=mali
SDL_RENDER_DRIVER=software
```

Running the SDL2 video probe immediately before RetroArch, or preferring the SDL2
`opengles2` renderer, can lead back to a black screen. The launcher now skips
the SDL2 probe unless `PLUMOS_V90S_RUN_SDL2_PROBE=1` is set and tries the
software renderer first.

## Audio Evidence

ALSA card:

```text
0 [audiocodec]: audiocodec - audiocodec
```

The playback PCM opens and runs:

```text
access: RW_INTERLEAVED
format: S16_LE
channels: 2
rate: 48000
state: RUNNING
```

DAPM shows the output path active during `speaker-test`:

```text
Playback: On
DACL: On
DACR: On
HPOUTL: On
HPOUTR: On
Headphone: On
HpSpeaker: On
LINEOUT: On
LINEOUT Output Select: On
```

The codec register dump also changes as expected while playback is active:

```text
SUNXI_DAC_DPC        [0x000]: 0x8003f001
SUNXI_DAC_VOL_CTRL   [0x004]: 0x1ffff
SUNXI_DAC_FIFOC      [0x010]: 0x3004010
SUNXI_DAC_CNT        [0x024]: incrementing
SUNXI_DAC_DAP_CTL    [0x0f0]: 0xa0000000
SUNXI_DAC_REG        [0x310]: 0x115f01f
SUNXI_HEADPHONE_REG  [0x324]: 0x80808fcc
```

The speaker PA GPIO is PH6, Linux GPIO 230:

```text
gpio-230 (SPK) out hi    # during playback with the DTS pa_level path
gpio-230 (SPK) out lo    # after playback closes
```

Manual `/dev/mem` tests using `v90s-mmio-rmw` confirmed PH6 can be forced both
low and high during active playback. This is useful for testing PA polarity, but
the user has not yet confirmed sustained audible tone from either polarity test.

## Interpretation

This is no longer a basic ALSA-open or mixer-zero problem:

- ALSA opens the codec PCM.
- The PCM ring is running.
- The DAC FIFO counter advances.
- DAPM marks Playback, DAC, HPOUT, HpSpeaker, Headphone, and LINEOUT active.
- The external speaker PA GPIO toggles and matches the observed speaker pop.

The remaining blocker is below the generic RetroArch/ALSA layer. Likely areas:

- V90S-specific A133 codec analog path initialization.
- Device-tree audio defaults such as `digital_vol`, `lineout_vol`, and `pa_level`.
- A mismatch between the DTS speaker PA polarity and the real board.
- A KNULLI PipeWire/ALSA quirk that is not represented by direct `hw:0,0` tests.

Kernel strings show the driver searches for `dac_digital_vol`, while the current
V90S DTS contains `digital_vol`. This should be tested in a future boot-package
patch, although manual mixer writes already prove that digital and DAC volume can
be changed from userspace.

## Next

- Keep the visible RetroArch route on `sdl2 + mali + software`.
- Continue audio work over SSH before building another image when possible.
- If a reflash is needed, test a boot-package DTS patch for `dac_digital_vol`
  and conservative A133 speaker defaults.
- Keep `v90s-mmio-rmw` as a diagnostic helper only; it writes physical MMIO via
  `/dev/mem` and should not be part of normal runtime behavior.
