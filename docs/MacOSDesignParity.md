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
| `Typography.windowTitleSize`              | 13    | `NSWindow.title` / `NSToolbar` title, semibold — the OS title-bar scale. Note this is *not* what `.navigationTitle` is set at: see "Navigation title" below. |
| `Typography.windowSubtitleSize`           | 11    | Toolbar subtitle, secondary label.                                    |
| `Typography.sectionHeaderSize`            | 11    | Grouped-form / list section header, semibold, secondary label. Hierarchy comes from size *and* colour — at body size in near-white it differed from its own rows by weight alone. |
| `Typography.symbolBoxRatio`               | 1.25  | An SF Symbol's image box relative to the inherited point size. `Image` inherits the ambient font rather than pinning a fixed 19.4px box. |
| `Typography.uppercaseTrackingRatio`       | 0.06  | Default tracking applied when `textCase == .uppercase`. Capitals carry sidebearings tuned for mixed-case setting; set solid they read as a banner. An explicit `.tracking()` still wins. |
| `Layout.labelIconSpacing`                 | 6     | `Label`'s symbol-to-title gutter (AppKit's image-and-title cell).      |

### Navigation title

macOS puts `NSWindow.title` in title-bar chrome this stack does not own, so
the band `NavigationStack` draws is the **content pane's** header — the title
a Finder or System Settings pane shows above its content — not a window
title. It is therefore set at pane scale:

| Display mode           | Font                      | Notes                                            |
|------------------------|---------------------------|--------------------------------------------------|
| `.automatic` / `.large` | largeTitle 26, bold      | Fits inside `Toolbar.regularHeight` (52).        |
| `.inline`              | title2 17, semibold       | The unified-compact toolbar variant.             |

Setting it at `windowTitleSize` (13) sized a *window* title into a *pane*
header: "Settings" read as a stray 13pt label adrift in an otherwise empty
52pt band. `testNavigationTitleIsSetAtContentPaneScale` pins it.

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

### A quaternary background is a bar, not a shade

The rungs resolve differently on the way to a *fill*, in exactly one place.
`.background(.quaternary)` is the idiomatic bottom bar — the scrim that
closes a list with an inspector or status strip. In the dark appearance the
white quaternary rung lightens the window into the bar (#373737 on #212121,
secondary strings 4.8:1), which is precisely what a macOS dark bottom bar
does, so dark resolves the label rung unchanged. In the light appearance the
same maths is a black wash that lands the bar at #D5D5D5 on the #ECECEC
window — *darker* than the page it closes, which no macOS bottom bar is:
Finder's status bar and Xcode's debug bar sit at `windowBackgroundColor`
and let the divider above them carry the edge. A light quaternary
*background* therefore resolves to `ControlPalette.windowBackground`, where
its secondary strings clear 4.5:1. The label resolution keeps AppKit's
published `#..19` in both appearances.
`Color.resolvedForBackgroundVisualEnvironment` implements the split;
`testQuaternaryBackgroundIsABarNotAShadeInLight` pins it.

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
| `Controls.surfaceSheenFactor`         | 0.96  | Luminance the bottom stop of a control sheen keeps, on a full-value surface. Apple retired the glossy bevel with Yosemite; the previous 0.82 was an 18% drop on every surface and is what made controls read as styled divs. |
| `Controls.surfaceSheenDrop`           | 0.04  | The same step stated as a distance rather than a ratio (`1 - surfaceSheenFactor`). macOS's bezels travel about the same *absolute* amount in both appearances: a light push button runs #FFFFFF → #F5F5F5 and a dark one #545456 → #48484A. |
| `Controls.surfaceSheenRelativeCeiling`| 0.16  | Most of itself a surface may lose to its own sheen. The absolute step is calibrated on a near-white bezel; on a dim one it is most of what the surface has, and a `white(0.10)` control over a black page (25/255) would dissolve its bottom edge into the window. macOS's dark push bezel travels ~14% of itself. |
| `Controls.borderSheenFadeFactor`      | 0.55  | Strength a bezel's ring keeps at its far edge. |
| `Controls.grooveSheenFactor`          | 0.90  | The deeper shade a genuinely recessed groove keeps (slider/progress track, segmented track, text-field well). |

### The sheen is a step in what the window shows

