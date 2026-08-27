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

The PNGs land in `artifacts/macos-reference/` (gitignored). They are native
capture candidates; review the capture method and toolchain provenance before
using them as comparison evidence.

## Running in CI

`.github/workflows/macos-reference-render.yml` runs the same
executable on a `macos-15` GitHub Actions runner and uploads the
PNGs as a workflow artifact (`macos-reference-png`, 30-day
retention). Triggered on:

- Push to the renderer source (`Sources/macos-reference-renderer/`).
- Manual `workflow_dispatch`.
- Weekly cron (Mondays at 06:00 UTC) so reference output tracks
  toolchain / SDK drift.

This workflow selects a compatible toolchain available on `macos-15`; it does
not select the pinned SDK in [SwiftUIBaseline.md](SwiftUIBaseline.md). Its
observations do not qualify that baseline, and no SDK pin is changed by this
workflow. Baseline capture, native behavioral review, and Windows/backend
comparisons remain separate evidence.

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

## Material capture diagnostics

The optional diagnostic mode preserves the six canonical top-level PNGs:

```bash
swift run macos-reference-renderer --self-test-material-diagnostics
swift run macos-reference-renderer --material-diagnostics
```

The first command exercises portable synthetic classifier and report metadata
checks and works on Windows too. Those values are not native observations. The
second command requires macOS and writes a unique run directory under
`artifacts/macos-reference/material-diagnostics/`, containing a JSON manifest
and two PNG captures of each fixture:

| Fixture | Purpose |
| --- | --- |
| `pattern-control` | Verify scale, orientation, contrast, and opaque background capture |
| `flat-tint-control` | Show the contrast attenuation caused by ordinary white at 0.4 opacity |
| `material-direct-control` | Establish whether the capture represents spatial filtering by ordinary regular material |
| `material-compositing-group` | Observe that material inside a `ZStack` followed by `.compositingGroup()` |
| `material-drawing-group` | Observe `.drawingGroup(opaque: false, colorMode: .nonLinear)` |
| `material-content-blur` | Observe `.blur(radius: 3, opaque: false)` |

All fixtures use public SwiftUI views, a 384 by 288 point frame, an explicitly
allocated 768 by 576 pixel bitmap, light appearance, and a fixed panel over a
patterned background. Four-point stripes occupy the upper half; broad dark and
light regions occupy the lower half. The panel remains inside the isolation
wrapper, and the patterned backdrop remains outside it. There are no fonts,
assets, system dialogs, or authored animations in the fixture.

