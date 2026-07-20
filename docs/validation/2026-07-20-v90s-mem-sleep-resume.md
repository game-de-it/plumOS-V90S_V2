# V90S mem Sleep and Resume Validation

Date: 2026-07-20

## Scope

Validate the V90S vendor kernel's `mem` system sleep path with the physical
Power key, then repair the one service that did not recover automatically.

The live kernel exposes:

```text
/sys/power/state: freeze mem
```

The RTC wakealarm accepted a bounded test alarm, and `rtc0` reported wakeup as
enabled. A 180-second alarm was armed before each physical test as a recovery
precaution.

## First Hardware Test

The user selected Sleep from the physical power menu and pressed Power after
about ten seconds. Kernel evidence showed a complete `mem` cycle:

```text
PM: suspend entry
PM: Preparing system for sleep (mem)
PM: Suspending system (mem)
Suspended for 10.797 seconds
disp_resume finish
PM: suspend exit
```

LCD, frontend, hardware-key service, and Wi-Fi recovered. The Mac saw the USB
gadget disconnect during suspend, but it did not re-enumerate after resume.
The persistent ADB setting remained enabled and `adbd` reopened FunctionFS;
manually toggling ADB OFF and ON rebound the UDC and restored the transport.

## Fix

`scripts/plumos-power-action-rootfs.sh` now records whether the owned ADB
service is enabled and running before system sleep. After a real `freeze` or
`mem` return, it restarts only `plumos-adbd`. It does not alter
`services.conf`, touch SSH, or restart unrelated processes. Dry-run sleep does
not restart ADB.

## Second Hardware Test

The updated helper was bind-mounted over the read-only rootfs helper for a
non-persistent hardware test. The second physical Sleep cycle reported:

```text
PM: suspend entry
Suspended for 8.323 seconds
PM: suspend exit
sleep: restarting adb gadget after resume
sleep: adb gadget restarted
```

Mac-side monitoring observed:

```text
21:09:28 usb=0 adb=none
21:09:44 usb=present adb=none
21:09:48 usb=0 adb=none
21:09:50 usb=present adb=plumos-v90s-d987c006
```

The final state had one frontend process, Wi-Fi at `192.0.2.120`, the
hardware-key service running, ADB `configured`, and no FAT, ext4, MMC, or I/O
error in the post-resume kernel log.

This validates FE-idle `mem` entry and physical-Power resume. Sleep while a
game or App owns video/audio still needs separate per-runtime testing.

## Release-System Build Verification

The tested helper was rebuilt through the formal Docker entry point:

```text
./scripts/docker-build.sh system-rootfs
tracked helper:  2cfe5811ed467934a4f6f3eefa95cb704624b74deef90957656afc5644ca346f
SquashFS helper: 2cfe5811ed467934a4f6f3eefa95cb704624b74deef90957656afc5644ca346f
SquashFS:        e23a9fac63f916e1e7b042dce178e50c3406c8deac4af8b73e47046c047a4b80
```

`./scripts/docker-build.sh preflight` passed the boot package, initramfs,
system SquashFS, app checksum, SD2/frontend, and p3-capacity checks. The live
device test used a temporary bind mount because the running SquashFS is
read-only; the rebuilt SquashFS carries the fix persistently for the next
image.
