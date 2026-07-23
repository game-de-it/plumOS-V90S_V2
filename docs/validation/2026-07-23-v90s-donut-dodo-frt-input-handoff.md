# V90S Donut Dodo FRT Input Handoff Validation

Date: 2026-07-23

## Symptom

After Donut Dodo was reinstalled through PortMaster, the game rendered and
played audio but did not react to the V90S controls. The owned processes were
present, and GPTokeYB had opened the physical controller:

```text
gptokeyb -> /dev/input/event4 (adc_gamepad)
```

FRT had opened only the board keys, power key, and audio-jack switch. It had
not opened GPTokeYB's `/dev/input/event5 (Fake Keyboard)`, so the configured
keyboard events could not reach Godot.

## Root Cause

The upstream port script backgrounds GPTokeYB and immediately starts
`frt_3.5.2`. On this image, FRT completed its SDL input enumeration before
GPTokeYB created the uinput keyboard. Starting FRT first was also tested and
did not help: this port consumes GPTokeYB's virtual keyboard rather than the
physical controller directly.

## Fix

PortMaster adapter version 11 keeps the checksum-addressed extracted runtime
unchanged. For `frt_*.squashfs` only, the mount shim bind-mounts a plumOS
launcher over the visible FRT executable. The launcher waits up to two seconds
for an input device named `Fake Keyboard`, then executes the original cached
runtime. A timeout still starts FRT so ports without GPTokeYB retain a bounded
fallback. Other runtimes are unchanged.

The nested bind mount is recorded after the runtime-directory mount, so the
existing reverse-order cleanup removes it first.

## Automated Validation

```text
python3 -m unittest discover -s tests -p 'test_*.py' -v
Ran 22 tests
OK
```

The three new tests cover a ready virtual keyboard, the timeout fallback, and
the directory-plus-executable bind-mount order without modifying the runtime
cache.

## Live Result

The adapter was rebuilt from the pinned PortMaster release and deployed as one
verified six-file payload chunk plus app-layer metadata. No installed port,
save, PortMaster upstream payload, or user setting was copied from the device.

The persistent adapter v11 launch produced:

```text
[GPTK]: Joystick 0 has device name 'adc_gamepad'
[GPTK]: Running in UINPUT output mode.
[plumOS] FRT input handoff: Fake Keyboard ready

gptokeyb -> /dev/uinput, /dev/input/event4
frt_3.5.2 -> /dev/input/event0, event1, event3, event5
```

This proves the previously missing game-input route is attached. Physical
button-response confirmation remains a user-facing hardware check; it is not
inferred from process presence alone.
