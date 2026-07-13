# V90S Network Information Runtime Validation

Date: 2026-07-14

## Scope

Validate and repair `START -> Network Settings -> INFORMATION` on the live
V90S. This screen is the deliberate full-runtime check; the parent Network
Settings and NW Service screens continue to read only persisted checkbox state
so they open immediately.

## Faults Found

- Wi-Fi information was read from the last generated WPA status file without
  first refreshing it from the current USB Wi-Fi interface.
- The raw WPA state `COMPLETED` was exposed instead of a user-facing connection
  result.
- Service `summary=` strings were used as status values. Long SSH and SFTP
  summaries did not fit the 640x480 settings row and appeared blank on the LCD.
- Those summaries described the service implementation rather than clearly
  separating live state from boot-enabled state.

## Implemented Contract

Opening INFORMATION now runs the read-only status path:

```text
plumos-network-control --wifi status
plumos-network-services status ssh
plumos-network-services status ftp
plumos-network-services status sftp
plumos-network-services status samba
plumos-network-services status adb
```

`plumos-network-control --wifi status` refreshes `/tmp/wpa_status.txt` before
the frontend reads it. `COMPLETED` is shown as `Connected` only when an IPv4
address is also present; otherwise it is shown as `No IP Address`.

Service rows use compact state values that fit the device display:

```text
Running / Auto
Running / Manual
Stopped / Auto
Stopped
Waiting for Network
Not Installed
```

`Auto` means the service is enabled in
`/mnt/plumos/config/network/services.conf`; the first word is the current
runtime state.

## Live Device Proof

The rebuilt frontend was deployed over ADB to serial
`plumos-v90s-330ad2e0`. The controller script runner used the same action path
as physical input to open the screen:

```text
start,down,down,a,down,down,down,a
```

The live values were:

```text
Connection  Connected
IP Address  192.0.2.120
Signal      -41 dBm
Link Speed  72 Mbps
Frequency   2472 MHz
SSH         Running / Auto
FTP         Running / Auto
SFTP        Running / Auto
Samba       Running / Auto
ADB         Running / Auto
```

Both pages of the 640x960 framebuffer were captured after rendering. The
visible INFORMATION page showed all ten rows without blank or clipped service
values. The normal frontend was then restarted.

Deployed frontend hash:

```text
9fde7d7e7bf4e4c8215cfac3912ae9fd130234bd6b41ea0f875b113ae36960a5  /mnt/plumos/bin/plumos-controller-ui-fbdev
```

## Build Validation

```text
git diff --check
./scripts/docker-build.sh frontend
```

Both completed successfully.
