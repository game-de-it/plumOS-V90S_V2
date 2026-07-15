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

The generated USB configuration used an ALSA `plug` PCM connected directly to
`hw:1,0`; it contained no mono route table. The channel identification test
completed successfully, and the user confirmed that the continuous left tone
and short right tones were audible from their respective channels through the
USB DAC.

Connect the DAC before launching or relaunching an application. Active ALSA
streams are not migrated during hotplug.

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
