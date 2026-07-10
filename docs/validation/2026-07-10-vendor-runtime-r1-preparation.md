# V90S Vendor Runtime r1 Preparation

Date: 2026-07-10

## Purpose

Validate the policy-aligned vendor runtime preparation path for
`v90s-stockos-r1`.

## Commands

```sh
./scripts/prepare-stockos-runtime.sh
./scripts/docker-build.sh vendor-runtime
```

Both commands completed successfully.

The current workstation still has the original extraction at:

```text
artifacts/20260710-stockos-runtime
```

Because the policy-aligned input path does not yet exist locally, the prepare
script used the legacy source with an explicit warning and wrote the prepared
runtime to the new output path.

## Output

```text
prepared runtime: output/vendor/v90s-stockos-r1
compat alias:     output/vendor/stockos-runtime -> v90s-stockos-r1
manifest:         output/vendor/v90s-stockos-r1/vendor-runtime.manifest
size:             774M
```

## Hashes

```text
vendor-runtime.manifest  2a964177c9ffa6bcf23bcb29a17a32b957fc2acc2cb17c8cd9530de093357c7a
SHA256SUMS               8df2854e470f7d477e5eec2939401f190721bdf4704700c74770d7db571cff98
```

## Manifest Summary

```text
id=v90s-stockos-r1
captured_at=2026-07-10
kernel=Linux 4.9.191
boot_model=a133-b6
gpu=PowerVR GE8300
display_route=mali_fbdev
known_good_step2=yes
known_good_doc=docs/validation/2026-07-10-step2-stockos-video-perfect-runtime.md
```

## Notes

This is a host-side build-system validation only. It does not replace a
real-device SD image validation.
