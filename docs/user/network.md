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

### Supported Wi-Fi Drivers

The current release includes these Realtek USB Wi-Fi drivers:

- `8192eu`
- `8723bu`
- `8812au`
- `8821cu`
- `88x2bu`
- `rtl8192cu`
- `rtl8xxxu`

The adapter verified on real hardware uses USB ID `0bda:c820` with the
`8821cu` driver. Products sold under the same name may use a different USB ID
or chipset in another hardware revision. A similar product name alone does not
confirm compatibility. If an adapter does not work, check its USB ID on a
computer and include that ID in the problem report.

## Network Services

Open `START -> Network Settings -> NW Service`. Enabling a checkbox starts that
service and also enables it for later boots.

Replace `V90S_IP` below with the IP address shown in
`Network Settings -> Information`, for example `192.168.1.120`.

| Service | Address | User | Initial password |
| --- | --- | --- | --- |
| SSH | `ssh root@V90S_IP` (port 22) | `root` | None; set one with the steps below before the first password login |
| SFTP | `sftp root@V90S_IP` (port 22) | `root` | Same as SSH |
| FTP | `ftp://V90S_IP` (port 21) | Anonymous; enter `anonymous` if prompted | None; if the client rejects an empty field, enter any text |
| Samba | `smb://V90S_IP/SDCARD` | `plumos` | `plumos` |
| ADB | Run `adb shell` after connecting USB | Not required | Not required |

SSH and SFTP share one device-local password. Release images do not contain an
initial SSH password. Set one before the first password login:

1. Connect the V90S to the computer over USB and enable ADB in NW Service.
2. Run `adb shell` in a terminal on the computer.
3. Run `/mnt/plumos/bin/plumos-ssh-password set`.
4. Enter the new password as one line and press Enter.
5. Run `exit`, then enable SSH or SFTP.

The password is stored in the Linux system area on SD1 and persists across
reboots. Public-key authentication is also available. FTP allows anonymous
writes, and the initial Samba password is public information. Use these
services only on a trusted home network and turn off services that are not
needed. ADB is for development and troubleshooting; use it only with a
computer you control.

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
