# V90S Common Application Audio Format Validation

Date: 2026-07-19

## Objective

PortMaster and other third-party applications must not require a new audio
override for every title. ALSA `default`, `plumos_output`, and the existing
named compatibility PCMs therefore converge on the plumOS-owned hotplug router.
The normal route owns software volume, internal-speaker mono mixing, USB-DAC
stereo, and live output-card selection.

## Supported Input Contract

The direct `plumos_hotplug` PCM accepts:

- `S8` and `U8`
- little-endian `S16` and `U16`
- little-endian `S24`, packed `S24_3`, and `S32`
- little-endian `F32`
- mono or stereo
- sample rates from 8 through 192 kHz

All non-`S16` samples are converted inside the router. Mono input is duplicated
to the two-channel physical stream. The internal speaker path subsequently
mixes stereo content to mono, while USB-DAC output preserves stereo.

## Real-Device Matrix

Eight silent 11025 Hz mono streams were opened through ALSA `default` on the
V90S. Every format completed successfully through the shared internal route:

```text
S8:       PASS
U8:       PASS
S16_LE:   PASS
U16_LE:   PASS
S24_LE:   PASS
S24_3LE:  PASS
S32_LE:   PASS
FLOAT_LE: PASS
```

## Kemono Rogue Result

Kemono Rogue requests `11025 Hz / U8 / mono` through SDL2 and does not allow
the obtained application format to change. Before U8 support, its unhandled
`Error: SDL_OpenAudioDevice` string exception appeared only as:

```text
terminate called after throwing an instance of 'char const*'
```

With the common route deployed, the same FE launch started the game, its
GPTokeYB helper, SDL hotplug thread, and SDL audio thread. The physical device
remained active with:

```text
state: RUNNING
format: S16_LE
channels: 2
rate: 11025
period_size: 800
buffer_size: 1600
```

No Kemono-specific ALSA configuration or launcher branch was added.

## Kemono Rogue BGM Package Gap

The game contains separate title and stage BGM paths. Upstream commit
`315509514bfc72cce4d0da62334a2159b36e62ee` opens
`KemonoRogue/title.raw` or `title.adp` for the title screen and
`KemonoRogue/stage.raw` or `stage.adp` during play.

The official PortMaster `kemonorogue.zip` checked on 2026-07-19 did not contain
any of those four files. The installed game therefore had working sound effects
but no BGM even after its audio device opened normally. This is missing game
content, not another V90S audio-route contract.

The smaller upstream ADP files were staged and synced into the existing
installation without replacing either save file:

```text
becc7b75dc8671a7ff034d10fbe169cf45dd6195bfbc6befcb3f2df20b9413e4  title.adp
cd2b009c2ba79bbef2fd30b0819ac7350402eba62208c101741a38e0ac0da6a9  stage.adp
```

After an ownership-safe stop and the same FE relaunch, the running process held
`KemonoRogue/stage.adp` open and the user confirmed audible BGM. A future
PortMaster reinstall may require the upstream package to include these assets;
plumOS must not hide their absence with a title-specific ALSA override.
