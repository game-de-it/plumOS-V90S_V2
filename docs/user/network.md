# Network and USB Connections

The V90S has no built-in Wi-Fi. Network access requires a supported USB Wi-Fi
adapter connected to the OTG port, directly or through a compatible powered hub.

## Wi-Fi

1. Connect the USB Wi-Fi adapter.
2. Open `START -> Network Settings`.
3. Turn Wi-Fi on.
4. Open `Connect Wi-Fi`, scan, and select the SSID.
5. Enter the password with the displayed keyboard and confirm.

The configuration is saved only after an IP address is acquired. Automatic time
synchronization runs after Wi-Fi connects when enabled in Time Settings. If the
adapter is disconnected, reconnect it and toggle Wi-Fi off and on.

## Network Services

Open `START -> Network Settings -> NW Service`. Enabling a checkbox starts that
service and also enables it for later boots.

| Service | Connection |
| --- | --- |
| SSH | `ssh root@V90S_IP` on port 22 |
| SFTP | Same address, account, and port as SSH |
| FTP | `ftp://V90S_IP` on port 21; writable anonymous access |
| Samba | `smb://V90S_IP/SDCARD`; user `plumos`, password `plumos` |
| ADB | Local USB development connection with `adb shell` |

The SSH password is device-local and may be changed by an administrator. Turn
off services that are not needed, especially ADB, which is intended for a
trusted local USB host.

## USB Disk Mode

USB Disk Mode exposes the complete SD1 p4 `PLUMOS` FAT32 volume as writable USB
storage. It can therefore transfer large ROMs and update archives without a
small staging-volume limit.

1. Stop games and file transfers.
2. Connect the V90S USB port to the computer.
3. Enable `USB Disk Mode` in NW Service.
4. Copy files to the mounted `PLUMOS` drive.
5. Eject the drive safely in Windows or macOS.
6. Leave USB Disk Mode or disconnect the cable and wait for plumOS to check and
   remount the volume.

The user volume is unavailable to the frontend and network file services while
the computer owns it. ADB and USB Disk Mode are mutually exclusive.
