# V90S NW Service checkbox and runtime state validation

## Goal

Confirm that the frontend NW Service checkboxes match the saved service enable
state, and that each service controller action also starts or stops the live
process as expected.

## Frontend Contract

The V90S frontend follows the MMF network-service contract:

- `start SERVICE` writes `SERVICE_enabled=1` and starts the service now.
- `stop SERVICE` writes `SERVICE_enabled=0` and stops the service now.
- `start-enabled` runs at boot and starts only services with `enabled=1`.
- The checkbox value is the saved `enabled=` value returned by
  `plumos-network-services status`.
- The status summary must still reflect the real runtime process state.

## Initial Finding

The frontend showed SSH as OFF. The saved config agreed:

```text
ssh_enabled=0
sftp_enabled=0
adb_enabled=1
```

However, the service status command incorrectly reported SSH as running:

```text
service=ssh
state=running
summary=SSH running; pid file will be adopted on start
enabled=0
```

There was no actual SSH daemon and no TCP listener:

```text
ps: only /mnt/plumos/adb/bin/adbd.bin matched network service processes
listeners: no :21, :22, :139, or :445 TCP listener
```

The mismatch was a status false positive. The old process-name fallback scanned
process text too loosely and could match transient command text rather than a
real `sshd` or `dropbear` process.

## Fix

`package/network-services/plumos/bin/plumos-network-services` now validates
service state more strictly:

- PID files are accepted only when the live PID matches the expected command.
- fallback process discovery scans `/proc/[0-9]*/comm` and
  `/proc/[0-9]*/cmdline`.
- fallback matches exact command names or command basenames only.
- FTP, Samba, SSH, and SFTP status paths all use the stricter checks.

## Live Device Result

After deploying the fixed script to `/mnt/plumos/bin/plumos-network-services`:

```text
service=ssh   state=stopped enabled=0 summary=SSH stopped
service=ftp   state=stopped enabled=0 summary=FTP stopped
service=sftp  state=stopped enabled=0 summary=SFTP disabled
service=samba state=stopped enabled=0 summary=Samba stopped
service=adb   state=running enabled=1 summary=ADB over USB FunctionFS
```

The frontend text-rendered NW Service screen matched the saved state:

```text
1 SSH    false
2 FTP    false
3 SFTP   false
4 Samba  false
5 ADB    true
6 USB Disk Mode
```

Final live process state:

```text
adbd.bin is running
no sshd/dropbear process
no tcpsvd/ftpd process
no smbd/nmbd process
no :21, :22, :139, or :445 TCP listener
```

## Toggle Validation

SSH:

```text
start ssh -> state=running enabled=1
stop ssh  -> state=stopped enabled=0
```

FTP:

```text
start ftp -> state=running enabled=1
stop ftp  -> state=stopped enabled=0
```

Samba:

```text
start samba -> state=running enabled=1
stop samba  -> state=stopped enabled=0
```

SFTP:

```text
start sftp -> sftp state=running enabled=1
start sftp -> ssh  state=running enabled=1
stop sftp  -> sftp state=stopped enabled=0
stop ssh   -> ssh  state=stopped enabled=0
```

ADB was kept running because it was the active command channel. Its current
state is:

```text
service=adb
state=running
enabled=1
```

## Build Validation

Validated:

```text
sh -n package/network-services/plumos/bin/plumos-network-services
git diff --check
./scripts/docker-build.sh network-services
./scripts/docker-build.sh app-layer
```

The package source, network-services output, app-layer output, and live device
copy all share this script hash:

```text
8c7d25e998680439701034bb00bb101192c4381c86e37e1a603774ece8ae980e
```
