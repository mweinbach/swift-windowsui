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
- `GlyphAtlasSnapshot.clampedDirtyRegion` is what consumers upload from:
  the raw region is producer-supplied, and a negative origin traps at
  `UINT(_:)` while an over-hanging region reads past the end of
  `pixels`. Clamping to nothing degrades to the always-in-bounds
  full-atlas upload.

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
own-decoration rule, so both paths paint the same tree. Hit testing is
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
`PainterBorderRingCoverageTests`, `CompositingGroupBitmapCacheTests`,
`ScenePainterTests`, `PathTessellationBudgetTests`.

## 3. Text: DirectWrite + native glyph atlas

Text rendering is the most complex part of the pipeline.

1. `WindowTextSystem` calls into DirectWrite via
   `DirectWriteTextRenderer` to lay out the line.
2. Per-glyph atlas pages are rasterized through DirectWrite's bitmap
   render target and stored in `NativeGlyphAtlas.shared`.
3. The painter walks each glyph in the line, looks up its atlas entry,
   and emits a `GlyphPrimitive` with UVs into the atlas.
4. `NativeGlyphAtlas.snapshotIfUsedInCurrentFrame()` attaches the atlas
   to the scene. If new glyphs were rasterized this frame, the snapshot
   carries the dirty region (so the GPU backend can upload incrementally).
5. The painter forces leading text alignment when laying out a *single
   line* through DirectWrite, so glyph origins return relative to the
   line's natural start. The actual horizontal alignment of the line
   is applied later by the painter's own `startX` calculation.

The "force leading alignment" rule is critical: DirectWrite sized the
layout box at 4096 px wide. Letting it center inside that box produces
glyph origins around `x ≈ 2000`, which then failed the painter's
visible-clip preflight check and silently fell back to PixelText.

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
   every frame. `bindImageResource` now keeps the existing texture when the
   incoming surface is the *same buffer*
   (`BitmapSurface.sharesPixelStorage`), which is sound because `detach()`
   — which every device rebuild goes through — empties the image map
   outright. A producer that rebuilds its bitmap each frame still
   re-uploads; a real upload protocol (content revisions, explicit
   invalidation) is WS-09.

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
bought neither: it built the report and threw it away. Turning the skips
into floors immediately found one scene that had already graduated —
materials, at 0.9996 — and it now gates like the rest.

Today's deferred list: shadows (different inflation, falloff and alpha),
a material blurred at a radius wider than its own region (the CPU
re-normalizes the truncated kernel at the edges, the GPU clamps taps to the
region's outermost texels), and everything with a rounded corner, a
rotation or a non-integer edge (the shader's ramp width is
`max(fwidth(distance), 0.75)`, up to 1.41 px along a corner arc, while
`roundedRectCoverage` always ramps over exactly 1 px, and square quads take
a binary-coverage short-circuit with no antialiasing at all).

Images and CPU-rasterized path textures used to be on that list — the batch
renderer uploaded BGRA `BitmapSurface` bytes as `R8G8B8A8_UNORM` and blended
straight alpha through a premultiplied blend state, so every image and every
path fill rendered with red and blue swapped and an over-bright edge. They
now agree, because the pixel format is part of the surface (§ 4a). The
residual sampling difference — linear on the GPU, nearest on the CPU — is
still real; the `scaled image` scene keeps its gradient gentle enough to
stay inside the tolerance rather than pretending the filters match.

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
`blurRadius`; the CPU rasterizer's existing `applyBoxBlur` step
produces the actual blurred backdrop in-place. Tested by
`MaterialBackdropBlurTests`.

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

The frame path (`ViewNode.appendCommands`, used when the host falls back
to the CPU renderer) has no per-corner `FillRectCommand`, so it degrades
to `cornerRadii?.maxRadius ?? cornerRadius` for shadow, outline, dashed
and solid border, and fill. Reading `cornerRadius` alone — typically 0 on
a per-corner node — turned a rounded joined control square the moment the
renderer degraded. Locked by
`RuntimeGeometrySanitationTests.testFramePathDegradesPerCornerRadiiToMaxRadius`.
