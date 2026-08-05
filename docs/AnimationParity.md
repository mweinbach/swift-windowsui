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
| `ControlAnimationStyle.default.activationDuration` | 0.18s | Activation flash.                                   |
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

`focusDuration` 0.18s, `pressDuration` 0.14s and `activationDuration` 0.18s
were reviewed against macOS feel alongside the scale decision and left alone.
They sit in the right band: AppKit's hover and focus-ring cross-fades are
around a sixth of a second, and the press highlight is quicker than the hover
it replaces, which is the ordering these three encode. The one known
simplification is that AppKit's press highlight snaps in faster than it fades
out, where this stack uses one duration in each direction — not worth churning
a constant over without a measurement to move it to.

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
