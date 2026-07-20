# V90S standalone PCSX-ReARMed validation

Date: 2026-07-21

## Scope

This validation covers the standalone PCSX-ReARMed r26l route launched from
the plumOS frontend on the physical POWKIDDY V90S. The test content was
`PSX/WILD ARMS/SCPS-10028.cue`.

## Runtime design

- PCSX-ReARMed is built as native AArch64 from tag `r26l`.
- SDL 1.2 calls use the pinned SDL12-compat runtime backed by the plumOS V90S
  SDL2/PowerVR build.
- Software video is copied to an asynchronous fbdev presenter. Emulation and
  audio production do not wait for the 58.9 Hz panel update cadence.
- V90S SDL button and evdev hat bindings provide game and menu controls.
- The launcher supplies `-cdfile`, the shared BIOS directory, and the normal
  standalone process supervisor.
- Audio must initialize the ALSA driver. `PLUMOS_PCSX_REQUIRE_ALSA=1` makes an
  initialization failure fatal instead of silently selecting SDL audio.

## FPS and frontend ownership

PCSX's two HUD values have different meanings. The first value is generated
display flips per second; many PlayStation scenes intentionally render at
15 or 30 FPS. The second value is emulated PlayStation VSync events per second,
not the physical LCD refresh rate.

The frontend remains present while a standalone emulator owns the screen, but
it is dormant. During the final game run its `/proc` user/system CPU ticks were
`70,8` before and after a five-second sample. It did not own an ALSA PCM. The
frontend was therefore not the cause of the audio breakup.

## Audio diagnosis

The original ALSA backend opened a nominal 44.1 kHz PCM. On this vendor codec,
the physical pointer advanced at approximately a 48 kHz cadence. The PCM
repeatedly entered XRUN recovery, and `trigger_time` changed about every
0.22-0.45 seconds. This was heard as severe periodic breakup.

The corrected route linearly converts the native 44.1 kHz SPU stream to 48 kHz
and opens the plumOS `plumos_hotplug` ioplug at 48 kHz. The ioplug retains
software volume, internal-speaker mono mixing, and USB-DAC hotplug behavior.

An initial implementation removed XRUNs but produced severe distortion. Paired
PCM captures isolated the fault:

| Capture | Peak | Clipped samples |
| --- | ---: | ---: |
| 44.1 kHz source before the fix | 8014 | 0 |
| 48 kHz output before the fix | 19563 | 0 |

The interpolation denominator was unsigned. C integer promotion converted
negative mixed samples to unsigned values during division, turning a source
sample near `-2` into output near `-12760`. Keeping interpolation weights and
division signed fixed the corruption.

Final paired capture evidence:

| Capture | Duration | Peak | Clipped samples | Maximum adjacent jump |
| --- | ---: | ---: | ---: | ---: |
| source, 44.1 kHz | 27.028 s | 8014 | 0 | 1726 |
| output, 48 kHz | 27.456 s | 7952 | 0 | 1568 |

The first nonzero sample appeared at the same time in both files
(`19.296168 s` source and `19.296167 s` output). The conversion no longer adds
DC offsets, peak growth, clipping, or a discontinuity at the start of audio.

## Physical result

The final physical PCM contract was:

```text
format: S16_LE
channels: 2
rate: 48000
period_size: 1024
buffer_size: 4096
state: RUNNING
```

Across the final observation window, ALSA `trigger_time` remained
`17652.775265665`; no XRUN restart occurred. The user confirmed that the game
audio sounded clean. Display and controller operation had already been
confirmed on the same standalone route.

Deployed hashes matched `/mnt/plumos/checksums.sha256`:

```text
992852796722a4c38cd63066ced661402434bc4c6da468e8be8edc0e935fa439  standalone/pcsx_rearmed/bin/pcsx
8511fe4db636bb750a7974e7d520c30c0985b41306739c371575a9a71b9974a3  standalone/pcsx_rearmed/lib/libSDL-1.2.so.0
270d01d39c2c1b9bf1246756f51590d990ed148b57419af6b6e86a275eef6379  bin/plumos-standalone-launch
```
