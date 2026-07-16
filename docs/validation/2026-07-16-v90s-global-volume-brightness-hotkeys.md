# V90S global volume and display hotkeys

Date: 2026-07-16

## Goal

Keep the physical V90S volume keys available independently of the frontend,
RetroArch, PicoArch, and standalone-emulator process lifetime:

- `Volume -` / `Volume +`: change the global plumOS volume.
- `Select + Volume -` / `Select + Volume +`: change the visible display
  luminance.

The vendor kernel does not expose a hardware backlight endpoint. The display
combo therefore controls the supported V90S `enhance_bright` endpoint, which
is the same backend as the frontend `Lumination` setting.

## Runtime design

`plumos-hardware-keys` is a small boot-persistent evdev daemon. It:

- finds `adc_gamepad` and `sunxi-keyboard` by `EVIOCGNAME`, not fixed event
  numbers;
- reads both devices without `EVIOCGRAB`, preserving normal controller access
  for applications;
- tracks `BTN_SELECT` from `adc_gamepad` and `KEY_VOLUMEDOWN` /
  `KEY_VOLUMEUP` from `sunxi-keyboard`;
- tracks `BTN_SELECT` plus `BTN_START` and, after a one-second hold, invokes
  the ownership-validated PortMaster port stop helper once per hold;
- supports held-key repeat after 450 ms at 120 ms intervals;
- retries missing or recreated input nodes every two seconds;
- writes runtime state immediately, then persists it after 750 ms of idle
  time to avoid one FAT32 write per repeat event;
- flushes pending settings on a normal `SIGTERM` service stop.

`plumos-hardware-keys-service start|stop|restart|status` owns the singleton PID
and log below `/run/plumos/hardware-keys`. The system-rootfs app-layer
bootstrap starts it before the frontend. The frontend launcher also performs
an idempotent start so app-layer-only updates and manual frontend launches use
the same service.

## Volume routing

`plumos-volume-control` remains the single 0..20 volume policy:

- the internal speaker and USB DAC both use 0..20 software gain in
  `libasound_module_pcm_plumos_hotplug.so`;
- the internal path keeps the StockOS `Headphone` / `HpSpeaker` ALSA controls
  as a fixed output stage and mute switch;
- the running ALSA plugin reads `/run/plumos/volume/current` first and falls
  back to `/mnt/plumos/config/system/settings.json`.

The frontend no longer treats physical `KEY_VOLUMEUP` / `KEY_VOLUMEDOWN` as
frontend actions. The resident service is the only physical volume-key owner,
which prevents duplicate increments while the FE is active.

## PortMaster forced exit

`Select + Start` held for one second is the emergency exit for a running
PortMaster port. The resident service does not signal arbitrary processes. It
calls `/mnt/plumos/bin/plumos-portmaster-port-stop`, which validates the saved
PID, start time, session/process-group ownership, and script path before sending
`TERM` and, only after a bounded wait, `KILL` to that owned process group.

Live validation used a hung `8-BIT BUCCANEER` session with owned PID/PGID
`31349`. The hold produced:

```text
hardware-keys: action=portmaster-force-exit rc=0
```

Afterward, every process in PGID `31349` was absent, all three PortMaster port
ownership files were removed, and exactly one frontend remained. The hardware
key daemon, ADB, and SSH stayed running. The framebuffer showed the FE `PORTS`
list with `8-BIT BUCCANEER` selected.

```text
output/validation/portmaster-v90s-force-exit/frontend-restored.png
SHA-256: 1cfc816c6568256e56cfbbfe0afe5e6d3ca28db390ba982e95bf0667f274d958
```

## Display routing

`plumos-display-control` owns runtime and persistent luminance changes:

```text
setting: /mnt/plumos/config/system/settings.json -> lumination 0..10
runtime: /run/plumos/display/lumination
backend: /sys/class/disp/disp/attr/enhance_bright -> 0..100
```

This is display processing rather than PWM/backlight power control. The
distinction remains visible in the frontend: unsupported hardware
`Brightness` stays `N/A`, while `Lumination` is writable.

## Live validation

Device connection:

```text
ADB serial: plumos-v90s-e14ba0b5
```

After deployment and one safe frontend restart:

```text
frontend_count=1
hardware_key_count=1
/dev/input/event4 adc_gamepad
/dev/input/event0 sunxi-keyboard
app_layer=ready
version=0.1.0-dev
vendor=v90s-stockos-r1
```

The physical sequence `Volume -`, then `Select + Volume +`, produced:

```text
hardware-keys: action=volume direction=down rc=0
hardware-keys: persist=volume rc=0
hardware-keys: action=display-lumination direction=up rc=0
hardware-keys: persist=display-lumination rc=0

volume: 14 -> 13
lumination: 5 -> 6
enhance_bright: 50 50 -> 60 60
```

Only one volume decrement occurred while the frontend was active. The test
values were restored to volume `14`, lumination `5`, and `enhance_bright`
`50 50` afterward.

The service was then restarted without restarting the frontend. It returned
as one process, reopened both named input devices, and left the settings file
checksum unchanged.

Singleton recovery was also tested by deleting only `service.pid` while the
daemon remained alive. `start` adopted the existing PID `4613`; a direct
second daemon invocation failed with `another daemon owns the service lock`,
and the live process count remained one.

Deployed hashes:

