# V90S boot speed retest

Date: 2026-07-11

## Goal

Measure the boot-speed change after making the frontend the primary boot path,
then fix any service regressions introduced by the faster order.

## Baseline

Before the boot-speed change, the live process offsets were:

```text
sshd                 7s
wpa_supplicant      10s
dhclient            15s
FTP                 16s
Samba               20s
frontend launcher   21s
```

The frontend launcher then waited on SD2 FAT fsck:

```text
07:32:24 fsck.fat -a -w /dev/mmcblk1p1
07:32:30 SD2 mounted and roms/bios bind-mounted
```

So visible frontend startup was effectively behind network setup and the SD2
fsck path.

## First Fast-Boot Retest

The first reboot after writing the permanent p5 rootfs confirmed that the
intended init was active:

```text
f76104801ebba49726c5f3184eac832b6568d9978e3058b5101b6bf11736d592  /dev/mmcblk0p5
71ef50cdd7ae7daeb5fdbcc9d7acf3ade6e3aba83f03a67e94b011d277503b5a  /overlay/base/usr/sbin/init
71ef50cdd7ae7daeb5fdbcc9d7acf3ade6e3aba83f03a67e94b011d277503b5a  /sbin/init
321384e98e734d76938bd21614463d01bf385862b343a2514528629a7e2fa994  /mnt/plumos/bin/plumos-frontend-launch
```

The process offsets changed to:

```text
init                 0s
frontend launcher    2s
FTP                  4s
sshd                 5s
wpa_supplicant       9s
dhclient            14s
first SSH login     25s
```

The boot log also showed the new order:

```text
debian-init: fb0 probe skipped
debian-init: starting PowerVR probe in background
debian-init: starting network/SSH init in background
debian-init: mounted app layer dev=/dev/mmcblk0p7 fstype=vfat
debian-init: starting plumOS frontend
debian-init: plumOS frontend pid=227
debian-init: starting enabled plumOS network services in background
debian-init: waiting for plumOS frontend pid=227
```

SD2 mounted without boot-time fsck:

```text
2026-06-08T07:54:35+0000 mount: trying dev=/dev/mmcblk1p1 fstype=vfat
2026-06-08T07:54:35+0000 mount: mounted SD2 dev=/dev/mmcblk1p1 fstype=vfat on /run/plumos/sd2
2026-06-08T07:54:35+0000 bind: roms /run/plumos/sd2/roms -> /mnt/plumos/roms
2026-06-08T07:54:35+0000 bind: bios /run/plumos/sd2/bios -> /mnt/plumos/bios
```

## Regression Found

The app-layer network services now start early enough that Samba can run before
Wi-Fi/DHCP has created a usable network interface:

```text
service=samba
state=stopped
summary=Samba stopped
enabled=1
...
ERROR: Could not determine network interfaces, you must use a interfaces config line
debian-init: plumOS network services exited rc=2
```

FTP and SSH were running, but Samba was not.

## Fix

The generated Debian init now keeps the early non-blocking service launch, but
also retries enabled plumOS network services after the rootfs Wi-Fi/DHCP hook
finishes successfully.

New init markers:

```text
debian-init: starting enabled plumOS network services in background reason=after-frontend
debian-init: retrying enabled plumOS network services after network init
debian-init: plumOS network services retry exited rc=...
```

The retry stays in the background path and does not block frontend startup.

## Build and Deployment

Rebuilt:

```sh
./scripts/docker-build.sh system-rootfs \
  --profile debian-retroarch-knulli \
  --out-dir output/rootfs-step2-appfat \
  --rom "artifacts/nes/Super Mario Bros..nes" \
  --wifi-ssid example-wifi-2 \
  --wifi-psk REDACTED_WIFI_PASSWORD \
  --ssh-root-password linux
```

Generated hashes:

```text
947fcd2f03eb6aabe71a51c597a5fa2868a0216d63616d54d38457d392decc52  output/rootfs-step2-appfat/debian-bookworm-retroarch-knulli-step2.squashfs
29dda2c1f21f467ebc78bd24c9103b2a89a4063bf4e73e90a6ffa52926a3de65  /usr/sbin/init inside rootfs
```

Repacked p5:

```text
9e9bef44418787313693ba35a6e2321db0dbaaae85737b28c1138881fddfd37f  output/images/.work-v90s-stockos-image/input/batocera-rootfs.squashfs
```

Deployed to the live device:

```text
9e9bef44418787313693ba35a6e2321db0dbaaae85737b28c1138881fddfd37f  /dev/mmcblk0p5
```

## Remaining Validation

The V90S needs one more reboot after the netretry p5 write. Expected result:

- frontend process still starts at about 2 seconds after boot;
- SD2 mount still uses `fsck_mode=off`;
- FTP and SSH start after the frontend without blocking it;
- Samba may fail on the first early service pass, then should start on the
  post-network retry;
- boot log should contain `retrying enabled plumOS network services after
  network init`.