`shaded(_:by:)` scales the channels and leaves alpha alone. That is the right
arithmetic for an opaque bezel and very nearly a no-op for a translucent one:
a dark-appearance control surface is `white(0.10)`, a wash whose composite is
`0.10 · 1 + 0.90 · window`, so scaling `(1,1,1)` to `(0.96,0.96,0.96)` moved a
25/255 button by a **single level**. Every bordered button in the dark
appearance was a flat fill while the light one carried its gradient, out of
one shared "sheen".

`Controls.sheenBottom` solves instead for the factor that lands the surface
`surfaceSheenDrop` lower in `compositeValue` — its greatest channel weighted
by its alpha — capped at `surfaceSheenRelativeCeiling` of the surface itself.
The channels still scale together, so hue survives; and on any opaque
full-value surface (white bezels, accent fills, destructive reds, slider and
progress bars) the factor comes out at exactly `surfaceSheenFactor`, which is
why nothing already correct moved.

The greatest channel rather than a weighted luminance sum, deliberately: a sum
reads `#007AFF` as dim (blue carries 11% of luminance), so an absolute step
against it would shade a full-strength accent three times as hard as the
near-white bezel beside it.

### A ring is lightest along its top edge — in both appearances

macOS lights a bezel from above, so its hairline is *lightest* on top whichever
appearance it is in. That is not the same as strongest on top, and the
difference is the whole light appearance: a dark-mode ring is drawn in white,
where lightest means full strength on top fading down; a light-mode ring is
drawn in black, where the identical lighting reads the other way round — the
ring withdraws at the top and closes along the bottom, which is the faint
under-line a macOS light push button carries. `Controls.borderSheen` picks the
stop order from the ring's own colour.

Two other things had to be true before any of that reached a pixel:

- **A ring's gradient belongs to the ring, not to each of its edges.** A quad
  evaluates its gradient across its own rect, and a bordered node *with
  children* paints its border as four thin edge quads. Handed the ring's
  gradient unmodified, each edge replayed the whole ramp inside a 1pt line, so
  the top and bottom hairlines both landed on the gradient's midpoint. Every
  button in this stack has a label inside it, so the highlight `borderSheen`
  produced never reached one real control while every node-reading unit test
  agreed it was there. `BorderSegments.segmentStops` re-samples the gradient
  onto each segment; `PainterBorderRingCoverageTests` pins it in pixels.
- **A quad carries two stops.** `GPUIScene`'s quad primitive has a start and an
  end colour, so a multi-stop gradient collapses at the paint layer. Chrome
  gradients are authored as two stops for that reason.
| `ControlPalette.disabledContentOpacity` | 0.35 | AppKit dims the whole disabled cell, label included — not only the surface fill. |
| `ControlAnimationStyle.pressedScale`  | 0.97  | Press-down affordance, Big Sur+ feel.   |
| `ControlAnimationStyle.default.focusDuration` | 0.18s | Hover/focus cross-fade.            |
| `ControlAnimationStyle.default.pressDuration` | 0.14s | Press state color + scale.         |
| `ControlAnimationStyle.default.activationDuration` | 0.18s | Activation flash.            |

## Grouped form and group box

