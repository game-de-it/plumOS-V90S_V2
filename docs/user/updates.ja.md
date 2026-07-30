# システムアップデート

plumOSのアップデートファイルは`.tar.gz`形式です。ファイルがV90S用の正しい
アップデートかどうかは、インストール前に自動確認されます。

## アップデートの種類

- **Runtime Update**: ゲーム一覧画面、アプリ、エミュレータ、初期設定などを更新します。
- **System Update**: plumOSのLinux基本部分を更新します。

どちらも画面の案内に従って操作できます。内部の保存場所をユーザーが選ぶ必要はありません。

## 配置先とstaging

Windows標準でSD1を開いた時に使用するのは、FAT32の`PLUMOS`ドライブです。
アップデートファイルは次のディレクトリ直下へ置きます。

```text
PLUMOS/updates/
```

接続方法ごとの同じ配置先は次のとおりです。

| 接続方法 | 配置先 |
| --- | --- |
| Windows/macOSのカードリーダー、USB Disk Mode | `PLUMOS/updates/` |
| SFTP、SSH、ADB | `/mnt/plumos-user/updates/` |
| FTP | 更新ファイルの配置には使用しない |

別のLinux用ext4領域`PLUMOS_SYS`は、Windows標準ではドライブとして表示されません。
この領域にはupdater内部専用の`/mnt/plumos/updates/staging`があります。ext4対応
ソフトなどでこの領域や`staging`が見えても、ファイルを追加、変更、削除しないで
ください。これはユーザーが更新ファイルを置く`PLUMOS/updates/`とは別の場所です。
SFTP/SSHの開始位置で見える`/mnt/plumos/updates/`も同じ内部領域なので、更新ファイルを
置かないでください。

FTPの公開ルートも`/mnt/plumos`であり、FTP画面に見える`updates/`は内部領域です。
FTPからFAT32の更新受信箱へは移動できないため、更新ファイルの配置にはカードリーダー、
USB Disk Mode、SFTP、SSH、ADBのいずれかを使用してください。FileZillaを使う場合は
FTPではなくSFTPで接続し、リモートパスへ`/mnt/plumos-user/updates/`を指定できます。

配置に必要なのは`.tar.gz`ファイルだけです。同梱の`.sha256`はPCでダウンロード破損を
確認するための任意ファイルであり、SDカードへコピーする必要はありません。

## アップデート手順

1. POWKIDDY V90S用のアップデートファイルを取得します。展開しないでください。
2. `.tar.gz`を展開せず、カードリーダーまたはUSB Disk Modeでは
   `PLUMOS/updates/`、SFTP、SSH、ADBでは`/mnt/plumos-user/updates/`の直下へ
   コピーします。FTP、`/mnt/plumos/updates/`、`staging`は使用しないでください。
3. 安全に取り外すか切断します。
4. `START -> システム設定 -> システムアップデート`を開きます。
5. Aボタンで最新の使用可能なアップデートを選びます。
6. 確認、インストール、再起動が終わるまで安定した電源へ接続します。

アップデート中はボタンを操作できません。Resetを押す、電源を切る、SDカードを
抜く、といった操作をしないでください。

## 復旧とログ

Runtime Updateは、失敗時に戻せるように1つ前の状態だけを残します。
System Updateも、正常に起動できない場合は以前のシステムへ戻ります。

アップデートに失敗した場合、PCから読めるログが次へ保存されます。

```text
PLUMOS/plumos-logs/update/
```

正常に起動できたことを確認した後は、`PLUMOS/updates/`内の古いアップデート
ファイルを削除して構いません。
