# Testing And Visual Checks

This repo uses first-class PowerShell scripts under `scripts/` for local Windows validation.
`scripts/with-swift.ps1` prepares the Swift for Windows environment by locating Visual Studio through the active environment, `vswhere`, or installed Visual Studio 18/2022 instances before adding the Swift toolchain, runtime, and SDK paths.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/with-swift.ps1 -CheckOnly
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/agent-check.ps1 -ContractsOnly
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/lint.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/agent-check.ps1 -Quick
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/build.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/demo-probe.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/demo-screenshot.ps1
```

## Agent Guardrails

Use these checks when making agent-driven changes:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/check-contracts.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/lint.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/lint.ps1 -AllSwift
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/agent-check.ps1 -Quick
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/agent-check.ps1 -Quick -Format
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/agent-check.ps1 -Full
```

- `check-contracts.ps1` fails fast on architecture regressions that generic lint cannot see. Besides the target dependency direction and the presentation-order rules, it pins the two single-implementation invariants a test cannot: `SceneRasterizer.swift` takes its coverage from `GPUIQuadCoverage`, declares no rounded-rect distance or smoothstep of its own, calls neither unqualified, and never answers coverage with a containment test against a sample point (WS-08); and `Runtime.swift` / `ScenePainter.swift` narrow clips only through `RuntimeClipShape.narrowed(to:)`, never with a bare `Rect.intersected(with:)` in any binding form — `guard let` and `if let` included (WS-16). A second copy of either rule is invisible to every pixel gate until it has already drifted. When editing these two rules, prove the edited pattern still fires: break the guarded file with a synthetic violation, run `check-contracts.ps1`, then `git checkout` the file and confirm the check is clean again. A rule that matches nothing passes silently forever.
- `lint.ps1` runs `check-contracts.ps1` and then toolchain `swift-format lint --strict` against changed Swift files. Use `-Path <file>` when the checkout already has unrelated dirty Swift files, and use `-AllSwift` before broad cleanup branches or CI-style validation.
- `agent-check.ps1 -Quick` runs contract checks, focused scene/renderer/runtime tests (including the two WARP suites, `D3D11BatchRendererRenderTests` and `CrossBackendPixelParityTests`, the pixel-format contract `PixelFormatContractTests`, and the device-loss suites `DeviceLostPolicyTests` / `DeviceLossRecoveryTests` / `PresentationFailurePolicyTests`), and the demo executable build serially. Add `-GalleryCompare` to also run the gallery regression gate.
- Four P1 invariant suites gate Quick as well: `ScenePresentationOrderTests` (the single draw-order authority), `SharedCoverageKernelTests` (the CPU/GPU coverage kernel), `CPUGPUBlendModeContractTests` (source-over on both paths) and `ClipAbstractionTests` (one clip value, one space). All four are cheap — 0.02 s to 0.4 s of test time each, ~2.5 s of wall clock apiece once the build is warm, since a `swift test` invocation dominates. The remaining P1 suites (`CPURasterizerGPUModelTests`, `PathRasterizationQualityTests`, `BorderCornerArcGeometryTests`, `TextShapingPipelineTests`) stay Full-only. Keep the Quick gate under ~10 minutes: measure a candidate before promoting it.
- `agent-check.ps1 -Full` runs full tests, builds the demo, regenerates scene plus frame fallback screenshots, and runs the gallery regression gate.
- Do not run multiple SwiftPM test/build commands against this checkout in parallel; they share `.build/build.db`.
- Do not leave root-level logs or screenshots behind. Generated screenshots belong under `artifacts/`, and temporary logs should be deleted before handoff.

