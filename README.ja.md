# plumOS V90S

plumOS V90Sは、POWKIDDY V90S専用のSDカード起動Linuxディストリビューションです。
StockOS由来のブート、カーネル、PowerVRハードウェアランタイムを基盤にしながら、
フロントエンド、エミュレータ、アプリ、設定、アップデート機能をplumOSで管理します。

## ドキュメント

利用者向けと開発者向けを分離し、それぞれ英語版と日本語版を用意しています。

- [ドキュメント索引](docs/README.ja.md)
- [ユーザー向け取扱説明書](docs/user/README.ja.md)
- [開発者向けガイド](docs/developer/README.ja.md)
- [English project overview](README.md)

ユーザー向け文書には通常操作だけを記載します。開発履歴、実機検証、ビルド内部、
低レベル実装は開発者向け文書に収録します。

## ディストリビューション構成

- POWKIDDY V90S専用
- SDカード起動。本体内蔵ストレージへのインストールは不要
- StockOS/Batocera由来Linux 4.9.191とPowerVR GE8300ランタイムを使用
- plumOSフロントエンド、RetroArch、PicoArch、スタンドアロンエミュレータ、
  Apps、Pyxel、PortMasterを搭載
- p3 ext4ランタイムとp4 FAT32ユーザーボリューム
- ROM、BIOS用のSD2に対応
- Windows/macOSから配置できる署名付きRuntime/Systemアップデート

ROMおよびゲームBIOSは同梱しません。合法的に入手したデータを用意してください。

## ビルド入口

開発時の正式なDockerビルド入口は次のコマンドです。

```sh
./scripts/docker-build.sh --help
```

イメージや更新パッケージを作る前に、
[開発者向けビルドガイド](docs/developer/build.ja.md)を参照してください。

## ライセンス

plumOSが作成したファイルには[MIT License](LICENSE)を適用します。vendorおよび
第三者コンポーネントは元の条件を維持します。詳細は[NOTICE.md](NOTICE.md)と
[THIRD_PARTY_NOTICES日本語版](THIRD_PARTY_NOTICES.ja.md)を参照してください。
