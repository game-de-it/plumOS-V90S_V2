# V90S Graphic TOP 60 Hz Slide Validation

Date: 2026-07-19

## Scope

The Graphic TOP controller already emitted the same page-transition contract
as MMF and A30, but the V90S fbdev renderer ignored it. Moving the cursor from
one six-system page to the next therefore changed the whole page immediately.

## Implementation

The V90S fbdev path now consumes:

```text
graphic_prev_entry
graphic_transition=slide
graphic_transition_direction
graphic_transition_progress
graphic_theme_motion transition_axis
graphic_theme_motion transition_easing
```

It draws the previous page leaving the display and the current page entering
it, then draws the TOP status bar and left accent as fixed overlays. Both the
MMF/A30 vertical and horizontal transition axes are supported. The default
theme remains aligned with those devices: a one-second vertical smoothstep
slide.

While a TOP transition is active, the fbdev event loop schedules a frame every
16 ms. The existing renderer waits for VSync and presents completed frames by
switching between the two framebuffer pages. Off-screen rectangle and PNG
drawing is clipped before pixel iteration so the slide does not spend time
walking invisible tile regions.

## Build

```text
./scripts/docker-build.sh frontend
./scripts/docker-build.sh app-layer --strict
./scripts/docker-build.sh preflight
```

All commands passed. The strict app-layer checksum set also passed.

The AArch64 frontend artifact and staged app-layer binary are identical:

```text
11d7b32db27723832521d0329b0263fc97cd088a9ecea2656c1a79bedfb0817a
```

## Live Deployment

The binary was transferred over ADB and hash-checked before activation. Only
the managed frontend was stopped; ADB and network services were not included
in the stop operation.

The live binary hash matches the build artifact:

```text
11d7b32db27723832521d0329b0263fc97cd088a9ecea2656c1a79bedfb0817a
```

The active display and framebuffer layout are:

```text
mode=U:640x480p-60
virtual_size=640,960
```

This gives a 60 Hz panel with two 640x480 pages. The 16 ms transition cadence
is therefore bounded by the existing VSync page flip at the panel refresh.

## Physical Result

The user moved across a Graphic TOP page boundary on the physical V90S and
confirmed that the screen now scrolls visibly. After the automated input test,
the frontend was restored to its normal launch contract:

```text
frontend_processes=1
stdin=/dev/null
renderer=fbdev
```

No framebuffer renderer error was recorded during the test.
