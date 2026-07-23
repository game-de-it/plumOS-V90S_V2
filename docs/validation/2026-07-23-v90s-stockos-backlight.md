# V90S StockOS Backlight Route

Date: 2026-07-23
Implementation commit: `eadf55c`
Host result: PASS
plumOS real-device result: pending

## Confirmed StockOS Reference

StockOS loads the following Linux 4.9.191 module:

```text
/lib/modules/4.9.191/sunxi-backlight.ko
sha256=ac6c0ece870c45fa8bd08de83a03a83263e779d4d4431ed4ab215a64b6db555c
```

After loading, StockOS controls:

```text
/sys/class/backlight/sunxi_backlight/brightness
max_brightness=255
levels=1,51,102,153,204,255
```

`enhance_bright` remained at 50 while the StockOS brightness levels changed.
This proves that panel backlight and display Lumination are independent
controls.

## Implemented Contract

The generated System init checks the sysfs endpoint after mounting sysfs and
before starting the app layer. It tries `modprobe sunxi_backlight`, then falls
back to `insmod /lib/modules/$(uname -r)/sunxi-backlight.ko`. An already
available endpoint is left unchanged. Load result, current brightness,
`max_brightness`, and writability are written to the boot log.

`plumos-display-control` now owns `brightness=1..6`:

| Setting | Raw backlight |
| ---: | ---: |
| 1 | 1 |
| 2 | 51 |
| 3 | 102 |
| 4 | 153 |
| 5 | 204 |
| 6 | 255 |

The helper retains `apply`, `up`, `down`, `runtime-up`, `runtime-down`,
`persist-runtime`, `get`, and `status`. It can load the module itself for an
app-layer-only update. Existing saved brightness values above 6 migrate to 6.
It never writes `lumination` or `enhance_bright`.

The global hardware-key service routes `SELECT + volume` to this helper and
logs `display-brightness`. Normal volume processing is unchanged. The V90S
frontend recognizes the helper/sysfs route as the formal Brightness backend,
shows and persists `1..6`, and keeps Lumination on `enhance_bright`.

## Automated Validation

The fake-sysfs test covers:

- all six setting/raw mappings
- upper and lower bounds
- runtime coalescing and persistent JSON update
- preserving `lumination` while brightness changes
- migration from saved brightness 10 to 6
- no module reload when the endpoint already exists
- `modprobe` before `insmod` when the endpoint is absent

```text
python3 -m unittest discover -s tests -p 'test_*.py' -v
Ran 32 tests
OK
```

The frontend cross-build, strict app-layer assembly, license audit, and System
SquashFS build passed. Independent SquashFS extraction confirmed:

```text
system_version=1.0.0
sunxi-backlight.ko_sha256=ac6c0ece870c45fa8bd08de83a03a83263e779d4d4431ed4ab215a64b6db555c
init_backlight_load=present
```

Final app-layer hashes:

```text
8f9f3576c91a685382812a3abc6fee0b78605f92a5a48f147e36cdefaeedf3e2  bin/plumos-display-control
ea4eb311bd32af6891acfe0a7ae71dfee25321371bd958e5dc629c334cdafbdb  bin/plumos-hardware-keys
5fe389a059777324afb2e3d8d5c9dcebb7212a5faf2f456af2126ef52a73dc3e  bin/plumos-controller-ui-fbdev
```

## Release Image

```text
path=output/images/plumos-v90s-release-1.0.0-vendor-r1.img
size=2840088576
sha256=ded3c2db2439bab6e2595ba12d218ec160b8e046c64a327ec0fe23356c854ea9
verification=PASS
```

## Required Physical Validation

This host result does not claim that the exact image has passed hardware
validation. After flashing, confirm:

- `sunxi_backlight` is present in `/proc/modules`
- the backlight brightness file exists and is writable
- `SELECT + volume` traverses `1,51,102,153,204,255`
- level 1 remains dimly visible instead of turning the display off
- Lumination still changes `enhance_bright` independently
- the hotkey works in FE, RetroArch, PicoArch, standalone, and Apps
