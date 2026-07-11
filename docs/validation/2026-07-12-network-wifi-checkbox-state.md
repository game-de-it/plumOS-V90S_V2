# V90S Network Settings Wi-Fi checkbox validation

## Goal

Verify that `Network Settings -> Wi-Fi` actually controls the USB Wi-Fi runtime
from the frontend.

## Initial State

ADB was used as the command path so SSH/Wi-Fi could be safely interrupted.

The live V90S was connected through the USB Wi-Fi dongle:

```text
wifi=on
iface=wlan0
ip=192.0.2.120
dongle=present
wpa_supplicant=running
```

The frontend Network Settings screen showed:

```text
1 Wi-Fi true
2 Connect Wi-Fi
3 NW Service
4 INFORMATION
```

## Finding

The first frontend OFF test did stop Wi-Fi, but the checkbox did not persist:

```text
result=stopped
status: read-only: Wi-Fi
wifi=off
iface=wlan0
ip=none
wpa_supplicant=stopped
```

The reason was that V90S did not ship the MMF-style system settings file:

```text
/mnt/plumos/config/system/settings.json: missing
```

`plumos-controller-ui-fbdev` saves `wifi_enabled` to
`/mnt/plumos/config/system/settings.json`. Without that file, the backend
runtime command could run, but the checkbox value fell back to the default
`true` when the screen was reopened.

## Fix

Added:

```text
package/frontend-v90s/plumos/config/system/settings.json
```

The file includes the MMF-compatible `wifi_enabled` key plus the V90S frontend
system defaults:

```json
{
  "version": 1,
  "wifi_enabled": true,
  "volume": 14,
  "brightness": 10,
  "lumination": 5,
  "contrast": 10,
  "hue": 10,
  "saturation": 10,
  "language": "en.lang",
  "timezone": "JST-9"
}
```

This file is now present in:

```text
output/frontend/v90s/plumos/config/system/settings.json
output/app-layer/v90s/config/system/settings.json
/mnt/plumos/config/system/settings.json
```

All three copies used during validation had the same hash:

```text
59edec8e991bff500e80dc896136dfcfefcf393499bf9474e446db23ca5db82b
```

## Live OFF Validation

Using the frontend text action path:

```text
START -> Network Settings -> Wi-Fi -> A
```

Result:

```text
result=stopped
1 Wi-Fi false
status: Wi-Fi off; saved
```

Runtime state:

```text
wifi=off
iface=wlan0
ip=none
dongle=present
wpa_supplicant=stopped
```

Saved state:

```text
"wifi_enabled": false
```

## Live ON Validation

Using the same frontend path again:

```text
START -> Network Settings -> Wi-Fi -> A
```

Result:

```text
1 Wi-Fi true
status: Starting Wi-Fi
status: Wi-Fi connected IP=192.0.2.120
```

Runtime state:

```text
wifi=on
iface=wlan0
ip=192.0.2.120
dongle=present
wpa_supplicant=running
```

Saved state:

```text
"wifi_enabled": true
```

## Build Validation

Validated:

```text
./scripts/docker-build.sh frontend
./scripts/docker-build.sh app-layer
```

The frontend rebuild emitted only the existing `plumos_text_ui.c` truncation
warnings unrelated to this settings-file change.

## Remaining Boot-Time Gap

The live runtime checkbox now works. Boot-time Wi-Fi enable/disable is still not
fully owned by the app-layer setting because the current V90S rootfs still
starts the legacy development hook:

```text
/usr/local/sbin/v90s-network-ssh-init
```

That hook starts Wi-Fi from the rootfs side and does not yet consult
`/mnt/plumos/config/system/settings.json`. This is the same open migration item
tracked in `TODO.md`: move the remaining rootfs-level Wi-Fi/SSH bring-up into
the plumOS app-layer network control path, or make the rootfs hook honor
`wifi_enabled=false` before starting Wi-Fi.
