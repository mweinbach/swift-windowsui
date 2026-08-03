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
| `SurfaceChrome.focusRingStrokeWidth`  | 4     | macOS focus-ring stroke width. Equals `MacOSControlMetrics.FocusRing.strokeWidth`; the two used to disagree (2 vs 4) with both pinned as "the" macOS value. |
| `SurfaceChrome.default.focusRingWidth`| 4     | "                                       |
| `SurfaceChrome.elevatedButton.borderWidth` | 1 | Elevated/prominent buttons match.       |
| `SurfaceChrome.elevatedButton.focusRingWidth` | 4 | "                                    |
| `ControlPalette.focusRingAlpha`       | 0.55  | A keyboard focus ring is a clearly visible accent halo, not the ~0.28 whisper the hand-tuned chrome drew. |
| `MacOSControlMetrics.Button.regularCornerRadius` | 6 | Push-bezel corner radius. A capsule is the opt-in shape (`.buttonBorderShape(.capsule)`), never the default — 16 on a 22–30pt control clamps to h/2 and renders every button as a stadium. |
| `MacOSControlMetrics.Button.smallCornerRadius` | 4 | `.mini` / `.small`, and the segmented pill. |
| `MacOSControlMetrics.Button.largeCornerRadius` | 8 | `.large`.                            |
| `Controls.surfaceSheenFactor`         | 0.96  | Luminance the bottom stop of a control sheen keeps. Apple retired the glossy bevel with Yosemite; the previous 0.82 was an 18% drop on every surface and is what made controls read as styled divs. |
| `Controls.grooveSheenFactor`          | 0.90  | The deeper shade a genuinely recessed groove keeps (slider/progress track, segmented track, text-field well). |
| `ControlPalette.disabledContentOpacity` | 0.35 | AppKit dims the whole disabled cell, label included — not only the surface fill. |
| `ControlAnimationStyle.pressedScale`  | 0.97  | Press-down affordance, Big Sur+ feel.   |
| `ControlAnimationStyle.default.focusDuration` | 0.18s | Hover/focus cross-fade.            |
| `ControlAnimationStyle.default.pressDuration` | 0.14s | Press state color + scale.         |
| `ControlAnimationStyle.default.activationDuration` | 0.18s | Activation flash.            |

## Semantic control palette

Control chrome used to be architecturally unable to read `colorScheme`:
`ViewBuildContext` exposed `colorSchemeContrast` but never `colorScheme`, and
every chrome literal in `Views.swift` was a hand-tuned dark value. With
`.preferredColorScheme(.light)` the app rendered identical dark buttons,
fields, pickers and near-white hairlines with only the toolbar flipping —
an unreadable hybrid, and one that could not even be *seen* because there
was no way to produce a light-mode snapshot.

`ControlPalette` (Sources/WinSwiftUI/ControlPalette.swift) resolves AppKit's
semantic colours for one `(colorScheme, contrast)` pair, and builders read
roles from it instead of writing RGB. `ViewBuildContext.controlPalette` is
the accessor. `--appearance light|dark` on `swift-windowsui-snapshot` (and
`-Appearance` on `scripts/demo-screenshot.ps1`) renders either appearance.

The neutrals are **achromatic**, asserted by `ControlAppearanceChromeTests`.
The retired palette was blue-cast navy — a `(0.18, 0.23, 0.31)` bordered
fill under `(0.96, 0.98, 1.0)` borders — where macOS uses grey.

| Role                             | Dark            | Light           | AppKit source |
|----------------------------------|-----------------|-----------------|---------------|
| `windowBackground`               | #212121         | #ECECEC         | `windowBackgroundColor` |
| `controlBackground`              | #1E1E1E         | #FFFFFF         | `controlBackgroundColor` / `textBackgroundColor` |
| `controlSurface` (bordered face) | white @ 0.10    | #FFFFFF         | `controlColor` |
| `raisedSurface`                  | #282829         | #FFFFFF         | grouped box |
| `label`                          | white @ 0.85    | black @ 0.85    | `labelColor` |
| `secondaryLabel`                 | white @ 0.55    | black @ 0.50    | `secondaryLabelColor` |
| `tertiaryLabel`                  | white @ 0.25    | black @ 0.26    | `tertiaryLabelColor` |
| `disabledLabel`                  | white @ 0.25    | black @ 0.25    | `disabledControlTextColor` |
| `separator`                      | white @ 0.10    | black @ 0.10    | `separatorColor` |
| `controlBorder`                  | white @ 0.14    | black @ 0.16    | control bezel ring |
| `unemphasizedSelectedBackground` | #3F3F41         | #DCDCDD         | `unemphasizedSelectedContentBackgroundColor` |
| `systemFill` … `quinaryFill`     | white @ .10/.08/.05/.03/.02 | black @ same | `systemFill` ramp |
| `segmentedTrackFill`             | #2C2C2E         | #E9E9EB         | NSSegmentedControl groove |
| `segmentedSelectedFill`          | #636366         | #FFFFFF         | selected segment pill |
| `segmentedSelectedLabel`         | white           | black           | selected segment label |

`.increased` contrast strengthens exactly the roles AppKit strengthens:
hairlines, control borders and secondary/tertiary text.

Selection and accent are derived, not stored: `selectedContentBackground` is
the **opaque** accent (macOS fills a selected row solid; it does not wash it),
and accent state is a lightness move — hover +8%, pressed −12% — never an
alpha ramp that lets the backdrop bleed through a half-disabled looking fill.
`ControlPalette.ambientShadow` is black @ 0.12 at offset (0, 1), spread 1:
macOS never tints a control shadow with the accent or role colour.

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

