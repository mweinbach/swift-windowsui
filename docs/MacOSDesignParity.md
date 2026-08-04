# macOS Design Value Parity

Source-of-truth values for SwiftUI design constants that WinSwiftUI
matches to feel like macOS. Each value here is pinned by a machine-
checkable test in `MacOSDesignParityTests`; if a developer changes one
of these without updating the doc the test fails. Animation curves and
spring constants are documented separately in `AnimationParity.md`.

## Font.system text styles

The **macOS** ramp — AppKit's `NSFont.preferredFont(forTextStyle:)`. These
used to be the *iOS* Dynamic Type table at `.large` (body 17, largeTitle 34)
under the heading "macOS parity", and `MacOSDesignParityTests` asserted them,
so the guardrail was actively locking the wrong ramp in. macOS has no `.large`
content size and no 34pt large title; the top of the ramp is 26.

The constants live in `MacOSControlMetrics.Typography` and `Font`'s statics
read from there, so the type and the control boxes it has to fit in are
pinned by one module. That coupling is the point: a 17pt body needs a ~21pt
line box, which is the whole height of `MacOSControlMetrics.TextField.regularHeight`,
so the old ramp specified a label that could not fit the field specified
beside it.

| Text style    | Size (pt) | Weight       | Line height (pt) | Source                     |
|---------------|-----------|--------------|------------------|----------------------------|
| `largeTitle`  | 26        | regular      | 32               | SwiftUI `Font.largeTitle`  |
| `title`       | 22        | regular      | 27               | SwiftUI `Font.title`       |
| `title2`      | 17        | regular      | 21               | SwiftUI `Font.title2`      |
| `title3`      | 15        | regular      | 18               | SwiftUI `Font.title3`      |
| `headline`    | 13        | **semibold** | 16               | SwiftUI `Font.headline`    |
| `subheadline` | 11        | regular      | 13               | SwiftUI `Font.subheadline` |
| `body`        | 13        | regular      | 16               | SwiftUI `Font.body`        |
| `callout`     | 12        | regular      | 15               | SwiftUI `Font.callout`     |
| `footnote`    | 10        | regular      | 12               | SwiftUI `Font.footnote`    |
| `caption`     | 10        | regular      | 12               | SwiftUI `Font.caption`     |
| `caption2`    | 10        | regular      | 12               | SwiftUI `Font.caption2`    |

Line height is `size + lineSpacing`, which is what the text renderer sets as
DirectWrite's uniform line height.

### `Font.system(size:)` is points

`Font.resolvedNativeTextSize` used to be
`size >= 8 ? size : max(12, size * 6 + 8)`: any value below 8 was silently
reinterpreted as a legacy 5x7-atlas *scale* unit. `.system(size: 3)` rendered
at 26px and `.system(size: 8)` at 8px — a public points API that was not
monotonic in its own argument. The stack authored ~27 of its own chrome sites
in those units, and because `1.5`, `1.6` and `1.9` all landed within 2px of
body(17), the app effectively had one type size plus a 26px title.

Points are now points at every value, and the 5x7 conversion (`resolvedScale`)
is the bitmap fallback's business alone. `TypographyAndAppearanceTests`
asserts monotonicity across the whole range.

### Leading

| `Font.Leading` | Extra leading | Notes                                        |
|----------------|---------------|----------------------------------------------|
| `.standard`    | `size × 0.22` | Puts 13pt body on macOS's 16pt line and 26pt largeTitle on its 32pt line. |
| `.tight`       | `size × 0.08` |                                              |
| `.loose`       | `size × 0.40` |                                              |
| floor          | 1pt           | Leading never rounds to nothing.             |

Leading is proportional because CoreText line height is. The previous flat
2px gave a 26pt headline the same gap as a 10pt caption, so a multi-line
block read as a different typeface at every size.

### Chrome type