```text
ac1e43cc85fa1f397a68e755067327138191dc9df1f0551638c2f098d31d19b4  bin/plumos-hardware-keys
f069e5eef651f4c2726c1a05e84466a945bc43df4f411153005587763b364ed3  bin/plumos-hardware-keys-service
5d407cc78e0eef5623c7c7e63f6e18d21c61ba295d6fcf69686feb5ec3d5e942  bin/plumos-display-control
3ef2f7f48b86c349163ab1b686388f93616ba4217dfcc2afa1417a0bc5c363ea  bin/plumos-volume-control
4c39d37ac0cf2dc52f28634cfd702189e7c20c2f2b4e09d3f2f1d9236080fad9  bin/v90s-retroarch-launch
26de5470ce52e738dbb946262bfa8f7584f458b8a4340345cee85198a513955a  bin/plumos-controller-ui-fbdev
5cefdad859b61bdb219fd65f980f20e866099730d905b6d27f2f7ad309d70030  lib/alsa-lib/libasound_module_pcm_plumos_hotplug.so
```

## Build validation

The following completed successfully:

```text
./scripts/docker-build.sh frontend
./scripts/docker-build.sh audio-router
./scripts/docker-build.sh app-layer
./scripts/docker-build.sh system-rootfs
```

The rebuilt release-system squashfs is 73.13 MiB. A host-side fake-sysfs test
also confirmed `plumos-display-control runtime-up` changes `5 -> 6`, writes
`50 -> 60`, persists the JSON setting atomically, and removes transient state.

## Internal volume correction

The first live gameplay test found that physical key events and saved values
changed, but relying on the seven-step `Headphone` mixer did not produce a
useful audible volume range. The audio router was corrected so the same 0..20
software gain used for USB output is also applied after internal stereo-to-mono
mixing. For nonzero volume the hardware `Headphone` gain now remains fixed;
volume zero emits software silence while keeping the hardware output stage
active so the synchronized PCM stream continues consuming samples.

Further live tests isolated the actual speaker gain control:

- `Headphone` and `LINEOUT volume` changes produced no audible change.
- plumOS software gain `20 -> 4` produced a clear change.
- codec `DAC volume` `160 -> 32` produced a clear change.
- the original test selected `190,190`, but it was performed with an unstable
  software-volume state and later proved to distort at software volume 20.
- a repeat test at software volume 20 selected `170,170` as the highest value
  without audible distortion.

The corrected policy therefore fixes internal card 0 `DAC volume` at `170,170`
during boot/service initialization and emulator launch, then applies the user
0..20 setting only through software gain. USB-DAC playback remains stereo and
does not use the internal card-0 mixer value.

Live startup-path proof changed card 0 manually to `160,160`, restarted only
`plumos-hardware-keys-service`, and observed:

```text
dac_before_service_restart=160,160
dac_after_service_restart=190,190 (superseded by the 170 correction)
volume=20
frontend_count=1
game_pid=14776
```

The frontend and running standalone game were not restarted by this check.

On 2026-07-17, a 50 ms live trace around Flycast Xtreme startup showed the
vendor PCM preparation changing the control after the launcher had set it:

```text
PCM=SETUP     DAC=190,190
PCM=PREPARED  DAC=160,160
PCM=RUNNING   DAC=160,160
```

The shared ALSA ioplug now restores the validated `170,170` immediately after
the physical PCM reaches `PREPARED`, covering RetroArch, PicoArch, standalone
emulators, and Music Player without changing USB-DAC gain.

Live validation of the corrected plugin on 2026-07-17 showed:

```text
silent plumos_output RUNNING: DAC=170,170
silent plumos_output closed:  DAC=170,170
Flycast Xtreme RUNNING:       DAC=170,170 owner_pid=22056
Flycast Xtreme stopped:       DAC=170,170
software volume:              20
frontend after validation:    one process
```

Build/deployment evidence:

```text
99e12e0a3ed0f2ed4025bcb51371c51015d07ab25385c171829eedb8942ddb6d  libasound_module_pcm_plumos_hotplug.so
d81f5919f7d5c8a93af79313c8407964741c5901603131b70386fcb16326df31  output/frontend/v90s/checksums.sha256
37f38fea7473421920f474841bc456c472cca8d88e4d8b0972d091f427f9a4ee  output/app-layer/v90s/checksums.sha256
14615634d9d4abc6180b3a39a522e0f11ad265eb55370c5e100e43975f5522f7  output/app-layer/v90s/manifest.json
```

The plugin hash matched `/mnt/plumos/lib/alsa-lib/` on the live device.

## Software-volume-zero runloop validation

On 2026-07-17, lowering software volume from 1 to 0 while RetroArch Flycast
Xtreme was running caused the on-screen rate to fall to 9.74 fps and gameplay
input appeared unresponsive. This was not a CPU, GPU, thermal, memory, or I/O
limit:

```text
CPU governor: performance
CPU frequency: 1800000 kHz
GPU frequency: 702 MHz
CPU/GPU temperature: approximately 51-62 C
memory pressure: none
I/O wait: 0%
RetroArch CPU at the failure: approximately 3.3% of one core
RetroArch threads: futex/poll wait
PCM delay/avail: 3072/0 frames
```

The volume-zero branch had disabled `HpSpeaker` and muted `Headphone`. The
physical PCM stopped draining, and RetroArch's required `audio_sync=true`
therefore held back the entire emulation runloop. Restoring software volume 20
immediately raised RetroArch to approximately 64% of one core split between its
main and rendering threads.

`plumos-volume-control` now leaves `HpSpeaker`, `LINEOUT`, and `Headphone`
enabled at volume zero. The ALSA ioplug already multiplies samples by zero, so
the output remains silent without stopping codec DMA. Repeating the live test
at software volume zero produced:

```text
RetroArch main thread:   34.71%
RetroArch render thread: 28.16%
RetroArch audio thread:   1.39%
PVR interrupts:          236.4/s
PCM state:               RUNNING
PCM delay/avail:         2133/939 frames
DAC volume:              170,170
CPU idle:                approximately 93%
```

No competing background process exceeded 3.3% of one core. This confirms the
9.74 fps event was an audio-route stall, not a V90S performance limit.
