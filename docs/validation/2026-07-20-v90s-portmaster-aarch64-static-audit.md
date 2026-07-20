# V90S PortMaster AArch64 Static Dependency Audit

Date: 2026-07-20

## Goal

Replace repeated loader-error discovery on the physical V90S with a build-time
audit of the complete official PortMaster AArch64 candidate catalog.

## Build Entry

```sh
./scripts/docker-build.sh portmaster-audit
```

The normal command refreshes the official catalog and audits payloads already
present below `.cache/portmaster-audit/payloads`. It does not automatically
download the complete payload set. A release-grade audit requires current
`vendor-runtime`, `portmaster`, `system-rootfs`, and `app-layer` outputs; an
incomplete target contract is rejected unless the diagnostic-only
`--allow-incomplete-contract` option is explicitly supplied.

Full incremental retrieval requires explicit confirmation:

```sh
./scripts/docker-build.sh portmaster-audit \
  --download-payloads \
  --allow-large-download
```

Individual ports can be audited without retrieving unrelated packages:

```sh
./scripts/docker-build.sh portmaster-audit \
  --port a7xpg \
  --port abombniball \
  --port profadeluxe \
  --download-payloads
```

## Catalog Result

The official 2026-07-20 catalog reported:

- total ports: 1332
- explicit AArch64 or legacy undeclared-architecture candidates: 1126
- complete candidate payload size: 24.02 GiB

Running the unrestricted download command without
`--allow-large-download` stopped before downloading and reported the expected
space guard.

## Static Inspection Contract

The Python auditor reads ELF dynamic metadata directly from ZIP members. It
does not execute games and does not leave extracted package trees behind. It
records:

- ELF architecture and interpreter
- `DT_NEEDED`, `DT_SONAME`, `DT_RPATH`, and `DT_RUNPATH`
- libraries supplied by the port itself
- PortMaster runtime declarations and requirements
- launch-script runtime families and ARMHF requests
- external game-data requirements
- unresolved SONAMEs after applying only the V90S target library contract

The target contract was assembled from the built app-layer library directory,
PortMaster adapter libraries, official built-in PortMaster runtimes, the vendor
PowerVR directory, and the system rootfs SquashFS. The sampled build exposed
695 target SONAMEs. Docker development libraries were not included.

## Known-Failure Proof

The three recent failing ports were downloaded from their catalog-pinned URLs,
validated by size and MD5, and audited:

| Port | AArch64 ELF files | Static result |
| --- | ---: | --- |
| A7Xpg | 12 | missing `libFLAC.so.8` |
| Abombniball | 17 | missing `libjpeg.so.8` |
| Abu Simbel Profanation Deluxe | 17 | missing `libFLAC.so.8` and `libjpeg.so.8` |

The Profanation Deluxe launch log had stopped at its first loader error and
showed only `libjpeg.so.8`. Static inspection found the additional FLAC ABI
before any compatibility package was changed.

Both SONAMEs were classified as `common-abi-candidate` because each is required
by two sampled ports. Classification is evidence for review, not permission to
copy a random port-local binary into the global runtime.

## Verification

```sh
python3 -m unittest discover -s tests -p 'test_*.py' -v
bash -n scripts/docker-build.sh
./scripts/docker-build.sh portmaster-audit \
  --offline \
  --port a7xpg \
  --port abombniball \
  --port profadeluxe
(cd output/portmaster-audit/v90s && sha256sum -c checksums.sha256)
```

The six unit tests passed. The Docker audit completed with three audited
payloads and two unresolved SONAME families. All generated report checksums
verified.

No live-device files or PortMaster user data were changed by this work.
