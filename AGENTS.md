# AGENTS.md

This repository is a Windows-only custom-rendered UI toolkit prototype. Keep changes aligned with the retained runtime, the renderer-neutral frame contract, and the `WinSwiftUI` compatibility layer instead of inventing parallel abstractions.

## Project Shape

- `SwiftWindowsCore`: shared geometry, color, input, and surface types
- `SwiftWindowsGraphics`: `RenderBackend`, `RenderFrame`, `GPUIScene`, gradients, and draw commands
- `SwiftWindowsLayout`: stack layout primitives and experimental generic layout helpers
- `SwiftWindowsPlatform`: Win32 host, window delegate bridge, timer/input/message handling
- `SwiftWindowsUI`: retained `ViewNode` tree, runtime, controls, text plumbing, and legacy `FoundationApp`
- `SwiftWindowsRendererD3D11`: the concrete D3D11 backends used by the demo and frame fallback
- `WinSwiftUI`: SwiftUI-shaped app/view surface mapped onto the retained runtime
- `swift-windowsui`: executable that boots the demo through `WinSwiftUI`

## Core Mental Model

- The active demo path is `AppEntry.swift` -> `WinSwiftUI.App` / `WindowGroup` -> `WinSwiftUIWindowHost` -> `Win32Window` events -> `RetainedViewRuntime` -> `GPUIScene` -> `D3D11BatchRenderer`.
- The runtime is retained-mode and mutable. Prefer mutating `ViewNode` state and letting the runtime invalidate/re-render.
- `RenderFrame` is still the fallback renderer-neutral command list. The batch path uses typed scene primitives, device-pixel scaling, and a cached native glyph atlas with pixel-atlas fallback for icon glyphs.
- `SwiftWindowsScene` exists, but `GPUIScene` in `SwiftWindowsGraphics` is the primary scene path used by the demo.
- `LayoutNode` and `FixedLayoutBox` are present, but the running UI currently relies on `ViewLayoutMode` and `StackLayout`.
- `FoundationApp` still exists, but it is no longer the main demo bootstrap path.

## Editing Rules

- Treat `Sources/SwiftWindowsUI/Runtime.swift` as the source of truth for layout, hit testing, focus traversal, clipping, frame caching, and animation behavior.
- Keep UI-facing code on the main actor. `ViewNode`, `RetainedViewRuntime`, `Controls`, `WinSwiftUI`, and the demo app are all main-actor-centric.
- When changing `Controls.button`, preserve the focus/press/activate animation lifecycle unless the task explicitly changes interaction behavior.
- Remember that `PixelText.swift` / `PixelFontAtlas.swift` remain the icon/private-use fallback and the legacy frame-text path. The active batch scene path now prefers cached native glyph bitmaps, but there is still no full shaped-text system.
- If you add new visual features, consider whether they belong in the shared render graph first, not only in `D3D11Renderer`.
- If you change renderer behavior, keep the backend-neutral API in `SwiftWindowsGraphics` coherent with the implementation.
- If you change Win32 message handling, keep `WindowDelegate` callbacks and `KeyboardEvent` translation consistent with existing runtime expectations.
- When extending `WinSwiftUI`, prefer SwiftUI-shaped names and call-site compatibility over framework-specific convenience APIs.
- Preserve the same-source contract for the demo: the shared demo view/app code should stay usable with `import WinSwiftUI` on Windows and `import SwiftUI` on macOS.

## Validation

- Run `swift test` for shared logic changes.
- Run `swift test --filter RetainedViewRuntimeTests` when iterating on retained runtime behavior.
- Run `swift test --filter WinSwiftUITests` when iterating on the SwiftUI-shaped compatibility layer.
- Run `swift build --product swift-windowsui` for renderer, host, or demo-entry changes because the test target does not cover all executable wiring.
- Prefer a manual demo run for changes in `Win32Host`, `WinSwiftUIWindowHost`, `PixelText`, `D3D11BatchRenderer`, or `D3D11Renderer`.

## High-Value File Targets

- `Sources/WinSwiftUI/Core.swift`: shared aliases, modifiers, observation wrappers, and compatibility helpers
- `Sources/WinSwiftUI/Views.swift`: SwiftUI-shaped view/container/control mappings
- `Sources/WinSwiftUI/App.swift`: `App`, `Scene`, `WindowGroup`, and retained-runtime hosting
- `Sources/swift-windowsui/AppEntry.swift`: active demo entry point
- `Sources/swift-windowsui/DemoDashboard.swift`: shared-source demo screen
- `Sources/SwiftWindowsUI/Runtime.swift`: retained tree behavior plus frame/scene generation
- `Sources/SwiftWindowsUI/Controls.swift`: reusable retained control builders and animation hooks
- `Sources/SwiftWindowsUI/PixelText.swift`: bitmap text measurement and rasterization
- `Sources/SwiftWindowsUI/ScenePainter.swift`: `ViewNode` to `GPUIScene` translation
- `Sources/SwiftWindowsPlatform/Win32Host.swift`: native windowing and input translation
- `Sources/SwiftWindowsRendererD3D11/D3D11BatchRenderer.swift`: D3D11 batch pipeline, atlas upload, and scene presentation
- `Sources/SwiftWindowsRendererD3D11/D3D11Renderer.swift`: D3D11 pipeline, swap chain, scissor clipping, rounded rect shader

## Documentation Guidance

- Describe the project as a custom-rendered Windows UI toolkit, not as a wrapper around native Win32 widgets.
- Call out the retained runtime, renderer-neutral frame/scene generation, Win32 host, D3D11 batch presentation path, frame fallback, and the `WinSwiftUI` compatibility layer.
- Be explicit that the repository remains Windows-only even though shared app source can target SwiftUI on macOS.
- Mention current limits honestly: subset SwiftUI parity, bitmap/native text limits, and thin automated coverage for renderer/platform layers.
- Update `README.md`, `AGENTS.md`, and relevant files under `docs` with any significant compatibility or architecture changes.

## Docs

As you work, create and update documentation in the `docs` directory so usage and architecture stay current.

## Commits and Git

- Make commits as you go with clear messages so changes do not pile up.
