# Basic Operation

## Frontend Controls

| Control | Action |
| --- | --- |
| D-pad | Move the cursor or change a value |
| A | Open, confirm, or launch |
| B | Go back |
| Y | Add or remove a favorite where available |
| START | Open the START menu |
| SELECT | Open the emulator/profile selection menu |
| Power button | Open the power menu |
| Volume - / + | Change system volume through 12 steps |
| SELECT + Volume - / + | Change display brightness when supported |

The selected emulator may define additional in-game shortcuts. Use its menu to
review or change those bindings.

## Main Screens

- **TOP** lists systems that contain ROMs. UI Settings can also show empty
  systems, Favorites, and Recent.
- **ROM list** shows games for the selected system.
- **Gallery** shows available thumbnails and scrolls long titles.
- **START** opens UI, System, Network, Apps, Help, Restart, and Shutdown.
- **SELECT** chooses between available RetroArch, PicoArch, or standalone
  profiles for the current system.

After adding or removing ROMs, run `START -> UI Settings -> Refresh TOP`.

## Power Actions

Use Restart or Shutdown from the frontend or the power-button menu. Wait until
the operation finishes; controls are intentionally disabled while data is
being synchronized. Sleep uses suspend-to-RAM and resumes with the power button.

## Audio

The built-in speaker receives a mono mix so both stereo channels are audible.
A supported USB DAC receives stereo output. USB DAC insertion and removal may
be performed while a game is running; allow a moment for the route to switch.
