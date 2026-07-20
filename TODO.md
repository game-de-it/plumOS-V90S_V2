# TODO

Last updated: 2026-07-20

This TODO follows `docs/plumos-v90s-distribution-policy.md`. Historical Step 1
and Step 2 bring-up details are preserved in git history and `docs/validation/`.
Do not use old Armbian-first or KNULLI-first notes as the current plan.

## Current Goal

Build plumOS V90S as a V90S-specific distribution:

- StockOS/Batocera-derived vendor runtime provides boot, kernel, PowerVR, audio,
  and low-level input support.
- plumOS owns userspace behavior, init, launchers, RetroArch, cores, standalone
  emulators, frontend, configuration, image assembly, and releases.
- The Linux base lives in a read-only system squashfs.
- The user-visible app/update/data layer lives on a FAT32 partition mounted at
  `/mnt/plumos`.
- Normal updates are applied from Windows or macOS by copying update files onto
  the SD card.
- Global volume uses 12 software-gain steps, with immediate tmpfs updates and
  delayed persistence so physical-key feedback does not wait for mixer probes
  or FAT32 writes.

## Working Rules

- Read `docs/plumos-v90s-distribution-policy.md` before design or
  implementation work.
- Keep work in small git commits with clear build, validation, or documentation
  boundaries.
- Keep `artifacts/`, `.cache/`, `output/`, and `dist/` out of git.
- Treat `artifacts/` as input-only. It may contain private ROMs, extracted
  vendor files, credentials, or other local-only material.
- User performs real-device validation. Record each result under
  `docs/validation/`.
- Do not add hidden runtime fallback paths. Keep validation routes explicit.
- Stop live device processes only through PID-file based tools that validate
  `/proc/<pid>/comm` or `/proc/<pid>/cmdline`.
- Do not use broad process-name kills that can affect SSH or unrelated sessions.
- Release builds must not contain private ROMs, Wi-Fi credentials, SSH keys, or
  root passwords.

## Completed Baseline

- [x] Step 1 boot console achieved: framebuffer console text visible, USB
  keyboard input works, and commands such as `df` execute.
- [x] Step 2 RetroArch baseline achieved on real V90S hardware.
- [x] Known-good runtime documented in
  `docs/validation/2026-07-10-step2-stockos-video-perfect-runtime.md`.
- [x] Known-good RetroArch path: `video_driver=gl`,
  `video_context_driver=mali_fbdev`, `video_refresh_rate=58.917103`,
  `video_threaded=true`, `vrr_runloop_enable=true`, ALSA `plumos_output`
  (internal physical PCM `hw:0,0`), QuickNES.
- [x] User confirmed FPS, scrolling, controls, audio output, and audio pitch are
  good on the live device.
- [x] StockOS/Batocera runtime extracted into ignored artifacts.
- [x] Initial Docker build entry point exists at `scripts/docker-build.sh`.
- [x] Initial StockOS/Batocera-layout image assembler exists.
- [x] Distribution policy documented.
- [x] Vendor runtime identity documented as `v90s-stockos-r1`.
- [x] System squashfs plus FAT32 app layer policy documented.
- [x] Build system completion plan documented.

## Milestone 1: Vendor Runtime Formalization

- [x] Move the default vendor input path to
  `artifacts/vendor/v90s-stockos-r1/`.
- [x] Move the default prepared vendor output path to
  `output/vendor/v90s-stockos-r1/`.
- [x] Keep `output/vendor/stockos-runtime` only as a compatibility alias during
  migration.
- [x] Generate `output/vendor/v90s-stockos-r1/vendor-runtime.manifest`.
- [x] Ensure the vendor manifest includes:
  - `id=v90s-stockos-r1`
  - source image or extraction source
  - capture date
  - kernel version
  - boot model
  - GPU/display route
  - hashes
  - known-good validation document
- [x] Generate `output/vendor/v90s-stockos-r1/SHA256SUMS`.
- [x] Make `./scripts/docker-build.sh vendor-runtime` run consistently through
  the Docker entry point.
- [x] Require explicit opt-in before using KNULLI `boot0` / `boot_package`
  fallback assets in StockOS-layout image assembly.
- [x] Rename or isolate remaining KNULLI-specific runtime script/profile names
  that now describe the stable StockOS-derived runtime.

## Milestone 2: Build System Targets

- [x] Make `scripts/docker-build.sh` expose the official target set:
  - `image`
  - `shell`
  - `vendor-runtime`
  - `userland`
  - `network-services`
  - `sdl2-powervr`
  - `retroarch`
  - `cores`
  - `quicknes`
  - `picoarch`
  - `standalone`
  - `portmaster`
  - `pyxel-runtime`
  - `frontend`
  - `portmaster-audit`
  - `system-rootfs`
  - `app-layer`
  - `sd-image`
  - `release`
  - `all`
- [x] Keep `rootfs` as a transitional alias for `system-rootfs`.
- [x] Keep `stockos-image` as a transitional alias for `sd-image` while the
  partition contract remains StockOS/Batocera-compatible.
- [x] Keep `knulli-image` as a legacy investigation target only.
- [x] Implement `cores` as the normal libretro-core build target.
- [x] Make the normal `cores` target build the complete V90S catalog. Keep the
  MMF-compatible A/B subset available through `--filter plumos` in an isolated
  filtered-output directory.
- [x] Align V90S libretro recipe IDs, repos, refs, and classes with the MMF
  source-built recipe inventory:
  - `A`: 37 recipes
  - `B`: 4 recipes
  - `O`: 61 initial recipes
- [x] Validate that the V90S A/B output matches MMF's built
  `dist/plumos-libretro-cores` file set: 41 cores and 41 `.info` files.
- [x] Extend and triage the V90S full catalog against the MMF final package:
  - V90S recipes: `A`: 37, `B`: 4, `O`: 73, total 114
  - V90S output: 118 `*_libretro.so`
  - MMF final package output: 117 `*_libretro.so`
  - filename comparison: no MMF files missing; one V90S-only Flycast Xtreme
    output is additional
  - compatibility aliases:
    `dosbox_pure_0.9.7`, `beetle_saturn`,
    `km_puae_xtreme_amped`, and `uae4arm`
  - V90S Dreamcast extension: one additional `flycast_xtreme` recipe/output is
    kept outside the 117-core MMF parity baseline. The A133-oriented build uses
    the KNULLI-pinned metallic77 commit and stages it as
    `flycast_xtreme_libretro.so` without replacing standard Flycast.
- [x] Validate that `PLUMOS_CORE_FILTER=all FAIL_ON_CORE_ERROR=1
  ./scripts/docker-build.sh cores` completes with zero failed recipes.
- [x] Prevent filtered one-core builds from deleting the canonical full core
  set: filtered builds now use `output/libretro-cores/v90s-filtered/FILTER`,
  explicit filtered replacement of the canonical output is rejected, and a
  strict app-layer requires at least 118 staged cores.
- [x] Recover release-image FE game launch after the partial core package:
  restore and deploy all 118 cores, route RetroArch to the app-layer binary,
  prepare FAT32 SONAME aliases under `/run`, and confirm QuickNES video, audio,
  and input through the real FE launch path on V90S.