Focused test runs:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Filter RetainedViewRuntimeTests
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Filter WinSwiftUIWindowHostTests
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Filter GPUISceneTests
```

On Swift for Windows, filtering the very large `WinSwiftUITests` XCTest class can fail in the runner with Windows error 206 (`NSCocoaErrorDomain Code=258`). Use full `swift test` for that coverage, or filter narrower XCTest classes such as `WindowGroupInitTests`, `CommandsAndSceneTests`, or `ClipboardButtonTests`.

## GPU Tests (WARP)

Every test that touches real D3D11 goes through the one harness in
`Tests/SwiftWindowsCoreLogicTests/WARPRenderHarness.swift`. It creates the
device WARP-first (the software rasterizer ships with every Windows install
and rasterizes deterministically across machines) and falls back to
hardware; when neither exists the helpers throw `XCTSkip`, so a machine
without D3D11 reports skipped GPU tests rather than failures.

Two levels:

- `makeWARPDevice()` plus `makeWARPOffscreenTarget(...)` / `readWARPPixels(...)`
  drive a single component against a bare `ID3D11Device` —
  `D3D11BackdropBlurTests`, `D3D11GlyphShaderPixelTests`.
- `WARPBatchRenderer.render(_:size:)` drives the real `D3D11BatchRenderer`
  frame path with no HWND, via `attachOffscreen(size:driver:)`, and reads
  the frame back. It caches one attached renderer for the whole test process
  (attaching compiles a dozen shaders), so scenes that bind images must use
  distinct texture IDs.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Filter "CrossBackendPixelParityTests|D3D11BatchRendererRenderTests"
```

- `D3D11BatchRendererRenderTests` — execution coverage for attach / resize /
  render / present: a 64→1920→1→4096 resize storm, zero-size and negative
  frames, repeated-frame stability, clear colour, and the typed error a
  glyph scene with no atlas must produce. Also the image-texture cache's
  live-set bound: content that changes every frame under one texture ID
  (an animating `.drawingGroup()`) keeps exactly one live texture, while a
  frame that renumbers its texture IDs keeps both and re-uploads neither.
- `CrossBackendPixelParityTests` — canonical scenes rendered through both
  the D3D11 batch backend and `GPUIRawSceneRasterizer`, asserting at most 4
  per channel over at least 99.5 % of pixels. Scenes the backends genuinely
  disagree on are present and asserted against a **measured match-ratio
  floor** rather than skipped: they fail if they drift below the recorded
  ratio, and they also fail with "promote me" if they reach the required
  ratio and should be gating like the rest. Re-measure a floor only when a
  deliberate change moves it, and record the new value with the reason; see
  `docs/GPURenderingPipeline.md` § 7 for the current divergence list — today
  that list is the two magnified sampler scenes (`magnified gradient glyph
  cell` at 0.835, `magnified high-contrast image` at 0.753), both owned by
  WS-18. Fixtures for the sampler families are deliberately hostile: a
  uniform opaque atlas cell or a gentle image gradient cannot observe a
  filtering difference at all.
- `PixelFormatContractTests` — the `BitmapSurface` format contract: the
  named default (BGRA, straight), the straight ↔ premultiplied conversions
  and their opaque fast path, the validation that rejects a truncated or
  under-strided surface before it reaches `CreateTexture2D`, and WARP
  readbacks proving red stays red, a half-transparent image composites to
  mid-gray, and an already-premultiplied surface is not multiplied twice —
  each cross-checked against `GPUIRawSceneRasterizer`.
- `AtlasUploadProtocolTests` — the atlas and texture upload protocol: the
  pure decision table (`skip` / `region` / `full`, including a fresh
  texture always taking `full` and a region only applying to the version
  it was computed against), the producers' content versioning, and the
  real upload counts on WARP — frame 1 fresh = one full upload, frame 2
  unchanged = zero, frame 3 with a small region = one boxed upload. Also
  pins image texture/SRV pointer identity across rebinds and across a
  frame that renumbers the texture IDs.
- `GlyphAtlasExhaustionSafetyTests` — an atlas rect handed out before a
  recovery addresses a different glyph after it, so no holder of one may
  outlive the recycle: the generation token only moves when shelves are
  recycled, a pass that recycles mid-flight re-emits its UVs, a working set
  larger than the atlas degrades to the pixel font instead of shipping UVs it
  cannot vouch for, the suspension does not outlive the degraded frame, and a
  runtime's *cached scene* is dropped when another window recovers the shared
  atlas under it (a clean window never repaints on its own, so the token is
  the only thing that can force it).
- `RenderBackendLifetimeTests` — GPU resource lifetime: `detach()` empties
  every stored COM pointer, the image map and the path cache; attach →
  detach → attach round-trips draw the identical frame on a fresh device;
  repeated cycles do not accumulate; and the host calls `detach()` on
  window close and on both directions of a presenter switch, always before
  the incoming backend claims the HWND. Attaches its own WARP renderer
  rather than the shared `WARPBatchRenderer`, since it destroys the device.
