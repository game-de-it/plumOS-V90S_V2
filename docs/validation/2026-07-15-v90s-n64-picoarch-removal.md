# V90S N64 PicoArch removal

Date: 2026-07-15

## Decision

PicoArch is not an N64 execution path on V90S. N64 hardware-render cores use
interfaces that are not supported reliably by the current V90S PicoArch host.
The frontend must expose only these N64 profiles:

```text
retroarch:parallel_n64
standalone:mupen64plus
retroarch:mupen64plus_next
```

## Implementation

`systems.json` already contains only the three supported profiles. The unwanted
PICO choices came from frontend companion generation, which automatically made
a `picoarch:*` choice for each `retroarch:*` profile when the PicoArch adapter
was installed.

N64 is now excluded from PicoArch companion generation, as Saturn already is.
Consequently, stale N64 `picoarch:*` overrides are not listed and cannot become
the effective launch profile.

## Validation

Build and inspect the N64 profile list with the PicoArch adapter present:

```text
PLUMOS_ROOT=output/frontend/v90s/plumos \
  output/frontend/v90s/plumos/bin/plumos-text-ui core system n64
```

The Docker-built frontend was deployed to the live V90S and produced exactly
the three profiles above with no `picoarch:` entry. The deployed binary hash
matched both generated outputs:

```text
6658921937b0c24bb75621f10254a7296cf1095f0685d379c0466e19d9d4a0e5  plumos-text-ui
```

The stale N64 system override `picoarch:parallel_n64` was cleared while keeping
its `ondemand` CPU policy. The effective profile then became the plumOS default
`standalone:mupen64plus`. An explicit attempt to restore the removed profile
was rejected:

```text
error: launch profile is not listed for n64: picoarch:parallel_n64
```

Final live state:

```text
frontend processes: 1
RetroArch processes: 0
/mnt/plumos: rw
```
