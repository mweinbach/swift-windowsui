# Testing And Visual Checks

This repo uses first-class PowerShell scripts under `scripts/` for local Windows validation.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/with-swift.ps1 -CheckOnly
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/build.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/demo-probe.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/demo-screenshot.ps1
```

Focused test runs:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Filter RetainedViewRuntimeTests
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Filter WinSwiftUIWindowHostTests
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Filter GPUISceneTests
```

Visual checks:

- `scripts/demo-probe.ps1` launches the demo long enough to record presenter selection, then exits.
- `scripts/demo-screenshot.ps1` builds the shared demo view through `WinSwiftUIRendererSnapshotter`, pulls the raw retained runtime scene, rasterizes it offscreen, and writes `artifacts/demo-screenshot.png`.
- Add `-FrameDebug` to either command to force the `RenderFrame` fallback path.
- `demo-screenshot.ps1` does not depend on desktop window visibility, monitor placement, or foreground focus. It also leaves the raw BMP source next to the PNG as `*.raw.bmp` for inspection.
