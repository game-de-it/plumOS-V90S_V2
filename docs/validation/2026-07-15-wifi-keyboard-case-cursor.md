# Wi-Fi keyboard case and cursor validation

Date: 2026-07-15

## Problem

The V90S `Network Settings -> Connect Wi-Fi` screen rendered every ASCII
letter as uppercase. The selected password-keyboard character also had no
visible highlight, so case-sensitive SSIDs and passwords were difficult to
enter reliably.

## Cause

The controller already kept the exact lower- or uppercase character selected
from the Wi-Fi keyboard. The V90S fbdev renderer caused the visual mismatch:

- its small built-in ASCII font mapped lowercase letters to uppercase before
  drawing;
- its generic menu renderer discarded `wifi_keyboard_cursor=` and
  `wifi_password=` metadata that the controller emits for capable renderers.

No Wi-Fi credential or connection logic was changing case.

## Fix

The V90S fbdev renderer now follows the existing MMF/A30 keyboard contract:

- Connect Wi-Fi text uses the FreeType path so SSID and password case is
  preserved;
- the password keyboard parses `wifi_keyboard_cursor=row,col`;
- only the selected character token receives a contrasting foreground and
  background;
- the password field is drawn separately from the generic footer and preserves
  the entered case.

The rest of the generic frontend renderer and the Wi-Fi backend are unchanged.

## Build and deployment

Both commands completed successfully:

```text
./scripts/docker-build.sh frontend
./scripts/docker-build.sh app-layer
```

The frontend was deployed over ADB to device
`plumos-v90s-5e66cf2c`. It was replaced through a temporary path, stopped with
`plumos-frontend-stop`, and restarted through `plumos-frontend-launch`.

```text
d779b04f5da11717a85f402ea8b2c758956cedbd4b00828f8057baf248e8387b  /mnt/plumos/bin/plumos-controller-ui-fbdev
d779b04f5da11717a85f402ea8b2c758956cedbd4b00828f8057baf248e8387b  /proc/8611/exe
frontend process count: 1
```

## Real-device framebuffer proof

A scripted frontend run opened the password editor without issuing CONNECT.
Both 640x480 pages of the 640x960 framebuffer were captured.

The captures proved:

- the SSID list displays `example-wifi-1`, `example-wifi-2`, and `example-wifi-3` with their
  original lowercase letters;
- the lowercase keyboard displays `qwertyuiop`, `asdfghjkl`, and `zxcvbnm`;
- the selected character is visibly highlighted;
- entering lowercase `q`, toggling SHIFT, and entering uppercase `Q` displays
  `Password: qQ`;
- after validation, the normal frontend was restored as exactly one process.

Local captures are stored under the ignored validation output directory:

```text
output/validation/wifi-keyboard-case-cursor/page0.png
output/validation/wifi-keyboard-case-cursor/page1.png
output/validation/wifi-keyboard-case-cursor/password-qQ.png
```
