# Bitmap image sizing and bounded cap/tile sampling

A decoded bitmap using `Image.resizable()` accepts finite layout proposals on
both axes. For example, a 1-by-1 resource followed by
`.resizable().frame(width: 8, height: 8)` produces an 8-by-8 destination.
The default stretch mode scales width and height independently; it does not
preserve the source aspect ratio automatically. The public
`resizable(capInsets:resizingMode:)` signature and its defaults are unchanged.

For bitmap images without an image aspect-ratio modifier, both resizing modes
leave `preferredSize` unset and declare both retained fill axes. The runtime
still supplies intrinsic bitmap dimensions when no finite proposal is
available. A nonresizable bitmap keeps its intrinsic size and alignment
inside a larger frame. Ordinary zero-cap stretch keeps the existing sampling
path and does not acquire the new cap/tile admission limits.

Resizable bitmap `Image.aspectRatio(..., contentMode: .fit)` and
`scaledToFit()` now share one retained proposal modifier with the generic
`View` fit methods. With positive finite width and height maxima and zero
minimum extents, it computes the largest rectangle of the requested ratio
inside that proposal. A nil ratio is read from the child's current ideal
size. The modifier offers the coupled width and height to its child and
reports the child's accepted size; a fixed frame or intrinsic child need
not take the full proposal. Its enclosing frame owns alignment. For example,
a 4-by-2 resizable bitmap in a centered 12-by-12 frame fits to 12-by-6 at
`(0, 3)`, leaving bands above and below.

This is retained layout, not a source-image transform. The fit wrapper keeps
the original centered stack as its fallback. An admitted finite measurement
forwards both dimensions and places the child's accepted size at the wrapper
origin, without fitting that answer again or inheriting independent fill axes.
The admission and accepted size travel together under the same measurement
cache and memo key. A declined proposal retains the old stack measurement,
alignment and clamping, including its treatment of an inner fixed frame.
The existing preferred size remains the fallback outside the admitted finite
domain, but does not override a finite fit measurement. Changes to the ratio,
proposal, or child invalidate or change the measurement cache; reconciliation
keeps the bitmap leaf within a stable fit modifier structure. Typed Image
methods still return Image, while generic methods build the same fit wrapper.
System symbols and `.fill` keep their existing paths.

The source stays at its decoded dimensions, with unchanged bytes and
`BitmapContentKey`. The retained scene emits one `ImagePrimitive` and one
source resource; frame output emits one `DrawBitmapCommand`. Their constant
size sampling descriptor describes caps and repetition without expanding
tiles into quads or creating a destination-sized bitmap. The descriptor
travels through the renderer-neutral scene, CPU rasterizer, and D3D11 image
paths. Texture reuse remains keyed by source bitmap content, not the
destination size, mode, or caps.

The new sampling path admits full-source bitmaps with finite, nonnegative
cap insets at whole source-texel boundaries. Each source axis and each
destination axis must have a positive center after subtracting both caps.
Zero-cap tile repeats the whole source. Nonzero caps leave the corners
fixed; capped stretch stretches the center and each edge along its
resizable axis, while capped tile repeats the center and those edge axes.
A final partial tile is cropped. The initial Windows policy maps
`leading` to the left source region and `trailing` to the right without
directional mirroring. These are implementation policies, not qualified
native SwiftUI edge behavior.

The descriptor holds normalized source and destination cap fractions.
Repetition is resolved from untransformed logical destination dimensions,
so display scale changes destination pixels without changing logical cap
widths or tile size. CPU and D3D11 sampling interpolate premultiplied
texels. Each capped region clamps its nonrepeating axes, and repeating
center axes wrap within their own source region rather than sampling an
adjacent cap. One image draw avoids overlapping blends at region borders.

To keep floating point tile phase bounded, the total center span across
repetitions, measured in source texels, and its repeat count must each be at most
`ImageSamplingPlan.maximumTilePhase` (4,096), with a two-ULP allowance for
representation roundoff. Nonlegacy source dimensions are limited to the
existing 16,384 surface-dimension bound. These are interim numeric
restrictions; they do not establish native limits or remove unsupported
inputs from the compatibility goal. A large admitted tile count still
uses one primitive and one source resource.

Unsupported nonfinite, negative, fractional, or oversized caps, nonpositive
centers, unsupported source regions, or excessive tile phase produce an
`ImageSamplingFailure`. The retained image exposes the last result through
`imageSamplingFailure`. That image contributes no paint for the failed
plan; siblings continue painting. Unsupported sampling does not silently
become ordinary stretch. A later valid update clears the failure and
reuses the retained bitmap node and its unchanged source content key.
The legacy frame renderer routes a frame that needs the new sampling
through its D3D11 path rather than dropping the descriptor in Direct2D;
frames using only legacy sampling keep their existing backend selection.

Current-target material passes require canonical legacy sampling on their
consuming image. Their replacement operation copies each composed child pixel
back to its original parent pixel; cap/tile remapping is rejected by shared
scene validation and before either backend acquires that parent region.
Independent image passes retain ordinary cap/tile sampling. This distinction
does not add cap/tile support to already-composited material output.

