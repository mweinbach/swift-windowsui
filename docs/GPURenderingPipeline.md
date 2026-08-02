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
and the animation tick share one recursion-depth counter capped at
`ViewNode.maximumTraversalDepth`; past it a subtree is skipped with a
one-shot diagnostic instead of overflowing the main thread's stack
(an access violation, which no fallback policy can absorb). The cap is a
backstop, not a stack guarantee: the demo's deepest screen reaches 42.

**Tests:** `RuntimeAnimationGatingTests`, `RuntimeDirtyFlagIntegrityTests`,
`RuntimeRenderPassReentrancyTests`, `RuntimeGeometrySanitationTests`.

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
  `GPUISceneLimits.maxCoordinate`, colours and opacity to `[0, 1]`,
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
- `GPUIScene.validate() -> [SceneDefect]` checks what direct mutation of
  the scene's `public var` surface can still break — layer count, every
  paint operation's range against its family array, and glyph-atlas
  buffer size. `D3D11BatchRenderer.makeRenderPlan` calls it
  unconditionally (it is O(layers + paint operations) and allocates
  nothing on a clean scene) and throws a `.sceneContent`
  `BatchRendererError` rather than trapping on a malformed layer.
- `GlyphAtlasSnapshot.uploadDecision(for:)` is what consumers upload
  from (see §3.1): regions are producer-supplied, and a negative origin
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
it as one `ImagePrimitive`. `compositingGroupBuffer` decides whether that
is possible at all:

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
instead of reusing pixels baked across the recycle.
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

**Tests:** `PainterDeviceSpaceTests`, `PainterZeroExtentSemanticsTests`,
`PainterBorderRingCoverageTests`, `BorderCornerArcGeometryTests`,
`CompositingGroupBitmapCacheTests`, `ScenePainterTests`,
`PathTessellationBudgetTests`.

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
   previous snapshot (§3.1).
5. The painter forces leading text alignment when laying out a *single
   line* through DirectWrite, so glyph origins return relative to the
   line's natural start. The actual horizontal alignment of the line
   is applied later by the painter's own `startX` calculation.

The "force leading alignment" rule is critical: DirectWrite sized the
layout box at 4096 px wide. Letting it center inside that box produces
glyph origins around `x ≈ 2000`, which then failed the painter's
visible-clip preflight check and silently fell back to PixelText.

### 3.0 Shaping, and the two glyph coordinate frames

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
face-keyed entries.

### 3.2 Text diagnostics

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

### 3.3 Conversions, tracking and wrap cost

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
- `longestFittingPrefixLength` gallops up from a short prefix before
  binary-searching. A plain binary search probes at n/2 first, and on the
  DirectWrite path each probe builds and shapes a whole
  `IDWriteTextLayout`; space-less scripts have no other break
  opportunity, so a 20,000-character CJK paragraph is one token and
  wrapping it was O(n² log n) character shaping on the main actor.
  `DirectWriteSystem.makeLineMeasurer` additionally memoises each call's
  probes, which the minimum-scale-factor pass and the wrap pass share.

### 3.1 The atlas and texture upload protocol

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
That cache is bounded twice — 30 frames unused, and a 96 MB byte budget
— and both bounds evict least-recently-used first.

**Tests:** `TextShapingPipelineTests` — shaped glyph identity, the frame
plumbing (a shaped scene and an unshaped scene paint glyphs at the same
height), the conversion guards, the registry, tracking, and the wrap
probe budget. `AtlasUploadProtocolTests` — the decision table, the
producers' versioning, and the real upload counts on WARP (frame 1
fresh = one full upload, frame 2 unchanged = zero, frame 3 with a small
region = one boxed upload, a region into a nil texture = full) plus
image texture/SRV pointer identity across rebinds and renumbering.

### Atlas exhaustion: the generation token

The atlas is a shelf allocator with no free list, so its only recovery
from a full atlas is `clear()` — which recycles every shelf *under the
UVs the current paint pass has already emitted*. An atlas rect is
therefore only meaningful within the generation that handed it out:
after a clear, the same rect addresses a different glyph.

`GlyphAtlas.generation` is bumped on every `clear()`, and
`ScenePainter.paint` compares it across each paint attempt:

1. Attempt 0 paints normally. If the generation moved, every UV it
   emitted is suspect and the scene is thrown away.
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
arc arms — now route through the GPU instance pipeline. The
tessellator's decision table is locked by `PathToQuadTessellatorTests`
and the rotated rasterization itself is locked by
`RotatedQuadRasterTests`.

For paths that still take the CPU route, `PathPrimitive` is rasterized
into a `BitmapSurface` and reused across frames:

1. The D3D11 backend caches the rasterized texture + SRV per *normalized*
   path (origin translated to `(0, 0)`), so simply moving the path
   doesn't bust the cache.
2. Entries idle more than 60 frames are evicted; the cache is capped at
   256 entries with LRU eviction.
3. On `attach` and on `detach` the cache is fully drained so no stale
   device-bound SRVs are reused.

