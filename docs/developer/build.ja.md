# Dockerビルドガイド

## 必要環境

- Git
- AArch64ソースとイメージ用の空き容量があるDocker
- `artifacts/vendor/v90s-stockos-r1/`のvendor入力
- 公式アップデートを生成する場合だけrelease署名鍵

すべてのtargetは`scripts/docker-build.sh`から実行します。Docker imageの初期値は
`plumos-v90s-toolchain:dev`、対象platformは`linux/arm64`です。

## Docker imageとtargetの確認

```sh
./scripts/docker-build.sh image
./scripts/docker-build.sh --help
./scripts/docker-build.sh shell
```

`artifacts/`は入力専用でgit管理外です。生成物は同じくgit管理外の`output/`または
`dist/`へ出します。ビルドスクリプト、レシピ、バージョン固定、パッチ、manifest
schema、公開更新鍵は追跡します。

## component target

```sh
./scripts/docker-build.sh vendor-runtime
./scripts/docker-build.sh boot-package
./scripts/docker-build.sh boot-image
./scripts/docker-build.sh sdl2-powervr
./scripts/docker-build.sh retroarch
./scripts/docker-build.sh cores
./scripts/docker-build.sh picoarch
./scripts/docker-build.sh standalone
./scripts/docker-build.sh userland
./scripts/docker-build.sh network-services
./scripts/docker-build.sh audio-router
./scripts/docker-build.sh nextcommander
./scripts/docker-build.sh music-player
./scripts/docker-build.sh pyxel-runtime
./scripts/docker-build.sh portmaster
./scripts/docker-build.sh frontend
```

全体を再ビルドせず、スタンドアローンを個別指定できます。

```sh
./scripts/docker-build.sh standalone ppsspp
./scripts/docker-build.sh standalone yabasanshiro
```

正式なcore出力は`output/libretro-cores/v90s/`です。filter buildは
`output/libretro-cores/v90s-filtered/<filter>`へ出し、release用正式setを置き換えません。
coreのsource URL、ref、class、build directory、引数は
`docker/plumos-v90s-toolchain/libretro-core-recipes.tsv`で固定します。

## 主な出力

| target | 出力 |
| --- | --- |
| `vendor-runtime` | `output/vendor/v90s-stockos-r1/` |
| `sdl2-powervr` | `output/sdl2-powervr/` |
| `retroarch` | `output/retroarch-powervr/` |
| `cores` | `output/libretro-cores/v90s/` |
| `picoarch` | `output/picoarch/v90s/` |
| `standalone` | `output/standalone-emulators/v90s/` |
| `frontend` | `output/frontend/v90s/` |
| `userland` | `output/userland/v90s/` |
| `network-services` | `output/network-services/v90s/` |
| `audio-router` | `output/audio-router/v90s/` |
| `pyxel-runtime` | `output/pyxel-runtime/v90s/` |
| `portmaster` | `output/portmaster/v90s/` |
| `system-rootfs` | `output/system-rootfs/v90s/` |
| `app-layer` | `output/app-layer/v90s/` |

## RuntimeとSystemの組み立て

```sh
PLUMOS_V90S_APP_LAYER_VERSION=VERSION \
  ./scripts/docker-build.sh app-layer --strict

PLUMOS_V90S_SYSTEM_VERSION=VERSION \
  ./scripts/docker-build.sh system-rootfs

./scripts/docker-build.sh license-audit output/app-layer/v90s
./scripts/docker-build.sh preflight
```

strict app-layerは、対応payload一式、正式core数、RetroArch・PPSSPP factory設定、
notice、license、component manifestを必須にします。`VERSION`、`COMPAT_VENDOR`、
`RUNTIME_ABI`、`manifest.json`、`checksums.sha256`を生成します。releaseでは
`manifest.json.complete`がtrue、`missing_optional`が空でなければなりません。

## seed imageの生成と検査

```sh
./scripts/docker-build.sh sd-image \
  --name plumos-v90s-four-partition-seed.img

./scripts/docker-build.sh verify-image \
  --image output/images/plumos-v90s-four-partition-seed.img
```

`sd-image`は組み立て前に4パーティションpreflightを実行します。preflightはboot入力、
partition容量、System A/B hash、p3 app-layer metadata、SD2 mount tool、FE起動、更新tool、
network service、USB Disk Mode、license、checksumを検査します。

`stockos-image`と`knulli-image`は明示的な過去調査用経路で、通常release targetではありません。

## 署名付きアップデート

公式packageは、古いcopy-over用`release` archiveではなく`update-package`を使います。

```sh
./scripts/docker-build.sh update-package \
  --type runtime \
  --input output/app-layer/v90s \
  --base-dir PATH/TO/PREVIOUS/RUNTIME \
  --base-version OLD --version NEW \
  --output-dir dist/updates

./scripts/docker-build.sh update-package \
  --type system \
  --input output/system-rootfs/v90s/plumos-v90s-system-rootfs.squashfs \
  --base-version OLD --version NEW \
  --output-dir dist/updates
```

Ed25519秘密鍵はgit管理外の`artifacts/update-signing/`へ置きます。追跡するのは
`package/system-v90s/`の公開鍵だけです。[アップデート契約](../plumos-v90s-update-contract.md)
も参照してください。

## PortMaster監査

```sh
PLUMOS_PORTMASTER_AUDIT_JOBS=4 \
  ./scripts/docker-build.sh portmaster-audit
```

静的監査は、公式AArch64 Port metadata、起動script、ELF architecture、interpreter、
`DT_NEEDED` library、runtime-family marker、未解決ABIを一覧化します。経路判断と
package準備の検査であり、実機の映像、音声、入力、save、終了確認の代わりではありません。

## 実機デプロイ規則

`scripts/deploy-app-layer-adb.sh`または同等のmetadata対応経路を使います。管理binaryを
単独で送ってはいけません。対応するchecksum entryとmanifestを原子的に更新し、再起動前に
実機で検査します。実機所有の変更可能パスはすべて保持します。
