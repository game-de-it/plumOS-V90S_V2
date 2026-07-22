# フロントエンドとエミュレータ統合

## フロントエンドのデータモデル

正式なsystem catalogは`package/frontend-v90s/plumos/config/frontend/systems.json`です。
各systemはROM root・alias、extension、thumbnail path、launch profile、default profileを
定義します。FEはactiveな`/mnt/plumos/roms`をscanし、設定を
`/mnt/plumos/config/frontend`へ保存し、画像を`/mnt/plumos/Images/<system>`から解決します。

TOP、ROM list、Gallery、START、SELECT、Apps、settings、progress、power viewはMMF由来の
data/theme modelを共有します。V90S rendererはvendor framebufferへ直接書き、固定page寸法、
CJK fallback fontを維持し、graphical TOP transitionをdisplay frame cadenceでanimateします。
TOP更新は進行画面を表示し、scan modelを原子的に置き換えます。

## launch profile契約

profile文字列はnamespaceを持ちます。

```text
retroarch:<core-id>
picoarch:<core-id>
standalone:<emulator-id>
```

FEはsystem ID、選択profile、content absolute path、active ROM root、BIOS root、save/state
directory、ownership tokenを管理launcherへ渡します。binary/coreとlauncher mappingがある
profileだけを表示し、人為的なruntime core allowlistは禁止します。

## RetroArch

所有binaryは`/mnt/plumos/bin/retroarch`です。launcherは`/run/plumos/retroarch/lib`へ
private runtime library treeを作り、`config/standalone/soname-links.tsv`からSONAME aliasも
生成します。directory設定は過去のlegacy値だけを書き換え、他のuser変更を保持します。

V90S初期値には次を含みます。

```text
video_driver = sdl2
video_context_driver = mali_fbdev
audio_driver = alsa
audio_device = plumos_output
input_driver = sdl2
input_joypad_driver = sdl2
```

既知良好なfactory configはversion付きbuild inputで、`factory-defaults/ra/`へ配置します。
factory reset時だけwritable configへコピーし、通常buildとlive deployでは使用中user configを
上書きしません。

## PicoArch

PicoArchはAArch64で`/mnt/plumos/cores`を共用し、2組目のcore setは持ちません。V90S patchが
direct framebuffer presentation、pixel format、aspect fit、controller init、content directory、
frame pacing、async audio callbackを担当します。通常audioは
`PLUMOS_PICOARCH_AUDIO_TARGET_FPS=0`でcore native clockを維持し、固定refresh由来targetは
診断用だけです。

## スタンドアローンエミュレータ

build targetは`ppsspp`、`scummvm`、`easyrpg`、`openbor`、`pcsx_rearmed`、`flycast`、
`mupen64plus`、`nxengine-evo`、`yabasanshiro`を扱います。userへ表示するものはsystem
catalogが決め、binaryをbuildしただけでdefault routeにはしません。

`plumos-standalone-launch`がemulator別workdir、XDG state、BIOS link、input helper lifetime、
PowerVR/SDL library、audio environment、PPSSPP factory設定、cleanupを所有します。採用済み
Saturn経路は、AArch64、V90S input、VDP1 readback、direct framebuffer用patchを含む固定
YabaSanshiro 2.10.4です。

## Apps、Pyxel、PortMaster

Appsも同じdisplay/input/power lifecycle上のforeground childです。NextCommanderとMusic
PlayerはV90S用にbuildしたnative appです。Pyxelは基本Python runtimeをSystem SquashFS、
user更新可能virtual environmentをp3へ置き、`roms/pyxel/requirements.txt`を専用setup appで
導入します。画面aspect fitとALSA/pygame routingはwrapper policyであり、user管理Pyxel
package自体は変更しません。

PortMasterは固定official GUI、V90S adapter、共通AArch64 ABI bundleを使います。導入済みportと
mutable PortMaster stateは実機所有です。32-bit PowerVR userspace driverがないためARMHF portは
非対応です。静的監査はlibrary package判断に使いますが、各runtime familyの実機lifecycle確認は
別途必要です。

## 設定の所有範囲

FEとemulatorが保存した設定を実機の正とします。build outputはversion付きfactory defaultと
冪等migrationを更新できますが、host configをactive設定へ自動上書きしません。RA、PicoArch、
standalone、PPSSPPのfactory reset経路は独立させます。
