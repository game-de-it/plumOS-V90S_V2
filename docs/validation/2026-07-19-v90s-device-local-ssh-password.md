# V90S device-local SSH password

Date: 2026-07-19

## Goal

Change the running V90S root SSH password without embedding a plaintext
password or reusable password hash in git, the read-only system SquashFS, the
FAT32 user partition, or release artifacts.

## Design

`plumos-ssh-password set` reads one password line from standard input and uses
the plumOS BusyBox `cryptpw` applet to create a salted SHA-512 shadow entry.
Only the resulting device-specific shadow file is stored at:

```text
/mnt/plumos/config/ssh/shadow
```

`/mnt/plumos` is p3 `PLUMOS_SYS`, formatted as ext4. The helper bind mounts
that file over the read-only SquashFS `/etc/shadow`. Both the app-layer
bootstrap and `ssh/start-ssh.sh` reapply the bind mount when the corresponding
startup path runs. Normal app-layer updates do not include the generated
`config/ssh/shadow` file.

## Build and deployment

The following completed successfully:

```text
sh -n package/network-services/plumos/bin/plumos-ssh-password
sh -n package/network-services/plumos/ssh/start-ssh.sh
sh -n scripts/plumos-app-layer-bootstrap.sh
git diff --check
scripts/docker-build.sh network-services
scripts/docker-build.sh app-layer --strict
scripts/deploy-app-layer-adb.sh
scripts/docker-build.sh system-rootfs
```

The verified differential deployment changed 14 app-layer files in one chunk
and restarted exactly one frontend process.

The generated SquashFS was inspected inside the toolchain container. Its
`usr/sbin/plumos-app-layer-bootstrap` matched the tracked bootstrap byte for
byte. Host and device hashes also matched for both deployed app-layer files:

```text
16159fc940aba1d538e7f3d61776783af9137579c28ca49ccf840021416c5e01  bin/plumos-ssh-password
28d93da3efbf89fc53cff0842a2321754cdaf96f91880ae4caf9eb2d17482fd4  ssh/start-ssh.sh
```

## Real-device validation

The requested password was set through ADB without recording its value or hash
in this document. Runtime state reported:

```text
ssh_password=configured
shadow=bound
storage=/mnt/plumos/config/ssh/shadow
/dev/mmcblk0p3 /etc/shadow ext4 rw,noatime,data=ordered
```

A password-only SSH test to `root@192.0.2.120` succeeded with the new
password and returned UID 0. The previous password was rejected with
`Permission denied`.

For startup-path validation, `/etc/shadow` was unmounted and the packaged
`ssh/start-ssh.sh` was run again while the existing SSH listener remained
active. The device-local shadow returned to `shadow=bound`, and a second
password-only SSH login succeeded. The frontend remained alive throughout the
password and startup-path checks.
