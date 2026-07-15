# V90S ALSA mono speaker and USB DAC routing validation

Date: 2026-07-15

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

`/mnt/plumos/bin/plumos-audio-output prepare` detects the playback route at
each application launch and writes:

```text
/run/plumos/audio/asound.conf
/run/plumos/audio/output.status
```

With the built-in codec, the generated transfer table is:

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

When a USB playback card is present, the generated logical PCM is an ALSA
`plug` connected to `hw:<usb-card>,0`. It does not apply the mono transfer table.
The selected route is recorded as `mode=usb_stereo`.

The shared route is used by:

- RetroArch
- PicoArch
- standalone emulators
- plumOS Music Player

No launcher silently falls back to raw internal audio if route preparation
fails. A route failure is reported and that application launch stops.

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
- an invalid explicit `PLUMOS_USB_AUDIO_CARD` is rejected instead of falling
  back to the internal card

The live vendor kernel reports:

```text
CONFIG_SND_USB_AUDIO=y
```

USB Audio Class support is therefore built into the kernel rather than
depending on a separately deployed module.

Physical USB DAC left/right separation remains to be tested when a DAC is
connected. Connect the DAC before launching or relaunching an application;
active ALSA streams are not migrated during hotplug.
