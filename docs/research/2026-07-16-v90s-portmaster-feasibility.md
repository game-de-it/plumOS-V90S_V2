# V90S PortMaster Feasibility

Date: 2026-07-16

## Conclusion

PortMaster can be integrated into plumOS V90S, but the upstream package is not
drop-in compatible. A bounded real-device probe proved that the official
PortMaster GUI starts with plumOS libraries, opens the V90S controller, and
renders its 640x480 disclaimer screen through the PowerVR SDL2 framebuffer
path.

The first implementation should therefore be a plumOS platform adapter around
the upstream GUI, not a fork of every port. Individual ports still require
compatibility filtering and real-device validation because their graphics,
architecture, and runtime requirements vary.

## Sources Inspected

- PortMaster-GUI commit
  `92efe43b36ea5a9ebc613990a7424228783f5184` from 2026-07-05.
- PortMaster-New commit
  `0d9880ec45269e5dd6df11e5949f07005d5108d8` from 2026-07-15.
- Official supported-device, installation, and packaging documentation:
  - <https://portmaster.games/supported-devices.html>
  - <https://portmaster.games/installation.html>
  - <https://portmaster.games/packaging.html>
  - <https://github.com/PortsMaster/PortMaster-GUI>

The V90S and plumOS are not listed as officially supported. The upstream
documentation does, however, define 640x480 as a normal target resolution and
supports AArch64 ports on several comparable Linux handhelds.

## V90S Compatibility Inventory

| Requirement | V90S result | Status |
| --- | --- | --- |
| CPU architecture | AArch64, four Cortex-A53 cores | compatible |
| Linux userspace | Debian Bookworm, glibc 2.36 | compatible |
| Python | Python 3.11.2 | compatible |
| Display | 640x480, 32-bit fbdev | compatible |
| SDL2 | plumOS PowerVR SDL2 2.30.6 | compatible with wrapper |
| Controller | `adc_gamepad`, SDL mapping detected | compatible |
| Memory | 1GB | compatible with normal 1GB-class ports |
| Network | bundled Python `requests` completed HTTPS | compatible |
| Runtime images | kernel advertises SquashFS; loop devices exist | likely compatible; mount test remains |
| ARMHF loader | `/lib/ld-linux-armhf.so.3` is absent | AArch64 only initially |
| OpenGL | vendor PowerVR GLES runtime, no general desktop OpenGL contract | port dependent |

The official `sdl_resolution.aarch64` helper linked against
`/mnt/plumos/lib/plumos-sdl2-powervr/libSDL2-2.0.so.0` and reported:

```text
Current Display Resolution: 640x480
```

The GUI loaded the following plumOS libraries successfully:

```text
SDL2       2.30.6
SDL2_ttf   2.20.1
SDL2_image 2.6.3
SDL2_mixer 2.6.2
```

These extension libraries already exist in the app layer. Because FAT32 does
not preserve ELF SONAME symlinks, the launch adapter must recreate their
canonical names under `/run`, using the same model as the existing standalone
and RetroArch launchers.

## Real-Device GUI Probe

The official 44MB PortMaster GUI payload was copied only to
`/run/portmaster-gui-probe`; no SD-card PortMaster data or existing port was
modified. The frontend was stopped with `plumos-frontend-stop`, the GUI was
run for a bounded interval, and exactly one frontend process was restored.

Runtime evidence:

```text
gui_alive=yes
SDL DLL: /run/pm-sdl/libSDL2-2.0.so.0, 2.30.6
Opened GameController 0: adc_gamepad
Display size: 640x480
MALI_CreateWindow:... done.
```

Both framebuffer pages contained a correctly sized PortMaster disclaimer
screen. Local diagnostic artifacts are kept in the ignored directory:

```text
output/validation/portmaster-v90s-feasibility/
```

The GUI did not need an X11, Wayland, or Weston session for this probe.

## Required plumOS Adapter

The upstream launch scripts assume known CFW paths and services. plumOS needs
an explicit integration layer with these responsibilities:

1. Identify the platform as `plumOS` and the device as `powkiddy-v90s` with
   A133/A133P, 640x480, 1GB RAM, no analog sticks, and AArch64 capability.
2. Set PortMaster tools, installed-port, and launcher paths under the plumOS
   app/content layout instead of `/roms/ports`.
3. Force the proven PowerVR SDL2, EGL/GLES, controller database, and
   `plumos_output` ALSA environment.
4. Build the FAT32 SONAME directory under `/run` before starting the GUI or a
   port.
5. Stop and restore the frontend through the owned plumOS PID helpers. Do not
   use upstream broad `pkill`, `pidof`, or unrelated `systemctl` restart paths.
6. Replace upstream `pm_finish` and GPTokeYB cleanup with PID-owned cleanup so
   SSH, ADB, the frontend, and unrelated games cannot be stopped.
7. Keep PortMaster settings, downloaded runtimes, installed ports, saves, and
   logs writable under `/mnt/plumos`; keep immutable hardware glue in the
   system squashfs.
8. Make installation/update failure explicit. Do not silently launch a
   fallback copy or overwrite a working PortMaster installation in place.

Upstream device detection currently misidentifies the V90S device tree as a
TrimUI Smart Pro and assigns 1280x720 with two analog sticks. The probe used a
temporary 640x480 device override. A permanent V90S entry is mandatory before
normal use.

## Port Compatibility Boundary

Successful GUI startup does not mean every catalog port will run.

- Start with native AArch64, SDL2/GLES, 640x480-compatible Ready-to-Run ports.
- Do not advertise ARMHF-only ports until an explicit 32-bit loader and library
  runtime is packaged and validated.
- Treat desktop OpenGL, X11/Wayland, Westonpack, GL4ES, Box64, Mono, Java, and
  other SquashFS runtime users as separate compatibility classes.
- Do not report a port as V90S-compatible based only on installation or process
  startup. Validate visible video, controller input, audio, exit behavior,
  saves, and frontend restoration on hardware.
- Use conservative capability metadata initially. The A133P is comparable to
  other A53 handhelds, but the proprietary PowerVR route differs from the
  upstream Mesa/KMS assumptions used by some ports.

The SD2 currently contains several existing PortMaster-format ports. Their
scripts confirm why the adapter is needed: older packages hard-code
`/$directory/ports`, source the upstream `control.txt`, kill GPTokeYB by broad
process name, and restart `oga_events` through systemd. Those scripts must not
be launched unchanged on plumOS.

## Recommended Implementation Sequence

1. Add a reproducible `portmaster` build/package target pinned to an upstream
   release and include its license/manifest/hash.
2. Add `control.txt` and `mod_plumOS.txt` adapters plus a V90S hardware entry.
3. Add a plumOS-owned GUI launcher and safe process lifecycle wrapper.
4. Add PortMaster to FE Apps and validate GUI navigation, metadata refresh, and
   one small installation without launching the game.
5. Validate one lightweight AArch64 Ready-to-Run SDL2/GLES port end to end.
6. Generate a compatibility report and hide unsupported architecture/runtime
   classes rather than presenting them as known-good.