## Control dimension reference

Apple HIG-published target dimensions for standard macOS controls.
These live as `public static let` constants in `MacOSControlMetrics`
(Sources/WinSwiftUI/MacOSControlMetrics.swift) and are the
*visual-parity target* WinSwiftUI converges toward. They are the
documentation half of the contract — pinned by
`MacOSControlReferenceTests` so changing the constants here without
updating the doc fails CI.

The constants used to be inert (referenced by nothing outside their own
file), which is how button padding, list rows, the toolbar band and the
segmented track each drifted independently. The control builders now
read them, and `MacOSControlMetricsWiringTests` asserts the constants
reach real layout output rather than being compared against themselves.
Wired today: `Button` content bezel and control-size heights,
`List.plainRowHeight` / `List.sidebarRowHeight` / `List.contentInset`,
`Toolbar.regularHeight` for the navigation title band,
`PopUpButton.regularHeight` for the segmented track, and
`Layout.defaultStackSpacing` for `VStack`/`HStack`/lazy stacks and
grids.

| Control                      | Constant                                  | Value     |
|------------------------------|-------------------------------------------|-----------|
| Push button (.regular)       | `Button.regularHeight`                    | 22 pt     |
| Push bezel corner radius     | `Button.regularCornerRadius`              | 6 pt      |
| Push button (.large)         | `Button.largeHeight`                      | 32 pt     |
| Toggle switch (.regular)     | `Toggle.regularSize`                      | 38×22 pt  |
| Slider track thickness       | `Slider.trackThickness`                   | 4 pt      |
| Slider thumb diameter        | `Slider.thumbDiameter`                    | 16 pt     |
| Stepper button               | `Stepper.buttonSize`                      | 19×11 pt  |
| Pop-up button (.regular)     | `PopUpButton.regularHeight`               | 22 pt     |
| Progress bar (.regular)      | `ProgressBar.regularHeight`               | 6 pt      |
| Progress spinner (.regular)  | `ProgressSpinner.regularDiameter`         | 16 pt     |
| Text field (.regular)        | `TextField.regularHeight`                 | 21 pt     |
| List row (plain)             | `List.plainRowHeight`                     | 24 pt     |
| List row (sidebar)           | `List.sidebarRowHeight`                   | 28 pt     |
| List content inset           | `List.contentInset`                       | 16 pt     |
| Toolbar (regular)            | `Toolbar.regularHeight`                   | 52 pt     |
| Window corner radius         | `Window.cornerRadius`                     | 10 pt     |
| Sheet corner radius          | `Window.sheetCornerRadius`                | 12 pt     |
| Focus ring stroke            | `FocusRing.strokeWidth`                   | 4 pt      |
| Default stack spacing        | `Layout.defaultStackSpacing`              | 8 pt      |
| Default `.padding()`         | `Layout.defaultPadding`                   | 16 pt     |

### One named ergonomic delta

The `ControlSize` extensions had drifted to 1.4x–3.5x the reference — text
field 220×36 against a 21pt reference, pop-up button 36 against 22, progress
bar 8 against 6 — with only three of the divergences recorded here. Each
control had been tuned on its own, which is exactly how drift happens.

Shipped heights are now `macOS reference + ControlSize.windowsPointerPadding`
(**6 pt**), scaled per size variant (mini 0.5x, small 0.75x, regular 1x,
large 1.25x, extraLarge 1.5x). macOS is designed for a trackpad; Windows UX
guidance asks for larger pointer targets, and that difference is *one*
constant rather than per-control guesswork.
`ListChromeAndMetricsTests` asserts the shipped sizes equal reference plus
delta, so a new divergence cannot be introduced without changing the constant
and this row.

Controls that are not pointer targets take the reference exactly: the linear
progress bar is `ProgressBar.regularHeight` (6 pt) and the slider groove is
`Slider.trackThickness` (4 pt) with a `Slider.thumbDiameter` (16 pt) knob.

The toggle (52×32) and slider control height (200×28) remain deliberate
Windows-side sizes; the stepper is now derived — each half is
`Stepper.buttonSize` (19×11) plus the delta on width and half the delta on
height, stacked vertically as NSStepper is, rather than the 68×30
side-by-side pair (the iOS UIStepper form factor) it used to draw.

Remaining recorded divergences, with rationale:

| Surface                | Windows value                    | Rationale |
|------------------------|----------------------------------|-----------|
| Control heights        | `macOS reference + 6 pt` (scaled) | Windows pointer-target ergonomics, applied as one constant. |
| Button content bezel   | 12/3 pt (regular), 16/6 pt (large) | Segoe UI renders wider than SF Pro at the same point size; the horizontal inset is the macOS push-bezel margin, the vertical one is what the control-size height leaves around the line box. |
| Separator thickness    | `1 / displayScale`               | One physical pixel at any backing scale, like an AppKit separator — a 1pt rule would double to 2px at 2x. |
| Tab band inset         | 12/16 pt around a centered group | macOS insets an `.automatic` tab view from the window edge and centres the segment group instead of distributing tabs across the full width. |
| Toolbar band           | Full bleed + bottom hairline     | The navigation title reads as window chrome, not a rounded card floating over the content. |
| List row separator     | Sibling 1px panel between rows   | The retained model has no per-side border, so the rule is a node rather than a bottom edge on the row. It therefore costs one physical pixel of layout height per gap, where AppKit draws the grid line inside the row rect. |

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
