# 2026-07-15 Release Network Services Fix

## Trigger

The user enabled every item in the frontend NW Service screen after the
release Wi-Fi repair and requested a live protocol check.

Persisted state initially contained:

```text
adb_enabled=1
ftp_enabled=1
sftp_enabled=1
samba_enabled=1
ssh_enabled=1
```

FTP and Samba were listening, but SSH and SFTP were stopped. The SSH log showed
that `/usr/sbin/sshd` was missing from the release-system rootfs.

## Fix

The release-system package set now includes `openssh-server`. The app-layer
SSH launcher also forces `/run/sshd` to root ownership and mode `0755` before
starting OpenSSH. This is required because a launch from the frontend may
inherit `umask 000`; OpenSSH correctly rejects a world-writable privilege
separation directory.

Release images still do not embed a root password, client key, Wi-Fi secret,
or other device credential. The live SFTP protocol check used the existing
development credential only in the current writable overlay.

## Live Validation

macOS performed an upload, byte-for-byte readback, and delete through each
file-transfer protocol:

```text
ftp_roundtrip=ok
sftp_roundtrip=ok
samba_roundtrip=ok
```

Final runtime state:

```text
ssh   state=running enabled=1
ftp   state=running enabled=1
sftp  state=running enabled=1
samba state=running enabled=1
adb   state=running enabled=1

21/tcp  FTP
22/tcp  SSH/SFTP
445/tcp Samba

wifi=on
ip=192.0.2.120
```

All temporary protocol-test files were removed from the Mac and V90S.

## Image

```text
image: output/images/plumos-v90s-system-squashfs-20260715-5.img
image sha256: f836b4a34d804fbb00ff6f2ddf5dba11527ee8d80908ee96328a327dcc1b65de
p5 sha256: 7225ea9568a50904714fd9634ac28d2b3bd5f117042b68749644fb7ffc1f71e3
```

Host extraction verified `sshd`, `ssh-keygen`, and `wpa_supplicant` in p5.
The p7 `start-ssh.sh` passed `sh -n` and contained the explicit `/run/sshd`
ownership and mode setup.
