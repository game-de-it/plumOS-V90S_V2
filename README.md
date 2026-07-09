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
  --name plumos-v90s-armbian-step1-20260709-15-fb-text-fat-logs.img \
  --userdata-size 64M \
  --boot-cmdline 'loglevel=8 ignore_loglevel initcall_debug=0 console=tty0 console=ttyS0,115200 rootwait root=/dev/mmcblk0p4 init=/sbin/init elevator=noop' \
  --diagnostic-init \
  --keep-work
```

実機確認用の現在の成果物は `output/images/plumos-v90s-armbian-step1-20260709-15-fb-text-fat-logs.img` です。

```text
sha256: f26b6391af990a7b4637054d5558d3794fd50250674fb3b9ec68ed94e1d52f24
size: 133M
```

`-1` と `-2` は実機で KNULLI boot logo までは表示されましたが、その先の console には進みませんでした。`-3-diag` では FAT にログは出ませんでしたが、userdata ext4 に `plumos-v90s-diag.log` が残り、kernel が Linux 4.9.191 として起動して診断 initramfs `/init` まで到達していることを確認できました。

`-3-diag` のログでは `/dev/mmcblk0p4` の FAT boot-resource から `/boot/knulli` を見つけたあと、squashfs ファイルを直接 mount しようとして失敗していました。`-4-diag-loop` は `/boot/knulli` を `/dev/loop0` に割り当ててから squashfs として mount しましたが、実機では `/dev/loop0` の squashfs mount に失敗しました。

`-5-diag-mount-probe` は KNULLI 元 initramfs と同じ直接 file mount を先に試し、失敗時は `-o loop`、明示 `losetup`、loop device mount を順に試しました。実機ログでは `/boot/knulli` の読み取りと loop attach は成功していましたが、gzip squashfs の mount がすべて `Invalid argument` で失敗しました。

`-6-diag-zstd` は KNULLI a133 の `BR2_TARGET_ROOTFS_SQUASHFS4_ZSTD=y` に合わせ、stage1 と Debian minbase payload を zstd squashfs にしました。実機ログでは `/boot/knulli` が KNULLI-style file mount で stage1 root として mount できました。これにより、前段の squashfs mount 問題は zstd で突破できたことを確認しています。

一方で画面は KNULLI boot logo のままでした。参照した V90S/KNULLI kernel config では `CONFIG_VT_CONSOLE=y` ですが `# CONFIG_FRAMEBUFFER_CONSOLE is not set` なので、`console=tty0` だけでは内蔵 LCD に Linux text console が出ない可能性が高いです。

`-7-stage1-fb-probe` は、stage1 と Debian init のログを userdata に残し、`/dev/fb0` へ直接 white band を書く probe を追加しています。また、diagnostic initramfs が `/dev/loop0` を使って stage1 を mount するため、stage1 側の Debian payload は `/dev/loop1` で mount します。

`-7-stage1-fb-probe` の実機ログでは、diagnostic initramfs が stage1 root までは mount しましたが、stage1/Debian のログは出ませんでした。host inspection で stage1 `/sbin/init` が `#!/bin/sh` なのに stage1 rootfs に `/bin/sh` がないことが分かったため、`-8-stage1-sh-prepersist` では `/bin/sh -> busybox` を追加し、framebuffer probe より前に stage1 到達ログを保存するようにしています。

`-8-stage1-sh-prepersist` の実機ログでは、diagnostic initramfs が `boot: preparing to switch to stage1 /sbin/init` まで到達しましたが、stage1/Debian のログはまだ出ませんでした。`-9-stage1-share-handoff` では diagnostic initramfs が userdata を `/new_root/mnt/share` に mount してから `switch_root` し、stage1 がそのまま `/mnt/share` として使えるようにしています。これで stage1 が実行された場合、block device scan の前に `plumos-v90s-stage1.log` が残るはずです。

