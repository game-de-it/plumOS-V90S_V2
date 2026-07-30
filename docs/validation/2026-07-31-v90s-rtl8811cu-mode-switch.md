# V90S UGREEN AC650 / RTL8811CU mode-switch validation

Date: 2026-07-31
Target release: `1.0.1`
Host result: PASS
Real-device diagnosis: PASS
Real-device provisional v1.0.1 update result: PASS with cold-boot gap found

## Failure evidence

The UGREEN AC650 / RTL8811CU was connected directly to the running V90S and
inspected through ADB. Before any manual intervention it did not expose the
USB ID registered to the Wi-Fi driver:

```text
0bda:1a2b Realtek DISK
interface class=08 subclass=06 protocol=50
driver=usb-storage
block device=/dev/sr0
wifi=off
iface=none
dongle=present_no_wifi_iface
```

Neither `8821cu` nor a wireless interface was present. The release contains
the correct `0bda:c811 -> 8821cu` alias and matching kernel module, but alias
matching cannot occur while the adapter remains in its driver-disk mode.

## Real-device mode-switch proof

The existing BusyBox eject applet was used on the matching virtual CD-ROM:

```text
eject -s /dev/sr0
```

The adapter immediately disconnected and re-enumerated as:

```text
0bda:c811 Realtek 802.11ac NIC
modalias=usb:v0BDApC811d0200dc00dsc00dp00icFFiscFFipFFin00
```

The normal app-layer Wi-Fi ON path then produced:

```text
module=8821cu
driver=rtl8821cu
iface=wlan0
link=UP,LOWER_UP
band=5 GHz
IPv4=assigned
gateway ping=3/3, 0% loss
rx_errors=0
tx_errors=0
```

The user also confirmed that the dongle activity LED was blinking. This is
direct physical confirmation for the `0bda:c811` path, not only module-alias
eligibility.

## Correction

The app-layer controller now:

1. checks for the exact initial USB ID `0bda:1a2b`;
2. resolves only an `sr*` block device below that USB sysfs node;
3. performs one bounded SCSI eject;
4. waits for `0bda:c811` re-enumeration;
5. continues the existing alias-driven `8821cu` load and bounded Wi-Fi path.

The Wi-Fi uevent helper also accepts the matching USB add event. It hands the
event to the existing coalesced recovery only while Wi-Fi is requested. There
is no periodic polling, and unrelated USB storage is not ejected.

## Host tests

```text
python3 -m unittest -v tests.test_network_control_mode_switch
Ran 6 tests
OK

python3 -m unittest discover -s tests -v
Ran 38 tests
OK
```

The fake-sysfs tests cover:

- `1a2b` to `c811` before driver detection;
- `c811` idempotency without a second eject;
- no eject for an unrelated USB storage ID;
- recovery routing for the Realtek driver-disk USB add event;
- preservation of the existing wireless net add event;
- rejection of unrelated USB add events.

## Provisional signed Runtime Update

The provisional package was a signed delta from the verified 5,766-file `1.0.0`
app-layer baseline:

```text
path=dist/updates/plumos-v90s-runtime-1.0.1.tar.gz
size=569962
sha256=1b3a2f372e30ddb4477f8ce9e53305316e980c59d471e7c1f629f4135774521e
package_type=runtime
source_version=1.0.0
version=1.0.1
full_payload=false
payload_files=7
payload_uncompressed_bytes=2453721
deleted_files=0
```

The payload contains only:

```text
VERSION
bin/plumos-network-control
bin/plumos-wifi-uevent
checksums.sha256
licenses/network-services-manifest.txt
manifest.json
share/doc/network-services/SHA256SUMS
```

The package public-key signature, compatibility fields, member allowlist, and
every payload size and SHA-256 passed independent inspection. An isolated
copy-on-write clone of the `1.0.0` runtime also completed the real updater
sequence:

```text
request=PASS
apply-pending=PASS
installed VERSION=1.0.1
runtime-pending=present
mark-healthy=PASS
runtime-pending=cleared
```

The archive was then copied only to the running V90S `/tmp` and inspected by
the unmodified `1.0.0` device updater at `/usr/sbin/plumos-system-update`.
No update request or installation was performed:

```text
installed_runtime=1.0.0
installed_system=1.0.0
package_type=runtime
source_version=1.0.0
version=1.0.1
sha256=1b3a2f372e30ddb4477f8ce9e53305316e980c59d471e7c1f629f4135774521e
device_inspect=PASS
```

## Provisional update device result

The provisional `1.0.1` Runtime Update installed successfully on the physical
V90S. The frontend reported `1.0.1`, the transaction reached
`runtime_healthy`, no pending state remained, and the seven installed payload
files matched the host build.

Toggling Wi-Fi OFF and ON switched the attached UGREEN adapter from
`0bda:1a2b` to `0bda:c811`, loaded `8821cu`, created `wlan0`, and obtained an
IPv4 address. A cold boot with the saved setting already ON exposed one final
gap: USB enumeration completed before the frontend-started uevent monitor, so
no add event remained to trigger recovery.

The final `1.0.1` correction keeps frontend startup non-blocking. After syncing
the monitor to a saved ON state, `plumos-wifi-recovery` now schedules one
background bounded recovery. Hot-plug event recovery remains unchanged and
coalesced by the existing lock.

## Final signed Runtime Update

The corrected archive replaced the provisional artifact while retaining the
public version `1.0.1` and compatibility route `1.0.0 -> 1.0.1`:

```text
path=dist/updates/plumos-v90s-runtime-1.0.1.tar.gz
size=571371
sha256=ff48b93aa6ee2d3b575f3e799a39f95bc0208b5baea67eb559416db8b7100d1e
package_type=runtime
source_version=1.0.0
version=1.0.1
full_payload=false
payload_files=8
payload_uncompressed_bytes=2465070
deleted_files=0
```

The payload contains only:

```text
VERSION
bin/plumos-network-control
bin/plumos-wifi-recovery
bin/plumos-wifi-uevent
checksums.sha256
licenses/network-services-manifest.txt
manifest.json
share/doc/network-services/SHA256SUMS
```

Rebuilt BusyBox and adbd outputs were deliberately excluded because they are
unrelated to this correction. The archive SHA-256 and public-key signature
passed verification. All 40 host tests passed, including saved-ON initial
recovery and saved-OFF suppression. An isolated clone of the `1.0.0` runtime
completed request, apply, and mark-healthy with all eight installed hashes
matching the final app layer and no pending state.

Physical cold-boot acceptance of this final archive remains pending because the
device already has the provisional package with the same public version.
