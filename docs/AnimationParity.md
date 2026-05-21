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
| `ControlAnimationStyle.default.pressDuration`   | 0.14s | Press-state color + scale animation.                   |
| `ControlAnimationStyle.default.activationDuration` | 0.18s | Activation flash.                                   |
| `ControlAnimationStyle.pressedScale`            | 0.97  | Tactile "press down" affordance, matches Big Sur+.     |

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
