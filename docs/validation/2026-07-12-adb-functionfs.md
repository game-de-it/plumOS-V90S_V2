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

The live device has the updated frontend language resources and the running
frontend process is the app-layer fbdev binary:

```text
/mnt/plumos/bin/plumos-controller-ui-fbdev --renderer fbdev
/mnt/plumos/share/frontend/lang/ja.lang:
settings.item.network_adb_enabled.name=ADB
settings.item.network_adb_status.name=ADB
```

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

`udc_state=not attached` and macOS `adb devices -l` initially returned no
devices, which meant the gadget was ready on the V90S side but not physically
attached to the Mac as a USB device at that moment.

## macOS USB Validation

After connecting the V90S to the Mac with a USB cable, macOS detected the ADB
gadget:

```text
List of devices attached
plumos-v90s-72fd7cb5   device usb:2-1 transport_id:1
```

ADB shell command execution worked:

```text
uid=0(root) gid=0(root) groups=0(root)
Linux (none) 4.9.191 #17 SMP PREEMPT Tue May 13 18:14:09 UTC 2025 aarch64 GNU/Linux
Filesystem                Size      Used Available Use% Mounted on
/dev/mmcblk0p7         1022.0M    345.3M    676.7M  34% /mnt/plumos
```

The device-side ADB state moved to configured:

```text
service=adb
state=running
summary=ADB over USB FunctionFS
gadget_bound=1
udc_state=configured
/sys/kernel/config/usb_gadget/plumos_adb/UDC=5100000.udc-controller
/sys/class/udc/5100000.udc-controller/state=configured
```

ADB file transfer also worked. A 51-byte test file was pushed to `/tmp`, pulled
back to macOS, and both hashes matched:

```text
586c72c65990100407949e017635f601e325ebd68c421fd999fa2dead199925f
```

## Frontend Service Control Validation

The frontend calls the same service controller used below, so this validates the
ON/OFF backend that the NW Service row uses.

ADB OFF:

```text
/mnt/plumos/bin/plumos-network-services stop adb
service=adb
state=stopped
summary=ADB stopped
enabled=0

adb devices -l
List of devices attached
```

ADB ON:

```text
/mnt/plumos/bin/plumos-network-services start adb
service=adb
state=running
summary=ADB over USB FunctionFS
enabled=1

/mnt/plumos/bin/plumos-adbd status
running=1
ffs_mounted=1
gadget_bound=1
udc_state=configured

adb devices -l
plumos-v90s-72fd7cb5   device usb:2-1 transport_id:1

adb shell id
uid=0(root) gid=0(root) groups=0(root)
```

After a later repeated stop/start cycle with the cable still connected, the V90S
side again reported `gadget_bound=1` and `udc_state=configured`, and macOS
IORegistry showed `plumOS V90S ADB`, but `adb devices -l` stayed empty. Treat
this as a remaining host re-enumeration or ADB handshake stability issue,
separate from the frontend service registration.

The FE navigation/action path was then validated with the controller UI script
runner. This uses the same `handle_action()` path as button input:

```text
start,down,down,a,down,down,a,down,down,down,down,a
```

That sequence opens `START -> Network Settings -> NW Service`, selects `ADB`,
and presses `A` on the checkbox row.

FE toggle OFF:

```text
PLUMOS_FRONTEND_MODE=manual PLUMOS_RENDERER=text \
  /mnt/plumos/bin/plumos-controller-ui-fbdev \
  --renderer text \
  --script start,down,down,a,down,down,a,down,down,down,down,a \
  --no-clear
rc=0

/mnt/plumos/bin/plumos-network-services status adb
service=adb
state=stopped
summary=ADB stopped
enabled=0

adb devices -l
List of devices attached
```

FE toggle ON:

```text
PLUMOS_FRONTEND_MODE=manual PLUMOS_RENDERER=text \
  /mnt/plumos/bin/plumos-controller-ui-fbdev \
  --renderer text \
  --script start,down,down,a,down,down,a,down,down,down,down,a \
  --no-clear
rc=0

/mnt/plumos/bin/plumos-network-services status adb
service=adb
state=running
summary=ADB over USB FunctionFS
enabled=1

/mnt/plumos/bin/plumos-adbd status
running=1
ffs_mounted=1
gadget_bound=1
udc_state=configured

adb devices -l
plumos-v90s-72fd7cb5   device usb:2-1.1 transport_id:2

adb shell id
uid=0(root) gid=0(root) groups=0(root)
```

## Live Visible Screen Mismatch

The first FE toggle validation used a separate controller-UI process, so it did
not prove that the already-running visible FE process had picked up the new
binary. A direct framebuffer capture of the user's visible screen showed the
problem:

```text
NETWORK SETTINGS - NW SERVICE
SSH
FTP
SFTP
SAMBA
USB DISK MODE
```

ADB was absent even though the file on disk contained the ADB strings. The
running process explained the mismatch:

```text
/proc/1692/exe -> /mnt/plumos/bin/plumos-controller-ui-fbdev (deleted)
```

The FAT32 app-layer binary had been replaced while the old FE process was still
running, so the visible screen was rendered by the deleted pre-ADB executable.
Restarting only the frontend through the safe frontend stop/launch scripts fixed
the mismatch:

```text
/mnt/plumos/bin/plumos-frontend-stop stop
nohup /mnt/plumos/bin/plumos-frontend-launch \
  >/mnt/plumos/Logs/frontend-restart-adb-menu-fixed.log 2>&1 &

/proc/9046/exe -> /mnt/plumos/bin/plumos-controller-ui-fbdev
```

A later framebuffer capture of `NETWORK SETTINGS - NW SERVICE` showed the
expected row:

```text
SSH
FTP
SFTP
SAMBA
ADB
USB DISK MODE
```

## Validation Still Needed

- Confirm the same FE checkbox row manually with the physical V90S controls
  during normal menu navigation.
- Investigate repeated ADB stop/start while the USB cable is connected; macOS
  may still see the USB gadget while the adb host does not list it until a
  reconnect or another recovery step.
- Decide whether ADB should remain enabled in development profiles after reboot
  or be treated as an explicit temporary service.
