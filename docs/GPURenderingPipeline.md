# GPU Rendering Pipeline

How a `WinSwiftUI` view tree becomes pixels on screen. Each numbered
section corresponds to a step in the runtime; the bracketed test names
are the machine-checkable invariants protecting that step.

```
WinSwiftUI View tree
        ↓ ViewBuildContext / makeComponent
ComponentHost
        ↓ ViewNode (RetainedViewRuntime)
        ↓ layoutSubtree / paintNode
GPUIScene  (paintOperations, glyphs, quads, paths, shadows, images)
        ↓
   ┌────────────┴────────────┐
   ↓                         ↓
D3D11BatchRenderer    Frame renderer fallback
   ↓                         ↓
ID3D11Texture2D /         BitmapSurface
ID3D11ShaderResourceView   ↓
   ↓                  GPUIRawSceneRasterizer (CPU)
swap-chain present        ↓
                       BitBlt to HWND
```

## 1. View tree → ViewNode

The SwiftUI-shape view declared by app code goes through
`makeComponent(context:)` and a `ComponentHost`, producing a retained
`ViewNode` tree in `Sources/SwiftWindowsUI/Runtime.swift`. The runtime
maintains layout, focus, hit testing, animation, and scroll state. All
public Apple SwiftUI view types are mapped to ViewNode primitives —
`ViewTaxonomyParityTests` covers `Toggle`, `Button`, `TextField`,
`Slider`, `Stepper`, `Picker`, `ProgressView`, `Menu`,
`DisclosureGroup`, `GroupBox`, `Divider`, and `Spacer`.

**Invariants**
- A SwiftUI-shape view tree always emits the expected primitive
  families (`CrossViewRenderingParityTests`).
- Deeply nested hierarchies (20+ levels) survive without layout
  collapse (`testDeeplyNestedHierarchyStillEmitsLeafText`).
- Determinism across re-renders is required
  (`testParitySceneIsDeterministicAcrossRepeatedSnapshots`).

## 1a. Runtime frame contract: animation gating, dirty flags, geometry

Three properties of `RetainedViewRuntime` are load-bearing for anything
above it, and each was a silent-failure class before it was pinned.

**Animation gating.** The host drives frames from
`runtime.hasActiveAnimations || runtime.isDirty || …`, so that property
has to report *every* mechanism that needs a tick: the runtime-level
ones (colour tweens, button repeat, scroll momentum, keyboard-scroll
tweens), the per-node `animationStates` written by `.animation()`,
insertion transitions, button presses and matched geometry, **and** the
`transitionOverlays` a removal transition creates. Per-node state is
tracked by a weak registry maintained from `ViewNode.animationStates`'
`didSet` (weak so a node dropped mid-animation cannot pin the driver on
for the session; stale slots are swept in `tickAnimations`). Omitting
overlays and `animationStates` froze every removal transition
permanently — the overlay was painted once at its start value, the frame
that painted it cleared the dirty flags, and nothing ever ticked again.

**Dirty-flag integrity.** A render pass runs app code inside its own
traversal (`onLayout` during layout; `onAppear`, `onSizeChange` and
`canvasDraw` during paint) and ends by clearing `dirtyFlags`. Passes are
therefore bracketed by `beginRenderPass()` / `endRenderPass()`:
invalidations raised while a pass is open are staged and applied after
the clear, and the raising node's subtree flags are re-applied too — the
ancestors' flags are erased again as `markSubtreeRendered` unwinds, which
would otherwise let the next pass replay a stale range. The bracket is a
`defer`, and `beginRenderPass()` returns whether *this* call opened the
pass: an app closure re-entering `renderFrame`/`renderScene` is a no-op
on both ends, because a nested pass that reset the staging and closed the
pass on its way out left the rest of the outer pass invalidating straight
into `dirtyFlags`, which the outer pass then wiped — a permanently clean
runtime the host stops requesting frames for. Nested passes are counted
in `RetainedViewRuntime.reentrantRenderPassCount` and reported once on
stderr.

**Geometry sanitation and boundedness.** `layoutSubtree` clamps
`resolvedFrame` and `resolvedContentSize` to finite, non-negative values
and composes `resolvedScrollOffset` from one `effectiveScrollOffset`
property at both exits (the full-relayout exit used to drop the
rubber-band and keyboard-tween deltas). `clampedScrollOffset` maps
non-finite input to 0 — `max(NaN, 0)` is NaN in Swift, and a NaN offset
poisons every descendant origin so that every clip intersection comes
back empty and the window paints blank with nothing logged. Layout,
measure, prepaint, the frame-path command walk, the cache-range shifts
and the animation tick share one depth counter capped at
`ViewNode.maximumTraversalDepth` (256); past it a subtree is skipped with a
one-shot diagnostic instead of overflowing the main thread's stack
(an access violation, which no fallback policy can absorb).

**The cap is a stack guarantee, not just a backstop.** It did not used to
be. Layout, prepaint and the frame-path command walk were recursions with
unoptimized frames of 12 KB, 15 KB and 24 KB, so the real ceiling against a
1 MB stack was about 43 levels — one above the deepest demo screen, and an
eighth of the cap; a 20-level SwiftUI hierarchy (every modifier adds a
wrapper node) killed the test process outright. All three are now explicit
worklists in the shape `ScenePainter.paintNode` already used: `.enter` does
what a node can do before its children, `.finish` what it can only do after
them, and depth costs an array element instead of a stack frame. The
worklists publish their depth on the shared counter
(`ViewNode.enterTraversal(atDepth:)`), so nesting is still accounted across
the boundary into the recursions that remain. Measurement is still a
recursion — it returns a value up the tree — and is held to about a
kilobyte a level by deciding what to measure and folding the result back
out of line; 256 levels of it is about a quarter of the stack in debug.
The demo's deepest screen reaches 42.

**Tests:** `RuntimeAnimationGatingTests`, `RuntimeDirtyFlagIntegrityTests`,
`RuntimeRenderPassReentrancyTests`, `RuntimeGeometrySanitationTests`,
`TraversalStackHeadroomTests` (renders a tree at the cap and one past it).

## 2. ViewNode → GPUIScene

`ScenePainter.paint(root:…)` walks the retained tree and produces a
`GPUIScene`. The scene's per-layer payload is split into typed primitive
families:
- `quads` — filled rectangles, gradient fills, borders, shadows-as-quads.
- `glyphs` — DirectWrite-rasterized character bitmaps (with a UV into
  the native glyph atlas).
- `pixelGlyphs` — fallback bitmap-font glyphs (only used when DirectWrite
  fails for a given character).
- `shadows` — soft-shadow blur passes.
- `images` — image draws bound by integer texture ID.
- `paths` — Canvas / Path primitives (currently CPU-rasterized; see §4).

The painter writes its primitives into the `paintOperations` array in
**presentation order**. Both backends read that array through one
iterator, `GPUIScene.presentationOrder()`, which spells the cross-layer
rule out:

> **Layers are z-order groups.** Every primitive in `layers[i]` presents
> before every primitive in `layers[i+1]`, and within a layer
> `paintOperations` is the order. A run whose range falls outside its
> family array (what `GPUIScene.validate()` flags) is skipped by the
> iterator, so the CPU rasterizer loses that run instead of trapping and
> `D3D11BatchRenderer.makeRenderPlan` refuses the scene outright.

`D3D11BatchRenderer.makeRenderPlan` turns each run into a `RenderStep`;
`GPUIRawSceneRasterizer` draws each run in place. The two therefore emit
the identical `(layer, family, index)` sequence for any scene
(`ScenePresentationOrderTests`).

This used to be three orderings. The CPU rasterizer preferred a second
walk over the flat `paintRecords` log — global insertion order, with
`layerIndex` discarded — so an interleaved multi-layer scene drew in a
different z-order on each backend; and because every screenshot, gallery
baseline and macOS-parity render comes through the CPU rasterizer, no
visual gate could observe the shipping order at all. A third ordering (a
bounds tree assigning a Zed-style draw `order` per primitive, plus a
per-family sort in `finish()`) was computed for every primitive of every
frame at roughly a dozen heap allocations each, and its only consumer,
`orderedBatches()`, was never called outside tests. Choosing
`paintOperations` retired the other two: `GPUIBoundsTree`,
`GPUIPrimitiveOrdering` and the family sort are gone, `finish()` now only
re-coalesces paint operations, and `paintRecords` is a reference log of
`(layerIndex, kind, index)` rather than a second copy of every primitive.