An outer fixed frame aligns an earlier image frame rather than enlarging
it again; competing smaller proposals remain subject to existing
frame-layout limitations. A frame alone does not establish a clip.
Explicit `.clipped()` still restricts drawing, while offsets, affine
placement, opacity, and presentation order remain separate from sampling.
No Canvas or demo-specific public API is needed.

The following remain open:

- Finite positive two-axis fit is an incremental implementation, not complete
  Image proposal negotiation. `scaledToFill` and `.fill` retain the existing
  preferred-size path; fill overflow and negative frame alignment need
  separate work. Unspecified, infinite, single-axis, zero, invalid-ratio,
  nonzero-minimum, fixed-size and competing-stack proposals remain
  unqualified. The retained constraint type does not distinguish SwiftUI's
  unspecified ideal proposal from infinity. Repeated typed Image aspect
  modifiers still overwrite one ratio/mode pair rather than nesting.
- Fractional caps, zero or negative center extents, undersized destinations,
  oversized caps, and tile phases beyond the admitted bound remain
  unsupported. Their native behavior has not been established.
- Asset density and source scale, orientation, right-to-left mirroring,
  interpolation and antialiasing modifiers, and native pixel/filtering
  parity remain unqualified. Current bitmap sizing uses one source pixel
  per logical unit; display scale alone is not asset-density support.
- System-symbol resizing remains on its existing icon path. Ideal-size,
  fixed-size, stack compression, asset-catalog, and full `Image` conformance
  are not established by this slice.

`WinSwiftUIBitmapStretchTests` remains unchanged and protects the existing
ordinary-stretch behavior: resource loading, independent axis scaling,
source bytes, intrinsic sizing, nested frames, clipping, scales 1 and 2,
reconciliation, and scene/frame/backend comparisons.
`WinSwiftUIBitmapResizingTests` adds source tests for partial zero-cap tiles,
nine distinct capped regions, asymmetric leading caps, transparent colored
edge filtering, scales 1, 1.25, 1.5, and 2, scene/frame propagation,
typed failures with sibling preservation,
reconciliation and recovery, and constant primitive/resource counts at the
tile-phase bound. It also specifies CPU/D3D11 comparisons through the
existing device-optional harness; a missing D3D11 device is a skip, not a
backend pass.

`WinSwiftUIBitmapAspectFitTests` specifies nineteen independent geometry and
preservation cases: wide and tall fits, an explicit ratio, shrinking,
alignment, generic and typed lowering, both orders of frame and fit,
reconciliation, fitted cap fractions and tile repeats, four display scales,
clipping, ordinary-stretch and intrinsic-size preservation, and the existing
tile-phase failure bound. Solid-color rectangles give exact independent
coverage expectations for scene and frame CPU output, including 72 pixels
for the 12-by-6 fit and 48 after the authored offset is clipped. Source bytes,
content keys, one-image presentation order and the 128-byte primitive ABI
are also asserted. The large phase-bound fixture emits records only, with
no destination raster allocation. The old preferred-size metadata tests
and all existing stretch, resizing and backend test bodies are unchanged.
These geometry expectations are analytic Windows oracles, not measured
native pixels or a new baseline.

Three fallback regressions preserve the prior centered-stack geometry under
`fixedSize`, an ordinary VStack's unbounded main-axis proposal, and repeated
finite/fallback reconciliation. A 12-by-8 fixed image frame followed by
ratio-1 fit, `fixedSize()` and a centered 20-by-20 frame keeps the old 8-by-8
image at `(6, 6)`; it does not regain the inner frame's declared width and
overflow to 12-by-8. These preserve existing Windows behavior outside finite
admission, without claiming native fixed-size or unbounded conformance.

At `a2cad23`, a fresh serial focused run passed all 20 resizing and stretch
XCTest methods with no failures or skips, including both D3D11 comparison
methods. The subsequent complete local Full run also passed. Two fixture
corrections preceded those runs: invalid caps are compared against the complete
sibling-only image, and the phase-limit test now uses a real 4097-point viewport
instead of a 24-point helper that clamped its requested size. Production
sampling, the 4096 phase limit, source bytes, ABI and tolerances did not change.
The runs and reviewed images are recorded in `goal.md`; native SwiftUI,
interpolation, legacy-frame placement and SDK conformance remain unqualified.

The nineteen new aspect-fit cases have not yet been compiled or executed on
this integration branch. The earlier a2 runs did not include them. No baseline
review flags are promoted. Run focused checks serially with the existing
architecture and formatting checks:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Filter WinSwiftUIBitmapStretchTests
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Filter WinSwiftUIBitmapResizingTests
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Filter WinSwiftUIBitmapAspectFitTests
```

The primary semantic reference is Apple's
[image sizing guide](https://developer.apple.com/documentation/swiftui/fitting-images-into-available-space)
and the documented
[scaledToFit alias](https://developer.apple.com/documentation/swiftui/view/scaledtofit%28%29/).
The inspected native reference catalog has no bitmap aspect fixture. Native
capture, fractional filtering, and full modifier-order behavior remain open.
In addition, a retained-scene or CPU frame result does not qualify the legacy
D3D11 frame bitmap path, whose canonical legacy placement still uses source
pixel dimensions. That backend limit is unchanged by this layout slice.
