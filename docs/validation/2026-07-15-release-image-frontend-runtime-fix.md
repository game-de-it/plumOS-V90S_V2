# 2026-07-15 Release Image Frontend Runtime Fix

## Device Result

The second release-system image still displayed only the boot logo:

```text
output/images/plumos-v90s-system-squashfs-20260715-2.img
```

ADB and SSH were unavailable. After attaching the SD card to macOS, p7
contained current boot logs. `Logs/frontend.log` proved that the vendor boot
chain, release-system init, p7 app-layer mount, and SD2 mount all succeeded.

The frontend process then failed with:

```text
/mnt/plumos/bin/plumos-controller-ui-fbdev: error while loading shared libraries:
libpng16.so.16: cannot open shared object file: No such file or directory
```

The library was already present under `/mnt/plumos/lib`; the launcher did not
provide a FAT32 app-layer library path. ADB and Wi-Fi state alone therefore did
not prove an early boot failure in this release profile.

## Fix

The frontend build now packages only its required non-system runtime libraries
under:

```text
/mnt/plumos/frontend/lib/libpng16.so.16
/mnt/plumos/frontend/lib/libfreetype.so.6
/mnt/plumos/frontend/lib/libbrotlidec.so.1
/mnt/plumos/frontend/lib/libbrotlicommon.so.1
```

`plumos-controller-ui-v90s` prepends that dedicated directory to
`LD_LIBRARY_PATH`. It does not prepend the generic app-layer library directory,
so unrelated emulator copies of libc cannot override the system rootfs.

The strict app-layer build and rootfs bootstrap now require and checksum the
wrapper and all four runtime libraries. The rootfs init log is also copied to
`/mnt/plumos/Logs/plumos-v90s-debian-init.log` after p7 becomes available.

## Validation

The frontend dynamic loader was run inside an extracted release-system rootfs.
It resolved PNG and FreeType from `/mnt/plumos/frontend/lib`, while resolving
libc, libm, and zlib from the system rootfs.

Corrected image:

```text
image: output/images/plumos-v90s-system-squashfs-20260715-3.img
image sha256: da71786bd994f85d388f006e76b577570630d44995aaa857a84a4bfe04ea35ae
p5 sha256: ebd57859384c055458a25ad6a02cd14f057aaf465d5741376005aad7683d2438
```

Host validation confirmed p1/p7 FAT integrity, all p7 checksums, the raw p5
hash, and the four frontend runtime files. The tested `-2` SD was also patched
with the same wrapper and libraries and safely unmounted for a quick device
retest without rewriting the whole image.

Real-device frontend display after this runtime fix remains to be confirmed.
