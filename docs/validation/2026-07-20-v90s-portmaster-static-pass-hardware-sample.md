# V90S PortMaster Static-Pass Hardware Sample

## Purpose

Check whether a representative sample from the full audit's `static-pass` set
actually crosses the loader boundary on a physical V90S. This is a short
launch-path test, not a claim that every audited port works.

## Device Baseline

- Device: POWKIDDY V90S at `192.0.2.120`
- Installed PortMaster adapter: version 8
- App layer: `/dev/mmcblk0p3` mounted read-write as ext4
- SD2 ROM layer: `/dev/mmcblk1p1` mounted read-write as FAT32
- Audio route during tests: `internal_mono`, ALSA `plumos_output`
- Launcher: `/mnt/plumos/bin/plumos-portmaster-port-launch`
- Stop path: `/mnt/plumos/bin/plumos-portmaster-port-stop stop`

The adapter-v9 Readline addition was not live-deployed for this test. The
sample instead exercises already-installed static-pass ports, including the
adapter-v8 FLAC and JPEG compatibility ABIs.

## Results

| Port | Framebuffer | Audio | Input path | Result |
| --- | --- | --- | --- | --- |
| Apotris | changed from FE and continued changing | card 0 playback `RUNNING` | dedicated `gptokeyb` attached | pass |
| Abombniball | changed from FE to a stable title frame | card 0 playback `RUNNING` | dedicated `gptokeyb` attached | pass |
| A7Xpg | changed from FE and continued changing | card 0 playback `RUNNING` | dedicated `gptokeyb` attached | pass |
| Abu Simbel Profanation Deluxe | changed from FE to a stable title frame | card 0 playback `RUNNING` | dedicated `gptokeyb` attached | pass |
| OpenSyobon | changed from FE to a stable title frame | card 0 playback `RUNNING` | dedicated `gptokeyb` attached | pass |

Representative framebuffer hashes were different from the FE baseline:

```text
Apotris:      559183e7... -> 1c0504b7... -> 153378e8...
Abombniball:  2e2a6f14... -> 0b7d598c...
A7Xpg:        e0a0f6ab... -> 67a6ce49... -> ebbd4d07...
Abu Simbel:   e0a0f6ab... -> 4836b2e6...
OpenSyobon:   6db88f3e... -> 14a09d61...
```

Current launches of A7Xpg, Abombniball, and Abu Simbel did not repeat the old
`libFLAC.so.8` or `libjpeg.so.8` loader failures still visible in historical
log lines. Their game processes remained alive for the observation window.

## Cleanup Evidence

Every port was stopped through its PortMaster-owned process group. Final state:

```text
port_owner=none
frontend_count=1
compat_mount=none
/mnt/plumos=rw
/mnt/plumos/roms=rw
```

No broad process kill, reboot, app-layer deployment, or persistent mount was
used during the tests.

## Validation Boundary

This proves short loader, framebuffer, audio-open, input-helper attachment,
owned stop, and FE restoration paths for five installed ports. The controller
was not physically pressed during this automated pass, so actual button
response is not yet claimed. Extended gameplay, performance, save behavior,
USB-DAC switching, suspend/resume, and title-specific menu behavior also remain
separate tests.
