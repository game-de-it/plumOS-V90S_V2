# Live-Bootchain 1GB FAT32 App-Layer Image

Date: 2026-07-11

## Goal

Build a V90S development SD image whose user-visible `SHARE` partition is large
enough to carry the full generated plumOS app layer.

The target change is:

```text
p7 rootfs_data / SHARE FAT32, 1024M
```

## Important Boot-Chain Boundary

The prepared `output/vendor/v90s-stockos-r1` runtime still does not include raw
StockOS `boot0` and `boot_package` captures:

```text
error: StockOS raw boot0 capture not found:
output/vendor/v90s-stockos-r1/raw-boot-chain/boot0-offset-131072.bin
```

The assembler correctly stops without `--allow-knulli-boot-fallback`.

For this image, the boot-chain areas were captured from the currently booted
live V90S development image at `root@192.0.2.120` and passed explicitly with
`--boot0` and `--boot-package`. This is useful for testing the FAT32 app-layer
layout, but it is not yet proof of a pure StockOS raw boot-chain capture.

Captured live boot-chain hashes:

```text
638d5d75f9d348a4fbcadb901a2c102fd88148900c3d186acc7ae6d4095784c4  output/device-live/raw-boot-chain/boot0-live.bin
15819caa0045aa6064d98c986bcfce33104286ddc6ea4fe2427eb5d46e64f869  output/device-live/raw-boot-chain/boot-package-live.bin
```

`boot0-live.bin` matches the current KNULLI V90S fallback `boot0.img`.
`boot-package-live.bin` did not match the current KNULLI fallback
`boot_package.fex` and should be treated as a live development boot-package
capture until its source is identified.

## Build

Command:

```sh
./scripts/docker-build.sh sd-image \
  --boot0 output/device-live/raw-boot-chain/boot0-live.bin \
  --boot-package output/device-live/raw-boot-chain/boot-package-live.bin \
  --app-layer-dir output/app-layer/v90s \
  --share-size 1024M \
  --keep-work \
  --name plumos-v90s-liveboot-appfat-1g-20260711-1.img
```

Output:

```text
output/images/plumos-v90s-liveboot-appfat-1g-20260711-1.img
output/images/plumos-v90s-liveboot-appfat-1g-20260711-1.img.manifest.txt
```

Image hash:

```text
fabbaf8532e13e490e7a3af472b147362b9f7a5deb7bdad5883723563d2e6369
```

Manifest excerpts:

```text
allow_knulli_boot_fallback=0
boot0_source=explicit
boot0_sha256=638d5d75f9d348a4fbcadb901a2c102fd88148900c3d186acc7ae6d4095784c4
boot_package_source=explicit
boot_package_sha256=15819caa0045aa6064d98c986bcfce33104286ddc6ea4fe2427eb5d46e64f869
share_size=1024M
app_layer_manifest_sha256=28639f16f7ba7ca6ea923aa33a11d452c6502da576f07cd08b63afb4921480fb
partitions=p1:boot-resource/Volumn,p2:env,p3:env-redund,p4:boot,p5:batocera,p6:rootfs/BATOCERA,p7:rootfs_data/SHARE-FAT32
```

## Partition Table

Docker/Linux `fdisk -l` reports:

```text
Disk output/images/plumos-v90s-liveboot-appfat-1g-20260711-1.img: 1.15 GiB, 1234972672 bytes, 2412056 sectors

Device                                                        Start     End Sectors  Size Type
output/images/plumos-v90s-liveboot-appfat-1g-20260711-1.img1  41984  109567   67584   33M Microsoft basic data
output/images/plumos-v90s-liveboot-appfat-1g-20260711-1.img2 109568  110079     512  256K Linux filesystem
output/images/plumos-v90s-liveboot-appfat-1g-20260711-1.img3 110080  110591     512  256K Linux filesystem
output/images/plumos-v90s-liveboot-appfat-1g-20260711-1.img4 110592  241663  131072   64M Linux filesystem
output/images/plumos-v90s-liveboot-appfat-1g-20260711-1.img5 241664  247279    5616  2.7M Linux filesystem
output/images/plumos-v90s-liveboot-appfat-1g-20260711-1.img6 247280  314863   67584   33M Linux filesystem
output/images/plumos-v90s-liveboot-appfat-1g-20260711-1.img7 314864 2412015 2097152    1G Microsoft basic data
```

## FAT32 App-Layer Verification

The p7 FAT32 volume can be inspected with `mtools` at offset
`314864 * 512 = 161210368`.

Root listing excerpt:

```text
Volume in drive : is SHARE
BIOS         <DIR>
Roms         <DIR>
Saves        <DIR>
Screenshots  <DIR>
States       <DIR>
bin          <DIR>
config       <DIR>
cores        <DIR>
frontend     <DIR>
gnu          <DIR>
lib          <DIR>
licenses     <DIR>
manifest.json
checksums.sha256
picoarch     <DIR>
samba        <DIR>
ssh          <DIR>
standalone   <DIR>
themes       <DIR>
updates      <DIR>
```

The FAT32 contents were copied back out of p7 and validated with the embedded
app-layer checksum file:

```text
146M  /tmp/plumos-p7-verify
sha256sum -c checksums.sha256: OK
28639f16f7ba7ca6ea923aa33a11d452c6502da576f07cd08b63afb4921480fb  manifest.json
3438ce8598374979fb1d42e4ff673cb512a1d567099af76f5f80479986223b10  checksums.sha256
```

Read-only FAT check:

```text
fsck.fat 4.2 (2021-01-31)
/tmp/plumos-p7.vfat: 1075 files, 37351/261627 clusters
```

## Result

Host-side image generation and FAT32 app-layer verification passed.

Real-device result:

```text
Boot logo did not proceed.
```

This image is superseded by:

```text
docs/validation/2026-07-11-appfat-boot-logo-stall-fix.md
output/images/plumos-v90s-appfat-1g-20260711-2.img
```

The cause was not the p7 FAT32 filesystem itself. The image accidentally used
the old default `stage1-userdata-loader.squashfs` because `--rootfs-squashfs`
was not specified with `--app-layer-dir`.

Real-device validation is still required:

- p7 FAT32 must mount at `/mnt/plumos`
- frontend must start from the app layer
- RetroArch launch, input, video pacing, and audio must remain known-good
- logs/configs should be visible from macOS or Windows after shutdown
