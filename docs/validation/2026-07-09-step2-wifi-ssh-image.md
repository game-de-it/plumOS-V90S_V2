# Step 2 Wi-Fi SSH Image

Date: 2026-07-09

## Purpose

The fifth Step 2 image proved that Debian RetroArch reaches a running state with:

- NES core and ROM loaded
- SDL2 `mali` window created
- ALSA opened
- `adc_gamepad` detected

The V90S LCD still does not show useful RetroArch video. The next iteration should happen on the live device over SSH, so this image adds Wi-Fi and SSHD before RetroArch starts.

## Build Inputs

Secrets were passed at build time only and are not recorded in git:

- Wi-Fi SSID configured: yes
- Wi-Fi PSK configured: yes, redacted from docs/git
- SSH authorized key source: `/Users/example/.ssh/id_ed25519.pub`
- SSH root password configured: yes, redacted from docs/git

The public key was copied to ignored workspace cache as `.cache/v90s-authorized_keys.pub` for the Docker build.

## Build Commands

```sh
cp /Users/example/.ssh/id_ed25519.pub .cache/v90s-authorized_keys.pub

./scripts/run-assembly-tools.sh ./scripts/build-step1-rootfs.sh \
  --profile debian-retroarch-pvr-sdl2 \
  --out-dir output/rootfs-step2-pvr-sdl2-ssh \
  --rom "artifacts/nes/Super Mario Bros..nes" \
  --wifi-ssid "<configured at build time>" \
  --wifi-psk "<redacted>" \
  --ssh-authorized-keys .cache/v90s-authorized_keys.pub \
  --ssh-root-password "<redacted>"

./scripts/run-assembly-tools.sh ./scripts/assemble-v90s-image.sh \
  --rootfs output/rootfs-step1/stage1-userdata-loader.squashfs \
  --userdata-payload output/rootfs-step2-pvr-sdl2-ssh/debian-bookworm-retroarch-pvr-sdl2-step2.squashfs \
  --boot-vfat-size 33M \
  --userdata-size 512M \
  --diagnostic-init \
  --name plumos-v90s-armbian-step2-20260709-6-wifi-ssh.img
```

## Artifacts

```text
output/images/plumos-v90s-armbian-step2-20260709-6-wifi-ssh.img
sha256: 70cbf6e8edf837ef5d9d3e08a5ed632ba643fce094f08090feeb6276ea874bbc
size: 581M

output/rootfs-step2-pvr-sdl2-ssh/debian-bookworm-retroarch-pvr-sdl2-step2.squashfs
sha256: 422bc36a8aeb2530377e1402402b2c366150ad76b86a523e4336027285f76909
size: 442M
```

The FAT boot-resource partition remains 33MB. The userdata partition remains 512MB.

## Payload Verification

The payload release file includes the network packages:

```text
packages=retroarch,libretro-nestopia,alsa-utils,input-utils,procps,psmisc,kmod,openssh-server,wpasupplicant,isc-dhcp-client,iproute2,rfkill,iw,wireless-regdb,ca-certificates
power_pvr_probe=1
custom_sdl2_mali=1
```

Network/SSH release state:

```text
wifi_configured=yes
ssh_authorized_keys=yes
ssh_password_auth=yes
```

SSHD configuration:

```text
PermitRootLogin yes
PasswordAuthentication yes
PubkeyAuthentication yes
KbdInteractiveAuthentication yes
UsePAM no
PermitEmptyPasswords no
AuthorizedKeysFile .ssh/authorized_keys
```

Verified without printing secrets:

```text
wpa-ssid-ok
authorized-key-ok
root-password-hash-ok
```

Useful runtime files are present:

```text
/usr/local/sbin/v90s-network-ssh-init
/root/.ssh/authorized_keys
/etc/wpa_supplicant/wpa_supplicant.conf
/usr/sbin/sshd
/usr/sbin/wpa_supplicant
/usr/sbin/dhclient
/usr/lib/firmware/fw_xr829.bin
/usr/lib/modules/4.9.191/kernel/drivers/net/wireless/rtl8723ds/8723ds.ko
/usr/lib/modules/4.9.191/extra/8723bu.ko
/usr/lib/modules/4.9.191/xradio_wlan.ko
```

## Expected FAT Logs

After boot, inspect:

```text
/Volumes/KNULLI/plumos-logs/plumos-v90s-network-ssh.log
/Volumes/KNULLI/plumos-logs/ssh-connect.txt
/Volumes/KNULLI/plumos-logs/plumos-v90s-debian-init.log
/Volumes/KNULLI/plumos-logs/plumos-v90s-retroarch-launch.log
/Volumes/KNULLI/plumos-logs/plumos-v90s-retroarch.log
```

`ssh-connect.txt` should contain a command like:

```text
ssh root@<v90s-ip-address>
```

If `ssh-connect.txt` is absent, use `plumos-v90s-network-ssh.log` to check:

- whether a Wi-Fi interface appeared
- whether `8723ds`, `8723bu`, or xradio module probing worked
- whether `wpa_supplicant` reached `wpa_state=COMPLETED`
- whether DHCP assigned an IPv4 address
- whether `sshd` started

