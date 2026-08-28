# Canvas fill rules

`GraphicsContext.fill(_:with:style:)` preserves the authored `FillStyle.eoFill`
choice for solid and linear-gradient path fills. The default remains non-zero
winding. An explicit even-odd fill counts crossings irrespective of contour
direction, so two nested contours with the same winding leave a hole:

```swift
Canvas { context, _ in
    var ring = Path()
    ring.addRect(CGRect(x: 8, y: 8, width: 80, height: 80))
    ring.addRect(CGRect(x: 28, y: 28, width: 40, height: 40))
    context.fill(ring, with: .color(.blue), style: FillStyle(eoFill: true))
}
```

Subpaths close implicitly for filling, whether or not the author calls
`closeSubpath()`. Reversing a contour changes non-zero winding but does not change
even-odd coverage. A fill still composites once per covered pixel; selecting
even-odd does not composite overlapping contours independently.

## Lowering and backend behavior

`CanvasGraphicsContext` records the rule with solid and gradient path operations.
The original operation cases remain the default non-zero spelling. Explicit-rule
cases preserve the existing public case payloads. `ScenePainter` carries the
rule into `PathPrimitive.fillRule`, and geometry translation, display scaling,
rotation, sanitation and scene replay retain it.
Exhaustive switches over the runtime `Operation` enum must handle its new cases;
preserving payloads is not a binary-compatibility guarantee.

The coverage rasterizer chooses non-zero winding or crossing parity only for the
fill. Stroke outlines always use their existing non-zero union, so overlapping
segment bodies, caps and joins do not acquire holes. Gradient stops, opacity,
clip coverage and source-over composition are unchanged.

Even-odd rectangles, triangles, canonical rounded rectangles and simple straight
polygons can use the existing GPU quad routes. The topology check rejects
compound contours, crossings, repeated vertices and ambiguous geometry. Its
pairwise proof is limited to 256 polygon vertices, using the existing ear-clip
limit. General curves, noncanonical rounded contours and larger even-odd polygons
use the existing bounded cached-path route. Existing non-zero promotion
decisions are unchanged. No new whole-window software rendering is introduced.

D3D11's path texture cache uses the same coverage rasterizer as the CPU reference.
Both the path hash and its structural collision check include the fill rule;
changing only that rule must not reuse the previous texture. Position-only
changes retain translation-invariant cache reuse. The quad structured-buffer
layout, presentation order and blend policy are unchanged.

The legacy frame route carries the rule in `FillPathCommand`, through both
`GPUISceneBridge` and `FramePathDegradation`. A degraded path bitmap therefore
retains its holes. The existing first-stop limitation for gradient path paint on
that route is unchanged.

## Limits and validation

This change does not implement `FillStyle.antialiased`: both fill rules retain
the existing coverage ramp. It does not establish fill-style behavior for
general `Shape.fill`, `clipShape`, masks, or content-shape hit testing. Those
remain separate compatibility work, as do native SwiftUI visual conformance,
general curved-path tessellation and physical-GPU performance qualification.

`CanvasEvenOddFillTests` exercises public Canvas lowering, fill/gradient pixels,
opacity, transforms, clips, copied contexts and frame fallback.
`CanvasEvenOddPromotionTests` checks supported GPU footprints and conservative
fallbacks, including a pentagram and very thin crossing contours.
`PathFillRuleBackendTests` covers scene copies/replay, cache identity, stroke
union and offscreen WARP rendering/cache alternation. Existing default-winding,
gradient, path-cache and frame-degradation suites remain preservation coverage;
pixel comparison tolerances are not relaxed for the new rule.
