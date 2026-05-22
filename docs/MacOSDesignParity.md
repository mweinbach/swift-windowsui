# macOS Design Value Parity

Source-of-truth values for SwiftUI design constants that WinSwiftUI
matches to feel like macOS. Each value here is pinned by a machine-
checkable test in `MacOSDesignParityTests`; if a developer changes one
of these without updating the doc the test fails. Animation curves and
spring constants are documented separately in `AnimationParity.md`.

## Font.system text styles

Sizes mirror SwiftUI's published defaults on macOS 14+.

| Text style    | Size (pt) | Weight     | Source                              |
|---------------|-----------|------------|-------------------------------------|
| `largeTitle`  | 34        | regular    | SwiftUI `Font.largeTitle`           |
| `title`       | 28        | regular    | SwiftUI `Font.title`                |
| `title2`      | 22        | regular    | SwiftUI `Font.title2`               |
| `title3`      | 20        | regular    | SwiftUI `Font.title3`               |
| `headline`    | 17        | **semibold** | SwiftUI `Font.headline`           |
| `subheadline` | 15        | regular    | SwiftUI `Font.subheadline`          |
| `body`        | 17        | regular    | SwiftUI `Font.body`                 |
| `callout`     | 16        | regular    | SwiftUI `Font.callout`              |
| `footnote`    | 13        | regular    | SwiftUI `Font.footnote`             |
| `caption`     | 12        | regular    | SwiftUI `Font.caption`              |
| `caption2`    | 11        | regular    | SwiftUI `Font.caption2`             |

## Control chrome defaults

These match Apple's macOS Big Sur+ design language for standard controls.

| Constant                              | Value | Notes                                   |
|---------------------------------------|-------|-----------------------------------------|
| `SurfaceChrome.default.borderWidth`   | 1     | Hairline border on standard controls.   |
| `SurfaceChrome.default.focusRingWidth`| 2     | macOS focus-ring stroke width.          |
| `SurfaceChrome.elevatedButton.borderWidth` | 1 | Elevated/prominent buttons match.       |
| `SurfaceChrome.elevatedButton.focusRingWidth` | 2 | "                                    |
| `ControlAnimationStyle.pressedScale`  | 0.97  | Press-down affordance, Big Sur+ feel.   |
| `ControlAnimationStyle.default.focusDuration` | 0.18s | Hover/focus cross-fade.            |
| `ControlAnimationStyle.default.pressDuration` | 0.14s | Press state color + scale.         |
| `ControlAnimationStyle.default.activationDuration` | 0.18s | Activation flash.            |

## Material backdrop blur

Tint alpha and blur radius per material kind. Calibrated to feel close
to macOS visual effects views.

| Material kind | Tint alpha | Blur radius (logical px) |
|---------------|------------|--------------------------|
| `ultraThin`   | 0.18       | 8                        |
| `thin`        | 0.28       | 14                       |
| `regular`     | 0.40       | 22                       |
| `thick`       | 0.58       | 30                       |
| `ultraThick`  | 0.72       | 40                       |
| `bar`         | 0.64       | 18                       |

## System colors

RGB values match Apple's documented macOS / SF Symbols system color
palette (Human Interface Guidelines → Color → System colors). These
are the exact hex codes Apple publishes as the "Multicolor" defaults
for `Color.red`, `Color.blue`, etc. on macOS.

| Color           | macOS hex | sRGB (3 dp)           |
|-----------------|-----------|-----------------------|
| `Color.red`     | `#FF3B30` | (1.000, 0.231, 0.188) |
| `Color.orange`  | `#FF9500` | (1.000, 0.584, 0.000) |
| `Color.yellow`  | `#FFCC00` | (1.000, 0.800, 0.000) |
| `Color.green`   | `#34C759` | (0.204, 0.780, 0.349) |
| `Color.mint`    | `#00C7BE` | (0.000, 0.780, 0.745) |
| `Color.teal`    | `#30B0C7` | (0.188, 0.690, 0.780) |
| `Color.cyan`    | `#32ADE6` | (0.196, 0.678, 0.902) |
| `Color.blue`    | `#007AFF` | (0.000, 0.478, 1.000) |
| `Color.indigo`  | `#5856D6` | (0.345, 0.337, 0.839) |
| `Color.purple`  | `#AF52DE` | (0.686, 0.322, 0.871) |
| `Color.pink`    | `#FF2D55` | (1.000, 0.176, 0.333) |
| `Color.brown`   | `#A2845E` | (0.635, 0.518, 0.369) |
| `Color.gray`    | `#8E8E93` | (0.557, 0.557, 0.576) |

`Color.accentColor` and `ViewBuildContext.defaultTint` both resolve
to `Color.blue` (`#007AFF`), matching macOS's default
controlAccentColor when the user hasn't picked a custom accent.

## What's deliberately NOT pinned here

- **Pixel-level visual match** against macOS rendered output. WinSwiftUI
  runs on a separate GPU and font stack (DirectWrite + Segoe UI vs.
  CoreText + SF Pro). The values above set the design grammar; the
  exact rasterized pixels will differ.
- **Color palette** for system colors (`Color.accentColor` etc.). Those
  are environment-driven on macOS and accent-aware on Windows; they
  intentionally don't have a fixed Apple value to pin.
- **Trait-dependent values** like dynamic type modifiers. Those scale
  off the base sizes documented above.

## Adding a new value

1. Add the constant to the relevant source file.
2. Add a row to one of the tables above.
3. Add a matching `XCTAssertEqual` to
   `MacOSDesignParityTests`. The test name should reference the doc
   row directly (e.g. `testTitleFontSizeMatchesSwiftUIDefault`).

The doc and the test must stay in lockstep — changes that don't update
both are caught at CI.
