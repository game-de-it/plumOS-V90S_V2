# V90S RetroArch Startup Latency Audit

Date: 2026-07-16

## Symptom

The user observed about eight seconds from FE launch to a RetroArch game while
PicoArch needed about three seconds.

## Difference Found

PicoArch performs the runtime checks needed to launch its core, prepares audio,
creates three runtime-library links, applies the CPU governor, and starts.

The RetroArch launcher still contained its original hardware bring-up sweep on
every normal launch:

- global `sync` after log initialization
- global `sync` for nearly every one of the first 30 log messages
- mount, framebuffer, input, ALSA-device, and complete mixer dumps
- custom SDL2 and PowerVR file/module inventories
- `retroarch --version` and `retroarch --features`
- a 120-line dmesg tail
- SHA-256 of the selected ROM
- a complete copy of the active RetroArch configuration
- further log-mirror `sync` calls before the RetroArch process was spawned
- about 50 repeated `grep`/`sed` config checks against a 3,374-line persistent
  RetroArch configuration, including already-completed migrations

These operations are useful when a new runtime fails, but they are not part of
the normal launch contract. Repeated global syncs are particularly expensive on
the V90S FAT32 app/data partition.

## Change

Normal launch now skips command/config dumps and does not synchronize the whole
filesystem per log line. The existing diagnostics remain available with:

```sh
PLUMOS_V90S_RETROARCH_DIAGNOSTICS=1
PLUMOS_V90S_RETROARCH_SYNC_LOGS=1
```

Persistent configuration migration is now versioned and performed once. The
factory defaults carry the matching marker, while an older or newly created
configuration is upgraded on its first launch. Per-system save and state paths
are passed through the volatile launch append-config instead of rewriting the
persistent configuration for every game. Parallel-N64 setup is both core
specific and one-time.

The generic app-runtime SONAME map currently creates 113 links and took about
1.85 seconds in the old shell loop on the live V90S. A single Python process now
creates them in about 0.42 seconds and signature-caches them in tmpfs. RetroArch
waits for the locked helper only when the cache is not ready, so it no longer
deletes and recreates all links on every game launch. This remains launch-time
work on the first run rather than leaving an unreaped background child under
the vendor PID 1 or moving the cost into frontend startup.

Two further bring-up leftovers were removed from the normal path: scanning all
of `/proc` to find the obsolete framebuffer console, and writing verbose output
from all 16 ALSA mixer assignments to FAT32. The console stop path now uses
`pidof` and still validates both `comm` and `cmdline`; mixer writes are quiet
unless diagnostics are enabled.

The process-owned PID/stop contract, PowerVR/SDL environment, mixer and shared
audio preparation, V90S directory migration, input repair, and launch-time
config overrides remain in the normal path.

## Live Validation

Device: `plumos-v90s-af929c1b`

The measured boundary is launcher invocation to a live RetroArch PID. It does
not include RetroArch's own final video/core presentation time.

| State | Time |
| --- | ---: |
| After only disabling repeated sync/diagnostic commands | 4.83 s |
| Final, cold 113-link cache | 1.00 s |
| Final, warm 113-link cache | 0.81-1.02 s |

The final clean NES validation loaded `quicknes_libretro.so`, redirected saves
and states to `/mnt/plumos/Saves/nes` and `/mnt/plumos/States/nes`, loaded the
ROM, and initialized ALSA playback device `plumos_output`. The final deployed
state has one frontend PID and no RetroArch process.

## Build Evidence

```text
11198b4437187de20672b8a0e7108eb532e24ceb0ce5397ddc3d119de1d1ef65  output/frontend/v90s/checksums.sha256
facc0b95e9285ec6a1f61e6481da04b6054371c06e12cc3a6e7fb68bbeaf233b  output/app-layer/v90s/checksums.sha256
57f1f66e7dce92f6350bac0ad822cc59ef650e5c63a5ab87b53e523c54f4d636  output/app-layer/v90s/manifest.json
94a49237453c710e064f7071e48d334033f2aec886f7d76083563188f19cfe20  output/app-layer/v90s/bin/plumos-app-runtime-prepare
23c366f8ac6458b3f4a4b5da0c8da3a8fa51b772504ead4146bd0aadc723e981  output/app-layer/v90s/bin/v90s-retroarch-launch
```

The two executable hashes matched the deployed files under `/mnt/plumos/bin`.
