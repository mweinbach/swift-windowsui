# Ordinary bitmap stretch sizing

A decoded bitmap using `Image.resizable()` now accepts finite layout proposals
on both axes. For example, a 1-by-1 resource followed by
`.resizable().frame(width: 8, height: 8)` produces an 8-by-8 image destination.
The default stretch mode scales width and height independently; it does not
preserve the source aspect ratio automatically. This follows Apple's
[image-sizing guide](https://developer.apple.com/documentation/swiftui/fitting-images-into-available-space).

The facade leaves the bitmap's `preferredSize` unset and declares both retained
fill axes. The existing runtime still supplies the bitmap's intrinsic size
when no finite proposal is available. A nonresizable bitmap keeps its existing
intrinsic sizing path, including alignment inside a larger fixed frame.
No Canvas or demo-specific path participates in this change.

The source resource stays at its decoded dimensions. Scene construction emits
the ordinary `ImagePrimitive` at the resolved destination size; frame output
emits `DrawBitmapCommand` with that destination. CPU and D3D11 rendering use
their existing resource and clip contracts. Stretch does not pre-rasterize a
larger source bitmap. A larger outer fixed frame aligns the earlier stretch
frame rather than enlarging it again; competing smaller proposals remain
subject to the existing frame-layout limitations. A frame alone does not
establish a clip; an explicit `.clipped()` still
restricts drawing. See Apple's [clipping contract](https://developer.apple.com/documentation/swiftui/view/clipped(antialiased:)).

This correction applies only to bitmap images with `.stretch`, zero cap
insets, and no image aspect-ratio modifier. The following remain open:

- Image and generic-view `aspectRatio`, `scaledToFit`, and `scaledToFill` still
  use the existing preferred-size path. Complete proposal negotiation, fit
  bands, fill overflow, and modifier-order behavior require a separate layout
  correction; these modes must not be treated as unrestricted stretching.
- Tiling and nonzero cap insets retain metadata without tile or nine-slice
  rendering. System-symbol resizing stays on its existing icon sizing path.
- Complete ideal-size, fixed-size, stack compression, asset-catalog, image
  interpolation, and antialiasing parity are not established by this slice.

These gaps remain part of the full compatibility goal. This implementation
does not establish native image pixel parity or complete `Image` support.

`WinSwiftUIBitmapStretchTests` exercises the public image and modifier APIs:
resource loading, independent axis scaling, preserved source bytes, intrinsic
nonresizable sizing, nested fixed frames, explicit clipping, display scales 1
and 2, and reconciliation between intrinsic and stretch sizing. Separate
tests compare scene/frame CPU output and the existing D3D11 offscreen path;
the shared GPU harness reports a skip if no D3D11 device is available.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Filter WinSwiftUIBitmapStretchTests
```
