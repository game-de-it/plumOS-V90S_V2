# ブートとランタイムサービス

## 4パーティションブート

seed imageはvendorのraw boot offsetを維持し、p1からp3までを含みます。p2のprovisioning
initramfsは`PLUMBOOT`と`PLUMOS_SYS` labelでboot diskを特定し、最小容量を検査し、
GPTを拡張し、p3を8 GiBへ拡張します。その後、card末尾までp4を作り、`PLUMOS`という
FAT32でformatし、ユーザーディレクトリを作成します。

2回目以降はprovision marker、clean shutdown marker、System slot状態を確認してから、
p1の`System/system-a.squashfs`または`System/system-b.squashfs`を選びます。検査済みimageを
loop deviceへ割り当て、読み取り専用mountし、永続mountを移動して、initramfsが次を実行します。

```text
switch_root <system-root> /sbin/init
```

初回起動の進行状況とerrorはframebufferへ直接表示し、可能な範囲でPCから読めるlogへ
コピーします。通常起動でcached verificationを使うのは、clean markerと保存hashが
一致する場合だけです。

## System initの順序

System SquashFSのinitは次を担当します。

1. p3 `/mnt/plumos`とp4 `/mnt/plumos-user`をmountまたは検出
2. 通常writerの起動前にpending署名付きupdateを適用
3. `plumos-app-layer-bootstrap`を実行
4. critical app-layer metadataを検査し、書き込みbindingを準備
5. PowerVR、input、display、ALSA routing、hotkey、network runtimeを準備
6. 利用可能ならSD2 contentをmount
7. FEを必ず1つだけ起動
8. FE readyを阻害せず、ONのnetwork serviceを起動
9. FE renderer proof後だけpending RuntimeまたはSystem updateをhealthyへ変更

## App-layer bootstrap

`scripts/plumos-app-layer-bootstrap.sh`はapp-layer契約を検査し、p4の`roms`、`bios`、
`Images`、user themeをbindし、SSH用の永続`/root`と`/etc/shadow` overlayを準備し、`/run/plumos`へ
runtime library aliasを作り、hardware-key service、保存済みservice、管理されたFEを起動します。

critical checksum failure時は、不整合なFEの起動を拒否します。このためlive deployでは
ファイルとmetadataを同時に更新します。

## foreground lifecycle

FE launcherは`/run/plumos`へPIDと所有状態を記録します。ゲームまたはapp起動時は次を行います。

1. foreground transition lockを取得
2. FE描画を止め、framebuffer・input descriptorを解放
3. system固有library、config、CPU policy、audio environmentを準備
4. 選択childと必要なinput helperだけを起動
5. 通常終了またはglobal quit時に子孫processを安全に停止
6. display・audio・input状態を解放
7. FEを1つだけ復帰

広範な`killall`を使いません。PID fileはcmdlineまたは実行ファイルのidentityを検査してから
採用し、emulator停止がSSH、ADB、無関係serviceを巻き込まないようにします。

## 安全な電源操作

再起動とshutdownは専用framebuffer進行画面へ入り、通常入力を無効にします。安全経路は、
foreground content、PortMaster writer、FE、network file service、removable content bindingを
止め、重要ファイルをflushし、clean markerを書き、依存順にFAT32とext4をunmountしてから
kernelのrebootまたはpoweroffを呼びます。

物理Power keyは常駐hardware-key serviceが受け取ります。FE、RA、PicoArch、standalone、
Apps上にglobal power overlayを開き、2つ目のFEは起動しません。cancel時はframebuffer page、
pauseしたprocess、audio routeを復元します。suspendは`mem`を使い、復帰も同じglobal serviceが
処理します。

## ランタイムログ

| 分類 | パス |
| --- | --- |
| boot/init | `/run/plumos-boot.log`、p3のlog・provision状態へ永続化 |
| frontend | `/mnt/plumos/Logs/`と`/run/plumos/frontend/` |
| launcher | `/mnt/plumos/Logs/` |
| network service | `/mnt/plumos/Logs/network-services.log` |
| SSH | `/mnt/plumos/ssh/log/sshd.log` |
| update | p3 update stateと`/mnt/plumos-user/plumos-logs/update/`概要 |
