# V90S RetroArch Sync Sweep

Date: 2026-07-10

## Context

The previous StockOS note said that audio pitch became normal with:

```text
video_refresh_rate = 59.049 Hz
Sync to Exact Content Framerate = on
```

That value is useful as a reference, but it should not be treated as confirmed
for the current KNULLI-kernel plus Armbian-rootfs environment. The current route
uses the KNULLI-derived PowerVR/SDL2/RetroArch stack, and the panel interrupt
measurement on this environment was closer to `59.06 Hz`.

## Current Split

The known behavior is now:

```text
58.955 Hz + Exact off -> audio noise disappears, pitch sounds low
58.955 Hz + Exact on  -> pitch may recover, but popping noise returns
```

This means `Sync to Exact Content Framerate` is not a standalone fix on the
current environment. On a fixed-refresh panel, it can ask RetroArch to pace at
the content rate while the display path still blocks around the real panel
cadence, which can reintroduce audio buffer pressure.

## Test Helper

Use the live SSH helper to apply one profile, restart only the managed
RetroArch process, and keep a config backup on the FAT/share partition:

```text
scripts/v90s-retroarch-tune.sh root@192.0.2.119 --profile dts
scripts/v90s-retroarch-tune.sh root@192.0.2.119 --profile dts-exact-fat
scripts/v90s-retroarch-tune.sh root@192.0.2.119 --profile panel
scripts/v90s-retroarch-tune.sh root@192.0.2.119 --profile hybrid-5925
scripts/v90s-retroarch-tune.sh root@192.0.2.119 --profile hybrid-5950
scripts/v90s-retroarch-tune.sh root@192.0.2.119 --profile stockos-generated
scripts/v90s-retroarch-tune.sh root@192.0.2.119 --profile sixty
```

The helper writes a history line to:

```text
/mnt/share/retroarch/tune-history.log
```

and creates backups like:

```text
/mnt/share/retroarch/retroarch-v90s.cfg.before-tune-<profile>.<timestamp>
```

## Sweep Order

Start with profiles that keep `vrr_runloop_enable=false`. This isolates whether
a slightly higher declared refresh rate can reduce the pitch error without
bringing back the one-second audio popping:

```text
dts          58.95531 Hz, Exact off, latency 64
panel        59.06063 Hz, Exact off, latency 64
hybrid-5925  59.25000 Hz, Exact off, latency 128
hybrid-5950  59.50000 Hz, Exact off, latency 128
sixty        60.00000 Hz, Exact off, latency 128
```

Then test Exact-on only with a thicker audio buffer:

```text
dts-exact-fat    58.95531 Hz, Exact on, latency 192
panel-exact-fat  59.06063 Hz, Exact on, latency 192
stockos-exact    59.04900 Hz, Exact on, latency 128
stockos-generated 58.917103 Hz, Exact on, latency 64, video_threaded on
```

If every profile with normal pitch still produces pacing noise or scroll judder,
the remaining clean path is probably an LCD timing image that makes the panel
interrupt cadence closer to true 60 Hz, followed by returning RetroArch to a
plain 60 Hz configuration.

## Live Checkpoint

The first live run applied:

```text
profile=hybrid-5925
video_refresh_rate = "59.25000"
vrr_runloop_enable = "false"
audio_latency = "128"
video_threaded = "false"
```

The first helper attempt showed an important persistence detail: if the config
is edited while RetroArch is still running, `config_save_on_exit=true` can write
the old runtime state back over the test values when RetroArch stops. The helper
now stops the managed process first, then edits the persistent config, then
starts RetroArch.

RetroArch accepted the second `hybrid-5925` run and logged:

```text
[Audio] Set audio input rate to: 43548.75 Hz.
```

That is less slowed down than the previous measured-panel test at `43409.56 Hz`,
but it is still below the core's `44100 Hz` audio rate. User confirmation of
pitch, popping, and scroll smoothness is pending.

## StockOS Generated Profile

The user's modified StockOS image was later used as a comparison target while
RetroArch was running through EmulationStation. StockOS generated:

```text
video_refresh_rate = "58.917103"
vrr_runloop_enable = true
video_threaded = true
audio_driver = "pulse"
audio_latency = 64
```

Its measured RA-running cadence was:

```text
display_hz=59.02293
pvr_hz=118.04586
```

The new `stockos-generated` profile intentionally copies only the RA timing
portion of that generated config. It does not import StockOS's Pulse/PipeWire,
CPU governor, irqbalance, shader, or evmapy behavior. Those layers should be
tested separately if the RA-only profile is not enough.
