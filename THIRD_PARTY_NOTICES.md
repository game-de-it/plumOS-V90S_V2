# Third-Party Notices

This file records the principal third-party and vendor-derived components
distributed by plumOS V90S.

plumOS-authored code, documentation, scripts, configuration, and artwork are
licensed under the repository MIT License unless a file states otherwise.
That MIT License does not relicense StockOS files, firmware, emulators,
libretro cores, fonts, libraries, ROMs, BIOS files, or user content.

plumOS releases do not include ROMs or game BIOS files.

Japanese counterpart: [THIRD_PARTY_NOTICES.ja.md](THIRD_PARTY_NOTICES.ja.md)

## Release Boundary

The V90S hardware baseline is the POWKIDDY V90S StockOS/Batocera-derived
`v90s-stockos-r1` runtime. Its bootloader data, kernel, modules, PowerVR files,
and device-specific runtime files retain their original terms and are not
covered by the plumOS MIT License. The binary package includes a dedicated
vendor-runtime notice and the build records source inventories and hashes.

## Major Bundled Components

| Component | Upstream or origin | License material in the plumOS build |
| --- | --- | --- |
| Vendor runtime | POWKIDDY V90S StockOS/Batocera-derived runtime | `v90s-stockos-vendor-runtime-NOTICE.txt`, vendor manifest, and hashes. |
| RetroArch | <https://github.com/libretro/RetroArch> | The exact source tree's `COPYING` is staged as `retroarch/RetroArch-COPYING`. |
| libretro cores | Repositories and refs in `docker/plumos-v90s-toolchain/libretro-core-recipes.tsv` | Available upstream `LICENSE`, `COPYING`, copyright, or license-bearing README files are staged under `libretro-cores/`; the core manifest records repository, ref, and commit. |
| Standalone emulators | PPSSPP, ScummVM, EasyRPG Player, PCSX-ReARMed, Flycast, Mupen64Plus, NXEngine-evo, OpenBOR, and YabaSanshiro upstream projects | Available upstream license texts are staged under `standalone/`; exact sources and outputs are recorded in the standalone manifest. |
| PicoArch and SDL12 compatibility | <https://github.com/shauninman/picoarch> and SDL compatibility projects | License texts are staged under `picoarch/`. |
| PortMaster | <https://github.com/PortsMaster/PortMaster-GUI> | The official payload retains its `PortMaster/licenses/` directory. plumOS compatibility libraries have separate texts in the top-level license bundle. |
| BusyBox and GNU/Debian userland | BusyBox and Debian/source packages used by the userland build | Version, source, dependency, and checksum records are staged under `share/doc`; each package retains its upstream terms. |
| Network services | ADB, OpenSSH SFTP, Samba, dosfstools, and their runtime libraries | Component versions and sources are recorded in the network-services manifest; upstream terms remain applicable. |
| Pyxel and Python packages | <https://github.com/kitao/pyxel>, Python, and installed Python packages | Package-provided license metadata remains inside the packaged virtual environment. |
| Frontend fonts | Noto Sans JP and WenQuanYi Micro Hei | SIL OFL and Apache-2.0 texts are staged under `share/doc/plumos-frontend/`. |
| Audio and PortMaster compatibility libraries | ALSA plugin, FFmpeg compatibility, OpenAL Soft, libevdev, FLAC, libjpeg, Readline, SquashFS tools, and LZO | Individual copied license or copyright texts are staged in the license bundle. |

## Distribution Checklist

Before publishing a binary release:

- keep `LICENSE`, `NOTICE.md`, `THIRD_PARTY_NOTICES.md`, and
  `THIRD_PARTY_NOTICES.ja.md` in the repository and release package
- run `scripts/audit-v90s-license-bundle.sh` against the app-layer output
- keep component manifests and recipes synchronized with distributed binaries
- exclude ROMs, BIOS files, saves, credentials, and personal SSH keys
- publish the corresponding source, recipes, and patches for source-built
  components as required by their respective licenses
