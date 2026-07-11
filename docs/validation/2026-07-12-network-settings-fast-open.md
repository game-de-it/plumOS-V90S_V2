# V90S Network Settings fast-open path

## Goal

Remove the visible pause when opening `Network Settings` and `NW Service`.

## Cause

Before this change, every settings screen open called `load_device_settings()`,
which called the full runtime network status path. Opening the Network screen or
NW Service screen therefore synchronously spawned:

```text
plumos-network-services status ssh
plumos-network-services status ftp
plumos-network-services status sftp
plumos-network-services status samba
plumos-network-services status adb
```

The V90S path was heavier than MMF/A30 because V90S also includes ADB, and the
ADB service status may call `plumos-adbd status`.

## Implemented Contract

`Network Settings` and `Network Settings -> NW Service` now use the persisted
requested state only:

```text
/mnt/plumos/config/system/settings.json        wifi_enabled
/mnt/plumos/config/network/services.conf       *_enabled
```

That matches the checkbox meaning:

- ON means start now and enable at boot.
- OFF means stop now and disable at boot.

The full runtime process check is still available, but only when opening:

```text
Network Settings -> INFORMATION
```

That screen still refreshes real Wi-Fi and service status using
`plumos-network-services status ...`.

## Build Validation

Validated:

```text
git diff --check
./scripts/docker-build.sh frontend
./scripts/docker-build.sh app-layer
```

The frontend rebuild emitted only the existing `plumos_text_ui.c` truncation
warnings unrelated to this change.

Generated frontend hash:

```text
c7fca77ebec47c7c82154065ee8ce0a65a6e7810e8c83cfee0b2d3ed9a5dd18d  output/app-layer/v90s/bin/plumos-controller-ui-fbdev
```

## Live Deployment Status

Live deployment was not performed during this pass because the current device
state had no command channel:

```text
adb devices -l: no devices
ping 192.0.2.120: reachable
tcp/22: connection refused
```

The implementation is ready for the next app-layer deploy or SD-image build.
