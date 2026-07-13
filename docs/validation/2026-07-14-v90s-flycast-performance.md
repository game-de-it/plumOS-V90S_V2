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
- Correcting the command-line key to
  `config:rend.ThreadedRendering=no` removed HWR in a later run, but the game
  still became black and audio performance became worse.
- Forcing the V90S GLES2 texture-backed path made game RGB visible. It reached
  about 46 FPS, but audio still stuttered and textures were missing.
- 240p, disabled modifier volumes/mipmaps, a larger audio buffer, and one level
  of automatic frame skipping did not materially improve the result.
- This binary is retained for direct diagnostics but is not exposed by the FE.

### Standard libretro Flycast

- PowerVR HWR count remained zero.
- ALSA underrun count remained zero.
- One gameplay sample displayed 32.87 FPS.
- The main emulation thread was approximately 100% busy; the render thread was
  approximately 65-90% busy depending on the scene.

### Flycast Xtreme libretro

- The original build test accidentally used repository HEAD because failed
  commit checkout was masked by later cleanup commands. The build script now
  fetches, checks out, and verifies the requested commit before compiling.
- The accidentally built HEAD binary displayed 44.23 FPS in one 640x480 scene.
  At 320x240, another scene displayed 36.35 FPS and did not show a meaningful
  reduction in CPU load.
- The corrected binary is built from `metallic77/flycast` commit
  `603814c9f73b773c455d9a497f389d2f93a257fd`, matching the A133-oriented KNULLI
  core selection.
- The corrected binary displayed normal video and audio at about 34 FPS in a
  heavy city scene. PowerVR HWR and ALSA underrun counts did not increase.
- The main emulation thread remained approximately 100% busy. This identifies
  single-thread CPU performance as the principal limit in heavy scenes.
- The corrected KNULLI-pinned binary therefore matches the user's prior
  experience rather than providing a new performance gain.

## Decision

- Use Flycast Xtreme libretro as the default Dreamcast profile.
- Keep internal resolution at 640x480; 320x240 did not provide a useful
  performance benefit in the live test.
- Use the `performance` CPU governor and four online CPU cores for Dreamcast.
- Keep standard libretro Flycast as an explicit alternate FE profile.
- Keep standalone Flycast outside the FE and invoke it only for direct
  diagnostics, without automatic fallback.
- Treat sub-60 FPS in demanding Dreamcast scenes as a V90S CPU performance
  limit unless a later dynarec/core optimization demonstrates otherwise.
