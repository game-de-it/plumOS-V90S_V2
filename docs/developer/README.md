# plumOS V90S Developer Guide

This guide is the technical entry point for building, modifying, deploying, and
releasing plumOS V90S. The user manual is intentionally separate.

## Start Here

1. [Architecture and ownership](architecture.md)
2. [Docker build guide](build.md)
3. [Boot and runtime services](runtime.md)
4. [Storage and updates](storage-and-updates.md)
5. [Frontend and emulator integration](frontend-emulators.md)
6. [Hardware integration](hardware-services.md)
7. [Validation and evidence index](validation.md)
8. [Distribution policy](../plumos-v90s-distribution-policy.md)
9. [Update contract](../plumos-v90s-update-contract.md)
10. [Update workflow](../update-workflow.md)

## Repository Map

```text
docker/plumos-v90s-toolchain/  reproducible AArch64 build environment,
                              recipes, pins, and V90S patches
package/                       tracked app, service, runtime, and factory payloads
scripts/                       build, assembly, deployment, boot, and audit tools
docs/user/                     end-user operating manual
docs/developer/                current technical guide
docs/research/                 upstream and hardware research
docs/validation/               dated build and physical-device evidence
artifacts/                     ignored input-only vendor and private content
output/                        ignored intermediate products
dist/                          ignored release packages
```

## Non-Negotiable Contracts

- V90S is the only target. Do not generalize hardware code at the expense of
  its known runtime.
- `v90s-stockos-r1` owns bootloader, Linux 4.9.191, matching modules, PowerVR
  GE8300 userspace, low-level ALSA, and hardware input support.
- plumOS owns the read-only System SquashFS, p3 app/runtime, p4 user data,
  frontend, emulators, services, configuration policy, and update engine.
- `/mnt/plumos` is the stable writable runtime ABI. `/mnt/plumos-user` is the
  host-readable p4 user volume. `/mnt/plumos-boot` is normally read-only.
- Only one foreground owner may hold the framebuffer/input presentation path.
  FE launchers must stop or suspend FE ownership before an emulator or app and
  restore it after the child exits.
- App-layer deployments are atomic metadata units. Deploy managed files with
  matching `checksums.sha256`, `manifest.json`, and component manifests; verify
  SHA-256 before restart.
- Never overwrite device-owned settings, saves, PortMaster content, credentials,
  or SSH state to make a live device match host metadata.
- ROMs, BIOS files, secrets, and vendor extraction inputs stay outside git.
- Release payloads include the MIT license, third-party notices, component
  licenses, manifests, and checksums.

## Canonical Technical References

- [Distribution policy](../plumos-v90s-distribution-policy.md): complete adopted
  design and hardware policy
- [Update contract](../plumos-v90s-update-contract.md): signed transactional
  Runtime and A/B System updates
- [Storage redesign](../v90s-ext4-runtime-fat32-userdata-update-design.md):
  ext4/FAT32 rationale and migration decisions
- [Docker build plan](../v90s-docker-build-plan.md): build-system history and
  target evolution
- [Step 1 boot plan](../step1-boot-console-plan.md): early boot and framebuffer
  console route
- [Step 2 runtime plan](../step2-knulli-runtime-armbian-plan.md) and
  [RetroArch plan](../step2-retroarch-plan.md): historical bring-up rationale

The dated files under `docs/validation/` are evidence, not user documentation
and not automatically current policy. When evidence conflicts with an adopted
contract, the distribution policy and current source take precedence.

## Japanese

- [日本語版開発者ガイド](README.ja.md)
