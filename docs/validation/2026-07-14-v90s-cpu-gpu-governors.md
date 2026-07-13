# V90S CPU and GPU Governor Validation

Date: 2026-07-14

## Live CPU Interface

The StockOS-derived Linux 4.9 runtime exposes one CPUFreq policy with these
governors:

```text
interactive conservative userspace powersave ondemand performance schedutil
```

The reported frequency range is 408000-1800000 kHz. The available frequency
table is:

```text
408000 600000 816000 1008000 1200000 1416000 1608000 1800000
```

plumOS exposes only dynamic game-oriented choices: Interactive, Performance,
Ondemand, Schedutil, and Conservative. Fixed MHz, OC presets, userspace, and
powersave are not part of the FE contract.

## Live GPU Interface

`/sys/class/devfreq` is empty on the live V90S. The PowerVR kernel driver is
`pvrsrvkm`, and the vendor debug interface reports:

```text
dvfs:off;
Frequency:700MHz;
```

The GPU and PLL clock debug entries report approximately 702 MHz. Runtime PM is
available through the platform GPU device and uses `power/control=auto`, but no
standard selectable GPU governor is exposed.

## Result

- Use Interactive as the game default.
- Keep Performance selectable for demanding emulators and diagnostics.
- Return the frontend browsing baseline to Ondemand.
- Do not add a GPU governor control without a new, stable, real-device-validated
  vendor interface.

## Deployment Validation

The regenerated frontend, RetroArch launcher, PicoArch launcher, and standalone
launcher were deployed to the live V90S at `192.0.2.120`. Host and device
SHA-256 hashes matched for all five files.

Using the deployed standalone launcher as the governor application path gave:

```text
interactive -> interactive range=408000-1800000
performance -> performance range=408000-1800000
ondemand -> ondemand range=408000-1800000
schedutil -> schedutil range=408000-1800000
conservative -> conservative range=408000-1800000
```

The deployed text UI saved both Interactive and Performance overrides and
rejected the removed `fixed` policy. The frontend was then restarted through
the PID-validated launcher/stop contract. Its live process was
`plumos-controller-ui-fbdev`, and the browsing baseline returned to Ondemand.
