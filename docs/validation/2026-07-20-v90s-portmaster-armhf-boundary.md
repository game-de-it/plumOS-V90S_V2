# V90S PortMaster ARMHF Boundary

## Decision

ARMHF-only PortMaster games are not supported on plumOS V90S. The platform
adapter continues to publish `DEVICE_HAS_ARMHF=N`, and the installed-port
launcher rejects a script that declares `PORT_32BIT=Y` before stopping FE.

## Hardware Probe

Maldita Castilla provided a representative ARMHF GameMaker port:

- `gmloader` and its Android `libyoyo.so` are ARMv7 binaries.
- The StockOS kernel has a working 32-bit compatibility ABI.
- No 32-bit PowerVR EGL/GLES userspace library is present in the captured
  vendor runtime.
- A packaged ARMHF Mesa llvmpipe runtime could initialize the game and render
  it into an offscreen surface.
- Copying completed frames to the V90S 640x480 fbdev back buffer removed the
  visible flashing.
- Running the native AArch64 GPTokeYB helper separately restored controls.
- Physical testing still observed gameplay at roughly 10 fps.

The probe therefore demonstrated ABI compatibility, not a usable game path.
Software GLES rendering plus framebuffer readback is too slow for release and
must not be retained as a silent fallback.

The temporary ARMHF runtime was removed from `/run` after the probe. The
regular PortMaster component was rebuilt successfully and its complete
`checksums.sha256` passed. The resulting V90S package is 53 MiB and contains no
`adapter/runtime/armhf` tree. Its key hashes are:

```text
2d83ee7447b69061666f3085186b316c98f908ec02658dfbe81752c9ce024dfe  portmaster.manifest
8ce55460aeb64ce311c934c5bd4b62847277a9769110673920114c5578c27295  checksums.sha256
0571d192b424ac6c8eae3f63977ccb4cb9393116117af4f5a22448ca5459a0df  plumos/bin/plumos-portmaster-port-launch
```

## Runtime Contract

Supported PortMaster games must provide an AArch64 runtime that can use the
normal plumOS PowerVR SDL2/EGL/GLES route. Existing ARMHF-only installations
remain on storage but return an explicit compatibility failure and leave the
frontend running. The failure is appended to:

```text
/mnt/plumos/Logs/apps/portmaster-ports.log
```

The live SD card contained two launchers declaring `PORT_32BIT=Y`: Maldita
Castilla and Valhalla. A post-deployment Maldita request returned status 78,
kept the same FE PID (`26316` before and after), started no `gmloader` or
GPTokeYB process, and wrote `unsupported_armhf` to the log. The deployed
launcher and restored AArch64 GPTokeYB wrapper were also merged into the root
app-layer `checksums.sha256` and verified from `/mnt/plumos`.