- [ ] Real-device runtime validation for non-baseline libretro cores.
  - [x] Inventory the refreshed live FE library and run the 2026-07-13 launch
    matrix for all 57 systems with indexed ROMs; see
    `docs/validation/2026-07-13-v90s-fe-rom-launch-matrix.md`.
  - [x] Confirm the live QuickNES core starts NES content through the FE.
  - [x] Confirm the separately deployed `nxengine_libretro.so` can draw Cave
    Story by direct diagnostic launch.
  - [x] Deploy and hash-check the complete 118-core app-layer output on the
  live V90S under `/mnt/plumos/cores`.
  - [x] Re-run FE launch validation after full deployment. All 48 systems
    previously blocked by missing live libretro cores now pass FE preflight;
    the only remaining preflight failure is non-libretro Pyxel.
  - [x] Enable Cave Story in the FE and package NxEngine under the normal
    `/mnt/plumos/cores` contract instead of the ROM directory.
  - [x] Replace the Japanese-incompatible NxEngine libretro default with the
    pinned NXEngine-evo standalone build, Japanese assets, V90S controls, and
    working Organya BGM; retain the libretro profile as a manual compatibility
    choice for translated content only.
  - [x] Run every currently reachable core through the FE on real hardware:
    83 of 86 unique cores remain active; three blockers and all 31 cores lacking
    compatible indexed content are recorded in
    `docs/validation/2026-07-14-v90s-fe-all-core-runtime.md`.
  - [x] Pin YabaSanshiro to performance-oriented 2.10.4 commit `8406a5c`,
    backport its ARM64 register-clobber fix, build this legacy AArch64 release
    with Clang, and validate sustained PowerVR video, ALSA playback, and the
    complete VDP1 framebuffer readback on the real V90S; see
    `docs/validation/2026-07-14-v90s-yabasanshiro-2.10.4.md`.
  - [x] Replace the black-screen ParaLLEl-N64 build with KNULLI's pinned
    A133/H5 GLES2 commit, validate Super Mario 64 and AeroGauge video plus
    audio on hardware, and add an N64-only D-pad-to-left-analog remap. The
    controller is fully usable; AeroGauge performance remains a separate
    optimization task. See
    `docs/validation/2026-07-15-v90s-parallel-n64-knulli-a133.md`.
  - [x] Fix Mupen64Plus-Next startup on the PowerVR GE8300 by disabling the
    falsely advertised persistent buffer-storage path. Core-dump analysis found
    a null destination from `glMapBufferRange` in GLideN64; Super Mario 64 now
    reaches rendered gameplay with the AArch64 dynarec and exits cleanly. See
    `docs/validation/2026-07-15-v90s-mupen64plus-next-powervr.md`.
  - [x] Remove PicoArch from every N64 launch choice. N64 now exposes only the
    validated RetroArch and standalone profiles; the FE no longer synthesizes
    `picoarch:parallel_n64` or `picoarch:mupen64plus_next` companion profiles.
  - [x] Restrict Saturn FE choices to standalone YabaSanshiro and the validated
    YabaSanshiro libretro core; remove Beetle/Mednafen and suppress the unusable
    PicoArch Saturn companion profile.
  - [x] Fix PicoArch PUAe startup by correcting the direct libretro core-option
    definition pointer. Add the missing VFS/PERF host interfaces and validate
    every live FE PICO route: 94 of 97 routes run on hardware with no segfault;
    see `docs/validation/2026-07-15-v90s-picoarch-all-runtime.md`.
  - [x] Suppress only the crashing PicoArch ChaiLove companion route while
    retaining its RetroArch route; ChaiLove's embedded SDL runtime cannot open
    a second V90S video device below PicoArch.
  - [ ] Add the three Channel F BIOS files and rerun FreeChaF without its
    incomplete HLE fallback.
  - [ ] Supply FBA 2012-matched Neo Geo ROM/BIOS sets and validate both
    `fbalpha2012` routes. The current set lacks required CRC `5be10ffd`.
  - [ ] Add compatible test content/system definitions and validate the 31
    currently unreachable packaged cores.
- [x] Keep `quicknes` as a compatibility or one-core development alias.
- [x] Implement `userland` for BusyBox and command-line tools.
- [x] Implement `network-services` for Wi-Fi/FTP/SFTP/Samba/ADB app-layer payloads.
- [x] Add `portmaster-audit` as the reproducible PortMaster AArch64 static
  compatibility gate. It audits all explicit and legacy-undeclared AArch64
  candidates from the official catalog, incrementally scans cached/downloaded
  ZIP payloads without persistent extraction, resolves ELF dependencies only
  against the built V90S runtime contract, and emits manifests, TSV reports,
  and SHA-256 checksums. Full payload retrieval is an explicit large-download
  operation because the current candidate set exceeds 24 GiB.
- [x] Promote the first audit-backed common ABI set into PortMaster adapter
  version 8: source-build pinned `libFLAC.so.8` and `libjpeg.so.8`, package
  their licenses and source hashes, create runtime links below `/run`, and
  reduce the A7Xpg, Abombniball, and Profanation Deluxe sample audit to zero
  unresolved SONAMEs. Device-side `ldd` also reports zero unresolved libraries;
  video, audio, controls, and clean exit remain per-port runtime tests.
- [x] Complete the 24.02 GiB full PortMaster AArch64 payload audit: download,
  size/MD5/ZIP-validate, and inspect all 1126 candidates. After separating 358
  Android/Bionic payloads and adding the actual SDL2_ttf runtime source to the
  target contract, the final report contains zero protected target-contract
  failures and 22 unresolved SONAMEs across 23 ports. See
  `docs/validation/2026-07-20-v90s-portmaster-aarch64-full-audit.md`.
- [ ] Triage and implement only approved PortMaster follow-up classes from the
  full audit: evaluate `libreadline.so.7` as the next common ABI; keep OpenSSL
  1.1 isolated; validate declared Weston/Java/Mono/Godot runtimes separately;
  reject Rockchip RGA/Mali dependencies instead of adding them globally; and
  leave single-port ABI dependencies with their owning port or runtime.
- [x] Implement `picoarch` as a native AArch64 runtime with SDL12 compatibility,
  V90S fbdev double-buffer presentation, FAT32-owned settings/saves, and shared
  `/mnt/plumos/cores/*_libretro.so` core resolution. QuickNES video and ALSA
  audio are validated on real hardware. The V90S evdev controller mapping and
  Aspect screen-size default are deployed. Flycast and Flycast Xtreme are
  explicitly excluded from PicoArch profiles after both failed content loading
  on the real device; their RetroArch profiles remain available.
  - [x] Explicitly attach Player 1 as `RETRO_DEVICE_JOYPAD` for every PicoArch
    core, with TyrQuake's required post-load ordering. Real-device gameplay
    controls are confirmed in PicoDrive/32X and Opera/3DO; the same test
    sequence did not regress RetroArch YabaSanshiro controls. See
    `docs/validation/2026-07-15-v90s-picoarch-game-input.md`.
  - [x] Add `scripts/v90s-fe-pico-smoke-test.sh` to derive all live FE PICO
    choices, verify loaded cores and framebuffer updates, stop by owned PID,
    and restore exactly one frontend process.
- [x] Implement `standalone` for the MMF final-package emulator set plus
  V90S PPSSPP, Dreamcast, and N64:
  - PPSSPP 1.20.4
  - ScummVM 2026.2.0
  - EasyRPG Player 0.8.1.1
  - OpenBOR v6391
  - DOSBox Staging 0.82.2
  - PCSX-ReARMed r26l
  - Flycast 2.6
  - Mupen64Plus 2.6.0
  - YabaSanshiro 2.10.4 (`8406a5c`)
- [x] Build all eight standalone executables as native aarch64 binaries with
  zero failed recipes.
- [x] Support incremental one-emulator builds such as
  `scripts/docker-build.sh standalone flycast` without deleting the other
  standalone outputs.
- [x] Package the recursive non-vendor runtime dependency closure under the
  FAT32 app layer while preserving the vendor PowerVR EGL/GLES boundary.
- [x] Integrate standalone executables, data, licenses, launcher, libraries,
  manifest, and checksums into `output/app-layer/v90s`.
