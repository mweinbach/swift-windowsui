# macOS reference parity workflow

How to produce macOS-side reference output for cross-platform visual
parity testing, and how to compare it against WinSwiftUI's Windows
output. Without this workflow, the "visual matching with macOS"
claim collapses to the design-constant contract in
`MacOSDesignParity.md` and `MacOSControlMetrics`. With it, the claim
extends to actual rendered output.

## What this gives you

`Sources/macos-reference-renderer/` is a standalone SwiftPM
executable target that has zero dependency on the Windows-only
modules (`SwiftWindowsRendererD3D11`, `WinSwiftUI`, etc.). On macOS
it imports SwiftUI / AppKit, builds canonical reference scenes
(button, toggle, slider, body text, system colors, default stack
spacing), and writes PNG snapshots to
`artifacts/macos-reference/`. On Windows it compiles to a stub that
prints an explanation and exits.

The renderer is intentionally tiny — six scenes that exercise the
parity claims most likely to drift between platforms: control
sizing, font metrics, system color rendering, and default layout
spacing.

## Running on macOS

```bash
swift run macos-reference-renderer
ls artifacts/macos-reference/
# button-regular.png  slider-mid.png       system-colors.png
# stack-default-spacing.png  text-body.png  toggle-on.png
```

The PNGs land in `artifacts/macos-reference/` (gitignored). They are
the gold reference.

## Running in CI

`.github/workflows/macos-reference-render.yml` runs the same
executable on a `macos-15` GitHub Actions runner and uploads the
PNGs as a workflow artifact (`macos-reference-png`, 30-day
retention). Triggered on:

- Push to the renderer source (`Sources/macos-reference-renderer/`).
- Manual `workflow_dispatch`.
- Weekly cron (Mondays at 06:00 UTC) so reference output tracks
  toolchain / SDK drift.

Download the artifact, drop it under `artifacts/macos-reference/`,
and run the Windows-side comparison.

## Producing the Windows-side equivalent

The Windows snapshot path is already in place via
`swift-windowsui-snapshot` and `scripts/demo-screenshot.ps1`. Each
of the six reference scenes has a 1:1 WinSwiftUI counterpart that
can be rendered via the existing `WinSwiftUIRendererSnapshotter`
infrastructure used by `Tests/.../VisualBaselineRegressionTests`.

The mapping is documented per-scene below. Scenes are intentionally
small (~120×64 px) so pixel-level inspection is tractable.

| Reference scene                  | WinSwiftUI counterpart                     |
|----------------------------------|--------------------------------------------|
| `button-regular`                 | `Button("OK")` with no modifier            |
| `toggle-on`                      | `Toggle("Enabled", isOn: .constant(true))` |
| `slider-mid`                     | `Slider(value: .constant(0.5))`            |
| `text-body`                      | `Text("Body 17 pt").font(.body)`           |
| `system-colors`                  | `HStack` of 13 system-color rectangles     |
| `stack-default-spacing`          | `VStack { Text("Row 1") … }`               |

## Comparison strategy

Compare each pair using:

1. **Geometric inspection** — using PNG decoders, locate the
   bounding box of any non-white content (the actual control) and
   assert width/height match within ±1 px. This is the strongest
   guarantee independent of font and GPU stack: "the control is the
   right size."

2. **Color sampling at landmark coordinates** — for the
   `system-colors` scene, sample the center pixel of each color
   swatch and assert the sRGB triple matches Apple's HIG value to
   within ±2/255 on each channel. Confirms color reproduction.

3. **Approximate structural similarity** (optional, requires a
   third-party PNG diff tool like `compare-png` or `imgsim`). Not
   pixel-perfect — DirectWrite vs CoreText anti-aliasing will
   differ — but useful as a soft-failure metric (>0.9 SSIM = OK).

**Pixel-exact comparison is explicitly NOT the bar.** Font
rasterization (DirectWrite vs CoreText), GPU gamma (D3D11 vs Metal),
display-scale snapping (1× vs Retina) all differ at the pixel
level. The claim WinSwiftUI proves with this workflow is "control
dimensions, font metrics, and system colors render to the same
geometry and palette as macOS." Pixel-perfect rasterization is not
achievable across SDKs and is not the goal.

## What's deliberately NOT in this workflow

- A pre-checked-in golden PNG set under `Tests/`. The reference is
  produced fresh on macOS each run because Apple's SDK is itself
  the source of truth and shifts with toolchain versions. Pinning a
  PNG would drift the moment Apple updates SF Pro.

- An auto-failure gate in Windows CI. The comparison is documented
  but not enforced — a soft contract. Pixel-level enforcement
  across font stacks is brittle, and the geometric / color contract
  is already enforced by `MacOSDesignParityTests` against documented
  constants.

## Why this is the right shape for "visual matching"

Cross-platform visual parity is fundamentally a contract over three
layers:

1. **Design constants** — pinned in `MacOSDesignParity.md` with
   `MacOSDesignParityTests` (fonts, system colors, materials,
   control chrome).
2. **Control dimension reference** — pinned in `MacOSControlMetrics`
   with `MacOSControlReferenceTests` (button heights, slider geometry,
   toggle switch, list rows, focus rings, layout spacing).
3. **Rendered-output reference** — produced by
   `macos-reference-renderer` on macOS, compared geometrically /
   colorimetrically against Windows output.

Each layer narrows the scope of "visual matching" from aspiration
to enforceable contract. The third layer was the previously-missing
piece — that this doc and the renderer target now close.
