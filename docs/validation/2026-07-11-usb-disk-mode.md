# V90S USB cable transfer investigation and USB Disk Mode

Date: 2026-07-11
Direct p4 export update: 2026-07-22

## Goal

Reduce dependence on the unstable USB Wi-Fi dongle for development access.

The desired result is command and unrestricted-size file transfer over a USB
cable. The initial 64 MiB transfer image proved the gadget and command mailbox,
but could not carry disc images. The current design directly exports SD1 p4
`PLUMOS` after safely releasing it from V90S.

## Kernel Capability Check

Live device:

```text
ssh root@192.0.2.120
```

Observed USB device controller:

```text
/sys/class/udc/5100000.udc-controller
```

Relevant kernel configuration:

```text
CONFIG_USB_GADGET=y
CONFIG_USB_SUNXI_UDC0=y
CONFIG_USB_LIBCOMPOSITE=y
CONFIG_USB_CONFIGFS=y
CONFIG_USB_CONFIGFS_MASS_STORAGE=y
CONFIG_USB_CONFIGFS_F_FS=y
CONFIG_USB_CONFIGFS_F_MTP=y
CONFIG_USB_CONFIGFS_F_PTP=y
CONFIG_USB_SUNXI_USB_ADB=y
CONFIG_CONFIGFS_FS=y
```

Not enabled in this StockOS-derived kernel:

```text
CONFIG_USB_CONFIGFS_ACM
CONFIG_USB_CONFIGFS_ECM
CONFIG_USB_CONFIGFS_ECM_SUBSET
CONFIG_USB_CONFIGFS_NCM
CONFIG_USB_CONFIGFS_RNDIS
```

Conclusion:

- Standard USB Ethernet for SSH/SCP is not available with this kernel config.
- USB serial console through ACM is not available with this kernel config.
- ADB is possible through FunctionFS if plumOS supplies a compatible `adbd`
  userspace daemon and configfs control script.
- USB Mass Storage is available now.

## Implementation

Added:

```text
/mnt/plumos/bin/plumos-usb-disk-mode
```

Build source:

```text
package/network-services/plumos/bin/plumos-usb-disk-mode
```

The helper exports the p4 FAT32 block device that is normally mounted at:

```text
device=/dev/mmcblk0p4 (resolved and label/type checked at runtime)
label=PLUMOS
mount_dir=/mnt/plumos-user
```

It never exports p3 `/mnt/plumos`. Before gadget binding, it pauses p4 network
writers and ADB, stops SD2 content bindings, releases p4 bind mounts, syncs, and
cleanly unmounts p4. SSH is not stopped; if any process still holds p4, entry
fails without a force-unmount. After host eject and disconnect, it runs a
bounded FAT check, remounts p4, validates `.plumos-ready`, and restores p4/SD2
bindings and previously enabled services.

p4 also carries the diagnostic command mailbox:

```text
commands/README.TXT
commands/run.sh.example
commands/run.sh
commands/ALLOW_EXECUTE
results/<timestamp>/
processed/<timestamp>/
RESULT-LATEST.txt
```

The mailbox is deliberately opt-in. V90S executes `commands/run.sh` only when
`commands/ALLOW_EXECUTE` also exists, and only after the USB drive has been
ejected/unplugged and p4 is remounted on V90S. Results are
written back to p4 after remount.

Frontend change:

```text
Network Settings -> NW Service -> USB Disk Mode
```

## Historical Initial Deployment

The hashes and loop mount below describe the earlier capacity-limited transfer
image implementation. They remain as evidence for the gadget and mailbox
bring-up, but the current implementation supersedes this storage target with
direct p4 export.

Deployed binaries:

```text
9ceec3e60233661dffd2762767c4578f5e126dfee1578406fa259fed1d3de89c  /mnt/plumos/bin/plumos-usb-disk-mode
af9e3727176f01d58d9b39970f35354331fd327b3e59f1624b85c54fd87a9272  /mnt/plumos/bin/plumos-controller-ui-fbdev
```