- [ ] Validate each standalone emulator on real V90S hardware, including
  display, audio, controller mapping, save paths, and clean return to the FE.
  - [x] PPSSPP starts Ridge Racers through the FE standalone profile, displays
    on the physical LCD after the V90S opaque-alpha fix, and owns the running
    ALSA PCM stream.
  - [x] Validate PPSSPP physical controls through car selection and an active
    Ridge Racers race.
  - [x] Characterize PPSSPP performance: Ridge Racers is 60/60 in light scenes
    but about 38/60 in its heavy grandstand scene due to a saturated Cortex-A53
    main/render thread, not GPU saturation or thermal throttling.
  - [x] Track the hardware-validated PPSSPP `ppsspp.ini` and `controls.ini` as
    the standalone factory snapshot. The PPSSPP build requires and hashes both
    files, the launcher installs them only for a new profile, and Standalone
    Factory Reset backs up user settings before restoring the snapshot.
  - [x] Start Flycast 2.6 with Crazy Taxi through the FE standalone profile;
    verify PowerVR GLES, `adc_gamepad`, nonblank framebuffer output, ALSA PCM,
    and clean PID-targeted TERM shutdown.
  - [x] Diagnose standalone Flycast 2.6 on the StockOS vendor driver. Forcing
    its SDL path to GLES2 makes game frames visible, but performance remains
    about 46 FPS with audio stutter and missing textures. Keep the binary for
    direct diagnostics, but do not expose it as an FE launch profile.
  - [x] Build and live-test the KNULLI-pinned Flycast Xtreme libretro core on
    V90S. Fix ref checkout so the output manifest and binary really use commit
    `603814c9`; Crazy Taxi renders with normal video and audio at about 34 FPS
    in a heavy gameplay scene. Use Flycast Xtreme, Performance, the global
    all-four-CPUs-online policy, and 640x480 as the V90S Dreamcast default.
  - [x] Start Mupen64Plus 2.6.0 with Super Mario 64 through the FE standalone
    profile; verify PowerVR GLES, nonblank framebuffer output, ALSA PCM, and
    the V90S `adc_gamepad` auto-configuration. The console UI has no native
    in-game menu, so a PID/executable-validated Function hotkey now performs a
    clean Mupen shutdown and returns to the FE; this is validated with Mario
    Story on hardware.
  - [ ] Complete standalone YabaSanshiro physical validation. PowerVR GLES,
    changing game frames, continuous ALSA playback, gameplay controls,
    Function menu controls, clean process teardown, and FE return are proven;
    only a representative gameplay performance measurement remains. See
    `docs/validation/2026-07-14-v90s-yabasanshiro-standalone.md`.
  - [x] Prevent duplicate standalone emulator processes with a PID/executable
    ownership lock and a targeted TERM-to-KILL stop helper.
  - [x] Map the V90S `adc_gamepad` into the standalone YabaSanshiro menu and
    supervise standalone child processes so normal or abnormal exits remove
    their exact PID/executable ownership records.
  - [x] Extend YabaSanshiro's GPU VDP1 framebuffer read path from the truncated
    `0x30000` range to the full `0x40000` hardware range. Virtual Hydlide MAP
    and game-menu backgrounds now render through the last scan line without a
    lower black band in both RetroArch and standalone routes.
  - [x] Verify that RetroArch YabaSanshiro performs a normal core unload,
    exits with status 0, removes its PID files, releases ALSA, and returns to
    the existing FE process. The stale process observed before this test was
    the standalone executable, not RetroArch.
  - [x] Fix ScummVM libretro audio on the physical V90S. The core now submits
    continuous frame-sized audio and preserves the fractional 58.917 Hz clock;
    the frontend also applies the saved `alsathread`/latency override. The
    decisive runtime fix is ScummVM's `performance` governor default: with
    `interactive`, the bursty libretro workload stayed at 600-816 MHz and only
    reached 42-47 fps; with `performance`, Beneath a Steel Sky holds 58.91 fps
    with normal 48 kHz audio. See
    `docs/validation/2026-07-14-v90s-scummvm-libretro-audio.md`.
  - [x] Rebuild EasyRPG libretro with its practical compatibility feature set:
    mpg123 MP3, libsndfile/dr_wav, Vorbis, Opus, XMP, FmMidi, ICU/XML,
    FreeType/HarfBuzz, and SpeexDSP resampling. The physical V90S now plays the
    `TurnedIntoAGirl` MP3 BGM normally; see
    `docs/validation/2026-07-15-v90s-easyrpg-libretro-codecs.md`.
  - [x] Run EasyRPG through the PicoArch/PICO route. PicoArch now accepts
    directory content, supplies the libretro frame-time callback, and drives
    asynchronous core audio independently from the 58.955 Hz LCD loop. The
    physical V90S displays the game and plays BGM without periodic popping; see
    `docs/validation/2026-07-15-v90s-picoarch-easyrpg.md`.
  - [x] Validate PPSSPP config persistence: app-layer deployment preserves the
    live `ppsspp.ini` and `controls.ini`, and normal launch does not overwrite
    later user changes.
  - [ ] Validate PPSSPP save persistence and clean FE return.
  - [ ] Fix the standalone ScummVM directory launch before validation. The
    current generic launcher passes the content directory as a game ID;
    `--auto-detect --path=CONTENT_DIR` launches the same game with normal audio.
  - [ ] Validate ScummVM, EasyRPG Player, OpenBOR, DOSBox Staging, and
    PCSX-ReARMed on the physical V90S.
    - [ ] Fix PCSX-ReARMed SDL startup; the FE route currently exits with no
      console terminal and no available video device.
    - [ ] Make ScummVM resolve a ROM directory to a valid detected game target.
    - [x] Make standalone EasyRPG pass the selected game directory through
      `--project-path` instead of opening its empty player browser. The direct
      corrected launch loads `CookieCutterTurnedIntoGirl`, and the generated
      launcher is deployed; see
      `docs/validation/2026-07-15-v90s-easyrpg-standalone-launch.md`.
    - [ ] Validate standalone EasyRPG controls, audio, exit, and FE return
      through the normal frontend route.
    - [ ] Stage or select the chosen OpenBOR PAK in the runtime `Paks` contract.
  - [ ] Replace or remove the stale `PORTS/tmp/1.sh` entry that writes to the
    unavailable `/dev/cpuset/foreground/tasks` path.
- [x] Implement `frontend`.
- [x] Implement `app-layer`.
- [x] Implement `release`.
- [ ] Implement `all` as the normal release build chain.
- [ ] Emit manifest and sha256 metadata for every reusable build output.
  - [x] `frontend` emits `output/frontend/v90s/frontend.manifest` and
    `output/frontend/v90s/checksums.sha256`.
  - [x] `userland` emits `output/userland/v90s/userland.manifest` and
    `output/userland/v90s/checksums.sha256`.
  - [x] `network-services` emits
    `output/network-services/v90s/network-services.manifest` and
    `output/network-services/v90s/checksums.sha256`.
  - [x] `cores` emits `output/libretro-cores/v90s/libretro-cores.manifest`
    and `output/libretro-cores/v90s/checksums.sha256`.
  - [x] `standalone` emits
    `output/standalone-emulators/v90s/standalone-emulators.manifest` and
    `output/standalone-emulators/v90s/checksums.sha256`.

## Milestone 3: System Rootfs

- [x] Introduce a release-oriented `system-rootfs` builder whose default is the
  `release-system` profile and whose output is
  `output/system-rootfs/v90s/plumos-v90s-system-rootfs.squashfs`.
- [x] Keep Step 1/Step 2 rootfs profiles as explicit development or diagnostic
  profiles only.
- [x] Keep release `system-rootfs` focused on:
  - init
  - mount policy
  - `/tmp`, `/run`, `/dev`, `/proc`, `/sys`, `/boot`, `/mnt/plumos`
  - vendor runtime startup glue
  - PowerVR startup
  - audio startup
  - input startup
  - app-layer Wi-Fi and SSH service launch hooks without embedded credentials
  - safe process stop/restart helpers
  - minimal diagnostics and recovery console
  - app-layer launch wrappers
  - default configuration templates
  - base license and notice files
- [x] Remove normal RetroArch binaries from release squashfs.
- [x] Remove normal libretro cores from release squashfs.
- [x] Remove frontend, PicoArch, and standalone emulators from release squashfs.
- [x] Remove private ROMs from release squashfs.
- [x] Ensure development-only Wi-Fi credentials and SSH credentials are never
  present in release squashfs.
- [x] Make the rootfs bootstrap validate and execute applications from
  `/mnt/plumos`.
- [x] Make boot diagnostics report missing, damaged, or vendor-incompatible
  app-layer metadata clearly without an application fallback.
