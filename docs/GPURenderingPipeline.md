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
**presentation order**. The D3D11 backend and CPU rasterizer both
consume this array so families always render in the declared order.

**Invariants**
- `paintOperations` is the single source of presentation order; no
  family-level sort may bypass it.
- Glyphs at body-text font sizes never fall back to PixelText
  (`ViewTaxonomyParityTests`, `CrossViewRenderingParityTests`,
  `DynamicListStressTests`).
- A scene that uses native glyphs always carries the corresponding
  glyph atlas snapshot (`testParitySceneEmitsNativeGlyphAtlas`).

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

**Invariants**
- Multiple consecutive renders all receive a non-`nil` glyph atlas
  snapshot, even when no new glyphs were rasterized.
- LRU eviction in the atlas cache always recovers — 200 distinct glyphs
  through a 32×32 atlas with a 32-entry cap drops zero inserts
  (`testSustainedExhaustionAlwaysRecoversAndNeverDropsInserts`).
- `nativeFontSize` flows from `Font.body`/`.system(size:)` into
  `PixelTextStyle` correctly across all built-in view types.

## 4. Paths: GPU short-circuit + cached CPU rasterization

Before any `PathPrimitive` is enqueued, `PathToQuadTessellator` checks
whether the path can be expressed as one or more axis-aligned
`QuadPrimitive`s. When it can — typical cases are axis-aligned rectangle
fills (with or without intervening Canvas transforms) and horizontal /
vertical stroked-line segments — the path is emitted as quads instead,
bypassing CPU rasterization and the per-frame texture upload entirely.

**Fills** take four GPU lanes today:

1. Axis-aligned rectangle fills become a single `QuadPrimitive` (the
   existing fast path).
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
4. Concave polygons (interior reflex vertices) still fall through to
   CPU rasterization — fan triangulation would emit incorrect strips
   for concave geometry, so the tessellator refuses via a cross-product
   sign check on adjacent edges.

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
3. On `attach` (e.g. device-loss reattach) the cache is fully drained so
   no stale device-bound SRVs are reused.

**Invariants**
- Translation-invariant cache key works
  (`testTranslatedPathsNormalizeToIdenticalKeys`).
- Shape/color changes produce distinct keys
  (`testPathsDifferingInShapeStayDistinct` etc.).
- Fresh renderer reports empty cache and zero hit/miss counters
  (`testFreshRendererHasEmptyPathCache`).

## 5. Backend dispatch + fallback chain

`WinSwiftUIWindowHost` picks the rendering backend:

1. Prefer `D3D11BatchRenderer` (the "scene" backend). If `attach` fails,
   immediately downgrade to the frame renderer and log the cause.
2. If a per-frame `render(scene:)` throws, transparently fall back to
   the frame renderer for that frame and pin the host to the frame
   backend for the rest of the session.
3. If a resize fails on the batch backend, downgrade to the frame
   backend at the new size.

The fallback is **one-way** by design: once a session downgrades, the
batch backend is never invoked again for the lifetime of that window
even if it stops failing. This keeps every subsequent frame from paying
a failing `render` call before falling back.

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
5. After the layers are drawn, present the swap chain.

The renderer is `@MainActor` and assumes the same DXGI swap chain it
attached to.

## 7. Render: CPU fallback

The frame renderer drives `GPUIRawSceneRasterizer.rasterize(scene:size:)`
which produces a `BitmapSurface`. The host then `BitBlt`s the bitmap to
the HWND. Determinism is locked in by
`VisualGoldenSnapshotTests.testRasterizedShapesProduceConsistentPixelsAcrossRepeatedRenders`
which compares the raw `pixels: Data` byte-for-byte across two renders.

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

## Open work

- A full GPU path tessellator (Loop-Blinn, stencil-and-cover, or
  libtess2) would let **concave** filled paths skip CPU rasterization.
  `PathToQuadTessellator` now covers axis-aligned rect fills, triangle
  fills, convex polygons (any vertex count, with curves subdivided
  inline), and **all** stroked paths (axis-aligned or rotated, line
  segments or subdivided curves). The remaining CPU residue is
  concave/self-intersecting fills.

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
clock is past the scheduled time. On success: `activeBackend = .scene`,
backoff resets, presentation selection reports
`.batchBackendRecovered`. On failure: backoff doubles, next attempt
scheduled. Locked in by
`WinSwiftUIWindowHostTests.testRecoveryPolicyDisabledKeepsOneWayPinBehaviour`
and `…testRecoveryPolicyEnabledRestoresBatchBackendAfterTransientFailure`.

The pipeline state is observable from app code via
`WinSwiftUIWindowHost.rendererHealthSnapshot` (active backend, recovery
countdown, last selection reason, etc.).

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