- `DeviceLostPolicyTests` — the HRESULT classifier and retry schedule, with
  no GPU involved: device-lost codes, `DXGI_STATUS_OCCLUDED` as throttle
  rather than clean present, permanent vs transient, bounded monotonic
  backoff, and each backend error type classifying itself for the host.
- `DeviceLossRecoveryTests` — the rebuild itself, driven through
  `simulateDeviceLossForTesting()` on an offscreen WARP renderer: a new
  device generation, the target rebuilt at the same size with matching
  pixels, a bounded budget that surfaces a typed `.deviceLost` failure, a
  clean present refunding it, and the backdrop-blur engine keyed on
  generation rather than device address. Attaches its own renderer and stubs
  the recovery wait, so the suite does not sleep.
- `PresentationFailurePolicyTests` — the host half: the failure kind reaches
  `RendererHealthSnapshot`, a `.permanent` failure schedules no recovery, an
  unclassified error keeps the historical transient behaviour, and a backend
  reporting `needsImmediateRepaint` keeps the frame loop alive.
- `SoftwarePresentationTests` — the GPU-less startup path end to end through
  the host seams: the substituted software backend actually blits a frame
  (right size, right clear-colour bytes, right client size) instead of
  rasterizing into memory, `render` never returns without presenting, a failed
  blit reaches the fallback policy and health rather than reading as a healthy
  scene session, and `RendererHealthSnapshot.backendResolution` separates
  healthy hardware from WARP from a substituted factory. Includes one real-HWND
  `StretchDIBits` blit, skipped where a top-level window cannot be created.
- `FrameClockPacingTests` — the frame clock and the pacing floor: the clock is
  monotonic and resolves inside a system tick, the floor sits strictly below
  the vsync period, a 15.625 ms-quantized tick sequence renders ≥ 55 frames per
  simulated second at 60 Hz, two rebuilds cannot share one vsync interval, and
  `WM_PAINT`-driven frames carry the host clock rather than `0`.
- `BatchRecoveryBackoffTests` — the recovery ladder: 5 → 10 → 20 → 40 → 60 s
  carried across downgrades instead of resetting, retired only by a sustained
  run of presented scene frames, with a `.sceneContent` failure never retried
  against an unchanged tree and `.permanent` scheduling nothing.
- `WindowConfigurationDPITests` — window creation and configuration: creation
  geometry linear in DPI and independent of the frame inset, the logical root
  equal to the requested size at 2×, one clamped effective scale for every
  consumer (hit testing round-trips at 0.75), track sizes / fixed size /
  placement / level translation, a 100-message drag costing ≤ 1 display-mode
  query, and an unchanged appearance snapshot triggering no reload.
- `ClipAbstractionTests` — the one clip value and the one space it lives in:
  the narrowing rule (anchored rounding, cut corners squared, an empty clip
  distinct from an absent one, per-corner radii floored like the uniform
  scalar), both halves of the in-band encoding (`encode` emits `emptyExtent`
  for a collapsed rect instead of the all-zero *absent* sentinel), rounded
  clips reaching the glyph / image /
  shadow / path families, and clip-space coherence under a transform — the
  interactive region of a rotated clip pixel-for-pixel equals its painted
  region, a deferred subtree under a translating clip paints where its clip
  moved, the frame path's border gate is the frame it paints, every clip
  prepaint records is `.painted`, and a rotation nested inside a translated
  and scaled ancestor survives on the frame path — the case a single
  transform hides, because only there do "the node's own transform" and "the
  accumulated transform" differ.
- `ScrollIndicatorTransformSpaceTests` — the two spaces a scroll indicator
  lives in: thumb length is the layout-space visible fraction, thumb position
  and drag rate are painted space, and the untransformed geometry every other
  indicator test pins is unchanged.
- `ScenePresentationOrderTests` — the single draw-order authority, plus
  replay integrity at the painter: a range rejected rather than trapped, a
  rejection answered by repainting instead of caching the emptiness, a
  subtree wrapped and then unwrapped from a `drawingGroup` replaying its own
  primitives rather than whatever moved into its old indices, and a fully
  replayed text frame CPU-rasterizing to the same pixels as the frame it
  replays (it has to ship the atlas its glyph quads address, even though it
  rasterized no glyph). Also the cost of the ordering machinery: a paint
  record stays a reference rather than a second copy of the primitive, and
  sealing plus planning a 5,000-quad / 10,000-glyph scene stays under an
  eighth of what inserting the same primitives cost — a *relative* budget,
  so a slow runner moves both sides together instead of flaking. It rejects
  even one heap allocation per primitive in the sealed phase, so the retired
  per-primitive sort in `finish()` cannot come back unnoticed.
