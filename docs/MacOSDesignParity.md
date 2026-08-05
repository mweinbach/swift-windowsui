# Design System Values

Source-of-truth values for **this app's design system** — every colour,
radius, spacing step, elevation rung and type role the stack ships. Each
value here is pinned by a machine-checkable test in
`MacOSDesignParityTests`; if a developer changes one of these without
updating the doc the test fails. Animation curves and spring constants are
documented separately in `AnimationParity.md`.

## What this document pins, and what it used to

This started as a macOS *parity* table: the goal was to look like AppKit, and
the values were Apple's published ones. That got the mechanisms right — one
alpha ladder per appearance, a top-lit hairline, opaque accent fills, a
pressed control that does not move — and those mechanisms are unchanged and
still the reason anything here composes.

What it did not get right is the design. An app whose neutrals are AppKit's
`#212121` window and whose accent is whatever blue the OS ships is not a
macOS app; it is an app that looks like it is trying to be one, in a window
manager that is not macOS. The values are now the design system's own:

> **Quiet ink, one signature.** A near-black (or near-white) page, structure
> carried by hairlines and one surface lift, and exactly one saturated moment
> per screen. Nothing else in the window is chromatic.

Where a value still equals its AppKit original that is now a coincidence
worth stating rather than a rule; where it diverges the row says why. The
divergence table at the end of this document is the list of places where the
system deliberately parts company with macOS geometry.

The whole signature reaches the app through **five hex values** — the accent
ink/fill pair and the hero gradient's stops — so restyling the app's
personality later is a table edit, not a redesign. No view may hardcode a
colour; `ControlPalette` is the only source, and `DesignTokens` inside it is
the only place a hex is written.

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
| `caption`     | **11**    | regular      | 13               | the `caption` role         |
| `caption2`    | 10        | regular      | 12               | SwiftUI `Font.caption2`    |

Line height is `size + lineSpacing`, which is what the text renderer sets as
DirectWrite's uniform line height.

`caption` is **11**, not SwiftUI's 10. A caption is the smallest string in the
app a reader is actually expected to read, and at 10pt in the third text rung
it is a texture rather than a string. 10 survives as `caption2`, which is the
*axis-label* role: a number you glance at beside a mark that already told you
the answer.

### Type roles

The weight axis is the hierarchy tool, not size. `card-title` (14/600 at the
first rung) and `body` (13/400 at the second) differ by one point and read as
clearly different roles because weight *and* rung both move. That is the fix
for weak hierarchy — not a size bump.

| Constant                          | Value | Role |
|-----------------------------------|-------|------|
| `Typography.controlLabelSize`     | 12    | A control's own label: a button, a segment, a placeholder. 12/500. |
| `Typography.cardTitleSize`        | 14    | A card's title. 14/600. |
| `Typography.eyebrowSize`          | 11    | Uppercase eyebrow — group titles, column headers. The only uppercase role. |
| `Typography.sectionHeaderSize`    | 11    | A `List` group header — the `eyebrow` role. A list group title genuinely is a *label*: it names the rows under it and is not something you read on the way past. |
| `Typography.formSectionHeaderSize` | **15** | A grouped-`Form` section header — the `section` role: 15/600 at the primary rung, attached to the group under it. |

### The face those sizes are set in

This document pins the point *sizes*. The family they resolve to —
Segoe UI Variable at the optical size each size calls for on Windows 11,
classic Segoe UI on Windows 10 — is `docs/Typography.md`, along with how
glyphs and hairlines land on device pixels at 125% and 150%.

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
| `Typography.sectionHeaderSize`            | 11    | A `List` group header: 11pt semibold at the secondary rung — the `eyebrow` role, unchanged. |
| `Typography.formSectionHeaderSize`        | 15    | A grouped-`Form` section header: 15/600 at the **primary** rung. A settings section header is a heading, not a label; the 11pt secondary-rung eyebrow it used to be is a System Settings idiom, and an 11pt dim string floating between two boxes belongs to neither of them. One call site, two roles, which is why there are two constants. |
| `Typography.symbolBoxRatio`               | 1.25  | An SF Symbol's image box relative to the inherited point size. `Image` inherits the ambient font rather than pinning a fixed 19.4px box. |
| `Typography.uppercaseTrackingRatio`       | 0.06  | Default tracking applied when `textCase == .uppercase`. Capitals carry sidebearings tuned for mixed-case setting; set solid they read as a banner. An explicit `.tracking()` still wins. |
| `Layout.labelIconSpacing`                 | 8     | `Label`'s symbol-to-title gutter. An icon and its label are one object, and 8 is the step the spacing scale has for that; AppKit's 6 is not a member of this grid. |

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

