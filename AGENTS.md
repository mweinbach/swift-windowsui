# AGENTS.md

This repository is a Windows-only Swift UI prototype. Keep changes aligned with the retained runtime and the current renderer contract rather than inventing parallel abstractions.

## Project Shape

- `SwiftWindowsCore`: shared geometry, color, input, and surface types
- `SwiftWindowsGraphics`: `RenderBackend`, `RenderFrame`, and `FillRectCommand`
- `SwiftWindowsLayout`: stack layout primitives and experimental generic layout helpers
- `SwiftWindowsPlatform`: Win32 host, window delegate bridge, timer/input/message handling
- `SwiftWindowsUI`: retained `ViewNode` tree, runtime, controls, bitmap text, and `FoundationApp`
- `SwiftWindowsRendererD3D11`: the concrete D3D11 backend used by the demo
- `swift-windowsui`: executable that boots `FoundationApp(renderer: D3D11Renderer())`

## Core Mental Model

- The active UI path is `main.swift` -> `FoundationApp` -> `Win32Window` events -> `RetainedViewRuntime` -> `RenderFrame` -> `D3D11Renderer`.
- The runtime is retained-mode and mutable. Prefer mutating `ViewNode` state and letting the runtime invalidate/re-render.
- The shared render graph is intentionally tiny. Most visible features reduce to `FillRectCommand`.
- `SwiftWindowsScene` exists, but it is not the primary path used by the demo.
- `LayoutNode` and `FixedLayoutBox` are present, but the running UI currently relies on `ViewLayoutMode` and `StackLayout`.

## Editing Rules

- Treat `Sources/SwiftWindowsUI/Runtime.swift` as the source of truth for layout, hit testing, focus traversal, clipping, frame caching, and animation behavior.
- Keep UI-facing code on the main actor. `FoundationApp`, `Controls`, `ViewNode`, and `RetainedViewRuntime` are designed around `@MainActor`.
- When changing `Controls.button`, preserve the focus/press/activate animation lifecycle unless the task explicitly changes interaction behavior.
- Remember that text in `PixelText.swift` is uppercase bitmap text with `?` fallback. Do not assume full font shaping or native text measurement.
- If you add new visual features, consider whether they belong in the shared render graph first, not only in `D3D11Renderer`.
- If you change renderer behavior, keep the backend-neutral API in `SwiftWindowsGraphics` coherent with the implementation.
- If you change Win32 message handling, keep `WindowDelegate` callbacks and `KeyboardEvent` translation consistent with existing runtime expectations.

## Validation

- Run `swift test` for shared logic changes.
- Run `swift test --filter RetainedViewRuntimeTests` when iterating on retained runtime behavior.
- Run `swift build --product swift-windowsui` for renderer or platform changes because the test target does not cover `SwiftWindowsRendererD3D11`.
- Prefer a manual demo run for changes in `Win32Host`, `FoundationApp`, `PixelText`, or `D3D11Renderer`.

## High-Value File Targets

- `Sources/SwiftWindowsUI/FoundationApp.swift`: demo composition and app/window wiring
- `Sources/SwiftWindowsUI/Runtime.swift`: retained tree behavior and render-frame generation
- `Sources/SwiftWindowsUI/Controls.swift`: reusable control builders and animation hooks
- `Sources/SwiftWindowsUI/PixelText.swift`: bitmap text measurement and rasterization
- `Sources/SwiftWindowsPlatform/Win32Host.swift`: native windowing and input translation
- `Sources/SwiftWindowsRendererD3D11/D3D11Renderer.swift`: D3D11 pipeline, swap chain, scissor clipping, rounded rect shader

## Documentation Guidance

- Describe the project as a custom-rendered Windows UI toolkit, not as a wrapper around native Win32 widgets.
- Call out the retained runtime, renderer-neutral frame generation, Win32 host, and D3D11 presentation path.
- Mention current limits honestly: Windows-only, bitmap text, hardcoded demo UI, and thin automated coverage for renderer/platform layers.
- Make sure to update the 'README.md' and 'AGENTS.md' with any significant changes.

## Docs

As you work, create and update the documentation in the `docs` directory. Make sure it's organized and up-to-date and keeps us understanding how to use the toolkit.

## Commmits and Git

- Please make commits as you go with details on the change, so they do not pile up.