- [x] Move transient PID, lock, in-progress scraper state, runtime volume state,
  and disposable emulator cache files to `/run/plumos` tmpfs while keeping
  persistent settings and saves on p7.
- [x] Disable the old fb0 black-screen/white-band boot probe by default; keep it
  available only through explicit diagnostic opt-in.
- [x] Start the frontend before slow development services by backgrounding
  PowerVR probe, rootfs Wi-Fi/SSH init, and app-layer network services.
- [x] Retry app-layer network services after rootfs Wi-Fi/DHCP completion so
  Samba is not lost when the first non-blocking service pass runs before
  interfaces are ready.
- [x] Keep SD2 FAT fsck enabled by default, but guard it with a short timeout
  so a bad SD2 cannot block FE startup indefinitely.
- [x] Reduce normal boot log sync pressure; keep forced boot-log sync behind an
  explicit diagnostic opt-in.
- [ ] Migrate the remaining rootfs-level `v90s-network-ssh-init` Wi-Fi/SSH
  bring-up into the plumOS app-layer network control path before disabling the
  old development hook.
- [x] Add a development init hook that probes p7/p6 for `/mnt/plumos`
  app-layer metadata and starts `/mnt/plumos/bin/plumos-frontend-launch` when
  present.
- [x] Capture the ignored `v90s-stockos-r1` vendor input from the known-good
  live SD over ADB and assemble the first release-system SD image; see
  `docs/validation/2026-07-15-release-squashfs-boundary.md`.
- [ ] Validate the release-system image boot, FE startup, services, emulator
  launch/stop, and safe reboot/poweroff on hardware.
- [x] Diagnose the first release image's logo-only boot as a missing `/overlay`
  destination in p5, add it to `release-system`, and reject incompatible
  `--no-rootfs-repack` inputs during image assembly.
- [x] Diagnose the second release image through p7 logs as a frontend-only
  `libpng16.so.16` loader failure, package a dedicated frontend dependency
  closure, and validate it against the extracted release-system rootfs.

## Milestone 4: FAT32 App Layer

- [x] Define the app-layer tree under `output/app-layer/v90s/`.
- [x] Define the on-device mount path as `/mnt/plumos`.
- [x] Include app-layer metadata:
  - `VERSION`
  - `manifest.json`
  - `checksums.sha256`
  - `COMPAT_VENDOR`
- [x] Set `COMPAT_VENDOR` to `v90s-stockos-r1`.
- [x] Add directories for:
  - `bin/`
  - `gnu/`
  - `lib/`
  - `cores/`
  - `info/`
  - `frontend/`
  - `picoarch/`
  - `standalone/`
  - `ssh/`
  - `samba/`
  - `config/`
  - `fonts/`
  - `share/`
  - `state/`
  - `themes/`
  - `Images/`
  - `media/`
  - `music/`
  - `roms/`
  - `bios/`
  - `Saves/`
  - `States/`
  - `Screenshots/`
  - `Logs/`
  - `updates/`
  - `licenses/`
- [x] Copy RetroArch into the app layer.
- [x] Copy supported libretro cores and libretro `.info` metadata into the app
  layer.
- [x] Copy frontend into the app layer.
- [x] Port the MMF-style FE Apps menu path to V90S with live-device validated
  `Scraping`, `File Manager`, and `RetroArch` entries.
- [x] Keep visible `File Manager` and `Music Player` Apps entries as MMF-style
  foreground apps rather than result-log tools.
- [x] Port the A30 NextCommander file-manager build target to V90S and validate
  a real-hardware smoke launch through the same launcher the FE calls.
- [x] Port the MMF/A30 `plumos_music_player.c` build target to V90S and
  validate a real-hardware smoke launch with input and ALSA initialization.
- [x] Add the V90S-adapted MMF thumbnail scraper as
  `/mnt/plumos/bin/plumos-thumbnail-scraper`, using `/mnt/plumos/roms` and
  A30/MMF-compatible `/mnt/plumos/Images/<system>`.
- [x] Replace the temporary V90S-safe Music Player Apps entry with the ported
  MMF/A30 Music Player payload.
- [x] Copy BusyBox and command-line userland into the app layer.
- [x] Copy Wi-Fi/SSH/FTP/SFTP/Samba/ADB network service payloads into the app layer.
- [x] Add the MMF-compatible default `config/system/settings.json` so frontend
  system settings such as `wifi_enabled` can persist on V90S.
- [x] Make START menu `System Settings` use validated V90S runtime backends:
  volume uses the StockOS ALSA speaker path, display enhance controls back
  Lumination/Contrast/Color Temp/Saturation, unsupported Brightness shows
  `N/A` and does not save misleading values, and Factory Reset exposes only
  installed default sets.
- [x] Fix `System Settings -> INFORMATION` for the V90S distribution split:
  show `POWKIDDY V90S`, plumOS `VERSION`, compatible vendor runtime,
  kernel, PowerVR GPU, display/audio runtime backends, ROM-storage capacity,
  memory, and base OS metadata without stale Miyoo/MMF firmware wording.
- [x] Live-validate `UI Settings` controls: refresh TOP, UI mode,
  empty/favorites/recent TOP entries, ROM cursor wrap, boot resume mode,
  system/ROM sorting, scan-on-enter, and Graphic theme options.
- [x] Revalidate `boot_resume_mode=recent` through a full hardware reboot after
  repairing the app-layer metadata from a prior binary-only FE deployment.
  Bootstrap now validates the deployed FE and manifest, starts one frontend,
  and reports `screen=4` (`SCREEN_RECENT`); see
  `docs/validation/2026-07-19-v90s-recent-boot-checksum-recovery.md`.
- [x] Align the V90S TOP status contract with MMF: keep the 3x2 system grid,
  logos, header indicators, selection frame, and left accent, but never draw
  transient/debug `status:` text along the bottom of TOP.
- [x] Port the MMF/A30 Graphic TOP page transition to the V90S fbdev renderer:
  draw the previous and current pages with themed vertical/horizontal slide
  offsets, refresh at 16 ms while active, and present through the existing
  VSync double-buffer path. The physical V90S visibly confirmed smooth page
  scrolling on its 640x480p-60 framebuffer; see
  `docs/validation/2026-07-19-v90s-graphic-top-60fps-slide.md`.
- [x] Drive the V90S TOP battery label from the StockOS AXP2202 power-supply
  sysfs instead of the missing generic `battery` path. Validate `CHG 100`
  against the live `Full` / `100` state and refresh TOP status every 5 seconds.
- [x] Align the SELECT/Core Settings menu with the MMF-style settings layout
  and validate the V90S framebuffer render on the live device.
- [x] Expose `Network Settings` from the V90S START menu so Wi-Fi and network
  services are reachable from the frontend.
- [x] Live-validate the FE `Network Settings -> Wi-Fi` checkbox for runtime
  OFF/ON control: OFF stops `wpa_supplicant` and removes the IP, ON reconnects
  `wlan0`, restores the IP, and persists `wifi_enabled`.
- [x] Make Wi-Fi ON initialize the USB radio before checking saved credentials.
  With no WPA config, load the matching vendor module, bring `wlan0` up, keep
  the checkbox enabled, and direct the user to `Connect Wi-Fi` instead of
  leaving the dongle uninitialized behind `missing_config`.
- [x] Preserve uppercase/lowercase SSID and password text in the V90S Wi-Fi
  editor, highlight the selected on-screen keyboard character, and validate
  mixed-case `qQ` input from a real-device framebuffer capture.
- [x] Make `Network Settings` and `NW Service` open from saved config state
  instead of synchronously spawning every network-service status command; keep
  full runtime checks on the `INFORMATION` screen.
- [x] Live-validate FTP, SFTP, and Samba startup plus read/write access from a
  Mac client.
- [x] Revalidate every enabled network service on the release-system runtime.
  FTP and Samba passed Mac upload/readback/delete tests; release p5 now contains
  OpenSSH server; `/run/sshd` permissions no longer depend on the FE umask; and
  SFTP passed the same roundtrip test. SSH, FTP, SFTP, Samba, and ADB all
  reported `running` with their persisted switches enabled.
