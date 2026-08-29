# Bitmap placement in the frame presenter

`DrawBitmapCommand.placement` separates a requested logical destination from
an already completed device-pixel raster. Sampling mode does not identify
which placement is required. In particular, ordinary Image stretching uses
the canonical legacy sampler but still needs its full destination rectangle.

The default, `.destinationRect`, maps the entire source into `command.rect`.
Direct2D receives that rectangle in logical units; the D3D11 frame path
multiplies it by display scale. Neither replaces its size with the source
pixel dimensions nor rounds its origin separately. The bitmap bytes and
content key remain unchanged.

`.devicePixelRaster` is explicit. It means the source has already been
rasterized for this destination at the current display scale. The native
frame presenter rounds the scaled origin to the nearest device pixel and
uses the bitmap's physical width and height. Direct2D receives the equivalent
logical rectangle after dividing by display scale. This preserves the
existing text and vector fallback behavior, including rounded-up raster sizes.
For example, a logical rectangle `(10.25, 5.5, 18.8, 9.6)` with a 29-by-15
bitmap at scale 1.5 still draws at `(15, 8, 29, 15)` device pixels.

The four destination-producing kinds are:

- Retained bitmap leaves, including ordinary Image and native icon rasters.
- Canvas bitmap draws into an authored rectangle.
- Cached Canvas symbols reused at a requested destination without composing
  that destination into a new bitmap.
- A Canvas rejection checker expanded from its 2-by-2 source into a visible
  proposal or a bounded 16-device-pixel marker.

The four completed-raster kinds are:

- DirectWrite whole-string text rasters.
- GDI whole-string text rasters.
- Paths degraded into device-pixel bitmap commands.
- Canvas symbols whose affine placement has already been composed into a
  destination-sized device surface.

All eight constructors state their placement explicitly. A cached bitmap or
a native font raster is not automatically a completed destination: native
icons and cached Canvas symbols can still be scaled by their caller.
Code outside the repository that used implicit physical placement must now
specify `.devicePixelRaster`; source size, alpha format, and sampling fields
are not reliable substitutes for that intent.

## Typed refusal without losing sibling paint

A completed device raster requires the exact canonical `.legacy` descriptor.
Cap/tile remapping, an unknown sampling kind, or noncanonical kind-zero fields
with `.devicePixelRaster` produce the distinct typed reason
`BitmapPlacementFailure.devicePixelRasterRequiresCanonicalLegacySampling`.
This is a placement failure, not a sampler phase-limit failure.

Destination coordinates, extents, and endpoints also need to be finite and
representable by the renderer's Float geometry. Nonfinite input has the typed
reason `.nonfiniteDestinationGeometry`; finite values that overflow or lose a
nonzero extent when narrowed have `.unrepresentableDestinationGeometry`.
The native presenter checks the actual scaled D3D rectangle and the Direct2D
logical rectangle as well, so a valid logical input cannot overflow silently
when display scale is applied. These checks introduce no cap/tile budget or
integer rounding; the extent restriction is renderer representability. Representable
subpixel and large legacy rectangles retain their original geometry; finite
empty rectangles remain admitted but do not paint. A completed raster only
substitutes its physical source extent when both logical extents are positive;
zero or negative width or height stays empty in both native placement plans.
CPU bridge resource registration for an admitted empty draw is unchanged.

`frame.admittingBitmapPlacements()` returns a `FrameBitmapPlacementAdmission`
with an accepted frame and an ordered list of `FrameBitmapPlacementFailure`.
Each failure holds the command index from the original input and the typed
reason. Admission never mutates that input. It removes only rejected bitmap
commands; valid siblings and clip-stack commands keep their relative order.
The common valid path retains the original command array.

The CPU frame bridge and native frame presenter perform this admission at
their consuming boundary. It occurs before the bridge registers any rejected
image resource and before the native presenter expands paths, selects its
Direct2D/D3D11 branch, or uploads bitmap pixels. Each boundary reports once.
The bridge and raw frame rasterizer have overloads accepting a synchronous
typed failure observer; without one, reporting goes to stderr in debug and
release builds. Diagnostics include only the index and reason, never bitmap
bytes, text, or resource paths. No global UI state or logging callback is added.

This is explicit partial-frame behavior, not a successful rendering of every
input command. A caller that needs a retained structured result can inspect
the admission before handing its accepted frame to a renderer. Structural
validation of the accepted scene does not erase the original failure list.
The original bitmap initializer, nonthrowing bridge, and two-argument raw
frame rasterizer remain available, including as function values. The bitmap
initializer forwards to the explicit-placement overload with `.destinationRect`.
`CPUBatchRenderer.render(frame:)`
uses the same admitting bridge.

Other sampling admission and error policies are unchanged. Ordinary legacy
destination images do not acquire the cap/tile source-dimension or phase
limits. ImagePrimitive remains 128 bytes, BitmapUniforms remains 80 bytes,
and `GPUIScene.presentationOrder()` remains the scene ordering authority.

## Qualification limits

The CPU frame preview continues to interpret a completed raster's recorded
logical rectangle. It does not apply the native presenter's late device-pixel
placement. General HiDPI frame snapshots therefore remain unqualified; use
the retained scene path for display-density reference renders.

Filtering is also unchanged. Both native legacy-frame branches use point
sampling: Direct2D selects nearest-neighbor and the D3D11 frame bitmap shader
uses its POINT sampler. The CPU and D3D11 batch-scene image paths use linear
filtering. Nonlegacy cap/tile draws use their existing explicit sampling
kernel. Correct destination geometry alone does not establish filtering or
transparent-edge pixel parity.

`D3D11FrameBitmapPlacementTests` covers the actual preparation helper and
rectangle calculations, including empty extents in both placement modes,
without creating an HWND or drawing pixels.
`FrameBitmapPlacementAdmissionTests` covers typed failures, original indices,
unchanged input, callback delivery, accepted resources, CPU sibling pixels,
finite geometry and Float/scale overflow, empty-draw no-paint behavior, and the
preserved function signatures.
`FrameBitmapProducerPlacementTests`
covers the eight constructors plus the native icon distinction. The text
producer fixtures use seeded caches but still perform native measurement;
DirectWrite can explicitly skip when unavailable. They are not font-pixel
qualification.

These new tests were authored in a source-only session and have not been
compiled or executed in that session. Existing bitmap stretch and cap/tile
tests retain their assertions, numeric limits, source identity expectations,
and pixel tolerances. The old physical-raster half of
`D3D11ImageResizingTests` now requests that placement explicitly; its exact
1-by-1 expected output is unchanged.

Actual frame execution still requires separate evidence from both native
branches: an owned HWND and renderer-owned swap-chain readback, or a reviewed
internal seam that exercises the same drawing implementation. The public
frame renderer still rejects offscreen attachment. A batch-scene WARP result
or CPU frame snapshot is not evidence that either native frame branch ran.
No baseline or tolerance changes are part of this correction.
