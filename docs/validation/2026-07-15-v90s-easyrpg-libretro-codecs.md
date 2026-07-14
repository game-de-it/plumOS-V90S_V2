# V90S EasyRPG Libretro Codec Validation

Date: 2026-07-15

## Symptom

EasyRPG loaded the indexed `TurnedIntoAGirl` project through RetroArch, but its
MP3 BGM did not play. The physical V90S log reported:

```text
Warning: Couldn't play BGM .../Music/Switch (1991) full intro - The Best Friends co ltd.mp3. Format not supported
```

RetroArch audio output itself was working. The failure occurred before audio
submission because the EasyRPG core did not contain an MP3 decoder.

## Cause

The V90S EasyRPG libretro recipe inherited the first minimal A30/MMF probe
configuration. It explicitly disabled almost every optional runtime feature:

- MP3 through mpg123
- WAV fallback through libsndfile
- Ogg Vorbis and Opus
- MOD through libxmp
- ICU encoding detection and XML data support
- FreeType and HarfBuzz text rendering
- SpeexDSP and libsamplerate resampling

The mature standalone EasyRPG recipe already enabled this practical feature
set, so the libretro recipe was the inconsistent path.

## Build Fix

`build-libretro-cores.sh` now enables and verifies:

```text
Audio backend: libretro
WAV playback: built-in (dr_wav);libsndfile
MIDI playback: built-in (FmMidi)
MP3 playback: mpg123
Ogg Vorbis playback: libvorbis
MOD playback: libxmp
Opus playback: opusfile
Resampler: speexdsp
Font rendering: Freetype with Harfbuzz / built-in
```

Native MIDI remains disabled deliberately. A libretro core must submit audio
through the RetroArch callback rather than opening an independent ALSA MIDI
path. WildMidi, FluidSynth, and FluidLite also remain disabled; the built-in
FmMidi path provides MIDI playback without external soundfont ownership.

The build stages the recursive non-glibc dependency closure under
`lib/libretro` using exact ELF SONAME filenames. This produced 29 runtime
libraries and resolved mpg123, sndfile, Vorbis, Opus, XMP, ICU, font, and
resampler dependencies with no `not found` entries. The isolated output passed
its complete `checksums.sha256` verification.

The standalone recipe now explicitly pins the same practical codec, text, and
data feature set so future Docker package changes cannot silently remove them.

## Physical V90S Proof

The rebuilt core was deployed through the normal FE RetroArch route:

```text
core: /mnt/plumos/cores/easyrpg_libretro.so
content: /mnt/plumos/roms/EASYRPG/TurnedIntoAGirl
core sha256: 8ee20c60c9da7287697ca955c722185099941b7b3f388f3ad87b0e24aa30a711
```

The old core was preserved as:

```text
/mnt/plumos/cores/.backup/easyrpg_libretro.pre-full-codecs-20260715.so
sha256: c2b614f3fbebc1b294b1ee17ee0203a39539f2c1765f4f0ffba4dc33d25cc471
```

Live process evidence showed `libmpg123`, libsndfile, Vorbis, Opus, XMP,
SpeexDSP, ICU, FreeType, and HarfBuzz loaded by RetroArch. ALSA PCM was
`RUNNING`, the previous `Format not supported` warning was absent, and the user
confirmed that the game's BGM played normally.
