# V90S UI Settings Runtime Validation

Date: 2026-07-12

## Scope

Validate that `START -> UI Settings` entries save correctly and affect the
frontend behavior that they control.

## Live Device

```text
ssh root@192.0.2.120
password: linux
PLUMOS_ROOT=/mnt/plumos
PLUMOS_SDCARD_ROOT=/mnt/plumos
```

The live `config/frontend/settings.json` was backed up before the test and
restored afterwards. The original and restored settings matched:

```text
ui=graphic top=graphic rom=graphic
show_empty_systems=false
show_favorites_on_top=true
show_recent_on_top=true
rom_cursor_wrap=true
boot_resume_mode=off
sort_systems=sort_order
sort_roms=name
rom_scan_policy=on_enter
graphic_theme_id=default
graphic_top_layout=
graphic_transition=
graphic_transition_ms=0
graphic_transition_axis=
graphic_transition_easing=
```

## Results

The following entries saved through the frontend controller UI script path:

```text
PASS refresh_top                 status: TOP refreshed
PASS ui_mode                     graphic -> text
PASS top_mode                    graphic -> text
PASS rom_mode                    graphic -> text
PASS show_empty_systems          false -> true
PASS show_favorites_on_top       true -> false
PASS show_recent_on_top          true -> false
PASS rom_cursor_wrap             true -> false
PASS boot_resume_mode            off -> on
PASS sort_systems                sort_order -> name
PASS sort_roms                   name -> path
PASS rom_scan_policy             on_enter -> manual
PASS graphic_theme_id            default -> default-horizontal
PASS theme_id                    default-horizontal
PASS theme_top_layout            tile_strip
PASS theme_transition            none
PASS theme_transition_ms         980
PASS theme_transition_axis       horizontal
PASS theme_transition_easing     linear
```

Behavior checks:

```text
show_empty_systems_visible       top_count 18 -> 76
show_favorites_on_top_visible    top_count 18 -> 17
show_recent_on_top_visible       top_count 18 -> 17
sort_systems_visible             first TOP NES -> Favorites
rom_cursor_wrap_behavior         disabled wrap keeps cursor=1 after UP
boot_resume_recent_behavior      startup opened RECENT screen
```

For the live NES library, `sort_roms=name` and `sort_roms=path` currently show
the same first visible ROM because the file names and titles are already aligned.
An isolated temporary root with two ROM-cache entries confirmed the runtime sort
switch:

```text
sort_roms=name first: Alpha Title  nes/zzz.nes
sort_roms=path first: Zeta Title   nes/aaa.nes
```

`boot_resume_mode=on` was not executed during this validation because that path
can launch RetroArch and take over the device display. The non-destructive
`recent` startup path was validated instead.

## Notes

No frontend code changes were required. The only repository changes for this
pass are this validation note and the TODO completion entry.
