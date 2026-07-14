# V90S FE All-Core Runtime Validation

Date: 2026-07-14

## Scope

Validate every deployed libretro core that can currently be reached from the
frontend with compatible indexed content. A pass requires all of the following:

- the frontend launch plan accepts the selected system, ROM, and profile;
- the expected `*_libretro.so` appears in the live RetroArch command line;
- RetroArch remains alive through the observation window;
- `/dev/fb0` can be read and hashed while that core is active;
- RetroArch stops through the PID-aware helper and exactly one FE is restored.

The reusable host runner is `scripts/v90s-fe-core-smoke-test.sh`. Raw captures
are written below ignored `output/validation/v90s-fe-core-smoke-*` directories.

## Coverage

- Deployed and hash-checked cores: **117**
- Cores declared in FE launch profiles: **112**
- Cores with an FE profile and compatible indexed content: **86**
- Confirmed running through the FE: **82**
- Core started but currently blocked: **4**
- Profile exists, but compatible indexed content is absent: **26**
- Profile/content definition is absent: **5**

The 31 cores without compatible selectable content cannot honestly be runtime
tested from the FE. They remain packaged and are listed below instead of being
reported as passes.

## Confirmed Running

The following 82 unique core binaries remained active and exposed a readable
framebuffer after FE launch:

```text
a5200 atari800 beetle_saturn bluemsx cannonball cap32 chimerasnes crocods
dinothawr easyrpg fake08 fbneo fceumm flycast freechaf freeintv frodo fuse
gambatte gearboy gearsystem genesis_plus_gx gme gpsp gw hatari
km_duckswanstation_xtreme_amped km_puae_xtreme_amped lowresnx lutro
mednafen_gba mednafen_ngp mednafen_pce mednafen_pce_fast mednafen_pcfx
mednafen_saturn mednafen_supafaust mednafen_supergrafx mednafen_wswan meteor
mgba nekop2 neocd nestopia np2kai numero nxengine o2em opera parallel_n64
pcsx_rearmed picodrive pokemini potator prboom prosystem puae puae2021 quasi88
quicknes retro8 scummvm snes9x snes9x2002 snes9x2005 snes9x2005_plus
snes9x2010 squirreljme stella2014 tgbdual theodore tyrquake uae4arm uw8 uzem
vba_next vbam vemulator vice_x64 vice_xvic virtualjaguar yabasanshiro
```

The newly enabled content-bearing systems are 3DO, Dreamcast, Saturn, N64,
PC-FX, MicroW8, Uzebox, Atari Jaguar, and Dreamcast VMU. VMU scanning now
accepts `.vmi` content.

## Current Blockers

| Core | Result | Evidence and next action |
| --- | --- | --- |
| `chailove` | runtime incompatible | Core loads, but its statically embedded SDL reports `No available video device`. Rebuild/port its internal SDL video path for V90S. |
| `fbalpha2012` | content rejected | Core loads, but the available `fatfury1.zip` and Neo Geo BIOS do not match the old FBA 2012 ROM-set CRCs. Test with a matching ROM set. |
| `fbalpha2012_neogeo` | content rejected | Same FBA 2012 ROM-set mismatch as above. |
| `mupen64plus_next` | SIGSEGV | Rebuilt for AArch64 Cortex-A53 GLES2. It still exits at R4300 start with both dynarec and cached interpreter, and with GLideN64 or Angrylion selected. `parallel_n64` is the working N64 default. |

## No Compatible Indexed Content

These 26 cores have FE profiles but no compatible indexed ROM on the current
SD cards:

```text
2048 81 bk daphne dosbox_pure dosbox_pure_0.9.7 ecwolf
fbalpha2012_cps1 fbalpha2012_cps2 fbalpha2012_cps3 fmsx handy
km_mame2003_xtreme mame2000 mame2003_plus mba_mini mednafen_lynx
mednafen_vb mrboom mu px68k reminiscence tic80 vecx x1 xrick
```

These five packaged cores do not yet have a compatible FE system/content
definition: `arduous`, `gong`, `km_superbroswar`, `puzzlescript`, and
`sameduck`.

## Build Corrections

The first run exposed host-platform recipes in three hardware-rendered cores.
The recipes now use V90S-compatible targets:

- Flycast: `arm64_cortex_a53_gles2`
- Mupen64Plus-Next: `arm64_cortex_a53_gles2`
- ParaLLEl-N64: `ARCH=aarch64 FORCE_GLES=1` (initial core-load test only)

Flycast passed after rebuilding. ParaLLEl-N64 passed the initial core-load
check, but a later visual test found that this build produced audio over a
black framebuffer. The KNULLI A133/H5 replacement and full video/input result
are recorded in
`docs/validation/2026-07-15-v90s-parallel-n64-knulli-a133.md`. The frontend
defaults N64 to `parallel_n64`, while keeping `mupen64plus_next` selectable for
later work. The final host core and app-layer outputs each contained 117 cores
and passed their SHA-256 manifests at the time of this matrix.

## Final Device State

```text
cores=117
frontend=1
retroarch=0
flycast=9d88a8421f3035ff41f06d7eca13358a0b1798441b707edb85f54eec8c5120a1
mupen64plus_next=0a26dd1e28a7693d74c73a948e1acd2defc8627177969e0a293f6afe7a76ff8c
parallel_n64=b1b1cee04f552bed8809cdbedf691a2a7be2818b9e91d4df3ebae9f5013bb662
```

No broad process-name kill was used. Every test stopped RetroArch with
`/mnt/plumos/bin/v90s-retroarch-stop`, and the final FE process count is one.
