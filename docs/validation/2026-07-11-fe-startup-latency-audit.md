# V90S FE startup latency audit

Date: 2026-07-11

## Trigger

The user reported that the frontend takes a long time to appear after reboot
and asked where the boot sequence is blocking.

## Live device

Device:

```text
root@192.0.2.120
```

Current boot command line:

```text
console=ttyS0,115200 root=/dev/mmcblk0p6 rootwait init=/sbin/init ...
```

## Process start offsets

The live process start times show that the frontend process container is created
after the network path:

```text
pid=1   start_after_boot=0s  comm=init
pid=383 start_after_boot=7s  comm=sshd
pid=475 start_after_boot=10s comm=wpa_supplicant
pid=505 start_after_boot=15s comm=dhclient
pid=594 start_after_boot=16s comm=busybox tcpsvd
pid=708 start_after_boot=20s comm=ld-linux-aarch64 / smbd.bin
pid=724 start_after_boot=21s comm=plumos-controller-ui-fbdev
```

Because `plumos-frontend-launch` uses `exec`, the PID start time reflects the
launcher shell creation time. The real first draw can be later if the launcher
is still doing synchronous setup.

## Boot-order evidence

`/mnt/share/plumos-v90s-debian-init.log` shows the current order:

```text
debian-init: starting PowerVR probe
debian-init: PowerVR probe exited rc=0
debian-init: starting network/SSH init
debian-init: network/SSH init exited rc=0
debian-init: probing app layer dev=/dev/mmcblk0p7 fstype=vfat
debian-init: mounted app layer dev=/dev/mmcblk0p7 fstype=vfat
debian-init: starting enabled plumOS network services
debian-init: starting plumOS frontend
```

So the frontend is intentionally last in this development boot path.

## Main blockers before FE

### 1. Rootfs-level Wi-Fi/SSH hook

The old development hook `v90s-network-ssh-init` still runs before the app
layer and before the frontend. It starts SSH, loads the USB Wi-Fi driver,
starts `wpa_supplicant`, waits for association, and runs DHCP.

Evidence from `/mnt/share/plumos-v90s-network-ssh.log`:

```text
network-ssh: loading USB Wi-Fi modules
network-ssh: usb_wifi_driver_candidates=8821cu
usbcore: registered new interface driver rtl8821cu
network-ssh: wifi_iface=wlan0
wpa_state=SCANNING
wpa_state=SCANNING
wpa_state=SCANNING
wpa_state=COMPLETED
network-ssh: WPA completed
DHCPDISCOVER on wlan0 ...
DHCPOFFER of 192.0.2.120 from 192.0.2.1
DHCPACK of 192.0.2.120 from 192.0.2.1
bound to 192.0.2.120
network-ssh: finished
```

This is the largest pre-FE blocker. It is also still responsible for current
SSH reachability, so it should not be removed until app-layer Wi-Fi/DHCP/SSH
startup is validated from a clean boot.

### 2. App-layer network services

After the app layer is mounted, `plumos-network-services start-enabled` starts
enabled services before the frontend:

```text
2026-06-08 07:32:19 service=ssh start
2026-06-08 07:32:19 service=ftp start port=21 max=20 share=/mnt/plumos
2026-06-08 07:32:20 service=sftp start share=/mnt/plumos ssh=plumos_controlled
2026-06-08 07:32:21 service=samba start max=20 share=/mnt/plumos
```

This adds roughly a few seconds and is currently synchronous.

### 3. SD2 fsck inside frontend launcher

`plumos-frontend-launch` runs `plumos-sd2-content-mount start` before execing
the controller UI. With the current FAT32 SD2 card this performs a blocking
`fsck.fat`:

```text
2026-06-08T07:32:24+0000 fsck: running fsck.fat -a -w /dev/mmcblk1p1
/dev/mmcblk1p1: 16903 files, 2095956/7629871 clusters
2026-06-08T07:32:30+0000 fsck: /dev/mmcblk1p1 rc=0
2026-06-08T07:32:30+0000 mount: mounted SD2 dev=/dev/mmcblk1p1 fstype=vfat on /run/plumos/sd2
2026-06-08T07:32:30+0000 bind: roms /run/plumos/sd2/roms -> /mnt/plumos/roms
2026-06-08T07:32:30+0000 bind: bios /run/plumos/sd2/bios -> /mnt/plumos/bios
```

This adds about 6 seconds before the UI can draw.

## Conclusion

The FE startup delay is not primarily inside the frontend renderer. The current
development boot path serializes these tasks before the visible UI:

1. PowerVR probe/startup.
2. Old rootfs Wi-Fi/SSH hook, including WPA association and DHCP.
3. App-layer FTP/SFTP/Samba startup.
4. SD2 FAT fsck and bind mounts.

The frontend appears only after these finish. On this boot, the process timeline
places the FE launcher around 21 seconds after boot, while SD2 fsck/mount
continues until roughly 28-30 seconds after boot.

## Recommended fixes

- Start the frontend before network services, then bring Wi-Fi/SSH/FTP/Samba up
  in the background.
- Move Wi-Fi association and DHCP into the app-layer network control path so
  the old rootfs-level `v90s-network-ssh-init` can be disabled.
- Change SD2 mount policy so the UI can appear before a full FAT32 fsck
  completes. Options:
  - mount SD2 in the background and refresh the FE when ready;
  - skip fsck during normal boot and expose a manual or periodic fsck path;
  - run fsck only when an explicit dirty/diagnostic policy requests it.
- Add monotonic timestamps to `debian-init`, `plumos-frontend-launch`, and
  `plumos-sd2-content-mount` logs so future boot timing can be measured without
  inferring from process start times.
