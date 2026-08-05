# Animation Parity Reference

This document is the source of truth for how `WinSwiftUI`'s animation
defaults map to Apple SwiftUI on macOS. Every numeric value here is
machine-checked by `AnimationDefaultsTests` and
`AnimationParityReferenceTests`. If you adjust a constant in
`SwiftUITypes.swift` without updating this table the test suite fails.

## Static eases

| Static                | Duration | Easing      | Notes                                                                 |
|-----------------------|----------|-------------|-----------------------------------------------------------------------|
| `Animation.default`   | 0.35s    | `.easeInOut`| Matches SwiftUI's documented `animation()` default duration.          |
| `Animation.linear`    | 0.35s    | `.linear`   | Inherits the default duration; only the curve changes.                |
| `Animation.easeIn`    | 0.35s    | `.easeIn`   | "                                                                     |
| `Animation.easeOut`   | 0.35s    | `.easeOut`  | "                                                                     |
| `Animation.easeInOut` | 0.35s    | `.easeInOut`| "                                                                     |

## Named springs

These mirror SwiftUI's iOS 17 / macOS 14 `Animation.spring(duration:extraBounce:)`
where `dampingFraction = 1 − extraBounce`.

| Static                 | Response | DampingFraction | Bounce (SwiftUI) |
|------------------------|----------|-----------------|------------------|
| `Animation.spring`     | 0.55     | 0.825           | 0.175            |
| `Animation.smooth`     | 0.5      | 1.0             | 0.0              |
| `Animation.snappy`     | 0.5      | 0.85            | 0.15             |
| `Animation.bouncy`     | 0.5      | 0.7             | 0.3              |
| `Animation.interactiveSpring()` | 0.15 | 0.86       | 0.14             |

## Function-style factories

| Factory                                              | Behaviour                                                     |
|------------------------------------------------------|---------------------------------------------------------------|
| `Animation.spring(response:dampingRatio:blendDuration:)` | Direct spring constructor. Defaults match `Animation.spring`. |
| `Animation.spring(duration:bounce:)`                 | Converts to `spring(response: duration, dampingRatio: 1 − bounce)`. |
| `Animation.smooth(duration:extraBounce:)`            | `spring(duration:, bounce: extraBounce)`.                     |
| `Animation.snappy(duration:extraBounce:)`            | `spring(duration:, bounce: 0.15 + extraBounce)`.              |
| `Animation.bouncy(duration:extraBounce:)`            | `spring(duration:, bounce: 0.3 + extraBounce)`.               |
| `Animation.linear(duration:)` / `easeIn(duration:)` / `easeOut(duration:)` / `easeInOut(duration:)` | Override the default 0.35s duration. |
| `Animation.interpolatingSpring(mass:stiffness:damping:initialVelocity:)` | Maps physical parameters to a response/damping pair. |
| `Animation.timingCurve(_:_:_:_:duration:)`           | Cubic-bezier curve over `duration` (default 0.35s).            |
| `.speed(_:)` / `.delay(_:)`                          | Scale or offset the duration in place.                        |

## Scroll animation timing

| Value                                            | Notes |
|--------------------------------------------------|-------|
| Wheel momentum decay half-life                   | ~0.115s (`exp(-6.0 * t)`)                                     |
| Wheel impulse factor                             | 5.0× the immediate offset jump produces velocity (px/s).      |
| Rubber-band stiffness `k`                        | 180                                                           |
| Rubber-band damping `c`                          | 27 (slightly under critical for `m = 1`)                      |
| Rubber-band maximum overshoot                    | 80 logical px                                                 |
| Keyboard-scroll viewport tween duration          | 0.22s ease-out (cubic)                                        |

## Control transitions

| Constant                                  | Value | Notes                                                  |
|-------------------------------------------|-------|--------------------------------------------------------|
| `ControlAnimationStyle.default.focusDuration`   | 0.18s | Hover / focus cross-fade.                              |
| `ControlAnimationStyle.default.pressDuration`   | 0.14s | Press-state colour cross-fade.                         |
| Focus-ring width tween                          | 0 → `MacOSControlMetrics.FocusRing.strokeWidth` over `focusDuration`, ease-out. |
| `ControlAnimationStyle.default.pressedScale`    | 1     | **A macOS control does not scale on press.** See below. |
| `ControlAnimationStyle.tactilePressedScale`     | 0.97  | The shrink, kept as an opt-in for a style that asks.    |
| `ControlPalette.pressedContentOpacity`          | 0.72  | Borderless styles only: AppKit darkens *contents* when there is no bezel. |

