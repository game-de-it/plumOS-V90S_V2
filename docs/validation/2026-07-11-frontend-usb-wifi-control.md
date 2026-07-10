# V90S Frontend USB Wi-Fi Control

Date: 2026-07-11

## Purpose

Make the frontend Wi-Fi settings functional through a plumOS-owned backend while
preserving the V90S hardware assumption that Wi-Fi is provided by an external
USB dongle.

## Implementation

- Added app-layer controller:
  `package/network-services/plumos/bin/plumos-network-control`
- The frontend already calls:
  `/mnt/plumos/bin/plumos-network-control`
- Supported frontend actions:
  - `--scan`
  - `--connect-file FILE`
  - `--wifi on`
  - `--wifi off`
  - `--wifi status`
- USB Wi-Fi detection reuses the V90S module-alias strategy from the development
  network/SSH init path:
  - `rtl8192cu`
  - `rtl8xxxu`
  - `8192eu`
  - `8723bu`
  - `8812au`
  - `8821cu`
  - `88x2bu`
  - `8188eu`
- Missing dongle or missing Wi-Fi interface returns a bounded failure stage such
  as `no_usb_wifi_dongle`, `no_supported_usb_wifi_driver`, or
  `no_wifi_interface`.
- Runtime status is written for the frontend at `/tmp/wpa_status.txt` and also
  mirrored under `/mnt/plumos/config/network/wpa_status.txt`.
- `plumos-frontend-stop` now looks for both `plumos-controller-ui-fbdev` and
  `plumos-controller-ui-v90s` so frontend restarts remain scoped to frontend
  processes and do not touch SSH.

## Commands

```sh
sh -n package/network-services/plumos/bin/plumos-network-control
sh -n package/network-services/plumos/bin/plumos-network-services
bash -n docker/plumos-v90s-toolchain/scripts/build-network-services.sh

./scripts/docker-build.sh network-services
./scripts/docker-build.sh frontend
./scripts/docker-build.sh app-layer --strict

(cd output/network-services/v90s && sha256sum -c checksums.sha256)
(cd output/app-layer/v90s && sha256sum -c checksums.sha256)
```

## Host Bounded-Failure Checks

These were run on the host with an empty temporary `PLUMOS_ROOT`, which simulates
no V90S USB Wi-Fi dongle/interface being available to the script.

```text
status rc=2
wifi=off
iface=none
ip=none
dongle=missing
wpa_supplicant=stopped
wpa_state=NO_USB_WIFI_DONGLE
```

```text
scan rc=1 elapsed=1
result=failed
stage=no_usb_wifi_dongle
```

```text
connect rc=1 elapsed=1
result=failed
stage=no_usb_wifi_dongle
```

The generated app-layer copy was also checked directly:

```text
result=failed
stage=no_usb_wifi_dongle
app-layer scan rc=1
```

## Output Hashes

```text
e7b2e63031bd8b04cbb6f54b4d28f2373f3fd576bba05e3d78bb96b5a00b3a19  output/network-services/v90s/plumos/bin/plumos-network-control
e7b2e63031bd8b04cbb6f54b4d28f2373f3fd576bba05e3d78bb96b5a00b3a19  output/app-layer/v90s/bin/plumos-network-control
9d6c08f57f6426047ebc85ba0927a7f3d80f7e4edb067148692d904ae15f9e98  output/app-layer/v90s/bin/plumos-controller-ui-fbdev
ab0777e494dcabf1a8a65da4b329ab90e59d6c80ceae66f3088a0997725ebf98  output/app-layer/v90s/bin/plumos-frontend-stop
3438ce8598374979fb1d42e4ff673cb512a1d567099af76f5f80479986223b10  output/app-layer/v90s/checksums.sha256
28639f16f7ba7ca6ea923aa33a11d452c6502da576f07cd08b63afb4921480fb  output/app-layer/v90s/manifest.json
```

## Live V90S Deployment Check

Target:

```text
root@192.0.2.120
```

The following app-layer files were copied to `/mnt/plumos` first:

```text
bin/plumos-network-control
bin/plumos-controller-ui
bin/plumos-controller-ui-fbdev
bin/plumos-controller-ui-v90s
bin/plumos-frontend-stop
share/doc/network-services/
licenses/network-services-manifest.txt
licenses/frontend-manifest.txt
```

Remote hashes after the targeted copy:

```text
e7b2e63031bd8b04cbb6f54b4d28f2373f3fd576bba05e3d78bb96b5a00b3a19  /mnt/plumos/bin/plumos-network-control
9d6c08f57f6426047ebc85ba0927a7f3d80f7e4edb067148692d904ae15f9e98  /mnt/plumos/bin/plumos-controller-ui-fbdev
ab0777e494dcabf1a8a65da4b329ab90e59d6c80ceae66f3088a0997725ebf98  /mnt/plumos/bin/plumos-frontend-stop
```

An attempted full app-layer sync was stopped by the current p7 size:

```text
/dev/mmcblk0p7   55M   54M     0 100% /mnt/plumos
tar: ... Cannot open: No space left on device
```

The oversized partial extraction was cleaned up and the critical FE/RA/Wi-Fi
files were recopied. The live device now uses a live-partial metadata file that
matches the files actually present on this 55MB p7:

```text
live_partial_sha_rc=0
/dev/mmcblk0p7   55M   40M   15M  74% /mnt/plumos
d4dfb044a69be697766f0f6b63d936c8a7d0a8af8ff250f9b52c394c73f08a94  /mnt/plumos/checksums.sha256
3a3d676d9f3ce8e08a3b22625d34b38b8f8007ec953ded7388ae68c507261171  /mnt/plumos/manifest.json
```

Runtime status:

```text
wifi=on
iface=wlan0
ip=192.0.2.120
dongle=present
wpa_supplicant=running
wpa_state=COMPLETED
ip_address=192.0.2.120
RSSI=-50
LINKSPEED=72
FREQUENCY=2472
```

Runtime scan:

```text
network secured -62 example-wifi-2
```

Frontend restart check:

```text
plumos-frontend-stop: pid=2852 cmd=/mnt/plumos/bin/plumos-controller-ui-fbdev --renderer fbdev
```

Final live hashes:

```text
e7b2e63031bd8b04cbb6f54b4d28f2373f3fd576bba05e3d78bb96b5a00b3a19  /mnt/plumos/bin/plumos-network-control
9d6c08f57f6426047ebc85ba0927a7f3d80f7e4edb067148692d904ae15f9e98  /mnt/plumos/bin/plumos-controller-ui-fbdev
b37b9afc692453407d3453d88c72a6f914550cd096abfde3f3204a77178cb459  /mnt/plumos/bin/retroarch
d4dfb044a69be697766f0f6b63d936c8a7d0a8af8ff250f9b52c394c73f08a94  /mnt/plumos/checksums.sha256
3a3d676d9f3ce8e08a3b22625d34b38b8f8007ec953ded7388ae68c507261171  /mnt/plumos/manifest.json
```

## Notes

- Direct backend validation succeeded on the live V90S. The remaining user-facing
  check is operating the FE Wi-Fi screen itself and verifying that credentials
  save from the menu path.
- The current 55MB p7 is too small for the full 146MB generated app-layer. A
  future SD image needs a larger FAT32 app-layer partition or a smaller
  network/userland packaging split before full `checksums.sha256` metadata can be
  deployed unchanged.
- `frontend` rebuilt with existing `plumos_text_ui.c` truncation warnings only.
