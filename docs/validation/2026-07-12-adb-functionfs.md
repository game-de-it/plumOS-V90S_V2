# V90S ADB FunctionFS implementation

## Goal

Provide interactive USB command execution without relying on the unstable USB
Wi-Fi dongle. The requested approach is normal ADB rather than a custom command
protocol.

## Kernel Surface

The StockOS-derived V90S kernel exposes the pieces needed for an ADB gadget:

```text
CONFIG_USB_GADGET=y
CONFIG_USB_CONFIGFS=y
CONFIG_USB_CONFIGFS_F_FS=y
CONFIG_USB_SUNXI_USB_ADB=y
```

It does not expose USB Ethernet or ACM serial gadget support, so SSH-over-USB
and serial-console-over-USB are not available with the current vendor runtime.

## Userspace Source

The StockOS and plumOS rootfs snapshots did not contain an `adbd` daemon. Debian
and Ubuntu packages provide the host `adb` client, not the device daemon, so
plumOS builds the daemon from the Debian `android-platform-tools` source package:

```text
android-platform-tools_29.0.6-28.dsc
android-platform-tools_29.0.6.orig.tar.gz
android-platform-tools_29.0.6-28.debian.tar.xz
```

The network-services builder downloads these files from Debian, checks fixed
sha256 hashes, compiles the AOSP daemon sources with `clang++`, and packages
the output under:

```text
/mnt/plumos/adb/bin/adbd
/mnt/plumos/adb/bin/adbd.bin
```

The first V90S daemon uses a small no-auth stub because the StockOS-derived
userspace does not provide Android framework key management. Treat it as a
trusted-host-only development service.

The V90S build applies three small source patches while compiling the Debian
source package:

- enable daemon USB FunctionFS initialization outside full Android framework
  builds
- force legacy FunctionFS because the V90S kernel lacks FunctionFS AIO support
- force synchronous FunctionFS I/O because the legacy AIO path also fails with
  `Function not implemented`

## Runtime Control

`plumos-adbd` owns the USB gadget setup:

```text
/mnt/plumos/bin/plumos-adbd start
/mnt/plumos/bin/plumos-adbd stop
/mnt/plumos/bin/plumos-adbd status
```

The order follows the standard FunctionFS pattern:

1. mount configfs if needed
2. create `usb_gadget/plumos_adb`
3. create and link `functions/ffs.adb`
4. mount FunctionFS at `/dev/usb-ffs/adb`
5. start `adbd`
6. wait for FunctionFS endpoints
7. bind the gadget to the UDC

The frontend-facing service controller wraps this as:

```text
/mnt/plumos/bin/plumos-network-services start adb
/mnt/plumos/bin/plumos-network-services stop adb
/mnt/plumos/bin/plumos-network-services status adb
```

ADB defaults to disabled unless `adb_enabled=1` is written to
`/mnt/plumos/config/network/services.conf`.

## Frontend

Network Settings now includes:

```text
NW Service -> ADB
Information -> ADB
```

The toggle uses the same `plumos-network-services` path as SSH, FTP, SFTP, and
Samba, so the UI, service state, logs, and boot-time `start-enabled` behavior
all agree.

## Build Validation

Validated locally:

```text
./scripts/docker-build.sh image
./scripts/docker-build.sh network-services
./scripts/docker-build.sh frontend
./scripts/docker-build.sh app-layer
```

The generated network-services manifest records:

```text
adbd: android-platform-tools_29.0.6-28
adbd-auth: no-auth development daemon
adbd-patch: enable daemon USB FunctionFS init outside Android framework builds
adbd-patch: force legacy FunctionFS because V90S kernel lacks FunctionFS AIO
adbd-patch: force synchronous FunctionFS I/O for V90S
```

## Live Deployment

Live V90S target:

```text
ssh root@192.0.2.120
```

The first live start attempt proved the daemon binary could start but missed
`7z.so`; the runtime-library search path was expanded to include
`/usr/lib/p7zip`, and `plumos/lib/7z.so` is now packaged.

The second attempt proved the daemon needed the USB FunctionFS code path enabled
outside `__ANDROID__`; otherwise it only listened on TCP/VSOCK.

The third attempt proved the V90S kernel does not support the AOSP nonblocking
FunctionFS AIO path:

```text
failed to create aio_context_t: Function not implemented
```

The fourth attempt proved the legacy code path still used AIO unless
`sys.usb.ffs.aio_compat` was true. Since there is no Android property service,
the V90S build now forces synchronous FunctionFS I/O.

Current live status after the final deployment:

```text
service=adb
state=running
summary=ADB over USB FunctionFS
enabled=1
adbd_installed=1
running=1
ffs_mounted=1
gadget_bound=1
udc_state=not attached
```

FunctionFS endpoints exist:

```text
/dev/usb-ffs/adb/ep0
/dev/usb-ffs/adb/ep1
/dev/usb-ffs/adb/ep2
```

`udc_state=not attached` and macOS `adb devices -l` returned no devices during
this validation, which means the gadget was ready on the V90S side but not
physically attached to the Mac as a USB device at that moment.

## Validation Still Needed

- Connect V90S to the Mac as a USB device with a data-capable cable, while ADB
  is enabled.
- Confirm on macOS:

```text
adb devices -l
adb shell id
adb shell df -h /mnt/plumos
adb push/pull
```