- [x] Make `network-services` self-contained for FTP by bundling BusyBox,
  `tcpsvd`, and `ftpd`; recover the live V90S from a partial app-layer copy.
- [x] Recover USB Wi-Fi from `wpa_state=COMPLETED` with no IPv4 by renewing DHCP
  and restarting enabled services after address acquisition.
- [x] Restore Wi-Fi scanning and connection in the release-system image: keep
  `wpa_supplicant`, `wpa_cli`, `iw`, and regulatory data in p5; poll Realtek
  scan results for up to eight seconds; and apply BusyBox `udhcpc` leases with
  the app-owned DHCP hook in p7. Live validation found `example-wifi-2`, acquired
  `192.0.2.120`, installed the default route and DNS, and reached the
  gateway.
- [x] Keep DNS writable with the read-only system SquashFS. Bind
  `/run/plumos/network/resolv.conf` over `/etc/resolv.conf` before rootfs
  Wi-Fi/DHCP, replace Docker's unreachable `192.168.65.7` resolver, and
  prepare DNS before the bounded Wi-Fi time sync. Real-device validation
  restored a 560-item PortMaster catalog, 1,386 images, network time, and the
  UTC RTC writeback.
- [x] Own the V90S boot logo in `package/boot-assets-v90s`, convert the
  640x480 source PNG to the bootloader's 24-bit Windows BMP contract, and
  verify that `sd-image` places the exact asset at `PLUMBOOT:/bootlogo.bmp`.
- [x] Route SFTP through the app-layer subsystem, validate SFTP OFF/ON without
  stopping SSH, and restrict SSH process adoption to the real listener.
- [x] Add USB Disk Mode as a file-transfer fallback for unstable USB Wi-Fi
  dongles. It exposes a dedicated transfer image, not `/mnt/plumos` itself.
- [x] Keep the FE responsive while USB Disk Mode waits for host eject and cable
  disconnect. Run the transfer helper asynchronously, poll its completion
  result, and restore the NW Service screen when it finishes.
- [x] Coordinate USB Disk Mode with ADB on the shared V90S USB controller:
  pause only the validated plumOS ADB gadget before mass-storage binding and
  restore ADB automatically when USB Disk Mode exits.
- [x] Add a USB command mailbox to USB Disk Mode so diagnostics can be queued
  as `commands/run.sh` plus `commands/ALLOW_EXECUTE` and results are written
  back to `RESULT-LATEST.txt` and `results/` after V90S remounts the transfer
  image.
- [ ] Physically validate USB Disk Mode from macOS with a data-capable USB
  cable and confirm the `PLUMUSB` drive appears, can be ejected, and remounts
  on V90S at `/mnt/plumos/usb-transfer`.
- [ ] Physically validate the USB command mailbox from macOS by copying a
  diagnostic `commands/run.sh`, creating `commands/ALLOW_EXECUTE`, ejecting
  `PLUMUSB`, unplugging USB, and confirming the result files on the next USB
  Disk Mode session.
- [x] Add standard ADB over USB FunctionFS/configfs as the intended interactive
  USB command path.
- [x] Physically validate ADB from macOS: enable ADB from the frontend or
  `plumos-network-services`, confirm `adb devices`, run `adb shell id`, and
  confirm file transfer with normal `adb push`/`adb pull`.
- [x] Register ADB in the FE NW Service screen and validate the frontend-facing
  service controller can stop/start ADB while keeping
  `/mnt/plumos/config/network/services.conf` in sync.
- [x] Validate that NW Service checkboxes use the persistent `enabled=` state
  while service status reports exact live process state for SSH, FTP, SFTP,
  Samba, and ADB.
- [x] Fix and live-validate `Network Settings -> INFORMATION`: refresh the USB
  Wi-Fi runtime status when the screen opens, report `COMPLETED` with an IPv4
  address as `Connected`, and show compact live/boot state for every network
  service without blank or clipped values. Keep the release FE and network
  controller on the same `/run/plumos/network-control/wpa_status.txt` source;
  do not fall back silently to the former `/tmp/wpa_status.txt` path.
- [x] Validate the FE navigation/action path for
  `START -> Network Settings -> NW Service -> ADB` by running the controller UI
  script path that presses `A` on the ADB checkbox and confirming `adb devices`
  disappears on OFF and returns on ON.
- [x] Investigate the 2026-07-12 ADB disconnect seen after SSH was re-enabled:
  it was not an `adbd` idle timeout. V90S had `adb_enabled=1`, `adbd` alive,
  FunctionFS mounted, but `gadget_bound=0`, `udc_state=not attached`, and macOS
  no longer enumerated `plumOS V90S ADB`; restarting only ADB over SSH rebound
  the gadget and restored `adb devices`.
- [ ] Physically confirm the FE ADB checkbox can be toggled with V90S controls
  during normal menu navigation.
- [x] Investigate and recover ADB host re-enumeration after repeated
  cable-attached stop/start cycles. macOS still enumerated `plumOS V90S ADB`
  while ADB 35.0.2 lost its transport after `usb read failed: status = 1`;
  restarting only the host server restored it. Standardize host access on
  `scripts/v90s-adb.sh`, which selects ADB 36.0.2 and recovered automatically
  through three deliberate gadget restart cycles. See
  `docs/validation/2026-07-15-adb-host-transport-recovery.md`.
- [x] Copy PicoArch/PICO payloads into the app layer. The final PicoArch and
  frontend hashes match their standalone build outputs, and all 3,798 app-layer
  checksum entries pass.
- [x] Copy standalone emulators into the app layer.
- [x] Live-capture the V90S physical key evdev mapping for D-pad, ABXY,
  shoulders, select/start/function, volume, and power; record the result in
  `docs/validation/2026-07-13-v90s-physical-keymap.md`.
- [x] Live-test StockOS-style V90S input combos: `Select+Start` emits
  `BTN_MODE` in addition to Select/Start, while the tested `Select+R2`
  sequence did not switch the D-pad away from `ABS_HAT0X/Y`.
- [x] Add and live-validate the boot-persistent V90S hardware-key service:
  physical Volume +/- changes the global 0..12 volume, while Select+Volume +/-
  changes the V90S display-enhance luminance. Keep the daemon independent of
  FE/emulator lifetime, rediscover evdev nodes by device name, debounce
  persistent setting writes, fix the validated internal codec DAC gain at
  `170,170`, and
  route user volume for both speaker and USB-DAC through the ALSA hotplug
  plugin's software gain. Keep the physical PCM path enabled at software volume
  zero so RetroArch `audio_sync` cannot stall the emulation runloop.
- [x] Make the physical Power key open one power menu across the FE and active
  display-owning runtimes without stopping SSH/ADB. Validate native FE handling,
  framebuffer restoration, single-instance ownership, and cancel/resume with
  RetroArch, standalone YabaSanshiro, and PPSSPP. Recover the shared physical
  ALSA stream after SIGSTOP/SIGCONT so both direct ALSA and SDL callback clients
  resume audio. See
  `docs/validation/2026-07-19-v90s-global-power-menu.md`.
- [x] Add Python 3.11, `python3-venv`, and `python3-pip` to the read-only
  release-system squashfs while keeping pip-installed modules on writable
  `PLUMOS_SYS`.
- [x] Add `Apps -> Pyxel Setup` to install
  `/mnt/plumos/roms/pyxel/requirements.txt`, or the packaged default when SD2
  does not provide it, into the FAT-safe copied venv at
  `/mnt/plumos/venvs/pyxel`. Preserve the previous venv on failure and show the
  complete result in the frontend.
- [x] Replace the inherited `pyxel:mmf` V90S default with the device-owned
  `pyxel:v90s` launcher contract.
- [x] Build the pinned AArch64 Pyxel 2.9.3 environment as a reproducible
  `pyxel-runtime` artifact, require it in strict app-layer builds, and include
  it in subsequent SD images instead of requiring a first-boot network install.
