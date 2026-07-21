# V90S USB cable transfer investigation and USB Disk Mode

Date: 2026-07-11

## Goal

Reduce dependence on the unstable USB Wi-Fi dongle for development access.

The desired long-term result is command and file transfer over a USB cable. The
first implemented step is safe USB file transfer through a dedicated mass
storage image. The second implemented step is a diagnostic command mailbox over
that same transfer image.

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

The helper exposes a dedicated transfer image instead of exporting
`/mnt/plumos` directly:

```text
image=/mnt/plumos/state/usb-disk/plumos-usb-transfer.img
mount_dir=/mnt/plumos/usb-transfer
size=64MiB by default
```

This avoids mounting the live FAT32 app layer on both V90S and the PC at the
same time.

The transfer image also carries a diagnostic command mailbox:

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
ejected/unplugged and the transfer image is remounted on V90S. Results are
written back to the same transfer image.

The transfer image also uses `roms/` as a safe ROM inbox. A USB mass-storage
gadget can export only a block device, not the live `/mnt/plumos/roms`
directory. Files copied to `PLUMUSB/roms/<system>/` are therefore imported,
after host eject and cable disconnect, into the currently active
`/mnt/plumos/roms` storage. Each file is copied to a temporary sibling and
renamed into place, and only a successfully imported inbox file is removed.
This preserves the rule that the PC and V90S never mount the same live ROM
filesystem concurrently.

Frontend change:

```text
Network Settings -> NW Service -> USB Disk Mode
```

## Live Deployment

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

On the Mac or other PC host, while `PLUMUSB` is visible:

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

Then eject `PLUMUSB` from the host and unplug the USB cable. V90S remounts the
transfer image and runs the command. The next USB Disk Mode session should show:

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

## User Validation Needed

Actual Mac-side USB drive detection and ROM import still need physical
validation:

1. Connect V90S to the Mac with a data-capable USB cable.
2. Open `Network Settings -> NW Service -> USB Disk Mode`.
3. Press A on `READY TO ENTER`.
4. A `PLUMUSB` drive should appear on the Mac.
5. Copy a test ROM to `roms/<system>/` on the drive.
6. Eject the drive on macOS.
7. Unplug the USB cable.
8. V90S should return and mount the transfer image at:

```text
/mnt/plumos/usb-transfer
```
9. Confirm the test ROM was moved into the active `/mnt/plumos/roms` storage
   and removed from the inbox.

## Remaining Work

True interactive command execution over USB is not solved by USB Disk Mode. The
standard path selected for plumOS is ADB userspace over FunctionFS/configfs. USB
Disk Mode remains the file-transfer and offline diagnostic mailbox path.

Alternative routes remain:

- implement a custom FunctionFS/libusb command channel plus a Mac-side CLI
- use a future kernel/vendor runtime with ECM/RNDIS/NCM or ACM enabled
