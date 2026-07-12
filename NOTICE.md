# plumOS V90S Notice

plumOS V90S uses POWKIDDY V90S StockOS/Batocera-derived runtime components for
hardware compatibility on the POWKIDDY V90S handheld.

These components may include boot images, boot environment data, Linux kernel
modules, PowerVR GE8300 firmware and userspace libraries, SDL2 runtime files,
ALSA/Pulse/PipeWire/WirePlumber configuration, RetroArch-related configuration,
and other device-specific files extracted from a POWKIDDY V90S StockOS image.

POWKIDDY StockOS is treated as the vendor runtime baseline for this device.
Batocera, RetroArch, libretro cores, Linux, BusyBox, PipeWire, SDL, and other
third-party components remain under their respective upstream licenses.

The V90S File Manager app is built from the LoveRetro NextCommander upstream
source reference at <https://github.com/LoveRetro/NextCommander>. No separate
upstream `LICENSE` file was present in the inspected repository.

The V90S Music Player app is ported from the plumOS MMF/A30
`plumos_music_player.c` source and uses upstream decoder/runtime libraries such
as miniaudio and FFmpeg/libav when those components are bundled by the build
output.

New plumOS-authored scripts, configuration, packaging logic, and device
integration files are maintained in this repository.