**Four rungs, and the two appearances no longer share their alphas.**

| Rung       | Dark | on `surface-1` | Light | on `#FFFFFF` | Use |
|------------|------|----------------|-------|--------------|-----|
| primary    | 0.95 | `#F2F2F3` 15.5:1 | 0.92 | `#1B1B1D` 15.9:1 | Headlines, card titles, metric values, selected labels |
| secondary  | 0.66 | `#ADADAF` 8.2:1  | 0.66 | `#58585B` 7.3:1  | Body, summaries, control labels, unselected nav |
| tertiary   | 0.47 | `#818184` 4.7:1  | 0.54 | `#757577` 4.9:1  | Captions, eyebrows, axis labels, resting icon glyphs |
| quaternary | 0.30 | `#5B5B5E` 2.5:1  | 0.34 | `#A9A9AB` 2.5:1  | Disabled labels, chevrons, decoration — **never a string the user must read** |
| quinary    | 0.18 | —                | 0.20  | —            | SwiftUI's fifth rung |
| secondary, `.increased` | 0.80 | — | 0.80 | — | one step toward primary |
| tertiary, `.increased`  | 0.62 | — | 0.68 | — | " |

AppKit's published alphas (`#..D9`, `#..8C`, `#..40`, `#..19`) were authored
against a `#212121` window. On the near-black `#0C0C0E` page this system
specifies, the third rung composites to **2.4:1** — which is why every caption
in a dark render read as noise rather than as text.

The light column is *not* the dark one, because a black wash on white loses
contrast faster than a white wash on near-black does: the two dimmer rungs
need more alpha in light to land on the same reading. The quaternary rung is
deliberately below AA; it is for chevrons and decoration.

The base is white in the dark appearance and `#0C0C0E` in the light one — the
page's own ink, not pure black, which reads a shade warm on a cool near-white
page. The dark column doubles as the sentinel set
`Color.labelHierarchyLevel` recognises, so `Color.primary` and
`ControlPalette.label` are the same colour by construction.

