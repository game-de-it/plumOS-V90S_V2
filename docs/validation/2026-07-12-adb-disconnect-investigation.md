# V90S ADB disconnect investigation

Date: 2026-07-12

## Context

The user enabled SSH after ADB disappeared from the macOS host. The goal was to
separate an ADB daemon timeout from a USB gadget, UDC, cable, or host-side ADB
issue.

## Host-side state before recovery

macOS did not list any ADB device:

```text
adb devices -l
List of devices attached
```

Restarting the macOS ADB server did not recover the device:

```text
adb kill-server
adb start-server
adb devices -l
List of devices attached
```

macOS USB inspection also did not show `plumOS V90S ADB` at that point. This
means the host was not merely missing an ADB protocol handshake; the USB device
itself was no longer enumerated.

## Device-side state before recovery

SSH to `192.0.2.120` was available. The V90S ADB service was enabled, but the
live USB gadget state was stopped:

```text
/mnt/plumos/bin/plumos-adbd status
service=adb
running=1
ffs_mounted=1
gadget_bound=0
udc_state=not attached
state=stopped
summary=ADB stopped

/mnt/plumos/bin/plumos-network-services status adb
service=adb
state=stopped
summary=ADB stopped
enabled=1
```

The `adbd` process and FunctionFS mount were still present:

```text
/mnt/plumos/run/adbd.pid: 9576
/mnt/plumos/adb/bin/adbd.bin
adb /dev/usb-ffs/adb functionfs rw,relatime 0 0
```

The UDC was disconnected:

```text
/sys/class/udc/5100000.udc-controller/state: not attached
/sys/class/udc/5100000.udc-controller/current_speed: UNKNOWN
```

Kernel logs showed repeated USB link transitions and the final disconnect:

```text
android_work: sent uevent USB_STATE=CONNECTED
configfs-gadget gadget: high-speed config #1: c
android_work: sent uevent USB_STATE=CONFIGURED
ERR : dev->driver=0xffff800029525dd0, dev->gadget.speed=0
android_work: sent uevent USB_STATE=DISCONNECTED
```

The `adbd` log showed the corresponding transport shutdowns:

```text
remote usb: read terminated (message): Connection reset by peer
remote usb: read terminated (message): Cannot send after transport endpoint shutdown
```

## Recovery test

Restarting only the ADB service over SSH recovered the USB gadget:

```text
/mnt/plumos/bin/plumos-network-services start adb
service=adb
state=running
summary=ADB over USB FunctionFS
enabled=1
```

Device-side state after recovery:

```text
/mnt/plumos/bin/plumos-adbd status
running=1
ffs_mounted=1
gadget_bound=1
udc_state=configured
state=running
summary=ADB over USB FunctionFS

/sys/class/udc/5100000.udc-controller/state: configured
/sys/class/udc/5100000.udc-controller/current_speed: high-speed
```

macOS then saw the USB device and ADB transport again:

```text
plumOS V90S ADB
USB Serial Number = plumos-v90s-72fd7cb5
idVendor = 6353
idProduct = 20199

adb devices -l
plumos-v90s-72fd7cb5   device usb:2-1.1 transport_id:1

adb shell id
uid=0(root) gid=0(root) groups=0(root)
```

A 60 second idle observation after recovery kept reporting the device:

```text
t=0s   plumos-v90s-72fd7cb5 device usb:2-1.1
t=10s  plumos-v90s-72fd7cb5 device usb:2-1.1
t=20s  plumos-v90s-72fd7cb5 device usb:2-1.1
t=30s  plumos-v90s-72fd7cb5 device usb:2-1.1
t=40s  plumos-v90s-72fd7cb5 device usb:2-1.1
t=50s  plumos-v90s-72fd7cb5 device usb:2-1.1
t=60s  plumos-v90s-72fd7cb5 device usb:2-1.1
```

## Conclusion

This disconnect was not caused by an idle timeout in `adbd`.

The observed failure mode was:

- `adb_enabled=1` stayed persisted.
- `adbd.bin` stayed alive.
- FunctionFS stayed mounted.
- The configfs gadget became unbound.
- The UDC state became `not attached`.
- macOS no longer enumerated `plumOS V90S ADB`.
- Restarting the ADB service rebound the gadget and restored ADB.

Treat this as a USB gadget / UDC / physical link disconnect path. It is
separate from the earlier documented case where V90S reports
`udc_state=configured` and macOS sees `plumOS V90S ADB`, but `adb devices` stays
empty.

## Follow-up

Possible fixes:

- Add a safe ADB recovery command that restarts only ADB when
  `adb_enabled=1`, `adbd` is alive, but `gadget_bound=0` or
  `udc_state=not attached`.
- Optionally expose that recovery path in the frontend information or network
  service UI.
- Keep investigating the separate host re-enumeration issue where USB remains
  configured but the ADB host list stays empty.
