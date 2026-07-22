# SDカードとフォルダ

## SD1

SD1にはOSとFAT32の`PLUMOS`ユーザーボリュームがあります。Windows/macOSでは
通常、ユーザー向けボリュームだけが表示されます。PCから不明な形式と表示された
パーティションをフォーマットしないでください。

`PLUMOS`ボリュームの主なフォルダ:

```text
PLUMOS/
  roms/          機種別のゲームデータ
  bios/          ユーザーが用意したBIOS
  Images/        取得・コピーしたサムネイル
  Themes/        ユーザーテーマ
  Screenshots/   書き出したスクリーンショット
  Music/         ユーザーメディア
  Cheats/        チートファイル
  Patches/       ゲーム用パッチ
  Shaders/       RetroArch用シェーダー
  updates/       署名付きplumOSアップデート
  imports/       明示的な取り込み待ちファイル
  exports/       Linux管理領域から書き出したファイル
  plumos-logs/   PCから読める更新・復旧ログ
```

システム設定、エミュレータ、セーブ、ステート、書き込み可能ランタイムはLinuxの
ext4システム領域へ保存され、Windows/macOSからは直接表示されません。

## SD2

SD2は任意で、FAT32を使用します。カード直下に次のフォルダを作成します。

```text
roms/
bios/
```

SD2がある場合、plumOSはファイルシステムをチェックし、この2フォルダをROM・BIOSの
参照先として自動マウントします。SD2を外すと、次回起動または更新時にSD1側へ戻ります。
SDカードの挿入・取り外しはシャットダウン後に行ってください。

## ROMフォルダ名

`FC`、`SFC`、`GB`、`GBC`、`GBA`などMiyoo系の大文字名と、`nes`、`snes`、
`gb`、`gbc`、`gba`などEmulationStation系の小文字名を認識します。
重複表示を避けるため、1機種につき1種類の命名を使用してください。

データ変更後は`TOP画面を更新`を実行します。ROM・BIOSはplumOSに同梱されません。
