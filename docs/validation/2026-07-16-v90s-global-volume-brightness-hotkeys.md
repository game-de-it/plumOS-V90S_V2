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

- the internal speaker uses the StockOS `Headphone` / `HpSpeaker` ALSA mixer;
- a USB DAC uses software gain in
  `libasound_module_pcm_plumos_hotplug.so`, because the DAC is not guaranteed
  to expose a writable hardware mixer;
- the running ALSA plugin reads `/run/plumos/volume/current` first and falls
  back to `/mnt/plumos/config/system/settings.json`.

The frontend no longer treats physical `KEY_VOLUMEUP` / `KEY_VOLUMEDOWN` as
frontend actions. The resident service is the only physical volume-key owner,
which prevents duplicate increments while the FE is active.

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
26de5470ce52e738dbb946262bfa8f7584f458b8a4340345cee85198a513955a  bin/plumos-controller-ui-fbdev
a70d131ef6d00f1b9d3a5be66a61d1294b065242984cab6e75c97c2719e6984c  lib/alsa-lib/libasound_module_pcm_plumos_hotplug.so
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
