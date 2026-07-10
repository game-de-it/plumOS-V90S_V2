# V90S Userland and Network Services Build

Date: 2026-07-11

## Purpose

Build plumOS-owned command-line tools and transfer services for the V90S app
layer. These payloads are placed under `/mnt/plumos` and are separate from the
StockOS-derived vendor runtime.

## Inputs

- A30 network service design was used as the reference shape.
- BusyBox source: `busybox-1.38.0.tar.bz2`
- BusyBox patch: `docker/plumos-v90s-toolchain/patches/busybox-1.38.0-ftpd-utf8-feat.patch`
- Service controller: `package/network-services/plumos/bin/plumos-network-services`
- Docker image: `plumos-v90s-toolchain:dev`

## Commands

```sh
./scripts/docker-build.sh image
./scripts/docker-build.sh userland
./scripts/docker-build.sh network-services
./scripts/docker-build.sh app-layer --strict
(cd output/userland/v90s && sha256sum -c checksums.sha256)
(cd output/network-services/v90s && sha256sum -c checksums.sha256)
(cd output/app-layer/v90s && sha256sum -c checksums.sha256)
docker run --rm -v "$PWD/output/userland/v90s:/out:ro" \
  plumos-v90s-toolchain:dev \
  sh -c '/out/plumos/bin/busybox --help | sed -n 1p'
```

## Outputs

```text
output/userland/v90s
output/network-services/v90s
output/app-layer/v90s
```

Sizes:

```text
17M  output/userland/v90s
94M  output/network-services/v90s
146M output/app-layer/v90s
```

Top-level checksum files:

```text
94f651518f6876d9dd931cce09805585634d59e151518b6e543a2262bd06eebf  output/userland/v90s/checksums.sha256
27ea9bfaf5ab75386ad6a8fb3aac6719a5651639fdc7186f1324c7c2d5261b48  output/network-services/v90s/checksums.sha256
3f8cf7807ef83df9f78df34617a72bb55d5e7a663836296ac6a32f94f51d7838  output/app-layer/v90s/checksums.sha256
639c8d3e766048985c7589ce5d17240080c67bbf5a428ce0f928817473c40f61  output/app-layer/v90s/manifest.json
```

## Validation

- `userland`, `network-services`, and `app-layer --strict` completed.
- All three `checksums.sha256` files verified.
- BusyBox runs inside the Docker Linux environment:

```text
BusyBox v1.38.0 (2026-07-10 15:42:32 UTC) multi-call binary.
```

- Key app-layer files are present:

```text
output/app-layer/v90s/bin/busybox
output/app-layer/v90s/bin/ftpd
output/app-layer/v90s/bin/tcpsvd
output/app-layer/v90s/bin/plumos-network-services
output/app-layer/v90s/gnu/bin/ip
output/app-layer/v90s/gnu/bin/rsync
output/app-layer/v90s/gnu/bin/ss
output/app-layer/v90s/gnu/bin/strace
output/app-layer/v90s/samba/sbin/smbd
output/app-layer/v90s/samba/sbin/nmbd
output/app-layer/v90s/ssh/libexec/sftp-server
output/app-layer/v90s/licenses/userland-manifest.txt
output/app-layer/v90s/licenses/network-services-manifest.txt
```

## Notes

- FTP uses BusyBox `tcpsvd` and `ftpd`.
- SFTP supplies `sftp-server`, but SSH itself stays system-rootfs managed.
- Samba exposes an `SDCARD` share with the app-layer controller defaulting to
  `/mnt/plumos` as the shared root.
- Service stop paths do not kill SSH. FTP/Samba stop paths use PID files and
  verify `/proc/<pid>/cmdline` or `/proc/<pid>/comm` before terminating
  processes.
