# V90S PortMaster Game Input Validation

Date: 2026-07-19

## Symptom

PortMaster games rendered, and the one-second `Select+Start` emergency exit
worked, but the V90S controls did not operate the game. The reproduced title
was Donut Dodo.

The owned launch log showed the input helper failing before the Godot runtime
started:

```text
missing GPTokeYB: /mnt/plumos/apps/portmaster/upstream/PortMaster/gptokeyb
```

The binary existed and matched the packaged SHA-256, but its ext4 mode was not
executable:

```text
-rw-r--r-- gptokeyb
-rw-r--r-- gptokeyb2
```

The official ZIP extraction had produced mode `0644`. Content checksums did
not detect the problem because Unix mode is filesystem metadata.

## Fix

PortMaster adapter version 6 enforces the executable contract at three
boundaries:

- the reproducible `portmaster` build sets both AArch64 helpers to `0755`
- the staged online updater requires both files and sets `0755` before switch
- `plumos-portmaster-runtime prepare` repairs the active payload before every
  installed-port launch

The build excludes Python `__pycache__` and `.pyc` files from the packaged
adapter.

## Live Result

The running installation was repaired without changing the two binary
contents. Donut Dodo was relaunched from FE and had all three owned processes:

```text
frt_3.5.2 --resolution 640x480 -f --main-pack gamedata/DonutDodo.pck
plumos-portmaster-gptokeyb frt_3.5.2 -c ./donutdodo.gptk
PortMaster/gptokeyb frt_3.5.2 -c ./donutdodo.gptk
```

The user confirmed that game controls worked. After game exit, the strict app
layer was deployed as one verified 17-file payload chunk. Final device state:

```text
adapter_version=6
gptokeyb mode=0755
gptokeyb2 mode=0755
plumos-portmaster-runtime prepare=PASS
frontend=one process
PortMaster game/GPTokeYB processes=absent
ADB=running
changed-file checksums=PASS
```
