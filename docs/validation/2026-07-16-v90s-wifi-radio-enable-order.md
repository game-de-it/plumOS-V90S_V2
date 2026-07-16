# V90S Wi-Fi radio enable order

Date: 2026-07-16

## Symptom

After inserting the USB Wi-Fi dongle, changing `Network Settings -> Wi-Fi`
between OFF and ON did not light or initialize the dongle.

ADB separated USB enumeration from the Wi-Fi runtime:

```text
USB ID: 0bda:c820
product: 802.11ac NIC
kernel module: not loaded
wlan0: missing
wifi=off
dongle=present_no_wifi_iface
```

The vendor `8821cu.ko` and its `usb:v0BDApC820` alias were present and valid.
Loading that module manually immediately created `wlan0`, and the normal scan
backend found `example-wifi-2` and the surrounding access points.

## Cause

`plumos-network-control --wifi on` checked for a saved WPA configuration before
calling `ensure_wifi_iface()`. A newly written image intentionally contains no
private Wi-Fi credentials, so the command returned `stage=missing_config`
without loading the USB driver or bringing up the radio.

The frontend saved `wifi_enabled=true` before invoking that backend. This left
the checkbox enabled while the physical runtime was still absent.

## Fix

The Wi-Fi ON path now performs these operations in order:

1. Detect the inserted USB device and its module alias.
2. Load the matching vendor module.
3. Wait for and bring up the Wi-Fi interface.
4. Check for a saved WPA configuration.
5. Connect when credentials exist, or return `result=ready` when they do not.

The frontend recognizes `result=ready` and displays:

```text
Wi-Fi on; use Connect Wi-Fi
```

Credentials remain user-owned p7 state and are not embedded in the repository
or release image.

## Live validation

The exact first-use state was reproduced by stopping Wi-Fi, unloading
`8821cu`, and temporarily moving both WPA configuration copies to RAM. The FE
button path then produced:

```text
START -> Network Settings -> Wi-Fi -> A
Wi-Fi false -> true
status: Wi-Fi on; use Connect Wi-Fi
module: 8821cu loaded
wlan0_operstate=up
wifi_enabled=true
```

After restoring the user-owned configuration, the same backend connected
normally:

```text
wifi=on
iface=wlan0
ip=192.0.2.120
gateway=192.0.2.1
gateway_ping=ok
wpa_supplicant=running
```

ADB remained available throughout. Exactly one frontend process was restored,
and SSH, FTP, SFTP, Samba, and ADB all reported `running` after reconnection.

## Build and deployment

The following official targets completed:

```text
./scripts/docker-build.sh network-services
./scripts/docker-build.sh frontend
./scripts/docker-build.sh app-layer
```

All generated checksums passed: 259 network-service files, 343 frontend files,
and 4,069 app-layer files. Generated and deployed hashes matched:

```text
36a097c0f7ec6ce1ada1082e7b1bf6df364856639d5eb9054d541d7d3f0ed250  plumos-network-control
5b1e4fd40d2ee73eea1c445dc44d457c279ec716f4b6474e1e137dfee6c0fc01  plumos-controller-ui-fbdev
```
