# Typography

What face this stack sets text in, how a run's optical size is chosen, and
what "crisp at 125%" means as something a test can measure.

The point *sizes* — the type ramp, leading, tracking — live in
`docs/MacOSDesignParity.md` under "Chrome type". This document is about the
face those sizes are set in and about how the result lands on device pixels.

## The UI face

`SystemUIFontFace` (`Sources/SwiftWindowsUI/SystemUIFontFace.swift`) resolves
the default UI family. `Font.resolvedFamily` is its only caller in normal
operation, so every `Text` and every control label in `WinSwiftUI` goes
through it.

| Windows | Face |
|---|---|
| 11 | **Segoe UI Variable**, in the optical size the run's point size calls for |
| 10 | **Segoe UI** (classic), at every size |

Windows 11 uses Segoe UI Variable for all of its own UI. Text set in the
classic face on Windows 11 is the loudest "this is not a modern app" signal a
window can emit, because every surface around it is in the variable face.

### Why the face is probed, not assumed

`IDWriteFactory.CreateTextFormat` returns `S_OK` for families that are **not
installed** and substitutes silently at layout time. A stack that simply asked
for "Segoe UI Variable Text" on Windows 10 would get a format, a layout and
glyphs — all of them from some other face, with no error anywhere.

The honest answer comes from `IDWriteFontCollection.FindFamilyName` against
the system collection, wrapped as
`DirectWriteTextRenderer.isFontFamilyInstalled(_:)`. The result is memoized
for the process: it cannot change while the app runs short of a font install,
and it is read once per `Text` in every rebuilt body.

`SWIFT_WINDOWSUI_CLASSIC_UI_FONT=1` forces the Windows 10 branch. Without it
the fallback path is unreachable — and therefore uninspectable — on any
machine that has the variable face, which is every Windows 11 machine this
stack is developed on.

### Optical size

Segoe UI Variable is one variable font with an `opsz` axis, which Windows
exposes as three families. They are not interchangeable styles: `Small` has
open apertures and loose fitting so a 10pt caption stays legible, `Display`
has tight fitting and fine strokes that only resolve at headline size.

| Point size | Family | This stack's roles |
|---|---|---|
| `< 12` | `Segoe UI Variable Small` | footnote, caption, caption2 (10pt), subheadline (11pt) |
| `12 ..< 20` | `Segoe UI Variable Text` | callout (12), body and headline (13), title3 (15), title2 (17) |
| `>= 20` | `Segoe UI Variable Display` | title (22), largeTitle (26) |

The bounds are `SystemUIFontFace.smallOpticalSizeUpperBound` and
`.displayOpticalSizeLowerBound`. `20` is where the named instances' own
geometric midpoint falls (`Text` is cut at `opsz` 12, `Display` at 36, and
`sqrt(12 × 36) ≈ 20.8`). `12` is above that rule's `sqrt(8 × 12) ≈ 9.8`
midpoint deliberately: at 10 and 11pt the `Small` cut is visibly more open
and better spaced than `Text`, which is what the caption sizes in this stack
need. That was decided by rasterizing the same caption in all three cuts at
each size and magnifying — not from the table — and it goes the other way at
the top of the ramp: at 17pt `Display` already reads thin and tight, which is
why the `Display` bound sits at 20 rather than following WinUI's 15pt
Subtitle.

**Point size, never device pixels.** Optical size tracks the physical size a
reader sees, and that is what a point already is: 10pt is 10pt at 96 DPI and
at 144 DPI, drawn from more device pixels at the same apparent size. Keying
the ramp off device pixels would also put 8pt at 150% and 12pt at 100% in the
same family while the glyph atlas — whose key *is* device pixels — held one
entry standing for two different faces.

### All three cuts or none

`isVariableFaceAvailable` is the conjunction over every optical size. A window
whose captions were Segoe UI Variable Small and whose headlines were classic
Segoe UI would be mixing two type designs, which is worse than either used
consistently.

### What the face change does and does not move

Measured on this stack's own sample text:

- **Body is metric-compatible.** Segoe UI Variable Text and classic Segoe UI
  measure identically at 13pt (258.0px for a 43-character line) and at 26pt.
  Nothing in a body-text layout moves.
- **Captions get ~3.5% wider** (`Small` is fitted looser: 206 vs 199px at
  10pt). This is the optical size doing its job.
- **Titles get ~1.7% narrower** (`Display` is fitted tighter: 507 vs 516px at
  26pt).
- **Weights resolve**, including bold: `regular < semibold < bold` in ink mass
  in all three cuts. Segoe UI Variable's weight axis reaches 700.
- **Italic is synthesized.** Segoe UI Variable has no italic outlines, so
  DirectWrite applies an oblique — the same thing Windows itself does. The
  raster still changes, which is what `SystemUIFontFaceTests` pins; what it
  does not do is switch faces mid-sentence to borrow classic Segoe UI's real
  italics, because a metric discontinuity inside a line reads worse than a
  shear.

## Rasterization at fractional display scale

### Glyphs

Glyphs are rasterized at their **effective device size** at every scale,
including 1.25, 1.5 and 1.75. The path is
`ScenePainter.appendNativeTextGlyphs`:

```
rasterScale       = NativeGlyphAtlas.glyphRasterScale(contentScale)   // rungs of 2^(1/8)
rasterScaleFactor = displayScale * rasterScale                        // display scale un-quantized
```

