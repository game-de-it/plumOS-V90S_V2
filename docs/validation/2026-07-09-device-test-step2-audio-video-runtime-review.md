# Device Test: Step 2 Audio And Video Runtime Review

Date: 2026-07-09

## Device State

Tested live over SSH after booting:

```text
output/images/plumos-v90s-armbian-step2-20260709-8-audio-diagnostic.img
```

The V90S was found at:

```text
192.0.2.111
```

RetroArch was stopped only through `v90s-retroarch-stop`, which validates PID
files against `/proc/<pid>/comm` and does not touch SSH.

## Audio Findings

`v90s-audio-diagnostic profile knulli_dts_loud 10` did not produce useful
game-audio proof. `v90s-audio-diagnostic profile knulli_asound_state 10`
produced a sustained audible tone on the internal speaker.

Live RetroArch game audio then became audible after applying the KNULLI-derived
codec route and raising DAC output for the game run:

```text
codec hub mode: hub_enable
DAC Swap: On
digital volume: 0
LINEOUT volume: 26
DAC volume: 160,160
ADC volume: 160,160
Headphone volume: 2
Headphone Switch: on
HpSpeaker Switch: on
LINEOUT Switch: on
```

This confirms the remaining blocker is not "no audio path". The speaker path is
usable from the Armbian/Debian payload when the KNULLI-derived mixer state is
recreated.

## Debian RetroArch Runtime Tests

Baseline visible route:

```text
video_driver=sdl2
SDL_VIDEODRIVER=mali
SDL_RENDER_DRIVER=software
audio_driver=alsa
audio_device=hw:0,0
```

This route displays the game and accepts V90S controls, but with Nestopia it
used unexpectedly high CPU and game audio broke up. Forcing the CPU governor to
`performance` changed CPU frequency from `1008000` to `1800000` kHz and reduced
observed RetroArch CPU load, but did not fix the visible 59fps pacing issue.

Increasing `audio_latency` from `64` to `128` doubled the ALSA buffer:

```text
Period size: 1536 frames
Buffer size: 6144 frames
```

This improved buffering but did not solve the underlying video pacing problem
with Nestopia.

## QuickNES Test

KNULLI references `libretro-quicknes` at:

```text
058d66516ed3f1260b69e5b71cd454eb7e9234a3
```

A small standalone arm64 build of that core was tested live:

```text
quicknes_libretro.so
sha256: da48490d5aab244bc0c13e6381555ac2003b438336dafe7db122043503686c68
```

With the same SDL2/Mali/software display route, QuickNES removed the audible
audio breakup. However, the user still observed uneven scrolling even though
the FPS overlay was near 60fps. Setting `video_threaded=false` dropped the
runtime to about 50fps and is not viable.

QuickNES is useful evidence that the emulator core matters, but it does not
solve the KNULLI-equivalent video pacing problem by itself.

## Renderer And GL Tests

`SDL_RENDER_DRIVER=opengles2` with `video_driver=sdl2` reduced observed CPU
load substantially, but the LCD became dark and game audio still broke up in
the tested Nestopia run. This route is not currently a valid replacement for
the visible software-renderer route.

`video_driver=gl` reached the PowerVR GL stack:

```text
Vendor: Imagination Technologies
Renderer: PowerVR Rogue GE8300
Version: OpenGL ES 3.2 build 1.19@6345021
```

Then Debian RetroArch crashed with a segmentation fault. This is a strong sign
that the remaining mismatch is RetroArch's video context path, not basic
PowerVR bring-up.

## KNULLI Runtime Contract

KNULLI's RetroArch package enables the native Mali framebuffer context when
`BR2_PACKAGE_HAS_LIBMALI=y`:

```text
RETROARCH_CONF_OPTS += --enable-mali_fbdev
```

That is the key difference from Debian's generic RetroArch package. The current
payload has KNULLI-derived PowerVR libraries and patched SDL2, but not a
KNULLI-equivalent RetroArch binary.

## Decision

Stop tuning the generic Debian RetroArch path as the main line. It is useful
for diagnostics but does not reproduce KNULLI's display contract closely
enough.

Next direction:

- keep the proven KNULLI boot chain, PowerVR userspace, SDL2 `mali` driver,
  audio mixer values, and V90S input path
- build or import a RetroArch binary with KNULLI's `--enable-mali_fbdev`
  configuration
- use Armbian's build system for the rootfs/userspace assembly layer rather
  than hand-maintaining a debootstrap-only rootfs
- continue keeping the FAT partition small and place larger payloads on the
  userdata/rootfs partition