**Invariants**
- A path whose `clipBounds` misses its `bounds` entirely is dropped at
  `addPath`, exactly like the four float-clip families
  (`testPathOutsideItsClipIsDropped`). It used to fall back to its
  *unclipped* bounds, so an invisible path still burned a paint
  operation, a cached path texture and a draw call.
- Translation-invariant cache key works
  (`testTranslatedPathsNormalizeToIdenticalKeys`).
- Shape/color changes produce distinct keys
  (`testPathsDifferingInShapeStayDistinct` etc.).
- Fresh renderer reports empty cache and zero hit/miss counters
  (`testFreshRendererHasEmptyPathCache`).

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
   resolved from `BitmapSurface.contentKey` at draw time (§3.1), which is
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

**The deferred list is currently empty.** Seven scenes carried floors —
corner antialiasing at 0.990–0.994, the shadow at 0.967, a large-radius
material at 0.620 — and § 7a closed all of them; every scene in the suite
now gates at the standard ratio, with a maximum per-channel delta of 1. The
machinery stays because a floor is the honest way to land a partial fix.

Images and CPU-rasterized path textures used to be on that list — the batch
renderer uploaded BGRA `BitmapSurface` bytes as `R8G8B8A8_UNORM` and blended
straight alpha through a premultiplied blend state, so every image and every
path fill rendered with red and blue swapped and an over-bright edge. They
now agree, because the pixel format is part of the surface (§ 4a). The
residual sampling difference — linear on the GPU, nearest on the CPU — is
still real; the `scaled image` scene keeps its gradient gentle enough to
stay inside the tolerance rather than pretending the filters match.

## 7a. What the reference renderer actually models

The CPU rasterizer's job is to draw what the shaders draw. Six models it
used to get wrong, and what it does now — each pinned by
`SharedCoverageKernelTests`, `CPURasterizerGPUModelTests`,
`PathRasterizationQualityTests` or `CPUGPUBlendModeContractTests`, and all
six measured end-to-end by `CrossBackendPixelParityTests`.

**Coverage.** `GPUIQuadCoverage` is the single Swift transcription of
`roundedRectDistance` + `saturate(0.5 - d/aa)`, used by the quad body, the
rounded clip and the shadow envelope alike. Three parts of the shader that
are easy to lose in a paraphrase and that the old `roundedRectCoverage`
had lost:

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

## 7b. Path fill and stroke

`ensureCachedPathTexture` CPU-rasterizes every `PathPrimitive` and uploads
the bitmap, so path quality here is not a fallback concern — it is the
shipping appearance of `Canvas`, `Shape` strokes, chart lines and the
SF-symbol vector fallback.

Fill and stroke each accumulate into one per-path coverage buffer
(`PathCoverageRasterizer`, exact in x and 8× supersampled in y) and
composite with a **single blend per pixel**. Four things that buys:

- **Antialiasing.** Spans used to be blended at full strength across
  integer x, so every curve and diagonal was a staircase.
- **No double blending.** Each flattened stroke segment used to be
  scanline-filled as its own quad with the right edge rounded out and the
  left rounded in, so adjacent segments overlapped and a translucent
  polyline came out blotchy and progressively darker at every vertex.
- **Joins.** The stroke outline is a quad per segment plus a round join
  wherever consecutive segments turn enough for the wedge between them to
  show, all wound the same way so a non-zero fill of the set is exactly
  their union. `PathPrimitive` carries only a `lineWidth`, so caps are butt
  (SwiftUI's default) and joins are round — a stand-in for SwiftUI's
  default miter that is indistinguishable on a flattened curve and degrades
  to a rounded corner rather than an unbounded spike on a sharp one.
  Carrying `StrokeStyle` through the contract is what a real miter needs.
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

The residual is the axis-aligned clip ABI itself: a rotated clip ships as its
bounding box on both paths, so both the eye and the pointer see the box. The
frame path's border used to be the one gate left comparing `absoluteFrame`
against a `paintFrame`-narrowed clip, which dropped the border of a translated
view the scene path drew — `…testATranslatedBorderSurvivesTheFramePathClipGate`.

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
everything but its representation. `ViewNode.appendCommands` is the one
recursive traversal left and its unoptimized frame is enormous; a 120-byte
clip copied into every argument and temporary along it overflows the main
thread's 1 MB stack at the demo's depth of ~42, well before
`ViewNode.maximumTraversalDepth` can fire.

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

Locked by `ClipAbstractionTests`.

The frame path (`ViewNode.appendCommands`, used when the host falls back
to the CPU renderer) has no per-corner `FillRectCommand`, so it degrades
to `cornerRadii?.maxRadius ?? cornerRadius` for shadow, outline, dashed
and solid border, and fill. Reading `cornerRadius` alone — typically 0 on
a per-corner node — turned a rounded joined control square the moment the
renderer degraded. Locked by
`RuntimeGeometrySanitationTests.testFramePathDegradesPerCornerRadiiToMaxRadius`.
