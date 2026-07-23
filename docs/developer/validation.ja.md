# 検証・根拠資料索引

## 根拠資料の規則

検証記録は`docs/validation/`へ置き、`YYYY-MM-DD-topic.md`という名前にします。各記録には、
buildまたはdeployしたファイル、必要なhash、command・runtime根拠、実機結果、残るrisk、
再現可能にしたcommitを記載します。

hostにファイルが存在するだけでは、V90S上で動く根拠になりません。実機根拠にはprocess identity、
mount ownership、ELF architecture・dependency解決、active config、checksum、framebuffer ownership・
screenshot、ALSA route、input event、終了動作、FE復帰が有効です。

## 現在のリリース基盤

最初に次を参照します。

- [最終seed自動検査](../validation/2026-07-22-v90s-final-seed-automated-validation.md)
- [4パーティションimage](../validation/2026-07-22-v90s-four-partition-image.md)
- [transactional update host検査](../validation/2026-07-22-v90s-transactional-update-host-validation.md)
- [利用者最終確認](../validation/2026-07-22-v90s-user-final-validation.md)
- [PortMaster cleanup・license audit](../validation/2026-07-22-v90s-portmaster-cleanup-license-audit.md)
- [USB Disk Mode host書き込み](../validation/2026-07-11-usb-disk-mode.md)
- [USB Wi-Fi hotplug復旧](../validation/2026-07-22-v90s-wifi-hotplug-recovery.md)

## 分野別の根拠

### BootとStorage

- `2026-07-09-step1-*`と`device-test-*`: KNULLI由来boot chainとframebuffer consoleの過程
- `2026-07-11-boot-*`、`fat32-*`、`sd2-*`: startup、FAT safety、SD2 content
- `2026-07-18-four-partition-*`から`2026-07-22-v90s-four-partition-*`:
  provisioning、recovery、現行image契約

### FrontendとControl

- `2026-07-10-frontend-*`から`2026-07-14-v90s-top-*`: MMF port、renderer、menu、list、
  gallery、CJK、settings、system information
- `2026-07-13-v90s-physical-keymap.md`とinput関連記録: 物理event mappingとemulator操作
- `2026-07-19-v90s-global-power-menu.md`以後のpower記録: runtime横断overlay、shutdown、sleep

### Video、Audio、Performance

- `2026-07-10-step2-stockos-video-perfect-runtime.md`とrefresh・sync sweep:
  採用したRetroArch video timingの基盤
- `2026-07-15-v90s-alsa-mono-usb-audio.md`: 内蔵monoとUSB-DAC経路
- `2026-07-16-v90s-global-volume-brightness-hotkeys.md`と
  `2026-07-19-v90s-volume-response-12-step.md`: system control
- PicoArch、standalone、core別の日付付き記録: pacing、audio、rendering、input、performance判断

### EmulatorとApps

- `2026-07-13-v90s-*core*`と`2026-07-15-release-core-set-recovery.md`:
  正式libretro setとdeploy
- YabaSanshiro、PPSSPP、PCSX-ReARMed、OpenBOR、ScummVM、EasyRPG、N64、Dreamcast、
  廃止したDOSBox-staging経路のstandalone記録
- `2026-07-23-v90s-ppsspp-factory-identity.md`: 取得済みPPSSPP network identityの
  除去と、installごとのMAC生成を必須にするrelease gate
- `2026-07-16-v90s-pyxel-*`、`2026-07-19-v90s-pyxel-*`: Python/Pyxel setup、
  aspect fit、image同梱、pygame audio
- `2026-07-20-v90s-portmaster-*`: 静的監査、共通ABI、architecture境界、代表実機sample

### NetworkとUpdate

- 7月11日から22日のWi-Fi、network-information、FTP/SFTP/Samba、SSH password、ADB、USB復旧記録
- `2026-07-23-v90s-default-ssh-credential.md`: 公開初期資格情報`root / plumos`の
  端末固有shadow生成、保持、System SquashFS、実機password login検証
- `2026-07-22-v90s-transactional-update-host-validation.md`と採用済み
  [アップデート契約](../plumos-v90s-update-contract.md)

## リリース条件

release前に、`git diff --check`、strict app-layer、license audit、preflight、image verify、archive
checksum、ROM・BIOS・秘密情報の不在、vendor互換性、実機cold bootを必須にします。続いてFE
renderer、操作、音声、代表RA・PicoArch・standalone・Appの起動終了、save保持、SD2、network
service状態、USB Disk Mode、安全なreboot・shutdown、update rollbackを確認します。

非公開ROM・BIOSが必要で確認できないsystemは、虚偽のpassにせず、release後のuser report対象とします。
