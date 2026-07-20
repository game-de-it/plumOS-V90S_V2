# V90S PortMaster AArch64 Full Static Dependency Audit

Date: 2026-07-20

## Scope

Run the complete PortMaster AArch64 static audit with every catalog payload,
rather than the initial three-port sample. The audit does not launch games and
does not persistently extract archives.

## Retrieval

The host had 44 GiB free before the audit. The explicit large-download command
was:

```sh
PLUMOS_PORTMASTER_AUDIT_JOBS=4 \
  ./scripts/docker-build.sh portmaster-audit \
  --download-payloads \
  --allow-large-download
```

Result:

```text
catalog ports: 1332
AArch64 candidates: 1126
payloads audited: 1126
payload download size: 24.02 GiB
```

Every selected payload passed its catalog size, MD5, and ZIP validation. The
cache occupies approximately 25 GiB below
`.cache/portmaster-audit/payloads`; 20 GiB remained free after completion.

## Accuracy Corrections

The first complete pass reported 31 missing SONAMEs. Two groups were target
modeling errors rather than libraries that plumOS should package:

1. 358 ports contain Android AArch64 shared objects below `arm64-v8a`. Their
   unversioned Bionic dependencies, including `libc.so`, `libdl.so`,
   `liblog.so`, `libOpenSLES.so`, and Unity Android libraries, are now recorded
   as the `android-bionic` runtime class instead of glibc target failures.
2. 83 ports require `libSDL2_ttf-2.0.so.0`. The normal PortMaster runtime
   already projects this library from `apps/nextcommander/lib` into
   `/run/plumos/portmaster/lib`; that exact directory was added to the target
   contract.

The correction is covered by a seventh unit test. The offline full scan was
rerun against all cached payloads and all report checksums passed.

## Final Status

```text
static-pass:             457
script-or-runtime-only:  134
runtime-unvalidated:     510
missing-libraries:        23 ports
unsupported-armhf:         2
missing SONAMEs:           22
target-contract-missing:    0
AArch64 ELF files:       6757
ARMHF ELF files:          306
```

`static-pass` proves only that the static AArch64 loader closure is available.
It does not prove PowerVR rendering, audio, controls, performance, saves, or
clean frontend return. The 510 runtime-unvalidated entries include the 358
Android/Bionic payloads plus declared external runtime families.

## Common ABI Candidates

Frequency alone does not authorize global packaging. The eight repeated
SONAMEs need the following ownership decisions:

| SONAME | Ports | Decision class |
| --- | ---: | --- |
| `libGL.so.1` | 4 | GL4ES/Weston graphics runtime; not global PowerVR ABI |
| `libXxf86vm.so.1` | 3 | Weston/X11 or Java runtime |
| `libcrypto.so.1.1` | 3 | EOL OpenSSL ABI; isolate with affected ports/runtime |
| `libjawt.so` | 2 | Java runtime |
| `libreadline.so.7` | 2 | genuine next common-ABI candidate |
| `librga.so.2` | 2 | Rockchip-specific; unsupported on V90S |
| `libsndio.so.7.0` | 2 | Weston/Java runtime |
| `libssl.so.1.1` | 2 | EOL OpenSSL ABI; isolate with affected ports/runtime |

Affected ports are recorded in `missing-libraries.tsv`. The legacy
`moonlight.zip` also depends on Rockchip `libgo2`, `libmali`, and `librga`;
those dependencies must not be confused with the validated V90S
`Moonlight New` path.

## Port Or Runtime Local Candidates

These fourteen SONAMEs each affect one port and do not belong in the global
adapter solely on current evidence:

```text
libOpenThreadsrd.so.21  openmw
libWildMidi.so.2        fade_to_black
libXpm.so.4             alicecliche
libXxf86dga.so.1        alicecliche
libboost_system.so.1.67.0 wargus
libffi.so.7             netsurf
libgo2.so               moonlight
libicudata.so.63        vcmi
libicudata.so.66        lierolibre
liblttng-ust.so.0       stardewvalleymainline
libmali.so              moonlight
libmonosgen-2.0.so.1    yknytt
librga.so               moonlight
libzip.so.4             mreader
```

Several are likely owned by declared runtimes rather than the port itself:
Mono owns `libmonosgen`, Weston owns X11 libraries, and Java owns `libjawt`.
Those runtime archives must be acquired and audited before changing the common
runtime.

## Declared Runtime Families

The catalog references 37 distinct runtime archive names. Only
`frt_3.2.3.squashfs` (26 ports) and `frt_3.5.2.squashfs` (72 ports) are marked
validated by the current V90S contract. The unvalidated set affects 208 ports
and contains 295 runtime references because one port can declare more than one
runtime. It spans Dotnet, other FRT/Godot versions, gmtoolkit, Mono, Pyxel,
Ren'Py, RLVM, Solarus, Weston, and Java runtimes.

Runtime-family validation is separate from copying old SONAMEs into the common
adapter. Each runtime needs its own complete ELF closure and representative
real-device video, audio, input, exit, and frontend restoration evidence.

## Artifacts

Generated, git-ignored results:

```text
output/portmaster-audit/v90s/manifest.json
output/portmaster-audit/v90s/summary.tsv
output/portmaster-audit/v90s/missing-libraries.tsv
output/portmaster-audit/v90s/runtime-families.tsv
output/portmaster-audit/v90s/download-plan.tsv
output/portmaster-audit/v90s/portmaster-aarch64-audit.manifest
output/portmaster-audit/v90s/checksums.sha256
```

Verification:

```sh
python3 -m unittest discover -s tests -p 'test_*.py' -v
./scripts/docker-build.sh portmaster-audit --offline
(cd output/portmaster-audit/v90s && sha256sum -c checksums.sha256)
```

Seven tests passed, all 1126 payloads were audited, and all generated report
checksums verified. No live V90S files or user data were changed.
