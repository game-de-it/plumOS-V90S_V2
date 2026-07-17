# 2026-07-17 PortMaster Update Time Sync Fix

## Symptom

Running `Update PortMaster` from Apps failed before release metadata could be
downloaded. The installed PortMaster payload remained intact.

## Root cause

The V90S system clock was still `2026-06-13` while the current date was
`2026-07-17`. Python rejected GitHub's TLS certificate with:

```text
ssl.SSLCertVerificationError: certificate verify failed: certificate is not yet valid
```

DNS, the Wi-Fi route, and the writable p7 filesystem were healthy. BusyBox
`ntpd -n -q` did not complete on this network, while BusyBox `rdate` obtained
the current time from `time.nist.gov` immediately.

## Fix

- Added the bounded one-shot `bin/plumos-time-sync` helper.
- Run time synchronization in the background whenever Wi-Fi obtains IPv4.
- Run time synchronization synchronously before PortMaster HTTPS operations.
- Convert PortMaster metadata/archive network failures into concise errors
  without a Python traceback.
- Preserve the existing staged update, checksum validation, atomic directory
  switch, and previous-payload recovery behavior.

## Real-device validation

Device transport: ADB serial `plumos-v90s-af929c1b`.

```text
before: Sat Jun 13 15:31:54 UTC 2026
after:  Fri Jul 17 11:06:59 UTC 2026
time-sync state: synced
time-sync source: time.nist.gov
Wi-Fi IPv4: 192.0.2.120
```

The exact Apps launch command then completed successfully:

```text
$ /mnt/plumos/bin/plumos-portmaster-update install stable
System time synchronized: 2026-07-17 11:07:13 UTC
PortMaster is current: 2026.06.23-0015 (stable)
```

Post-checks:

```text
installed.json version: 2026.06.23-0015
payload version:        2026.06.23-0015
partial update dirs:    0
p7 /mnt/plumos:         vfat rw
```

The official stable metadata also reported `2026.06.23-0015`, so no payload
replacement was needed after the clock fix.
