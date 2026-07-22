# plumOS V90S 開発者向けガイド

このガイドは、plumOS V90Sのビルド、変更、デプロイ、リリースを行う開発者向けの
技術的な入口です。利用者向け取扱説明書とは明確に分離します。

## 最初に読む文書

1. [アーキテクチャと所有範囲](architecture.ja.md)
2. [Dockerビルドガイド](build.ja.md)
3. [ブートとランタイムサービス](runtime.ja.md)
4. [ストレージとアップデート](storage-and-updates.ja.md)
5. [フロントエンドとエミュレータ統合](frontend-emulators.ja.md)
6. [ハードウェア統合](hardware-services.ja.md)
7. [検証・根拠資料索引](validation.ja.md)
8. [ディストリビューションポリシー](../plumos-v90s-distribution-policy.md)
9. [アップデート契約](../plumos-v90s-update-contract.md)
10. [アップデート作業手順](../update-workflow.ja.md)

## リポジトリ構成

```text
docker/plumos-v90s-toolchain/  再現可能なAArch64ビルド環境、レシピ、
                              バージョン固定、V90S用パッチ
package/                       app、サービス、ランタイム、初期設定の追跡対象
scripts/                       ビルド、組み立て、デプロイ、ブート、監査ツール
docs/user/                     利用者向け取扱説明書
docs/developer/                現行の技術ガイド
docs/research/                 upstream・ハードウェア調査
docs/validation/               日付付きビルド・実機根拠
artifacts/                     git管理外の入力専用vendor・非公開コンテンツ
output/                        git管理外の中間成果物
dist/                          git管理外のリリースパッケージ
```

## 変更してはいけない契約

- 対象はV90S専用です。既知のV90Sランタイムを損なう一般化を行いません。
- `v90s-stockos-r1`がブートローダー、Linux 4.9.191、対応モジュール、PowerVR
  GE8300 userspace、低レベルALSA、ハードウェア入力対応を所有します。
- plumOSが読み取り専用System SquashFS、p3 app/runtime、p4ユーザーデータ、FE、
  エミュレータ、サービス、設定方針、更新エンジンを所有します。
- `/mnt/plumos`は安定した書き込み可能ランタイムABIです。`/mnt/plumos-user`は
  PCから読めるp4、`/mnt/plumos-boot`は通常読み取り専用です。
- framebuffer・入力表示経路を所有するフォアグラウンドプロセスは1つだけです。
  FEランチャーはエミュレータやアプリの前にFE所有権を停止または退避し、終了後に戻します。
- app-layerのデプロイはmetadataを含む原子的な単位です。管理ファイルと一致する
  `checksums.sha256`、`manifest.json`、component manifestを同時に送り、再起動前に
  SHA-256を検査します。
- 実機固有の設定、セーブ、PortMasterコンテンツ、認証情報、SSH状態を、ホスト側
  metadataへ合わせる目的で上書きしません。
- ROM、BIOS、秘密情報、vendor抽出入力はgit外に保ちます。
- リリースにはMITライセンス、第三者表記、component license、manifest、checksumを含めます。

## 正式な技術資料

- [ディストリビューションポリシー](../plumos-v90s-distribution-policy.md): 採用済み
  設計とハードウェア方針の全体
- [アップデート契約](../plumos-v90s-update-contract.md): 署名付きtransactional Runtime更新と
  A/B System更新
- [ストレージ再設計](../v90s-ext4-runtime-fat32-userdata-update-design.md): ext4/FAT32の
  根拠と移行判断
- [Dockerビルド計画](../v90s-docker-build-plan.md): ビルドシステムの履歴とtargetの変遷
- [Step 1ブート計画](../step1-boot-console-plan.md): 初期ブートとframebuffer console経路
- [Step 2ランタイム計画](../step2-knulli-runtime-armbian-plan.md)および
  [RetroArch計画](../step2-retroarch-plan.md): 初期立ち上げの技術的経緯

`docs/validation/`の日付付き文書は根拠資料であり、利用者向け文書でも自動的に現行方針と
なる文書でもありません。根拠資料と採用済み契約が矛盾する場合は、ディストリビューション
ポリシーと現在のソースを優先します。

## English

- [English developer guide](README.md)
