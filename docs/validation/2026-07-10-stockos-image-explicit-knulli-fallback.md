# StockOS Image Explicit KNULLI Boot Fallback

Date: 2026-07-10

## Purpose

Validate that StockOS-layout image assembly no longer uses KNULLI `boot0` and
`boot_package` assets implicitly when the prepared `v90s-stockos-r1` vendor
runtime lacks raw StockOS boot-chain captures.

## Expected Failure

Command:

```sh
./scripts/docker-build.sh sd-image --name plumos-v90s-test-no-fallback.img
```

Result:

```text
error: StockOS raw boot0 capture not found: output/vendor/v90s-stockos-r1/raw-boot-chain/boot0-offset-131072.bin
hint: extract raw boot-chain captures or pass --allow-knulli-boot-fallback for a legacy diagnostic image
```

This is the expected behavior. A normal StockOS-layout image should not silently
fall back to KNULLI boot assets.

## Explicit Fallback Build

Command:

```sh
./scripts/docker-build.sh sd-image \
  --allow-knulli-boot-fallback \
  --name plumos-v90s-test-knulli-fallback.img
```

Result:

```text
image:    output/images/plumos-v90s-test-knulli-fallback.img
size:     218M
sha256:   b6005f0d184b0293fcedb3e1a7e1e6032208713b43bf22d199b8a3a33b7dfc20
manifest: output/images/plumos-v90s-test-knulli-fallback.img.manifest.txt
```

Manifest hash:

```text
3cef66668d59e87ee91ad0006214ae4bcdbabc770b750249b35126847fd67941
```

Relevant manifest fields:

```text
vendor_runtime_id=v90s-stockos-r1
boot0_source=knulli-fallback
boot_package_source=knulli-fallback
allow_knulli_boot_fallback=1
```

## Notes

This is a host-side assembler validation only. It does not replace a real-device
boot test.
