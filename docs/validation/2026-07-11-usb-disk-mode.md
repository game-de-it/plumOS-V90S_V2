# V90S USB cable transfer investigation and USB Disk Mode

Date: 2026-07-11

## Goal

Reduce dependence on the unstable USB Wi-Fi dongle for development access.

The desired long-term result is command and file transfer over a USB cable. The
first implemented step is safe USB file transfer through a dedicated mass
storage image.

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
- ADB may be possible in the future through FunctionFS, but no `adbd` userspace
  daemon is currently present in plumOS or the live rootfs.
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

Frontend change:

```text
Network Settings -> NW Service -> USB Disk Mode
```

## Live Deployment

Deployed binaries:

```text
bad0802cdb00181be74b11cadb2a0a97244539cb664eda8aa5eb73e25ecb2e61  /mnt/plumos/bin/plumos-usb-disk-mode
af9e3727176f01d58d9b39970f35354331fd327b3e59f1624b85c54fd87a9272  /mnt/plumos/bin/plumos-controller-ui-fbdev
```

The previous frontend binary and any previous USB disk helper were backed up
under:

```text
/mnt/plumos/backups/usb-disk-mode-20260711/
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

## User Validation Needed

Actual Mac-side USB drive detection still needs physical validation:

1. Connect V90S to the Mac with a data-capable USB cable.
2. Open `Network Settings -> NW Service -> USB Disk Mode`.
3. Press A on `READY TO ENTER`.
4. A `PLUMUSB` drive should appear on the Mac.
5. Copy files to/from the drive.
6. Eject the drive on macOS.
7. Unplug the USB cable.
8. V90S should return and mount the transfer image at:

```text
/mnt/plumos/usb-transfer
```

## Remaining Work

Command execution over USB is not solved by USB Disk Mode. The practical future
routes are:

- port an `adbd` userspace daemon and expose ADB through FunctionFS
- implement a custom FunctionFS/libusb command channel plus a Mac-side CLI
- use a future kernel/vendor runtime with ECM/RNDIS/NCM or ACM enabled
