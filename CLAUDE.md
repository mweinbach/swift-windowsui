# CLAUDE.md

This repo is building SwiftUI on Windows as a native Swift UI stack: SwiftUI-shaped app code on top of a retained runtime, a renderer-neutral frame/scene contract, a Win32 host, and a Direct3D presentation path. It is not a wrapper around native Win32 controls.

The rendering target is GPUI-inspired architecture in Swift, not a one-off demo renderer. Preserve the split between `WinSwiftUI` compatibility APIs, `RetainedViewRuntime` state/layout/focus/input behavior, `GPUIScene` paint records and typed primitives, and the D3D11 backend. If a change does not fit that stack, stop and rethink it before adding another abstraction.

## Non-Negotiable Architecture

- App code should look SwiftUI-shaped and import `WinSwiftUI` on Windows.
- Shared demo code must stay same-source compatible with macOS SwiftUI through the existing conditional import pattern.
- `Sources/SwiftWindowsUI/Runtime.swift` is the source of truth for retained layout, hit testing, focus traversal, clipping, frame caching, and animation behavior.
- UI-facing retained runtime, controls, host, and `WinSwiftUI` work is main-actor-centric.
- `GPUIScene.paintOperations` is the presentation-order paint stream. D3D11 and CPU screenshots must consume it so mixed primitive families keep retained runtime order.
- Family batches and typed primitive arrays are optimization/data-layout surfaces. They must not replace `paintOperations` for visible presentation order.
- Offscreen compositing and `drawingGroup` rendering must not poison outer-scene cache ranges. Preserve `ScenePainter.skipCacheUpdates` behavior.
- The screenshot path is raw retained runtime output through `swift-windowsui-snapshot` and `GPUIRawSceneRasterizer`. Do not bring back `CopyFromScreen` or foreground-window screenshots as validation.
- Keep renderer-neutral API changes coherent between `SwiftWindowsGraphics`, the CPU rasterizer, and `SwiftWindowsRendererD3D11`.
- Prefer extending `ViewBuildContext` and inherited style/environment propagation over adding global UI state.

## Agent Loop

Use the repo scripts from PowerShell. Do not run multiple SwiftPM commands against the same `.build` directory in parallel.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/agent-check.ps1 -ContractsOnly
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/agent-check.ps1 -Quick
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/agent-check.ps1 -Quick -Format
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/agent-check.ps1 -Full
```

Default workflow:

- Before editing architecture-sensitive code, run `scripts/agent-check.ps1 -ContractsOnly`.
- For Swift edits, run `scripts/lint.ps1` before finishing. It uses the toolchain `swift-format` against changed Swift files; use `-Path <file>` when the checkout already has unrelated dirty Swift files.
- For retained runtime, scene, renderer, or screenshot changes, run `scripts/agent-check.ps1 -Quick`.
- For visual or presentation changes, run the screenshot script and inspect `artifacts/demo-screenshot.png`.
- For release-quality validation, run `scripts/agent-check.ps1 -Full`.

## Cleanup Discipline

- Do not leave root-level build logs, test captures, screenshots, or ad-hoc scratch files.
- If temporary command output is needed, write it under `artifacts/` or the OS temp directory and remove it before finishing unless it is an intentional validation artifact.
- Generated screenshots belong under `artifacts/`; root-level `screenshot*.png` files are treated as junk.
- Before handing off, run `git status --short` and remove generated untracked files that are not source, tests, docs, or intentional tooling.
- Never clean by resetting or reverting user work. Only remove files that are clearly generated output.

## What Not To Do

- Do not make `SwiftWindowsScene` or `FoundationApp` the primary demo path.
- Do not bypass `WinSwiftUIWindowHost` or `RetainedViewRuntime` for app rendering.
- Do not sort primitive families independently for presentation if that can change mixed-family paint order.
- Do not update `ViewNode.cachedScenePaintRange` from temporary offscreen scenes.
- Do not replace the shared demo's SwiftUI-shaped `ForEach` usage with raw `for` loops inside `ViewBuilder` code.
- Do not solve Windows rendering bugs by adding platform-only APIs to demo source.
- Do not add docs-only architecture changes without a script, test, or contract check when the invariant is machine-checkable.

## Validation Map

- Shared logic: `scripts/test.ps1`
- Retained runtime: `scripts/test.ps1 -Filter RetainedViewRuntimeTests`
- Scene ordering and raw screenshots: `scripts/test.ps1 -Filter GPUISceneTests` and `scripts/test.ps1 -Filter SceneRasterizerTests`
- D3D11 scene planning: `scripts/test.ps1 -Filter D3D11BatchRendererTests`
- SwiftUI-shaped compatibility: focused `WinSwiftUI...Tests` classes, or full `scripts/test.ps1` when the Windows XCTest runner hits command length limits
- Executable wiring: `scripts/build.ps1 -Product swift-windowsui`
- Screenshot path: `scripts/demo-screenshot.ps1`
- Frame fallback comparison: `scripts/demo-screenshot.ps1 -FrameDebug -OutputPath artifacts/demo-screenshot-frame.png`
