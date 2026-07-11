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
- Added V90S app-layer direct font candidates:
  - `fonts/default.otf`
  - `fonts/cjk-fallback.ttc`

The direct `fonts/` candidates are required because V90S mounts the app layer
itself at `/mnt/plumos`. The MMF-style `plumos/fonts/...` candidates are still
kept as compatibility candidates for layouts where the SD root contains a nested
`plumos/` directory.

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
4b3b096087fb5f8e5db3bd2580b640d4abb6c22868e0b851c4d7e638a5ebf898  output/app-layer/v90s/bin/plumos-controller-ui-fbdev
783bdf40891ca3df088e6d9a832fdc80ce81fe1f0db8716bd280bc86535b0c81  output/app-layer/v90s/fonts/default.otf
e4bca8df123ce01b104780f576ea1a58b9a5ff1662a91124b6d3180cb6c88212  output/app-layer/v90s/fonts/cjk-fallback.ttc
```

## Offscreen Render Check

A small Docker-side offscreen render test exercised the same fbdev text
functions with the bundled fonts.

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

## Live Device Deployment

Device:

```text
ssh root@192.0.2.120
```

Deployment:

```text
scp output/app-layer/v90s/bin/plumos-controller-ui-fbdev \
  root@192.0.2.120:/tmp/plumos-controller-ui-fbdev.new
/mnt/plumos/bin/plumos-frontend-stop stop
mv /tmp/plumos-controller-ui-fbdev.new /mnt/plumos/bin/plumos-controller-ui-fbdev
chmod 0755 /mnt/plumos/bin/plumos-controller-ui-fbdev
nohup env PLUMOS_ROOT=/mnt/plumos PLUMOS_SDCARD_ROOT=/mnt/plumos \
  /mnt/plumos/bin/plumos-frontend-launch &
```

Device hash after deploy:

```text
4b3b096087fb5f8e5db3bd2580b640d4abb6c22868e0b851c4d7e638a5ebf898  /mnt/plumos/bin/plumos-controller-ui-fbdev
```

Font load proof from the live framebuffer status line:

```text
FBDEV RENDERER READY FONT=/MNT/PLUMOS/FONTS/DEFAUL...
```

Captured framebuffer PNGs:

```text
output/validation/plumos-fb0-fontpath-page0.png
output/validation/plumos-fb0-jp-roms-font3-page0.png
```

`plumos-fb0-jp-roms-font3-page0.png` shows Japanese NES ROM titles rendered
legibly in the ROM list and preview panel:

```text
つっぱり大相撲
アイスクライマー
アトランチスの謎
イー・アル・カンフー
エキサイトバイク
ギャラガ
グラディウス
スーパーマリオUSA
```

The live ROM cache also retained valid UTF-8:

```text
roms 86 non_ascii 26 square_titles 0
```
