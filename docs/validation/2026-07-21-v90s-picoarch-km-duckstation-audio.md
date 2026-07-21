# V90S PicoArch KM_DUCKSTATION audio performance validation

Date: 2026-07-21

## Scope

This validation covers the PicoArch PSX profile using the deployed
`km_duckswanstation_xtreme_amped_libretro.so` core on the physical POWKIDDY
V90S. The test content was `PSX/WILD ARMS/SCPS-10028.bin`.

The frontend label is KM_DUCKSTATION, but the packaged core ID retains the
upstream MMF-compatible spelling `km_duckswanstation_xtreme_amped`.

## Reproduction boundary

The initial report was narrowed to the following scene-specific result:

- the opening movie played cleanly;
- the title screen had severe audio breakup with the `ondemand` governor;
- after leaving the title screen, normal gameplay audio played cleanly;
- changing the live governor to `performance` removed the title-screen audio
  breakup.

This is not a general PSX audio-route failure and must not be described as
gameplay audio always breaking up.

## Runtime evidence

The running process and content were:

```text
picoarch /mnt/plumos/cores/km_duckswanstation_xtreme_amped_libretro.so \
  /mnt/plumos/roms/PSX/WILD ARMS/SCPS-10028.bin NONE
```

PicoArch reported a 44.1 kHz source, a 59.818363 Hz core frame rate, and a
48 kHz output contract. The physical ALSA PCM remained `RUNNING`, retained the
same `trigger_time`, and did not enter XRUN recovery during either governor
sample. The audio breakup therefore came from insufficient or irregular core
work delivery, not from the physical PCM being restarted.

Under the default `ondemand` governor:

```text
governor=ondemand
frequency=816000-1008000 Hz
up_threshold=95
sampling_rate=3150000 us
five-second process CPU delta=816 ticks
```

The workload used about 1.6 CPU cores, but the vendor `ondemand` policy sampled
slowly and did not raise the shared cluster to its 1.8 GHz maximum during the
problem scene.

Under the temporary `performance` comparison:

```text
cpu0-cpu3 governor=performance
cpu0-cpu3 frequency=1800000 Hz
five-second process CPU delta=429 ticks
PCM state=RUNNING
PCM trigger_time unchanged
```

At the higher frequency the same emulated work completed with about half the
scheduled CPU time, and the user confirmed that the title-screen audio breakup
disappeared.

## Conclusion

The Wild Arms title-screen failure is a CPU performance-policy issue specific
to this PicoArch/core workload. `performance` is the verified workaround for
the KM_DUCKSTATION PSX profile. The global V90S default remains `ondemand`;
other systems should not be moved to `performance` solely because of this
result.

