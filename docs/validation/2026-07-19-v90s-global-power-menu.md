# V90S Global Power Menu Validation

Date: 2026-07-19

## Scope

The V90S Power key must open the same power menu while the frontend,
RetroArch, PicoArch, a standalone emulator, or an App owns the screen. Cancel
must return to the existing runtime without creating a second FE, changing the
normal FE ready marker, stopping SSH/ADB, or leaving audio silent.

## Implementation

- The hardware-key daemon discovers the vendor Power input by its stable
  `axp2202-pek` name.
- If the normal FE PID from `/tmp/plumos-fe-ready` still owns `/dev/fb0`, the FE
  handles Power itself.
- Otherwise `plumos-power-menu-overlay` snapshots the visible framebuffer page,
  pauses only PIDs holding `/dev/fb0`, `/dev/dri/*`, `/dev/mali*`, `/dev/pvr*`,
  or `/dev/disp`, and runs the controller UI with `--power-overlay`.
- Cancel restores all framebuffer pages before resuming exactly those PIDs.
  Reboot and Shutdown continue through `plumos-safe-shutdown`.
- The overlay controller does not write `/tmp/plumos-fe-ready`, so it cannot
  impersonate the normal frontend after returning.

The first shared ALSA recovery fixed standalone YabaSanshiro's post-overlay
XRUN, but PPSSPP exposed a second state: SDL remained logically RUNNING while
the physical PCM had recovered to PREPARED. The `plumos_hotplug` ioplug now
marks a resync only after a real XRUN/SUSPENDED recovery, advances the logical
hardware position past the lost queue once, resets producer-speed history, and
allows fresh callback audio to start the physical PCM. Normal initial PREPARED
state and unrelated device errors do not enter this path.

## Hardware Evidence

The user confirmed:

- RetroArch displays and cancels the power menu normally.
- Standalone YabaSanshiro retains audio after cancel.
- PPSSPP retains audio after cancel.

The final automated PPSSPP run used PID `9810`. Before the overlay, card 0 PCM
was RUNNING. During the overlay it reached XRUN, then recorded:

```text
physical-recover detail=-32 physical=PREPARED
poll-recover revents=POLLOUT
physical-resync logical_appl=50688
```

Five seconds after cancel the same PPSSPP process owned a RUNNING PCM:

```text
state: RUNNING
owner_pid: 9810
delay: 288
hw_ptr: 218080
appl_ptr: 218368
```

The increasing hardware/application pointers prove resumed writes rather than
only a prepared but silent device. `plumos-app-layer-bootstrap validate` also
reported `app_layer=ready` after the selective deployment.

## Deployed Hashes

```text
c49740720674245dcad62e4f603993e3d014ff81a589c166dc5d9e45ac567412  bin/plumos-controller-ui-v90s
d0e07a754293416848068b26a090d3202752ea343fed128d4c2b40aa4c036d47  bin/plumos-controller-ui-fbdev
2948e297b97046a67a6424867f445d34e89d15cce09b02cd1aa3af79fddb5b8e  bin/plumos-hardware-keys
1fad3f33cef91ae7e388e10226bfd98bd35dd20d953706431728743c3fbdfe57  bin/plumos-power-menu-overlay
6b1097a48efcbd5181940a0f2c0904702fd9f47c569d4708a0b8f2a2e91bd82c  lib/alsa-lib/libasound_module_pcm_plumos_hotplug.so
```

Each live update included the matching `manifest.json` and
`checksums.sha256`; mutable user settings, saves, and PortMaster files were not
replaced.