- [ ] Complete Pyxel real-device validation through the physical FE controls.
  - [x] Boot the Pyxel-enabled system image, install the writable venv, and run a
    `.pyxapp` long enough to prove PowerVR video and ALSA audio initialization.
  - [x] Confirm visible output and audible game audio on real hardware; fix the
    inherited GE8300 SDL2 1280x720 native-window override so Pyxel uses the
    V90S active 640x480 display mode without horizontal displacement or crop.
  - [x] Keep the official pip-installed Pyxel package user-updatable while an
    OS-owned SDL2/OpenGL fit layer constrains oversized 3:2 content and
    preserves centered 1:1 content on the 640x480 LCD. Confirm 720x480 and
    480x480 geometry on real hardware.
  - [x] Supply pygame's GLib host dependencies outside the user-controlled
    venv and confirm `LastEmulator` owns a live 44100 Hz, signed 16-bit,
    two-channel ALSA stream through pygame mixer.
  - [x] Restore exactly one frontend process after the bounded runtime test.
  - [ ] Confirm gamepad controls, game-owned exit, and a `.py` title whose
    project requirements are present.
- [x] Investigate PortMaster feasibility on V90S. The official GUI runs on the
  real device with the plumOS PowerVR SDL2 route, renders at 640x480, and opens
  `adc_gamepad`; see
  `docs/research/2026-07-16-v90s-portmaster-feasibility.md`.
- [ ] Integrate PortMaster as a pinned, reproducible app-layer component.
  - [x] Add a `portmaster` build/package target with manifest, SHA256, and
    upstream license notices.
  - [x] Add a `plumOS` platform/control adapter and an explicit POWKIDDY V90S
    A133P hardware definition. Do not retain the current TrimUI Smart Pro
    misidentification.
  - [x] Recreate SDL2 extension and other ELF SONAME aliases under `/run` for
    the FAT32 app layer.
  - [x] Add a PID-owned GUI/port lifecycle wrapper that uses the existing
    frontend stop/launch helpers and does not use broad `pkill`, `pidof`, or
    unrelated systemd service restarts.
  - [x] Add a one-second `Select+Start` emergency exit for hung PortMaster
    ports. Validate that it stops only the recorded process group, clears
    ownership state, restores one FE, and leaves ADB/SSH running.
  - [x] Route PortMaster and launched ports through the proven PowerVR SDL2,
    `adc_gamepad`, and `plumos_output` contracts.
  - [x] Package a source-pinned common AArch64 compatibility runtime for
    FFmpeg 4.4 ABI (`libavcodec.so.58` and its companion libraries) and
    `libevdev.so.2`. Recreate its SONAMEs under `/run` without replacing the
    PowerVR EGL/GLES or patched SDL2 route. On hardware, Moonlight Embedded
    2.7.0 resolves every direct dependency and reaches its LÖVE launcher.
  - [x] Add PortMaster and its confirmed staged updater to FE Apps. On hardware,
    validate the official stable metadata refresh, GUI rendering, controller
    discovery, and single-frontend restoration. A future newer upstream release
    still needs one real network switch test.
  - [ ] Remove stale `portmaster-download-*` and `upstream.next.*` directories
    left by interrupted updates before starting a new update. Preserve only
    the active `upstream` and the single `upstream.previous` rollback payload.
  - [x] Keep upstream catalog checks enabled while suppressing only payload
    self-update. Persist 1,386 downloaded catalog images under p7 and confirm
    thumbnail rendering survives a PortMaster restart without another download.
  - [x] Validate one lightweight AArch64 Ready-to-Run SDL2/GLES port before
    enabling wider catalog classes.
    Apotris rendered and used the normal internal audio route; its owned process
    group stopped cleanly and restored exactly one FE process. A7Xpg remains an
    explicit incompatible sample because that installed port omits
    `libFLAC.so.8`.
  - [x] Make the installed Balatro and Donut Dodo ports launch on V90S.
    Balatro now uses the packaged AArch64 OpenAL Soft ALSA library. Donut Dodo
    uses the shared persistent HarbourMaster runtime metadata and a
    SHA-256-keyed userspace extraction cache for zlib SquashFS runtimes, which
    the StockOS kernel cannot mount. Both titles rendered and owned the active
    ALSA PCM on hardware, then stopped without leaving processes or mounts.
    Balatro audio was subsequently validated through a direct ALSA `default`
    ioplug route: the physical PCM remained `RUNNING`, accepted continuing
    960-frame writes, and the user confirmed audible game audio.
    The same default route now accepts the common SDL/OpenAL signed, unsigned,
    integer, packed 24-bit, and float formats. This removed Kemono Rogue's
    title-specific `11025 Hz / U8 / mono` startup failure without a per-port
    override. Kemono Rogue's separately missing BGM was traced to the official
    port ZIP omitting `title.*` and `stage.*`; restoring the upstream ADP assets
    produced confirmed BGM without changing its audio route.
  - [x] Physically confirm PortMaster GUI navigation and game controls with the
    V90S buttons. On the ext4 runtime, repair official ZIP mode `0644` to
    `0755` for `gptokeyb`/`gptokeyb2`; Donut Dodo then ran with its owned
    GPTokeYB process and the user confirmed controls.
  - [x] Keep ARMHF-only ports unavailable. The V90S has no 32-bit PowerVR
    userspace driver; the Maldita Castilla ARMHF probe rendered and accepted
    input through Mesa llvmpipe but ran at roughly 10 fps. Reject installed
    scripts declaring `PORT_32BIT=Y` before stopping FE. Desktop OpenGL,
    Weston/GL4ES, Box64, Mono, Java, and other runtime classes remain gated
    until each class is explicitly packaged and validated on V90S.
- [ ] Confirm the V90S NextCommander button mapping on real hardware.
- [x] Confirm the V90S Music Player button mapping on real hardware after the
  `adc_gamepad` input-device fix.
- [ ] Confirm the V90S Music Player can play an actual music file with ALSA
  output on real hardware.
- [x] Copy plumOS-owned private libraries into the app layer.
- [x] Avoid symlink-dependent library layouts on FAT32.
- [x] Generate app-layer `manifest.json`.
- [x] Generate app-layer `checksums.sha256`.
- [x] Mark complete app-layer manifests explicitly and reject partial
  `missing_optional` app layers during release packaging.
- [x] Add boot/frontend startup checks for app-layer metadata in the
  development init path.
- [x] Validate frontend boot on real V90S hardware.
- [x] Live-validate the formal V90S fbdev frontend design after SSH reconnect,
  including a `/dev/fb0` capture and single-frontend-process check.
- [x] Align V90S settings-screen checkbox and option control placement with the
  MMF/A30-style frontend layout.
- [x] Keep V90S START/settings/Wi-Fi list cursors inside the visible fbdev
  screen by using a scroll window and 2x text for settings-family rows.
- [x] Formalize the V90S SD1 content roots as lowercase `roms/` and `bios/`,
  with FE ROM scanning rooted at `/mnt/plumos/roms`.
- [x] Define SD2 as an optional ROM/BIOS-only content layer that is mounted
  internally and bind-mounted onto `/mnt/plumos/roms` and `/mnt/plumos/bios`.
- [x] Add `plumos-sd2-content-mount start|status|stop|restart` for SD2 content
  mount control, including FAT fsck before FAT32/vfat mounts.
- [x] Expose FE reboot and shutdown actions through
  `/mnt/plumos/bin/plumos-safe-shutdown`, with SD2 content mounts stopped and
  filesystem sync performed before reboot or poweroff.
- [x] Render FE reboot and shutdown with the same centered progress-screen
  language as Refresh TOP: top status bar, left accent, large action/wait
  labels, smaller safe-save/SD-card warnings, and no interactive cursor.
- [x] Visually confirm the new reboot and shutdown progress screens on the
  physical V90S after the 2026-07-18 frontend deployment.
- [x] Shorten the four-partition reboot/poweroff path without weakening clean
  unmounts: poll process exits instead of fixed waits, consolidate syncs,
  skip redundant SysRq sync/remount after verified p3/p4 unmounts, and launch
  the rootfs helper without app-layer loader paths. Hardware reboot testing
  reduced ADB action-to-return from about 33-35 seconds to about 21 seconds
  while retaining the clean fast-boot path.
