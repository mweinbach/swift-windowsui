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

- `check-contracts.ps1` fails fast on architecture regressions that generic lint cannot see.
- `lint.ps1` runs `check-contracts.ps1` and then toolchain `swift-format lint --strict` against changed Swift files. Use `-Path <file>` when the checkout already has unrelated dirty Swift files, and use `-AllSwift` before broad cleanup branches or CI-style validation.
- `agent-check.ps1 -Quick` runs contract checks, focused scene/renderer/runtime tests (including the two WARP suites, `D3D11BatchRendererRenderTests` and `CrossBackendPixelParityTests`), and the demo executable build serially. Add `-GalleryCompare` to also run the gallery regression gate.
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
  glyph scene with no atlas must produce.
- `CrossBackendPixelParityTests` — canonical scenes rendered through both
  the D3D11 batch backend and `GPUIRawSceneRasterizer`, asserting at most 4
  per channel over at least 99.5 % of pixels. Scenes the backends genuinely
  disagree on are present but `XCTSkip`ped with the workstream that will
  unskip them and the measured match ratio; see
  `docs/GPURenderingPipeline.md` § 7 for the current divergence list.

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
