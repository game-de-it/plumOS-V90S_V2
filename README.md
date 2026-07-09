# plumOS-V90S_v2

POWKIDDY V90S 向けに、Armbian 系の userspace/rootfs を使った Linux SD カードイメージを作るための作業リポジトリです。

## Step 1 goal

まずは V90S 実機で SD カードから起動し、内蔵画面に Linux コンソールが表示され、USB キーボードで入力でき、`ls` などの基本コマンドを実行できる状態を目標にします。

## Current strategy

- V90S は KNULLI では `a133-powkiddy-v90s` ターゲットとして扱われています。
- KNULLI の V90S boot chain は `boot0.img`、`boot_package.fex`、Android boot image 形式の `boot.img`、FAT の boot-resource、SHARE 用 ext4 で構成されています。
- Step 1 では、V90S で実績のある KNULLI/stock 系 kernel と boot chain を温存し、Armbian 由来の aarch64 rootfs を squashfs として差し替える方針から始めます。
- mainline kernel / open U-Boot 化は、Step 1 の起動確認後の別トラックにします。

## Host status

この作業開始時点では Docker は利用可能でしたが、作業ディスクの空きが約 15GiB でした。KNULLI 公式の Docker ビルド要件は 180GB 超、Armbian も最低 50GB 級なので、フルビルド前に容量確保が必要です。

```sh
./scripts/check-host.sh
```

## Reference sources

参照ソースは `.cache/` 以下へ取得します。`.cache/` は git 管理外です。

```sh
./scripts/fetch-reference-sources.sh
./scripts/inspect-v90s-boot-chain.sh
```

Armbian build も取得したい場合:

```sh
./scripts/fetch-reference-sources.sh --with-armbian
```

## Image assembly prototype

`scripts/assemble-v90s-image.sh` は、KNULLI の V90S boot assets と任意の rootfs squashfs から SD カードイメージを組み立てるための試作スクリプトです。現時点では rootfs を作る処理は含みません。

```sh
./scripts/assemble-v90s-image.sh \
  --rootfs output/rootfs/armbian-v90s-step1.squashfs \
  --knulli-src .cache/knulli-linux \
  --out-dir output/images
```

`genimage` などのホストツールが必要です。

ホストに直接ツールを入れない場合は、アセンブリ用 Docker イメージを使います。

```sh
docker build -f docker/assembly-tools/Dockerfile -t plumos-v90s-assembly-tools .
./scripts/run-assembly-tools.sh sh -lc 'genimage --version && mksquashfs -version'
```

## Git workflow

作業履歴と判断ログは git に残します。調査・スクリプト・実機結果のまとまりごとに小さく commit します。
