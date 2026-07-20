# V90S PortMaster Common ABI Adapter v9

## Purpose

Implement the common ABI that passed the full AArch64 audit review and encode
the ownership boundary for the repeated candidates that must not be global.

## Build Result

- PortMaster adapter: version 9
- Added ABI: GNU Readline 7.0, `libreadline.so.7`
- Source SHA-256:
  `750d437185286f40a369e1e4f4764eda932b9459b5ec9a731628393dd3d32334`
- ELF machine: AArch64
- ELF SONAME: `libreadline.so.7`
- ELF dependencies: `libc.so.6`, `libtinfo.so.6`
- Runtime projection: `/run/plumos/portmaster/lib/libreadline.so.7`

The PortMaster package and strict app-layer checksum manifests both verify in
full after the build.

```text
2065c95dad06f2a32c0b915bc0caa7921ba03e0fe9318a7feb046ae89138ae9c  libreadline.so.7
6457f2a48aac0182f6f61fff6b1da45bdd51ff4f932d78f3360690eb04fc2dc5  PortMaster checksums.sha256
63637cd1efb596a2c6fef5b8ee97279d19a85b094c4ed258f46cba1377359918  app-layer checksums.sha256
ea3764b7b7446ea4c6329db63c63cf54fe990175f81f3934332ad1e6d451759a  audit checksums.sha256
```

## Complete Audit Result

The cached 24.02 GiB catalog payload set was rescanned offline:

- Catalog ports: 1,332
- AArch64 candidates audited: 1,126 of 1,126
- Missing SONAMEs: 21, reduced from 22
- Wizznic: `static-pass`
- Yatka: `static-pass`
- Protected target-contract failures: 0

The remaining repeated candidates now carry explicit policy rather than a
frequency-only common-ABI label. The audit contract and output schema are
version 2; `missing-libraries.tsv` records the classification, owner, and
handling decision for every unresolved SONAME:

| ABI | plumOS handling |
| --- | --- |
| `libGL.so.1` | `runtime-owned`, Weston/GL4ES |
| `libXxf86vm.so.1` | `runtime-owned`, Weston X11 |
| `libcrypto.so.1.1` | `isolated-compat`, owning port/runtime |
| `libssl.so.1.1` | `isolated-compat`, owning port/runtime |
| `libjawt.so` | `runtime-owned`, Java |
| `libsndio.so.7.0` | `runtime-owned`, Weston/Java audio |
| `librga.so.2` | `unsupported-hardware`, Rockchip RGA |

This work proves loader dependency closure only. Wizznic and Yatka still need
real-device video, audio, controls, performance, and clean-exit validation.
The runtime-owned and isolated candidates remain unavailable until their exact
runtime packages are separately implemented and validated on V90S.