`contentScale` is the *transform* scale (a `scaleEffect`, a press spring),
and only that is quantized to rungs — so a live animation does not churn the
atlas. `displayScale` multiplies in directly. This matters because the rungs
would put 1.25 on 1.2968 and 1.5 on 1.5422, a 3–4% resample at exactly the
two DPI settings Windows users run at.
`MultiDPIParityTests.testDisplayScaleReachesTheRasterizerUnquantized` pins it
by comparing the emitted glyph cells against both candidate rasters.

Crispness itself is measured, not asserted:
`testFractionalScaleGlyphsAreRasterizedAtDeviceSizeNotMagnified` takes the
mean 10–90% coverage ramp over every ink edge, in device pixels, and requires
it to stay flat as scale rises — against a **control** that bilinearly
magnifies the 1x raster and must measure visibly softer. At 26pt the fresh
ramp holds at 1.6–1.9 device px from 1.0x through 3.0x while the magnified
control climbs 1.7 → 3.5 → 4.5 → 6.1 → 6.9.

A display-scale change re-rasterizes rather than reusing: the glyph cache key
is the device pixel size, so a window dragged from a 100% monitor to a 150%
one misses the cache and re-rasterizes for the new monitor
(`testDisplayScaleChangeReRasterizesGlyphsAtTheNewDeviceSize`).

The rasterizer also preserves effective scales below 1. A shrinking transform
must shrink the ink as well as the advances; clamping the raster to 1x made
half-size labels draw full-size letters on half-size spacing.
`ScaledTextLayoutTests.testShrinkingLabelShrinksItsGlyphCellsAcrossDisplayScales`
checks both cell dimensions at 100%, 125%, 150%, and 200% display scale.

Whole-symbol bitmaps measure their natural width in leading/top coordinates,
then paint with the requested alignment. Centering a measurement probe inside
a large layout box introduced enough floating-point error to make a 15.2pt
icon exceed its own raster width at 125% DPI. Text fitting then replaced the
icon with a period, whose glyph is missing from the icon font. The measurement
and raster now agree; `SymbolIconRenderingTests` checks the intended symbols
at 100%, 125%, 150%, 175%, and 200% without changing their font mappings.

### Line spacing

DirectWrite's uniform line height already contains `fontSize + lineSpacing`.
The captured line box includes that leading, so the painter adds no second
gap between those boxes. Empty lines and reserved line limits use the same
height, and the baseline remains the baseline supplied to DirectWrite.
`TextShapingPipelineTests.testNativeParagraphLeadingIsAppliedOnce` checks
measurement and painted baseline spacing together.

If a styled span uses a larger font than the paragraph, the line grid expands
to DirectWrite's largest natural ascent and descent in the source paragraph,
plus nonnegative authored leading. Every shaped line and the whole-string
bitmap use that same baseline and height, including empty and reserved lines.
The grid conservatively retains the larger font's space if truncation hides
that span. Plain text and spans at the base size keep the existing type-ramp
metrics. The span regression in `TextShapingPipelineTests` checks glyph ink
against line bounds and requires separate bitmap ink bands across newlines.

### Hairline rules: the device-pixel pin

**Rule: a separator is pinned to whole device pixels along its thin axis.**
`ScenePainter.devicePixelSnappedRule`, applied to any node the runtime has
marked `isSeparatorRule` that is an axis-aligned, unscaled leaf.

The thin axis rounds to the nearest whole device pixel with a floor of one (a
rule never vanishes), and the origin is placed so the snapped span keeps the
rule's centre — it moves by at most half a device pixel from where layout put
it. The long axis is left exactly as laid out: its ends are covered by
whatever it runs between, and rounding them would shorten a rule meant to
reach an edge. This is a *paint*-time pin; the node's layout frame is
untouched, so nothing around it moves.

#### Why it is needed

Both backends rasterize a quad the same way: the pixel shader runs only where
a pixel **centre** falls inside the rect, and the signed-distance term inside
it can attenuate that coverage but never extend it. The D3D11 vertex stage
emits the rect itself with no antialiasing margin, and
`GPUIQuadCoverage.geometryCovers` mirrors that exactly.

So a rect one device pixel thick sitting on a half pixel — device y
`12.5 ..< 13.5` — contains exactly one pixel centre, at distance 0 from its
own edge, and draws at coverage `0.5`. The other half of the rule's ink is
not redistributed to the neighbouring row; it is gone, and the separator
renders at half its intended weight.

At 100% and 200% that is rare, because a layout in whole points lands on
whole device pixels. At 125%, 150% and 175% it is the common case: 10pt ×
1.25 is 12.5. That is why separator weight used to vary with DPI.

Measured on a `Divider` over three layout offsets × five display scales,
peak coverage against an intended 0.10:

| | before | after |
|---|---|---|
| cases at full weight | 6 / 15 | **15 / 15** |
| worst case | 0.05 (50%) | 0.10 (100%) |

`HairlineDevicePixelSnapTests` holds both halves: the arithmetic of the pin,
and the end-to-end profile through the CPU rasterizer.

#### What is *not* pinned

- **App geometry.** A `Rectangle().frame(height: 1)` an app authored is
  content, not a stack hairline, and keeps the geometry it asked for.
- **Border and focus rings.** Measured and still inconsistent: a 1pt
  `.border` at 150% draws its top edge at 1.0 device px where 1.5 is called
  for and its bottom at 1.5, and at 100% with a half-point offset both edges
  draw at 0.5. The mechanism is the same one above, but a ring is a rounded
  rect with an inset fill, so pinning it means pinning the outer rect *and*
  the border width in device space, which moves the outer edge of every card,
  button and field in the app by up to a device pixel. That is a larger
  change than this one and is not attempted here.