The previous frontend binary and any previous USB disk helper were backed up
under:

```text
/mnt/plumos/backups/usb-disk-mode-20260711/
/mnt/plumos/backups/usb-command-mailbox-20260711/
```

Running frontend after deploy:

```text
pid=1692
```

## Live Validation

Created and mounted the transfer image on V90S:

```text
/mnt/plumos/bin/plumos-usb-disk-mode mount
```

Result:

```text
image_exists=1
mounted=1
gadget_bound=0
udc_state=not attached
/dev/loop1 on /mnt/plumos/usb-transfer type vfat
```

Write test:

```text
echo plumOS-usb-transfer-test > /mnt/plumos/usb-transfer/README.TXT
sync
```

No-cable safety test:

```text
PLUMOS_USB_DISK_CONNECT_TIMEOUT_SECONDS=3 \
/mnt/plumos/bin/plumos-usb-disk-mode enter
```

Result:

```text
rc=1
mounted=1
gadget_bound=0
udc_state=not attached
```

The helper bound `5100000.udc-controller`, timed out because no USB host was
attached, removed the gadget, and remounted the transfer image. This confirms
the UI path should not remain stuck forever when started without a cable.

## Command Mailbox Workflow

On the Mac or other PC host, while `PLUMOS` is visible:

```sh
mkdir -p commands
cat > commands/run.sh <<'EOF'
#!/bin/sh
date
uname -a
id
ip addr 2>/dev/null || ifconfig -a 2>/dev/null || true
plumos-network-services status 2>/dev/null || true
plumos-network-control status 2>/dev/null || true
df -h
EOF
touch commands/ALLOW_EXECUTE
```

Then eject `PLUMOS` from the host and unplug the USB cable. V90S checks and
remounts p4, then runs the command. The next USB Disk Mode session should show:

```text
RESULT-LATEST.txt
results/<timestamp>/command.sh
results/<timestamp>/stdout.txt
results/<timestamp>/stderr.txt
results/<timestamp>/exit_code.txt
results/<timestamp>/timed_out.txt
results/<timestamp>/env.txt
processed/<timestamp>/run.sh
```

Default execution environment:

```text
cwd=/mnt/plumos
PATH=/mnt/plumos/bin:/mnt/plumos/gnu/bin:/usr/sbin:/usr/bin:/sbin:/bin
timeout=120 seconds
```

This is not an interactive shell. It is intended for bounded diagnostics and
log capture when Wi-Fi or SSH is unavailable.

## Live Command Mailbox Smoke Test

Live deployment was updated over SSH while Wi-Fi was still reachable:

```text
sha256=/mnt/plumos/bin/plumos-usb-disk-mode
9ceec3e60233661dffd2762767c4578f5e126dfee1578406fa259fed1d3de89c
```

A short command was placed into the mounted transfer image and processed on the
V90S:

```text
commands/run.sh
commands/ALLOW_EXECUTE
PLUMOS_USB_COMMAND_TIMEOUT_SECONDS=10 plumos-usb-disk-mode process-commands
```

Result:

```text
ELAPSED=1
exit_code=0
timed_out=0
result_dir=results/20260608-211850
stdout contained:
USB_MAILBOX_FAST_SMOKE
Linux (none) 4.9.191 #17 SMP PREEMPT Tue May 13 18:14:09 UTC 2025 aarch64 GNU/Linux
uid=0(root) gid=0(root) groups=0(root)
```

Timeout behavior was also tested with `sleep 5` and a one-second command
timeout:

```text
exit_code=124
timed_out=1
stdout contained:
USB_MAILBOX_TIMEOUT_SMOKE
```

After each run, `command_script=0` and `command_armed=0` in `status`, confirming
that the same command is not re-executed automatically.

This prior live use validates command execution, output capture, timeout, and
one-shot behavior. Physical macOS enumeration remains a USB Disk Mode transport
check rather than a separate mailbox implementation check.

