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

`scripts/assemble-v90s-image.sh` は、KNULLI の V90S boot assets と任意の rootfs squashfs から SD カードイメージを組み立てるための試作スクリプトです。rootfs 生成は別スクリプトで行います。

```sh
./scripts/assemble-v90s-image.sh \
  --rootfs output/rootfs/armbian-v90s-step1.squashfs \
  --knulli-src .cache/knulli-linux \
  --out-dir output/images \
  --boot-vfat-size 33M \
  --userdata-size 64M
```

`genimage` などのホストツールが必要です。

KNULLI の元設定は boot-resource FAT を数GB確保しますが、このプロジェクトの反復テストでは不要なので、組み立てスクリプトのデフォルトは `--boot-vfat-size 33M`、`--userdata-size 64M` にしています。30MB/32MB は KNULLI 元設定の FAT32 指定では `mtools` がディレクトリを作れず失敗したため、実測で通る最小値の 33MB を使います。Armbian rootfs が 33MB に収まらない段階では、FAT を大きくするよりも rootfs を別 partition に置く方向で調整します。

ホストに直接ツールを入れない場合は、アセンブリ用 Docker イメージを使います。

```sh
docker build -f docker/assembly-tools/Dockerfile -t plumos-v90s-assembly-tools .
./scripts/run-assembly-tools.sh sh -lc 'genimage --version && mksquashfs -version'
```

## Step 1 Debian minbase image

最初の Armbian 方向の boot proof として、Debian Bookworm arm64 minbase rootfs を使った小さい console image を作ります。FAT には 3MB 程度の stage1 squashfs だけを置き、42MB 程度の Debian rootfs payload は userdata ext4 に置きます。

```sh
./scripts/run-assembly-tools.sh ./scripts/build-step1-rootfs.sh \
  --out-dir output/rootfs-step1

./scripts/run-assembly-tools.sh ./scripts/assemble-v90s-image.sh \
  --rootfs output/rootfs-step1/stage1-userdata-loader.squashfs \
  --userdata-payload output/rootfs-step1/debian-bookworm-minbase-step1.squashfs \
  --out-dir output/images \
  --name plumos-v90s-armbian-step1-20260709-5-diag-mount-probe.img \
  --userdata-size 64M \
  --boot-cmdline 'loglevel=8 ignore_loglevel initcall_debug=0 console=tty0 console=ttyS0,115200 rootwait root=/dev/mmcblk0p4 init=/sbin/init elevator=noop' \
  --diagnostic-init
```

実機確認用の現在の成果物は `output/images/plumos-v90s-armbian-step1-20260709-5-diag-mount-probe.img` です。

```text
sha256: c4c600696276c550d3be36b0fa83b039221a462e796ad1ccb72ca1e6120e2089
size: 133M
```

`-1` と `-2` は実機で KNULLI boot logo までは表示されましたが、その先の console には進みませんでした。`-3-diag` では FAT にログは出ませんでしたが、userdata ext4 に `plumos-v90s-diag.log` が残り、kernel が Linux 4.9.191 として起動して診断 initramfs `/init` まで到達していることを確認できました。

`-3-diag` のログでは `/dev/mmcblk0p4` の FAT boot-resource から `/boot/knulli` を見つけたあと、squashfs ファイルを直接 mount しようとして失敗していました。`-4-diag-loop` は `/boot/knulli` を `/dev/loop0` に割り当ててから squashfs として mount しましたが、実機では `/dev/loop0` の squashfs mount に失敗しました。

`-5-diag-mount-probe` は KNULLI 元 initramfs と同じ直接 file mount を先に試し、失敗時は `-o loop`、明示 `losetup`、loop device mount を順に試して詳細ログを残します。Debian minbase payload も gzip squashfs に作り直してあります。

`-5-diag-mount-probe` を実機で 60 秒ほど起動した後、console が出ない場合は SD をホストへ戻して FAT partition の `plumos-v90s-diag.log` / `boot/plumos-v90s-diag.log`、または userdata ext4 の `rootfs/plumos-v90s-diag.log` を確認します。

## Git workflow

作業履歴と判断ログは git に残します。調査・スクリプト・実機結果のまとまりごとに小さく commit します。
