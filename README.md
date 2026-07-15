# plumOS-V90S_v2

POWKIDDY V90S 向けに、StockOS/Batocera 由来の boot/runtime と
plumOS-built userspace を組み合わせた Linux SD カードイメージを作るため
の作業リポジトリです。

## Step 1 goal

まずは V90S 実機で SD カードから起動し、内蔵画面に Linux コンソールが表示され、USB キーボードで入力でき、`ls` などの基本コマンドを実行できる状態を目標にします。

Step 1 は `plumos-v90s-armbian-step1-20260709-15-fb-text-fat-logs.img` で達成済みです。Step 2 は、StockOS-derived RetroArch video timing defaults を live 適用した状態で、NES/QuickNES の FPS、スクロール、音程、音声出力、本体コントローラー操作が実機確認済みです。Step 2 の詳細は `docs/step2-retroarch-plan.md`、`docs/step2-knulli-runtime-armbian-plan.md`、`docs/validation/2026-07-10-step2-stockos-video-perfect-runtime.md` に記録します。

## Current strategy

- V90S は StockOS/Batocera 由来の Linux 4.9.191 kernel、boot image、
  PowerVR GE8300 runtime、audio stack を vendor runtime baseline とします。
- KNULLI は有用な参考実装ですが、今後の主契約は実機で動作確認済みの
  StockOS/Batocera 抽出物に寄せます。
- Armbian / Buildroot は必須条件ではありません。規模が大きいため、当面は
  MMF方式の `plumOS-V90S` 専用 Docker toolchain で、RA / libretro cores /
  PicoArch / standalone / frontend / rootfs / SD image を段階的にビルドします。
- mainline kernel / open U-Boot 化は別トラックにします。A133 mainline spike は
  reboot/black-screen loop で止め、当面は StockOS runtime を活用してユーザーが
  自由に設定変更できる plumOS runtime を作る方向にします。

V90S Docker build 方針は `docs/v90s-docker-build-plan.md` に記録しています。
ディストリビューション全体の意思決定は
`docs/plumos-v90s-distribution-policy.md` に追記していきます。
入口は MMF と同じように `scripts/docker-build.sh` です。

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

Armbian build framework は macOS 上で直接ではなく、Ubuntu コンテナ内で動かします。まずは inventory 系コマンドでターゲット/ユーザーランド情報を確認します。

```sh
./scripts/run-armbian-build.sh inventory
./scripts/run-armbian-build.sh inventory-boards
```

## Docker Build Flow

現在の主経路は、StockOS/Batocera 由来の vendor runtime を入力にした
Docker build flow です。

```sh
./scripts/docker-build.sh image
./scripts/docker-build.sh vendor-runtime
./scripts/docker-build.sh userland
./scripts/docker-build.sh network-services
./scripts/docker-build.sh retroarch
./scripts/docker-build.sh cores
./scripts/docker-build.sh frontend
./scripts/docker-build.sh app-layer --strict
./scripts/docker-build.sh system-rootfs
./scripts/docker-build.sh release

# Vendor inputがない場合だけ、既知良好な実機SDからADB経由で採取します。
./scripts/capture-v90s-vendor-runtime-adb.sh --force
./scripts/docker-build.sh vendor-runtime

# 正式なrelease-system SD imageです。p5を再パックしません。
./scripts/docker-build.sh sd-image \
  --rootfs-squashfs output/system-rootfs/v90s/plumos-v90s-system-rootfs.squashfs \
  --no-rootfs-repack \
  --app-layer-dir output/app-layer/v90s \
  --share-size 4096M \
  --name plumos-v90s-system-squashfs-20260715-5.img

# Explicit Step 2 diagnostic profile; not the release rootfs.
./scripts/docker-build.sh system-rootfs \
  --profile debian-retroarch-powervr \
  --out-dir output/rootfs-step2 \
  --rom "artifacts/nes/Super Mario Bros..nes"
./scripts/docker-build.sh sd-image --name plumos-v90s-stockos-smoke-20260710-1.img
./scripts/docker-build.sh sd-image \
  --rootfs-squashfs output/rootfs-step2/debian-bookworm-retroarch-powervr-step2.squashfs \
  --name plumos-v90s-stockos-ra-20260710-1.img
```

