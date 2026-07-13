# V90S Flycast performance validation

Date: 2026-07-14

## Test conditions

- Device: POWKIDDY V90S
- Content: `Crazy Taxi (Japan).chd`
- CPU governor: `performance`
- Online CPUs: 0-3
- Observed CPU clock: 1.8 GHz
- Observed GPU clock: 702 MHz
- Display path: StockOS PowerVR/fbdev runtime

The FPS samples below were captured from the V90S framebuffer while gameplay
was active. They are observations from different gameplay scenes, not a
controlled same-frame benchmark.

## Results

### Standalone Flycast 2.6

- Repeated PowerVR HWR events occurred.
- Depending on the scene, output was black, corrupted, or briefly visible.
- Disabling threaded rendering reduced the symptom temporarily but did not
  prevent HWR events from returning.
- This path is retained only as a manual diagnostic profile.

### Standard libretro Flycast

- PowerVR HWR count remained zero.
- ALSA underrun count remained zero.
- One gameplay sample displayed 32.87 FPS.
- The main emulation thread was approximately 100% busy; the render thread was
  approximately 65-90% busy depending on the scene.

### Flycast Xtreme libretro

- Built from `metallic77/flycast` commit
  `603814c9f73b773c455d9a497f389d2f93a257fd`, matching the A133-oriented KNULLI
  core selection.
- PowerVR HWR count remained zero.
- ALSA underrun count remained zero.
- At 640x480, one gameplay sample displayed 44.23 FPS.
- At 320x240, another gameplay sample displayed 36.35 FPS and did not show a
  meaningful reduction in CPU load.
- The main emulation thread remained approximately 100% busy. This identifies
  single-thread CPU performance as the principal limit in heavy scenes.

## Decision

- Use Flycast Xtreme libretro as the default Dreamcast profile.
- Keep internal resolution at 640x480; 320x240 did not provide a useful
  performance benefit in the live test.
- Use the `performance` CPU governor and four online CPU cores for Dreamcast.
- Keep standard libretro Flycast and standalone Flycast available as explicit
  manual profiles, without automatic fallback.
- Treat sub-60 FPS in demanding Dreamcast scenes as a V90S CPU performance
  limit unless a later dynarec/core optimization demonstrates otherwise.
