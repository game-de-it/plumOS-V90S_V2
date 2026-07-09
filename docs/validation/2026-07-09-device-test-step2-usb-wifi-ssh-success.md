# Device Test: Step 2 USB Wi-Fi SSH Success

Date: 2026-07-09

## Image

- `output/images/plumos-v90s-armbian-step2-20260709-7-usb-wifi-ssh.img`
- sha256: `a340674105a9a0ef115833e78c9c84b391b31bc49226ccab943b793997150130`

## User Report

- The image was booted on the V90S with a TP-Link USB Wi-Fi dongle attached.
- The dongle LED turned on.
- The user logged in over SSH and confirmed `df` can run.
- Future work that does not require rewriting the SD card should continue over SSH.

## SSH Verification

SSH target:

```text
root@192.0.2.110
```

Kernel:

```text
Linux (none) 4.9.191 #17 SMP PREEMPT Tue May 13 18:14:09 UTC 2025 aarch64 GNU/Linux
```

IPv4 address:

```text
wlan0: 192.0.2.110/24
```

`df` over SSH:

```text
Filesystem     1K-blocks   Used Available Use% Mounted on
devtmpfs          481388      0    481388   0% /dev
/dev/mmcblk0p4     33256  24816      8440  75% /boot
/dev/mmcblk0p5    498900 452816     35600  93% /mnt/share
/dev/loop2        452608 452608         0 100% /
tmpfs             500320      4    500316   1% /run
tmpfs             500320    160    500160   1% /tmp
```

Network log highlights:

```text
usbcore: registered new interface driver rtl8821cu
network-ssh: wifi_iface=wlan0
wpa_state=COMPLETED
network-ssh: WPA completed
DHCPOFFER of 192.0.2.110 from 192.0.2.1
DHCPACK of 192.0.2.110 from 192.0.2.1
```

## Notes

DHCP did assign `192.0.2.110`, but `dhclient` also logged that it could not create `/var/lib/dhcp/dhclient.leases` because the root filesystem is read-only. A future image should point dhclient lease/pid files into `/run` to avoid that warning.

The generated `/etc/resolv.conf` still contains the build-container DNS value. Fix DNS over a runtime overlay or in the next image if live device package downloads become necessary.
