# V90S RTC and Time Settings Validation

Date: 2026-07-17

## Scope

Make the frontend `TIME SETTINGS` screen control real V90S timekeeping:

- retain a useful time without network access
- synchronize after Wi-Fi obtains IPv4
- persist corrected or manually selected time to RTC
- expose the actual RTC state instead of presenting a non-existent NTP daemon

## Hardware and Kernel Result

The StockOS-derived kernel has the sunxi RTC enabled:

```text
/dev/rtc0
/sys/class/rtc/rtc0/name: sunxi-rtc
CONFIG_RTC_HCTOSYS=y
CONFIG_RTC_SYSTOHC=y
CONFIG_RTC_DRV_SUNXI=y
```

Before this change, network time had corrected the system clock to July 17,
but RTC was still around June 13. The observed difference was about 34 days.

The RTC ticks and survives a safe reboot. It is not precise on this device: a
short live sample showed it losing seconds relative to the system clock. plumOS
therefore treats RTC as the offline boot baseline and network time as the
authoritative correction source.

## Runtime Contract

`/mnt/plumos/bin/plumos-time-sync` owns clock synchronization.

```text
sync        obey automatic_time and synchronize once
force-sync  synchronize once regardless of automatic_time
store-rtc   write current system time to /dev/rtc0 in UTC
status      report setting, system time, RTC time, and offset
```

The operation uses a bounded `rdate` request and does not leave a daemon
running. A successful request stores system time to RTC. The existing Wi-Fi
control path calls `sync` only after IPv4 has been obtained.

Frontend `TIME SETTINGS` now exposes:

```text
Current Time
Automatic Time
Sync Now
RTC Status
Timezone
Manual Time
```

Automatic Time defaults to ON. Manual Time turns it OFF and writes the selected
time to RTC. Sync Now always performs one explicit synchronization. Timezone is
applied to plumOS processes while the system clock and RTC remain UTC.

## Build and Static Checks

```text
sh -n package/network-services/plumos/bin/plumos-time-sync
./scripts/docker-build.sh frontend
./scripts/docker-build.sh network-services
./scripts/docker-build.sh app-layer --strict
git diff --check
```

The time helper was also tested with mocked `rdate`, `hwclock`, system time, and
RTC sysfs inputs. Automatic Time OFF skipped `rdate`; `force-sync` invoked both
`rdate` and `hwclock`; status reported a zero-second mock offset.

## Real-Device Frontend Checks

The text renderer showed the deployed screen through the normal settings
navigation path:

```text
Current Time             2026-07-17 22:09
Automatic Time           true
Sync Now
RTC Status               Synced
Timezone                 Japan
Manual Time
```

Frontend input paths were exercised for:

- Automatic Time OFF: retained the current clocks and skipped automatic sync
- Automatic Time ON: synchronized system time and RTC
- Sync Now: synchronized even when invoked as an explicit action
- Manual Time Apply: disabled Automatic Time and saved the selected time to RTC
- re-enabling Automatic Time after manual input

The existing mutable settings were preserved during deployment:

```text
automatic_time=true
volume=12
frontend_processes=1
partial_files=0
```

## Safe-Reboot Proof

Immediately before reboot, system and RTC epochs matched:

```text
before_reboot_system=1784294064
before_reboot_rtc=1784294064
```

The reboot used the protected rootfs power path:

```text
/mnt/plumos/bin/plumos-safe-shutdown --reboot
```

ADB returned at 12 seconds uptime. The new boot log proved that the kernel read
the newly stored RTC rather than the old June value:

```text
sunxi-rtc rtc: setting system clock to 2026-07-17 13:14:37 UTC (1784294077)
```

After boot:

```text
automatic_time=true
frontend_processes=1
/dev/mmcblk0p7 on /mnt/plumos type vfat (rw,...,errors=remount-ro)
FAT/I/O errors: none
```

No Wi-Fi interface was present during the reboot check, so the post-IPv4
network synchronization correctly remained pending instead of delaying boot.
