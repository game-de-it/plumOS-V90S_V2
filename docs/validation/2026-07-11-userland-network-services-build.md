# V90S Userland and Network Services Build

Date: 2026-07-11

## Purpose

Build plumOS-owned command-line tools and network services for the V90S app
layer. These payloads are placed under `/mnt/plumos` and are separate from the
StockOS-derived vendor runtime.

## Inputs

- A30 network service design was used as the reference shape.
- BusyBox source: `busybox-1.38.0.tar.bz2`
- BusyBox patch: `docker/plumos-v90s-toolchain/patches/busybox-1.38.0-ftpd-utf8-feat.patch`
- Service controller: `package/network-services/plumos/bin/plumos-network-services`
- SSH controller: `package/network-services/plumos/ssh/start-ssh.sh`
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
275f53938616b2f5a6a3b191ed97721f98bab4ffe37c0174d37eb3db1017eb1e  output/userland/v90s/checksums.sha256
073818d4ea66b71bb8f4bbf9e985521cf45a0a026139eefabe45dad4ae700172  output/network-services/v90s/checksums.sha256
d9f5b5595efb0b60c163b56f9e1eacaf73c159b8a5a6b3094e7235cd8ef1459a  output/frontend/v90s/checksums.sha256
9b2f2f0bb415c2507214cfc4d0dd28bf212b055ed6d5baf85ea208e56ef467c3  output/app-layer/v90s/checksums.sha256
ece01d04cd46a31379e5dcc91a81cb2d3491a129f1d68cedec054a12a59de989  output/app-layer/v90s/manifest.json
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
output/app-layer/v90s/ssh/start-ssh.sh
output/app-layer/v90s/ssh/stop-ssh.sh
output/app-layer/v90s/samba/sbin/smbd
output/app-layer/v90s/samba/sbin/nmbd
output/app-layer/v90s/ssh/libexec/sftp-server
output/app-layer/v90s/licenses/userland-manifest.txt
output/app-layer/v90s/licenses/network-services-manifest.txt
```

## Notes

- FTP uses BusyBox `tcpsvd` and `ftpd`.
- SSH is a `plumos-network-services` control target. V90S uses OpenSSH from the
  system rootfs, but the app-layer controller starts, adopts, stops, and reports
  the service.
- SSH login environments prefer `/mnt/plumos/bin` and then
  `/mnt/plumos/gnu/bin` in PATH.
- SFTP supplies `sftp-server` and depends on the same SSH service state.
- Samba exposes an `SDCARD` share with the app-layer controller defaulting to
  `/mnt/plumos` as the shared root.
- FTP/SSH/Samba stop paths use PID files and verify `/proc/<pid>/cmdline` or
  `/proc/<pid>/comm` before terminating processes. SFTP toggling does not stop
  SSH by itself.
