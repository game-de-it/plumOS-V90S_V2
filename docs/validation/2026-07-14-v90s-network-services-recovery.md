# V90S network services recovery

Date: 2026-07-14

## Failure

The frontend persisted FTP, SFTP, Samba, SSH, and ADB as enabled, but the live
V90S reported FTP as `not_installed` and Samba as `stopped`. Only port 22 was
reachable over the network.

The live FAT32 app layer contained a partial app-layer manifest whose
`missing_optional` list included `userland` and `network-services`. Its `bin/`
directory no longer contained `busybox`, `tcpsvd`, or `ftpd`, so the FTP
controller could not start its runtime. Separately, `wpa_supplicant` reported
`COMPLETED` while `wlan0` had no IPv4 address and a stale DHCP client remained.
Samba then exited because it could not determine a usable interface.

Two related state-control defects were also found during protocol validation:

- SFTP status checked only for an SSH process and an app-layer wrapper, while
  the system OpenSSH configuration still used the rootfs SFTP binary.
- SSH process adoption could accept a transient authenticated child as if it
  were the listener, leaving port 22 down after a restart race.

## Corrections

- `network-services` now builds its userland dependency and bundles `busybox`,
  `tcpsvd`, and `ftpd` in the same artifact.
- Wi-Fi ON renews DHCP when WPA is associated without IPv4, then starts enabled
  services idempotently after address acquisition.
- Samba reports `waiting_network` before IPv4 is available instead of launching
  into a known failure.
- The rootfs and plumOS SSH paths use the app-layer SFTP subsystem. SFTP OFF/ON
  changes only that subsystem path and does not terminate SSH.
- SSH adoption/status checks require an actual `[listener]` process.
- App-layer manifests expose `complete`; release packaging rejects partial
  manifests or a non-empty `missing_optional` list.

## Build validation

The following checks completed successfully:

```text
sh/bash syntax checks for all changed scripts
git diff --check
./scripts/docker-build.sh network-services
sha256sum -c output/network-services/v90s/checksums.sha256
./scripts/docker-build.sh app-layer --strict
```

The strict app layer reported `complete=true`, an empty `missing_optional`, and
contained the FTP, SFTP, and Samba runtime files. A synthetic partial manifest
was rejected by `scripts/build-release.sh` with exit status 1.

## Live-device validation

ADB serial `plumos-v90s-330ad2e0` was used so Wi-Fi repair could not remove the
diagnostic path. Existing `services.conf` was hash-checked before and after the
payload copy and remained unchanged.

Wi-Fi recovered without restarting the device:

```text
iface=wlan0
ip=192.0.2.120
wpa_supplicant=running
```

All enabled services reported `running`, and the listeners were present:

```text
21/tcp   FTP
22/tcp   SSH and SFTP
445/tcp  Samba
```

macOS wrote and read back the same `network-services-final` payload through:

```text
ftp://192.0.2.120/Logs/
sftp root@192.0.2.120
smb://192.0.2.120/SDCARD
```

The SFTP toggle was also exercised. OFF made an SFTP request fail while a normal
SSH command still succeeded and the SSH listener PID stayed unchanged. ON
restored SFTP and its default working directory was `/mnt/plumos`.
