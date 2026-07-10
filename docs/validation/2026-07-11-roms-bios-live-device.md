# V90S live device lowercase roms/bios deployment

Date: 2026-07-11

## Target

Live V90S over SSH:

```text
root@192.0.2.120
/mnt/plumos: /dev/mmcblk0p7 vfat
```

## Deployed Files

Copied a small tar payload to `/tmp/plumos-v90s-roms-bios-live-update.tar.gz`
and extracted these files onto `/mnt/plumos`:

```text
bin/plumos-library-scan
bin/plumos-frontend
bin/plumos-frontend-launch
bin/plumos-retroarch-launch
bin/plumos-retroarch-menu-launch
config/frontend/systems.json
```

Frontend was stopped with:

```text
/mnt/plumos/bin/plumos-frontend-stop stop
```

No SSH, Wi-Fi, FTP, SFTP, or Samba service was stopped.

Backup directory:

```text
/mnt/plumos/backups/roms-bios-lower-20260608-064807
```

## Directory Migration

Before migration, `/mnt/plumos` contained:

```text
BIOS
Roms
```

Because p7 is FAT32/vfat, the case-only rename used a temporary name. Result:

```text
renamed Roms -> roms
renamed BIOS -> bios
```

Confirmed content roots:

```text
bios
roms
```

## Installed Hashes

```text
9958acbc76ad716509df8b31fe2b5df516344decfb7a50eca0ed55d2330873f4  /mnt/plumos/bin/plumos-library-scan
8ba8613d5b23100c254592a93840f8c9bb475d1d5c29319992d65c9e0da2a877  /mnt/plumos/bin/plumos-frontend
05c7119868a346d4de963abfa794df852e056eb81ee0e523838ca0b16684f0ad  /mnt/plumos/bin/plumos-frontend-launch
ba6e75bb280d4af36c9d290e35e2ac176d75e791db5b9c6d9c0e19bcc4cbbf36  /mnt/plumos/bin/plumos-retroarch-launch
8c7368c5cf0b5273bfb274b16019d7815c9039bc7c45cc74c445d4998b16f79f  /mnt/plumos/bin/plumos-retroarch-menu-launch
d121cc44703a0ba0201299fdf19753ca59ecf4b32205584cf9d12d4c2d08d254  /mnt/plumos/config/frontend/systems.json
```

## Test ROM

For development validation only, copied the existing local test ROM from
`artifacts/nes/Super Mario Bros..nes` to:

```text
/mnt/plumos/roms/nes/Super Mario Bros..nes
```

Hash:

```text
0b3d9e1f01ed1668205bab34d6c82b0e281456e137352e4f36a9b2cfa3b66dea  /mnt/plumos/roms/nes/Super Mario Bros..nes
```

This is live-device test content only and is not part of release artifacts.

## Scanner Result

Command:

```sh
PLUMOS_ROOT=/mnt/plumos PLUMOS_SDCARD_ROOT=/mnt/plumos \
  /mnt/plumos/bin/plumos-library-scan --system nes --defer-thumbnails
```

Result:

```text
system nes                roms=1 thumbnails=0
summary alias_dirs=1 files_seen=1 matched=1 roms=1 thumbnails=0 elapsed_ms=7
wrote: /mnt/plumos/state/frontend/systems/nes.json
```

Cache check:

```text
"rom_count": 1
"path": "/mnt/plumos/roms/nes/Super Mario Bros..nes"
"relative_path": "nes/Super Mario Bros..nes"
```

## Frontend State

Frontend was restarted after deployment.

```text
plumos-frontend-stop: pid=2349 cmd=/mnt/plumos/bin/plumos-controller-ui-fbdev --renderer fbdev
```