## Direct p4 Host Simulation

The current direct-export implementation was exercised in a privileged Linux
container with a loop-backed FAT32 volume labeled `PLUMOS`.

Round trip:

```text
volume size: 256 MiB
host write:  roms/psx/test-96m.chd (96 MiB)
host write:  updates/test.tar.gz
result:      direct-p4-roundtrip=PASS
```

The test mounted p4 on the simulated V90S, released it through
`plumos-usb-disk-mode unmount`, mounted it on the simulated host, wrote files
larger than the old 64 MiB transfer image, unmounted it from the host, and
restored it through `plumos-usb-disk-mode mount`. The `.plumos-ready` marker,
ROM image, update archive, and command-mailbox tree were all present after the
round trip.

Negative and recovery tests:

```text
busy-p4-refusal=PASS
failed-fsck-refusal=PASS
wrong-label-refusal=PASS
cross-process-service-restore=PASS
```

The helper refuses to export a busy p4, refuses to remount after an unrepaired
FAT check, and rejects a block device whose current uncached label is not
`PLUMOS`. Recovery markers under `/run` also restore ADB plus only the
previously enabled FTP/SFTP/Samba services when `leave` runs in a new helper
process. The mass-storage LUN keeps FUA handling enabled (`nofua=0`); users
must still eject `PLUMOS` on the host before unplugging the cable.

## Physical macOS Direct-p4 Validation

The live V90S initially still carried the old 64 MiB transfer-image helper.
Only `bin/plumos-usb-disk-mode` and its matching live manifest/checksum entries
were updated. The app-layer validator returned `ready` before the test.

USB Disk Mode was started over SSH so that ADB could stop when the shared USB
controller changed from FunctionFS to mass storage. macOS detected and mounted:

```text
/dev/disk5 (external, physical)
name: PLUMOS
size: 114.0 GB
mount: /Volumes/PLUMOS
filesystem: msdos
```

While the host owned p4, live status correctly reported:

```text
export_device=/dev/mmcblk0p4
mount_dir=/mnt/plumos-user
mounted=0
gadget_bound=1
```

Two lightweight files were written and read back on macOS:

```text
566c4e9dd81d173b7175955e79e0d93f0038e704c3f4b610a8da41e881111934  roms/USB-DISK-MODE-ROM-TEST.txt
63344492c34c35c640a7a4ddd9147220af7e9ce450e78480f6ea3453617ce897  updates/USB-DISK-MODE-UPDATE-TEST.txt
```

After `diskutil eject`, USB Disk Mode was left over SSH. The helper checked and
remounted p4, restored the SD2 content bindings, and restored the previously
enabled services. Both hashes matched from `/mnt/plumos-user`, then the test
files were removed.

Final state:

```text
/dev/mmcblk0p4 on /mnt/plumos-user type vfat (rw)
/dev/mmcblk1p1 on /mnt/plumos/roms type vfat (rw)
ssh=running
ftp=running
sftp=running
adb=running
app_layer=ready
```

This validates direct writes to the SD1 p4 `roms/` directory and the System
Update inbox at `updates/`. USB Disk Mode does not export SD2. When SD2 is
inserted, the frontend's active `/mnt/plumos/roms` bind points to SD2, so a ROM
copied to p4 is retained on SD1 but is not the active FE ROM source until SD2 is
removed. This bounded physical check used small files; the earlier Linux host
simulation remains the 96 MiB sustained-transfer evidence.

## Remaining Work

True interactive command execution over USB is not solved by USB Disk Mode. The
standard path selected for plumOS is ADB userspace over FunctionFS/configfs. USB
Disk Mode remains the file-transfer and offline diagnostic mailbox path.

Alternative routes remain:

- implement a custom FunctionFS/libusb command channel plus a Mac-side CLI
- use a future kernel/vendor runtime with ECM/RNDIS/NCM or ACM enabled