`quicknes` は現在の1 core開発用aliasです。通常の libretro core build 入口は
`cores` です。`rootfs` は `system-rootfs`、`stockos-image` は `sd-image` の
移行aliasとして残します。

`userland` は BusyBox と補助コマンド群を `output/userland/v90s/` に生成します。
`network-services` は FTP/SFTP/Samba のapp-layer payloadを
`output/network-services/v90s/` に生成します。FTPに必要なBusyBox、`tcpsvd`、
`ftpd`も同じ成果物へ同梱されるため、service controllerだけが配置される
不完全な更新にはなりません。SSHも
`plumos-network-services` の制御対象です。V90Sではsystem rootfs側のOpenSSHを
app-layerの `ssh/start-ssh.sh` / `ssh/stop-ssh.sh` から起動または採用し、
SSHログイン時は `/mnt/plumos/bin:/mnt/plumos/gnu/bin` をPATH先頭へ入れます。

`app-layer` は FAT32 にコピーする plumOS 側ツリーを
`output/app-layer/v90s/` に生成します。現在は RetroArch、QuickNES、frontend、
BusyBox/command tools、FTP/SFTP/Samba payload、SDL2 PowerVR private libs、
既知良好RetroArch設定テンプレート、metadata、checksumを含みます。manifestの
`complete`がfalse、または`missing_optional`が空でないapp-layerからはreleaseを
生成しません。symlinkは
使わず、FAT32上で成立する実体ファイルとして配置します。

`release` は `output/app-layer/v90s/` から update-only package を
`dist/plumos-v90s-update-VERSION/`、`.tar.gz`、`.zip` として生成します。
現時点では full SD-root package ではなく、FAT32 app layer へ上書きコピーする
ための更新パッケージです。コピー手順は `docs/update-workflow.md` に記録します。

`sd-image` は StockOS 実機スナップショットで確認したパーティション契約を
再現します。

```text
p1 boot-resource / Volumn vfat
p2 env
p3 env-redund
p4 boot Android boot image
p5 batocera squashfs
p6 rootfs / BATOCERA ext4
p7 rootfs_data / PLUMOS FAT32
```

反復テストを速くするため、p1 の FAT 領域はデフォルトで `33M` に抑えます。
StockOS 由来の `boot0` / `boot_package` が未採取の場合に互換性のある
KNULLI V90S asset を使うには、診断用として
`--allow-knulli-boot-fallback` を明示します。
vendor runtime の正式入力は `artifacts/vendor/v90s-stockos-r1/`、正式出力は
`output/vendor/v90s-stockos-r1/` です。`output/vendor/stockos-runtime` は移行中
の互換エイリアスとして扱います。
現在のRA入りStockOSレイアウト候補は
`output/images/plumos-v90s-stockos-ra-20260710-2-stockos-video.img` です。

旧 KNULLI/Armbian レイアウトを使う場合だけ、明示的に `knulli-image` を使います。

