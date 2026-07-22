# V90S PortMaster Cleanup and License Audit

Date: 2026-07-22

## Scope

- remove updater-owned PortMaster staging paths left by interrupted updates
- preserve the active payload and the single rollback payload
- collect license material from source-built emulator outputs
- make license and notice coverage a strict app-layer and release gate
- remove release TODO entries that require unavailable ROM or BIOS content

## PortMaster Update Cleanup

PortMaster adapter version 10 runs cleanup only after confirming that the
PortMaster runtime is stopped. It removes direct children of the PortMaster
application root matching `portmaster-download-*` or `upstream.next.*` before
the next download starts. It preserves `upstream`, `upstream.previous`, the
exact `upstream.next` path, state directories, and unrelated files. Symlinks
are unlinked without following their targets.

Host test:

```text
python3 -m unittest tests/test_portmaster_update_cleanup.py
Ran 1 test
OK
```

The test removed two stale directories and one stale symlink while preserving
the active, previous, non-temporary, and external target directories.

The complete host unit suite also passed all 14 PortMaster audit, PortMaster
cleanup, and transactional update tests.

The packaged result was rebuilt from PortMaster release
`2026.06.23-0015`, and `installed.json` records adapter version 10.

## License Collection

The following reproducible outputs were rebuilt or restaged:

```text
RetroArch COPYING:                    1
libretro recipe license files:      114
libretro core binaries:             118
standalone license files:            10
PortMaster upstream license files:   26
```

The 114 libretro recipe records cover 118 binaries because some recipes emit
multiple core variants. Every recipe has a non-empty upstream license,
copyright, or license-bearing README in the staged `licenses/libretro-cores`
directory. The standalone count includes the emulator sources plus the
PCSX-ReARMed SDL compatibility license.

The app layer also contains:

- the plumOS MIT License and repository NOTICE
- English and Japanese third-party notices
- a dedicated POWKIDDY StockOS/Batocera-derived vendor-runtime notice
- RetroArch's exact source-tree `COPYING`
- PicoArch, PortMaster, Pyxel, font, and compatibility-library license texts
- component manifests that retain source, ref, commit, and checksum evidence

## Verification

The strict app-layer build completed with:

```text
license-audit: PASS
libretro_core_license_files=114
standalone_license_files=10
portmaster_upstream_license_files=26
```

`checksums.sha256` verified every one of the assembled app-layer files. The
release build then produced `plumos-v90s-update-0.1.0-dev` with 5,775 files and
placed `LICENSE`, `NOTICE.md`, `THIRD_PARTY_NOTICES.md`, and
`THIRD_PARTY_NOTICES.ja.md` at the release root as well as retaining the full
license tree.

Commands used:

```text
./scripts/docker-build.sh cores --stage-existing
./scripts/docker-build.sh retroarch
./scripts/docker-build.sh standalone mupen64plus
./scripts/docker-build.sh portmaster
./scripts/docker-build.sh app-layer --strict
./scripts/docker-build.sh license-audit
./scripts/docker-build.sh release --no-zip
(cd output/app-layer/v90s && shasum -a 256 -c checksums.sha256)
```

ROMs, game BIOS files, saves, credentials, and private keys are outside this
license bundle and are not release content.
