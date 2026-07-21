# V90S user-visible final validation

Date: 2026-07-22

The user confirmed the following behavior on the current four-partition V90S
system:

- safe poweroff followed by a normal cold boot
- built-in controls
- audio output
- known-good FPS, scrolling, and audio pitch
- SD2 game video, audio, controls, clean exit, and settings persistence
- `mem` sleep/resume across emulator and Apps use
- Pyxel gamepad control, game exit, and Python title operation
- NextCommander physical controls
- Music Player playback through ALSA
- usable Windows/macOS partition enumeration

The stable rootfs Wi-Fi/SSH initialization remains in place. Moving it into the
app layer is no longer a release requirement unless the current path develops a
specific fault.

The physical mid-write power-interruption test is intentionally excluded. Host
tests cover transaction journal recovery, and deliberately corrupting user
media is not required for release acceptance.

The following remain separate checks:

- macOS USB Disk Mode enumeration and USB command mailbox workflow
- host-readable update failure evidence on p4
- optional PortMaster runtime-family compatibility
- third-party license inventory and packaging
