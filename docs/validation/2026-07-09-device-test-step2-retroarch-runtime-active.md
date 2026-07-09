# Device Test: Step 2 RetroArch Runtime Active But Not Visible

Date: 2026-07-09

## Tested Image

```text
output/images/plumos-v90s-armbian-step2-20260709-5-retroarch-timeout-log.img
sha256: b098ae5474b7517980810245c4227384e04a5d0a621e1e98e23e99acfb57c298
```

User result:

- RetroArch did not appear on the V90S LCD.
- SD card was returned to macOS and FAT logs were inspected.

## FAT Logs Present

```text
/Volumes/KNULLI/plumos-logs/session.txt
/Volumes/KNULLI/plumos-logs/plumos-v90s-diag.log
/Volumes/KNULLI/plumos-logs/plumos-v90s-debian-init.log
/Volumes/KNULLI/plumos-logs/plumos-v90s-pvr-probe.log
/Volumes/KNULLI/plumos-logs/plumos-v90s-retroarch-launch.log
/Volumes/KNULLI/plumos-logs/plumos-v90s-retroarch.log
```

The new runtime log persisted successfully. This confirms the timeout-log image fixed the previous missing-log problem.

## Key Findings

PowerVR and SDL2 `mali` still initialize:

```text
sdl2-probe: current_video_driver=mali
sdl2-probe: joystick[0]=adc_gamepad
MALI_CreateWindow:0xaaaae3741280 done.
sdl2-probe: SDL_CreateWindow ok
sdl2-probe: SDL_GL_CreateContext ok
sdl2-probe: ok
```

RetroArch reaches the first attempt:

```text
retroarch-launch: attempt=1 video=sdl2 input=sdl2 joypad=sdl2 audio=alsa sdl_video=mali
retroarch-launch: attempt=1 pre-launch sync complete
```

`plumos-v90s-retroarch.log` shows that this is not a pre-launch failure. RetroArch loads the NES core and ROM, initializes audio, sees the 640x480 display, and creates the SDL2 Mali window:

```text
[INFO] [Core]: Loading dynamic libretro core from: "/usr/lib/aarch64-linux-gnu/libretro/nestopia_libretro.so"
[INFO] [Content]: Loading content file: "/roms/nes/Super Mario Bros..nes".
[libretro INFO] [Nestopia]: Machine is NTSC.
[INFO] [Audio]: Set audio input rate to: 48000.00 Hz.
[INFO] [Video]: Set video size to: fullscreen.
[INFO] [SDL2]: Available renderers (change with $SDL_RENDER_DRIVER):
[INFO] 	opengles2
[INFO] 	opengles
[INFO] 	software
[INFO] [SDL2]: Available displays:
[INFO] 	Display #0 mode: 640x480@60hz.
MALI_CreateWindow:0xaaaaf2deb740 done.
[INFO] [Joypad]: Found joypad driver: "sdl2".
[INFO] [ALSA]: Using floating point format.
[INFO] [ALSA]: Period size: 768 frames
[INFO] [ALSA]: Buffer size: 3072 frames
[INFO] [ALSA]: Can pause: yes.
```

The last useful lines are:

```text
[INFO] [Display]: Found display driver: "null".
[ERROR] [Core Info] Failed to write to core info cache file: /usr/share/libretro/info/core_info.cache
[INFO] [Autoconf]: adc_gamepad (307/4496) not configured, using fallback.
```

There is no `attempt=1 exited rc=124` or timeout marker in the launcher log. The device was likely powered off before the timeout loop could finish, or RetroArch entered a running state that kept the launcher blocked while the last mirrored log captured the early runtime state.

## Interpretation

The current failure is narrower than before:

- Kernel boot and Debian payload handoff work.
- PowerVR starts.
- KNULLI-derived SDL2 `mali` opens an EGL window.
- RetroArch loads the NES core and ROM.
- ALSA opens the audio device.
- SDL2 sees `adc_gamepad`, but there is no autoconfig profile yet.
- The missing piece is useful on-screen rendering from Debian RetroArch after its SDL2/Mali window is created.

The fastest next step is live iteration over SSH instead of continuing blind image flashes.

## Next Image

Build a Wi-Fi/SSHD image so the running device can be inspected while RetroArch is black:

- start network/SSH before launching RetroArch
- save `plumos-v90s-network-ssh.log` to FAT
- save `ssh-connect.txt` to FAT when an IP address is acquired
- allow both public-key and password SSH authentication

