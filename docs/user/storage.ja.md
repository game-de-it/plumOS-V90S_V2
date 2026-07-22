# SDカードとフォルダ

V90Sは2枚のSDカードを使えます。SD1は必須です。SD2はROMとBIOSを別の
カードへ保存したい場合だけ使います。

## 全体図

```text
V90S
├─ SD1（必須：plumOS本体とユーザーデータ）
│  ├─ PLUMBOOT       起動用。変更・削除しない
│  ├─ Linux用領域    通常はPCから見えない。フォーマットしない
│  └─ PLUMOS         ROM、画像、音楽、アップデートなど
│
└─ SD2（任意：ROMとBIOS用）
   ├─ roms/          ゲームデータとRetroArchのセーブ
   └─ bios/          BIOSデータ
```

SD2の有無で、ROMとBIOSの読み込み先が変わります。RetroArchのセーブと
ステートはROM側へ保存されるため、ROMと一緒に移動します。

```text
SD2なし  →  SD1の PLUMOS/roms/ と PLUMOS/bios/ を使う
SD2あり  →  SD2の roms/ と bios/ を使う

RetroArchのセーブとステート → 使用中の roms/ 内へ保存
OS、設定、PicoArch・スタンドアローンのセーブ、画像、アップデート → SD1
```

## SD1

SD1にはplumOS本体とユーザーデータが入ります。PCへ接続すると、
`PLUMBOOT`と`PLUMOS`が表示されることがあります。

- `PLUMBOOT`は起動用です。中のファイルを変更・削除しないでください。
- 普段ファイルを入れる場所は`PLUMOS`です。
- PCが「フォーマットが必要です」と表示しても、`PLUMOS`以外は
  フォーマットしないでください。

`PLUMOS`の主なフォルダ:

```text
PLUMOS/
  roms/          機種別のゲームデータ
  bios/          ユーザーが用意したBIOS
  Images/        サムネイル画像
  Themes/        ユーザーテーマ
  Screenshots/   PCへ書き出したスクリーンショット
  Music/         音楽などのユーザーファイル
  Cheats/        チートファイル
  Patches/       ゲーム用パッチ
  Shaders/       RetroArch用シェーダー
  updates/       plumOSのアップデートファイル
  imports/       plumOSへ取り込ませるファイル
  exports/       PCへ持ち出すために書き出したファイル
  plumos-logs/   エラー調査用のログ
```

システム設定と、PicoArch・スタンドアローンエミュレータのセーブなどは、
PCから見えないLinux用領域へ保存されます。RetroArchのセーブとステートは
`roms/`内へ保存されます。詳しくは[セーブデータ](save-data.ja.md)を参照してください。

## SD2

SD2は任意です。FAT32でフォーマットし、カードの一番上に次の2つの
フォルダを作ります。

```text
SD2/
  roms/
  bios/
```

SD2を入れて起動すると、plumOSはSD2の`roms/`と`bios/`を使います。
RetroArchのセーブとステートもSD2の`roms/`内へ書き込まれます。
SD2を取り外して起動すると、SD1側へ戻ります。

SDカードを抜き差しする前に、必ずV90Sをシャットダウンしてください。

## ROMフォルダ名

`roms/`の中には機種別のフォルダを作ります。次のどちらの名前も使えます。

```text
Miyoo系:               FC  SFC  GB  GBC  GBA
EmulationStation系:    nes snes gb  gbc  gba
```

同じ機種で両方の名前を使うと、ゲームが重複表示されることがあります。
1機種につき、どちらか一方だけを使ってください。

ROMを追加・削除した後は、`START -> UI設定 -> TOPを更新`を実行します。
ROMとBIOSはplumOSに同梱されません。
