# ハードウェア統合

## DisplayとPowerVR

vendor基盤はV90S LCDを`/dev/fb0`、PowerVR GE8300をEGL/GLES libraryとして公開します。
plumOS SDL2はハードウェアに正しい`sdl2-powervr`というpackage名を使い、vendor互換driver
文字列は`mali_fbdev`のままです。RetroArchとnative appは、generic互換libraryより先に
package済みPowerVR EGL/GLES・SDLを読み込む必要があります。

LCD timingは公称60.000 Hzと完全には一致しません。FPS表示を60にする目的でemulation audioを
display clockへ固定してはいけません。各runtimeがpacingを所有します。RetroArchは採用済みの
threaded-video・sync設定、PicoArchはcore audio pitchを変えない専用presentation経路を使います。
overlayとdirect rendererはframebuffer page数、pitch、pixel format、visible dimensionを保持します。

## Audio

通常clientはALSA `default`または`plumos_output` aliasを開きます。生成設定は
`/run/plumos/audio/`にあり、AArch64 ioplug routerが物理出力を選びます。

- 内蔵codec: 左右をmono mixし、共有0..12 software gainを適用し、card 0の`DAC volume`を
  `170,170`へ固定
- USB DAC: stereoを維持し、対応format・rateをnegotiate
- hotplug: gameを再起動せず、open済みstreamを内蔵とUSB出力間で移行

routerは一般的なapp formatを受け、物理deviceへ変換します。launcherが経路を準備して生成ALSA
設定をexportします。direct `hw:0,0`は診断専用です。ALSAを迂回するappには個別integrationが必要です。

global power overlayのcancelはpauseしたclientとaudio routeを再開し、standaloneやPPSSPPを無音の
まま残してはいけません。XRUN・suspend recoveryはrouterで行い、無関係errorを回復可能underrunと
誤認しません。

## Inputとglobal key

低レベル入力は`adc_gamepad`、`axp2202-pek`などStockOS kernel device由来です。FE、SDL2
launcher、PicoArch、standalone helperがD-pad、ABXY、shoulder、L2/R2、SELECT、START、
function、volume、power keyを正規化します。

global hardware-key serviceはFE、RA、PicoArch、standalone、Apps、PortMasterを通して常駐し、
次を所有します。

- volume key: 12段software volumeと書き込み回数を抑えた永続化
- SELECT + volume: backendがある場合の画面brightness
- power key: global power menu
- 対応launcherのsystem-wide emergency quit policy

入力readerを二重にせず、無制限key repeatを避けます。child固有input helperはchildと同時に
開始・終了します。

## CPUとGPU policy

CPU governor初期値は`ondemand`で、`performance`など公開済みdynamic governorをsystemごとに
選べます。固定周波数UIは非対応です。game別governor適用前に全CPUをonlineにし、過去の固定
min/max overrideを消します。通常終了でsystem policyへ戻します。

vendor PowerVR stackはFEから制御できる標準devfreq governorを公開していません。GPU governor
設定を表示してはいけません。idle GPU clockとsuspendはvendor power managementへ任せます。

## USBとNetwork

V90Sに内蔵Wi-Fiはありません。`plumos-network-control`が対応USB Wi-Fi interfaceを、制限時間付き
scan・connect・DHCP段階で制御します。`plumos-wifi-recovery`はnetlink ueventを待ち、ON状態の
dongleが再追加された時に1回だけ制限付きreconnectを行います。dongleがない時にpollし続けません。

`v90s-stockos-r1`に収録し、network controllerが読み込めるUSB Wi-Fi moduleは次の通りです。

| 種別 | kernel module |
| --- | --- |
| StockOS由来extra module | `8192eu`, `8723bu`, `8812au`, `8821cu`, `88x2bu` |
| vendor kernel標準module | `rtl8192cu`, `rtl8xxxu` |

実機確認済みの経路はUSB ID `0bda:c820`、module `8821cu`、interface `wlan0`です。
controllerには`8188eu`互換処理もありますが、`v90s-stockos-r1`には独立した
`8188eu.ko`を収録していないため、対応module一覧には含めません。製品名ではなく
`/sys/bus/usb/devices/*/idVendor`と`idProduct`を既存moduleの`modules.alias`へ照合します。
新しいmodule・firmwareをvendor runtimeへ追加する場合は、実機検証後にruntime IDを更新します。

network service状態は`/mnt/plumos/config/network/services.conf`へ保存します。controllerは
OpenSSH/SFTP、BusyBox FTP、Samba SMB2、ADB FunctionFSを所有します。IPv4なしでONになった
serviceはwaiting状態となり、FEをblockしません。SSH login PATHは
`/mnt/plumos/bin:/mnt/plumos/gnu/bin`を優先します。

認証契約は次の通りです。

| service | account | 認証 |
| --- | --- | --- |
| SSH/SFTP | `root` | release初期passwordなし。公開鍵または`plumos-ssh-password set`で作成した端末固有password |
| FTP | anonymous | `ftpd -A`。credentialを検証せず、書き込み可能 |
| Samba | client名`plumos`からlocal `root`へmap | 初期password `plumos`、guest不可、share名`SDCARD` |
| ADB | なし | USBローカルtransport、user/passwordなし |

SSHの端末固有shadowはp3の`/mnt/plumos/config/ssh/shadow`にだけ保存し、SquashFSの
`/etc/shadow`へbindします。release image、app-layer、gitへ生成済みshadowを取り込んでは
いけません。ユーザー向け資格情報を変更した場合は、実装と日英の`docs/user/network*`を
同じcommitで更新します。

ADBとUSB Disk Modeは同じUSB gadget controllerを使います。ADB uevent helperは外れたUDCを
修復できますが、mass storageが所有中のgadgetを奪ってはいけません。USB HUBの相性と供給電力は
物理的制約として残ります。

## Battery、RTC、Time

FE battery serviceはvendor power-supply sysfsを読み、範囲を制限したpercentage・statusを表示します。
利用可能ならkernel interfaceからRTCを設定します。自動時刻はWi-FiがIPv4を取得した後にnetwork
同期し、その時刻をRTCへ書きます。FE起動やPortMaster TLSを無期限にblockしません。

## 主な実装

- `package/audio-router-v90s/`
- `package/frontend-v90s/plumos/bin/plumos-audio-output`
- `package/frontend-v90s/plumos/bin/plumos-volume-control`
- `package/frontend-v90s/plumos/bin/plumos-hardware-keys-service`
- `package/frontend-v90s/plumos/bin/plumos-power-menu-overlay`
- `package/frontend-v90s/plumos/bin/plumos-display-control`
- `package/network-services/plumos/bin/plumos-network-control`
- `package/network-services/plumos/bin/plumos-wifi-recovery`
- `package/network-services/plumos/bin/plumos-adbd`
