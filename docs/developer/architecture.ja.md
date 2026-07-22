# アーキテクチャと所有範囲

## レイヤーモデル

```text
StockOS vendor基盤（v90s-stockos-r1）
  boot0 / boot package / Linux 4.9.191 / DTB / vendor modules
  PowerVR GE8300 EGL/GLES / ALSA codec / adc_gamepad / USB drivers
                         |
plumOS System SquashFS（読み取り専用、p1 A/B）
  init / 更新エンジン / mount制御 / rootfsライブラリ / 診断
                         |
plumOS Runtime（書き込み可能ext4、p3）
  FE / launcher / emulator / core / app / service / config / save
                         |
plumOS User Data（FAT32、p4またはSD2 content binding）
  ROM / BIOS / artwork / theme / media / update inbox / PC向けlog
```

vendor層はソースから再構築するものではなく、再配布可能なバイナリ入力です。由来と
ハッシュをvendor manifestへ記録し、低レベル基盤が変わる場合だけ新しいruntime IDを
作ります。通常のplumOSリリースは`v90s-stockos-r1`との互換性を保ったまま更新します。

## プロセスとマウントの所有権

| パスまたは資源 | 所有者 | 規則 |
| --- | --- | --- |
| `/` | 使用中のp1 System SquashFS | `switch_root`後は読み取り専用 |
| `/mnt/plumos-boot` | p1 PLUMBOOT | 未使用slot更新時以外は読み取り専用 |
| `/mnt/plumos` | p3 PLUMOS_SYS | plumOS runtime ABIと永続Linux状態 |
| `/mnt/plumos-user` | p4 PLUMOS | PCとのFAT32交換領域 |
| `/run/plumos` | tmpfs | PID、lock、生成audio設定、一時状態 |
| `/dev/fb0` | 1つのforeground renderer | FE、emulator、app、power overlayのいずれか |
| 物理入力デバイス | active frontend/helper | readerを二重に残さない |
| ALSA `default` | plumOS audio router | 内蔵monoまたはUSB-DAC stereo |

bootstrap時にp4の`roms`、`bios`、`Images`を`/mnt/plumos`以下の同名パスへbindし、
`Themes`を`/mnt/plumos/themes-user`へbindします。SD2がある場合は`roms`と`bios`だけを
SD2へ置き換えます。これにより、アプリ側の安定したパスとFAT32上の可搬ファイルを両立します。

## 永続・変更可能データ

plumOS管理の置き換え可能ファイルは、実行ファイル、共有ライブラリ、core、FEコード、
起動metadata、factory default、notice、manifestです。実機所有の変更可能パスは、
使用中設定、save、state、log、PortMaster導入物、Pyxel環境、認証情報、SSH home、
ユーザーファイルです。Runtime Updateはこの所有境界を強制します。

## 互換名称

plumOS側のPowerVR名称は`sdl2-powervr`と`PowerVR GE8300`を使います。vendorまたは
upstream互換文字列である`SDL_VIDEODRIVER=mali`、
`video_context_driver=mali_fbdev`は必要箇所に残し、表示経路全体を確認せずに
改名しません。

## 正とする情報の順序

1. 現在のソースと実行契約
2. [ディストリビューションポリシー](../plumos-v90s-distribution-policy.md)
3. [アップデート契約](../plumos-v90s-update-contract.md)
4. 現在生成されたmanifestとchecksum
5. 日付付き検証根拠
6. 過去のStep 1・Step 2計画
