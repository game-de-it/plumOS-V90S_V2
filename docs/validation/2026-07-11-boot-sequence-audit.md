# V90S boot sequence audit

Date: 2026-07-11

## Trigger

After FE reboot was fixed, the user confirmed reboot worked and asked whether
the boot sequence still contained the old "black screen with a white bar at the
top" framebuffer test.

## Live device evidence

Device:

```text
root@192.0.2.120
```

Kernel command line did not request any explicit plumOS framebuffer diagnostic:

```text
console=ttyS0,115200 root=/dev/mmcblk0p6 rootwait init=/sbin/init ...
```

The live boot log proved the old framebuffer probe was still running during
normal boot:

```text
debian-init: fb0 probe begin
debian-init: fb0 unblank requested
debian-init: fb0 full black wrote blocks=600 bytes=2457600
debian-init: fb0 white band page0 wrote
debian-init: fb0 white band page1 wrote seek_blocks=300
```

No `v90s-fb-console` process was running after boot. The visible bar was from
the one-shot boot probe, not from a resident framebuffer console process.

## Root cause

`scripts/build-step1-rootfs.sh` still generated stage1 and Debian init scripts
that called `fb_probe` unconditionally. That probe was created during early LCD
bring-up and deliberately painted the framebuffer black, then wrote a white
band to both framebuffer pages.

The current distribution policy requires diagnostics and fallback experiments
to be explicit. This white-band probe no longer belongs in the normal boot
path.

## Fix

Changed `scripts/build-step1-rootfs.sh` so the framebuffer probe is skipped by
default in both stage1 and Debian init.

The probe now runs only when explicitly enabled by one of these diagnostic
switches:

```text
PLUMOS_V90S_BOOT_FB_PROBE=1
plumos.fb_probe=1 on /proc/cmdline
/mnt/share/plumos-enable-fb-probe
/mnt/plumos/config/system/enable-fb-probe
```

The generated init path now logs one of these states:

```text
stage1: fb0 probe skipped
debian-init: fb0 probe skipped
```

or, when explicitly enabled:

```text
stage1: fb0 probe enabled
debian-init: fb0 probe enabled
```

## Validation

Syntax check:

```text
sh -n scripts/build-step1-rootfs.sh
```

Generated a lightweight stage1 test rootfs:

```text
./scripts/docker-build.sh system-rootfs --profile stage1 --out-dir output/rootfs-nofbprobe-stage1-test
```

Output:

```text
created: output/rootfs-nofbprobe-stage1-test/stage1-userdata-loader.squashfs
23b392838f1a687ce99de0cdc07d2bda3f3a4fe40c2af5079675901a538af5df  output/rootfs-nofbprobe-stage1-test/stage1-userdata-loader.squashfs
```

Inspected the generated stage1 init inside Docker. The white-band drawing code
still exists for explicit diagnostics, but the only call sites now go through
`run_fb_probe_if_enabled`.

## Other boot-sequence observations

The boot log also showed that the old rootfs-level development network hook is
still active:

```text
debian-init: starting network/SSH init
debian-init: network/SSH init exited rc=0
```

That hook currently loads the USB Wi-Fi driver, starts `wpa_supplicant`, obtains
DHCP, and starts the rootfs SSH daemon:

```text
wpa_state=COMPLETED
bound to 192.0.2.120
/usr/sbin/sshd ... -o PidFile=/run/plumos-v90s/sshd.pid
```

The app-layer network services then start FTP/SFTP/Samba and report SSH as
running. This means the old hook is still functionally important for current
SSH reachability, even though it conflicts with the long-term policy that
Wi-Fi/SSH should be controlled from the plumOS app layer.

Do not disable `v90s-network-ssh-init` until app-layer Wi-Fi association, DHCP,
and SSH startup have been validated from a clean boot without the rootfs hook.
