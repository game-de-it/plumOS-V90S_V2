# 第三者コンポーネントに関する表記

この文書は、plumOS V90Sが配布する主な第三者コンポーネントと
StockOS由来ファイルの出典・扱いを記録します。

plumOS用に作成したコード、文書、スクリプト、設定、アートワークは、
個別の記載がない限りリポジトリのMIT Licenseで扱います。このMIT Licenseは、
StockOSファイル、ファームウェア、エミュレータ、libretroコア、フォント、
ライブラリ、ROM、BIOS、ユーザーコンテンツを再ライセンスするものではありません。

plumOSのリリースにはROMおよびゲームBIOSを含めません。

英語版: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)

## 配布物の境界

V90Sのハードウェア基盤には、POWKIDDY V90S StockOS/Batocera由来の
`v90s-stockos-r1`を使用します。ブートローダーデータ、カーネル、モジュール、
PowerVR関連ファイル、機種固有ランタイムは元の権利者・上流の条件を維持し、
plumOSのMIT Licenseの対象にはなりません。バイナリには専用NOTICEを同梱し、
ビルド記録には取得元、ファイル一覧、ハッシュを残します。

## 主な同梱コンポーネント

| コンポーネント | 取得元 | plumOSビルド内のライセンス資料 |
| --- | --- | --- |
| Vendor runtime | POWKIDDY V90S StockOS/Batocera由来 | 専用NOTICE、vendor manifest、ハッシュを同梱します。 |
| RetroArch | <https://github.com/libretro/RetroArch> | 使用したソースツリーの`COPYING`を`retroarch/RetroArch-COPYING`として収録します。 |
| libretroコア | `docker/plumos-v90s-toolchain/libretro-core-recipes.tsv`記載のrepository/ref | 上流に存在する`LICENSE`、`COPYING`、copyright、ライセンス記載READMEを`libretro-cores/`へ収録し、manifestにrepository/ref/commitを記録します。 |
| スタンドアローンエミュレータ | PPSSPP、ScummVM、EasyRPG Player、PCSX-ReARMed、Flycast、Mupen64Plus、NXEngine-evo、OpenBOR、YabaSanshiro | 上流のライセンス本文を`standalone/`へ収録し、manifestに取得元と成果物を記録します。 |
| PicoArch・SDL12互換層 | PicoArchおよびSDL互換プロジェクト | `picoarch/`へライセンス本文を収録します。 |
| PortMaster | <https://github.com/PortsMaster/PortMaster-GUI> | 公式payloadの`PortMaster/licenses/`を維持し、plumOS互換ライブラリの本文も別途収録します。 |
| BusyBox・GNU/Debian userland | BusyBoxおよび使用したDebian/source package | `share/doc`へversion、source、依存関係、checksumを記録し、各上流の条件を維持します。 |
| Network services | ADB、OpenSSH SFTP、Samba、dosfstoolsと依存ライブラリ | network-services manifestへversionとsourceを記録し、各上流の条件を維持します。 |
| Pyxel・Python package | Pyxel、Python、venvへ導入したpackage | venv内にpackage提供のlicense metadataを維持します。 |
| Frontend font | Noto Sans JP、WenQuanYi Micro Hei | SIL OFLおよびApache-2.0本文を`share/doc/plumos-frontend/`へ収録します。 |
| Audio・PortMaster互換ライブラリ | ALSA plugin、FFmpeg互換、OpenAL Soft、libevdev、FLAC、libjpeg、Readline、SquashFS tools、LZO | 個別のlicense/copyright本文をlicense bundleへ収録します。 |

## リリース前チェック

- `LICENSE`、`NOTICE.md`、`THIRD_PARTY_NOTICES.md`、
  `THIRD_PARTY_NOTICES.ja.md`をリポジトリと配布物へ含める
- app-layerに対して`scripts/audit-v90s-license-bundle.sh`を実行する
- 配布バイナリとcomponent manifest・recipeを同期する
- ROM、BIOS、セーブ、認証情報、個人SSH鍵を除外する
- 各ライセンスで必要なsource、recipe、patchを対応するバイナリとともに公開する