## Press feedback is a fill change, not a transform

A pressed AppKit control is drawn in exactly the frame it had at rest. The
feedback is the cell's highlight — `NSButtonCell` moves its bezel fill (darker
in the light appearance, brighter in the dark one), `NSSegmentedControl`
washes the pressed segment, `NSPopUpButton`, `NSStepper` and `NSSwitch` do the
same. Nothing in AppKit shrinks, lifts or nudges a control under the pointer,
in any macOS from Big Sur through Sonoma.

This stack shipped `pressedScale = 0.97` as the default for a while, pinned in
three tests and both parity documents as "the Big Sur feel". It was not: a
press shrink is an iOS / custom-`ButtonStyle` idiom
(`scaleEffect(configuration.isPressed ? 0.97 : 1)`), and parity is the standard
this project is held to. It survived because nothing rendered a pressed control
until the gallery's interaction-state tier existed, and by then it read as
intentional. `ControlAnimationStyle.default.pressedScale` is now `1`, and a
default control installs **no** transform animation on pointer-down at all.

Two consequences worth stating:

- **The fill ramp is now the whole affordance**, so a rung that was only just
  visible is no longer good enough. An unselected segment used to press to
  `tertiaryFill`, one rung above its own hover — measured against the
  segmented track that is a 10/255 step, with the shrink carrying the rest of
  what the eye read. It presses to `systemFill` now (a ~20/255 step, in line
  with the ~28/255 a push button moves). `Toggle`'s switch used to answer a
  press by painting an opaque pale blue (`#B8D1EB`) plate behind itself, in
  *both* appearances; it uses the appearance's own neutral wash now.
- **A style with no bezel has nothing to move**, so `.plain` / `.borderless` /
  `.link` would have had no press feedback whatsoever. AppKit's answer for a
  borderless button is `contentsCellMask` — it darkens the button's contents —
  which is `SurfacePalette.pressedContentOpacity`, set for those styles only.

The machinery is intact: `ControlAnimationStyle(pressedScale:)` still takes a
scale, `Controls.button` still animates one, and `tactilePressedScale` is the
0.97 for a style that deliberately wants it. What changed is what a control
gets when it does not ask.

### The durations, reviewed

`focusDuration` 0.18s and `pressDuration` 0.14s were reviewed against macOS
feel alongside the scale decision and left alone. They sit in the right band:
AppKit's hover and focus-ring cross-fades are around a sixth of a second, and
the press highlight is quicker than the hover it replaces, which is the
ordering these two encode. The one known simplification is that AppKit's press
highlight snaps in faster than it fades out, where this stack uses one duration
in each direction — not worth churning a constant over without a measurement to
move it to.

`activationDuration` is gone, and with it `SurfacePalette.activated`,
`SurfaceChrome.borderActivatedColor` and `shadowActivatedColor`. There is no
third colour past `pressed` on macOS: `NSButtonCell` releases its highlight on
mouseUp and *then* sends the action. Here the activation tween animated to
`palette.activated`, which every appearance-resolved ramp set equal to
`palette.pressed` — so it parked the control on its held-down fill and nothing
was scheduled to leave it. Measured: a clicked button held bg alpha 0.220 for
three seconds with `hasActiveAnimations` false from 0.3s, recovering only when
the pointer left the control. Pointer-up now resolves the ramp against the
phase the pointer is actually in, which is hover.

## Interaction chrome is runtime-resolved, not build-installed

A control's state colours are data on the node
(`ViewNode.interactionSurface: RetainedInteractionSurface`) and the runtime
resolves them against `hoveredNode` / `focusedNode` / `pressedNode`, the three
things a view build cannot know. `ComponentHost.reload()` ends by calling
`RetainedViewRuntime.restoreInteractionChrome()`, which re-applies them
**instantly** — a rebuild is not an interaction, and the chrome it restores was
already on screen a frame ago, so replaying the 0.18s ramp would be a flicker.