- `TextMeasurePaintFidelityTests` — measured width == painted width for
  native text at fractional scales, and the same equality for *tracked*
  text, where measurement and painting have to count the same inter-glyph
  gaps. Its combining-mark fixture asserts that it still shapes into a
  different glyph count than character count, so it fails loudly rather
  than passing for the wrong reason.
- `TextShapingPipelineTests` — WS-17's pipeline end to end: shaped glyph
  identity (a real `DWRITE_GLYPH_RUN`, not a per-character hit-test walk),
  the two glyph coordinate frames and the raster declaring which one it
  measured ink from, the `Double → Int32` conversions that return `nil`
  instead of trapping on a non-finite frame, `FontFaceRegistry` handing out
  stable monotonic identifiers and reporting when its retained set stops
  being bounded, tracking moving measurement and paint together, and the
  galloping wrap probe staying linear on a 20,000-character space-less
  paragraph. Needs a real DirectWrite; the cases that would silently pass
  without one assert the layout came back first.
- `SharedCoverageKernelTests` — `GPUIQuadCoverage`, the one Swift
  transcription of the quad shader's coverage math, compared on a dense
  sample grid against a *third* copy transcribed line-by-line from the HLSL
  in the test itself. Uniform and per-corner radii, the box-SDF ramp a
  square quad must get (there is deliberately no `radius == 0` short
  circuit), the rasterizer's own centre-coverage rule, and a rounded clip
  producing fractional alpha where an exact rect rejection would not.
  Editing one side of the pair without the other fails here; that the pair
  matches the *running* shader is pinned by `CrossBackendPixelParityTests`.
- `CPURasterizerGPUModelTests` — what the reference renderer models: the
  shadow envelope and falloff, the material composite and its shared blur
  cap, `luminanceToAlpha` ordering, and the glyph sampler's alpha
  convention (coverage is `.a`, exactly as the shader reads it).
- `PathRasterizationQualityTests` — path fill and stroke quality, which is
  not a fallback-only concern: the D3D11 path texture cache calls
  `GPUIRawSceneRasterizer.rasterizePath` and uploads the result, so this is
  the shipping appearance of `Canvas`, `Shape` strokes, chart lines and the
  SF-symbol vector fallback. Implicit per-subpath closure (SwiftUI's fill
  semantics), non-zero winding on a self-overlapping shape, fractional
  coverage on a diagonal edge, a translucent polyline never exceeding its
  single-segment alpha, no gap at a thick join, a stroke *not* closing an
  open subpath, and the path clip rejecting per pixel centre.
- `BorderCornerArcGeometryTests` — the corner-arc geometry `BorderSegments`
  emits for a rounded border, measured in all four quadrants rather than
  the one whose maths was right. The annular-sector bounding box used to be
  computed as if the ring's outer edge always lay at `+x`/`-y`, so three
  corners came out narrower than the ring by the border width and the
  sub-boxes nearest the straight edges inverted and were dropped: a rounded
  border on a container with children rendered thin or gapped. Asserts ring
  coverage at each 45° midpoint, the arc union spanning the whole corner
  square, areas and counts agreeing across quadrants, no sub-arc inverting,
  and full-width and dashed borders still emitting every corner.
- `CPUGPUBlendModeContractTests` — source-over, and only source-over, on
  **both** paths: every mode rasterizes as `.normal` on the scene path and
  on the frame path, a `.multiply` overlay matches on WARP, and the mode
  still survives onto `QuadPrimitive.blendMode` — through the painter and
  through `GPUISceneBridge` — so the decision stays reversible. Landing the
  opposite decision means implementing the modes on the GPU and deleting
  this suite.