**Invariants**
- `paintOperations`, read through `presentationOrder()`, is the single
  source of presentation order; no family-level sort may bypass it, and
  family arrays are never reordered after insertion (which is what makes
  a paint record's index a stable reference).
- Sealing and planning a scene is O(runs), not O(primitives). A
  single-family scene collapses to one run and one render step however
  many primitives it holds, and `finish()` + `makeRenderPlan` together
  stay under an eighth of what inserting the same primitives cost —
  measured at 0.1–0.3 %, where injecting a *single* heap allocation per
  primitive into the sealed phase reaches 20–27 %
  (`testSealingAndPlanningIsNotPerPrimitiveWork`).
- Glyphs at body-text font sizes never fall back to PixelText
  (`ViewTaxonomyParityTests`, `CrossViewRenderingParityTests`,
  `DynamicListStressTests`).
- A scene that uses native glyphs always carries the corresponding
  glyph atlas snapshot (`testParitySceneEmitsNativeGlyphAtlas`).
- Every primitive in a scene carries finite, in-range field values
  (§2a).

## 2a. Scene-contract value sanitation

`Int(_: Float)` is a Swift **trap** — a process kill, not a thrown
error — on NaN, on ±infinity and on out-of-`Int`-range magnitudes. Those
conversions sit on the hottest paths in both backends
(`splitQuadRangeForBackdropBlur` evaluates one per quad per scene before
any culling), and non-finite values reach the scene from ordinary app
code: `.blur(radius: a / b)` with `b == 0`, a frame that collapses to
NaN during layout, an animation interpolating through infinity. A trap
is the one failure class the fallback chain in §5 **cannot** degrade, so
the contract rejects it at the boundary instead.

`GPUIScene.add*` runs every primitive through `GPUISceneSanitizer`
before it reaches a family array or `paintRecords`, so both backends and
every replay inherit the guarantee:

- Non-finite position, size or offset ⇒ the primitive is **dropped**
  (there is nowhere to put it).
- A non-finite clip extent ⇒ **dropped**. Treating an unknowable clip as
  "unclipped" would paint the subtree across the whole window.
- Every other field is **clamped**: coordinates and radii to
  `GPUISceneLimits.maxCoordinate` — including `clipCornerRadius`, which is
  part of the clip but not part of the "drop it" test, in every family
  rather than only in quads: both backends feed it into a signed-distance
  term where NaN erases the primitive and a negative inverts the arc —
  colours and opacity to `[0, 1]`,
  atlas/image UVs to `maxTextureCoordinate`, `effectType` to `[0, 8]`,
  `blendMode` to `[0, 4]`, backdrop `blurRadius` to `maxBlurRadius`
  (256 device pixels, shared by both backends so they agree above the cap
  instead of each truncating somewhere else — the D3D11 blur engine sizes
  its weight cbuffer to exactly this radius, and `D3D11BackdropBlurTests`
  pins the two together), shadow `blurRadius` to `maxShadowBlurRadius`.

`GPUISceneLimits` holds **shared engine limits, not backend
capabilities**: each number bounds what this engine promises to draw at
all, on every backend, so a scene renders the same everywhere rather than
being truncated differently by each consumer. Where a value coincides with
a D3D11 maximum, that is a floor the engine chose to live inside, not a
capability read off a device — `maxBlurRadius` is 256 because the painter
emits `radius × displayScale` and 128 silently sharpened
`.blur(radius: 100)` on any HiDPI display, not because D3D11 said so.
Asking the device what it can actually do is a backend capability record
(WS-20); until it lands, a backend that can do less than the shared limit
is a divergence, not a configuration.
- `PathPrimitive` additionally caps its element count
  (`maxPathElements`) and clamps element coordinates, arc radii and
  angles.

Sanitation is an *identity transform* for well-formed primitives —
finite in-range values are returned bit-identical — so no accepted scene
changes shape (`testWellFormedQuadIsStoredByteIdentically`).

Structural bounds live alongside it:

- `ensureLayer` returns `false` without allocating for a negative index
  or one at/above `GPUISceneLimits.maxLayers`; it used to grow the array
  to whatever index it was handed.
- `GPUIScene.layers` and `paintRecords` are `public private(set)`, like
  the family arrays inside `GPUILayer`: `add*` is the one door sanitation,
  the family arrays and `paintRecords` all agree behind, and a
  `scene.layers[0] = GPUILayer(...)` skipped it entirely while leaving
  `paintRecords` describing primitives that were no longer there. The
  deliberate escape hatch is named — `installHandBuiltLayers(_:)` /
  `installHandBuiltLayer(_:at:)` — because building a malformed scene is
  what proves `validate()` works, and nothing else should want it. Both
  installers drop `paintRecords`: the log is a list of *references* into
  the family arrays, so records kept across a layer swap stay in bounds
  while naming primitives that are no longer the ones they described —
  the same in-bounds-but-wrong replay the stale-range check closes on the
  painter's side, and `.invalidRange` never fires on it. A hand-built
  layer set has no valid log, and an empty log replays as `.invalidRange`
  rather than as a wrong picture. Installing at an index that addresses no
  layer changes nothing at all, log included.
  (`ScenePresentationOrderTests.testInstallingHandBuiltLayersDropsTheStaleReplayLog`,
  `…OneHandBuiltLayerDropsTheLogOnlyWhenItReplacesSomething`.)
- `GPUIScene.validate() -> [SceneDefect]` checks what a hand-built layer
  can still break — layer count, every
  paint operation's range against its family array, and glyph-atlas
  buffer size. `D3D11BatchRenderer.makeRenderPlan` calls it
  unconditionally (it is O(layers + paint operations) and allocates
  nothing on a clean scene) and throws a `.sceneContent`
  `BatchRendererError` rather than trapping on a malformed layer.
- `GlyphAtlasSnapshot.uploadDecision(for:)` is what consumers upload
  from (see §3.2): regions are producer-supplied, and a negative origin
  traps at `UINT(_:)` while an over-hanging region reads past the end of
  `pixels`, so the decision clamps first. A region that clamps to nothing
  degrades to the always-in-bounds full-atlas upload.

Downstream of the contract, every remaining `Float → Int` conversion
uses `GPUISceneValue.int`, which saturates instead of trapping
(`splitQuadRangeForBackdropBlur`, `D3D11BackdropBlurEngine.blurRegion`
— which converts *before* clamping — the CPU rasterizer's blur radius,
blend-mode selector, glyph and image UVs, and the path scanline spans).
Curve flattening is depth-capped and the arc angle-normalisation loop is
turn-capped, so termination is a property of the algorithm rather than
of its callers.

**Tests:** `SceneValueSanitationTests`, `SceneStructuralValidationTests`,
`MalformedInputResilienceTests`.

## 2b. Painter device space, cull footprint, compositing groups

The painter is where logical points become device pixels. Everything it
hands a backend is already multiplied by `displayScale`:

- Quads, glyphs, images and shadows go through `scaleRect(_:by:)` at the
  point of emission.
- **Paths go through `PathPrimitive.scaled(by:)` inside
  `ScenePainter.emit`** — the single lowering point for path geometry, so
  elements, `bounds`, `clipBounds` and `lineWidth` are all converted
  exactly once, *before* tessellation, and the promoted quads and the
  residual CPU path land in the same space. Paths were the one family
  that used to reach the backends unscaled, so on a 150 % display every
  `Shape` background, `Canvas` drawing and vector `SymbolIcon` rendered at
  `1/1.5` size anchored toward the window origin while its container
  rendered correctly.

**Culling** is per node, against the inherited clip, using the footprint
the node's decoration actually reaches:
`paintFrame ∪ shadowRect ∪ outlineRect`. Culling on `paintFrame` alone
dropped the shadow of a card scrolled one pixel past a clip edge, which
read as shadows popping at every scroll boundary.

**Zero-extent nodes** follow macOS SwiftUI: a frame boundary does not
clip, so a container collapsed to `0 × 0` still paints its overflowing
children (`.clipped()` is what hides them) while painting none of its
*own* decoration — an outset shadow or outline around a zero-extent
frame would otherwise draw a small square where the app asked for
nothing. They are still culled: `clipAllowsSubtreeTraversal` (the one
predicate both paint traversals use) treats a degenerate footprint as
touching rather than empty, so it prunes only when the footprint is
strictly outside the clip, and prunes everything under an empty clip.
`Rect.intersected` reports "no overlap" for every degenerate rect
wherever it sits, so the primitive test cannot be reused here — and
skipping the cull for zero-extent nodes leaves a collapsed row parked
off-screen traversing its whole subtree every frame. The frame path
(`ViewNode.appendCommands`) uses the same predicate and the same
own-decoration rule, so both paths paint the same tree. Both also cull and
clip against `paintFrame` — the transformed footprint they actually draw at.
The frame path used to clip the *untransformed* `absoluteFrame` while drawing
the transformed one, so a rotated `.clipped()` container chopped its content
diagonally there and bled past the visible edge on the scene path: two
different regions for one tree, swapped silently whenever the host fell back
to the frame renderer. Hit testing is
deliberately *not* included: prepaint still prunes a zero-extent
subtree, so overflow content renders without becoming newly clickable.

**Transform lowering.** A node's transform reaches the scene as two
values, not one. `PaintPlacement.lowering(_:through:)` splits the
accumulated screen-space transform into an axis-aligned rect and an
angle:

- `frame` — the node's rect with translation and uniform scale applied
  and the rotation factored out. This is what the quad families carry,
  together with `QuadPrimitive.rotationRadians`, so a card rotated 45°
  paints as a rotated card rather than the unrotated box `√2` too large
  that `Rect.applying(transform:)` returns.
- `boundingBox` — the axis-aligned footprint of the rotated rect. Every
  *predicate* uses it: culling, the clip rejection rect, the cache key's
  `bounds`. It is an acceptance bound, not a shape.
- `scale` — the similarity's uniform scale factor, `1` whenever the
  transform is not a similarity. Only one kind of content needs it: a
  text run, which is *laid out* rather than placed (see below). Everything
  else the painter emits is already expressed in the transformed rect, so
  re-applying `scale` to it would square the scale.

**Every family turns.** WS-19 lowered the angle for quad decoration only;
R-ROT closed the rest, and all four GPU families now carry a
`rotationRadians` in a slot that used to be padding (so every stride is
unchanged and `GPUIPrimitiveLayoutCoherenceTests` still pins 144 / 80 / 64 /
80 bytes):

| family | field offset | what turns |
| --- | --- | --- |
| `QuadPrimitive` | 112 | the rect, about its centre; interior maths stays in unrotated local space |
| `ShadowPrimitive` | 68 | the soft envelope, about the **offset** rect's centre — the rect it draws |
| `GlyphPrimitive` | 68 | the atlas cell, about its centre; UVs ride the turned vertices |
| `ImagePrimitive` | 60 | the destination rect, about its centre — how an offscreen pass composites back turned |

Both backends implement each one the same way, and it is the same way in
all four: the **vertex stage** turns the corners about the centre and the
**pixel stage** keeps working in unrotated local coordinates, so corner
radii, gradients, colour effects and texture sampling are untouched by the
angle. The CPU rasterizer mirrors it through one shared helper,
`RasterTarget.rotatedScan`, which scans the turned rect's bounding box and
inverse-maps each pixel centre back into local space. `rotationRadians == 0`
short-circuits on every path, so axis-aligned scenes stay byte-identical —
the 25 gallery baselines did not move when R-ROT landed.

**Paths turn their elements.** `PathPrimitive` has no `rotationRadians`
and will not get one: paths never cross the GPU as typed primitives (both
backends rasterize them), so there is no shader to hand an angle to. The
honest lowering is `PathPrimitive.rotated(by:about:)`, applied once in
`ScenePainter.emit` — the single lowering point for path geometry — which
turns every element (an arc's centre moves and both its endpoint angles
shift by the angle; the radius and sweep direction are rotation-invariant)
and widens `bounds` to the turned footprint. The raster then simply covers
the turned geometry, and the path-texture caches re-key by construction
because `shapeHash` digests the element stream. `clipBounds` is
deliberately *not* turned: the scene contract's clip is an axis-aligned
screen-space rect for every family.

**Text is laid out before it is placed.** A run inside a transformed subtree
is shaped and laid out in the node's own **untransformed** paint space —
`PaintPlacement.runLayoutRect(_:)`, the painted rect pulled back through the
node's scale about its centre — and the finished cells are then scaled and
turned by `PaintPlacement.placingRun(_:displayScale:)`. Line breaking is a
function of the width a run is measured against, and both halves of the
placement used to leak into that width:

- a **rotation** made the run break to the bounding box's width, so a turned
  card's label wrapped differently (and stayed horizontal) inside it;
- a **scale** made the run break to the *transformed* width at an
  untransformed font size, so `scaleEffect(2)` re-broke the string into
  half as many lines of twice the characters, and a control pressed to 0.97
  re-fitted its own title into a box 3% narrower and ellipsized it.
  Segmented-control titles were given centring headroom to survive that;
  every other control label was one tight string away from the same.

SwiftUI does neither: a transform scales a rendered run, it does not reflow
one. `ScaledTextLayoutTests` pins the statement from both ends — a scaled-down
label has the identical breaks of its unscaled self, a 2x label has the
identical breaks of its 1x self with twice the cell geometry, and a
rotated-and-scaled label is the scaled one with every cell turned about the
node's centre.

The press half of that example is historical twice over: E6-PRESS took the
0.97 shrink off macOS-parity controls (a macOS control answers a press with
its fill, not with geometry — see docs/AnimationParity.md), so the smallest
scale a control label routinely meets is now whatever the app asks for with
`scaleEffect`. The layout rule is the same either way, and the tests still
drive it at 0.97 because a 3% squeeze is the sharpest case of it.

Laying out first makes the pre-placement cull a hazard: comparing an
unplaced glyph cell against the placed screen clip drops glyphs the
placement would have brought inside it. `appendTextGlyphs` therefore takes a
separate `cullClip`, which callers set to
`PaintPlacement.unplacedRunFootprint(of:)` — the clip pulled back into the
layout space, widened to a box. The map is a similarity, so that box is a
superset: it can keep a glyph the clip then rejects per pixel, never drop
one it would have shown. `Canvas` gets the same treatment through a paired
clip stack (`currentClip` in screen space, `currentCullClip` in the
canvas's drawing space), which is why `check-contracts.ps1` exempts both
names from the bare-`Rect.intersected` rule.

**A scaled run rasterizes at its own size, on a rung.** Laying out in local
space leaves one question: what pixel size the glyphs are rasterized at.
Drawing a 2x run from the 1x atlas entries would be a 100% bilinear
stretch — the whole reason to keep a glyph atlas is to avoid that — but
rasterizing at exactly the effective device size means a new set of atlas
entries per *frame* of any scale animation. `NativeGlyphAtlas.glyphRasterScale(for:)`
quantizes the scale onto the powers of `2^(1/8)` and the painter rasterizes
there, dividing the raster's pixel metrics by the rung so `placingRun` can
multiply by the true scale. Three consequences, which are the justification:

- neighbouring rungs are 9% apart, so nothing is ever resampled by more than
  ±4.4% in linear size — a bilinear stretch of a *full-detail* raster;
- `0.97` is inside that band, so the entire pressed-control case rasterizes
  on the rung it already occupies and costs no atlas entries at all;
- `1`, `2`, `4` and the rest of the powers of two are rungs *exactly*, so
  authored scales are crisp rather than merely close.

Clamped to `[1/8, 8]`; past that the resample is the lesser evil against a
400px glyph in a 2048² atlas.

**Residual: shears, mirrors and non-uniform scales still re-flow.** They are
not separable (below), so `scale` is `1` and the run is laid out in the
bounding box, exactly as everything did before. **Residual: `Canvas` text.**
A canvas closure is handed the *placed* size and draws in that space, so
there is no untransformed box to lay out in; canvas runs keep the placed
rect and `rotating`. Moving them would change what the closure is handed,
which is a `Canvas` semantics question rather than a text one. **Residual:
the frame path.** `ViewNode.appendCommands` has no placement at all and lays
its text out in the transformed rect; it is the CPU fallback, and it already
cannot follow the rotation either.

Only a **similarity** is separable — a rotation composed with a uniform
scale, no reflection, no shear. In matrix terms (row-vector convention,
the one `Point.applying` uses) that is `a == d` and `b == -c`. Shears,
mirrors and non-uniform scales fall back to the bounding box, which is
what the painter did for everything before this existed; `rotation` is
then exactly `0` and the emitted bytes are unchanged.

**A mirror is a mirror all the way to that fallback.** `Transform2D` is
stored decomposed and every composition (`concatenating`, `inverse`, and
the centred transform above) goes out to the matrix and back through
`init(fromMatrix:)`, so whatever that read-back cannot express is
rewritten the first time a transform composes. It used to take
non-negative scales, which cannot carry a negative determinant: a
reflection came back as a **half turn**, which *is* separable, so
`.scaleEffect(x: -1)` painted upside down and backwards and the pointer
followed it there. The decomposition now carries the reflection as a
negative scale — on `scaleX` or `scaleY`, whichever reading is the
smaller rotation, so a horizontal mirror is `scaleX: -1` with no
rotation — and is an exact round trip for every non-singular matrix
(shears included; the second row's *norm* used to be read as `scaleY`,
which grew a shear by `sec(skewX)` per composition). The residual is
narrower and honest: a mirrored subtree's **placement** mirrors — its
own box, its descendants' boxes, and the pointer inverse — while its
**content** does not, because the scene contract carries an angle per
primitive and no reflection. `TransformReflectionTests` pins both
halves.

`QuadPrimitive.contentMaskedBounds` is rotation-aware for the same
reason: a rotated quad's footprint is the box of the *turned* rect, and
comparing the unturned one against the clip dropped diagonal stroke
segments and rotated decoration whose bodies were inside the clip all
along.

**Transform composition order.** `Transform2D.concatenating` is
self-first: `a.concatenating(b)` maps a point through `a` and then
through `b`. A node's own transform is built around its **screen-space**
centre (`T(-c) · M · T(c)`), so it is a screen-space operator and
composes *after* the map that produced that screen space:

```swift
effectiveTransform = inheritedTransform.concatenating(centeredTransform)
```

The painter, prepaint (`appendPrepaintState`), the frame path
(`accumulatedPaintGeometry`) and the compositing-group sub-scene all
compose in that order, and the pointer inverse composes in the opposite
one (`(A·B)⁻¹ = B⁻¹·A⁻¹`) so what is visible is what is clickable. The
older order applied node-before-ancestors, which left a node's own frame
and the frames its descendants inherited in two different spaces: a
`.scaleEffect(2)` child of a `.offset(100, 0)` ancestor moved 100 points
and its grandchildren 200. `TransformLoweringTests` pins absolute
placements computed by hand from the tree — agreement between the two
paint paths is necessary but not sufficient, because both were wrong
together.

**Borders** are emitted exactly once. A node with children draws its
border as a ring of edge/arc segments *after* its children (so child
content cannot cover it); a leaf draws the historic full-rect fill under
its inset background. Doing both — which is what containers used to do —
blended a translucent border twice, so
`.border(Color.white.opacity(0.10))` composited at 0.19 on a container
and 0.10 on a leaf. The ring is the whole border: a bordered container
with a transparent or translucent background keeps its interior free of
border colour, where the pre-children fill used to tint it.

A **rounded** ring walks its corners as annular sectors, subdivided into
axis-aligned bounding boxes (`QuadPrimitive` has no arcs). Each box's
extent per axis is the interval product of `[innerR, r]` with the two
direction cosines of the sub-arc — every sub-arc stays inside one
quadrant, where `cos`/`sin` are monotonic, so that box is exact. It has
to be computed that way because *which* side of the arc centre carries
the ring's outer edge flips per quadrant: pinning it to `+x`/`-y` (true
only for the top-right corner) made the other three corners' boxes
narrower than the ring by exactly the border width and inverted the
sub-boxes next to the straight edges, which were then dropped — three
corners out of four rendered thin or gapped. Every corner's arc boxes
now union to the full `radius × radius` corner square.

**Compositing groups** (`.drawingGroup()`, `.compositingGroup()`)
rasterize their children into an offscreen `BitmapSurface` and composite
it as one `ImagePrimitive`. `offscreenPassBuffer` — shared with the
content-blur isolation pass — decides whether that is possible at all:

- the group's frame is **clamped to the effective clip** before sizing —
  pixels outside it could not survive the clip anyway, and sizing from the
  raw frame made `.drawingGroup()` on tall scroll content a
  hundreds-of-MB allocation every frame;
- the frame is checked for finiteness and the buffer for an area budget
  (`maxCompositingGroupPixels`), with saturating conversions throughout —
  `Int(_: Double)` on an infinite frame is a process kill, not a glitch;
- when the buffer cannot be sized, the group **falls back to inline
  painting** rather than dropping its children.

The sub-scene carries the glyph atlases. `RasterTarget.drawGlyph` returns
immediately on a nil atlas, so without them every piece of text inside a
`drawingGroup` silently disappeared. The sub-scene reads the atlas via
`NativeGlyphAtlas.currentSnapshot()`, which deliberately does **not** mark
the atlas clean: a frame has many readers but exactly one consumer of the
dirty region (the outer scene, at the end of `paint`), and consuming it
mid-traversal would hand the GPU backend an empty dirty region for glyphs
it still had to upload.

The bitmap is **cached on the node**, under the same condition the paint
record replay uses: the node's `ViewPaintCacheKey` is unchanged and its
subtree is clean (the key covers the group itself, `subtreeDirtyFlags`
covers its descendants). Rasterizing a group walks and CPU-rasterizes its
whole subtree on the main actor, so an uncached group is the most
expensive node in the frame, every frame it is painted. A cached bitmap
whose sub-scene drew native glyphs also records the atlas generation it
was baked against, so the repaint an atlas recycle triggers re-rasterizes
instead of reusing pixels baked across the recycle. The runtime's
`cachedScene` records the same token for the same reason: the atlas is
process-wide and a clean window never repaints, so a recovery triggered by
*another* window would otherwise leave that window shipping pre-recovery UVs
against the recovered atlas forever. A mismatch drops the cached scene — and
with it the replay source, whose primitives carry the same dead UVs — and
forces a real paint (`GlyphAtlasExhaustionSafetyTests`).
`ScenePaintMetrics.compositingGroupsRasterized` /
`compositingGroupsReused` report which happened; the bitmap is released
as soon as the node paints inline again.

`isInsideDrawingGroup` and `skipCacheUpdates` are **inherited by the whole
subtree**, not just by the group's direct children. Resetting them at each
child boundary — which the traversal did — let every grandchild inside a
group write a `cachedScenePaintRange` measured against the group's
sub-scene, a scene discarded as soon as it is rasterized. Replaying such a
range against the real `previousScene` reads unrelated primitives, or runs
past the end of the record log; `GPUIScene.replay` now bounds-checks the
range and returns `.invalidRange` rather than trapping, and `ScenePainter`
answers any rejection by dropping the cache entry and repainting the
subtree (counted in `ScenePainter.rejectedReplayCount`, reported once on
stderr). Discarding the replay result with `_ =`, which is what both call
sites did, turned a rejection into a permanently blank subtree: the empty
range was written straight back into the cache.

Inheriting `skipCacheUpdates` stops the *write*; entering a group also
**clears** `cachedSceneKey` / `cachedScenePaintRange` on every node it
walks. Skipping the write alone left a descendant holding the range it had
from before the group was applied — measured against a real earlier scene,
so still in bounds of the next one and still keyed the same. Removing the
group then replayed whichever primitives had since moved into those
indices (the group's own composited image, in the test case);
`.invalidRange` never fires, because the range is perfectly valid. The
frame a group appears on walks its whole subtree, so clearing on entry
covers both directions of the toggle.

**Tests:** `PainterDeviceSpaceTests`, `PainterZeroExtentSemanticsTests`,
`PainterBorderRingCoverageTests`, `BorderCornerArcGeometryTests`,
`CompositingGroupBitmapCacheTests`, `ScenePainterTests`,
`TransformLoweringTests`, `PathTessellationBudgetTests`.

## 3. Text: DirectWrite + native glyph atlas

Text rendering is the most complex part of the pipeline.

1. `WindowTextSystem` calls into DirectWrite via
   `DirectWriteTextRenderer` to lay out the line.
2. Per-glyph atlas pages are rasterized through DirectWrite's bitmap
   render target and stored in `NativeGlyphAtlas.shared`.
3. The painter walks each glyph in the line, looks up its atlas entry,
   and emits a `GlyphPrimitive` with UVs into the atlas.
4. `NativeGlyphAtlas.snapshotIfUsedInCurrentFrame()` attaches the atlas
   to the scene, carrying its content version and what changed since the
   previous snapshot (§3.2).
5. The painter forces leading text alignment when laying out a *single
   line* through DirectWrite, so glyph origins return relative to the
   line's natural start. The actual horizontal alignment of the line
   is applied later by the painter's own `startX` calculation.

The "force leading alignment" rule is critical: DirectWrite sized the
layout box at 4096 px wide. Letting it center inside that box produces
glyph origins around `x ≈ 2000`, which then failed the painter's
visible-clip preflight check and silently fell back to PixelText.

### 3.1 Shaping, and the two glyph coordinate frames

Step 1 resolves a line into glyphs two ways, and which one runs decides
whether the text is *shaped*:

- `captureGlyphLayouts` draws the layout through an `IDWriteTextRenderer`
  and receives real `DWRITE_GLYPH_RUN`s: glyph IDs, shaped advances,
  per-glyph offsets and a cluster map. Ligatures are one glyph, complex
  scripts get their contextual forms, and each glyph carries the
  `IDWriteFontFace` it came from.
- `fallbackGlyphLayouts` walks `Array(text)` and hit-tests each character
  position. It produces one glyph per character with no glyph ID and no
  face, so every glyph is later re-laid-out in isolation.

Shaping is primary. `NativeTextRenderer.isGlyphShapingEnabled` (default
`true`) is the escape hatch: turning it off reverts the whole pipeline to
the hit-test walk, which stays live anyway because a capture that comes
back empty falls through to it.

The capture renderer is a COM object DirectWrite calls *back* into, and
before it reports a run's baseline it asks that object two questions:
`IsPixelSnappingDisabled` and `GetPixelsPerDip`. The capture answers
"disabled" and "1" — it is reading the layout's own DIP coordinates and
never draws, and `ScenePainter` snaps glyph destinations to device pixels
itself. Both renderers this file installs receive their client context as
one untyped `void *` from `IDWriteTextLayout.Draw`, and they pass two
different structs through it, so every context now carries a tag in its
first word (`DirectWriteClientContextTag`) and an accessor that refuses a
foreign one. That is not hypothetical tidiness: the two renderers used to
share `GetPixelsPerDip`, which read `pixelsPerDip` at offset 16 of the
8-byte capture context and handed DirectWrite whatever followed it in
memory. DirectWrite snaps the baseline origin against that number, so on
an unlucky process every shaped line reported `baselineOriginY == 0` — a
whole ascent too high, with most of the line then culled above the
surface. The value was stable inside a process and different in the next
one, which is what an intermittent, order-sensitive text test looks like.
`TextShapingPipelineTests` pins both halves: the snapping contract at the
seam, and the user-visible invariant that a shaped glyph's `origin.y` is
the line's baseline rather than its top.

Enabling shaping exposed a hazard the old ordering had been hiding: the
two rasterizers measure ink from different origins.

| producer | `origin.y` / `bearingY` measured from |
|---|---|
| `captureGlyphLayouts` + `rasterizeCapturedGlyph` | the text **baseline** |
| `fallbackGlyphLayouts` + `rasterizeGlyph(Character:)` | the **layout-box top** |

Each pair is self-consistent, but a shaped glyph whose raster falls back
to the character path mixes them and lands one ascent low.
`GlyphVerticalFrame` makes the frame part of the value:
`NativeTextGlyphLayout.verticalFrame` says which origin `origin.y` is,
`NativeGlyphBitmap.verticalFrame` and `GlyphEntry.verticalFrame` say
which origin `bearingY` is, and the painter computes both anchors (line
top and baseline) and picks the one the *raster* reports. The cull
preflight spans both anchors, because which one applies is not known
until the raster exists.

`FontFaceRegistry` hands out monotonic `FontFaceID`s and retains each
`IDWriteFontFace`. `GlyphKey.fontFaceID` used to be the raw COM address,
which a later face allocated at the same address would inherit — an
alias that only became reachable once shaping started producing
face-keyed entries. Retention is for the process lifetime, on the
assumption that DirectWrite returns the same face object for the same
face; nothing in its contract promises that, and shaping now runs per
glyph run. `registeredFaceCount` makes the set observable and
`reportThreshold` (256) makes the assumption falsifiable: crossing it
sets `hasExceededReportThreshold` and reports once to stderr. The
registry keeps working — a threshold is a report, not a policy — but an
unbounded retained set stops being silent.

### 3.2 The atlas and texture upload protocol

An atlas snapshot is a *versioned* value, not a bag of pixels with a
dirty rect. Three pieces, all in `AtlasUploadProtocol.swift`:

- `contentVersion: UInt64` on `GlyphAtlasSnapshot` — minted from
  `RenderContentVersion.next()`, a single process-wide monotonic source.
  Uniqueness across producers is the point: a consumer compares versions
  without knowing which atlas produced them, so per-instance counters
  would let two atlases alias each other's textures.
- `AtlasUpdate` — `unchanged`, `region(_, since:)` or `full`. The base
  version in `region` is part of the claim: the shared process atlas has
  one dirty region and N window consumers, so "the region since someone's
  last read" is only safe for the consumer whose texture is at exactly
  that version.
- `AtlasTextureState` — what a consumer's texture holds: `isInitialized`,
  `uploadedVersion`, `size`. `isInitialized` is tracked, never inferred
  from a matching size.

`GlyphAtlasSnapshot.uploadDecision(for:)` turns those into `skip`,
`region` or `full`, and `D3D11BatchRenderer.updateGlyphAtlasTexture`
does exactly what it says. Everything ambiguous falls to `full`: a fresh
texture, a resize, a region whose base version this texture never held, a
region that clamps to nothing.

This replaced an `Optional<GlyphAtlasRegion>` carrying three meanings at
once, which the producer and the D3D11 consumer read in opposite
directions. Two bugs lived in that one block: a zero-size "nothing
changed" region failed the consumer's `width > 0` guard and took the
**full** branch, so every frame containing text uploaded the whole
2048×2048×4 = 16 MiB atlas; and a texture created moments earlier was
judged initialized because its size matched, so a first frame with a
small dirty region uploaded only that rect into undefined texels — a
frame of garbage text whenever a second window opened against a warm
atlas, or after a device reset.

The pixel-font atlas is built once and never written, so its snapshot
reports the same version and `.unchanged` on every frame; it used to
declare itself fully dirty on each one.

**Which frames ship an atlas** is decided by the primitives in the scene
(`GPUIScene.usesGlyphs` / `usesPixelGlyphs`), not by what the painter
rasterized. A frame that replayed all of its text asks the atlas for
nothing, and a frame the runtime serves from `cachedScene` is not painted
at all; both used to ship `glyphAtlas == nil` while carrying glyph quads.
D3D11 covered for that by resolving `AtlasSource.cached` against the
texture it still held, so the defect was invisible on the GPU — but the
CPU rasterizer has no such texture, `RasterTarget.drawGlyph` returns on a
nil atlas, and *every* screenshot, gallery baseline and macOS parity
render comes through it. `ScenePainter.attachCachedGlyphAtlases` closes
it at both ends (the painter's own output, and the runtime's cached-scene
returns) via `NativeGlyphAtlas.snapshotForCachedGlyphs()`. It is nearly
free: the snapshot carries the atlas `Data` by reference and declares
`.unchanged` at the version the consumer already holds, so
`uploadDecision` answers `skip`. The runtime still stores `cachedScene`
*without* its atlases — that copy outlives the frame, and pinning the
buffer across frames turns the next glyph write into a copy of the whole
2048² atlas.

Image textures follow the same idea with a different key.
`BitmapSurface.contentToken` is minted when a buffer is created and
re-minted by the `didSet` on `pixels`, so any write — including
`replaceSubrange` and `withUnsafeMutableBytes` — produces a new
identity. `contentKey` (token + geometry + alpha mode) keys both
`GPUIScene.registerImageResource`'s dedupe (previously a `memcmp` of the
whole buffer against every image already registered) and the D3D11
image-texture cache. Texture IDs are positional within a frame's
registration order, so a scene that gains or loses one image renumbers
the rest; keying the GPU cache on content instead means renumbering
costs nothing and an unchanged image keeps its texture across frames.
That cache is bounded three ways. Two are budgets — 30 frames unused, and
a 96 MB byte budget, both evicting least-recently-used first. The third is
exact: at the top of every frame, after `bindResources(for:)` has applied
the frame's bindings, `collectUnreferencedImageTextures()` releases every
cached texture no binding refers to any more. Content-keying means
rebinding a texture ID to different pixels *orphans* the old entry rather
than replacing it, and an animating `.drawingGroup()` re-rasterizes its
bitmap — hence a fresh content token — on every frame, so without the
sweep one visible image accumulated a texture per frame until a budget
caught it. The sweep runs at the frame boundary rather than inside
`bindImageResource` precisely because texture IDs are positional: a scene
that renumbers is mid-rewrite during the binding loop, and releasing there
would drop the texture the next binding is about to ask for again
(`D3D11BatchRendererRenderTests` pins both halves).

**Tests:** `AtlasUploadProtocolTests` — the decision table, the
producers' versioning, and the real upload counts on WARP (frame 1
fresh = one full upload, frame 2 unchanged = zero, frame 3 with a small
region = one boxed upload, a region into a nil texture = full) plus
image texture/SRV pointer identity across rebinds and renumbering.