```sh
./scripts/docker-build.sh knulli-image \
  --rootfs output/rootfs-step1/stage1-userdata-loader.squashfs \
  --userdata-payload output/rootfs-step1/debian-bookworm-minbase-step1.squashfs
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

`-15-fb-text-fat-logs` の実機確認では、内蔵 LCD に framebuffer console の文字が表示され、USB keyboard から `df` を入力して実行できました。FAT の `/Volumes/KNULLI/plumos-logs/` にもログが保存され、パスワードなしで確認できました。これで Step 1 の「画面表示、USB keyboard 入力、基本コマンド実行」は実機で確認済みです。

## Step 2 RetroArch image

最初の RetroArch 実機確認用イメージは Debian bookworm arm64 の `retroarch` と `libretro-nestopia` を使います。FAT boot-resource は 33MB のまま、RetroArch payload が大きいため userdata だけ 512MB にしています。

```text
output/images/plumos-v90s-armbian-step2-20260709-1-retroarch-debian.img
sha256: d31d2913b1792bc4979e55a1437d7d9aedd60c84af11be613b4c0d3387df39a7
size: 581M
```

実機確認後、macOS では FAT 側の `/Volumes/KNULLI/plumos-logs/` から以下を確認します。

```text
plumos-v90s-retroarch-launch.log
plumos-v90s-retroarch.log
plumos-v90s-debian-init.log
plumos-v90s-diag.log
```

現在の最新 Step 2 診断イメージは、PowerVR と KNULLI 由来 SDL2 `mali` driver が実機で動作した後の黒画面ハングを調べるため、RetroArch 起動を45秒timeout付きにしています。

```text
output/images/plumos-v90s-armbian-step2-20260709-5-retroarch-timeout-log.img
sha256: b098ae5474b7517980810245c4227384e04a5d0a621e1e98e23e99acfb57c298
size: 581M
```

このイメージでは `plumos-v90s-retroarch.log` もFATへ残る想定です。RetroArchが黒画面で止まる場合でも、`plumos-v90s-retroarch-launch.log` に `attempt=1 timed out after 45s` が出るかを確認します。

最新の実機作業用イメージは、USB Wi-Fiドングル前提のWi-Fi接続とSSHD起動を追加したものです。RetroArchが黒画面に入る前にネットワーク初期化を実行し、FATへ `plumos-v90s-network-ssh.log` と、IP取得できた場合は `ssh-connect.txt` を出します。

前回の `-6-wifi-ssh` は、ネットワーク初期化がWi-Fiモジュール一覧を出した後に戻らず、SSHDもRetroArchも起動しませんでした。`-7-usb-wifi-ssh` ではsshdを先に起動し、`lsusb` と `/sys/bus/usb/devices` のVID/PIDをログへ残し、KNULLI A133/V90S overlayにあるUSB Wi-Fi向けRealtekドライバ候補だけをalias一致で読み込みます。

```text
output/images/plumos-v90s-armbian-step2-20260709-7-usb-wifi-ssh.img
sha256: a340674105a9a0ef115833e78c9c84b391b31bc49226ccab943b793997150130
size: 581M
```

SSHは `root` で鍵認証とパスワード認証を有効にしています。公開鍵はビルド時に `/Users/example/.ssh/id_ed25519.pub` を入れています。Wi-Fi PSKとroot passwordは生成済みイメージ内だけに入れ、git管理ファイルには残しません。

`-7-usb-wifi-ssh` の実機確認では、TP-Link USB Wi-Fiドングルが `rtl8821cu` として認識され、`wlan0` が DHCP で `192.0.2.110` を取得しました。Mac から `ssh root@192.0.2.110` でログインでき、`df` も実行できました。以降、SDカードの焼き直しが不要な作業はSSH越しに進めます。

音声調査用の最新イメージは、通常のRetroArch経路を `sdl2 + mali + software` の単一路線に保ったまま、SSHから明示的に呼び出す `v90s-audio-diagnostic` を追加しています。FAT boot-resource は引き続き33MBです。

```text
output/images/plumos-v90s-armbian-step2-20260709-8-audio-diagnostic.img
sha256: 21dc57e4107669b1ce28be87412d93cc2fa62181b06619e5a64d94458c2fef9e
size: 581M
```

最初に試す音声診断コマンド:

```sh
v90s-retroarch-stop stop
v90s-audio-diagnostic profile knulli_dts_loud 10
v90s-audio-diagnostic profile headphone_hotplug 10
v90s-audio-diagnostic profile dmix_softvol 10
```

最新の実機調査では、KNULLI-derived mixer state でゲーム音が出ること、KNULLI-pinned QuickNES で音切れが止まることを確認しました。一方で Debian generic RetroArch は、QuickNESでもスクロールのガタつきが残り、`video_threaded=false` では約50fpsまで落ちます。次は generic Debian RetroArch の調整ではなく、KNULLIのRetroArch build contractである `--enable-mali_fbdev` を再現する方向に進めます。

QuickNES core は以下で生成し、RetroArch payload へ必須ファイルとして組み込みます。

```sh
./scripts/build-libretro-quicknes.sh
```

## Git workflow

作業履歴と判断ログは git に残します。調査・スクリプト・実機結果のまとまりごとに小さく commit します。
