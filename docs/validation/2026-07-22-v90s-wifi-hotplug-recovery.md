# V90S USB Wi-Fi hotplug recovery

Date: 2026-07-22

## Failure evidence

The V90S remained reachable through ADB while Wi-Fi was unavailable. The USB
Wi-Fi dongle was still enumerated as Realtek `0bda:c820`, and
`wpa_supplicant` reported:

```text
ssid=example-wifi-1
wpa_state=COMPLETED
```

However, `wlan0` had no IPv4 address or default route and plumOS correctly
reported `wifi=off`. Kernel logs showed repeated disconnect and re-enumeration
of the complete OTG hub tree, including the Wi-Fi dongle:

```text
sunxi-ehci 5200000.ehci1-controller: highspeed device disconnect
usb 1-1: USB disconnect
usb 1-1.2: USB disconnect
usb 1-1.3: USB disconnect
usb 1-1: new high-speed USB device
```

The saved user intent was still `"wifi_enabled": true`. The failure was not an
authentication or credential error: the one-shot DHCP process had completed
earlier, the USB disconnect removed the lease from the interface, and no DHCP
request was triggered when the wireless interface returned.

## Immediate recovery

The existing bounded recovery path was invoked over ADB:

```text
plumos-network-control --wifi on
result=connected
ip=192.0.2.120
```

The default route returned through `192.0.2.1`. SSH, FTP, and SFTP all
reported `running`; Samba remained intentionally disabled.

## Permanent correction

The app layer now contains:

```text
/mnt/plumos/bin/plumos-wifi-recovery
/mnt/plumos/bin/plumos-wifi-uevent
```

When the saved Wi-Fi switch is ON, the frontend launcher starts a blocking
BusyBox kernel-uevent monitor. A wireless `SUBSYSTEM=net`, `ACTION=add` event
is coalesced, allowed a short controller settle period, and routed through one
bounded `plumos-network-control --wifi on` call. Wi-Fi OFF stops the exact
PID-validated monitor. There is no timer, periodic interface probe, or retry
loop while the dongle is absent.

## Host simulation

A privileged Linux test validated:

```text
wifi-uevent-recovery=PASS
```

The test confirmed monitor start for `wifi_enabled=true`, one recovery call for
`wlan0` add, no call for `eth0`, monitor stop for `wifi_enabled=false`, and no
recovery while disabled. A separate startup-identity test confirmed that the
manager waits only until the spawned process has exec'd BusyBox before
reporting `monitor_running=1`:

```text
wifi-monitor-start-identity=PASS
```

## Live deployment

The runtime scripts, frontend launcher, merged component checksum, and only
their matching app-layer manifest/checksum entries were deployed over ADB.
Unrelated user settings and application payloads were retained. Host and live
device hashes matched:

```text
c127afa81489fa35d2d966752d8a9bd8a202fc869d268c7152176d72cb5d21d4  plumos-network-control
cd165fa47a3b3b362944d805078f87fba5ec9936c498d5157f9bcc6a5dbe1553  plumos-wifi-recovery
cb1ead33d9e71fe2f7dbe621792abe3504c08e032ef1ebe79d09419db4f9aa5a  plumos-wifi-uevent
c829a85d7db81bc10ce4e9e9d9a263020dd46b48839c9098f80a2d52658641a0  plumos-frontend-launch
```

Current live result:

```text
wifi_requested=1
monitor_running=1
mode=kernel_uevent
wifi=on
iface=wlan0
ip=192.0.2.120
default via 192.0.2.1 dev wlan0
app_layer=ready
```

Exactly one ADB uevent monitor and one Wi-Fi uevent monitor were running.

## Remaining physical validation

With Wi-Fi ON, unplug and reconnect the OTG hub or Wi-Fi dongle. Confirm that
IPv4, the default route, SSH, FTP, and SFTP return without toggling Wi-Fi in the
frontend and without issuing a recovery command over ADB.
