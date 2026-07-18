# V90S PortMaster OpenAL Audio Validation

Date: 2026-07-19

## Symptom

Balatro rendered and accepted controls, but produced no sound. Its packaged
OpenAL Soft 1.23.1 runtime ignored `AUDIODEV=plumos_output` and opened ALSA
`default`. Before the default route was managed, the physical PCM used
`S24_LE` and bypassed plumOS mono mixing. Routing `default` through an outer
ALSA `plug` fixed the format but still played only the first buffer:

```text
state: XRUN
format: S16_LE
rate: 48000
period_size: 960
buffer_size: 2880
```

The first custom ioplug implementation also reported submitted frames as its
hardware pointer and exposed an always-writable pipe as its poll descriptor.
OpenAL therefore had no valid physical-consumption signal.

## Fix

- Generate `pcm.!default` as a direct `plumos_hotplug` PCM. Keep the explicit
  `plug` conversion layer on named interfaces such as `plumos_output`.
- Track the submitted ring position separately and report playback progress as
  submitted position minus `snd_pcm_delay()` from the selected physical PCM.
- Forward the selected physical PCM poll descriptors and demangled revents
  through the ioplug callbacks. Route changes are observed before the next
  wait, so the following wait obtains descriptors from the new card.
- Retain marker-controlled startup diagnostics through
  `/run/plumos/audio/debug`; normal launches do not create the marker.

## Live Result

The repaired Balatro process loaded the deployed plugin and continued writing
one physical period per wake:

```text
event=transfer value=960 detail=960 physical=3
event=pointer value=960 detail=1920 physical=3
state: RUNNING
delay: 2080
avail: 800
```

Fifty consecutive 20 ms samples found zero non-running PCM states. The route
remained `internal_mono`, the process continued advancing both hardware and
application pointers, and the user confirmed audible Balatro game audio.
