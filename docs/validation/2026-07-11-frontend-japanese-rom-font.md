# V90S frontend Japanese ROM filename rendering

Date: 2026-07-11

## Goal

Fix mojibake/tofu-like rendering of Japanese ROM filenames in the V90S fbdev
frontend by following the plumOS MMF frontend font path.

## Change

- Added UTF-8 decoding to the V90S fbdev renderer.
- Added MMF-style kana dakuten/handakuten normalization.
- Added FreeType-backed font loading to the V90S fbdev renderer.
- Loaded the existing app-layer fonts from the controller UI:
  - `/mnt/plumos/fonts/default.otf`
  - `/mnt/plumos/fonts/cjk-fallback.ttc`
- Forced font rendering for ROM titles/details and gallery footer text, where
  user ROM filenames appear.
- Kept the built-in ASCII glyph route for lightweight UI labels.

## Build

```text
./scripts/docker-build.sh frontend
./scripts/docker-build.sh app-layer
```

Result:

```text
created: output/frontend/v90s
created: output/app-layer/v90s
version: 0.1.0-dev
compat_vendor: v90s-stockos-r1
mount_path: /mnt/plumos
```

The fbdev app-layer binary contains the FreeType path:

```text
FT_New_Face
fbdev renderer ready font=%.160s
plumos/fonts/cjk-fallback.ttc
```

Hashes:

```text
6ef19148e25e1e77ba2d43f9f6d29c0736274d0260e53440ec1810d7568394a8  output/app-layer/v90s/bin/plumos-controller-ui-fbdev
783bdf40891ca3df088e6d9a832fdc80ce81fe1f0db8716bd280bc86535b0c81  output/app-layer/v90s/fonts/default.otf
e4bca8df123ce01b104780f576ea1a58b9a5ff1662a91124b6d3180cb6c88212  output/app-layer/v90s/fonts/cjk-fallback.ttc
```

## Offscreen Render Check

Because the live V90S SSH endpoint was not reachable during this work, a small
Docker-side offscreen render test exercised the same fbdev text functions with
the bundled fonts.

Generated:

```text
output/validation/fbdev-japanese-rom-font.png
```

The test rendered these sample ROM names legibly:

```text
日本語ROMファイル名テスト
スーパーマリオブラザーズ.nes
ゼルダの伝説 - ハイラルファンタジー.nes
がんばれゴエモン！からくり道中.nes
```

## Live Device Status

Network scan results during this task:

```text
192.0.2.1
192.0.2.6
192.0.2.100
```

`192.0.2.100` accepted a TCP connection on port 22 but timed out during SSH
banner exchange, so it was not treated as a valid V90S SSH target. The previous
V90S address `192.0.2.120` was not reachable.

Live deploy and real `/dev/fb0` screenshot should be performed after V90S SSH is
reachable again.