The helper captures an **unattached** `NSHostingView` with
`cacheDisplay(in:to:)`; it never captures a desktop or window. It allocates and
clears a fixed bitmap, converts it to sRGB, encodes PNG, and measures the decoded
PNG. Each capture follows layout and a 50 ms main-run-loop opportunity, with
two repetitions. This is a bounded settling policy, not proof of compositor
completion. [Apple's capture documentation](https://developer.apple.com/documentation/appkit/nsview/cachedisplay(in:to:))
does not guarantee that every compositor-backed effect appears in a view cache.

The positive control measures fine-pattern contrast relative to coarse-pattern
contrast, normalized to the bare pattern. A flat tint should attenuate both
frequencies similarly, with a measurable dark-region brightness increase and
contrast attenuation proving that the overlay itself was captured. Fine contrast
uses twice the standard deviation of all fine-region pixels, so a sharp pattern
shift cannot masquerade as blur by cancelling pooled stripe phases. Separate
phase means validate the bare pattern's expected eight-pixel stripe grid.
Ordinary material must preserve measurable coarse
background variation while attenuating the fine pattern substantially more.
The manifest records the exact sample regions, measurements, threshold version,
and thresholds used by the classifier. These thresholds validate the capture
diagnostic; they are not invented native material colors or conformance tolerances.

Failed/missing controls, opaque or transparent output, insufficient coarse
contrast, wrong orientation/scale, and unstable control repetitions yield
`positiveControlStatus: "inconclusive"` with reasons. The PNGs and individual
observations remain available. A valid but inconclusive run exits successfully;
allocation, conversion, encoding, measurement, or file failures exit nonzero
after preserving the report where possible. No group is assigned a native
pass/fail expectation. Even a passing direct control does not prove capture
fidelity through every wrapper, because grouping can change layer realization.

The manifest includes actual OS/build, architecture, capture-time Xcode/Swift/SDK
information, source commit and tracked checkout state, executable/PNG hashes,
requested/effective appearance, accessibility settings, capture method, modifier
order, and repetition results. Capture-time tool versions are not an embedded
binary build identity; CI logs supply the build linkage. System accessibility
settings are recorded, never changed to force a passing result.

Each capture's `captureProvenance` also records `NSWorkspace` accessibility flags
before and after its synchronous cache/encode/measurement attempt, together with
application activation/visibility, host attachment/visibility, and backing geometry.
The original top-level `systemAccessibility` remains an end-of-run sample; it does
not establish what was enabled during an earlier capture. A transparent SwiftUI
probe inside the fixture's existing light/2x environment records effective Reduce
Transparency, Reduce Motion, color scheme/contrast, and display scale when its
body evaluates. Its snapshots include the evaluation count and time: unchanged
counts mean a reused observation, and an unevaluated probe reports `unobserved`
with null values. These observations are separate from system preferences and
cannot establish what the compositor used. Missing host windows/layers are not
reported as observed visibility or backing values.

After each attempt, the helper records only the format and dimensions returned by
`bitmapImageRepForCachingDisplay(in:)`, or an explicit `unavailable` result. The
recommended bitmap is never rendered into or substituted for the existing fixed
2x bitmap. No window is created, no accessibility setting is changed, and neither
the settling policy nor the control thresholds change. Additional provenance
alone cannot turn an inconclusive material control into a positive one.

The existing `macos-15` workflow runs these diagnostics after the canonical
captures and uploads `macos-material-diagnostics-candidate`, including JSON.
It retains the **candidate-only** classification regardless of the controls'
outcome. Pinned-SDK execution and reviewed native behavior are still required
before changing the material isolation contract or removing the existing skipped
renderer regression. No production renderer, reviewed baseline, or SDK pin is
modified by this diagnostic.

The pinned `swiftui-baseline-capture.yml` job also runs these unchanged public
fixtures, serially after a successful SDK export, through
`scripts/capture-swiftui-material-reference.ps1`. Its material step has a 15 minute
limit inside the existing 90 minute job; the wrapper reserves time for failure
evidence with a 13 minute internal command budget. It uses the captured absolute
XcodeDefault Swift executable, verifies its SHA256 and the live SDK settings
against the export, and builds the release product in a fresh owned temporary
SwiftPM scratch directory. It never reuses the repository's `.build` directory.
The same executable runs the synthetic self-tests and then the native captures.
Inherited compiler/SDK/driver overrides are rejected, as are untracked or ignored
target sources and package configuration. Source and capture hashes are rechecked
after execution. This closes the gap between the recorded commit/tool and what
SwiftPM actually selects; [SwiftPM permits environment compiler overrides](https://github.com/swiftlang/swift-package-manager/blob/swift-6.3-RELEASE/Sources/PackageModel/UserToolchain.swift).

`artifacts/swiftui-baseline/github-actions/material/context.json` links the
material manifest and executable hashes to `capture/capture.json` and the exact
baseline manifest hash. It verifies the completed export status/digest, copied
manifest, live compiler/SDK identity, clean source commit, actual OS version and
build, and native Intel architecture. Only small metadata files are read; this
step does not load or reinterpret the SDK's large `inventory.json`. The original
SDK `ci-context.json` still describes only the export step.

The existing always-upload artifact includes the material context, command
outputs, and every newly produced diagnostic PNG/manifest, also when controls are
inconclusive or later provenance validation fails. Operational failures fail the
step; a complete valid `inconclusive` result remains a preserved candidate. The
sidecar records whether the captured environment matched, separately from
`nativeRuntimeBuildReviewed`, `nativeBehaviorReviewed`, and `releaseQualified`,
which remain false. Running on `macos-26-intel` does not review that observed OS
build, establish arm64 native behavior, populate reviewed build pins, or qualify
SwiftUI conformance. The SDK's two inventory targets do not supply two native
rendering observations.

`scripts/test-swiftui-material-reference.ps1` checks provenance rejection and
inconclusive-result preservation with synthetic files on Windows or macOS. It
does not produce or validate native pixels. The native spatial-filtering positive
control still has to succeed before these observations can inform any review of
material grouping; even then each wrapper needs its own review.