- `SystemAppearanceTests` — sampling, the mapping tables, and the
  settings-change routing: the generic high-frequency broadcasts
  (environment, policy) are filtered when the four-field snapshot did not
  move, while metrics/font/theme/locale broadcasts and `WM_SYSCOLORCHANGE`
  reach the delegate unconditionally — they change what the app draws from
  and the snapshot does not carry them. Every route re-samples, filtered or
  not, so a filtered broadcast never leaves a stale snapshot cached. It also
  covers the hostile side of `WM_SETTINGCHANGE`: `lParam` is a pointer only
  by convention and is marshalled only for the `SendMessage` family, so any
  process can `PostMessage(HWND_BROADCAST, …)` an arbitrary value into it.
  `Win32Window.settingChangeSection` validates the address with
  `VirtualQuery` before reading it — null, misaligned, reserved-but-
  uncommitted, `PAGE_NOACCESS` and a name running off the end of a committed
  page all classify as "no section" rather than faulting the UI thread — and
  the tests drive each of those through `VirtualAlloc`. A `wParam` allow-list
  is deliberately *not* the gate: `ImmersiveColorSet` arrives with
  `wParam == 0`, so allow-listing would drop the dark-mode switch while
  leaving the forgeable case dereferencing a raw address.
- `IconDisplayScaleTests` — icon rasterization at a requested scale, scale-1
  byte-identity, and who may write the process-global
  `NativeTextRenderer.defaultIconDisplayScale`: the sole live host writes it
  on activation and on every resize, a second live host cannot stomp it, and
  claims are weak so a closed window releases it.

Test runs never write images into the source tree: `check-contracts.ps1`
fails if a `ReferenceImages` directory appears under `Tests/`. Reviewed
baselines live in the gallery gate and the golden-hash suites.

Visual checks:

- `scripts/demo-probe.ps1` launches the demo long enough to record presenter selection, then exits.
- `scripts/demo-screenshot.ps1` builds the shared demo view through `WinSwiftUIRendererSnapshotter`, pulls the raw retained runtime scene, rasterizes it offscreen, and writes `artifacts/demo-screenshot.png`.
- Add `-AllScreens` to `demo-screenshot.ps1` to capture all three demo tabs in one run: `artifacts/demo-screenshot-dashboard.png`, `artifacts/demo-screenshot-settings.png`, and `artifacts/demo-screenshot-data.png`. Default behavior (a single dashboard shot) is unchanged.
- The underlying `swift-windowsui-snapshot` executable also accepts `--screen <dashboard|settings|data>` to render a single non-default tab directly; the default is `dashboard`.
- Add `-FrameDebug` to either command to force the `RenderFrame` fallback path.
- `demo-screenshot.ps1` does not depend on desktop window visibility, monitor placement, or foreground focus. It also leaves the raw BMP source next to the PNG as `*.raw.bmp` for inspection.

## Gallery Regression Gate

`scripts/gallery-compare.ps1` turns the `swift-windowsui-gallery` tool into a visual regression gate for Supported-tier controls.

- The gate covers a fixed subset of gallery entries (buttons, toggles, sliders, stepper, picker, progress views, text fields, list/form chrome — 25 entries). The list lives at the top of `scripts/gallery-compare.ps1`. Animation-, focus-, and time-dependent entries (e.g. indeterminate progress) are deliberately excluded because their renders are not frame-stable.
- Checked-in baselines live in `tests/fixtures/gallery-baselines/` as compact PNGs. The rest of `artifacts/gallery/` stays generated-only.
- A compare run re-renders the subset into `artifacts/gallery-compare/current/` and computes bounded per-entry diffs. A pixel counts as changed when any B/G/R/A channel differs by more than `-ChannelTolerance` (default 8). An entry fails when changed pixels exceed `-MaxChangedPercent` (default 0.5%) or any single channel delta exceeds `-MaxChannelDelta` (default 64). Missing baselines and canvas-size changes always fail. The raw-scene CPU rasterizer is deterministic, so unchanged code should produce 0% diffs.
- Failures write red-overlay diff images to `artifacts/gallery-compare/diffs/` and a summary to `artifacts/gallery-compare/report.txt`; the script exits non-zero.
- The gate runs as part of `agent-check.ps1 -Full` (and therefore in the Full stage of Windows CI, with the compare output uploaded as the `windows-gallery-compare` artifact). It is opt-in for Quick runs via `agent-check.ps1 -Quick -GalleryCompare`.

```powershell
# Compare against baselines (fails on meaningful regression)
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gallery-compare.ps1

# Regenerate baselines after an intentional visual change; review the PNGs before committing
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gallery-compare.ps1 -UpdateBaselines
```

The gallery executable also accepts `--entries <csv>` and `--output-dir <path>` for ad-hoc filtered renders; with no arguments it keeps rendering the full gallery to `artifacts/gallery/`.
