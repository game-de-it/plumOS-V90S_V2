# V90S Live Network Services Validation

Date: 2026-07-11

## Trigger

The user enabled FTP, SFTP, and Samba from the frontend and asked whether they
were actually working on the live V90S.

Device:

```text
root@192.0.2.120
```

## Initial Status

The frontend had persisted all network services as enabled:

```text
ftp_enabled=1
sftp_enabled=1
ssh_enabled=1
samba_enabled=1
```

Runtime status before the Samba fix:

```text
ssh:   running, listening on 22
sftp:  running through SSH
ftp:   running, listening on 21
samba: stopped, enabled but not listening on 445
```

Mac-side port check:

```text
21  succeeded
22  succeeded
139 refused
445 refused
```

FTP was already functional. `curl -l ftp://192.0.2.120/` listed
`/mnt/plumos`.

SFTP was already functional. A password-authenticated `sftp root@192.0.2.120`
session connected and accepted commands.

## Samba Failure

Manual `smbd` startup showed the blocker:

```text
tdb(/mnt/plumos/config/network/samba-private/secrets.tdb): tdb_transaction: fsync failed
PANIC: could not start commit secrets db
```

Cause:

- The `SDCARD` share can live on FAT32.
- Samba's private TDB state cannot safely live on the FAT32 app layer.
- The previous config used `/mnt/plumos/config/network/samba-private` as
  `private dir`, which made `secrets.tdb` fail during startup.

## Fix

Changed `package/network-services/plumos/bin/plumos-network-services` so Samba
runtime-private state lives in tmpfs:

```text
SAMBA_RUNTIME_DIR=/tmp/plumos-samba
SAMBA_PRIVATE_DIR=/tmp/plumos-samba/private
SAMBA_LOG_DIR=/tmp/plumos-samba/log
```

Generated `smb.conf` now points these Samba-internal paths at `/tmp`:

```text
passdb backend = smbpasswd:/tmp/plumos-samba/private/smbpasswd
username map = /tmp/plumos-samba/private/smbusers
lock directory = /tmp/plumos-samba/lock
state directory = /tmp/plumos-samba/state
cache directory = /tmp/plumos-samba/cache
ncalrpc dir = /tmp/plumos-samba/ncalrpc
private dir = /tmp/plumos-samba/private
log file = /tmp/plumos-samba/log/samba-%m.log
```

The shared user data path remains:

```text
[SDCARD]
path = /mnt/plumos
```

## Live Deploy

Deployed fixed script:

```text
/mnt/plumos/bin/plumos-network-services
sha256=55b3588db9494ade648ff03eaf7e034d4bb34d8b900d16a4f363190e95ecdea2
```

Previous script was preserved on device:

```text
/mnt/plumos/bin/plumos-network-services.bak-20260608-055137
sha256=2091976626ecf4fa057f2adb94219e8a1d12199b74ab9d3c52a3737400457d85
```

Restarted only Samba:

```sh
/mnt/plumos/bin/plumos-network-services restart samba
```

Result:

```text
service=samba
state=running
summary=Samba share SDCARD, max 20
enabled=1
share_dir=/mnt/plumos
```

Process/socket proof:

```text
smbd.bin -D -s /mnt/plumos/config/network/smb.conf
LISTEN 0.0.0.0:445
```

## Mac-side Runtime Tests

Port checks:

```text
21  succeeded
22  succeeded
139 refused
445 succeeded
```

FTP read test:

```sh
curl --connect-timeout 5 --max-time 10 --disable-epsv -l ftp://192.0.2.120/
```

Result: listed `/mnt/plumos` contents.

SFTP read/write test:

```text
sftp root@192.0.2.120
password: linux
put /tmp/plumos-v90s-sftp-check.txt /mnt/plumos/Logs/codex-sftp-check.txt
```

Result: upload succeeded.

SMB direct mount/write test:

```sh
mount_smbfs //plumos:plumos@192.0.2.120/SDCARD /tmp/plumos-v90s-smb-test
cp /tmp/plumos-v90s-smb-check.txt /tmp/plumos-v90s-smb-test/Logs/codex-smb-check.txt
umount /tmp/plumos-v90s-smb-test
```

Result: mount and upload succeeded.

The temporary files were verified on the device and then removed:

```text
/mnt/plumos/Logs/codex-ftp-check.txt
/mnt/plumos/Logs/codex-sftp-check.txt
/mnt/plumos/Logs/codex-smb-check.txt
```

Post-cleanup service status:

```text
ssh:   running, enabled=1
sftp:  running, enabled=1
ftp:   running, enabled=1
samba: running, enabled=1
```

Post-cleanup sockets:

```text
0.0.0.0:21   busybox/tcpsvd
0.0.0.0:22   sshd
0.0.0.0:445  smbd
```

## SMB Client Note

`smbutil view //plumos:plumos@192.0.2.120` returned `Broken pipe` while
directly mounting `//plumos:plumos@192.0.2.120/SDCARD` worked. For now, use
the explicit share path:

```text
smb://192.0.2.120/SDCARD
user: plumos
pass: plumos
```

## Rebuilt Outputs

Commands:

```sh
./scripts/docker-build.sh network-services
./scripts/docker-build.sh app-layer --strict
./scripts/docker-build.sh sd-image \
  --boot0 output/device-live/raw-boot-chain/plumos-v90s-stockos-ra-20260710-2-stockos-video.img/boot0.bin \
  --boot-package output/device-live/raw-boot-chain/plumos-v90s-stockos-ra-20260710-2-stockos-video.img/boot-package.bin \
  --rootfs-squashfs output/rootfs-step2-appfat/debian-bookworm-retroarch-knulli-step2.squashfs \
  --app-layer-dir output/app-layer/v90s \
  --share-size 1024M \
  --name plumos-v90s-appfat-1g-netmenu-samba-20260711-1.img
```

Generated image:

```text
output/images/plumos-v90s-appfat-1g-netmenu-samba-20260711-1.img
sha256=9a4a2fde4995ef26c77007f928df5261edaf1fedad9df4417115e71e1dbfda11
```

Image manifest highlights:

```text
share_size=1024M
app_layer_manifest_sha256=1ce564fcf09919bbfff7878752a082372e452e9001ba81183b42841a9345b20f
allow_knulli_boot_fallback=0
```

Direct image inspection confirmed p7 contains the fixed script:

```text
sha256=55b3588db9494ade648ff03eaf7e034d4bb34d8b900d16a4f363190e95ecdea2
SAMBA_RUNTIME_DIR=/tmp/plumos-samba
private dir = ${SAMBA_PRIVATE_DIR}
```
