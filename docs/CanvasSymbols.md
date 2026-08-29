# Canvas symbol rendering

`Canvas` can resolve tagged public views through `GraphicsContext.resolveSymbol`
and draw the result at an anchor or in a rectangle. Resolution preserves the
inherited environment and display scale. A symbol has a logical measured size
and an isolated retained tree; declaring it does not add its controls to the
window's input or accessibility tree. Applications must provide accessibility
semantics for the overall Canvas separately.

Each Canvas invocation caches successful and missing identifiers. Explicit
tags and implicit ForEach IDs retain their Hashable values rather than their
descriptions. An explicit tag takes precedence over its implicit ID. Duplicate
tags choose the first declaration on this implementation; native duplicate,
nested-layout lookup, natural sizing, and draw-in-rectangle semantics still
need qualification against the pinned SwiftUI SDK.

The Canvas callback receives logical size. Its drawing operations retain
inherited uniform scale when lowered to device coordinates. Copies of a
GraphicsContext share operation order and destination but independently retain
transform, opacity, and clip state. `drawLayer` currently scopes that state;
it does not implement complete offscreen layer blending or filter semantics.

## Scene and frame execution

The normal scene path records a symbol as a renderer-neutral child scene and
an image primitive at its authored presentation position. D3D11 executes the
child on the same device; the CPU renderer interprets the same contract.
Recording a symbol does not begin an independent native glyph-atlas frame.
The completed parent graph shares one final atlas snapshot, as described in
[the rendering pipeline](GPURenderingPipeline.md). Old returned scenes remain
immutable and can retain their own buffers.

Sources record at the display scale captured from their environment.
Magnification filters the source's existing antialiasing; it does not increase
source raster density to match the destination. `CanvasSymbolSamplingTests`
pins the retained square-quad coverage and its bilinear magnification on the
CPU scene, frame fallback, and D3D11 WARP paths. Native SwiftUI Canvas capture
density still needs reference qualification.

Symbol placement preserves context-authored translation, scale, shear,
reflection, and rotation. ImagePrimitive keeps four Float basis entries at
offsets 64, 68, 72, and 76. Its stride is 128 bytes after the bitmap resize
sampling fields; resolved Canvas symbols keep the default sampling mode. The
identity basis preserves the established image route. CPU inverse placement
and the D3D11 vertex shader share the transform contract; reflected edges
follow the GPU top/left rule. This does not extend general inherited View
shears, mirrors, or nonuniform scales beyond their existing bounding-box
fallback.

Finite, nonsingular matrices and representable transformed bounds are required.
Rejected Canvas placement emits a small visible checker and diagnostic. An
unrepresentable destination falls back to a bounded device-space marker rather
than becoming invisible. Hand-built invalid image placements remain visible
to scene validation. Scene equality now includes child image passes, including
their content, extent, and effects; no production cache dependency on equality
is asserted by that correction.

The legacy RenderFrame path uses bounded CPU symbol bitmaps. Its source cache
and source/transformed-output allocation budget belong to one Canvas recording.
It checks an exhausted budget before recording another source. This is a
declared fallback, not the normal hardware route. Direct Canvas PixelFont
fallback now interprets line spacing consistently after native text declines;
native text styles are unchanged.

## Bounds and remaining behavior

The existing image-pass contract limits depth to 32, passes to 1,024, a source
to 4,194,304 pixels, and aggregate realized source work to 16,777,216 pixels.
Canvas lookup admits at most 1,024 distinct identifiers per invocation and
bounds its declaration traversal to 4,096 nodes and depth 128. These checks
do not bound arbitrary application code or tree allocation performed by the
symbol builder before traversal. They also do not establish a total CPU RAM,
driver-memory, or identical CPU/GPU cache bound.

Ordinary retained traversal uses an ordered work list. Primitive preparation
and cache completion run outside nested source recording so large debug stack
frames do not accumulate at each accepted symbol depth. The source recorder
retains only small coordination frames; mixed symbol/color-effect, drawing
group, and blur tests exercise the same unchanged limits. This does not bound
arbitrary recursion inside application callbacks.

Complete blend modes, filter chains, path clips, layer composition,
`withCGContext`, material access to enclosing offscreen backdrops, and general
inherited affine transforms remain open. Native SwiftUI reference comparisons
must distinguish the symbol API mapping from the independently tested scene
contract. No gallery or hardware timing qualification is implied.

`AffineImagePlacementTests`, `CanvasSymbolRuntimeTests`, `CanvasSymbolSceneTests`,
`CanvasSymbolMixedDepthTests`, `CanvasSymbolSamplingTests`,
`WinSwiftUICanvasSymbolTests`, `CanvasSymbolAtlasLifetimeTests`, and
`CanvasPixelFontScaleTests` cover the public and retained contracts. The primitive layout and
D3D11 buffer-size tests also cover the ABI change. Integration must run these
alongside existing Canvas, image-pass, atlas, replay, CPU/WARP parity, and
fallback suites.