A macOS grouped form (SwiftUI's `.formStyle(.grouped)`, System Settings) is a
**two-column grid inside a centred content column**: trailing-aligned labels
share one leading column, controls lead the value column beside them, and the
section header sits *outside and above* the box it names. Controls read
`EnvironmentValues.isInsideGroupedForm` and build a row through
`groupedFormRowNode`; the container resolves the shared column width once
every row exists (`alignedGroupedFormRows`).

| Constant                                       | Value | Notes |
|------------------------------------------------|-------|-------|
| `MacOSControlMetrics.Form.contentMaxWidth`     | 640   | Width of the centred content column. macOS settings run a ~600–715pt column with generous margins; edge to edge across a 1256pt window is a web layout, and it is what made a three-segment picker 1215pt wide. |
| `MacOSControlMetrics.Form.contentHorizontalMargin` | 20 | Margin inside the column, so 640pt of column carries 600pt boxes. |
| `MacOSControlMetrics.Form.labelColumnGap`      | 8     | Label column to value column. |
| `MacOSControlMetrics.Form.sectionSpacing`      | 20    | Box to the next section's header. |
| `MacOSControlMetrics.Form.headerSpacing`       | 6     | Header to the box it names. |
| `MacOSControlMetrics.Form.headerLeadingInset`  | 6     | Header text sits just proud of the box's corner. |
| `MacOSControlMetrics.Form.rowSpacing`          | 10    | Row to row inside a box. |
| `MacOSControlMetrics.Form.boxVerticalPadding`  | 12    | Group box interior. |
| `MacOSControlMetrics.Form.boxHorizontalPadding`| 16    | " |
| `MacOSControlMetrics.GroupBox.cornerRadius`    | 10    | macOS Sonoma's grouped box radius. The previous 28 on a 600pt-wide card is a marketing panel, not an `NSBox`. |
| `MacOSControlMetrics.GroupBox.shadowOffsetY`   | 2     | Ambient *contact* shadow only. |
| `MacOSControlMetrics.GroupBox.shadowSpread`    | 3     | " |
| `ControlPalette.groupedContainerShadow` (light)| black @ 0.04 | A macOS light-mode group box is near-flat: a white surface closed by a separator-tone hairline. The shared `ambientShadow` at 0.12 put a visible smudge under every card. |
| `ControlPalette.groupedContainerShadow` (dark) | black @ 0.22 | Dark mode carries the depth the low-contrast hairline cannot. |
| `ControlPalette.raisedSurfaceHighlight` (light)| white @ 0.55 | Top edge of a grouped container's ring. |
| `ControlPalette.raisedSurfaceHighlight` (dark) | white @ 0.16 | " |

### The panel material

A macOS panel is not one flat colour. It carries a vertical gradient so slight
you would not call it a gradient if you saw it alone — a handful of levels of
255 between its top and its bottom — and that slight amount is the whole
difference between a surface and a rectangle of paint. Every card in this app
was a single `fillRect`, which is why a screenshot read as flat colour
blocking however correct the tones themselves were.

`ControlPalette.raisedSurfaceFill` is that material: `raisedSurface` at the top
and `Controls.sheenBottom` of it at the bottom — the *same* sheen every control
surface takes, deliberately, because a card and the buttons standing on it have
to be lit from one direction. `ControlPalette.raisedSurfaceRing` is the ring
that closes it: `raisedSurfaceHighlight` along the top edge, `separator` along
the bottom, the same top-lit rule `borderSheen` gives a control bezel.

A `GroupBox`, a grouped `Form`'s section boxes and a grouped `Form`'s own card
all take it. `GroupBox` in particular used to carry literals no appearance
resolved at all — a translucent `#252525 @ 0.54` fill under a `#DADADA @ 0.14`
ring at a 12pt radius — so it was neither appearance-correct nor the same box
the settings pane beside it drew.

An `NSSegmentedControl` is **intrinsically sized** — equal segments as wide as
the widest label — and stretches only when something explicitly asks it to (a
`.frame(width:)`, a stretching container). The segmented track used to declare
itself greedy, which is why it took the whole row it was offered.

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
| `controlTrack`                   | #4D5766         | #D6D6DA         | slider / progress / switch groove |
| `segmentedTrackFill`             | #2C2C2E         | #E9E9EB         | NSSegmentedControl groove |
| `segmentedSelectedFill`          | #636366         | #FFFFFF         | selected segment pill |
| `segmentedSelectedLabel`         | white           | black           | selected segment label |
| `elevatedSurface`                | #2B2B2D @ 0.98  | #F9F9FA @ 0.98  | floating-panel material |
| `elevatedSurfaceBorder`          | white @ 0.16    | black @ 0.14    | floating-panel hairline |
| `scrollerKnob`                   | white @ 0.48    | black @ 0.42    | `NSScroller` overlay knob |
| `scrollerKnobHovered`            | white @ 0.64    | black @ 0.58    | knob under the pointer |
| `scrollerKnobActive`             | white @ 0.78    | black @ 0.72    | knob being dragged |

`controlTrack` is the groove a *continuous* control's fill runs along: a
`Slider`'s unfilled bar, a determinate `ProgressView`'s remainder, a `Gauge`'s
empty span, and the body of an `off` `Toggle`. All four read the same
hard-coded dark slate off `Controls` and no WinSwiftUI caller overrode it, so
`--appearance light` drew a near-black bar across a white settings pane and an
`off` switch came out charcoal — the last controls still wearing the dark
appearance. The dark value is that literal unchanged, so no dark-mode pixel
moved. `ControlTrackAppearanceTests` pins both values and the wiring on all
four controls.

`elevatedSurface` is a *different* elevation from `raisedSurface`: a raised
surface is a card on the window's own backdrop, an elevated one floats above
the window entirely — a menu, a popover, a sheet, an alert, a context menu,
an inspector, a full-screen cover. Every one of those was a dark literal, so
a light-mode app opened a near-black panel with near-black text on it.
`testFloatingPanelsSitOnAnAppearanceResolvedSurface` pins it.

The three segmented roles also dress the `TabView` tab bar: macOS draws a tab
bar with `NSSegmentedControl`, so the band is the groove, the selected tab is
the raised pill, and unselected tabs carry no border. Giving each tab its own
rounded border inside the band's border — with the accent ringing the selected
one — is what made the bar read as three chained web buttons inside a fourth.
`testTabBarSpeaksTheSegmentedControlLanguage` pins it.

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

A system colour is a *pair*, not a value. Apple publishes two sRGB
resolutions for each — one per appearance — and `NSColor.systemOrange`
is a dynamic colour that picks between them; SwiftUI documents
`Color.orange` as "context-dependent" for the same reason. The light
value on a dark window is a shade too heavy and the dark value on white
is a shade too pale, which is why one constant cannot serve both.

Both columns live in `SwiftWindowsCore.SystemColorPalette`. The
`Color.red` / `Color.orange` statics are the *light* rung of each pair,
so everything that reads a static keeps the value it always had;
`Color.resolvedForVisualEnvironment` swaps in the dark twin when the
colour scheme is dark, exactly as it already does for the
`LabelHierarchy` rungs.

These are the SwiftUI system palette — the same table on macOS and iOS.
AppKit publishes a few macOS-only `NSColor` variants (`systemGreen` is
`#28CD41` rather than `#34C759`, `systemTeal` `#59ADC4`, `systemCyan`
`#55BEF0`); those belong to `Color(nsColor:)`, not to SwiftUI's own
`Color.green`, which is the cross-platform one this layer implements.

There is deliberately no increased-contrast column: Apple publishes no
increased-contrast sRGB values for the system palette, and inventing
them would put unverifiable numbers behind a parity test.

| Color           | Light hex | Light sRGB (3 dp)     | Dark hex  | Dark sRGB (3 dp)      |
|-----------------|-----------|-----------------------|-----------|-----------------------|
| `Color.red`     | `#FF3B30` | (1.000, 0.231, 0.188) | `#FF453A` | (1.000, 0.271, 0.227) |
| `Color.orange`  | `#FF9500` | (1.000, 0.584, 0.000) | `#FF9F0A` | (1.000, 0.624, 0.039) |
| `Color.yellow`  | `#FFCC00` | (1.000, 0.800, 0.000) | `#FFD60A` | (1.000, 0.839, 0.039) |
| `Color.green`   | `#34C759` | (0.204, 0.780, 0.349) | `#30D158` | (0.188, 0.820, 0.345) |
| `Color.mint`    | `#00C7BE` | (0.000, 0.780, 0.745) | `#66D4CF` | (0.400, 0.831, 0.812) |
| `Color.teal`    | `#30B0C7` | (0.188, 0.690, 0.780) | `#40C8E0` | (0.251, 0.784, 0.878) |
| `Color.cyan`    | `#32ADE6` | (0.196, 0.678, 0.902) | `#64D2FF` | (0.392, 0.824, 1.000) |
| `Color.blue`    | `#007AFF` | (0.000, 0.478, 1.000) | `#0A84FF` | (0.039, 0.518, 1.000) |
| `Color.indigo`  | `#5856D6` | (0.345, 0.337, 0.839) | `#5E5CE6` | (0.369, 0.361, 0.902) |
| `Color.purple`  | `#AF52DE` | (0.686, 0.322, 0.871) | `#BF5AF2` | (0.749, 0.353, 0.949) |
| `Color.pink`    | `#FF2D55` | (1.000, 0.176, 0.333) | `#FF375F` | (1.000, 0.216, 0.373) |
| `Color.brown`   | `#A2845E` | (0.635, 0.518, 0.369) | `#AC8E68` | (0.675, 0.557, 0.408) |
| `Color.gray`    | `#8E8E93` | (0.557, 0.557, 0.576) | `#98989D` | (0.596, 0.596, 0.616) |

A saturated system colour used as *text* is low contrast on white in
both appearances — `#FF9500` measures 2.2:1 on a white table row — and
that is macOS's own behaviour, not a defect in the pair table: the light
value already is the darker-on-white member. Colour on a light surface
carries emphasis, not legibility; the reading is the label colour's job.

`Color.accentColor` and `ViewBuildContext.defaultTint` both resolve to
`Color.blue`'s light value (`#007AFF`), matching macOS's default
controlAccentColor when the user hasn't picked a custom accent. The tint
is not run through the appearance resolver: control chrome takes its
accent from `ControlPalette`, which owns its own per-appearance tones.

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
| Stepper half (one arrow)     | `Stepper.buttonSize`                      | 13×11 pt  |
| Stepper bezel (the pair)     | `Stepper.regularSize`                     | 13×22 pt  |
| Stepper bezel radius         | `Stepper.cornerRadius`                    | 3 pt      |
| Colour well (.regular)       | `ColorWell.regularSize`                   | 34×22 pt  |
| Colour well bezel radius     | `ColorWell.cornerRadius`                  | 5 pt      |
| Colour well swatch inset     | `ColorWell.swatchInset`                   | 3 pt      |
| Pop-up button (.regular)     | `PopUpButton.regularHeight`               | 22 pt     |
| Progress bar (.regular)      | `ProgressBar.regularHeight`               | 6 pt      |
| Progress spinner (.regular)  | `ProgressSpinner.regularDiameter`         | 16 pt     |
| Text field (.regular)        | `TextField.regularHeight`                 | 21 pt     |
| List row (plain)             | `List.plainRowHeight`                     | 24 pt     |
| List row (sidebar)           | `List.sidebarRowHeight`                   | 28 pt     |
| List content inset           | `List.contentInset`                       | 16 pt     |
| Inset list body corner       | `List.insetCornerRadius`                  | 6 pt      |
| Inset list body top/bottom   | `List.insetVerticalInset`                 | 6 pt      |
| Overlay scroller knob        | `Scroller.overlayThumbThickness`          | 7 pt      |
| Overlay scroller inset       | `Scroller.overlayInset`                   | 4 pt      |
| Overlay scroller min knob    | `Scroller.minimumThumbLength`             | 24 pt     |
| Toolbar (regular)            | `Toolbar.regularHeight`                   | 52 pt     |
| Window corner radius         | `Window.cornerRadius`                     | 10 pt     |
| Sheet corner radius          | `Window.sheetCornerRadius`                | 12 pt     |
| Focus ring stroke            | `FocusRing.strokeWidth`                   | 4 pt      |
| Default stack spacing        | `Layout.defaultStackSpacing`              | 8 pt      |
| Default `.padding()`         | `Layout.defaultPadding`                   | 16 pt     |

### Overlay scrollers

A macOS scroller is an *overlay* scroller unless the user has set "Show
scroll bars: Always": no track, no arrows, a rounded pill floating over the
content, invisible at rest, faded in while the content moves and faded back
out afterwards. That is why a screenshot of a real macOS app shows no
scrollbar anywhere.

The runtime supplies the mechanism (`ViewNode.scrollIndicatorAutoHides`,
`RetainedViewRuntime.revealScrollIndicator(for:)` /
`flashScrollIndicator(for:)`), WinSwiftUI sets the policy:
`.scrollIndicators(.automatic)` — the default — is an overlay scroller;
`.scrollIndicators(.visible)` is the legacy persistent bar.

| Timing                                          | Value  |
|-------------------------------------------------|--------|
| `RetainedViewRuntime.scrollIndicatorRevealDuration`   | 0.12 s |
| `RetainedViewRuntime.scrollIndicatorVisibleHold`      | 1.00 s |
| `RetainedViewRuntime.scrollIndicatorFadeOutDuration`  | 0.45 s |

Fade in is quick and fade out is slow on purpose — a scroller answers
instantly and leaves quietly. The reveal state is part of
`hasActiveAnimations` for the whole hold, because a revealed scroller with no
tween in flight still needs frames to reach its own hide deadline.
`OverlayScrollIndicatorTests` pins the timeline; the flash hooks ride the same
lifecycle pass `onAppear` does.

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
Windows-side sizes; the stepper is derived — each half is
`Stepper.buttonSize` (13×11) plus the delta on width and half the delta on
height, stacked vertically as NSStepper is, rather than the 68×30
side-by-side pair (the iOS UIStepper form factor) it used to draw. The colour
well takes `ColorWell.regularSize` exactly: a well is as wide as the swatch it
shows, not a pointer target sized for a click.

### The stepper is one bezel, not two chained buttons

An NSStepper is a *narrow* two-part bezel — one rounded rectangle 13pt across
and 22pt tall, split by a hairline, with a small arrow centred in each half.
Two failures produce the flat box it used to draw:

- **Width.** The 19pt this doc used to claim as `Stepper.buttonSize.width` is
  the old Aqua stepper. At that width the arrow glyph grew to fill its half and
  the control read as a square button with two chevrons on it. The arrow's own
  box is now pinned separately (`Stepper.chevronSize`), because the icon bitmap
  is *stretched into the node's rect* — the glyph box is the arrow's size.
- **The seam.** Two flush buttons each closed by their own 1pt ring put two
  adjacent rings at the join, and against the low-contrast dark palette they
  cancelled into a 2pt smear with no divider in it. The ring now belongs to the
  bezel (the painter re-draws a parent's ring *after* its children, so the
  halves may fill it edge to edge) and the seam is a real hairline node, like
  every other separator in this stack.

### A grouped form rules between every row

macOS System Settings separates every row inside a grouped box. A box that
ruled only where the app happened to write a `Divider` reads as an arbitrary
rhythm rather than a settings pane, so `Section` interleaves the rule itself,
the same way `List` does between its rows. An app's own `Divider` is not
doubled: a row that is already a rule suppresses the automatic one on either
side of it, which is what `ViewNode.isSeparatorRule` is for.

Scoped to a grouped `Section`, like the shared label column: a `Section`
outside a `Form` keeps the list-group layout it has always had, and a grouped
`Form` whose rows are written directly (no `Section` at all) is one box with no
row grouping to rule between.

The rule sits in the middle of the row gap and costs the gap nothing: the
section's stack spacing is `(Form.rowSpacing - hairline) / 2` on each side, so
two rows stay exactly `Form.rowSpacing` apart and what changed is that there is
now a line between them. Subtracting the hairline is what keeps that true at
every backing scale — a rule is one *device* pixel, so a fixed half-gap would
make a settings pane a few points shorter at 2x, and in a scrolling pane a fold
that moves with the display is a different app at every DPI.

Remaining recorded divergences, with rationale:

| Surface                | Windows value                    | Rationale |
|------------------------|----------------------------------|-----------|
| Control heights        | `macOS reference + 6 pt` (scaled) | Windows pointer-target ergonomics, applied as one constant. |
| Button content bezel   | 12/3 pt (regular), 16/6 pt (large) | Segoe UI renders wider than SF Pro at the same point size; the horizontal inset is the macOS push-bezel margin, the vertical one is what the control-size height leaves around the line box. |
| Separator thickness    | `1 / displayScale`               | One physical pixel at any backing scale, like an AppKit separator — a 1pt rule would double to 2px at 2x. |
| Tab band inset         | 12/16 pt around a centered group | macOS insets an `.automatic` tab view from the window edge and centres the segment group instead of distributing tabs across the full width. |
| Toolbar band           | Full bleed + bottom hairline     | The navigation title reads as window chrome, not a rounded card floating over the content. |
| List row separator     | Sibling 1px panel between rows   | The retained model has no per-side border, so the rule is a node rather than a bottom edge on the row. It therefore costs one physical pixel of layout height per gap, where AppKit draws the grid line inside the row rect. |
| Grouped-form row rule  | Spans the box's *content* width  | The section's horizontal padding is applied by the stack to every child, and a full-bleed rule would need a negative margin the retained layout has no concept of. macOS bleeds the rule to the box edge. |
| Stepper bezel height   | `2 × (buttonSize.height + delta) + 1px` | The seam is a node, so the joined pair costs one physical pixel more than twice a half — the same separator-thickness divergence the list row rule records. |

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
