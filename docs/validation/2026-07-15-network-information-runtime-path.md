# V90S Network Information Runtime Path

Date: 2026-07-15

## Symptom

The V90S was connected over USB Wi-Fi, but `Network Settings -> INFORMATION`
showed no connection details or IPv4 address.

Live diagnostics proved the network itself was healthy:

```text
interface:  wlan0
SSID:       example-wifi-1
WPA state:  COMPLETED
IPv4:       192.0.2.120
gateway:    192.0.2.1
```

## Cause

The release network controller had moved transient ownership to:

```text
/run/plumos/network-control/wpa_status.txt
```

That matches the distribution runtime policy, but the frontend still read the
older A30/MMF-compatible path `/tmp/wpa_status.txt`. Running
`plumos-network-control --wifi status` refreshed the correct release file, then
the frontend looked at a different and nonexistent file.

## Fix

- default the V90S frontend to
  `/run/plumos/network-control/wpa_status.txt`;
- honor `PLUMOS_WPA_STATUS` first and retain `PLUMOS_A30_WPA_STATUS` only as an
  explicit legacy override;
- pass the selected status path back to `plumos-network-control` during the
  INFORMATION refresh;
- clear previously loaded Wi-Fi values before reading the refreshed file, so a
  failed refresh cannot leave stale connection details on screen.

## Live Validation

The updated frontend was deployed over ADB and the real frontend action path
opened INFORMATION with:

```text
start,down,down,a,down,down,down,a
```

The text renderer and visible fbdev page agreed:

```text
Connection  Connected
IP Address  192.0.2.120
Signal      -50 dBm
Link Speed  434 Mbps
Frequency   5220 MHz
SSH         Running / Auto
FTP         Running / Auto
SFTP        Running / Auto
Samba       Stopped / Auto
ADB         Running / Auto
```

`Stopped / Auto` is deliberate: it distinguishes a saved boot-enabled switch
from a currently stopped service process.

The visible framebuffer capture is retained locally at:

```text
output/validation/2026-07-15-network-information-runtime-path/page1.png
```

Deployed frontend hash:

```text
babd87bb95fbb488432bfe960faae876105c32da70b001ecfc614af0f6bbc891
```

After validation, exactly one normal frontend process was restored.
