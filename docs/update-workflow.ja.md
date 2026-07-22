# plumOS V90S アップデート作業手順

これは採用済み署名付き更新システムの開発者向け手順です。利用者は短い
[システムアップデート](user/updates.ja.md)を参照してください。

## アップデートの種類

- Runtime Update: p3 ext4上のplumOS管理ファイルをtransactionalに更新
- System Update: 完全な読み取り専用System SquashFSをp1の未使用A/B slotへ書き込み

固定StockOS由来のboot0、boot package、kernel、DTB、p2 initramfs、対応vendor moduleは
通常更新の対象外です。変更する場合は、全体を検査した新しいSD imageとして扱います。

## ビルド入力の準備

完全なstrict app layerと、versionが一致するSystem SquashFSを生成します。

```sh
PLUMOS_V90S_APP_LAYER_VERSION=NEW \
  ./scripts/docker-build.sh app-layer --strict

PLUMOS_V90S_SYSTEM_VERSION=NEW \
  ./scripts/docker-build.sh system-rootfs

./scripts/docker-build.sh license-audit output/app-layer/v90s
```

Runtime入力は`manifest.json.complete=true`、`missing_optional`が空、正しい
`COMPAT_VENDOR`、完全な`checksums.sha256`が必要です。Systemに埋め込んだversionは、
System packageのtarget versionと一致させます。

## 署名鍵

追跡対象の検証公開鍵は次です。

```text
package/system-v90s/plumos-update-public.pem
```

Ed25519秘密鍵はgit管理外のローカルパスだけに置きます。

```text
artifacts/update-signing/plumos-v90s-ed25519-private.pem
```

秘密鍵をcommit、app layer、image、log、release archiveへ入れてはいけません。

## Runtime Updateの生成

```sh
./scripts/docker-build.sh update-package \
  --type runtime \
  --input output/app-layer/v90s \
  --base-dir PATH/TO/PREVIOUS/RUNTIME \
  --base-version OLD \
  --version NEW \
  --output-dir dist/updates
```

base directoryは、実機所有のmutable pathを除外しながら、管理対象の追加、置換、削除を
算出するために必要です。

## System Updateの生成

```sh
./scripts/docker-build.sh update-package \
  --type system \
  --input output/system-rootfs/v90s/plumos-v90s-system-rootfs.squashfs \
  --base-version OLD \
  --version NEW \
  --output-dir dist/updates
```

## PCからの配置

署名済み`.tar.gz`を展開せず、次へコピーします。

```text
PLUMOS:/updates/
/mnt/plumos-user/updates/
```

FEは`システム設定 -> システムアップデート`からinboxをscanし、全候補を検査し、最新の
互換署名済みpackageを選び、p3へrequestを記録して安全なreboot経路へ入ります。

## ブート時の適用

updaterはFEと通常network writerより前にSystem SquashFSから動きます。Runtime packageは
staging、write-ahead rollback journal、atomic rename、renderer-ready health confirmationを
使います。System packageは未使用p1 slotへ書いて全体をreadbackし、pending slotをcommitして
1回だけ起動します。health proofがなければ次回bootでrollbackします。

Runtime backupは1つ、Systemは固定2 slotだけを保持します。古いupdater stagingは削除します。
p4のarchiveはuser管理のままです。

## 診断

実機では次を使います。

```sh
plumos-system-update scan
plumos-system-update inspect /mnt/plumos-user/updates/PACKAGE.tar.gz
```

永続update状態と完全なlogはp3に残ります。PCから読める範囲制限付きの最新失敗概要は
次へコピーします。

```text
/mnt/plumos-user/plumos-logs/update/
```

package形式、信頼性検査、不正path拒否、journal、A/B状態、保持規則は
[アップデート契約](plumos-v90s-update-contract.md)を参照してください。
