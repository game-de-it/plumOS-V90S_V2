# 2026-07-15 Release Wi-Fi Runtime Fix

## Symptom

The release-system image booted the frontend, and the Wi-Fi checkbox showed
enabled, but `Connect Wi-Fi` displayed no SSIDs.

ADB diagnostics separated saved UI state from the actual runtime:

```text
wifi_enabled=true
USB ID=0bda:c820
module=8821cu
iface=wlan0
wpa_supplicant=MISSING
wpa_cli=MISSING
scan stage=no_scan_backend
```

The USB dongle, vendor kernel module, and network interface were healthy. The
release-system package set had omitted the userspace scan backend.

## Fix

The release-system p5 now includes `wpasupplicant`, `iproute2`, `rfkill`, `iw`,
`usbutils`, and `wireless-regdb`. Credentials remain user-owned state on p7 and
are not embedded in the squashfs.

`plumos-network-control --scan` now polls `wpa_cli scan_results` for up to eight
seconds and returns as soon as at least one result is available. The tested
Realtek dongle needed about six seconds, so the previous fixed two-second wait
could return an empty list despite a working radio.

The app layer also adds `plumos-udhcpc-script`. It applies the BusyBox DHCP
lease to the interface and installs the default route and DNS. IP detection no
longer uses the unsupported BusyBox form `ip -4 addr`.

## Live Validation

The corrected FE command path returned eight visible network rows, including:

```text
network secured -42 example-wifi-2
```

Connecting through the same backend then reported:

```text
result=connected
ip=192.0.2.120
gateway=192.0.2.1
gateway_ping=ok
wifi=on
wpa_supplicant=running
```

## Image

```text
image: output/images/plumos-v90s-system-squashfs-20260715-4.img
image sha256: bddc599ff9ecedcbc781733b18d698960cd4d58a31f9d5d46cfb923b24c5be08
p5 sha256: e7fdb8fabb48217a8bb73a2a114a928836a351f27f9d465c2ed5e3b751a8d6e5
```

Host extraction verified `wpa_supplicant`, `wpa_cli`, and `iw` in p5 and both
`plumos-network-control` and `plumos-udhcpc-script` in p7. The app-layer scripts
also passed `sh -n` after extraction from the image.