`-9-stage1-share-handoff` の実機ログでは、handoff mount と `boot: switching to stage1 /sbin/init` までは確認できましたが、stage1/Debian のログはまだ出ませんでした。stage1/Debian rootfs は squashfs なので、`/tmp` を tmpfs にしないまま `/tmp/plumos-*.log` へ書くと失敗します。`-10-stage1-tmpfs-log` では stage1 と Debian init の最初に `/tmp` と `/run` を tmpfs として mount し、tty リダイレクトより前にログ保存を試します。また diagnostic 側から stage1 `/bin/sh` を chroot 実行して `plumos-v90s-stage1-preflight.log` を残します。

`-10-stage1-tmpfs-log` の実機ログでは、stage1 init が起動し、pre-mounted userdata share を使って Debian payload を `/dev/loop1` に attach し、payload rootfs の mount まで成功しました。ただし Debian init log は出ず、stage1 から payload への2回目の `switch_root` 境界で止まっています。また stage1 では sysfs 上の fb0 情報は見えましたが、`/dev/fb0` device node が消えていました。

`-11-direct-payload` では diagnostic initramfs が userdata の Debian payload を直接 `/dev/loop2` で mount し、initramfs から payload `/sbin/init` へ1回だけ `switch_root` します。stage1 は direct payload 準備に失敗した場合の fallback として残します。stage1/Debian init では、移動済みの `/dev` を保持し、sysfs に fb0 があるのに `/dev/fb0` が無い場合は `mknod /dev/fb0 c 29 0` します。

`-11-direct-payload` の実機ログでは、Debian `/sbin/init` まで到達し、`plumos-v90s-debian-init.log` が userdata に残りました。Debian init は `fb0` を認識し、先頭領域への black/white probe 書き込みも成功しました。ただし実機画面は KNULLI boot logo のままだったため、次の課題は boot ではなく「fb0 書き込みが実表示へ出るか」と「fbcon 無しでどう簡易consoleを描くか」です。

`-12-fb-full-probe` では `virtual_size=640,960` のダブルバッファ疑いに合わせ、fb0全体をblackで塗り、page0/page1の両方へ大きなwhite bandを書きました。実機では KNULLI boot logo が消え、黒画面に白帯が表示されたため、Debian userspace からの `/dev/fb0` 描画が V90S LCD に出ることを確認できました。

`-13-fb-console` では kernel framebuffer console に依存せず、Debian init から `/usr/local/sbin/v90s-fb-console` を実行しました。実機では KNULLI boot logo の後に黒画面になり、console text は出ませんでした。戻した SD のログでは Debian init が `starting framebuffer console` まで到達し、`plumos-v90s-fb-console.log` は 0 bytes でした。一方で dmesg には USB keyboard が `usbhid` input device として認識された記録があり、Caps Lock LED が反応しないことだけでは USB 未認識とは判断しません。

`-14-fb-console-logged` では、console 起動前に `perl -c` を実行し、console の stdout/stderr を userdata の `plumos-v90s-fb-console.log` へリダイレクトします。Perl console 側も起動直後からログを強制 flush/sync し、画面には大きな白い start marker と左上の白枠を描くため、また黒画面で止まっても次の原因を SD 側ログから追えるはずです。

`-14-fb-console-logged` の実機ログでは、console が `uname -a`、`ls /`、`ls /dev/input` を実行し、USB keyboard から入力された `ls` も実行できていました。画面には白い枠線だけが出て文字が見えなかったため、残りの問題は font bitmap が初期化されていないことでした。

`-15-fb-text-fat-logs` では font bitmap を起動前に初期化し、文字を少し大きくしました。また Debian 側で FAT boot-resource を `/boot` として rw remount し、ログを `/boot/plumos-logs/` に保存します。macOS では次回から `/Volumes/KNULLI/plumos-logs/` を見るだけで主要ログを確認できます。

## Git workflow

作業履歴と判断ログは git に残します。調査・スクリプト・実機結果のまとまりごとに小さく commit します。
