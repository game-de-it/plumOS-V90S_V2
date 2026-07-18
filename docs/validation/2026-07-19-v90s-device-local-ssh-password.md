# V90S device-local SSH state

Date: 2026-07-19

## Goal

Change the running V90S root SSH password without embedding a plaintext
password or reusable password hash in git, the read-only system SquashFS, the
FAT32 user partition, or release artifacts.

Also provide a writable persistent root home so interactive shell history,
profile settings, and authorized keys work normally over SSH.

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

`plumos-ssh-home apply` prepares another device-local directory:

```text
/mnt/plumos/config/ssh/root
```

It copies the initial SquashFS root profile once, adds the plumOS command path
and Bash history policy, and bind mounts the directory over `/root`. History is
appended to `/root/.bash_history`; `.profile`, `.bashrc`, and `.ssh` changes are
therefore persistent without making the system SquashFS writable.

## Build and deployment

The following completed successfully:

```text
sh -n package/network-services/plumos/bin/plumos-ssh-password
sh -n package/network-services/plumos/bin/plumos-ssh-home
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
699a4eadae05fd262ebc411fa8b4576e9561c2824422646bcfef1beb392cdee6  bin/plumos-ssh-home
16159fc940aba1d538e7f3d61776783af9137579c28ca49ccf840021416c5e01  bin/plumos-ssh-password
1c6231d4da1bdfbd0c6eef0f5f8f55c1f1ea7581786d07fffaddc284bb110eda  ssh/start-ssh.sh
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

## Persistent interactive shell validation

Before the fix, a password-authenticated SSH command showed that `history` was
a Bash builtin, but the non-interactive history file was unset and writing any
file below `/root` failed:

```text
history is a shell builtin
HOME=/root
HISTFILE=
touch: /root/.plumos-write-test: Read-only file system
```

After deploying and applying `plumos-ssh-home`, runtime state became:

```text
ssh_home=configured
home=bound
storage=/mnt/plumos/config/ssh/root
/dev/mmcblk0p3 /root ext4 rw,noatime,data=ordered
root_write=ok
```

The first interactive SSH session ran a uniquely named probe command followed
by `history -a`. A second, separately authenticated interactive SSH session
found that command through the `history` builtin and printed
`HISTORY_PERSIST_OK`. The backing `.bash_history` existed below the bound ext4
home. BusyBox `vi -c q` also completed with status 0 through the same SSH PATH.
Running the packaged SSH start path again left the persistent `.bashrc` hash
unchanged, confirming that service startup does not overwrite user shell state.
