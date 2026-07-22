# Network and USB Connections

The V90S has no built-in Wi-Fi. Connect a supported USB Wi-Fi adapter to the
OTG port. If you use a USB hub, use a compatible powered model.

## Wi-Fi

1. Connect the USB Wi-Fi adapter.
2. Open `START -> Network Settings`.
3. Turn Wi-Fi on.
4. Open `Connect Wi-Fi`, scan, and select the SSID.
5. Enter the password with the displayed keyboard and confirm.

The settings are saved after the connection succeeds. When automatic time is
enabled in Time Settings, the clock is also set after Wi-Fi connects. If the
adapter does not reconnect, insert it again and turn Wi-Fi off and on.

## Network Services

Open `START -> Network Settings -> NW Service`. Enabling a checkbox starts that
service and also enables it for later boots.

Replace `V90S_IP` below with the IP address shown in
`Network Settings -> Information`, for example `192.168.1.120`.

| Service | Connection |
| --- | --- |
| SSH | `ssh root@V90S_IP` on port 22 |
| SFTP | Same address, account, and port as SSH |
| FTP | `ftp://V90S_IP` on port 21; writable anonymous access |
| Samba | `smb://V90S_IP/SDCARD`; user `plumos`, password `plumos` |
| ADB | Local USB development connection with `adb shell` |

The SSH password can be changed. Turn off services that are not needed. ADB is
for development and troubleshooting; use it only with a computer you control.

## USB Disk Mode

USB Disk Mode shows `PLUMOS` on SD1 to a computer like a USB drive. You can copy
large ROMs and update files directly to it.

1. Stop games and file transfers.
2. Connect the V90S USB port to the computer.
3. Enable `USB Disk Mode` in NW Service.
4. Copy files to the `PLUMOS` drive shown on the computer.
5. Eject the drive safely in Windows or macOS.
6. Turn off USB Disk Mode or disconnect the cable. Wait until `PLUMOS` is
   available on the V90S again.

While `PLUMOS` is shown on the computer, the V90S cannot access ROMs or update
files on it. ADB and USB Disk Mode cannot be used at the same time.
