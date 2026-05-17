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
- `agent-check.ps1 -Quick` runs contract checks, focused scene/renderer/runtime tests, and the demo executable build serially.
- `agent-check.ps1 -Full` runs full tests, builds the demo, and regenerates scene plus frame fallback screenshots.
- Do not run multiple SwiftPM test/build commands against this checkout in parallel; they share `.build/build.db`.
- Do not leave root-level logs or screenshots behind. Generated screenshots belong under `artifacts/`, and temporary logs should be deleted before handoff.

Focused test runs:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Filter RetainedViewRuntimeTests
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Filter WinSwiftUIWindowHostTests
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Filter GPUISceneTests
```

On Swift for Windows, filtering the very large `WinSwiftUITests` XCTest class can fail in the runner with Windows error 206 (`NSCocoaErrorDomain Code=258`). Use full `swift test` for that coverage, or filter narrower XCTest classes such as `WindowGroupInitTests`, `CommandsAndSceneTests`, or `ClipboardButtonTests`.

Visual checks:

- `scripts/demo-probe.ps1` launches the demo long enough to record presenter selection, then exits.
- `scripts/demo-screenshot.ps1` builds the shared demo view through `WinSwiftUIRendererSnapshotter`, pulls the raw retained runtime scene, rasterizes it offscreen, and writes `artifacts/demo-screenshot.png`.
- Add `-FrameDebug` to either command to force the `RenderFrame` fallback path.
- `demo-screenshot.ps1` does not depend on desktop window visibility, monitor placement, or foreground focus. It also leaves the raw BMP source next to the PNG as `*.raw.bmp` for inspection.
