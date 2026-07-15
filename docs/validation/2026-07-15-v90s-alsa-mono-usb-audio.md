# V90S ALSA mono speaker and USB DAC routing validation

Date: 2026-07-15 (updated 2026-07-16)

## Purpose

The V90S has one built-in speaker and no headphone jack. A raw two-channel
ALSA test showed that the speaker exposes only the right hardware channel, so
stereo content can lose everything panned left. USB DAC output must remain
normal two-channel stereo.

The previous StockOS fix was published as
[`auto_mono_output`](https://github.com/game-de-it/plumOS-V90S/releases/download/plumOS-V90S_v0.3/auto_mono_output).
That script implemented the same policy with PulseAudio remap sinks. plumOS v2
implements it directly in ALSA and does not require a PulseAudio daemon.

## Channel identification test

The repeatable host command is:

```sh
PLUMOS_ADB_SERIAL=plumos-v90s-5e66cf2c \
  ./scripts/v90s-audio-channel-test.sh
```

The signal is 48 kHz, signed 16-bit stereo:

- left channel: one continuous 660 Hz tone
- right channel: six short 880 Hz tones

Results on the real V90S:

| Route | Result |
| --- | --- |
| raw `hw:0,0` | only the right short tones were audible |
| managed `plumos_output` | both the left continuous and right short tones were audible |

The user confirmed both audible patterns after the ALSA route was applied.

## Runtime implementation

`/mnt/plumos/bin/plumos-audio-output prepare` installs the logical
`plumos_output` PCM and writes:

```text
/run/plumos/audio/asound.conf
/run/plumos/audio/output.status
```

`plumos_output` loads the process-local plugin:

```text
/mnt/plumos/lib/alsa-lib/libasound_module_pcm_plumos_hotplug.so
```

The plugin opens the current physical PCM at the rate, period, and buffer size
negotiated by the application. With the built-in codec, each frame is mixed as:

```text
left input  -> left hardware output  * 0.5
right input -> left hardware output  * 0.5
left input  -> right hardware output * 0.5
right input -> right hardware output * 0.5
```

The factor of 0.5 prevents full-scale left and right samples from clipping when
summed. On the current hardware the audible speaker is the right physical
output, but duplicating the mix to both channels keeps the route independent of
that board-level detail.

When a USB playback card is present, the plugin opens `hw:<usb-card>,0` and
preserves the stereo samples. It checks card availability during transfer and
can replace the physical handle while the logical application stream remains
open. The selected route is recorded as `mode=usb_stereo`.

The shared route is used by:

- RetroArch
- PicoArch
- standalone emulators
- plumOS Music Player

No launcher silently falls back to raw internal audio if route preparation
fails. A route failure is reported and that application launch stops.

No audio server or monitor daemon is involved. RetroArch enables a bounded
nonblocking mode for fast-forward only. PicoArch, standalone emulators, and the
Music Player keep blocking physical writes for ordinary playback.

## Verification evidence

Live internal route:

```text
mode=internal_mono
card=0
card_id=audiocodec
physical_pcm=hw:0,0
pcm=plumos_output
alsa_config_path=/run/plumos/audio/asound.conf
```

Host fixture coverage also confirmed:

- internal `audiocodec` selects `internal_mono`
- a USB playback card takes priority and selects `usb_stereo`
- the generated ALSA configuration points to the packaged ioplug rather than a
  numbered hardware PCM

The live vendor kernel reports:

```text
CONFIG_SND_USB_AUDIO=y
```

USB Audio Class support is therefore built into the kernel rather than
depending on a separately deployed module.

## Physical USB DAC validation

The CX31993 DAC was connected to the V90S OTG port while ADB remained connected
through the separate USB port. The live device reported:

```text
Bus 001 Device 002: ID 3302:3365 TTGK Technology Co.,Ltd
  CX31993 384Khz HIFI AUDIO

0 [audiocodec]: audiocodec
1 [AUDIO]: USB-Audio - CX31993 384Khz HIFI AUDIO
```

The managed route then selected:

```text
mode=usb_stereo
card=1
card_id=AUDIO
physical_pcm=hw:1,0
pcm=plumos_output
alsa_config_path=/run/plumos/audio/asound.conf
```

The channel identification test completed successfully, and the user confirmed
that the continuous left tone and short right tones were audible from their
respective channels through the USB DAC.

## Active-stream hotplug validation

The same running RetroArch process was observed opening:

```text
/dev/snd/pcmC1D0p -> /dev/snd/pcmC0D0p -> /dev/snd/pcmC1D0p
```

while the CX31993 was removed and inserted. The ROM and RetroArch process were
not restarted. The user confirmed normal internal mono audio, normal USB stereo
audio, stable FPS, working fast-forward, and normal audio after leaving
fast-forward.

Standalone YabaSanshiro initially exposed a 44.1 kHz/period mismatch. Matching
the application's negotiated physical period and buffer removed the noise. The
user then confirmed normal internal output, normal USB DAC output, and repeated
DAC removal/insertion during the same game.

PicoArch QuickNES required a separate timing fix. Its synchronous framebuffer
presentation had tied the approximately 60.10 FPS NES core to the 58.955 Hz LCD,
causing recurring ALSA underfeed. A fixed 58.955 audio ratio removed breakup but
lowered pitch, so it was rejected. The accepted build keeps native 48 kHz audio
and presents framebuffer frames from a dedicated nonblocking thread. The user
confirmed perfect USB DAC audio and normal pitch. A second game showed that the
remaining scrolling cadence matched RetroArch on this LCD.

The final physical route status was:

```text
mode=usb_stereo
router=alsa_ioplug_hotplug
card=1
physical_pcm=hw:1,0
pcm=plumos_output
```

The final PicoArch binary SHA-256 is:

```text
df82476720649ccdeba2a39ca3e84e2c8d96da93beda36447d99b62f3f12f400
```

The final strict app-layer was deployed incrementally and validated with:

```text
app_layer=ready
version=0.1.0-dev
vendor=v90s-stockos-r1
```

## Rejected PulseAudio prototype

A minimal PulseAudio sink-migration prototype could move streams, but reduced
Game Boy emulation to about 36 FPS on the real V90S. It was removed. The final
runtime uses ALSA only and does not leave a polling or sink-monitor process.

## Frontend startup incident during validation

After a reboot with the DAC connected, the frontend did not start. USB audio
was not the cause: the CX31993 had already enumerated successfully as ALSA card
1. The app-layer bootstrap stopped on:

```text
critical checksum failed: bin/plumos-controller-ui-fbdev
```

The deployed frontend binary itself matched the current formal app-layer
artifact:

```text
babd87bb95fbb488432bfe960faae876105c32da70b001ecfc614af0f6bbc891
```

Only the device's `checksums.sha256` entry still contained an older frontend
hash. Updating that single metadata entry made all ten bootstrap-critical files
match their formal artifacts, `plumos-app-layer-bootstrap validate` returned
`app_layer=ready`, and the frontend was restored as one process.

The same boot also found a dirty p7 FAT filesystem and repaired damaged state
and SSH configuration cluster chains. That filesystem damage and the stale
incremental-deployment checksum are separate from USB DAC enumeration.