- [x] Add a final-action watchdog so a hung `reboot -f` or `poweroff -f` cannot
  block the already-synced FE Reboot/Shutdown path before reaching sysrq.
- [x] Change the normal FE Reboot/Shutdown path to direct sysrq after SD2 stop
  and sync, because BusyBox `reboot` / `poweroff` can return or hang on V90S.
- [x] Repair and revalidate the p7 FAT32 app layer after the kernel remounted
  `/mnt/plumos` read-only due to FAT corruption.
- [x] Improve FE Reboot/Shutdown so app-layer writers are stopped and p7
  `PLUMOS` is remounted read-only before final sysrq reboot/poweroff.
- [x] Replace the final p7 read-only remount with a stronger final-stage path
  that runs outside `/mnt/plumos`, unmounts p7 completely, and then triggers
  sysrq reboot/poweroff.
- [x] Add rootfs-side mount-before-fsck protection for p7 `PLUMOS` using
  `dosfstools`/`fsck.fat` so dirty FAT can be repaired before app-layer use.
- [x] Validate `plumos-v90s-appfat-1g-fatguard-20260711-1.img` on hardware
  and confirm FE Reboot no longer leaves p7 `PLUMOS` with the FAT dirty
  warning on the next boot.
- [x] Validate SD2 auto-mount from a clean reboot with SD2 inserted.
- [x] Make frequently replaced frontend JSON and ROM-library indexes durable
  with file `fsync`, atomic rename, and parent-directory `fsync`.
- [x] Harden live ADB app-layer deployment by verifying the host artifact,
  quiescing p7 writers while preserving SSH/ADB, transferring bounded chunks,
  syncing and verifying each chunk, and committing metadata last.
- [x] Make PortMaster payload switching, dependency extraction,
  installed-version metadata, and completed GUI game installations durable
  across large FAT32 updates.
- [x] Live-validate the hardened deployment with three two-file chunks, then
  stress p7 with 64 state replacements and five full library-index rebuilds
  without a FAT/MMC error or read-only remount.

## Milestone 5: SD Image Layout

- [x] Preserve the seven-partition StockOS layout behind the explicit
  `stockos-image` compatibility target while the four-partition candidate is
  validated.
- [x] Implement the candidate seed layout on
  `codex/four-partition-provisioning`:
  - raw vendor-compatible `boot0` and `boot_package` offsets
  - p1 `boot-resource` / `PLUMBOOT` FAT16, exactly 1024 MiB
  - p2 `boot` Android boot image, exactly 64 MiB
  - p3 `runtime` / `PLUMOS_SYS` ext4, exactly 1600 MiB in the seed
  - no p4 in the downloadable seed
- [x] Build a fixed-default boot package that loads GPT partition `boot`
  without the old external `env` / `env-redund` partitions.
- [x] Add a p2 provisioning initramfs that validates the known seed geometry,
  relocates backup GPT, expands p3 to exactly 8192 MiB, and creates p4 FAT32
  `PLUMOS` through the final usable SD sector.
- [x] Make provisioning resumable and idempotent. A 16 GB simulation retained
  the same p4 UUID across a second provisioning run.
- [x] Add preflight checks for the boot chain, system SquashFS, complete app
  manifest/checksums, bounded SD2 fsck/mount, and the single-FE `exec` chain.
- [x] Generate and structurally verify the compact candidate image
  `plumos-v90s-four-partition-20260718-6.img`.
- [x] Boot the four-partition candidate on a physical V90S and verify p3/p4
  geometry, labels, provisioning markers, mounts, and exactly one FE process.
  - [x] The first physical boot expanded p3 to 8192 MiB and created and seeded p4
    through the SD-card tail. FUSE-T inspection found handoff stopped because
    the initramfs BusyBox `sha256sum` does not implement `-c`.
  - [x] Rebuilt `plumos-v90s-four-partition-20260718-7.img` with
    BusyBox-compatible system hash verification and FAT32 boot-log mirroring.
  - [x] Diagnosed the second physical boot stall: the read-only system
    SquashFS omitted `/mnt/plumos-boot` and `/mnt/plumos-user`, so initramfs
    exited while attempting to create those mountpoints after mounting it.
  - [x] Rebuilt the system SquashFS with all handoff mountpoints and added an
    initramfs framebuffer progress/error screen.
  - [x] Generated `plumos-v90s-four-partition-20260718-8.img` with explicit
    framebuffer handoff diagnostics and a clean 1 MiB-aligned p4.
  - [x] Physical boot completed through system init and FE. ADB proved p3 at
    exactly 8192 MiB, aligned p4 through the SD tail, all expected mounts and
    markers, clean kernel storage logs, and one framebuffer FE process.
  - [x] Diagnose the apparent second-boot setup rerun. The old initramfs ran
    `resize2fs`, userdata seeding, setup progress frames, and overwrote
    `first-boot.log` on every boot despite a valid completion marker.
  - [x] Add a completed-provisioning normal path that preserves the original
    first-boot log, writes `last-boot.log`, and skips resize/seeding writes.
  - [x] Update the SquashFS power action for the four-partition mounts. It now
    stops all p3/p4 users, unmounts p4 aliases and persistent filesystems in
    child-first order, then issues SysRq sync and read-only remount before the
    final reboot or poweroff.
  - [x] Reproduce the old FE shutdown defect and validate the new sequence on
    hardware: the old path caused p3 journal recovery and a p4 dirty bit after
    menu shutdown; a patched reboot produced neither condition.
  - [x] Generate and verify
    `plumos-v90s-four-partition-20260718-9.img` with the normal-boot and safe
    power-action fixes.
  - [x] Diagnose the first `-9` live-update boot failure. Updating the active
    p1 FAT while its system SquashFS was loop-mounted corrupted both SHA-256
    directory entries; the SquashFS payloads themselves remained intact.
    Repair p1 offline, restore both hash files, and prohibit this live-update
    procedure.
  - [x] Confirm the repaired `-9` p2/SquashFS reaches FE through the normal
    boot path with valid A/B hashes, one FE, ADB, SSH, and SD2 mounts.
  - [x] Make initramfs recovery preserve its FAT-accessible log and then
    unmount p3/p4, or remount them read-only, before holding the failure screen.
  - [x] Generate and verify
    `plumos-v90s-four-partition-20260718-10.img`, then deploy and read back its
    recovery-safe p2 on the physical card.
  - [x] Add a clean-shutdown fast path. A verified system cache plus p3/p4
    clean-shutdown markers now skip ext4/FAT fsck, full SquashFS hashing, and
    all initramfs progress frames; the markers are consumed before system
    handoff so an abnormal next shutdown cannot reuse them.
  - [x] Validate the fast path on hardware with the updated p2 and power helper.
    The FE process started at about 3.0 seconds and PowerVR initialized at about
    3.7 seconds, compared with about 11.8 seconds for PowerVR on the checked
    normal path.
  - [x] Generate and verify
    `plumos-v90s-four-partition-20260718-11.img` with the persistent fast-boot
    power helper in the system SquashFS.
  - [x] Complete FE menu reboot and shutdown/cold-power-on cycles with the
    complete `-11` image. Both returned through the clean fast path without
    setup frames, journal recovery, a FAT dirty bit, or storage I/O errors.
  - [x] Generate and verify
    `plumos-v90s-four-partition-20260718-13.img` with the shortened power
    action and sanitized rootfs-helper loader environment.
  - [x] Confirm SquashFS handoff, FE startup, and one frontend process on
    hardware.
  - [x] Diagnose the 2026-07-19 regression where a normal FE reboot displayed
    the checked-boot progress screen. Initramfs evidence isolated the rejection
    to the missing p3 clean-shutdown marker; p4 readiness/clean state and the
    cached p1 system hash all remained valid, so the boot-logo replacement was
    not involved.
  - [x] Keep clean-shutdown markers through a transient p3/p4 unmount failure:
    refresh persistent-storage users and retry before invalidating either
    marker, and log every rejected fast-boot predicate in initramfs.
  - [x] Deploy the fixed p2 and system SquashFS, then confirm two consecutive
    hardware reboots through the installed FE power-action path report
    `fast boot: clean p3/p4 and cached system verification accepted` with p1
    mounted read-only and one frontend process.
  - [x] Generate and structurally verify
    `plumos-v90s-four-partition-20260719-2.img` with the fast-boot retry fix.