### 3.3 Atlas exhaustion: the generation token

The atlas is a shelf allocator, and recycling space *under the UVs the
current paint pass has already emitted* is the hazard. An atlas rect is
only meaningful within the generation that handed it out: after a recycle,
the same rect addresses a different glyph.

There are two ways space gets recycled, and both bump
`GlyphAtlas.generation`:

- **`clear()`** — every shelf at once, the last resort.
- **A reclaimed free span.** `GlyphAtlasCache.evictLRU` returns the evicted
  entry's rect to a per-shelf free list (`GlyphAtlas.deallocate`, with
  adjacent spans coalesced so two 8-wide frees satisfy one 16-wide glyph).
  `allocate` prefers *virgin* frontier space and only falls back to the free
  list, so the generation moves exactly when reclaimed space is handed out —
  never for an allocation that can alias nobody. Before the free list
  existed, eviction released nothing and a rolling working set larger than
  `maxEntries` marched the frontier to the edge of the atlas and then took
  the full `clear()`, dropping every cached glyph.

Freed pixels are deliberately left in place: nothing addresses them until
the space is handed out again, and the rewrite that *does* matter goes
through `writePixels`, which bumps `contentVersion` and unions the dirty
region like any other write — so § 3.2's upload protocol stays correct over
reclaimed space.

The two are not the same invalidation, which is why `clear()` also bumps
`GlyphAtlas.recycleGeneration` on its own. A recycle moves every shelf, so
every rect the atlas ever minted is wrong. Reusing one freed span
invalidates exactly that span — and the entry that owned it left the cache
when it was freed, so nothing *live* points at it. Only a stale holder can:
a replayed paint record carrying last frame's UVs forward, a cached scene
from an earlier frame, or — the one intra-pass case — a cell this pass
already drew from and then evicted, which `GlyphAtlasCache` reports as
`didFreeCellUsedThisFrame`.

`ScenePainter.paint` compares the generation across each paint attempt:

1. Attempt 0 paints normally. If the generation moved *and* any of those
   three stale holders is in play, every UV it emitted is suspect and the
   scene is thrown away. If none is — a reclaim that aliased only dead
   cells — the pass ships, and the *next* frame starts with replay
   disabled (`NativeGlyphAtlas.replayIsUnsafeThisFrame`) instead. That is
   what keeps a full atlas plus one new glyph per frame at one paint pass
   per frame rather than two, forever: collapsing the two invalidations
   into one token made every such frame pay a full repaint.
2. Attempt 1 repaints with scene replay bypassed, so cached text ranges
   rerasterize against the recovered atlas instead of replaying stale
   UVs.
3. Attempt 2 paints with the atlas *suspended*
   (`NativeGlyphAtlas.setSuspended`): it hands out nothing, so
   `appendNativeTextGlyphs` emits nothing, text falls through to the
   pixel-font path, and the pass cannot exhaust. A frame whose working
   set does not fit the atlas therefore degrades to bitmap text rather
   than shipping — and caching — quads that sample recycled cells.

Suspension is released at the end of the paint, so the degradation is
scoped to the one frame that could not be satisfied.

`NativeGlyphAtlas.beginFrame()` (the LRU clock) is ticked once per
rendered *frame*, outside the attempt loop: ticking it per attempt would
age glyphs the frame is still using.

**Invariants**
- Multiple consecutive renders all receive a non-`nil` glyph atlas
  snapshot, even when no new glyphs were rasterized.
- LRU eviction in the atlas cache always recovers — 200 distinct glyphs
  through a 32×32 atlas with a 32-entry cap drops zero inserts
  (`testSustainedExhaustionAlwaysRecoversAndNeverDropsInserts`).
- Every `GlyphPrimitive` in a returned scene resolves to the pixels of
  the glyph that requested it, and a working set larger than the atlas
  emits zero native glyphs rather than stale UVs
  (`GlyphAtlasExhaustionSafetyTests`). `NativeGlyphAtlas(atlasWidth:
  atlasHeight:maxEntries:)` + `installForTesting` inject a small atlas so
  this is reachable without a four-thousand-glyph working set.
- `nativeFontSize` flows from `Font.body`/`.system(size:)` into
  `PixelTextStyle` correctly across all built-in view types.

### 3.4 Text diagnostics

`ScenePaintMetrics.textDiagnostics` (`TextRenderDiagnostics`) counts what
degraded while painting: `pixelFontFallbacks` (strings pushed onto the
5×7 bitmap atlas, which uppercases and maps most codepoints to `?`),
`glyphRasterFailures`, `atlasRecoveries`, `shapedGlyphRuns` /
`unshapedGlyphRuns`, and `letterSpacingDroppedRasterizations`. The text
layer reports failure as `nil` from a dozen places with no scene in
scope, so `ScenePainter` brackets each attempt with
`TextRenderDiagnosticsCounters.beginPass()` and copies the snapshot onto
the scene it ships. Nothing branches on the counters — `isClean` is a
reporting convenience, not a gate.

### 3.5 Conversions, tracking and wrap cost

- Every `Double → Int32/UInt32` in the text layer goes through
  `roundedUpInt32` / `roundedUpUInt32`, which return `nil` on non-finite
  or out-of-range input instead of trapping. `framePathTextRasterSize`
  clamps both axes first: an unbounded frame extent contributes *no*
  floor (so `.frame(width: .infinity)` rasterizes at the measured width,
  not at the 4096 ceiling), and a non-finite draw *origin* makes
  `appendCommands` decline rather than invent a pixel.
- `PixelTextStyle.letterSpacing` is the 5×7 atlas's inter-glyph gap in
  atlas units — its default of 1 is that font's normal spacing, not a
  point value. Typographic tracking is `nativeLetterSpacing`, set only by
  `.kerning` / `.tracking`, and the DirectWrite path applies it to both
  measurement and painted glyph positions. The legacy bitmap raster path
  cannot express it (that needs `IDWriteTextLayout1`) and says so through
  `letterSpacingDroppedRasterizations`.