This replaced six closures per control over a build-scope interaction state,
which had two failures a fill ramp cannot survive:

- `updateNodeProperties` overwrites `backgroundColor`, `borderColor`,
  `outlineColor` and `shadowColor` from the fresh build on every
  reconciliation, so any `@State` change anywhere in the window repainted every
  control under the pointer at its **idle** fill — permanently, because the
  pointer was already inside and `updateHoverTarget` returns early when the hit
  node has not changed. `WinSwiftUI`'s `invalidateHandler` reloads
  synchronously, so this was every state change in every app.
- The closures captured the node of the build that installed them, and the
  reconciler copies closures onto the retained node. After one rebuild they
  animated a discarded orphan, so hover, focus and press did nothing at all on
  that control for the rest of the session — leaving and re-entering included.

## One focus ring, one owner

`ViewNode.focusEffectCommands` — a hardcoded 2pt
`Color(0.25, 0.55, 1, 0.75)` halo, unaware of both the appearance palette and
the animation clock — stands down for any node that paints its own ring
(`interactionSurface.focusRingColor` set, or a non-zero `outlineWidth`). It
remains the fallback for a focusable node with no ring of its own.

A focused bordered button used to carry both: a scanline through its edge read
two 2px bands of different blue (light appearance: `106,173,246` beside
`47,140,252`), on two timelines — the runtime's halo at full strength on frame
zero, the control's own ring fading in behind it over 0.18s, so mid-fade the
outer band was still grey next to a solid blue inner one. The survivor is the
control's ring: appearance-resolved, animated on the injected clock, and its
width is the pinned `MacOSControlMetrics.FocusRing.strokeWidth`.

The ring's width animates alongside its colour (0 → `focusRingWidth`,
ease-out, over `focusDuration`). AppKit's ring is not an alpha cross-fade; it
expands from the control bounds and settles, and retracts the same way. The
ring is keyed off focus itself, not the resolved ramp phase: a press outranks
focus for the *fill*, but a pressed control that has focus still shows it.

## The switch knob

`NSSwitch` springs its knob across the track and cross-fades the track, and it
does so whether or not the state change was wrapped in an animation. Both
properties used to reach their end value in a single frame here: sampled at
0.00 / 0.05 / 0.10 / 0.20 / 0.40s after a toggle, the track read
`(0, 0.478, 1, 1)` and the knob's local x read 24.00 at every sample, so the
20px of travel was never drawn.

| Constant                                | Value                                        |
|-----------------------------------------|----------------------------------------------|
| `Controls.switchKnobAnimation`          | `Animation.snappy` - spring(response 0.5, damping fraction 0.85) |
| Knob travel (effective)                 | 0.3125s - where the spring saturates          |
| `Controls.switchTrackCrossfadeDuration` | 0.3125s ease-in-out, matching the travel      |