| Constant                                  | Value | Notes                                                                 |
|-------------------------------------------|-------|-----------------------------------------------------------------------|
| `Typography.windowTitleSize`              | 13    | `NSWindow.title` / `NSToolbar` title, semibold. macOS has no large-title navigation bar; the previous 26px bold banner was iOS's `.large` display mode expressed in legacy scale units. |
| `Typography.windowSubtitleSize`           | 11    | Toolbar subtitle, secondary label.                                    |
| `Typography.sectionHeaderSize`            | 11    | Grouped-form / list section header, semibold, secondary label. Hierarchy comes from size *and* colour — at body size in near-white it differed from its own rows by weight alone. |
| `Typography.symbolBoxRatio`               | 1.25  | An SF Symbol's image box relative to the inherited point size. `Image` inherits the ambient font rather than pinning a fixed 19.4px box. |
| `Typography.uppercaseTrackingRatio`       | 0.06  | Default tracking applied when `textCase == .uppercase`. Capitals carry sidebearings tuned for mixed-case setting; set solid they read as a banner. An explicit `.tracking()` still wins. |
| `Layout.labelIconSpacing`                 | 6     | `Label`'s symbol-to-title gutter (AppKit's image-and-title cell).      |

`Label` inherits the ambient font. It used to hardcode
`.system(size: 1.6, weight: .semibold)` — 17.6px via the size<8 rule — and
apply it with `withFont`, so it *overrode* any `.font()` set on the list
around it, and it forced `lineLimit(1)`, which SwiftUI does not.

## Semantic label colours

`Color.primary` was literally `(1, 1, 1)` and `Color.secondary` a blue-cast
`(0.70, 0.74, 0.80)`, with no light counterparts, and
`resolvedForVisualEnvironment` took contrast and background prominence but
never a colour scheme. Light mode was therefore not merely unwired — it could
not be expressed, and the ambient foreground default was a literal `.white`,
so every inherited label vanished the moment an app was rendered light.

macOS builds the whole text hierarchy as **one alpha ladder over one neutral
base**; only the base changes with the appearance. `LabelHierarchy`
(SwiftWindowsCore) holds the ladder, `Color.primary`/`.secondary`/`.tertiary`/
`.quaternary`/`.quinary` are its dark-appearance rungs, and
`Color.resolvedForVisualEnvironment(colorScheme:contrast:backgroundProminence:)`
resolves a rung out of the same `ControlPalette` the control chrome reads.

| Rung         | Alpha  | Hex     | AppKit                      |
|--------------|--------|---------|-----------------------------|
| primary      | 0.851  | `..D9`  | `NSColor.labelColor`        |
| secondary    | 0.549  | `..8C`  | `secondaryLabelColor`       |
| tertiary     | 0.251  | `..40`  | `tertiaryLabelColor`        |
| quaternary   | 0.098  | `..19`  | `quaternaryLabelColor`      |
| quinary      | 0.051  | `..0D`  | SwiftUI's fifth rung        |
| secondary, `.increased` contrast | 0.749 | `..BF` | AppKit's increase-contrast pass |
| tertiary, `.increased` contrast  | 0.451 | `..73` | "                        |

The base is white in the dark appearance and black in the light one, so
`Color.primary` and `ControlPalette.label` are the same colour by
construction rather than by two people rounding to 0.85 independently.

Recognition is by exact rung value: a colour the app wrote itself is not a
semantic role and passes through untouched, and `Color.accentColor` (#007AFF)
is never desaturated. The known limitation is that `Color.primary.opacity(0.5)`
is no longer a recognised rung — an app that wants a dimmer label should ask
for `.secondary` rather than fade `.primary`.

`.increased` background prominence promotes secondary to primary: content
drawn over a filled selection stops being secondary, which is what AppKit
does. It also changes the *base*: an emphasised selection is the same
saturated accent fill in both appearances, so the ladder over it is built on
`selectedContentLabel` (`alternateSelectedControlTextColor`, white) rather
than on the appearance's base. Promoting the rung while keeping the light
appearance's black base put an 85%-black version label on `#007AFF` in the
demo's Data screen; `testSelectionContentIsLightInBothAppearances` pins it.

## Chrome neutrals

Every hardcoded chrome literal in `Views.swift` and `Core.swift` sat on a
navy axis where blue was roughly twice red — `(0.07, 0.10, 0.15)` surfaces
under `(0.92, 0.95, 1.0)` "whites". macOS dark neutrals carry no hue at all;
the accent is the only chromatic element. 171 literals were desaturated to
their Rec.709 luminance, preserving the surface ladder's depth relationships
and leaving every genuinely chromatic colour (the accent, the status greens
and ambers, the module tints) untouched.

The containers that a screen actually shows — the navigation band, the tab
bar, `Form` and `Section` boxes, `List` bodies and their hairlines, the
scroller thumb, the window backdrop — now read roles from `ControlPalette`
instead of holding literals, so they follow the appearance rather than
staying dark under light text.

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
