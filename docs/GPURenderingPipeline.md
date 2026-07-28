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
- Translation-invariant cache key works
  (`testTranslatedPathsNormalizeToIdenticalKeys`).
- Shape/color changes produce distinct keys
  (`testPathsDifferingInShapeStayDistinct` etc.).
- Fresh renderer reports empty cache and zero hit/miss counters
  (`testFreshRendererHasEmptyPathCache`).

## 4b. Resource lifetime: `attach` / `detach`

Both backend protocols (`RenderBackend`, `BatchRenderBackend`) declare
`detach()` alongside `attach(to:)`, defaulting to a no-op for backends that
own no platform resources (the CPU rasterizer, test fakes). The D3D11
implementations release everything the attach created — device, context,
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
intact. `deinit` on both renderers is a debug assertion, not a teardown
path: releasing requires the immediate context and therefore the main
actor, which a nonisolated `deinit` cannot reach.

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

Scenes the two backends genuinely disagree on stay **in the suite but
skipped**, each `XCTSkip` naming the workstream that will make it pass and
carrying the measured match ratio so progress is visible before the gate
flips. Today: images and CPU-rasterized path textures (the batch renderer
uploads BGRA `BitmapSurface` bytes as `R8G8B8A8_UNORM`, so red and blue are
swapped), shadows (different inflation, falloff and alpha), materials
(blur-then-tint offscreen vs tint-then-blur in place), and everything with a
rounded corner, a rotation or a non-integer edge (the shader's ramp width is
`max(fwidth(distance), 0.75)`, up to 1.41 px along a corner arc, while
`roundedRectCoverage` always ramps over exactly 1 px, and square quads take
a binary-coverage short-circuit with no antialiasing at all).

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

**Backend parity:** the D3D11 batch renderer now performs true backdrop
blur for material quads: each blur quad (axis-aligned, radius ≥ 1) splits
the quad batch in presentation order, copies its backbuffer region,
applies a two-pass separable Gaussian with the same kernel weights as the
CPU rasterizer, and composites the tint over the blurred backdrop —
nested materials blur the already-composited material beneath. Rotated
blur quads deliberately stay on the old edge-softening path. Locked by
`D3D11BackdropBlurTests` (WARP-device pixel tests).

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
