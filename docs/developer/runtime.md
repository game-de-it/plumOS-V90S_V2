# Boot and Runtime Services

## Four-Partition Boot

The seed image preserves the vendor raw boot offsets and contains p1 through p3.
The provisioning initramfs in p2 identifies the boot disk by the `PLUMBOOT` and
`PLUMOS_SYS` labels, checks minimum capacity, expands GPT, grows p3 to 8 GiB,
creates p4 through the end of the card, formats it FAT32 as `PLUMOS`, and creates
the user directory layout.

Subsequent boots check provisioning markers, clean-shutdown markers, and System
slot state before selecting `System/system-a.squashfs` or
`System/system-b.squashfs` from p1. A verified image is attached to a loop device,
mounted read-only, persistent mounts are moved into it, and the initramfs runs:

```text
switch_root <system-root> /sbin/init
```

First-boot progress and errors are rendered directly to the framebuffer and
copied to host-readable logs when possible. Normal boots use cached verification
only when clean markers and stored hashes agree.

## System Init Order

The System SquashFS init performs these responsibilities:

1. mount or locate p3 `/mnt/plumos` and p4 `/mnt/plumos-user`
2. apply a pending signed update before normal writers start
3. run `plumos-app-layer-bootstrap`
4. validate critical app-layer metadata and prepare writable bindings
5. prepare PowerVR, input, display, ALSA routing, hotkeys, and network runtime
6. mount SD2 content if available
7. start exactly one frontend
8. start enabled network services without blocking frontend readiness
9. mark a pending Runtime or System update healthy only after FE renderer proof

## App-Layer Bootstrap

`scripts/plumos-app-layer-bootstrap.sh` verifies the app-layer contract, binds
p4 `roms`, `bios`, `Images`, and user themes, prepares persistent `/root` and `/etc/shadow`
overlays for SSH, creates runtime library aliases under `/run/plumos`, starts
the hardware-key service, restores enabled services, and launches FE through
the controlled launcher.

Critical checksum failure must prevent an inconsistent frontend from running.
Live deployment therefore updates files and metadata together.

## Foreground Lifecycle

The frontend launcher records PID and ownership state under `/run/plumos`.
Launching a game or app must:

1. acquire the foreground transition lock
2. stop FE rendering and release framebuffer/input descriptors
3. prepare system-specific libraries, config, CPU policy, and audio environment
4. start the selected child plus only the required input helper
5. stop descendants safely on normal exit or global quit
6. release display/audio/input state
7. restore one FE process

Do not use broad `killall` patterns. PID files are accepted only after cmdline
or executable identity checks so emulator shutdown cannot include SSH, ADB, or
unrelated services.

## Safe Power Actions

Restart and shutdown enter a dedicated framebuffer progress screen and block
normal input. The safe path stops foreground content, PortMaster writers,
frontend, network file services, and removable-content bindings; flushes
important files; writes clean markers; unmounts FAT32 and ext4 in dependency
order; then invokes the kernel reboot or poweroff action.

The physical Power key is consumed by the always-running hardware-key service.
It opens a global power overlay over FE, RA, PicoArch, standalone emulators, and
Apps without spawning a second FE. Cancel restores the framebuffer pages,
paused processes, and audio route. Suspend uses `mem`; resume is handled by the
same global service.

## Runtime Logs

| Area | Path |
| --- | --- |
| boot/init | `/run/plumos-boot.log`, persisted under p3 logs/provision state |
| frontend | `/mnt/plumos/Logs/` and `/run/plumos/frontend/` |
| launchers | `/mnt/plumos/Logs/` |
| network services | `/mnt/plumos/Logs/network-services.log` |
| SSH | `/mnt/plumos/ssh/log/sshd.log` |
| update | p3 update state plus `/mnt/plumos-user/plumos-logs/update/` summary |