- Tracking is counted in **inter-glyph gaps on both sides**.
  `applyLetterSpacing` walks the shaped run, so the painted line is
  `base + (glyphs − 1) × tracking`; `makeLineMeasurer` used to add
  `(characters − 1) × tracking`, which agrees only while shaping is a
  no-op. It is not: one Swift `Character` carrying two combining marks is
  three glyphs, and a ligature is two characters in one glyph. The
  measurer now derives its gap count from the same shaping capture the
  painter uses (`shapedGlyphCount`, built from a layout configured
  exactly like `layoutLine`'s), falling back to the character count only
  where the paint path itself falls back to the per-character walk. The
  shaping capture runs only for text that actually carries
  `nativeLetterSpacing`. `TextMeasurePaintFidelityTests` pins measured ==
  painted for a tracked string whose glyph and character counts differ.
- That coherence costs a whole `IDWriteTextLayout` plus a glyph-run
  capture *per probed prefix*, on the main actor, so the count is memoised
  on `DirectWriteSystem` — keyed by the line plus the style fields that
  change a glyph count, bounded at 512 entries, and deliberately outliving
  a single `layout` call. Scoped to the call, the same bill was re-paid by
  the next `measure`, the next `rasterize` and every frame's layout of the
  same unchanged paragraph. Spanned text has per-range fonts and span
  ranges that index the paragraph rather than the probed prefix, so it has
  no honest key and is not cached.
  `testWrappedTrackedParagraphShapesEachPrefixOnce` counts the probes.
- `longestFittingPrefixLength` gallops up from a short prefix before
  binary-searching. A plain binary search probes at n/2 first, and on the
  DirectWrite path each probe builds and shapes a whole
  `IDWriteTextLayout`; space-less scripts have no other break
  opportunity, so a 20,000-character CJK paragraph is one token and
  wrapping it was O(n² log n) character shaping on the main actor.
  `DirectWriteSystem.makeLineMeasurer` additionally memoises each call's
  probes, which the minimum-scale-factor pass and the wrap pass share.

**Tests:** `TextShapingPipelineTests` covers §3.1 and §3.5 — shaped glyph
identity, the frame plumbing (a shaped scene and an unshaped scene paint
glyphs at the same height), the conversion guards, the registry, tracking,
and the wrap probe budget.

## 4. Paths: GPU short-circuit + cached CPU rasterization

Before any `PathPrimitive` is enqueued, `PathToQuadTessellator` checks
whether the path can be expressed as one or more axis-aligned
`QuadPrimitive`s. When it can — typical cases are axis-aligned rectangle
fills (with or without intervening Canvas transforms) and horizontal /
vertical stroked-line segments — the path is emitted as quads instead,
bypassing CPU rasterization and the per-frame texture upload entirely.

**Fills** take five GPU lanes today:

1. Axis-aligned rectangle fills become a single `QuadPrimitive` (the
   existing fast path). The check rejects bowties / figure-8s whose
   four corner points match a rect but whose edges cross.
2. Triangle fills (3-vertex closed paths) scanline-tessellate into a
   stack of 1-pixel-tall axis-aligned `QuadPrimitive` strips. For each
   integer row inside the triangle, the tessellator computes the left
   and right edge intersections and emits one strip quad spanning that
   range. Degenerate (colinear) triangles fall through.
3. Convex polygons with 4+ vertices (and filled curved paths whose
   curve elements are first subdivided into line segments) fan-
   triangulate from vertex 0: each of the N-2 fan triangles is
   scanline-stripped via the same algorithm as (2). Curved closed
   shapes like RoundedRectangle, Circle, and Capsule take this lane.
4. **Concave simple polygons** triangulate via **ear-clipping**:
   repeatedly find a convex vertex whose triangle is empty of other
   vertices, emit its scanline strips, remove the vertex, repeat.
   Arrow-heads, star-fragments, L-shapes, and other concave-but-simple
   shapes ride this lane.
5. Self-intersecting (non-simple) polygons still fall through to CPU
   rasterization — ear-clipping can't produce a valid triangulation
   without the cleaner topology of a simple polygon.

Every fill lane is cost-bounded, because the row and vertex counts come
from app-supplied coordinates. The scanline range is intersected with the
path's `clipBounds` (rows the clip cannot show are not worth a quad), the
per-triangle row count and the per-path quad count are capped, and the
ear clipper — O(n³) in vertices, fed by curve subdivision — refuses
polygons past a vertex cap. Past any budget the whole path falls back to
CPU rasterization, which is bounded by the surface instead. A single
outlier vertex at `y = 2_000_000` used to emit ~2 M `QuadPrimitive`s per
frame that the clip then discarded, and a finite-but-huge coordinate
(`1e300`) trapped at `Int(_:)`; the row count now saturates via
`GPUISceneValue.int` (`PathTessellationBudgetTests`).

Curves (`quadraticCurveTo`, `cubicCurveTo`, `arc`) inside stroked paths
are adaptively subdivided into 16 line segments first. Each segment
becomes a `QuadPrimitive`: axis-aligned segments emit unrotated quads
(`rotationRadians = 0`, fast path in both the HLSL vertex shader and
the CPU rasterizer); diagonal/curved segments emit **rotated quads**
(`rotationRadians = atan2(dy, dx)`). The vertex shader rotates the
on-screen footprint around the quad's centre while keeping interior
coordinates (corner radius, gradient axis) computed in unrotated
local space; the CPU rasterizer scans the rotated bounding box and
inverse-rotates each pixel back to local space for the same coverage
maths. Stroked paths of any shape — chart lines, hand-drawn Beziers,
arc arms — route through the GPU instance pipeline. The
tessellator's decision table is locked by `PathToQuadTessellatorTests`
and the rotated rasterization itself is locked by
`RotatedQuadRasterTests`.

Caps and joins decide *whether* a stroke promotes at all, because a quad
is a rectangle and only some stroke geometry is:

- **Caps.** A butt end stops flush, a square end extends the body by half
  a line width, and a round end stops flush and adds a disc — a
  `lineWidth × lineWidth` quad whose corner radius is half its side, which
  both backends' rounded-rect coverage resolves to a circle. Every segment
  used to be extended by half a width at both ends whatever the style said,
  which is a square cap on every open stroke.
- **Joins.** A round join is the same disc. A miter across a right angle is
  exactly the square the two extended bodies already cover, so an L or a
  stroked rect promotes unchanged; at any other angle the wedge is a kite,
  and a bevel is a triangle. Neither is a rectangle, so *that one wedge*
  goes to `PathCoverageRasterizer` through `Result.residualPath` — a short
  stub back along the incoming segment, the vertex, and a stub forward
  along the outgoing one — while both segment bodies stay on the GPU. A
  three-corner bevelled polyline is four quads plus three wedges, not a
  full-extent CPU raster and texture upload.
- **Translucent strokes still fall back whole.** A wedge stub overlaps the
  two bodies it joins, because a stroker draws a join by stroking the
  corner it belongs to. Painting an opaque colour twice is invisible;
  painting a translucent one twice is a dark notch at every corner, so a
  stroke with `alpha < 1` keeps the whole-path CPU raster.
- **Tolerance.** "Sharp enough to matter" is
  `StrokeOutlineGeometry.joinIsVisible`, shared with the CPU stroker, so
  the flattened steps of a stroked circle stay on the GPU and a real corner
  does not.
- **Miter limit.** `StrokeOutlineGeometry.effectiveMiterLimit` caps the
  app's `miterLimit` at `maxMiterBoundsRatio` (4 half-widths), and both
  `resolvedJoin` and `boundsOutset` read it. `boundsOutset` sizes a raster
  buffer, so it refuses to track an app-supplied 10; `resolvedJoin` used
  not to, which meant a corner sharper than ~29° drew a spike past the
  `bounds` that sized its own bitmap and shipped sheared flat by the buffer
  edge. Past the ratio the miter now degrades to the bevel a tighter
  `miterLimit` would have produced — a shape SwiftUI also draws, unlike a
  cropped spike (`testSharpMiterBevelsRatherThanOverflowingItsBounds`).

For paths that still take the CPU route, `PathPrimitive` is rasterized
into a `BitmapSurface` and reused across frames:

1. The D3D11 backend caches the rasterized texture + SRV per *normalized*
   path (origin translated to `(0, 0)`), so simply moving the path
   doesn't bust the cache. The key is a scalar struct —
   `PathPrimitive.shapeHash` (a translation-invariant digest of the whole
   element stream and the paint), the element count, the extent and the
   raster window — so a lookup hashes and compares in constant time. It
   used to hold a whole normalized `PathPrimitive`, which meant building
   `path.translated(by: -origin)` on every frame for every path purely to
   have something to hash, plus a full element-array `==` on every hit.
   The exact comparison survives as `matchesShapeAndPaint(of:translatedBy:)`
   against the entry's stored path, run only when the digest matches, so a
   collision costs one comparison and never a wrong texture.
2. **The raster is bounded by what can be seen.** Below
   `pathWholeRasterByteBudget` (8 MB) the raster covers the whole path and
   the key stays clip-invariant, which is what makes a scrolling chart one
   entry and one upload. Above it the raster covers the visible region
   only — the clip intersected with the surface, snapped out to a 128 px
   tile grid so a small scroll still hits — because sizing a raster off
   unclipped bounds allocated coverage, bitmap and texture for every row a
   viewport will never show, up to the 16 384 px surface clamp.
3. Entries idle more than 60 frames are evicted; the cache is capped at
   256 entries and 64 MB with LRU eviction, and eviction runs *before* the
   texture is allocated. An entry larger than the whole byte budget is
   denied a slot and owned by the caller for the one draw: it used to
   evict every other entry (the loop cannot satisfy a condition one entry
   alone violates) and then be inserted anyway, so the next frame found an
   empty cache and did it again.
4. On `attach` and on `detach` the cache is fully drained so no stale
   device-bound SRVs are reused.

**Invariants**
- A path whose `clipBounds` misses its `bounds` entirely is dropped at
  `addPath`, exactly like the four float-clip families
  (`testPathOutsideItsClipIsDropped`). It used to fall back to its
  *unclipped* bounds, so an invisible path still burned a paint
  operation, a cached path texture and a draw call.
- Translation-invariant cache key works
  (`testTranslatedPathsNormalizeToIdenticalKeys`,
  `testShapeDigestIsTranslationInvariantAndMatchesWithoutCopying`).
- Shape/color changes produce distinct keys
  (`testPathsDifferingInShapeStayDistinct`,
  `testDigestSeparatesPathsThatDifferAtAnUnsampledVertex`,
  `testTwoShapesWithTheSameExtentStayTwoEntries`).
- A huge path inside a small clip rasterizes bounded, and scrolling inside
  one tile still hits (`testAHugePathInsideASmallClipRasterizesBounded`,
  `testAWindowedPathStillHitsWhileScrollingInsideOneTile`).
- An over-budget raster is denied rather than flushing the cache
  (`testAnOversizedRasterIsDeniedRatherThanFlushingTheCache`).
- Fresh renderer reports empty cache and zero hit/miss counters
  (`testFreshRendererHasEmptyPathCache`).

### 4a-scale. Why 2x emits more primitives

The same app at the same *logical* size does not emit the same number of
scene primitives at every display scale. On the demo at 1280x720 pt:

| screen    | 1x  | true 2x |
| --------- | --- | ------- |
| dashboard | 752 | 787     |
| data      | 490 | 520     |
| settings  | 723 | 723     |

This is one effect, not several, and it is the fill lanes above. Every
other family is scale-invariant, and so is chrome:

- Glyphs, images, shadows and CPU paths are one primitive per drawn thing
  at any scale. A glyph is a quad against an atlas whose *raster* is
  scale-dependent; its count is not.
- Borders, corner arcs, hairlines, scroll indicators and fills are
  resolved in **points** and scaled on the way into the scene, so a
  rounded border ring is the same four edges and four arc runs at 1x and
  2x — `BorderSegments.appendCornerArc` subdivides a point-space arc.
  That is why the settings pane, which is nothing but chrome, costs the
  same 723 primitives at both scales.
- A **path fill** is lowered by `PathToQuadTessellator` into axis-aligned
  quads one **device-pixel row** at a time (`scanlineFillTriangle` emits
  `height: 1` in the device space `ScenePainter` scaled the path into).
  The rows *are* the pixels: the same logical shape covers twice as many
  rows at 2x, and emitting a scale-invariant number of them would leave
  gaps between the strips. The dashboard and data screens draw vector
  symbols this way; the settings pane draws none, which is the whole
  difference between the rows of the table.

So the count difference is the cost of GPU-promoting a fill, and it is
bounded by the same budgets as every other fill (`maxScanlineRows`,
`maxTessellatedQuads`, and the clip intersection that drops rows the clip
cannot show). `ScenePrimitiveScaleInvarianceTests` pins all three claims:
only quads may differ across scale, a chrome-only screen may not differ
at all, and a path fill emits exactly one one-device-pixel-tall quad per
row.

### 4b. Dashes are geometry before the path contract

`PathPrimitive` carries no `dashPattern`: both stroke rasterizers draw
every element solid, and `strokeStyle` reports an empty pattern. Dashes are
resolved *into* geometry upstream, by whichever lowering owns the outline:

- `BorderSegments.dashedSegments` for a rect or rounded-rect border, which
  walks the perimeter and emits one quad per dash.
- `PathDashing.dashed` for every other outline — a `Shape` that arrives as
  a `backgroundPath`, a `Canvas` `strokePath`, a frame-path stroke command.
  It flattens curves (a dash is a length along the outline, which a curve
  does not give in closed form), walks each subpath, and returns the "on"
  runs as open subpaths so the existing solid stroker draws them, cap and
  all. The walk is bounded at `maxDashSteps` so a pattern finer than the
  path is long cannot emit millions of subpaths.

Those three lowerings used to drop the pattern outright — a dashed custom
`Shape` outline and a dashed `Canvas` stroke shipped solid
(`PathDashingTests`).

## 4a. Pixel format and alpha convention

Every image, every icon and every CPU-rasterized path reaches the GPU as a
`BitmapSurface`. The surface therefore names its own format rather than
leaving each consumer to guess:

```swift
BitmapPixelFormat(channelOrder: .bgra, alphaMode: .straight | .premultiplied)
```

Channel order is BGRA throughout — that is what GDI DIBs, WIC's
`32bppBGRA`, Direct2D and the swap chain's `B8G8R8A8_UNORM` all use — so the
only live variable is the alpha convention, and the producers genuinely
disagree:

| Producer | Alpha mode |
|---|---|
| `GPUIRawSceneRasterizer` (`RasterTarget.blend` divides by output alpha) | straight |
| `ImageLoader` (WIC `GUID_WICPixelFormat32bppBGRA`) | straight |
| `PixelFontAtlas` (binary coverage) | straight |
| DirectWrite / GDI text (`GDIRasterTextRenderer.tint` scales RGB by coverage) | **premultiplied** |
| `D3D11BatchRenderer.readOffscreenPixels` (output of a premultiplied blend) | **premultiplied** |

The rules that follow from that:

1. **Premultiplied is the upload convention.** Every GPU texture and every
   Direct2D bitmap is normalized with `premultipliedAlpha()` at the upload
   site. That is what the `ONE` / `INV_SRC_ALPHA` blend state requires, and
   the only convention under which the bilinear sampler is correct — a
   straight-alpha texture bleeds the RGB of transparent texels into every
   antialiased edge. The image and text pixel shaders therefore return
   `sample * opacity` and premultiply nothing themselves.
2. **Straight is the CPU convention.** `RasterTarget.blend` composites in
   straight alpha, so `drawImage` divides premultiplied sources out per
   texel — the exact mirror of rule 1, which is what keeps the two backends
   pixel-identical on image and path scenes.
3. **Straight is the interchange convention.** `pixelColor`, `writePNG` and
   `writeBMP` all report/emit straight alpha regardless of how the bytes are
   stored, because PNG colour type 6 is straight and BMP viewers drop the
   channel.
4. **Every upload validates first.** `BitmapSurface.validate()` rejects
   non-positive dimensions, a stride below `width * 4`, and a buffer shorter
   than `bytesPerRow * height`, throwing `BitmapSurfaceError` instead of
   handing a short buffer to `CreateTexture2D` / `CreateBitmap`. The glyph
   atlas upload carries the same check.
5. **The conversion scans before it allocates, and an unchanged image is
   not re-uploaded.** Straight and premultiplied bytes are identical for an
   opaque pixel, so `converted(to:)` looks for a translucent one first and
   returns the surface relabelled — sharing the buffer — when it finds
   none; only a genuinely translucent surface is copied and rewritten,
   through an unsafe buffer. On top of that, `bindResources(for:)` runs
   every frame, and it used to release the texture and SRV of every bound
   image, so a frame-stable `Image` or `.drawingGroup()` bitmap paid a
   full-surface conversion plus a `CreateTexture2D` on the main thread on
   every frame. Binding is now pure bookkeeping and the GPU texture is
   resolved from `BitmapSurface.contentKey` at draw time (§3.2), which is
   sound because `detach()` — which every device rebuild goes through —
   empties the texture cache outright.

The glyph atlas texture is the one deliberate exception: it stays
`R8G8B8A8_UNORM` because the glyph shader samples only `.a`, which is byte 3
in either channel order.

**Invariants** (`PixelFormatContractTests`, `CrossBackendPixelParityTests`)
- A 1×1 surface holding `[0, 0, 255, 255]` — pure red in BGRA — reads back
  red, not blue (`testPureRedImageReadsBackRed`).
- Half-transparent white over black composites to ~128 per channel on both
  backends (`testHalfTransparentWhiteCompositesToMidGray`).
- A surface already tagged premultiplied is not multiplied twice
  (`testPremultipliedSurfaceIsNotMultipliedTwice`).
- A truncated surface is rejected by the upload rather than read
  (`testMalformedSurfaceIsRejectedByTheUploadRatherThanRead`).
- The `image`, `translucent image`, `scaled image` and `path texture` parity
  scenes hold GPU and CPU output within ±4 over ≥ 99.5 % of pixels.

## 4b. Resource lifetime: `attach` / `detach`

Both backend protocols (`RenderBackend`, `BatchRenderBackend`) declare
`detach()` alongside `attach(to:)` as a **bare requirement, with no
protocol-extension default**: a default no-op let a backend owning a
device, a swap chain and two atlases satisfy the requirement by inheriting
an empty teardown and leak exactly as it did before the requirement
existed. Backends that own no platform resources (the CPU rasterizer, test
fakes) write their own one-line no-op, where a reader can see it is a
decision. `check-contracts.ps1` fails if either default comes back, and
fails if a file that calls `CreateSwapChainForHwnd` defines no `detach()`.
The D3D11 implementations release everything the attach created — device, context,
DXGI factory, swap chain, render target view, every shader and pipeline
state, all four instance buffers, both glyph atlases, the image-texture
map, the path cache and the backdrop-blur engine — and reset `isAttached`.

Two properties of a GPU surface make this mandatory rather than tidy:

- A swap chain **pins the HWND it presents to**, and nothing else in the
  process ever releases it. Without `detach()`, closing a window leaked its
  whole device, including blur ping-pong textures that reach tens of
  megabytes at 4K, so a session that opens and closes windows exhausted
  video memory.
- Flip-model presentation is **exclusive per window**. A presenter switch
  that attaches the second backend before the first lets go asks DXGI for a
  second flip-model chain on the same HWND.

The call sites, all on the main actor:

| Site | Why |
|---|---|
| top of `attach` / `attachOffscreen` | attach always starts from nothing, so re-attach cannot rebind a removed device or leave a second swap chain behind |
| `WinSwiftUIWindowHost.windowWillClose` | release while the HWND is still alive |
| `fallbackToFrameRenderer`, and the batch-attach-failure branch of `attachPreferredRenderer` | batch lets go before the frame backend claims the HWND |
| `attemptBatchBackendRecoveryIfDue` | frame lets go before batch re-claims it; a failed recovery re-attaches the frame backend so the window keeps presenting |

Creation calls route their COM out-params through `makeCOM(into:_:)`
(`COMOwnership.swift`), which creates into a local and releases the
destination only once the replacement exists — so a re-attach cannot
overwrite a live pointer and a failed create leaves the previous resource
intact. `deinit` on both renderers is a **backstop, not a teardown path**:
releasing requires the immediate context and therefore the main actor,
which a nonisolated `deinit` cannot reach, and enqueueing the raw pointers
onto the main actor would release them at an unpredictable later point —
never at all, at process teardown. What it does instead is refuse to be
silent: `RendererTeardownBackstop.reportUndetachedTeardown` writes the leak
to stderr in **every** configuration and counts it, then traps in debug.
The previous debug-only `assert` meant a shipping build leaked a device, a
swap chain, both atlases, the path cache and the blur ping-pong pair with
no diagnostic at all.

`RenderBackendLifetimeTests` checks the released state two ways: the Swift
side (`liveCOMObjectCountForTesting`, every stored pointer counted one at a
time) and the **debug layer** — a device created with
`D3D11_CREATE_DEVICE_DEBUG`, run through attach/detach cycles, with
`ID3D11Debug` held across the detach. Because every device child holds a
reference on its device, a device whose only surviving reference is that
`ID3D11Debug` has nothing alive on it; the test also leaks a texture on
purpose and confirms the count rises, so the check is known to have teeth.
It skips when the Graphics Tools feature (which ships the debug layer) is
not installed.

**Invariants** (`RenderBackendLifetimeTests`)
- `testDetachReleasesEveryCOMObjectTheRendererOwns` — every stored pointer,
  the image map and the path cache are empty afterwards.
- `testAttachDetachAttachRoundTripProducesTheSamePixels` — a re-attached
  renderer draws the identical frame on a newly created device.
- `testRepeatedAttachDetachCyclesReturnToZeroLiveObjects` — the open/close
  loop does not accumulate.
- `testWindowWillCloseDetachesBothBackends`,
  `testMidSessionDowngradeDetachesBatchBeforeAttachingFrame`,
  `testBatchRecoveryDetachesFrameBackendBeforeReattachingBatch` — the host
  really calls it, in the right order.

## 4c. Device loss: classification, rebuild, generation tokens

Device loss is **not** a backend being bad, so it is not handled by the
backend-selection policy in §5. A removed adapter is gone for every backend
in the process; switching presenters would only create the next device on
the same dead adapter. Both D3D11 renderers rebuild their own device in
place instead.

`DeviceLostPolicy` (`Sources/SwiftWindowsRendererD3D11/DeviceLostPolicy.swift`)
is the shared, GPU-free classifier. Every decision the recovery path makes
is a function from an HRESULT and an attempt number to a value there:

| HRESULT | `PresentOutcome` | Meaning |
|---|---|---|
| `S_OK` and other success codes | `.presented` | the frame reached the screen |
| `DXGI_STATUS_OCCLUDED` (positive) | `.occluded` | window invisible; flip-model `Present` stops blocking on vsync, so the frame loop must throttle rather than spin |
| `DEVICE_REMOVED`, `DEVICE_RESET`, `DEVICE_HUNG`, `DRIVER_INTERNAL_ERROR` | `.deviceLost` | rebuild the device |
| any other negative | `.failed` | a real failure that is not device loss |

Both renderers present from exactly one call site (`presentFrame`, pinned by
`check-contracts.ps1`) and classify its HRESULT there. On `.deviceLost` they
follow GPUI's shape: `OMSetRenderTargets(nil)` → `ClearState` → `Flush` →
release every device object (all of which `detach()` already does, §4b) →
wait ~0.35 s and up → recreate → skip one frame. The wait matters: GPUI's
comment is "if we don't wait, the final drawing result will be blank".

The rebuild is bounded by `DeviceLostPolicy.maxRecoveryAttempts` (3)
**consecutive** attempts, where "consecutive" means without an intervening
present that reached the screen — so the budget bounds a device-loss storm,
not a session. Past it the renderer detaches itself and the failure reaches
the host typed `.deviceLost`, at which point the §5 policy applies.

Because the rebuilt frame is deliberately skipped, the backend reports
`presentationState.needsImmediateRepaint`; `renderCurrentFrame` folds that
into `pendingPresentation` so a static tree still repaints. (It does *not*
call `window.invalidate()` — that runs inside `WM_PAINT`'s
BeginPaint/EndPaint pair, where re-dirtying the region spins.)

**Device generations.** Every `ID3D11Device` this module creates gets a
monotonic `deviceGeneration`, and device-owned caches key on it rather than
on the device pointer. After a rebuild the allocator is free to hand the new
device the address the removed one just released, so pointer equality would
report a match for resources built on a device that no longer exists. The
backdrop-blur engine is the first cache keyed this way
(`matches(deviceGeneration:)`); any future device-owned cache should be too.

**Typed failures.** `PresentationFailureKind`
(`SwiftWindowsGraphics/PresentationFailure.swift`, renderer-neutral) is what
crosses the backend boundary: `.deviceLost`, `.transient`, `.sceneContent`,
`.permanent`. `D3D11RendererError` and `BatchRendererError` classify
themselves from their HRESULT, with per-scene sites (image upload, glyph
atlas, unresolved scene resources) declaring `.sceneContent` explicitly and
device loss outranking any such claim. An error that classifies nothing is
read as `.transient`, the historical retry-with-backoff behaviour.

**Invariants**
- `DeviceLostPolicyTests` — the classifier, the failure-kind mapping, the
  bounded monotonic backoff, and that each error type classifies itself.
- `DeviceLossRecoveryTests` — a forced loss produces a *new* device
  generation with the render target rebuilt at the same size and pixels that
  still match; the retry budget is bounded and surfaces `.deviceLost`; a
  clean present refunds it; the blur engine is keyed on generation, not
  address, and is rebuilt across a loss.
- `PresentationFailurePolicyTests` — the kind reaches
  `RendererHealthSnapshot`, a `.permanent` failure schedules no recovery,
  and a backend owing a repaint keeps the frame loop alive.

## 4d. Host lifecycle: window ownership, presenter attach, frame timer

Everything above assumes a window that is alive and a presenter that is
attached. Three host-level rules keep that assumption true, and each replaced
a way the session could wedge.

**Window ownership.** `Win32Window.create()` installs a *retained* self
reference in `GWLP_USERDATA`, and an explicit `WM_NCDESTROY` case — the last
message any window receives — calls `DefWindowProcW`, zeroes `GWLP_USERDATA`,
forgets the `HWND` and releases that reference (from `windowProc`, after the
handler frame has returned, so the deallocation never runs on a frame that is
still executing a method on the window). Closing a window drops the
coordinator's last strong reference from *inside* `windowWillClose`, so an
unretained back pointer left `WM_NCDESTROY` resolving freed memory on every
close. For the same reason `WinSwiftUIWindowCoordinator` keeps the closed host
alive past the callback that closed it: window bookkeeping and the
last-window-quit policy stay immediate, only the release is deferred to the
next open, close, or main-actor turn.

**Presenter attach.** A window with no attached backend never invalidates
itself. `renderCurrentFrame`'s not-ready branch runs inside `WM_PAINT`'s
BeginPaint/EndPaint pair, where `InvalidateRect` re-dirties the region
`BeginPaint` just validated — a self-feeding repaint loop that pegged a core
behind a blank window for the life of the process on any machine where device
creation failed. Instead:

- the attach is retried a bounded number of times (5) with exponential
  backoff (0.5s → 8s), driven by the frame timer at a coarse 250 ms cadence
  because nothing is being painted;
- a successful retry runs the same `activatePresenter` path the startup attach
  does, so a recovered window is in the state a never-failed window is in;
- past the budget the host enters a terminal state: `activeBackend = .frame`,
  `isRendererReady = false`, selection reason `.presenterUnavailable`, the
  timer off, and `RendererHealthSnapshot.isPresenterUnavailable == true`. A
  blank window that reports why is recoverable by the app; one that spins is
  indistinguishable from a hang.

The same path owns the double-failure case: when `render(scene:)` throws *and*
the frame backend cannot attach to take over, the host pins `.frame`, leaves
the ready state and hands recovery to the bounded retry, rather than leaving
the dead scene backend selected and rebuilding it every tick. `report` is rate
limited per distinct failure signature (first occurrence, then every 100th,
bounded at 16 signatures, cleared on a real recovery) because it is
synchronous console I/O on the UI thread.

Before any window exists, `RenderBackendFactoryResolution.resolve` asks the
app's factory `probeAvailability()`. `D3D11RenderBackendFactory` answers with
a device-free `D3D11CreateDevice` capability query — hardware, then WARP — and
both D3D11 renderers retry device creation on `D3D_DRIVER_TYPE_WARP` too, so a
machine with no usable hardware adapter gets a slow window instead of no
window. `.degraded` (WARP) keeps the factory and logs why.

`.unavailable` substitutes `SoftwareWindowRenderBackendFactory`, **not**
`CPURenderBackendFactory`. The distinction is the whole point: the CPU
reference backend rasterizes into `lastRenderedBitmap` and stops, so
substituting it made `attach` succeed, `isRendererReady` stay true and
`isPresenterUnavailable` stay false in front of a window that never received a
pixel — a blank window reporting itself healthy, strictly worse than the
terminal state above. `SoftwareWindowRenderBackend` (in `WinSwiftUI`, because
`SwiftWindowsGraphics` is platform-free by contract) wraps the same CPU
rasterizer and blits each frame into the client area with `StretchDIBits`, so
it either presents or throws. A fallback that reports it cannot present here
either is not substituted at all, leaving the bounded attach retry to reach
`.presenterUnavailable`.

What the probe decided is carried into
`RendererHealthSnapshot.backendResolution` (requested factory, resolved
factory, availability), so "healthy hardware D3D11", "running on WARP"
(`availability == .degraded`) and "substituted onto the software presenter"
(`isSubstituted`) are distinguishable rather than identical in health.

**Frame timer.** Three bounds on the animation timer:

- The timer-queue callback fires on a pool thread and posts `WM_TIMER`, which
  Windows does *not* coalesce the way it does `SetTimer`'s synthesized ticks.
  A `Win32AnimationTimerGate` (`Atomic<Bool>`) admits one un-consumed post at
  a time — the `WM_TIMER` handler releases it before running the frame — so a
  frame slower than the timer period cannot grow the queue one message per
  tick. A refused `PostMessageW` releases the gate rather than wedging it.
- `CreateTimerQueueTimer` failure falls back to `SetTimer` and marks the
  high-resolution path unavailable. Previously the window recorded a running
  timer that did not exist, which stopped all animation and pending
  presentation permanently and silently.
- The requested cadence is kept separately from the installed one, so exiting
  a size/move or menu loop restarts the timer at the interval the host asked
  for. Reading it back from the just-stopped timer restarted it at `max(1, 0)`
  — a 1000 Hz frame timer.

`WM_SIZE` with `SIZE_MINIMIZED`, and any empty client rect reaching
`didResizeTo`, return early: a minimize used to rebuild the whole component
tree at 0×0, resize the swap chain to zero and raise a UIA structure change,
then do it again on restore.

**Invariants**
- `Win32WindowLifecycleTests` — a destroyed window forgets its handle and
  balances its self reference exactly once (a real HWND, skipped where one
  cannot be created); the timer plan rules; the post gate.
- `HostPresenterWedgeTests` — repeated paints with no presenter never
  invalidate and never log; the bounded retry ends in the observable terminal
  state; a healed backend is picked up and presents; a double fallback failure
  stops rebuilding the dead path and rate-limits its reports; an empty client
  rect changes nothing; a closed host outlives its close callback.
- `RenderBackendAvailabilityTests` — the probe contract and the composition
  root's substitution.

## 4e. Frame clock, pacing, and DPI-correct window configuration

**One monotonic clock.** `Win32Window.currentTimestampSeconds()` is
`QueryPerformanceCounter` divided by a once-queried frequency, and *every*
render entry point stamps its frame from it through the host's `frameClock`
seam — `WM_PAINT` included. Two defects met at that sentence:

- `GetTickCount64` advances in system clock ticks (documented 10–16 ms,
  typically 15.625 ms), which is coarser than a 60 Hz vsync period. Feeding it
  into a pacing floor of exactly `1/refreshRate` refused a tick that arrived
  15.6 ms after the last render for being 1 ms early, so every continuous
  animation — colour transitions, scroll momentum, rubber-band, keyboard-scroll
  tween — ran at ~30 fps with alternating 15.6/31.2 ms spacing, sampling the
  easing curves pinned in `docs/AnimationParity.md` on a quantized, jittering
  clock.
- `WM_PAINT` passed `0`, and the runtime's gate is `timestamp > 0 &&
  lastRenderTime > 0`. Since almost every frame is produced through
  `requestFrame` → `InvalidateRect` → `WM_PAINT`, pacing was inert exactly
  where frames come from and over-strict on the timer path, and one session
  interleaved renders at `t = 0` and `t = 523456.7`.

The floor is now `1 / (refreshRate × 1.15)`
(`WinSwiftUIWindowHost.pacingInterval(forRefreshRate:)`): strictly below the
vsync period, so a tick that lands slightly early still renders, and still
above half of it, so two rebuilds cannot share one vsync interval. A paced
frame returns the cached scene/frame and *leaves the dirty flags set*, so the
content still reaches the screen on the next tick.

**Recovery ladder.** `scheduleBatchBackendRecoveryIfNeeded` no longer resets
the backoff on every downgrade. A healthy device with one unrenderable scene
re-attaches trivially (`createDeviceIfNeeded`, the factory and
`createSwapChain` all early-out on live objects), so resetting on downgrade
plus extending only on *attach* failure oscillated the app between two
visibly different presenters every 5 s for the rest of the session — a full
scene build and a failed present per cycle. The interval is carried across
downgrades (5 → 10 → 20 → 40 → 60 s) and only restarts once the scene backend
has presented 30 consecutive frames. WS-02's typed failure is consumed here
too: a `.sceneContent` failure describes *the scene*, not the device, so the
promotion is withheld until the retained tree has actually changed since the
failure (sampled from `runtime.isDirty` at the top of the frame, before the
render consumes the flags). `.permanent` still schedules nothing.

**DPI-correct creation.** `CreateWindowExW`'s `nWidth`/`nHeight` are the outer
window rect in *physical* pixels; `WindowGroup(size:)` is logical points.
Passing one for the other opened every app at a fraction of its intended area
on any HiDPI display — a requested 1280×720 became a ≈632×341 logical client
area at 200 %, below the 600 pt threshold that flips
`resolvedHorizontalSizeClass` to `.compact`. `create()` now resolves the
target monitor's DPI (`GetDpiForSystem` under the per-monitor-v2 awareness
`Win32HighDpiSupport` installs, i.e. the primary monitor `CW_USEDEFAULT` uses),
scales the client size by `dpi/96`, and runs `AdjustWindowRectExForDpi` to turn
the desired client rect into a window rect.

**Window configuration.** `Win32WindowConfiguration` is the renderer-neutral
subset of `WindowGroupConfiguration` the host can enforce; `WinSwiftUI`
translates, `SwiftWindowsPlatform` applies. `minSize`/`maxSize` and
`.windowResizability(.contentSize)` become `WM_GETMINMAXINFO` track sizes (and,
for a fixed size, a style without `WS_THICKFRAME`/`WS_MAXIMIZEBOX`);
`idealSize` is the size the window opens at, clamped into min/max;
`defaultPosition` places the window in its monitor's work area; a non-normal
`windowLevel` becomes `HWND_TOPMOST`. Modifiers with no Win32 meaning
(toolbar style, subtitle, activation mode, …) are reported once at window
creation instead of silently doing nothing — see
`unsupportedWindowConfigurationModifiers`.

**One effective scale.** `Win32Window.effectiveScaleFactor` clamps the raw
`GetDpiForWindow` ratio at 1.0 and is the *only* scale the root size,
`runtime.displayScale`, `logicalPoint`, the IME caret rect and
`clientRectToScreen` use. Clamping in one of those and not the others put
every hit test, hover, drag and caret in a sub-1 DPI session (remote and
virtual displays report them) a third away from the pixels the user sees, with
nothing crashing.

**Caches.** `WM_MOVE` arrives at mouse-report rate and used to mark the
refresh rate dirty unconditionally, so every drag ran a `MonitorFromWindow` +
`GetMonitorInfoW` + `EnumDisplaySettingsW` driver round-trip per message on
the UI thread inside the modal move loop. It now invalidates only on a monitor
*identity* change, and the query itself is rate limited to once per 250 ms
(`WM_DISPLAYCHANGE`, being rare and real, bypasses the limiter). Likewise
`WM_SETTINGCHANGE` — a broadcast any process can trigger by writing any system
parameter — only reaches the delegate when the re-sampled
`SystemAppearanceSnapshot` actually differs, instead of tearing down every
observed-object token, rebuilding the tree and raising a UIA structure change
for a setting the app does not read.

**Invariants**
- `FrameClockPacingTests` — the clock is monotonic and finer than a system
  tick; the floor sits strictly below the vsync period; a 15.625 ms-quantized
  tick sequence renders ≥ 55 frames per simulated second at 60 Hz; two
  rebuilds cannot share a vsync interval; `WM_PAINT` frames carry the host
  clock, never `0`.
- `BatchRecoveryBackoffTests` — the ladder grows 5 → 10 → 20 → 40 → 60 across
  downgrades, a sustained healthy run retires it, a `.sceneContent` failure is
  not retried against an unchanged tree, `.permanent` schedules nothing.
- `WindowConfigurationDPITests` — creation geometry is linear in DPI and
  frame-inset independent; the logical root equals the requested size at 2×;
  the effective scale clamps once for every consumer and hit testing
  round-trips at 0.75; track sizes, fixed size, placement and level
  translation; a 100-message drag costs ≤ 1 display-mode query; an unchanged
  appearance triggers no reload.

## 5. Backend dispatch + fallback chain

`WinSwiftUIWindowHost` picks the rendering backend:

1. Prefer `D3D11BatchRenderer` (the "scene" backend). If `attach` fails,
   immediately downgrade to the frame renderer and log the cause.
2. If a per-frame `render(scene:)` throws, transparently fall back to
   the frame renderer for that frame and pin the host to the frame
   backend for the rest of the session.
3. If a resize fails on the batch backend, downgrade to the frame
   backend at the new size.

The default recovery policy is `BatchBackendRecoveryPolicy.standard`:
after a downgrade the host retries the batch attach with exponential
backoff (5s → 60s cap) and restores the scene backend when a retry
succeeds (see "Two-way fallback recovery" below). Apps that need the
historical **one-way** pin — where a downgraded session never invokes
the batch backend again — pass `recoveryPolicy: .disabled`.

**Invariants**
- `testBatchRenderFailureDowngradesToFrameSameSession` covers single-
  failure downgrade.
- `testBatchRendererIsNotCalledAgainAfterDowngrade` covers the one-way
  property.
- `testResizePropagationAfterBatchDowngradeReattachesResizesAndActivatesFrameRenderer`
  covers the resize-failure path.

## 6. Render: D3D11 backend

`D3D11BatchRenderer.render(scene:)` follows the plan from
`makeRenderPlan(for:)`:

1. Increment the frame counter and evict stale path-cache entries.
2. Upload incremental glyph-atlas dirty regions if any.
3. Iterate the scene's layers; for each layer issue per-family draw
   calls in the order encoded by the plan's `RenderStep`s.
4. Images use a long-lived `imageResources` table keyed by `textureID`;
   shadows, quads, glyphs, and pixelGlyphs use structured buffers per
   primitive type.
5. After the layers are drawn, present the frame.

The renderer is `@MainActor`.

### 6a. Render targets: swap chain or offscreen

`render(scene:)` is target-agnostic. Two targets exist:

| Target | Attached by | Back buffer | Present |
|---|---|---|---|
| swap chain | `attach(to:)` (needs an HWND) | `IDXGISwapChain1.GetBuffer(0)` | `Present(1, 0)` |
| offscreen | `attachOffscreen(size:driver:)` | the offscreen texture itself | `Flush` |

Everything downstream of the target — device, pipeline, instance buffers,
atlases, the backdrop-blur engine, the whole frame path — is identical for
both; the offscreen texture uses the same `B8G8R8A8_UNORM` format the swap
chain does, so what a readback shows is what a window would have shown.
`readOffscreenPixels()` returns a `BitmapSurface` (BGRA, the byte order
`GPUIRawSceneRasterizer` produces).

The offscreen path is what makes the GPU backend testable: before it
existed, `attach` required an HWND, so `resize`, `render` and `Present` had
zero execution coverage and every GPU-only defect could only be found by
reading the shader source. `attachOffscreen(size:driver: .warpFirst)`
creates the device on WARP, which ships with every Windows install and
rasterizes deterministically across machines — the requirement for pixel
assertions. `D3D11BatchRendererRenderTests` drives attach/resize/render/
present headlessly (including a 64→1920→1→4096 resize storm and zero-size
frames); `CrossBackendPixelParityTests` renders canonical scenes through
both this backend and the CPU rasterizer and asserts they agree.

## 7. Render: CPU fallback

The frame renderer drives `GPUIRawSceneRasterizer.rasterize(scene:size:)`
which produces a `BitmapSurface`. The host then `BitBlt`s the bitmap to
the HWND. Determinism is locked in by
`VisualGoldenSnapshotTests.testRasterizedShapesProduceConsistentPixelsAcrossRepeatedRenders`
which compares the raw `pixels: Data` byte-for-byte across two renders.

The same rasterizer produces every screenshot, gallery baseline and
macOS-parity render, so "the CPU rasterizer is a faithful reference for the
GPU" is load-bearing for the whole verification workflow.
`CrossBackendPixelParityTests` is what holds it up: each canonical scene
renders through the D3D11 batch renderer (offscreen on WARP) and through
the rasterizer, and must agree within 4 per channel over at least 99.5 % of
pixels — the tolerance shape `scripts/gallery-compare.ps1` uses.

Scenes the two backends genuinely disagree on stay **in the suite and
asserted against a measured floor**, never skipped. Each carries the match
ratio measured when the divergence was accepted (rounded down to three
decimals) and the workstream that will close it, and the assertion pins the
scene from both sides:

- it may not fall **below** the floor, so a shader change that halves a
  deferred scene's agreement fails instead of passing as a skip;
- it may not **reach** `requiredMatchRatio` either — a scene that has
  quietly started passing fails with "promote me", because a deferred scene
  nobody unskips is a gate nobody is minding.

Skipping after computing the comparison, which is what the suite did first,
bought neither: it built the report and threw it away.

**The deferred list is empty.** Nine scenes have carried floors over the
life of this suite — corner antialiasing at 0.990–0.994, the shadow at
0.967, a large-radius material at 0.620, and last the two magnified sampler
scenes at 0.835 and 0.753. § 7a closed the first seven; WS-18 closed the
sampler pair. Every scene in the suite now gates at the standard ratio, and
`KnownDivergence` is machinery kept for the next real gap rather than a
list with entries in it.

Images and CPU-rasterized path textures used to be on that list — the batch
renderer uploaded BGRA `BitmapSurface` bytes as `R8G8B8A8_UNORM` and blended
straight alpha through a premultiplied blend state, so every image and every
path fill rendered with red and blue swapped and an over-bright edge. They
now agree, because the pixel format is part of the surface (§ 4a).

**Texture filtering is shared, not approximated.** The GPU samples every
texture — glyph atlas and image alike — through
`D3D11_FILTER_MIN_MAG_MIP_LINEAR` with `D3D11_TEXTURE_ADDRESS_CLAMP`.
`RasterTarget` used to pick the nearest texel, which is invisible at 1:1 —
why the `scaled image` scene's gentle gradient and the uniform opaque
`solidGlyphAtlas` cell both passed without saying anything about the
filters — and a visible staircase under magnification. It now takes the
same bilinear tap: `BilinearAxisTap` maps a normalized coordinate to
`u · size − 0.5`, takes that value's floor and floor + 1 clamped into range,
and weights them by its fraction, exactly as the hardware addresses a
clamped linear sample.

Two things make it a transcription rather than a lookalike:

- **Glyphs filter alpha only** (`glyphAtlas.Sample(...).a`), so the four
  taps are alpha and the mix is one number.
- **Images filter premultiplied texels**, because every upload is
  normalized to premultiplied before it reaches the sampler
  (§ 4a). Straight-alpha sources are premultiplied per texel, mixed, and
  un-premultiplied once at the end — `blend` composites in straight alpha.
  Interpolating straight-alpha colour instead drags a transparent texel's
  hue into its opaque neighbour, which is a halo the GPU never draws.

The two scenes built to expose the gap now measure it closed:

| Scene | Fixture | Before | After |
| --- | --- | --- | --- |
| `magnified gradient glyph cell` | 8×8 atlas cell, alpha ramping across texels | 0.8359 (Δ 14) | 1.0000 (Δ 1) |
| `magnified high-contrast image` | 8×8 checkerboard | 0.7539 (Δ 116) | 1.0000 (Δ 0) |

At a texel-aligned 1:1 draw the fraction is 0 and bilinear returns exactly
the texel nearest sampling picked, so no unmagnified glyph or icon baseline
moved — `CPURasterizerGPUModelTests.testUnmagnifiedGlyphSamplingIsUnchangedByFiltering`
pins that half of the claim, and
`…testMagnifiedGlyphIsFilteredNotStaircased` the other half.

**Glyph coverage is alpha, on both backends.** The glyph shader reads
`glyphAtlas.Sample(glyphSampler, uv).a` and nothing else. The rasterizer
used to substitute `max(r, g, b)` wherever the sampled alpha was zero — a
second alpha convention with no GPU counterpart, under which the CPU could
draw ink the GPU never would. Every atlas producer writes coverage into
alpha (`NativeTextRenderer.tint` emits premultiplied BGRA, `PixelFontAtlas`
writes 255 in all four channels), so the substitution bought nothing and hid
the sampler question behind an opaque fixture. `CPURasterizerGPUModelTests`
pins the convention: a cell with colour and no alpha draws nothing.

## 7a. What the reference renderer actually models

The CPU rasterizer's job is to draw what the shaders draw. Six models it
used to get wrong, and what it does now — each pinned by
`SharedCoverageKernelTests`, `CPURasterizerGPUModelTests`,
`PathRasterizationQualityTests` or `CPUGPUBlendModeContractTests`, and all
six measured end-to-end by `CrossBackendPixelParityTests`.

**Coverage.** `GPUIQuadCoverage` is the single Swift transcription of
`roundedRectDistance` + `saturate(0.5 - d/aa)`, used by the quad body, the
rounded clip and the shadow envelope alike. `check-contracts.ps1` pins that
single implementation with three rules: `SceneRasterizer.swift` must reference
`GPUIQuadCoverage`; it must not *declare* a rounded-rect distance or
smoothstep of its own; and — because a second kernel can be inlined into
`drawQuad` rather than declared — every `signedDistance`/`smoothstep` call in
the file must be qualified with `GPUIQuadCoverage.`, and coverage may never be
answered by a containment test against a sample point. The stated limitation:
no regex recognises fresh distance math written from scratch under an
unforeseen name. `SharedCoverageKernelTests` and `CrossBackendPixelParityTests`
hold that line; the contract rules exist so the obvious regressions cannot
land silently between test runs. Three parts of the shader that are easy to lose in a paraphrase
and that the old `roundedRectCoverage` had lost:

- There is **no `radius == 0` short circuit.** Square quads run the same
  box SDF as rounded ones; answering `rect.contains(pixelCentre) ? 1 : 0`
  snapped every divider, border segment and un-rounded control background
  to whole pixels in the reference render while the shader feathered them.
- `aa` is **`fwidth(distance)` as the hardware measures it** — a finite
  difference across the 2×2 derivative quad, aligned to even pixel
  coordinates, not the analytic gradient. It is 1 along an axis-aligned
  edge, √2 along a corner arc at 45°, wider again on a rotated edge (the
  derivative is taken after the rotation), and **2** on the one pixel where
  both axes of the box SDF move across the quad. That last case is why the
  far corner pixel of every square rect is 75 % covered rather than 100 %,
  on both backends; an analytic gradient reads 1 px of ramp there where the
  shader reads 2. Emulating the derivative quad rather than differentiating
  in closed form is what took the parity scenes from ~0.99 to 1.0000.
- The **rasterizer's own coverage rule is part of the model**: a pixel
  shader runs only where the geometry covers the pixel centre, so the
  shipping antialiasing is a *half* ramp — alpha falls from 1 to 0.5 across
  the last half pixel inside the quad and is cut to 0 outside it. Scanning
  an outward-rounded integer window and evaluating the SDF over it painted
  an outward half-ramp no GPU draw can produce.

**Clipping.** A rounded clip contributes an antialiased `clipAlpha` that
multiplies the primitive's alpha; it used to be computed and then thrown
away as a boolean gate, so every card and sheet corner was hard-edged in
the reference render. An unrounded clip is rejected per pixel centre
against the float rect, in every family (quad, glyph, image, path, shadow),
rather than via the outward-rounded scan window — a systematic 1 px bleed
at 125 % and 150 % DPI.

**Shadows.** The envelope is the rect grown by `2 · blurRadius`, the
falloff is `1 - smoothstep(-blur/2, blur, distance)`, and the peak alpha is
the requested alpha. The rasterizer used to grow by `blurRadius / 2`, ramp
linearly over 1 px on a rounded rect of radius
`cornerRadius + 0.35 · blurRadius`, and scale alpha by a magic `0.55` that
appeared nowhere else in the stack. A `.shadow(radius: 20)` was a crisp
10 px halo at 55 % in every screenshot and a soft 40 px halo at full alpha
on screen. The `0.55` is retired, not promoted to a design constant.

**Materials.** `drawMaterialQuad` performs the GPU's three steps in the
GPU's order: snapshot the region under the quad, blur the snapshot, then
composite the tint over it *through the quad's coverage*. The rasterizer
used to tint first and blur the framebuffer in place over the quad's whole
axis-aligned window, which smeared the backdrop outside a rounded corner
into a square halo and — with `blurOpaque` — overwrote the same window's
alpha unconditionally, turning an opaque material's rounded corners into
square opaque blocks. The blur itself clamps taps to the region's outermost
texel, as the GPU's sampler-clamped pass does, instead of re-normalizing
the truncated kernel; that policy difference is invisible while the kernel
is narrower than the region and dominant once it is wider, which is exactly
`.blur(radius: 80)` on a 2× display.

**Colour effects.** `luminanceToAlpha` writes alpha, so both sides branch
it out of `applyColorEffect` and apply it *before* the coverage multiply;
applying it after overwrote the antialiasing and the quad's own alpha. The
shader `saturate`s the effect result, because the CPU's `RasterColor`
clamps every channel — without it an over-driven brightness composited
brighter on the GPU, where the premultiply happens before the render
target's UNORM clamp.

**Blend modes.** The contract is **source-over, and only source-over**.
`QuadPrimitive.blendMode` used to be honoured by the CPU rasterizer's
`blend` (five separable modes) and ignored by the HLSL, which declares
`float blendMode;` and never reads it against a fixed
`ONE / INV_SRC_ALPHA` blend state — so `.blendMode(.multiply)` was a
multiply in every screenshot and a plain composite on screen. The field is
still lowered onto the primitive so the information survives, but no
backend interprets it. Implementing it means splitting quad batches and
swapping `ID3D11BlendState` (multiply, screen and plusLighter are
expressible as fixed-function states; overlay is not);
`CPUGPUBlendModeContractTests` is what that work would delete.

The **frame path makes the same decision**, because a presenter swap must
not change how a tree looks. `RetainedViewRuntime.appendCommands` lowers
non-normal modes onto `FillRectCommand.blendMode` exactly as the painter
lowers them onto the primitive, `GPUISceneBridge` forwards the field onto
the quad (it used to drop it, which lost the data the reversibility
argument depends on), and nothing reads it: the fallback `D3D11Renderer`
owns exactly one `ID3D11BlendState`. It used to build an additive and a
multiply state too, plus an `activateBlendMode` helper to swap between
them — never called, so the divergence was one call site away rather than
live. The frame half is pinned by
`CPUGPUBlendModeContractTests.testEveryBlendModeRendersAsSourceOverOnTheFramePath`.

## 7b. Path fill and stroke

`ensureCachedPathTexture` CPU-rasterizes every `PathPrimitive` and uploads
the bitmap, so path quality here is not a fallback concern — it is the
shipping appearance of `Canvas`, `Shape` strokes, chart lines and the
SF-symbol vector fallback.

**What identifies a cached raster.** The key (`PathRasterKey`) is the path
normalized to a (0, 0) origin, with its clip stripped: shape, paint, stroke
width and extent, and nothing about where it sits or what is cutting it.
The clip is applied at *draw* time instead — the rectangular part as a UV
sub-rect of the cached texture (so a tall path under a short viewport does
not run a full-height pixel shader that discards almost everything), the
corner arc through the synthetic `ImagePrimitive`'s `clipCornerRadius`,
which is a shape a sub-rect cannot express. Two consequences:

- A chart inside a `ScrollView` is one entry and one upload. The key used
  to be the whole `PathPrimitive`, clip included, so a moving clip produced
  a fresh key every frame: a miss, a main-actor CPU rasterization and a
  texture upload, sixty times a second, for a shape that never changed.
- The clip is antialiased by the shader rather than cropped at integer
  bitmap edges, which is what `CrossBackendPixelParityTests`'
  `clipped path texture` scene gates.

Lookup is a dictionary hit. `PathRasterKey` hashes a bounded digest (count,
extent, paint, and up to 32 sampled elements) while `==` stays exact, so a
5,000-segment `Canvas` path costs a constant-size hash and a collision costs
one extra comparison rather than a wrong texture. The cache is bounded by
entries *and* bytes (`docs/PerformanceBudgets.md`), because dropping the
clip from the key means an entry now covers the path's whole extent.

Fill and stroke each accumulate into one per-path coverage buffer
(`PathCoverageRasterizer`, exact in x and 8× supersampled in y) and
composite with a **single blend per pixel**. Four things that buys:

- **Antialiasing.** Spans used to be blended at full strength across
  integer x, so every curve and diagonal was a staircase.
- **No double blending.** Each flattened stroke segment used to be
  scanline-filled as its own quad with the right edge rounded out and the
  left rounded in, so adjacent segments overlapped and a translucent
  polyline came out blotchy and progressively darker at every vertex.
- **Caps and joins.** The stroke outline is a quad per segment, plus the
  join at every turn sharp enough for its wedge to show, plus a cap at each
  end of an open subpath — all wound the same way so a non-zero fill of the
  set is exactly their union. `PathPrimitive` carries `lineCap`, `lineJoin`
  and `miterLimit` alongside `lineWidth` (defaulting to `StrokeStyle`'s own
  butt / miter / 10), so butt, round and square caps and round, miter and
  bevel joins are all drawn, and a miter past its limit degrades to a bevel
  the way SwiftUI, Core Graphics and Direct2D all do. It used to carry a
  width and nothing else, so this rasterizer butt-capped and round-joined
  everything while the painter's tessellator square-capped everything: a
  `Canvas` stroke asking for `StrokeStyle(lineCap: .round)` — which is what
  the SF-symbol vector fallback asks for on every icon — got neither, and
  which wrong answer it got depended on whether the path promoted.
  `StrokeOutlineGeometry` owns the rules both routes apply: the miter
  ratio, the limit resolution, and how much error an omitted join is worth
  (0.1 px, so a 2 000-segment flattened curve does not pay for 2 000
  wedges).
- **Stroke bounds.** A stroke straddles its path, so an emitter sizes
  `bounds` through `StrokeOutlineGeometry.boundsOutset(forElements:…)`
  rather than by half a line width: a square cap reaches √2 half-widths on
  a diagonal and a miter reaches as far as its corner asks, bounded at
  `maxMiterBoundsRatio` so an app-supplied limit cannot size a bitmap. The
  shape-outline lowering used to hand the primitive the path's own bounding
  rect, which cropped the outer half of every outline that reached CPU
  rasterization.
- **SwiftUI fill semantics.** Every subpath is implicitly closed for
  filling (a three-point triangle without `.close` used to be *invisible*:
  most scanlines produced one crossing and the pairing loop discarded it)
  but not for stroking, and the fill rule is **non-zero**, matching
  SwiftUI and this stack's own `Path.contains(_:eoFill: false)`. Even-odd
  filled a star or a figure-eight with holes its own hit testing called
  solid.

## 8. Stress / robustness invariants

Beyond the per-step invariants:

- `AnimationStressTests.testSustainedTickingSettlesAllAnimations` —
  1500 simulated frames with concurrent momentum + rubber-band on
  multiple scroll containers, asserts every animation settles.
- `AnimationStressTests.testRepeatedWheelAndTickPreservesRuntimeIntegrity` —
  500 wheel events interleaved with ticks, asserts no leaked state.
- `AnimationStressTests.testDynamicMutationPreservesScenePrimitiveTopology` —
  200 mutation rounds with re-renders, asserts primitive counts stay
  bounded.
- `DynamicListStressTests.testThousandItemListRendersWithNativeGlyphsAndBoundedPrimitives` —
  1000-row LazyVStack, asserts visible-window virtualization holds and
  text uses DirectWrite throughout.
- `DynamicListStressTests.testListGrowingFromHundredsToThousandsKeepsRenderingConsistent` —
  100/500/1000/2500/5000-item scaling consistency.
- `SceneValueSanitationTests` / `SceneStructuralValidationTests` — NaN,
  ±infinity and `1e30` in every primitive family, through
  `splitQuadRangeForBackdropBlur`, `blurRegion`, `makeRenderPlan` and
  `rasterize`: no trap, no hang, degenerate-but-sane output (§2a).

## Open work

- A full GPU path tessellator (Loop-Blinn, stencil-and-cover, or
  libtess2) would let **self-intersecting** filled paths skip CPU
  rasterization. `PathToQuadTessellator` now covers axis-aligned rect
  fills, triangle fills, convex polygons, concave-but-simple polygons
  (via ear-clipping, curves subdivided inline), and all stroked paths
  (axis-aligned or rotated, line segments or subdivided curves). The
  remaining CPU residue is non-simple polygons (bowties, figure-8s) —
  rare in practice.

## Two-way fallback recovery

The framework defaults to `BatchBackendRecoveryPolicy.standard`: after a
downgrade, the host periodically tries to re-attach the batch backend so
a transient driver glitch doesn't permanently strand apps on the slower
frame backend. Apps that need the historical one-way pin behaviour pass
`recoveryPolicy: .disabled`.

| Field                  | Default       | Notes                                                      |
|------------------------|---------------|------------------------------------------------------------|
| `isEnabled`            | `true`        | `.standard` enables recovery; `.disabled` keeps one-way pin. |
| `initialRetryInterval` | 5s            | Wait before the first recovery attempt after a downgrade.  |
| `maxRetryInterval`     | 60s           | Cap on exponential backoff.                                |
| `backoffMultiplier`    | 2.0           | Each failed attempt doubles the wait (up to the cap).      |

The host attempts a re-attach during the next `renderCurrentFrame` whose
clock is past the scheduled time. Because the frame backend currently owns
the HWND's swap chain, the attempt `detach()`es it first (see §4b). On
success: `activeBackend = .scene`, backoff resets, presentation selection
reports `.batchBackendRecovered`. On failure: the half-attached batch
backend is detached, the frame backend is re-attached so the window keeps
presenting, backoff doubles, next attempt scheduled. Locked in by
`WinSwiftUIWindowHostTests.testRecoveryPolicyDisabledKeepsOneWayPinBehaviour`
and `…testRecoveryPolicyEnabledRestoresBatchBackendAfterTransientFailure`.

Recovery is skipped entirely when the last failure classified as
`.permanent` (see §4c): a capability this machine does not have cannot
become available later, and retrying costs a full scene build plus a
visible backend switch every backoff window.

The pipeline state is observable from app code via
`WinSwiftUIWindowHost.rendererHealthSnapshot` (active backend, recovery
countdown, last selection reason, `lastPresentationFailureKind`,
`isPresentationOccluded`, etc.).

## Materials (`.regularMaterial`, `.thinMaterial`, etc.)

`Material` is wired into the rendering path via a `ForegroundStyle`
case (`.materialFill(tint:blurRadius:)`). When a view applies
`.background(.regularMaterial)`, the WinSwiftUI layer constructs a
panel whose ViewNode `blurRadius` is set from the material kind:

| Material kind | Tint α | Blur radius |
|---------------|--------|-------------|
| `ultraThin`   | 0.18   | 8 px        |
| `thin`        | 0.28   | 14 px       |
| `regular`     | 0.40   | 22 px       |
| `thick`       | 0.58   | 30 px       |
| `ultraThick`  | 0.72   | 40 px       |
| `bar`         | 0.64   | 18 px       |

The painter emits the panel's background quad with the encoded
`blurRadius`; the CPU rasterizer's `drawMaterialQuad` snapshots the
region under the quad, blurs the snapshot and composites the tint over it
through the quad's coverage (§ 7a). Tested by
`MaterialBackdropBlurTests` and `CPURasterizerGPUModelTests`.

**Backend parity:** the D3D11 batch renderer now performs true backdrop
blur for material quads: each blur quad (radius ≥ 1) splits the quad
batch in presentation order, copies its backbuffer region, applies a
two-pass separable Gaussian with the same kernel weights as the CPU
rasterizer, and composites the tint over the blurred backdrop — nested
materials blur the already-composited material beneath. Rotated blur
quads take the same path over the axis-aligned bounding box of their
rotated footprint (the window the CPU rasterizer also blurs). Locked by
`D3D11BackdropBlurTests` (WARP-device pixel tests).

**Region safety.** Four rules bound what a blurred quad may touch, all
pinned by `BackdropBlurRegionSafetyTests`:

- **Every tap is clamped to the region, not to the texture.** The
  ping-pong targets are grow-only and only the current region is copied
  into them, so every texel past the region still holds the previous
  material's blurred output. The region's half-texel inset rides in the
  previously unused `blurUVScale.zw`, and the blur shader clamps each tap
  to `[zw, xy - zw]`. Without it a small material drawn after a larger one
  pulls up to `radius` pixels of the previous panel into its right and
  bottom edges — deterministic, order-dependent corruption.
- **The copy box is bounded by the backbuffer's own `GetDesc`,** not by
  the caller's surface size: `resize` writes the new pixel size before
  `ResizeBuffers` and never rolls it back, so a failed resize would
  otherwise hand `CopySubresourceRegion` a source box past the end of a
  smaller buffer — undefined behaviour with no HRESULT to check.
- **The region is intersected with the quad's clip rect** (`clipWidth ==
  clipHeight == 0` still means unclipped), matching the CPU rasterizer,
  which blurs the clipped bounds. A tall material in a short scroll clip
  therefore no longer blurs — or grows the ping-pong pair to — its full
  unclipped height.
- **A blur failure costs the frost, not the frame.** The ping-pong pair
  is the renderer's largest allocation and is made lazily mid-frame, so it
  is the one most likely to fail under memory pressure. `render` contains
  any non-device-lost blur failure, draws the material through the plain
  edge-softening quad path instead, and latches `blurDegraded` until the
  next `resize` (which is what changes the allocation). Device loss is
  deliberately not contained — it has its own recovery path.

The blur engine replaces the caller's render target, viewport, rasterizer
state, blend state, shaders and VS `b0` and cannot restore them, so
`D3D11BatchRenderer.bindFramePipelineState` re-binds the frame's state
after every blurred quad (and once before the step loop). That makes the
batch loop's state contract an invariant rather than a prose
post-condition that happens to hold while the two frame-uniform layouts
stay byte-identical.

### Blur cost model and the downsample chain

A two-pass separable Gaussian costs `2 · w · h · (2r + 1)` texture
samples, and the painter emits `radius × displayScale`, so both the
region and the radius grow with the display: **blur cost is cubic in
display scale**. A `.blur(radius: 100)` panel that costs 20 M samples at
1× costs 160 M at 2×.

`BlurPassPlan` (`Sources/SwiftWindowsGraphics/RenderPass.swift`) is the
one place that decides what to do about it, and both backends read it:

| Requested radius (device px) | Halvings | Reduced radius | Cost vs full |
|------------------------------|----------|----------------|--------------|
| ≤ 128                        | 0        | unchanged      | 1×           |
| 129 … 192                    | 1        | r / 2          | ~8× cheaper  |
| 193 … 256 (`maxBlurRadius`)  | 2        | r / 4          | ~64× cheaper |

Two properties are load-bearing:

- **The schedule depends on the radius alone.** The CPU rasterizer's scan
  bounds and `D3D11BackdropBlurEngine.blurRegion` are written to agree,
  but "agree" is not "are provably identical"; keying the plan on the
  region size would let a one-pixel disagreement at a threshold flip one
  backend to a different number of halvings, which is a cross-backend
  parity failure with no local cause.
- **Everything a baseline pins is below the threshold.** Built-in
  materials top out at 40 device pixels, so the reduced path is reachable
  only from app-supplied wide `.blur(radius:)`. Turning it on moved no
  reference render.

The GPU halving pass is the ordinary blur shader with a **zero radius**.
The blur shader maps a `[0,1]` viewport coordinate through
`uv = input.uv * blurUVScale.xy`, so output texel `i` taps the source at
`(i + 0.5) · span / outputExtent` texels. That is the boundary between
texels `2i` and `2i+1` — an exact 2×2 box average under bilinear
filtering — **only when the span is exactly twice the output extent**,
which is why the span comes from `SubTextureRegion.halvingSource` and not
from the region. The engine used to pass the whole region: at an even
extent those are the same number, and at an odd one the taps drifted by
`(i + 0.5) / outputExtent` texels, reaching a full texel of offset at the
far edge and picking up the trailing column the CPU's block average
drops. Both implementations documented the other as an exact
transcription while disagreeing at every odd extent, and two halvings
compounded it.

`SubTextureRegion.halvedExtent` / `halvingSourceExtent` are that one
derivation, and `PremultipliedImageBlur` — the CPU chain, shared with the
painter's content-blur pass — reads them too, so the reduction is one
rule with two spellings rather than two rules that agree on the cases
anyone happened to test. The upsample is folded into the composite draw:
`backdropRegion.zw` carries the texture size *multiplied by the
downsample factor*, so one divide does the region mapping and the
bilinear magnification together, and the CPU's upsample clamps through
`SubTextureRegion.clampTexelCentre` — the texel-space spelling of
`clampUV`, from the same bounds.

Pinned by `RenderPassAbstractionTests` (schedule, cost, continuity across
the threshold, the halving tap model, the CPU's dropped column, and
cross-backend parity scenes at quarter resolution and over an odd-width
region), by the contract check (both backends must be seen reading the
shared derivations), and by
`D3D11BackdropBlurTests.testBothBackendsHonourABlurRadiusAboveTheOldCap`.

### The render-pass vocabulary

`RenderTargetKind` / `RenderTargetDescriptor` / `RenderPassDescriptor` /
`SubTextureRegion` live in `Sources/SwiftWindowsGraphics/RenderPass.swift`
and are read by all three places that used to have their own idea of
"draw somewhere that is not the window":

| Consumer | What it says in the vocabulary |
|----------|-------------------------------|
| `D3D11BatchRenderer` | `currentRenderTargetDescriptor` — one statement of what and how big the current surface is, `.presentation` or `.offscreen` |
| `D3D11BackdropBlurEngine` | takes that target instead of a pair of loose surface ints, and expresses every blur pass's source rectangle as a `SubTextureRegion` |
| `ScenePainter` offscreen passes | `OffscreenPassBuffer.pass` — an `.offscreen` target with a clear colour, viewport = whole target. Every field is read: the extent sizes the bitmap, `target.clearColor` is what the sub-scene clears to, `isCacheable` decides whether last frame's bitmap may stand in (a compositing group and a content-blur isolation ask for different answers) |

It is a **consolidation, not a capability**. Nothing here made an effect
possible that was impossible before: the blur engine was already told the
same surface size, by two loose ints off the same target, so a material
blurred inside an offscreen snapshot before this too. What the vocabulary
buys is that the kind travels with the size, that there is one place to
read it from, and that a pass which clears and a pass which loads are the
same type saying different things.

### Residual: a Material inside an offscreen pass has no backdrop

An offscreen sub-scene clears to **transparent**, and a Material is a
backdrop effect — it samples what is already painted under it. Inside one
that is nothing, so the material composites its tint over emptiness and
the pass's bitmap then lands over the wallpaper unblurred: the content
under the panel stays razor sharp where it should have been smeared.

This is a property of the *pass*, not of `.drawingGroup()`, so it holds
for all three offscreen routes — `.drawingGroup()`, `.compositingGroup()`
and the `.blur(radius:)` isolation pass. The isolation pass clears to
transparent for a reason of its own: that transparent margin is what lets
a blur fade out to nothing instead of smearing a neighbour into the
subtree.

Closing it means seeding the sub-scene with the already-painted backdrop
under the pass's frame, and three separate things stand in the way:

1. **The pixels do not exist yet.** At that point the outer scene is a
   *scene* — a paint-record stream — not pixels. Turning it into pixels
   costs a full-surface CPU rasterization per pass per frame, on a path
   (D3D11) that otherwise never rasterizes on the CPU at all, and
   `.drawingGroup()` exists to make a subtree cheaper, not to make the
   whole surface expensive.
2. **It fights the bitmap cache.** `cachedCompositingGroupBitmap` is
   keyed on the node's paint key plus a clean subtree — both entirely
   subtree-local. A backdrop baked into the bitmap goes stale the moment
   anything *outside* the group moves, and the key cannot see that; the
   alternative is making any group containing a Material uncacheable,
   which is the exact case the cache is worth the most on.
3. **The composite is source-over, and only source-over** (see
   *Blend modes* above). A bitmap that already contained the backdrop
   would draw that backdrop a second time everywhere the pass is not
   fully opaque. Getting it right needs a replace/copy blend, which the
   contract does not have.

Running the pass as a real GPU pass — the backend rendering into a real
offscreen target that the material's backdrop copy can read — sidesteps
all three, and is the shape a fix would take. Recorded and skipped by
`RenderPassAbstractionTests.testMaterialInsideADrawingGroupBlursNothing`,
whose assertions pin what happens today for both the compositing-group
and the content-blur route.

### `SubTextureRegion`: one clamp, and the stale-texel class

Scratch textures in this stack are grow-only: the blur ping-pong pair and
the path cache hold a region smaller than the texture, and every texel
past the region is whatever the previous, larger region left there.
Sampling `region / textureSize` directly reaches those texels at the
region's far edge, because bilinear filtering *at the region boundary*
blends the last in-region texel with the first out-of-region one.

`SubTextureRegion` makes that unrepresentable. It clips itself into its
texture, and every UV it hands out — `uvMinU/uvMaxU`, `uvMinV/uvMaxV`,
`clampUV` — is already inset to the region's outermost texel **centres**.
The blur passes clamp through it, and so does the composite draw: the
`BackdropRegion` cbuffer's second `float4` is that clamp range. Before
this the composite sampled unclamped, so the right and bottom edge pixels
of every material panel blended in a texel the blur had never written.

### Content blur vs backdrop blur

`QuadPrimitive.blurRadius` means one thing — *blur what is already
painted under this quad* — but `ViewNode` used to spell two things with
it, and both came out wrong:

- **Cost.** `.blur(radius:)` was inherited down the tree and applied to
  every descendant *background quad*. Each such quad breaks the quad
  batch and costs one backbuffer copy plus two blur passes, so a blurred
  50-row list issued 50 copies and 100 blur draws a frame.
- **Fidelity.** Only background quads carry the field, so the text,
  images, borders and paths inside a `.blur()`ed subtree came out
  perfectly sharp. `.blur()` on a `Text` did nothing whatsoever.

The two meanings are now separate fields:

| Field | Set by | Meaning |
|-------|--------|---------|
| `ViewNode.blurRadius` | `.background(.regularMaterial)` | the node's own backdrop effect; not inherited |
| `ViewNode.contentBlurRadius` | `.blur(radius:)` | blur the subtree's rendered result; resolved as one pass |

There was a third wrong lowering in between, and it is worth naming
because it looked right: one backdrop-blur quad over the subtree's bounds
**outset by the radius**, emitted after the subtree had drawn. That fixed
both bullets above and broke a rule that matters more — *blurring one
view is not allowed to change the pixels of another*. A backdrop pass
blurs whatever is already painted under it, so `VStack { a; b.blur(10); c }`
composited a blurred copy of `a` and `c` across a 10-point band of each,
and `.blur()` on a view that painted nothing at all still smeared its
neighbours.

`ScenePainter.appendIsolatedContentBlur` is the lowering that holds:

1. size an `.offscreen` pass over the node's painted frame outset by the
   (capped, device-space) radius, clamped to the clip and to the offscreen
   area budget — the same `OffscreenPassBuffer` a compositing group uses;
2. paint the node *and its subtree* into that buffer, shifted to its
   origin, cleared to transparent;
3. blur the bitmap with `PremultipliedImageBlur` — the same chain, plan
   and kernel the backends run, so there is nothing per-backend to keep in
   step;
4. composite it as an `ImagePrimitive` at ancestor opacity.

The margin is transparent in the bitmap, so the blur still fades out past
the frame — it just fades to *nothing* rather than to a neighbour. The
node's own opacity is applied inside the pass and ancestors' opacity to
the image, so nothing frame-specific is baked into a bitmap that outlives
the frame.

**Deferred descendants come with it.** A pinned section header is a
deferred subtree: prepaint collects it and the painter drains it after
every node has finished painting, which is after the blur. A blurred
`LazyVStack(pinnedViews:)` therefore used to render blurred rows with a
perfectly sharp header on top. The isolation pass claims the deferred
entries that live under its node — marking them `isDrawnInline` so the
deferred phase skips them — and draws them into its own scene. Nested
scroll views' indicators are claimed by the same rule: the indicator
payload carries its owning node, and an owner strictly below the blurred
node is drawn into the bitmap. (The blurred node's *own* indicator is
deliberately not claimed — matching the subtree rule, which excludes the
node itself — and stays sharp above its blurred content.) It claims them
on the frames it *reuses* its bitmap too: those entries are already
inside those pixels, and a claim tied to the rasterization would put a
sharp copy back on top from the second frame onwards. For the same
reason a content-blur node never replays its outer paint-record range —
replay is the one path that skips the isolation branch, and a replayed
bitmap with unclaimed descendants is exactly that sharp copy; the bitmap
cache below, not scene replay, is what makes an unchanged blurred
subtree cheap. The `isDrawnInline` flag is reset at the top of every
paint attempt, because the deferred list outlives the frame (it carries
the replay ranges) and the decision does not. The frame path's own
deferred drain ignores the flag entirely; it has no isolation pass, so
it must still draw everything.

**Cost.** One CPU rasterization plus one Gaussian when the subtree
changes, and nothing at all when it does not: the bitmap is cached on the
node's paint key, which includes the radius and the display scale.
`ScenePaintMetrics.contentBlurPasses` / `contentBlurPassesReused` report
which happened.

**Fallback.** When the buffer cannot be sized — a non-finite frame, or an
outset area past the offscreen budget — `appendContentBlurPass` still
emits the backdrop quad, now over the **un-outset** frame. It blurs the
backdrop under the subtree rather than the subtree alone and ends at a
hard edge, which is a visible approximation; the outset that would soften
it is exactly what smeared the neighbours, and a hard edge is wrong in a
way the user can see belongs to the blurred view.

The frame path (`RenderCommand`) has no blur primitive and degrades a
content blur to sharp content, as it already did for materials.

Pinned by `ContentBlurRenderPassTests` and by the blur-pass budget in
`PerformanceBudgetGateTests`.

### A rotated clip is a render pass

The scene contract's clip is four floats naming an axis-aligned rect, and
that is the only clip a primitive can carry. For a clip established by a
**rotated** node the box its turned frame fits in is up to `√2` too large
on each axis at 45°, so the box alone cannot be the answer.

`RuntimeClipShape` therefore carries three things, not two: the
axis-aligned **rejection rect** (`rect`), the **shape** the rounding and
the rotation are anchored to (`shapeRect`), and the **angle**
(`rotation`). They divide by consumer:

- `allowsDrawing` / `allowsSubtreeTraversal` keep using `rect`. They are
  *acceptance* predicates, and a superset there costs a primitive the clip
  then rejects per pixel, while a subset loses content outright.
- `contains` — the pointer test — turns the point back into the shape's
  own space and tests it there. The interactive region is the visible one.
- `ScenePainter` routes the subtree through an **offscreen pass**. The
  children are painted *un*-turned into a buffer sized from the node's
  unrotated frame (`PaintPlacement.frame`), with the node's own rounding
  applied inside it, and the bitmap is composited back through
  `ImagePrimitive.rotationRadians`. The bitmap's own extent is then the
  clip, exactly, on both backends. This is the same
  `RenderPassDescriptor` / `OffscreenPassBuffer` machinery a
  `.drawingGroup()` uses; the only extra step is
  `ScenePainter.unrotating`, which takes the node's rotation out of the
  transform the children inherit so the angle lives on the composite
  instead of in the bitmap.

When the buffer cannot be sized — a non-finite frame, or past the
offscreen budget — the node falls through to inline painting against the
bounding-box clip, which is what the whole stack did before this route
existed. A childless rotated clip has nothing to buffer and paints its own
turned decoration directly.

Pinned by `RotationClosureTests` (the pixels and the pointer) and
`RenderPassAbstractionTests.testARotatedClipRoutesThroughAnOffscreenPassCompositedRotated`
(the vocabulary).

**Frame-path residual.** `ViewNode.appendCommands` cannot follow. Its clip
is a rect on a `RenderCommand` and it has no offscreen pass to composite,
which is the same reason it draws a rotated node's geometry as an upright
bounding box at all (`PaintPlacement.axisAligned`). So the fallback
renderer paints the **bounding box** of what the scene path paints — a
superset, never a subset: it over-fills the corners the turned rect does
not reach, and it never drops a pixel the GPU path draws.
`ClipAbstractionTests.testRotatedClipFallbackIsASupersetOfTheScenePathRegion`
pins exactly that containment. Closing it would mean giving the frame path
either a rotation on `FillRectCommand` or an offscreen pass of its own.

**Nesting residual.** A clip re-anchors `shapeRect` to the node that
established it, so a rotated ancestor clip narrowed by a *differently*
oriented descendant keeps only the descendant's shape and angle; the
ancestor's turned boundary degrades to its contribution to the rejection
rect. This is the same single-`shapeRect` approximation the rounded-clip
lowering already documents above.

### Virtualization: `.lazyStack`

`LazyVStack` was lazy in name only — the runtime had no virtualization
concept, so a 5,000-row list ran a full `layoutSubtree` descent into
every row on every layout pass.

`ViewLayoutMode.lazyStack(StackLayout)` is that concept:

- **Placement is unchanged.** Every child is still measured and given a
  frame, because a stack cannot know where row 900 goes without knowing
  how tall rows 0…899 are. `sizeThatFits` is cached per node, so that
  half stays shallow.
- **The descent into the child is skipped** while the scroll viewport, plus a
  full viewport of overscan on each side, cannot reach the child. The
  overscan is what makes the skip safe: a row's subtree may draw outside
  the row and layout is not the place that knows how far.
- **The window is computed by walking up** to the nearest scrollable
  ancestor (`ViewNode.layoutVirtualizationWindow()`), not pushed down.
  A scroll frame dirties `.paint`, not `.layout`, so most layout passes
  over a scrolling list never reach code that would refresh a pushed-down
  value — and a stale window is not a slow list, it is rows that scrolled
  into view and were never laid out.
- **Deferral is recorded explicitly** (`isLayoutDeferredByVirtualization`)
  because dirty flags are not a reliable record of "still needs laying
  out": the painter culls an out-of-viewport subtree and calls
  `markSubtreeRendered()` on it, clearing the aggregate flag. Resuming a
  deferred child also clears its `cachedLayoutKey`, so `layoutSubtree`
  cannot take its early-return path over a subtree that was never laid
  out.
- **Scrolling invalidates layout only over virtualized content.** A
  `.lazyStack` that defers a child sets `hasVirtualizedDescendants` on its
  scroll ancestor; that node's `scrollOffset` then invalidates
  `[.paint, .layout]` instead of `.paint`. An ordinary scroll view keeps
  its paint-only invalidation and pays nothing for the concept. The flag
  is **recomputed per pass, never latched**: a scrollable node clears it
  as `layoutSubtree` enters it, and only deferrals observed after that set
  it again, so a lazy stack reconciled into an eager one stops charging
  every later scroll a layout pass it has no use for.
- **The path to a lazy stack is kept reachable.** A scroll dirties the
  scrollable node and its *ancestors*, never the panel between it and the
  stack, so that panel takes `layoutSubtree`'s early return and the stack
  below it is never visited — leaving rows that scrolled into range laid
  out at whatever geometry they last had. `layoutVirtualizationWindow()`'s
  upward walk therefore stamps `virtualizationDescentPassID` on every node
  from the stack up to its scroll ancestor, and the early return descends
  into children on that path as well as dirty ones. Comparing that stamp
  against the node's own `lastLayoutVisitPassID` makes the path
  self-limiting: once a pass reaches a node and finds no lazy stack below
  it, the next pass stops descending.
- **`resolvedScrollOffset` is published before children lay out** as well
  as after, so a descendant lazy stack resolves its window against this
  frame's offset rather than last frame's.

What deferral costs, and who pays it:

- **Accessibility does not read a deferred subtree.** A deferred row's own
  frame is real — the stack placed it — but everything inside it is zero,
  and bounds are the one thing a UIA client is entitled to trust.
  `AccessibilityProjection` therefore projects such a row as a single
  childless element flagged `isVirtualizedPlaceholder`, keeping its real
  rectangle and a name folded from its descendants' labels (structure, not
  layout). The provider wave maps that onto the `VirtualizedItem` pattern;
  realizing a row is a scroll and a layout pass away.
- **`onLayout` stops firing** for a row outside the overscan, because it
  is the layout pass that publishes it. This is the semantic that keeps
  `List` out of virtualization for now — see below.

Not done: lazy *node construction*. `LazyVStack`'s content arrives as an
already-materialised `[AnyView]`, so every row's `ViewNode` is built even
though most are never laid out — 500 rows are ~1,000 nodes whatever the
viewport shows, pinned by `testLazyListStillConstructsANodePerRow` and, at
the per-row slope, by
`testLazyStackConstructionIsStillLinearInTheRowCount` and
`testRowsTheViewportNeverReachesAreBuiltInFullAnyway`.

##### Why lazy construction needs an API

The tempting version of the fix is that `ForEach` over a range is the
common case and already carries its data plus a per-element closure, so
the runtime could call that closure only for rows inside the window
without changing any call site. It cannot, and the reason is two lines
of the compatibility layer:

```swift
// ForEach.init
self.contentViews = Self.buildContentViews(data: data, id: id, content: content)

// ViewBuilder
public static func buildExpression<Data, ID>(_ e: ForEach<Data, ID>) -> [AnyView] { e.contentViews }
```

`ForEach` calls its element closure for every element **inside its own
initializer** — the closure is consumed there and never stored — and
`ViewBuilder` then flattens the resulting array into the enclosing block,
so the enclosing `LazyVStack.init` receives one `AnyView` per row and no
`ForEach` at all. Every row's view value exists before `makeComponent`
runs, which is before the runtime, the scroll viewport, or the
virtualization window are in the picture. `retainedLazyStackChildren`
building a `ViewNode` per `AnyView` is the *second* linear cost, not the
first.

Deferring it means all of:

- `ForEach` retaining `data` and an `@escaping` element closure instead of
  a materialised array — which changes `onDelete`/`onMove`/`onInsert`,
  which decorate `contentViews` today, and the `.id("\(elementID)#\(i)")`
  identity each row is given at build time;
- `ViewBuilder` keeping a `ForEach` whole instead of flattening it, i.e. a
  currency other than `[AnyView]` for lazy containers — every consumer of
  the flattened array (`Section`, `Group`, pinned-view hints,
  `sectionHeaderChildCount`, `dynamicContentIndex`) indexes rows in it;
- a runtime node whose children are materialised on demand during layout,
  with the reconciliation identity, hit testing, accessibility projection
  and replay-cache keys that a materialised child gets today;
- an estimated row extent, because placement still needs to know where row
  900 goes without building rows 0…899.

That is a compatibility-surface change plus a new runtime node kind, not a
seam that exists and is unused — so the honest state is: layout work is
bounded by the viewport, construction is bounded by the data, and the
budget tests say so in numbers.

Re-verified 2026-08 at source, because the shape of the blocker matters
more than the fact of it. `ForEach.init` calls
`Self.buildContentViews(data:id:content:)`, which calls `content(element)`
in a loop over the whole collection; every one of the four `ForEach`
initializers (keyed, `Identifiable`, and the two binding-backed
`Collection` ones) takes a **non-escaping** `content` and consumes it
there. `data` survives — `public let data: Data` — but the closure that
turns an element into views does not, so the thing a lazy builder would
need to call is gone before `makeComponent` exists. And
`ViewBuilder.buildExpression(_: ForEach<Data, ID>)` returns
`expression.contentViews`, so the `ForEach` value itself is discarded at
the enclosing block. Threading a lazy child-builder through
`composeComponent` therefore cannot help: by the time `composeComponent`
runs, its argument is already `[AnyView]`, one per row.

##### The shape the seam would have

Written out so the next attempt starts from a design rather than from the
same rediscovery. Four pieces, in the order they have to land, each with
the invariant it must not break.

**1. A lazy currency for `ViewBuilder`.** `[AnyView]` cannot express "rows
not yet made", so lazy containers need a second currency — a
`LazyContentSequence` value carrying, per segment, either a materialised
`[AnyView]` or an unmaterialised `(count, (Int) -> [AnyView])`. Blocks mix
freely (`Section { header }; ForEach(rows) { … }; footer`), so the
sequence is a list of segments, not a single provider.
`ViewBuilder.buildExpression(_: ForEach)` stops flattening and contributes
an unmaterialised segment; `buildBlock` concatenates segments.
*Invariant:* `LazyContentSequence.materialiseAll()` must be exactly
today's `[AnyView]`, element for element, because every eager container
keeps consuming that — this is what makes the change incremental instead
of a fork.

**2. `ForEach` retaining its element closure.** `content` becomes
`@escaping`, and `contentViews` becomes a computed materialisation.
The three things that decorate rows today have to move from decorating an
array to decorating a *row function*: `onDelete`/`onMove`/`onInsert` wrap
each produced row in `DynamicListEditMetadataView`, and the per-row
`.id("\(elementID)#\(index)")` is minted inside `buildContentViews`. Both
compose as functions of `(element, index)` with no loss.
*Invariant:* the id string a row gets must not depend on how many rows
were materialised before it, or reconciliation identity moves when the
window scrolls.

**3. A runtime node that materialises children on demand.** `.lazyStack`
gains a child provider — `count`, `materialise(index) -> ViewNode`, and a
cache of the materialised range — and `layoutStackChildren` walks indices
rather than `children`. Everything downstream of `children` is what makes
this the expensive step, and each needs an answer, not a shrug:
reconciliation (`ComponentHost.reconcileChildren` walks old against new by
index — it must diff the materialised ranges and leave the rest alone),
hit testing and the prepaint dispatch table (built from `children`; an
unmaterialised row has no node to dispatch to, which is correct, because
it is off screen), accessibility projection (today it walks nodes; it
would have to report `count` and project only the window, which is what
every platform accessibility API for a virtualised list expects anyway),
and the replay-cache keys, which are per node and so simply do not exist
for a row that does not.
*Invariant:* a materialised row must be indistinguishable from an eagerly
built one. `LazyStackVirtualizationTests` already pins this from the other
side — a lazy tree and an eager tree must render identically — and it is
the right test to keep pointing at.

**4. An estimated extent for unmaterialised rows.** Placement needs to
know where row 900 goes without building rows 0…899. v1: measure the first
materialised row and use its main-axis extent as a constant estimate for
every unmaterialised one, refreshed whenever the window materialises a row
of a different extent. This is what makes the change *observable* rather
than free: `resolvedContentSize` — and therefore the scrollbar length and
the scroll clamp — becomes an estimate for non-uniform rows, exact for
uniform ones. It must be documented at the call site and pinned by a test
that a uniform list's content size is unchanged to the pixel.

**Blocked by:** step 1 and step 2 together are a compatibility-surface
change to `ViewBuilder` and `ForEach` — the two types every view in the
demo and every consumer of the flattened array goes through — and step 3
is a new runtime node kind whose children are not a stored array. Neither
half is useful alone: retaining the closure with no lazy currency still
flattens at the block, and a provider-backed node with no lazy currency
has nothing to provide. That is why the cost is *pinned* today
(`PerformanceBudgetGateTests.testLazyListConstructionCostIsPinnedAtFiveThousandRows`,
10,003 nodes for 5,000 rows) rather than partially deferred: a half-landed
seam would trade a documented linear cost for an undocumented correctness
gap in scroll extents.

#### Why `List` is not virtualized yet

`List` is the dominant long-list surface and its scroll panel *is* its
vertical stack, so `.lazyStack` would drop onto it with no structural
change. It has not, for one concrete reason: `List` rows do not have
uniform semantics with `LazyVStack` rows.

`ViewNode.resolvedFrame` and `resolvedContentSize` are internal to
`SwiftWindowsUI`, so `WinSwiftUI` cannot read a row's geometry directly.
`ListKeyboardNavigationState` therefore mirrors every row's frame through
`node.onLayout`, and `scrollRowIntoView(tag:)` — the arrow-key
scroll-into-view — reads that mirror plus the maximum `maxY` across all
rows to clamp the offset. Deferral silences `onLayout` for exactly the
rows that selection would most need to scroll to, and truncates the
content extent to the rows that happen to be in range: arrow-key
navigation could not reach past the overscan, and the clamp would be
computed from a fraction of the list. `LazyVStack` has no such mirror, so
it does not have the problem.

Adopting `.lazyStack` for `List` is therefore gated on giving the
compatibility layer a supported way to read placed-but-deferred row
geometry — either widening the resolved-layout surface or a runtime-side
scroll-into-view that works on a placed row — not on the virtualization
machinery, which is ready. The deferral semantic itself is pinned by
`testALazyStackPublishesLayoutOnlyForRowsWithinRange`.

Pinned by `LazyStackVirtualizationTests` — including the property that
matters most, that a virtualized list is **pixel-identical** to the eager
one both before and after scrolling, and the same property with a plain
panel between the scroll view and the stack — and by the layout-work,
layout-visit and node-count budgets in `PerformanceBudgetGateTests`.
`virtualizedLayoutSkipCount` counts descents avoided;
`layoutVisitCount` counts nodes `layoutSubtree` actually descended into,
which is the only one of the two that can tell "skipped the descent" from
"still walked every row".

## Per-corner radii

`ViewNode.cornerRadii` (`RetainedCornerRadii`, absolute TL/TR/BR/BL)
flows through `ScenePainter` into four extra fields on `QuadPrimitive`;
both the HLSL rounded-rect SDF (quadrant-selecting) and the CPU
rasterizer's coverage function consume them. All-zero per-corner radii
(or a `nil` node property) preserve the historic uniform path
byte-for-byte. Consumers that only understand uniform rounding
(shadow, outline, clip, dashed borders) fall back to `maxRadius`.
`UnevenRoundedRectangle` maps leading/trailing onto absolute corners
(RTL-aware). Locked by `PerCornerRadiiTests`.

Clip handling is per-corner aware: each emitted quad resolves the exact
uniform clip radius for the clip corners it actually reaches (0 when it
reaches no corner zone, the shared radius when all reached corners agree,
`maxRadius` only for quads spanning differently-rounded corners), so
deliberately-square corners under `clipsToBounds` stay square. A node's
own decoration quads (background, borders) take the *inherited* clip
corner radius — SwiftUI semantics: a view's clip shapes its children,
not its own background. Locked by `PerCornerClipTests`.

## The clip shape

Clipping is one value, `RuntimeClipShape`
(`Sources/SwiftWindowsUI/ClipShape.swift`), with one narrowing rule shared by
the three traversals that used to carry their own copy of it:
`appendPrepaintState`, `appendCommands` and `ScenePainter.paintNode`. (Two
more — `ViewNode.hitTest` and `ViewNode.scrollTarget` — were recursive
interaction traversals with no entry point left; interaction reads the clip
prepaint already recorded, and they are gone.) It carries three things four
loose scalars could not:

- **`rect`** — the *rejection* rect, the intersection of every clip rect on
  the chain. Nothing outside it paints, hits or scrolls.
- **`shapeRect`** — the rect the rounding is *anchored* to: the frame of the
  innermost node that established a rounded clip. Narrowing by a square
  `clipsToBounds` ancestor moves `rect` and leaves `shapeRect` alone.
- **`space`** — `.painted` (screen space after the accumulated node
  transforms, the only space the axis-aligned primitive clip fields can
  express) for every clip the runtime narrows, or `.layout` (untransformed
  absolute layout space, where `resolvedFrame`,
  `PrepaintInteractionState.frame` and an inverse-mapped hit point live).
  `intersecting(_:radii:uniformRadius:space:)` takes the incoming frame's
  space and asserts it matches, because intersecting two rects from different
  spaces is arithmetically fine and geometrically meaningless.

`check-contracts.ps1` keeps the narrowing single: `Runtime.swift` and
`ScenePainter.swift` call `narrowed(to:radii:uniformRadius:space:)` (the
optional-aware wrapper that also answers the absent-clip case) and may not
assign a clip from a bare `Rect.intersected(with:)`. `clip.intersected(with:)
!= nil` stays legal — that is the acceptance test every emitter shares, not a
narrowing. The one exemption is `ScenePainter`'s `RenderFrame` replay, whose
`currentClip` stack is bare rects because `RenderCommand.pushClip` carries
nothing else. The rule does not enumerate binding forms: an earlier version
allowed only an optional `var`/`let` prefix at line start, which meant it
could not fire on the `guard let` / `if let` form every real narrowing uses.
What it matches is the shape `<clip-ish name> = <anything>.intersected(with:`
wherever on the line it sits.

### One space, because one clip has more than one consumer

Prepaint used to narrow the *untransformed* frame while both paint paths
narrowed the transformed one, and prepaint's clip is not a private value: the
painter inherits it for every deferred subtree and scroll indicator, and
interaction tests pointers against it. A rotated `.clipped()` container
therefore painted one region, accepted pointers in a second and handed its
overlays a third — on the fixture in `ClipAbstractionTests` the visible and
interactive regions agreed on only 70% of probes, and a deferred overlay under
a *translating* transform was clipped away entirely.

Every runtime clip is now narrowed by `paintFrame`. Interaction follows:
`PrepaintInteractionState.clip` is tested against the raw screen point, so the
interactive region *is* the painted region, while the node's own `frame` stays
in layout space and the pointer is inverse-mapped into it — the exact rotated
footprint rather than its bounding box. Locked by
`ClipAbstractionTests.testTheInteractiveRegionOfARotatedClipIsItsVisibleRegion`,
`…testADeferredSubtreeUnderATranslatedClipPaintsWhereItsClipMoved` and
`…testEveryRuntimeClipIsNarrowedInPaintedSpace`.

The axis-aligned clip ABI used to leave one residual here — a rotated clip
shipped as its bounding box on both paths, so both the eye and the pointer saw
the box. R-ROT closed it: `RuntimeClipShape` carries the shape and its angle,
`contains` turns the pointer back into that shape, and the painter routes the
subtree through an offscreen pass composited back rotated. See
“A rotated clip is a render pass” above, including what the *frame* path can
still only approximate. The frame path's border used to be the one gate left
comparing `absoluteFrame` against a `paintFrame`-narrowed clip, which dropped
the border of a translated view the scene path drew —
`…testATranslatedBorderSurvivesTheFramePathClipGate`.

**One space needs an accumulated transform, not just the node's own.**
`appendCommands` took no inherited transform at all: it applied a node's own
transform to `paintFrame` and narrowed the clip there, then handed children a
`.painted` clip while their frames were still built from the untransformed
origin chain. Under a single transform the two coincide, which is why the
rotated fixture above agreed; nest a rotation inside a translated *and*
scaled ancestor and the frame path clipped a region the scene path never
painted, with both clips labelled `.painted` so the `Space` assertion could
not see it. The frame path now threads the accumulated transform the way
prepaint and `ScenePainter.paintNode` do —
`ViewNode.accumulatedPaintGeometry(of:transform:inheritedTransform:)`, which
is deliberately *out of line*: the temporaries of three `concatenating` calls
belong in one leaf frame, not in the walk that visits every node. Pinned by
`ClipAbstractionTests.testANestedNonCommutingTransformClipsTheSameRegionOnBothPaths`.

**Scroll indicators live in both spaces at once.** The thumb's *length* is
the fraction of the content the viewport shows — `resolvedFrame` against
`resolvedContentSize`, both layout space — while its *position* is what the
painter draws and what `deferredDrawContains` tests, which is painted space.
Measuring the track on `paintFrame` put the position right and the length
wrong: under `.scaleEffect(2)` the viewport measured twice as tall while the
content size did not, so a `ScrollView` showing a third of its content drew a
thumb two thirds of the track long and dragged at twice the rate.
`ViewNode.scrollIndicatorTrack(in:inheritedTransform:centeredTransform:)`
measures in layout space and maps the resulting rects through exactly the
mapping the caller used for its own `paintFrame`. Pinned by
`ScrollIndicatorTransformSpaceTests`.

Keeping the anchor separate fixes two visible bugs at once. A rounded card
scrolling past a `ScrollView` boundary used to pop its rounding onto the
*viewport* edge mid-scroll, because the radii were re-anchored to the
intersected rect; a nested *square* `.clipped()` used to inherit the card's
radii and apply them at its own square corners, biting arcs out of list rows
nowhere near the card's rounded edge.

The primitive ABI carries one axis-aligned clip rect plus one radius, so
`shapeRect` cannot be shipped verbatim.
`RuntimeClipShape.resolvedCornerRadius(forQuadRect:)` lowers it per
primitive: **a corner of the rejection rect is rounded only when it is still
a corner of `shapeRect`**, and a primitive reaching no surviving rounded
corner is emitted square. An *intact* clip (`rect == shapeRect`) answers its
uniform radius for every primitive exactly as before, so the zone analysis
only engages once an ancestor has actually cut a corner away.

Two residuals, documented rather than hidden. A single primitive spanning one
surviving rounded corner *and* one cut corner still takes the largest reached
radius, which rounds the cut corner it touches — the historic uniform
approximation, unchanged. And an ancestor whose corner lands *inside* a
rounded shape's corner arc (a diagonal cut) is slightly too permissive there;
exactness would need a second clip rect in every primitive family.

`RuntimeClipShape` is a `final class` with `let` properties — a value in
everything but its representation. It became one when `appendCommands` was
still a recursion with an enormous unoptimized frame, and a 120-byte clip
copied into every argument and temporary along it overflowed the 1 MB stack
at the demo's depth of ~42. That walk is a worklist now, but the class still
earns its keep: the clip is carried in a heap traversal record and inherited
by every child, so a reference is one word where a value was fifteen.

### Rounded clips reach every family

`clipCornerRadius` used to exist only on `QuadPrimitive`, so text, images,
shadows and paths inside a rounded container were rect-clipped on *both*
backends — consistent, and consistently wrong against macOS.
`GlyphPrimitive` and `ShadowPrimitive` now carry it (64 → 80 bytes each,
padded to the 16-byte structured-buffer stride), `ImagePrimitive` reuses a
padding slot (stride unchanged at 64), and `PathPrimitive` carries a
`Double`. The HLSL glyph, image and shadow pixel shaders run the same
`roundedRectDistance` + `saturate(0.5 - d/aa)` ramp the quad shader does, and
the CPU rasterizer multiplies `GPUIClipRegion.alpha` into those families'
coverage instead of using it as a yes/no gate.
`CrossBackendPixelParityTests` gates a glyph, an image and a shadow inside a
rounded container.

An image, a glyph and a path carry no corner radius of their own, so they are
rounded by the node's *own* clip; a background or border quad carries its own
radii and is rounded only by what ancestors imposed. That is the same SwiftUI
rule the per-corner section states, applied per family.

### An empty clip is representable

The four float-clip families encode their clip in band, and
`GPUIClipEncoding` (`Sources/SwiftWindowsGraphics/ClipEncoding.swift`) owns
the three states that has to express: *absent* is all four fields zero — the
value every unclipped primitive has always had — while a clip that is
positioned but collapsed (`clipX: 10, clipY: 10, clipWidth: 0,
clipHeight: 0`), or has a negative extent (`GPUIClipEncoding.emptyExtent`),
is an *empty* clip and rejects its primitive at `add*`.
`contentMaskedBounds` used to reject only the asymmetric collapse and read
the symmetric one as "unclipped", so a container whose clip collapsed to
nothing did not hide its children — it removed their clip.
`PathPrimitive` needs none of this: its `clipBounds` is an optional `Rect`,
where `nil` already means unclipped.

The writer half has to agree: `GPUIClipEncoding.encode` emits
`emptyExtent` for a non-positive width or height rather than copying the
rect through field for field, or a `Rect(0, 0, 0, 0)` written by the
public `contentMask` setter reads back as *absent* — the in-band sentinel
the encoding exists to kill, reintroduced by the one function whose job is
to avoid it.

Producing the radius is held to the same standard as encoding the rect:
`RuntimeClipShape.init` floors per-corner `RetainedCornerRadii` the way it
has always floored the uniform scalar (negative and non-finite become 0, a
square corner), because a corner radius flows through
`resolvedCornerRadius(forQuadRect:)` into `clipCornerRadius` *and* sizes
the corner-zone rects that analysis is built from.

Locked by `ClipAbstractionTests`.

The frame path (`ViewNode.appendCommands`, used when the host falls back
to the CPU renderer) has no per-corner `FillRectCommand`, so it degrades
to `cornerRadii?.maxRadius ?? cornerRadius` for shadow, outline, dashed
and solid border, and fill. Reading `cornerRadius` alone — typically 0 on
a per-corner node — turned a rounded joined control square the moment the
renderer degraded. Locked by
`RuntimeGeometrySanitationTests.testFramePathDegradesPerCornerRadiiToMaxRadius`.

### The frame path's whole-string raster cache

Frame-path text is not glyph quads: `NativeTextRenderer.appendCommands` and
`DirectWriteTextRenderer.appendCommands` lay the string out, rasterize the
whole thing into one `BitmapSurface`, and emit a single `.drawBitmap`. That
raster used to be rebuilt through DirectWrite on **every frame the path
drew** — a full layout plus a full raster per visible string per frame —
for pixels that are a pure function of `(text, style, raster size, scale)`.

That tuple is exactly `TextRasterCacheKey`, so both renderers now go through
`FramePathTextRaster.bitmap(for:size:style:scaleFactor:rasterize:)`, which is
the same `TextRasterCache` `Controls.icon` uses. One seam for both, so the
two cannot drift onto different keys. The scene path is untouched: it draws
text from the glyph atlas and never asks for a whole-string bitmap.

`TextRasterCache.shared` is a process global on purpose — its callers
(`Controls.icon` from a static factory, `appendCommands` from deep inside
`ViewNode`'s frame-path walk) have no runtime in scope; the key carries
everything that varies
per window, so there is no per-runtime state to separate and no invalidation
hook to get wrong; and the 64 MiB bound is a process bound, which
per-runtime instances would multiply by the window count. The reasoning is
restated at the declaration, and `installForTesting` is the seam a test
substitutes through. Bounds and enforcing tests: `docs/PerformanceBudgets.md`.
