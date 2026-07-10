# V90S Frontend Network Settings Menu

Date: 2026-07-11

## Trigger

The user confirmed that the frontend boots, but there was no visible network
settings item. That made Wi-Fi setup unavailable from the frontend.

## Finding

The V90S frontend source already had the network settings implementation:

- `internal:network-settings` routes to the network settings category.
- The network category exposes Wi-Fi enable, Wi-Fi connect, network services,
  and network information entries.
- Language files already included `menu.entry.network-settings.name`.

The missing piece was the V90S menu configuration. `package/frontend-v90s` did
not include the `network-settings` START menu entry that exists in the MMF and
A30 frontend menu definitions.

## Change

Added this START menu entry to
`package/frontend-v90s/plumos/config/frontend/menus.json`:

```json
{
  "id": "network-settings",
  "display_name": "Network Settings",
  "kind": "internal",
  "action": "internal:network-settings"
}
```

## Build

Commands:

```sh
./scripts/docker-build.sh frontend
./scripts/docker-build.sh app-layer --strict
./scripts/docker-build.sh sd-image \
  --boot0 output/device-live/raw-boot-chain/plumos-v90s-stockos-ra-20260710-2-stockos-video.img/boot0.bin \
  --boot-package output/device-live/raw-boot-chain/plumos-v90s-stockos-ra-20260710-2-stockos-video.img/boot-package.bin \
  --rootfs-squashfs output/rootfs-step2-appfat/debian-bookworm-retroarch-knulli-step2.squashfs \
  --app-layer-dir output/app-layer/v90s \
  --share-size 1024M \
  --name plumos-v90s-appfat-1g-netmenu-20260711-1.img
```

Generated image:

```text
output/images/plumos-v90s-appfat-1g-netmenu-20260711-1.img
sha256=377bee0f642b1e058a98de19d3ebf36b3c31ac2efcb01b4a4ff67e770be900e0
```

Image manifest highlights:

```text
share_size=1024M
app_layer_dir=output/app-layer/v90s
app_layer_manifest_sha256=a2132547d25fb36b41ff1c70f358022da284fb54eecfe8e5d130b57e3d179dc7
allow_knulli_boot_fallback=0
```

## Host Verification

App-layer checksum verification:

```sh
(cd output/app-layer/v90s && sha256sum -c checksums.sha256)
```

Result: all files OK.

Docker-toolchain partition inspection:

```text
Disk output/images/plumos-v90s-appfat-1g-netmenu-20260711-1.img: 1.58 GiB
p7 start=1223912 sectors=2097152 size=1G type=Microsoft basic data
```

Direct p7 FAT32 inspection:

```sh
img=output/images/plumos-v90s-appfat-1g-netmenu-20260711-1.img
off=$((1223912*512))
MTOOLS_SKIP_CHECK=1 mtype -i "$img@@$off" ::/config/frontend/menus.json
```

Confirmed the image contains:

```json
{
  "id": "network-settings",
  "display_name": "Network Settings",
  "kind": "internal",
  "action": "internal:network-settings"
}
```

## Real-device Status

Pending. The next device test should confirm:

- START menu shows `Network Settings`.
- Wi-Fi scan does not hang when no USB Wi-Fi dongle is attached.
- With the USB Wi-Fi dongle attached, selecting a network can start the
  connection flow.
- SSH/FTP/SFTP/Samba service toggles are reachable from the network services
  submenu.