Recognition is by exact rung value: a colour the app wrote itself is not a
semantic role and passes through untouched, and `Color.accentColor` (#5B4DE0)
is never desaturated. The known limitation is that `Color.primary.opacity(0.5)`
is no longer a recognised rung — an app that wants a dimmer label should ask
for `.secondary` rather than fade `.primary`.

`.increased` background prominence means **"this content sits on a *filled*
emphasised surface"**. It promotes secondary to primary, and it changes the
*base*: a filled accent surface is the same hex in both appearances, so the
ladder over it is built on `selectedContentLabel` (white) rather than on the
appearance's base. Promoting the rung while keeping the light appearance's
black base put an 85%-black label on the accent fill;
`testSelectionContentIsLightInBothAppearances` pins it.

A **selected list row no longer sets it**, because a selected row is an accent
wash rather than a fill (see "Semantic control palette" below). Inverting
content to white over a wash is white-on-`#E4E2F8` in the light appearance.
The flag stays exactly what it says it is, and is now only claimed by surfaces
that genuinely are filled.

### A quaternary background is a bar, not a shade

The rungs resolve differently on the way to a *fill*, in exactly one place.
`.background(.quaternary)` is the idiomatic bottom bar — the scrim that closes
a list with an inspector or status strip.

**A bar is never brighter than the list it closes in the dark appearance, or
darker than it in the light one.** Drawn as a wash the rung fails that in
whichever appearance it is not tuned for. The light black wash landed the bar
at #D5D5D5 on the #ECECEC window — below the page it closed, which no bottom
bar is. And once the dark rung moved to 0.30 for legibility, the same maths
lifted a dark footer well above the table over it: a bar brighter than its own
content, which reads as a second window pinned to the bottom of the first.

A quaternary *background* therefore resolves to
`ControlPalette.windowBackground` in **both** appearances, and the hairline
above it carries the edge — one rule, the same one Finder's status bar and
Xcode's debug bar follow. The *label* resolution of the rung is untouched.
`Color.resolvedForBackgroundVisualEnvironment` implements the split;
`testQuaternaryBackgroundIsABarNotAShadeInLight` pins it.

## The neutral ramp

`DesignTokens` (Sources/WinSwiftUI/ControlPalette.swift) is the table every
neutral in the app comes from. Roles are named by *what a surface is for*;
tokens by *where they sit in the ramp*, and keeping them apart is what makes
the design restylable.

| Token      | Dark      | Light     | Use |
|------------|-----------|-----------|-----|
| `base`     | `#0C0C0E` | `#F2F3F5` | Window backdrop, sidebar and rail columns, tab band, page gutters |
| `surface0` | `#111113` | `#F7F8FA` | Content wells, scroll wells, table bodies |
| `surface1` | `#17171A` | `#FFFFFF` | **Cards.** The one and only card fill |
| `surface2` | `#1E1E22` | `#F1F2F5` | Inside a card: fields, chips, icon tiles, segmented track, row hover |
| `surface3` | `#26262B` | `#E6E8EC` | Pressed / active / selected-neutral; menu and popover body |
| `surface4` | `#2C2C32` | `#ECEDF1` | One step past `surface3` — a bordered control held down |
| `scrim`    | `#000000` @ 0.55 | `#0C0C0E` @ 0.28 | Sheet / dialog backdrop |

Hairlines, and the ring stop above them:

| Token          | Dark          | Light           | Use |
|----------------|---------------|-----------------|-----|
| `strokeSubtle` | white @ 0.06  | `#0C0C0E` @ 0.07 | Separators, table/form row rules, chart gridlines |
| `stroke`       | white @ 0.09  | `#0C0C0E` @ 0.10 | Card ring, chip ring, field ring |
| `strokeStrong` | white @ 0.14  | `#0C0C0E` @ 0.15 | Toolbar/footer band edges, popover ring, control bezel, chart baseline |
| `edgeHighlight`| white @ 0.10  | white @ 0.75    | Top stop of every ring |

**Achromatic within a hair.** The neutrals carry at most an 8/255 cool cast
between their red and blue channels — enough that a near-black page reads as
ink rather than as brown, and far short of the blue-cast navy this stack
started from (`(0.07, 0.10, 0.15)` surfaces under `(0.92, 0.95, 1.0)`
"whites", 171 literals on a navy axis where blue was roughly twice red).
`ControlAppearanceChromeTests.testNeutralRolesAreAchromatic` pins the bound.

The containers a screen actually shows — the navigation band, the tab bar,
`Form` and `Section` boxes, `List` bodies and their hairlines, the scroller
thumb, the window backdrop — read roles from `ControlPalette` rather than
holding literals, so they follow the appearance rather than staying dark
under light text.

## The accent: one accent, two roles

The split is the system's core colour idea. An accent used as **ink** must
vary with the appearance behind it; an accent used as an **opaque fill** has
no appearance to vary with.

| Token                | Dark      | Light     | Use |
|----------------------|-----------|-----------|-----|
| `accentForeground`   | `#8B7CFF` (5.6:1 on `surface1`) | `#5B4DE0` (5.9:1 on white) | Accent **as ink**: chart bars, selection indicators, active glyphs, link text, focus ring |
| `accentFill`         | `#5B4DE0` | `#5B4DE0` | Accent **as an opaque fill** under white text: prominent buttons, filled badges, toggle-on, menu highlight. White on it = 5.9:1 |
| `accentFillHovered`  | `#6A5DE8` | `#6A5DE8` | |
| `accentFillPressed`  | `#4A3EC4` | `#4A3EC4` | |
| `accentWash`         | ink @ 0.14 | ink @ 0.10 | Selected nav row, hovered chart column, tag chips |
| `accentWashStrong`   | ink @ 0.20 | ink @ 0.15 | Selected row in a focused list |
| `accentRing`         | ink @ 0.45 | ink @ 0.45 | Keyboard focus halo |
| `accentSelection`    | ink @ 0.30 | ink @ 0.30 | Text selection |

`Color.accentColor` and `ViewBuildContext.defaultTint` are `accentFill`.
`ControlPalette.accentInk(for:)` is how chrome crosses from one role to the
other: hand it the ambient tint and, if that tint is the system accent, it
resolves to the appearance's own `accentForeground`; a tint the app chose
itself passes through untouched — the same exact-value recognition rule the
label ladder uses. Chrome that draws the accent as a line, a glyph or a ring
goes through it; chrome that fills a surface does not.

Status colours ride a 6–7pt dot, a meter fill or 11pt chip text — never a
large fill, never body text, never a button fill.

| Token     | Dark      | Light (contrast on white) |
|-----------|-----------|---------------------------|
| `success` | `#3FD08A` | `#0B7A52` (5.4:1) |
| `warning` | `#F5B93C` | `#A45A00` (5.2:1) |
| `danger`  | `#FF6F6F` | `#C62B22` (5.6:1) |
| `*Wash`   | hue @ 0.14 | hue @ 0.10 |

## The spacing and radius scales

`MacOSControlMetrics.Spacing` is a 4/8 grid — `4 8 12 16 20 24 32 40 48 64` —
and **nothing else is legal**. The app used to space things at 6, 10, 14, 18,
26 and 30 as often as at 8, 12 and 16, because every gap was chosen where it
was written. Half a dozen near-miss values do not read as a rhythm; they read
as the absence of one, and no amount of care at any single site recovers it.

`MacOSControlMetrics.Radius`:

| Token | Value | Applies to |
|-------|-------|------------|
| `xs`  | 3     | Chart bar caps, selection indicator bars, mini meters |
| `sm`  | 6     | **Controls**: button, text field, segment pill, checkbox, nav row, table row hover/selection, tab item |
| `md`  | 8     | Chip, icon tile, segmented track, badge |
| `lg`  | 10    | **Cards**, form section boxes, group boxes |
| `xl`  | 12    | Hero, popover, menu, sheet, dialog |

**Nothing in the app exceeds 12**, and full-bleed regions take radius 0 and
are bounded by a hairline instead. The 16 / 20 / 22 / 24 / 26 / 30 the app
used to carry is what made it read as bubbly: a 20pt radius on a 28pt row is
a stadium, and a window full of stadiums is a consumer toy however correct
its tones are.

## The elevation ramp

**Structure is carried by the hairline; a shadow only ever says "this
floats."** That distinction is the whole ramp — a card in the page is flat
and closed by a ring, and only something genuinely above the page casts
anything.

| Level | Dark | Light | Applies to |
|-------|------|-------|------------|
| `e0` | none | none | Everything flat in the page: nav rows, table rows, form rows, chips, and **all cards in dark** |
| `e1` | black @ 0.30, r 3, y 1 | `#0C0C0E` @ 0.06, r 3, y 1 | Cards and form boxes **in light**; segmented selected pill; toggle knob |
| `e2` | black @ 0.38, r 10, y 4 | `#0C0C0E` @ 0.08, r 8, y 3 | Toolbar band over scrolled content, inline popup, tooltip |
| `e3` | black @ 0.50, r 24, y 12 | `#0C0C0E` @ 0.13, r 22, y 10 | Menu, popover, sheet, dialog |
| `e4` | `#5B4DE0` @ 0.22, r 28, y 10 | `#5B4DE0` @ 0.16, r 24, y 10 | **The hero card only.** The one tinted shadow in the app |

**The appearance-conditional card rule.** In dark a card is `surface1` closed
by a hairline and casts nothing: a shadow under a near-black card on a
near-black page is invisible work, and at any alpha strong enough to see it
fills the 12pt gutter beside the card with a grey smear instead of page tone.
In light a white card on `#F2F3F5` takes `e1` — a 3pt blur at y 1 that reads
as a paper lift. `ControlPalette.groupedContainerShadow` and
`ControlPalette.controlShadow` both state it once and resolve twice.

**No shadow offset in the app exceeds 12.** The retired ramp had one shadow
used at every level with an *unspecified* offset that defaulted large — 8pt
of blur at **y 14**, under a 12pt gutter — so every gutter in the window was
filled with a shadow smear rather than showing the page base. That was the
single largest source of the muddy read in both appearances.

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
| `SurfaceChrome.focusRingStrokeWidth`  | **2** | Focus-ring stroke. Equals `MacOSControlMetrics.FocusRing.strokeWidth`; the two used to disagree (2 vs 4) with both pinned as "the" macOS value. A 2pt halo outside a 1px accent border — see the divergence table. |
| `SurfaceChrome.default.focusRingWidth`| 2     | "                                       |
| `SurfaceChrome.elevatedButton.borderWidth` | 1 | Elevated/prominent buttons match.       |
| `SurfaceChrome.elevatedButton.focusRingWidth` | 2 | "                                    |
| `ControlPalette.focusRingAlpha`       | **0.45** | A focus ring is a thin accent outline, drawn in the accent as *ink* so it is visible against the page it sits on. `accentFill` as a ring is 2.7:1 on the near-black page — a focus ring you cannot see on the control you just tabbed to. |
| `MacOSControlMetrics.Button.regularCornerRadius` | 6 = `Radius.sm` | Push-bezel corner radius. A capsule is the opt-in shape (`.buttonBorderShape(.capsule)`), never the default — 16 on a 22–30pt control clamps to h/2 and renders every button as a stadium. |
| `MacOSControlMetrics.Button.smallCornerRadius` | **6** = `Radius.sm` | `.small`, and the segmented pill — the same shape as the standard bezel at a smaller size. The 4 it used to carry is not a member of the radius scale. |
| `MacOSControlMetrics.Button.miniCornerRadius` | 3 = `Radius.xs` | `.mini`.                  |
| `MacOSControlMetrics.Button.largeCornerRadius` | 8 = `Radius.md` | `.large`.                |
| `Controls.surfaceSheenFactor`         | **0.98** | Luminance the bottom stop of a control sheen keeps, on a full-value surface. A surface travels at the *edge of perception* — a couple of levels of 255 — and that slight amount is the whole difference between a surface and a rectangle of paint. 0.82 was an 18% drop that made every control a styled div; 0.96 was still visible on a card the size of a settings box. |
| `Controls.surfaceSheenDrop`           | **0.02** | The same step stated as a distance rather than a ratio (`1 - surfaceSheenFactor`), so a translucent surface falls by what the *window* shows rather than by its own channels. |
| `Controls.surfaceSheenRelativeCeiling`| 0.16  | Most of itself a surface may lose to its own sheen. The absolute step is calibrated on a near-white bezel; on a dim one it is most of what the surface has, and a `white(0.10)` control over a black page (25/255) would dissolve its bottom edge into the window. macOS's dark push bezel travels ~14% of itself. |
| `Controls.borderSheenFadeFactor`      | 0.55  | Strength a bezel's ring keeps at its far edge. |
| `Controls.grooveSheenFactor`          | **0.95** | The deeper shade a genuinely recessed groove keeps (slider/progress track, segmented track, text-field well). A groove is shaded rather than lit, so it travels further than a surface — still near-flat. |

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
| `ControlAnimationStyle.default.pressedScale` | 1 | A macOS control does not change geometry on press — see below. |
| `ControlAnimationStyle.tactilePressedScale` | 0.97 | The shrink, opt-in per style. Nothing built for parity references it. |
| `ControlPalette.pressedContentOpacity` | 0.72 | Borderless styles only: no bezel to move, so AppKit darkens the contents. |
| `ControlAnimationStyle.default.focusDuration` | 0.18s | Hover/focus cross-fade.            |
| `ControlAnimationStyle.default.pressDuration` | 0.14s | Press-state colour cross-fade.     |

## A pressed control does not move

macOS answers a press with the cell's highlight and nothing else: the bezel
fill darkens in the light appearance and brightens in the dark one, in exactly
the frame the control had at rest. `NSButton`, `NSSegmentedControl`,
`NSPopUpButton`, `NSStepper`, `NSSwitch` — none of them scales, lifts or nudges
under the pointer, from Big Sur through Sonoma.

The 0.97 shrink this table used to pin as a "Big Sur feel" is an iOS /
custom-`ButtonStyle` idiom. It was never a macOS behaviour, it reached the
gallery's pressed entries, and by the time anything rendered a pressed control
it read as intentional. It is gone from the default (E6-PRESS); the machinery
stays, opt-in per style, as `ControlAnimationStyle(pressedScale:)`.

Removing it makes the fill ramp the entire affordance, which two rungs were not
strong enough to carry alone:

- an **unselected segment** pressed to `tertiaryFill`, one rung above its own
  hover — a 10/255 step against the segmented track. It presses to `systemFill`
  now, about 20/255, in line with the ~28/255 a push button moves;
- the **switch** painted an opaque pale blue plate (`#B8D1EB`) behind itself on
  pointer-down and a slate one on hover — hand-tuned literals from before there
  was an appearance to resolve against, identical in light mode and dark. It
  presses to the appearance's own neutral wash now.

And it leaves the borderless styles with nothing to change, since `.plain` /
`.borderless` / `.link` are transparent in every state. AppKit's borderless
button highlights by darkening its *contents* (`NSCell.StyleMask`'s
`contentsCellMask`), which is `SurfacePalette.pressedContentOpacity` — set for
those styles and left at `1` everywhere a bezel exists.

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
| `MacOSControlMetrics.Form.contentMaxWidth`     | **720** | Width of the content column. 640 centred in a 1280 window leaves ~340pt of dead space on each side and reads as a pane borrowed from another app. |
| `MacOSControlMetrics.Form.contentHorizontalMargin` | 20 | Margin inside the column. Still a *centred* column: leading-anchoring it inside the page margin is a decision the settings pane makes, not a chrome default — moving it here would re-anchor every grouped `Form` in every app. |
| `MacOSControlMetrics.Form.labelColumnGap`      | **12** | Label column to value column. |
| `MacOSControlMetrics.Form.sectionSpacing`      | **24** | Box to the next section's header. |
| `MacOSControlMetrics.Form.headerSpacing`       | **8**  | Header to the box it names — 8 below against 24 above, the 3:1 ratio that keeps a header attached to what is *under* it rather than floating between two groups. |
| `MacOSControlMetrics.Form.headerLeadingInset`  | **0**  | A section header sits flush with the box it names. |
| `MacOSControlMetrics.Form.rowSpacing`          | **12** | Row to row inside a box. |
| `MacOSControlMetrics.Form.boxVerticalPadding`  | **8**  | Group box interior. The end state is 0 — a row states its own `rowMinHeight`, so box padding only doubles the first and last gaps — but that is only correct once rows carry that height, which is the settings pane's own rebuild. Kept at one scale step until then, and recorded as the interim it is. |
| `MacOSControlMetrics.Form.boxHorizontalPadding`| 16     | " |
| `MacOSControlMetrics.Form.rowMinHeight`        | 36     | Minimum height of a form row. |
| `MacOSControlMetrics.Form.descriptiveRowMinHeight` | 52 | …and of a row that also carries a description line. |
| `MacOSControlMetrics.GroupBox.cornerRadius`    | 10 = `Radius.lg` | The card radius. The previous 28 on a 600pt-wide card is a marketing panel, not a settings box. |
| `MacOSControlMetrics.GroupBox.shadowOffsetY`   | **1**  | `Elevation.e1`. The unspecified offset that used to default large is what smeared every gutter in the window. |
| `MacOSControlMetrics.GroupBox.shadowSpread`    | 3      | " |
| `ControlPalette.groupedContainerShadow` (light)| `#0C0C0E` @ 0.06 | `e1` — a paper lift. |
| `ControlPalette.groupedContainerShadow` (dark) | **none** | A shadow under a near-black card on a near-black page is invisible work, and at any alpha you can see it fills the gutter beside the card with a smear. The hairline carries the edge. |
| `ControlPalette.raisedSurfaceHighlight` (light)| white @ 0.75 | Top edge of a container's ring (`edgeHighlight`). |
| `ControlPalette.raisedSurfaceHighlight` (dark) | white @ 0.10 | " |

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

`ink(_:)` below is `#0C0C0E` at an alpha — the page's own neutral, which is
what a light-appearance wash is mixed from. Pure black on a cool near-white
page reads a shade warm; the page's ink does not.

| Role                             | Dark            | Light           | Token |
|----------------------------------|-----------------|-----------------|-------|
| `windowBackground`               | #0C0C0E         | #F2F3F5         | `base` |
| `controlBackground`              | #111113         | #F7F8FA         | `surface0` |
| `controlSurface` (bordered face) | #1E1E22         | #FFFFFF         | `surface2` / `surface1` — **opaque**. A `white(0.10)` wash over a #212121 window was a visible plate; over the near-black page it is 25/255 of nothing, and every button dissolved into its own backdrop |
| `controlSurfaceHovered`          | #26262B         | #F7F8FA         | `surface3` / `surface0` |
| `controlSurfacePressed`          | #2C2C32         | #ECEDF1         | `surface4` |
| `fieldSurface`                   | #1E1E22         | #FFFFFF         | The appearances are genuine inverses and both are right: a field is one step *lighter* than the card on near-black (a darker recess there is a hole) and one step lighter than the chips beside it on near-white |
| `raisedSurface`                  | #17171A         | #FFFFFF         | `surface1` |
| `label`                          | white @ 0.95    | ink @ 0.92      | text-1 |
| `secondaryLabel`                 | white @ 0.66    | ink @ 0.66      | text-2 |
| `tertiaryLabel`                  | white @ 0.47    | ink @ 0.54      | text-3 |
| `quaternaryLabel`                | white @ 0.30    | ink @ 0.34      | text-4 |
| `disabledLabel`                  | white @ 0.30    | ink @ 0.34      | text-4 — a disabled label is the same tone as a chevron |
| `separator`                      | white @ 0.06    | ink @ 0.07      | `strokeSubtle` |
| `controlBorder`                  | white @ 0.09    | ink @ 0.10      | `stroke` |
| `controlBorderStrong` / `separatorStrong` | white @ 0.14 | ink @ 0.15 | `strokeStrong` |
| `unemphasizedSelectedBackground` | #26262B         | #E6E8EC         | `surface3` |
| `systemFill` … `quinaryFill`     | white @ .10/.08/.05/.03/.02 | ink @ same | fill ramp |
| `controlTrack`                   | #26262B         | #D2D4DA         | slider / progress / switch groove. The `#4D5766` slate it used to be was the last chromatic neutral in the app, on the one control that sits in every settings row |
| `segmentedTrackFill`             | #1E1E22         | #F1F2F5         | `surface2` — a recess inside a card is a recess inside a card |
| `segmentedSelectedFill`          | #26262B         | #FFFFFF         | `surface3` + `e1`. The pill's lift comes from *elevation*, not lightness: #636366 was a mid-grey plate six steps above its own track so it could be seen |
| `segmentedSelectedLabel`         | `label`         | `label`         | a selected segment is the one you are meant to read |
| `elevatedSurface`                | #26262B @ 0.98  | #E6E8EC @ 0.98  | floating-panel material |
| `elevatedSurfaceBorder`          | `strokeStrong`  | `strokeStrong`  | a floating panel has no page around it to borrow an edge from |
| `scrollerKnob`                   | white @ 0.22    | ink @ 0.18      | overlay knob — **nearly invisible at rest** |
| `scrollerKnobHovered`            | white @ 0.34    | ink @ 0.30      | knob under the pointer |
| `scrollerKnobActive`             | white @ 0.50    | ink @ 0.46      | knob being dragged |
| `accentForeground` / `accentFill` | see the accent section above | | |

`controlTrack` is the groove a *continuous* control's fill runs along: a
`Slider`'s unfilled bar, a determinate `ProgressView`'s remainder, a `Gauge`'s
empty span, and the body of an `off` `Toggle`. All four read the same
hard-coded dark slate off `Controls` and no WinSwiftUI caller overrode it, so
`--appearance light` drew a near-black bar across a white settings pane and an
`off` switch came out charcoal. It is `surface3` now: a groove is a recess in
a surface, and it is whatever tone that surface's own ramp says a recess is,
not a colour of its own. `ControlTrackAppearanceTests` pins both values and
the wiring on all four controls.

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

Selection and accent are derived, not stored. There are **two** selection
fills and the difference matters:

- `selectedContentBackground(tint:)` is the **opaque** accent, for a surface
  that genuinely is filled — a highlighted menu item, a filled badge. White
  content on it.
- `listSelectionBackground(tint:)` is an **accent wash** (`accentWashStrong`),
  for a row in a list or table. A selected row used to take the solid accent
  with white text on it; on the demo's Data screen that is a full-bleed
  saturated band across the window — the loudest object in the app for the
  least important reason. The wash keeps the row on the page's own ladder and
  lets a leading indicator bar say "this one". An unfocused list falls back to
  the neutral `surface3` fill.

Because the row is no longer a *filled* surface, a selected row does not set
`.increased` background prominence any more: that flag means "this content
sits on a filled emphasised surface", and inverting content to white on a
wash is white-on-`#E4E2F8` in the light appearance. The row supplies the
primary label rung as its inherited default instead.

Accent state is a lightness move — the pinned `accentFillHovered` /
`accentFillPressed` stops for the system accent, +8% / −12% for a tint the app
chose — never an alpha ramp that lets the backdrop bleed through a
half-disabled looking fill.

`ControlPalette.controlShadow` follows the same appearance-conditional rule
the cards do: `e1` in light, nothing in dark. A control shadow is never
tinted with the accent or role colour.

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

`Color.accentColor` and `ViewBuildContext.defaultTint` are the design
system's own `accentFill` (`#5B4DE0`) and are **not** members of this pair
table. They used to be `Color.blue`'s light value (`#007AFF`), macOS's
default controlAccentColor — the right answer for an app cloning macOS and
the wrong one for an app with a signature: the OS blue arrived in every
render as a fourth unrelated hue beside the module tints, and "the accent"
was whatever the OS happened to ship.

Because the accent is not in the pair table, the resolver returns it
unchanged in either appearance, which is exactly right for a fill. The *ink*
half of the accent is per-appearance and lives on `ControlPalette`
(`accentForeground`), reached from a tint through `accentInk(for:)`.

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
| Push bezel corner radius     | `Button.regularCornerRadius`              | 6 pt (`Radius.sm`) |
| Push button (.large)         | `Button.largeHeight`                      | 32 pt     |
| Toggle switch (.regular)     | `Toggle.regularSize`                      | **40×22 pt**, knob 18 at a 2pt inset |
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
| Text field (.regular)        | `TextField.regularHeight`                 | **22 pt** — so `+ windowsPointerPadding` lands a field on 28, the same height as a button |
| List row (plain)             | `List.plainRowHeight`                     | **30 pt** |
| List row (sidebar)           | `List.sidebarRowHeight`                   | **30 pt** — one row height for the app |
| List content inset           | `List.contentInset`                       | 16 pt     |
| Inset list body corner       | `List.insetCornerRadius`                  | 6 pt (`Radius.sm`) |
| Inset list body top/bottom   | `List.insetVerticalInset`                 | 6 pt      |
| Overlay scroller knob        | `Scroller.overlayThumbThickness`          | **6 pt**  |
| Overlay scroller inset       | `Scroller.overlayInset`                   | 4 pt      |
| Overlay scroller min knob    | `Scroller.minimumThumbLength`             | 24 pt     |
| Toolbar (regular)            | `Toolbar.regularHeight`                   | 52 pt     |
| Window corner radius         | `Window.cornerRadius`                     | 10 pt (`Radius.lg`) |
| Sheet corner radius          | `Window.sheetCornerRadius`                | 12 pt (`Radius.xl`) |
| Focus ring stroke            | `FocusRing.strokeWidth`                   | **2 pt**  |
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

A modern overlay scroller is also **nearly invisible at rest**: the 0.48 /
0.42 knob this used to draw made the scrollbar the brightest object in
whatever column it floated over, which is the one thing a scrollbar must never
be. The lifecycle below is unchanged — fast in, quiet out.

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
| **Focus ring**         | 2 pt halo outside a 1 px accent border, alpha 0.45 | macOS draws a 4 pt soft ring. On this radius scale 4 pt of ring around a 6 pt corner swallows the corner, so the focused control loses the shape that identifies it at the moment you need to find it. |
| **Toggle switch**      | 40×22 with an 18 pt knob         | The one control sized outside the "reference + pointer padding" rule. A padded 38×22 comes out at 52×32, which is an iOS switch: the largest object in a settings pane, for a boolean. |
| **Text field height**  | reference 22 rather than 21      | So the shipped field is 28 — the same height as a button. A field and the button beside it differing by one point is the kind of misalignment nobody can name and everybody sees. |
| **List row height**    | 30 plain *and* 30 sidebar        | macOS's 24/28 split is a distinction between two kinds of list this design does not draw, and a 24 pt row is cramped under a 13 pt label with a 15 pt glyph beside it. |
| **Selected list row**  | accent *wash* + primary label    | macOS fills a selected row solid with white content on it. At full-bleed table width that is the loudest object in the app for the least important reason; the wash plus a leading indicator says the same thing quietly. |
| **`caption` size**     | 11 rather than SwiftUI's 10      | The smallest string a reader is expected to read. 10 survives as `caption2`, the axis-label role. |
| **Section header**     | 15/600 at the primary rung       | A settings section header is a heading, not a label. The 11 pt secondary-rung eyebrow is a System Settings idiom and floats between two boxes belonging to neither. |
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
