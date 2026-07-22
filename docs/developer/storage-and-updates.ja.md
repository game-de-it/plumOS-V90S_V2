# ストレージとアップデート

## パーティション契約

| パーティション | 形式 | 初期容量 | ランタイム上の役割 |
| --- | --- | ---: | --- |
| p1 `PLUMBOOT` | FAT16 | 1024 MiB | boot resourceと固定System A/B SquashFS slot |
| p2 `BOOT` | raw Android boot image | 64 MiB | 固定vendor kernel、DTB、provisioning initramfs |
| p3 `PLUMOS_SYS` | ext4 | 1600 MiB seed | 8192 MiBへ拡張。app-layerとLinux状態 |
| p4 `PLUMOS` | FAT32 | seedには存在しない | 初回起動でSD card末尾まで作成 |

imageはGPT partitionより前のvendor必須raw boot dataも維持します。p1は通常
`/mnt/plumos-boot`へread-only、p3は`/mnt/plumos`、p4は`/mnt/plumos-user`へmountします。

## ディレクトリ所有範囲

### p3 ext4

```text
/mnt/plumos/
  bin/ lib/ gnu/ cores/ standalone/ frontend/ apps/
  config/ factory-defaults/ state/ Saves/ States/ Logs/
  ssh/ samba/ python/ portmaster/ licenses/
  manifest.json checksums.sha256 VERSION COMPAT_VENDOR RUNTIME_ABI
```

POSIX permission、runtimeで生成するlink、実機固有設定、active save、service credential、
transactional update状態を保存します。Runtime package管理はmutable subtreeを消しません。

### p4 FAT32

```text
/mnt/plumos-user/
  roms/ bios/ Images/ Themes/ Screenshots/ Music/
  Manuals/ Cheats/ Patches/ Shaders/
  updates/ imports/ exports/ plumos-logs/
```

bootstrap時に`roms`、`bios`、`Images`を`/mnt/plumos`以下の互換パスへbindします。
USB Disk Modeはloopback中継imageではなく、p4 block deviceを直接公開します。

### SD2

`plumos-sd2-content-mount`はFAT32の2枚目を検出し、制限時間付きfilesystem repairを行い、
直下`roms`と`bios`の大文字小文字variantを受け入れ、`/mnt/plumos/roms`と
`/mnt/plumos/bios`へbind mountします。helper停止時はp4 bindingへ戻します。
Imagesとupdate archiveはSD1 p4に残ります。

## Runtime Update transaction

署名付きRuntime packageはp3を更新します。boot-time updaterは変更前にsignature、device、
architecture、vendor runtime、ABI、path、file type、size、SHA-256を検査します。`.partial`
staging treeへ展開し、user-owned pathを拒否し、空き容量を確認してから、write-ahead rollback
journalを介して置き換えます。`VERSION`、`manifest.json`、`checksums.sha256`を最後にcommitします。

中断transactionはFE起動前にrollbackします。直前の成功transaction backupを1つだけ保持し、
次のtransaction前に古いbackupとstaging treeを削除します。FEがrenderer-ready proofを
書いた後だけhealthyにします。

## System Update transaction

署名付きSystem packageは完全なSquashFSを1つ含みます。updaterはp3でstage・hashし、処理中だけ
p1を書き込み可能にし、未使用slotへ一時名で書き込み、flushし、全imageをreadbackして
SHA-256を検査します。その後slot metadataを原子的にcommitし、p1をread-onlyへ戻して再起動します。

initramfsはpending slotを1回だけ起動します。FE renderer readinessで正式採用します。readinessなしで
次回bootした場合はpendingを拒否し、以前のactive slotを使います。保存領域は固定2 slotのままです。

## package形式と信頼

両方のpackageは次を持つ`.tar.gz`です。

```text
META/manifest.json
META/manifest.sig
payload/...
```

Ed25519署名はcanonical manifest全体を対象にします。production FEはunsigned modeを有効にしません。
固定vendor kernel、DTB、boot0、boot package、p2 initramfsはfull imageでのみ変更します。

## USB Disk Modeの安全性

p4公開前にcontrollerはcontent bindingを解放し、競合するFTP/SFTP/Samba writerを止め、p4を
unmountし、write-through semanticsでblock deviceをUSB mass storageへ渡します。復帰時は
`fsck.fat`を実行し、失敗時はmountを拒否し、成功時はp4、binding、以前ONだったserviceだけを
復元します。ADBとmass storageは同じgadget経路を使うため排他的です。

transactionと復旧の詳細は[アップデート契約](../plumos-v90s-update-contract.md)を参照してください。