The knob is `Animation.snappy` itself, read from the named spring rather than
restated. Its *envelope* is `response * 5` (this stack's spring convention),
but `AnimationEasing.spring` clamps its first overshoot, so the knob arrives at
`0.25 * response` of normalised progress - 0.3125s. That is the number to
compare against NSSwitch, and it is what the track cross-fade matches.

The mechanism is `ViewNode.implicitReconcileAnimation`: a transaction the node
carries for its *own* frame and fill changes. A control's state change rebuilds
the tree with no `currentAnimationTransaction`, so `updateNodeProperties` had
nothing to animate with; an explicit `withAnimation` still wins when both are
present. The track's *gradient* ends animate alongside its colour
(`AnimatedColorProperty.backgroundGradientStart` / `.backgroundGradientEnd`) -
not a nicety: a gradient wins over `backgroundColor` at paint time, so a tween
that moved only the colour under a snapped gradient would not be visible at all.

## The text caret

| Constant                                     | Value  |
|----------------------------------------------|--------|
| `RetainedViewRuntime.caretBlinkOnDuration`   | 0.5s   |
| `RetainedViewRuntime.caretBlinkOffDuration`  | 0.5s   |
| `RetainedViewRuntime.caretBlinkFadeDuration` | 0.1s   |

`NSTextInsertionIndicator` blinks at roughly half a second each way, and fades
rather than hard-toggling on recent macOS. Before this there was no blink
machinery anywhere in the stack: with a `TextField` focused, `tickAnimations`
returned false on every tick for two seconds and the caret's alpha never moved.

The blink runs on the injected clock in `tickAnimations(at:)`, driving the
opacity of the node marked `isTextInputCaret` under `focusedNode`. It is in
`hasActiveAnimations` - it has to be, because a blink has no settled state: the
host gates its timer on that property, and without it the caret would freeze
mid-phase. It resets to fully on whenever focus changes and on every key the
focused input handles, which macOS also does; a caret that blinked out on the
keystroke that moved it would be unreadable exactly when it matters.

## Scroll input provenance

| Constant                            | Value                                  |
|-------------------------------------|----------------------------------------|
| `ViewNode.defaultScrollLineHeight`  | 16pt (13pt body at the 0.22 leading ratio) |
| Default three-line notch            | 48pt                                   |
| Momentum                            | `.precise` sources only                |

A wheel `delta` is in **lines**: the Win32 host has already multiplied the
physical notch by `SPI_GETWHEELSCROLLLINES` (default 3) before the runtime sees
it, so `scrollStep` is a per-line distance. It defaulted to 64 - a notch-sized
value in a line-sized slot - which put one notch at ~192px of step plus ~160px
of glide, more than half a 600pt viewport. Measured with `delta = 1` on a 200pt
scroll view: an immediate 64px jump, a glide reaching 117.68px, last motion at
t = 0.667s.

Momentum is now gated on `ScrollInputSource`. AppKit populates
`NSEvent.momentumPhase` for gesture devices only - a trackpad or Magic Mouse -
and a click-wheel detent is a bounded jump that stops when it stops. The decay
constants above are right where they apply; what was wrong was applying them to
a detent. Windows exposes the same distinction: a click wheel reports whole
multiples of `WHEEL_DELTA`, a precision touchpad reports fractions of it, and
`Win32Window.scrollInputSource(from:)` reads exactly that.

## List edits animate one row

Reconciliation matches on identity first (`nodeTag`, which `ForEach` already
writes onto every row), position second. Removing anything but the tail of a
list used to mismatch at the edit point and at every index after it: one head
deletion from a four-row list spawned four removal overlays carrying the whole
previous list at opacity 1.0, fading out on top of a new list whose every
surviving row had been re-created and faded in from zero. A single-element
removal now produces exactly one overlay at any index, and the survivors keep
their identity *and* move, which is what lets the frame animations
`updateNodeProperties` installs slide the rows below a deletion up under it.

## Why these values

- **`Animation.default = 0.35s easeInOut`**: SwiftUI's documented default
  is `Animation(duration: 0.35, easing: .easeInOut)`. Earlier versions of
  this codebase used 0.25s, which felt snappier than reference SwiftUI;
  the 0.35s value brings them into alignment.
- **`spring(response: 0.55, dampingRatio: 0.825)`**: Apple's published
  `Animation.spring` default ([SwiftUI / iOS 13 reference]). Equivalent
  to `spring(duration: 0.55, bounce: 0.175)`.
- **`spring(duration: 0.5, bounce: 0/0.15/0.3)`**: Apple's iOS 17+
  named-spring presets `smooth/snappy/bouncy`. Earlier code used
  `bouncy = 0.5/0.4`, which is far bouncier than the platform default.
- **Wheel momentum half-life of 0.115s**: Calibrated so a single wheel
  notch produces ~50 px of trailing glide on top of the immediate
  scrollStep offset, matching the feel of a precision Windows touchpad
  and Apple Magic Mouse. The decay constant is `6.0/s` (≈ `ln(2) / 0.115`).
- **Rubber-band `k = 180`, `c = 27`**: Spring with natural frequency
  ~13 rad/s, slightly underdamped (`ζ ≈ 1.0`) so the overshoot settles
  in roughly 150 ms with one perceptible decay rather than visible bounce.
