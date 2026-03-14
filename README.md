# swift-windowsui

`swift-windowsui` is a pure-Swift Windows UI toolkit prototype with a bundled demo application. It uses a retained `ViewNode` tree, resolves layout on the main actor, emits a renderer-neutral `RenderFrame`, and presents that frame through a Win32 host backed by Direct3D 11.

## What It Is

- A custom-rendered Windows UI stack, not a wrapper around native controls
- A retained-mode runtime with mutable view state, hit testing, focus, and color animation
- A minimal rendering pipeline built around a single shared primitive: `FillRectCommand`
- A Windows-only package today, using `WinSDK` and `WinSDK.DirectX`

The current demo renders a dashboard-style interface with rounded panels, focusable buttons, bitmap text, and animated interaction states.

## Package Layout

`Package.swift` defines one library product, `SwiftWindowsUI`, and one executable product, `swift-windowsui`.

### Targets

- `SwiftWindowsCore`: geometry, colors, input events, native window handles, and surface descriptors
- `SwiftWindowsGraphics`: the renderer contract and backend-neutral frame/command types
- `SwiftWindowsScene`: a small scene abstraction that can also build `RenderFrame` values
- `SwiftWindowsLayout`: stack layout types and a small generic layout protocol
- `SwiftWindowsPlatform`: Win32 window creation, message handling, timers, and input translation
- `SwiftWindowsRendererD3D11`: the Direct3D 11 renderer implementation
- `SwiftWindowsUI`: the retained runtime, controls, text rasterization, and demo app shell
- `swift-windowsui`: the demo executable entry point
- `SwiftWindowsCoreLogicTests`: logic-focused test coverage across the shared layers

## Runtime Architecture

The main path through the app is:

1. `Sources/swift-windowsui/main.swift` creates `FoundationApp(renderer: D3D11Renderer())`.
2. `FoundationApp` builds the demo `ViewNode` tree and owns the renderer, `Win32Window`, and `RetainedViewRuntime`.
3. `Win32Application.run(window:)` creates the native window and enters the Win32 message loop.
4. `Win32Window` translates resize, paint, pointer, keyboard, focus, and timer events into `WindowDelegate` callbacks.
5. `FoundationApp` forwards those events into `RetainedViewRuntime`.
6. `RetainedViewRuntime` resolves layout, performs hit testing, tracks hover/press/focus, and generates a `RenderFrame`.
7. `D3D11Renderer` clears the backbuffer, applies scissor clipping, draws rounded rectangles from `FillRectCommand`, and presents the swap chain.

In practice, nearly everything visible today eventually becomes filled rectangles. Borders, outlines, shadows, and even text are expressed through rectangle draws.

## UI Model

The main UI abstraction is `ViewNode` in `Sources/SwiftWindowsUI/Runtime.swift`.

- `ViewNode` stores frame, colors, text, borders, shadows, corner radius, focusability, hit testing, and event closures
- `RetainedViewRuntime` caches the last frame and invalidates when node state changes
- `ViewLayoutMode` supports `.absolute` and `.stack(StackLayout)`
- `Controls` provides convenience builders like `panel`, `stackPanel`, `label`, and `button`

Buttons are stateful retained controls. They are focusable by default and wire pointer/focus/activation callbacks into runtime-driven color animation.

## Text Rendering

Text is rendered by `PixelFont` in `Sources/SwiftWindowsUI/PixelText.swift`.

- It uses a built-in 5x7 bitmap font
- Characters are uppercased before rasterization
- Unsupported glyphs fall back to `?`
- Text ultimately emits more `FillRectCommand` values

This makes text predictable and portable, but it is intentionally much lower-level than a native text API.

## Rendering Details

`SwiftWindowsGraphics` defines a small backend boundary:

- `RenderBackend`
- `RenderFrame`
- `RenderCommand`
- `FillRectCommand`

`D3D11Renderer` in `Sources/SwiftWindowsRendererD3D11/D3D11Renderer.swift`:

- creates the D3D11 device and DXGI factory
- compiles an inline vertex shader and pixel shader
- creates a flip-model swap chain for the Win32 window
- draws a screen-aligned triangle-list quad per rectangle
- clips per command with D3D11 scissor rects
- uses shader math to discard pixels outside a rounded-rectangle distance field

If a frame clear color is `.clear`, the renderer falls back to a configured opaque clear color.

## Build And Run

Run commands from the repository root in PowerShell:

```powershell
swift test
swift build --product swift-windowsui
swift run swift-windowsui
```

Useful targeted test command:

```powershell
swift test --filter RetainedViewRuntimeTests
```

## Verified Locally

The following commands were run successfully during this documentation pass:

```powershell
swift test
swift build --product swift-windowsui
```

The GUI demo was not launched as part of this pass.

## Test Coverage

Current automated coverage is strongest in shared logic:

- `GeometryTests`: intersections, containment, inset clamping, and color interpolation
- `SceneTests`: scene-to-frame conversion
- `FoundationAppTests`: renderer attachment, resize wiring, invalidation, and demo frame creation
- `RetainedViewRuntimeTests`: stack layout, clipping-aware hit testing, focus traversal, pointer behavior, button state changes, and animation completion

The renderer and Win32 host are only lightly or indirectly covered. Changes to `SwiftWindowsRendererD3D11` or `SwiftWindowsPlatform` should be validated with an executable build, and ideally a manual run.

## Current Limits

- Windows-only implementation
- No native text API; text uses a bitmap font
- No automated GPU, swap-chain, or real Win32 event-loop tests
- `SwiftWindowsScene` and the generic `LayoutNode` APIs exist, but the main demo path goes through `RetainedViewRuntime`
- The demo UI is currently hardcoded in `FoundationApp`

## Where To Start

- For app bootstrap and demo wiring: `Sources/SwiftWindowsUI/FoundationApp.swift`
- For retained UI behavior: `Sources/SwiftWindowsUI/Runtime.swift`
- For reusable controls: `Sources/SwiftWindowsUI/Controls.swift`
- For text rendering: `Sources/SwiftWindowsUI/PixelText.swift`
- For platform integration: `Sources/SwiftWindowsPlatform/Win32Host.swift`
- For the renderer: `Sources/SwiftWindowsRendererD3D11/D3D11Renderer.swift`
