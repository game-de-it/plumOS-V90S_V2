# Hardware Integration

## Display and PowerVR

The vendor baseline exposes the V90S LCD through `/dev/fb0` and PowerVR GE8300
EGL/GLES libraries. plumOS SDL2 uses the hardware-accurate package name
`sdl2-powervr`; the underlying vendor compatibility driver remains `mali_fbdev`.
RetroArch and native applications must load the packaged PowerVR EGL/GLES and
SDL libraries before generic system compatibility libraries.

The LCD timing is not exactly a nominal 60.000 Hz. Do not force emulation audio
to the display clock to make an FPS counter read 60. Each runtime owns pacing:
RetroArch uses its adopted threaded-video/sync settings, while PicoArch presents
on a dedicated path without changing core audio pitch. Framebuffer page count,
pitch, pixel format, and visible dimensions must be preserved by overlays and
direct renderers.

## Audio

All normal clients open ALSA `default` or the `plumos_output` alias. The generated
configuration lives under `/run/plumos/audio/` and the AArch64 ioplug router
selects the physical output:

- internal codec: mix left and right into mono, apply the shared 0..12 software
  gain, keep card 0 `DAC volume` at `170,170`
- USB DAC: preserve stereo and negotiate supported formats/rates
- hotplug: migrate an already-open stream between internal and USB output
  without restarting the game

The router accepts common application formats and converts to the physical
device. Launchers prepare the route and export the generated ALSA configuration.
Direct `hw:0,0` is diagnostic-only. Applications bypassing ALSA require a
specific integration layer.

Global power-overlay cancel must resume paused clients and re-prepare the route;
it must not leave standalone or PPSSPP audio silent. XRUN and suspend recovery
are handled in the router without treating unrelated errors as recoverable
underruns.

## Input and Global Keys

Low-level input comes from StockOS kernel devices including `adc_gamepad` and
`axp2202-pek`. FE, SDL2 launchers, PicoArch, and standalone helpers normalize
D-pad, ABXY, shoulders, L2/R2, SELECT, START, function, volume, and power keys.

The global hardware-key service remains active across FE, RA, PicoArch,
standalone emulators, Apps, and PortMaster. It owns:

- volume keys: 12-step software volume with coalesced persistent writes
- SELECT + volume: display brightness action where a backend exists
- power key: global power menu
- system-wide emergency quit policy used by supported launchers

Avoid duplicate readers and unbounded key repeat. A child-specific input helper
must start and stop with that child.

## CPU and GPU Policy

The default CPU governor is `ondemand`; `performance` and other exposed dynamic
governors may be selected per system. Fixed-frequency UI settings are not
supported. Before a per-game governor is applied, all CPUs must be online and
stale fixed min/max overrides cleared. Normal exit restores the system policy.

The vendor PowerVR stack exposes no standard devfreq governor suitable for FE
control. Do not present a GPU-governor setting. Vendor power management remains
responsible for idle GPU clock and suspend behavior.

## USB and Network

V90S has no internal Wi-Fi. `plumos-network-control` drives supported USB Wi-Fi
interfaces with bounded scan/connect/DHCP stages. `plumos-wifi-recovery` sleeps
on netlink uevents and performs one bounded reconnect when an enabled dongle is
re-added; it does not poll indefinitely when no dongle exists.

The USB Wi-Fi modules bundled in `v90s-stockos-r1` and loadable by the network
controller are:

| Source | Kernel modules |
| --- | --- |
| StockOS-derived extra modules | `8192eu`, `8723bu`, `8812au`, `8821cu`, `88x2bu` |
| Vendor kernel standard modules | `rtl8192cu`, `rtl8xxxu` |

The real-device validated route is USB ID `0bda:c820`, module `8821cu`, and
interface `wlan0`. The controller contains an `8188eu` compatibility path, but
`v90s-stockos-r1` does not bundle a separate `8188eu.ko`, so it is not listed as
a supported module. Match `/sys/bus/usb/devices/*/idVendor` and `idProduct`
against the bundled `modules.alias` data instead of relying on a retail product
name. Adding a new module or firmware to the vendor runtime requires real-device
validation followed by a vendor runtime ID revision.

Network service state is stored in
`/mnt/plumos/config/network/services.conf`. The controller owns OpenSSH/SFTP,
BusyBox FTP, Samba SMB2, and ADB FunctionFS. Services enabled without IPv4 enter
a waiting state rather than blocking FE. SSH login PATH prefers
`/mnt/plumos/bin:/mnt/plumos/gnu/bin`.

ADB and USB Disk Mode share the USB gadget controller. The ADB uevent helper may
repair a detached UDC, but it must not steal the gadget while mass storage owns
it. USB hub compatibility and available power remain physical constraints.

## Battery, RTC, and Time

The FE battery service reads the vendor power-supply sysfs interface and renders
bounded percentage/status values. The RTC is set through the kernel interface
when available. Automatic Time synchronizes from the network after Wi-Fi gains
IPv4 and writes the resulting time to RTC; it must not block FE startup or
PortMaster TLS indefinitely.

## Primary Implementations

- `package/audio-router-v90s/`
- `package/frontend-v90s/plumos/bin/plumos-audio-output`
- `package/frontend-v90s/plumos/bin/plumos-volume-control`
- `package/frontend-v90s/plumos/bin/plumos-hardware-keys-service`
- `package/frontend-v90s/plumos/bin/plumos-power-menu-overlay`
- `package/frontend-v90s/plumos/bin/plumos-display-control`
- `package/network-services/plumos/bin/plumos-network-control`
- `package/network-services/plumos/bin/plumos-wifi-recovery`
- `package/network-services/plumos/bin/plumos-adbd`
