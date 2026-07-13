# V90S network and USB recovery

Date: 2026-07-14

## Failure observed

After a hardware reset, the frontend Wi-Fi checkbox remained checked and did
not react to an OFF request. Enabling USB Disk Mode then left the frontend on a
non-responsive screen.

The live device was reachable briefly over Wi-Fi at `192.0.2.120`. Early in
boot, `/mnt/plumos` was not mounted yet. Once boot completed, the frontend was
running, but these app-layer control files were absent:

```text
/mnt/plumos/bin/plumos-network-control
/mnt/plumos/bin/plumos-network-services
/mnt/plumos/bin/plumos-adbd
/mnt/plumos/bin/plumos-usb-disk-mode
```

The StockOS rootfs had still started `wpa_supplicant`, so Wi-Fi was connected
even though the frontend control backend was missing. This explained the stale
checked state and the failed toggle.

## Live recovery

The complete `output/network-services/v90s/plumos` payload was restored over
SSH. The archive and deployed ADB-critical files were hash-checked. ADB then
started successfully and macOS enumerated:

```text
plumos-v90s-330ad2e0 device usb:2-1.1
```

Normal ADB command access was confirmed:

```text
uid=0(root) gid=0(root) groups=0(root)
```

Wi-Fi was tested through ADB so loss of Wi-Fi could not remove the diagnostic
path:

```text
OFF: wifi=off, ip=none, wpa_supplicant=stopped
ON:  result=connected, ip=192.0.2.120, wpa_supplicant=running
```

ADB remained connected throughout the Wi-Fi OFF/ON test.

## USB Disk Mode correction

The USB transfer helper exports a dedicated 64 MiB image. It does not export or
unmount `/mnt/plumos`. The apparent frontend hang came from the FE calling the
helper synchronously while the helper waited for the host to eject the drive
and disconnect the USB cable.

The frontend now starts USB Disk Mode asynchronously and polls a completion
file every 250 ms. It keeps rendering the USB instructions and returns to the
NW Service screen when the helper finishes.

ADB and USB mass storage share the V90S USB device controller. The helper now
uses `plumos-adbd` to pause an active, PID-validated ADB gadget before binding
mass storage, without changing `adb_enabled`. It restores ADB when USB Disk
Mode finishes or is terminated.

## Build and deployment

The following builds completed:

```text
./scripts/docker-build.sh frontend
./scripts/docker-build.sh network-services
```

Both generated checksum sets passed. The changed frontend and USB helper were
deployed over ADB and matched their build hashes:

```text
28f09d18d64092bf3d2dc429f58ac39b0308ef9ab1db91419ac903ef4a401218  plumos-controller-ui-fbdev
41f5be0563b70734498c65d8a6de57136b28e8ce5126050665b0ea1e1be6ef5c  plumos-usb-disk-mode
```

After deployment, one frontend process was running, Wi-Fi was connected at
`192.0.2.120`, and ADB reported `state=running`, `enabled=1`.

## Remaining physical check

Starting USB Disk Mode intentionally disconnects ADB while mass storage owns
the USB controller. The remaining check is to enter the mode from the FE,
confirm that `PLUMUSB` appears on macOS, eject it, unplug the cable, and confirm
that the FE returns and ADB reconnects after the cable is reattached.