- [ ] Launch a ROM from SD2 through the FE and reconfirm LCD video, audio,
  controls, FPS/scrolling/audio pitch, clean exit, and persistence.
  - [x] Launch SD2 `nes/Baseball.nes` from the FE with QuickNES and confirm
    visible gameplay plus physical controls. ADB proved the intended wrapper,
    core, ROM, input, video, and ALSA ownership with no duplicate active FE.
  - [ ] Confirm audible audio quality/pitch, FPS and scrolling, then exit the
    game normally and verify FE return plus save/config persistence.
- [ ] Run the remaining power-interruption, A/B update, rollback, recovery,
  and Windows/macOS enumeration tests before promoting the candidate to the
  release default.
- [x] Use p7 `rootfs_data` / `PLUMOS` as the current development FAT32
  app/update/data partition.
- [ ] Validate the chosen p6/p7 FAT32 layout on real hardware.
- [x] Increase the development FAT32 app-layer capacity to 4096MB so the full
  generated app-layer can be included without exceeding the current payload
  size.
- [x] Keep an explicit development compatibility mode for the current p6/p7
  shape until the four-partition candidate is validated.
- [x] Stop treating ext4 `SHARE` as the current app-layer development design.
- [x] Include app-layer manifest hash in the SD image manifest.
- [x] Add `--app-layer-dir` support to the StockOS-compatible image assembler
  so current p7 development images can carry the app layer for frontend boot
  tests.
- [x] Include vendor-runtime manifest hash in the SD image manifest.
- [x] Include system-rootfs hash in the SD image manifest.

## Milestone 6: RetroArch Runtime Integration

- [ ] Move the normal RetroArch launch path to `/mnt/plumos`.
- [ ] Preserve the known-good V90S defaults:
  - `video_driver = "gl"`
  - `video_context_driver = "mali_fbdev"`
  - `video_refresh_rate = "58.917103"`
  - `video_threaded = "true"`
  - `vrr_runloop_enable = "true"`
  - `audio_driver = "alsa"`
  - `audio_device = "plumos_output"`
  - `audio_latency = "64"`
  - `input_driver = "sdl2"`
  - `input_joypad_driver = "sdl2"`
- [x] Ensure users can save RetroArch settings. The live 2026-07-19 V90S cfg
  keeps `config_save_on_exit=true` and is the tracked factory snapshot.
- [x] Ensure frontend/config tooling does not overwrite user settings on every
  launch. The launcher installs the factory cfg only when the persistent cfg is
  absent; normal builds, deploys, and launches preserve the user copy.
- [x] Migrate RetroArch's unset/default `/root/.config/retroarch` directory
  values to the V90S `/mnt/plumos` layout while preserving explicit user paths
  and keeping disposable cache under `/run/plumos`.
- [x] Remove the old bring-up diagnostic sweep and repeated global `sync` calls
  from normal RetroArch startup; retain them behind explicit diagnostic flags.
- [x] Make RetroArch config migrations one-time and pass per-system save/state
  paths through the volatile append-config instead of rewriting the main cfg.
- [x] Cache the 113-link app-runtime SONAME map per boot and generate it in one
  Python process instead of rebuilding it with 113 commands for every RA game.
- [x] Replace normal RetroArch `/proc`-wide fb-console discovery and verbose
  mixer dumps with targeted process validation and quiet mixer assignments.
- [ ] Provide a resettable defaults mechanism.
- [ ] Write RetroArch launch and runtime logs to the app layer.
- [x] Route normal app audio through the shared `plumos_output` ALSA PCM.
- [x] Downmix left and right channels for the built-in mono speaker.
- [x] Preserve stereo and automatically select a USB DAC, including insertion
  and removal while an application stream remains open.
- [x] Validate left/right stereo separation with a physical USB DAC. The
  CX31993 was detected as ALSA card 1 and the user heard the long left-channel
  tone and short right-channel tones separately through `usb_stereo`.
- [x] Build and package the process-local ALSA hotplug ioplug. Active RetroArch,
  PicoArch, and standalone YabaSanshiro streams now migrate between the
  built-in mono route and CX31993 stereo output without restarting the app.
- [x] Preserve RetroArch fast-forward while using the hotplug route. Only the
  RetroArch launcher enables bounded fast-producer drops; normal playback and
  the transition out of fast-forward were confirmed without audio breakup.
- [x] Decouple PicoArch presentation from the 58.955 Hz LCD clock. QuickNES now
  keeps native 48 kHz audio and normal pitch while the framebuffer presenter
  runs on a separate thread. The user confirmed clean USB DAC playback; the
  remaining scrolling cadence matched RetroArch on a second test game.
- [x] Keep Pulse/PipeWire out of the normal path; direct hardware playback is an
  explicit diagnostic only.
- [x] Replace fixed/OC CPU-frequency presets with dynamic V90S governors:
  Ondemand (FE and all-system default), Interactive, Performance, Schedutil,
  and Conservative. Restore the full hardware frequency range before applying
  a governor while retaining explicit per-system and per-ROM overrides.
- [x] Verify that the vendor PowerVR runtime exposes no standard devfreq GPU
  governor; keep GPU governor controls out of the FE.
- [x] Remove per-system and per-ROM CPU core-count limits. Keep CPU0-CPU3
  online in the FE, scraper, RetroArch, PicoArch, Pyxel, and standalone paths;
  retain governor selection as the only CPU performance control.
- [ ] Keep future `irqbalance` experiments separate from the known-good
  video/audio baseline unless validation proves a benefit.

## Milestone 7: Release Packaging

- [ ] Generate a full SD-root style package:
  `dist/plumos-v90s-sdroot-VERSION/`.
- [x] Generate an update-only package:
  `dist/plumos-v90s-update-VERSION/`.
- [x] Ensure update-only packages can be copied over the FAT32 app layer from
  Windows or macOS.
- [x] Generate release `manifest.json`.
- [x] Generate release `checksums.sha256`.
- [ ] Include license and notice files for:
  - plumOS-owned files
  - POWKIDDY StockOS/Batocera-derived runtime files
  - RetroArch
  - libretro cores
  - bundled standalone emulators
  - bundled frontend dependencies
- [x] Ensure release archives do not contain private ROMs or credentials.
- [x] Document the copy-over update workflow for Windows and macOS users.

## Milestone 8: Validation

- [x] Build the first policy-aligned development image with:
  - `v90s-stockos-r1` vendor runtime
  - system squashfs on p5
  - FAT32 app layer on the chosen p6/p7 partition
  - RetroArch launched from `/mnt/plumos`
- [ ] User boot-tests the development image on V90S.
- [ ] Record boot result under `docs/validation/`.
- [ ] Confirm LCD output.
- [ ] Confirm built-in controls.
- [ ] Confirm audio output.
- [ ] Confirm FPS, scrolling, and audio pitch remain at the known-good level.
- [ ] Confirm RetroArch settings persist after reboot.
- [ ] Confirm logs are visible from macOS or Windows through the FAT32 app
  layer.
- [ ] Test an update-only package by copying it onto the SD card from macOS or
  Windows.
- [ ] Record the update test result under `docs/validation/`.

## Deferred Reference Work

- [ ] Revisit Armbian only as a userspace/rootfs reference or component build
  helper.
- [ ] Revisit Buildroot only as a component build reference.
- [ ] Keep old KNULLI investigation paths available for comparison, but do not
  use them as the distribution identity.
- [ ] Add more libretro cores after the current A/B recipe set is validated on
  real hardware.
- [x] Add standalone emulators after the app-layer split is stable.
- [ ] Add frontend workflows after the app-layer split is stable.
