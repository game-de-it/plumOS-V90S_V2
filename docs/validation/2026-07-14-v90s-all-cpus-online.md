# V90S All CPUs Online Validation

Date: 2026-07-14

## Problem

The frontend browsing baseline forced CPU2 and CPU3 offline. System and ROM
profiles could also pass CPU-count limits through RetroArch, PicoArch, Pyxel,
and standalone launch commands. A missing system value silently defaulted to
two CPUs, so demanding or newly added emulators could be restricted without an
explicit configuration entry.

## Resolution

- Removed `default_cpu_cores` and `cpu_cores` from frontend system and override
  handling.
- Removed the text UI `--cores` action and all generated `--cores` or
  `PLUMOS_*_CPU_CORES` launch arguments.
- Removed CPU-count parsing from RetroArch, PicoArch, and standalone launchers.
- Changed frontend, scraper, RetroArch, PicoArch, and standalone startup to
  bring CPU1, CPU2, and CPU3 online without ever offlining a CPU.
- Kept dynamic CPU governor selection independent from CPU availability.

## Static Validation

The source tree contains no V90S runtime write that sends `0` to a CPU online
sysfs node. System configuration contains no CPU-count default, and application
launch plans report `cpu_cores: all online` without accepting an override.

## Device Validation

The rebuilt frontend, RetroArch launcher, PicoArch launcher, and standalone
launcher were deployed over ADB. Host and device SHA-256 hashes matched for all
five executable files.

```text
8706b7b65ae380605344d922cb7541529f35223cfecaff076cc4295210879efe  plumos-text-ui
f622b78370dc574dc7abc3949a569f7d4508e6732528e472efd893dbb3963003  plumos-controller-ui-fbdev
2c1e2716e28d5513ed778bfdcafc675795823aeabfe7adc07e5b0e22ff768dde  plumos-retroarch-launch
075d98a55d6e9e3d337fc5c8f35159286650055cde8743857d5d9896d0e998bf  plumos-picoarch-launch
a2235875a69ad4d25964e8173b017745b699cf934738f07c08359d181d5d26b1  plumos-standalone-launch
```

Observed states:

```text
frontend idle:            online=0-3 governor=ondemand FE process count=1
RetroArch QuickNES:       online=0-3 governor=interactive
PicoArch QuickNES:        forced legacy 0-1 state -> launcher restored 0-3
standalone invalid probe: forced legacy 0-1 state -> launcher restored 0-3
```

The live NES launch plan contained no `--cores` argument and reported:

```text
cpu_cores: all online
```

RetroArch and PicoArch were stopped with their PID-validated helpers. The
frontend was then restarted once and remained the only frontend process.
