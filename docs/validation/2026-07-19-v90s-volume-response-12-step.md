# V90S 12-step volume response

Date: 2026-07-19

## Goal

Make the physical volume keys respond immediately during gameplay and reduce
the user-facing range from 20 to 12 steps without changing the validated audio
route:

- internal speaker: mono mix through `plumos_hotplug`, fixed codec `DAC volume`
  `170,170`;
- USB DAC: stereo through the same logical output;
- shared user volume: software gain `0..12`;
- volume zero: software silence without disabling the physical PCM path.

## Previous delay

The old physical-key path launched `plumos-volume-control` for every repeat
event. That shell helper synchronously performed several `amixer` operations
before publishing the new software volume. The running audio plugin also
sampled the runtime value only once per 16 transfer callbacks. Depending on
the application buffer size, the audible update could therefore lag behind a
button press and encourage unnecessary repeated input.

## Current design

`plumos-hardware-keys` now owns the low-latency key path:

1. Initialize the audio backend and tmpfs value once when the service starts.
2. Read the current value from `/run/plumos/volume/current`.
3. Clamp the requested change to `0..12`.
4. Atomically replace the tmpfs value directly from the resident C process.
5. After 750 ms without another volume event, invoke
   `plumos-volume-control persist-runtime` once.

No process is launched and no filesystem-backed setting is written for each
physical-key repeat. `plumos_hotplug` reads the tmpfs value on every audio
transfer, so an already-running application observes the new gain promptly.

The persistent setting remains
`/mnt/plumos/config/system/settings.json`. On the four-partition layout this is
on `PLUMOS_SYS` p3, which is ext4. The volatile state is tmpfs. Neither the key
path nor idle persistence writes the volume setting to the FAT32 `PLUMOS` p4
user partition.

## Build validation

The following commands completed successfully after the change:

```text
scripts/docker-build.sh frontend
scripts/docker-build.sh audio-router
scripts/docker-build.sh app-layer --strict
git diff --check
```

A fake-backend helper test verified saturation at both limits and persistence
of a runtime value. Incrementing above 12 remained at 12, decrementing below 0
remained at 0, and persisting runtime value 7 produced saved value 7.

## Real-device validation

The app layer was deployed over ADB. Host and device SHA-256 values matched:

```text
d7076e5c58040b8192e69e208f4d16b1b00ef4a15980a7dcc75b836f947454ea  plumOS-hardware-keys
8d9d27a8a4c5894f2977ccc257dd13de56bb29660064d7f988919c13fc4d510e  plumOS-hardware-keys-service
c70f4a7c0df2b13bd0bb704d1ab0d7e64499afc2071bcd15149238a98cb6a219  plumOS-volume-control
6226e36e6746b886faf67e6bda5e2ee8f5634b912bd61e35029b29dad36f4cb3  plumOS-controller-ui-fbdev
bddd33d92c6a516c9b2d0139c60e60e815df8ed47dadbffd059f60b32ce14fc9  libasound_module_pcm_plumos_hotplug.so
```

One physical `Volume +` press changed runtime volume from 1 to 2 immediately.
After the idle interval, runtime and saved values were both 2, and the service
log recorded exactly one action and one persistence event:

```text
hardware-keys: action=volume direction=up rc=0
hardware-keys: persist=volume rc=0
```

Repeated presses reached and stopped at 12. The user confirmed that the new
response felt immediate. A later live check showed runtime and saved value 1
still agreeing, with the expected filesystems:

```text
/run/plumos/volume/current                  tmpfs runtime
/dev/mmcblk0p3 /mnt/plumos                 ext4, data=ordered
/dev/mmcblk0p4 /mnt/plumos-user            vfat, errors=remount-ro
```

The startup path was also tested after stopping the service and removing the
tmpfs value. Starting the service recreated runtime value 1 from persistent
value 1 before accepting key input, and the daemon remained running.

## Separate GB regression check

The first GB launch attempted `/mnt/plumos/roms/GB/ARETHA.gb`, which Gambatte
rejected as corrupt or unsupported. Its malformed content and prior validation
history predate this volume change. It was preserved as `ARETHA.gb.invalid` so
the frontend no longer indexes it. The valid `Aretha (Japan).gb` launched with
Gambatte and active PCM playback, confirming that the volume work did not
regress the GB launch path.
