plumOS V90S vendor runtime capture
Captured: 2026-07-15T06:30:48Z
Source: currently running, known-good V90S SD1 through plumOS ADB
Kernel: Linux 4.9.191
Boot layout: StockOS/Batocera-compatible p1-p7

This capture preserves the exact raw boot chain and p2/p3/p4 partitions from
the running SD. It also includes p1 boot resources, p6 boot configuration,
PowerVR userspace, Linux 4.9.191 modules, firmware, and SDL2 PowerVR runtime.

boot0_sha256=638d5d75f9d348a4fbcadb901a2c102fd88148900c3d186acc7ae6d4095784c4
boot_package_capture_sha256=69587a6ee20b4e6e7ad0f916f964e578660799370326d72fd53f8728ec2d41e9
knulli_cache_boot0_sha256=638d5d75f9d348a4fbcadb901a2c102fd88148900c3d186acc7ae6d4095784c4
boot0_matches_knulli_cache=yes

The captured boot0 may match the KNULLI cache because the currently running
baseline used that compatible V90S boot component. Image assembly consumes this
captured vendor input and does not invoke the KNULLI fallback path.

Sanitized for redistribution: yes
Removed fields: active rootshadowpassword, randomseed, Wi-Fi SSID/key values
ROM, BIOS, save, SSH key, and personal network content: not included
