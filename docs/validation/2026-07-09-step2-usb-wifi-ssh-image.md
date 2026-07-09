# Step 2 USB Wi-Fi SSH Diagnostic Image

Date: 2026-07-09

## Output

- image: `output/images/plumos-v90s-armbian-step2-20260709-7-usb-wifi-ssh.img`
- image sha256: `a340674105a9a0ef115833e78c9c84b391b31bc49226ccab943b793997150130`
- image size: `581M`
- rootfs payload: `output/rootfs-step2-pvr-sdl2-usb-wifi-ssh/debian-bookworm-retroarch-pvr-sdl2-step2.squashfs`
- rootfs sha256: `e36763a4f39ae357b53c6fb252749da63843488da44a7373f31a7fd508c135c2`
- rootfs size: `442M`

## Purpose

The previous Wi-Fi/SSHD image stopped inside network initialization before sshd or RetroArch could run. The user clarified that the V90S setup uses a USB Wi-Fi dongle, not internal Wi-Fi.

This image keeps the Step 2 RetroArch/PowerVR/SDL2-Mali payload but changes the network path:

- start sshd before Wi-Fi probing
- include `usbutils` so `lsusb` can identify the attached dongle
- log USB device IDs from `/sys/bus/usb/devices`
- avoid the internal/xradio Wi-Fi path for this test
- preserve both standard A133 and V90S `modules.alias` files for USB driver matching
- load only USB Wi-Fi driver candidates whose aliases match the attached VID/PID

## KNULLI USB Wi-Fi Coverage

The KNULLI A133/V90S overlay used by this project contains these USB Wi-Fi candidates:

- standard A133 modules: `rtl8192cu`, `rtl8xxxu`, `rtlwifi`, `rtl_usb`, `rtl8192c-common`
- V90S overlay modules: `8192eu`, `8723bu`, `8812au`, `8821cu`, `88x2bu`

KNULLI's generic `enable_wifi_dongle` service loads `8188eu` and `rtl8192cu`. In this A133/V90S overlay snapshot, `8188eu.ko` was not present, but `8192eu.ko` was present.

## Build Notes

The Wi-Fi credentials, SSH authorized key, and root password were provided only at image build time and are intentionally not recorded in git.

Rootfs release metadata confirms network packages are included:

```text
packages=retroarch,libretro-nestopia,alsa-utils,input-utils,procps,psmisc,kmod,openssh-server,wpasupplicant,isc-dhcp-client,iproute2,rfkill,iw,usbutils,wireless-regdb,ca-certificates
power_pvr_probe=1
custom_sdl2_mali=1
```

## Host Verification

Verified inside the generated squashfs:

```text
/usr/bin/lsusb
/usr/sbin/sshd
/usr/sbin/wpa_supplicant
/usr/sbin/dhclient
/usr/local/sbin/v90s-network-ssh-init
/usr/lib/modules/4.9.191/modules.alias.standard
/usr/lib/modules/4.9.191/modules.alias.v90s
/usr/lib/modules/4.9.191/extra/8192eu.ko
/usr/lib/modules/4.9.191/extra/8723bu.ko
/usr/lib/modules/4.9.191/extra/8812au.ko
/usr/lib/modules/4.9.191/extra/8821cu.ko
/usr/lib/modules/4.9.191/extra/88x2bu.ko
/root/.ssh/authorized_keys
/etc/ssh/ssh_host_rsa_key
/etc/ssh/ssh_host_ecdsa_key
/etc/ssh/ssh_host_ed25519_key
```

Secret-safe checks passed:

```text
wpa-ssid-present
wpa-psk-present
authorized-key-present
root-password-hash-present
```

GPT layout still uses the small test partition scheme:

```text
boot-resource: 67584 sectors
userdata:      1048576 sectors
```

## Expected Device Test

Boot the image with the USB Wi-Fi dongle attached.

If Wi-Fi succeeds, FAT should contain:

```text
/plumos-logs/ssh-connect.txt
/plumos-logs/plumos-v90s-network-ssh.log
```

If SSH does not work, return the SD card and inspect:

```text
/Volumes/KNULLI/plumos-logs/plumos-v90s-network-ssh.log
```

The most important next lines are:

- `usb-devices-before-wifi`
- `usb_wifi_driver_candidates=...`
- `sshd-state`
- `net-after-module-load`
- `network-ssh: wifi_iface=...`
- `network-ssh: WPA completed`
- `net-final`
