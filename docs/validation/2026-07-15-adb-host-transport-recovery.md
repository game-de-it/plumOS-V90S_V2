# V90S ADB host transport recovery

Date: 2026-07-15

## Symptom

ADB disappeared while a PicoArch game remained active. Wi-Fi and the V90S OS
were still responsive, so this was not a system hang or an `adbd` idle timeout.

## Failure-state evidence

The device remained healthy over SSH:

```text
running=1
ffs_mounted=1
gadget_bound=1
udc_state=configured
```

The V90S kernel had no new disconnect event after its initial successful USB
configuration. macOS IOKit still reported the same high-speed device:

```text
plumOS V90S ADB@02110000
UsbLinkSpeed = 480000000
USB Serial Number = plumos-v90s-f23f90b1
```

The macOS ADB list was nevertheless empty. Its server log recorded the failure
at the same time:

```text
07-15 12:28:56.154 usb read failed: status = 1
07-15 12:28:56.155 connection terminated: usb read failed: status = 1
07-15 12:28:56.155 destroying transport plumos-v90s-f23f90b1
```

The active server was Android SDK ADB 35.0.2 even though Homebrew ADB 36.0.2
was also installed. The older SDK directory appeared first in `PATH`.

## Recovery and version test

Restarting only the macOS ADB server restored the existing USB gadget without
touching the V90S:

```text
adb kill-server
adb start-server
adb devices -l
plumos-v90s-f23f90b1 device usb:2-1.1 transport_id:1
```

The server was then standardized on ADB 36.0.2. The device-side ADB gadget was
deliberately restarted three times while the host list was sampled once per
second. Each restart caused only the expected short enumeration gap, then ADB
36.0.2 rediscovered the device automatically as transport IDs advanced. No
host-server restart, cable reconnect, frontend restart, or V90S reboot was
needed.

## Implementation

`scripts/v90s-adb.sh` is the project host entry point. It:

- selects the newest available ADB from Homebrew, Android SDK, or `PATH`;
- honors `PLUMOS_ADB_BIN` when a specific binary is required;
- detects the narrow macOS failure where IOKit still has
  `plumOS V90S ADB` but `adb devices` has no V90S transport;
- restarts only the host ADB server once in that state;
- passes normal ADB arguments through unchanged.

Use it for development commands:

```text
./scripts/v90s-adb.sh status
./scripts/v90s-adb.sh shell
./scripts/v90s-adb.sh push SOURCE DESTINATION
./scripts/v90s-adb.sh recover
```

Device status reporting now distinguishes a configured connection from a
gadget waiting for a host. A bound and running FunctionFS service reports
`waiting_usb` until the UDC reaches `configured` or `suspended`; the persistent
FE checkbox remains the saved enable policy.

## Conclusion

This occurrence was host-side ADB transport loss after a libusb read failure,
not PicoArch changing USB state and not `adbd` timing out. The earlier failure
recorded on 2026-07-12, where the V90S UDC itself became `not attached`, remains
a separate physical-link/device-gadget failure mode and is recovered by
restarting the device-side ADB service over SSH.
