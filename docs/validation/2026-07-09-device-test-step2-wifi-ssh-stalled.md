# Device Test: Step 2 Wi-Fi/SSHD Image Stalled Before SSHD

Date: 2026-07-09

## Image

- `output/images/plumos-v90s-armbian-step2-20260709-6-wifi-ssh.img`
- sha256: `70cbf6e8edf837ef5d9d3e08a5ed632ba643fce094f08090feeb6276ea874bbc`

## User Report

- Image was written by the user.
- V90S was booted.
- SD card was returned to macOS.
- Additional clarification: this V90S setup must use a USB Wi-Fi dongle, not internal Wi-Fi.

## FAT Logs

FAT log directory:

```text
/Volumes/KNULLI/plumos-logs/
```

Files present:

```text
plumos-v90s-debian-init.log
plumos-v90s-diag.log
plumos-v90s-network-ssh.log
plumos-v90s-pvr-probe.log
session.txt
```

`plumos-v90s-debian-init.log` reached network init:

```text
debian-init: starting PowerVR probe
debian-init: PowerVR probe exited rc=0
debian-init: starting network/SSH init
```

`plumos-v90s-network-ssh.log` reached the network script and module inventory:

```text
network-ssh: entered

===== network-release =====
name=plumOS V90S network SSH payload
wifi_configured=yes
ssh_authorized_keys=yes
ssh_password_auth=yes
===== network-release rc=0 =====

===== wifi-module-files =====
/lib/modules/4.9.191/extra/8192eu.ko
/lib/modules/4.9.191/extra/8723bu.ko
/lib/modules/4.9.191/extra/8812au.ko
/lib/modules/4.9.191/extra/8821cu.ko
/lib/modules/4.9.191/extra/88x2bu.ko
/lib/modules/4.9.191/rtl8192c-common.ko
/lib/modules/4.9.191/rtl8192cu.ko
/lib/modules/4.9.191/rtl8xxxu.ko
/lib/modules/4.9.191/rtl_usb.ko
/lib/modules/4.9.191/rtlwifi.ko
```

No `plumos-v90s-retroarch*.log` files were present from this run. The network init did not return to the Debian init path, so RetroArch was not reached.

## Interpretation

The previous image treated Wi-Fi as a broad device bring-up problem and ran Wi-Fi initialization before starting sshd. That made a network probe failure block both SSH and RetroArch.

KNULLI's available module set includes USB Wi-Fi candidates for common Realtek dongles:

- standard A133 modules: `rtl8192cu`, `rtl8xxxu`, `rtlwifi`, `rtl_usb`, `rtl8192c-common`
- V90S overlay modules: `8192eu`, `8723bu`, `8812au`, `8821cu`, `88x2bu`

The next image should:

- start sshd before Wi-Fi probing
- include `usbutils` for `lsusb`
- log USB device IDs from `/sys/bus/usb/devices`
- keep the internal/xradio path out of the first USB dongle attempt
- load only the module candidates matching the attached USB device aliases
- leave logs on FAT even when Wi-Fi does not connect
