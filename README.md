# swift-windowsui

`swift-windowsui` is a custom-rendered Windows UI toolkit prototype with a retained runtime, a renderer-neutral frame graph, a Win32 host, and a Direct3D 11 presentation backend.

The repo now also includes `WinSwiftUI`, a SwiftUI-shaped compatibility layer for the retained runtime. The demo app is written against that layer so the same demo source can be used in a macOS SwiftUI app by changing the import from `WinSwiftUI` to `SwiftUI`.

## What It Is

- A custom-rendered UI stack, not a wrapper around native Win32 widgets
- A retained `ViewNode` runtime with mutable state, layout, hit testing, focus, clipping, and animation
- A backend-neutral render path that mostly reduces visible UI to `FillRectCommand`
- A Windows-only implementation for the runtime/host/renderer layers today

## Same-Source Goal

The current portability target is shared app source, not full package portability.

- On Windows, app code can import `WinSwiftUI`
- On macOS, the same view/app source can import `SwiftUI`
- The demo in [`Sources/swift-windowsui/DemoDashboard.swift`](/D:/Projects/swift-windowsui/Sources/swift-windowsui/DemoDashboard.swift) stays inside that shared subset

Important limit:

- The repository itself is still Windows-only because `SwiftWindowsPlatform` and `SwiftWindowsRendererD3D11` depend on Win32 and D3D11

## Package Layout

Products:

- `SwiftWindowsUI`: retained runtime and controls
- `WinSwiftUI`: SwiftUI-shaped compatibility layer over the retained runtime
- `SwiftWindowsApp`: app shell and D3D11 wiring
- `swift-windowsui`: demo executable

Targets:

- `SwiftWindowsCore`: geometry, color, input, surface, and shared utility types
- `SwiftWindowsGraphics`: `RenderBackend`, `RenderFrame`, gradients, and render commands
- `SwiftWindowsScene`: alternate scene abstraction
- `SwiftWindowsLayout`: stack layout primitives and experimental generic layout helpers
- `SwiftWindowsPlatform`: Win32 windowing, input, timers, and delegate bridge
- `SwiftWindowsRendererD3D11`: Direct3D 11 renderer
- `SwiftWindowsUI`: retained `ViewNode` tree, runtime, controls, bitmap/native text plumbing, and `FoundationApp`
- `WinSwiftUI`: `App`, `Scene`, `WindowGroup`, common views/modifiers, observation wrappers, and the retained-runtime host bridge
- `swift-windowsui`: the demo app entry point and demo screen

## Active Demo Path

The running demo now goes through:

1. [`Sources/swift-windowsui/AppEntry.swift`](/D:/Projects/swift-windowsui/Sources/swift-windowsui/AppEntry.swift)
2. `WinSwiftUI.App` / `WindowGroup`
3. `WinSwiftUIWindowHost`
4. `Win32Window` delegate callbacks
5. `RetainedViewRuntime`
6. `RenderFrame`
7. `D3D11Renderer`

`FoundationApp` still exists, but it is no longer the primary demo bootstrap path.

## WinSwiftUI Coverage

The current `WinSwiftUI` surface is intentionally a subset. It is designed to cover the demo and common dashboard-style composition patterns first.

Included today:

- App hosting: `App`, `Scene`, `WindowGroup`
- Core views: `Text`, `Image(systemName:)`, `Label`, `Spacer`, `Group`, `GeometryReader`
- Containers: `VStack`, `HStack`, `ZStack`, `ScrollView`, `Section`, `HSplitView`, `VSplitView`
- Controls: `Button`
- Modifiers: `frame`, `padding`, `background`, `cornerRadius`, `border`, `shadow`, `layoutPriority`, `allowsHitTesting`
- Compatibility helpers: `Color(red:green:blue:opacity:)`, `Color.opacity(_:)`, `LinearGradient(colors:startPoint:endPoint)`, `UnitPoint`
- Shared-source support: `CGFloat`/`CGPoint`/`CGSize`/`CGRect` aliases and minimal `ObservableObject` / `Published` / `ObservedObject`

Current gaps:

- This is not full SwiftUI API parity
- Observation support is intentionally small and tuned for retained-runtime invalidation
- Text is still limited by the current runtime text system; bitmap text remains the baseline path

## Demo Source Compatibility

The demo files use a conditional import so the same source can compile in either environment:

```swift
#if canImport(SwiftUI)
import SwiftUI
#else
import WinSwiftUI
#endif
```

That is the compatibility contract to preserve when extending the demo.

## Build And Validate

Run from the repository root in PowerShell:

```powershell
swift test
swift build --product swift-windowsui
swift run swift-windowsui
```

Useful focused command:

```powershell
swift test --filter WinSwiftUITests
```

Verified in this pass:

```powershell
swift test
swift build --product swift-windowsui
```

The GUI demo was not manually launched in this pass.

## Important Files

- [`Sources/WinSwiftUI/Core.swift`](/D:/Projects/swift-windowsui/Sources/WinSwiftUI/Core.swift)
- [`Sources/WinSwiftUI/Views.swift`](/D:/Projects/swift-windowsui/Sources/WinSwiftUI/Views.swift)
- [`Sources/WinSwiftUI/App.swift`](/D:/Projects/swift-windowsui/Sources/WinSwiftUI/App.swift)
- [`Sources/swift-windowsui/AppEntry.swift`](/D:/Projects/swift-windowsui/Sources/swift-windowsui/AppEntry.swift)
- [`Sources/swift-windowsui/DemoDashboard.swift`](/D:/Projects/swift-windowsui/Sources/swift-windowsui/DemoDashboard.swift)
- [`Sources/SwiftWindowsUI/Runtime.swift`](/D:/Projects/swift-windowsui/Sources/SwiftWindowsUI/Runtime.swift)
- [`Sources/SwiftWindowsUI/Controls.swift`](/D:/Projects/swift-windowsui/Sources/SwiftWindowsUI/Controls.swift)
- [`Sources/SwiftWindowsPlatform/Win32Host.swift`](/D:/Projects/swift-windowsui/Sources/SwiftWindowsPlatform/Win32Host.swift)
- [`Sources/SwiftWindowsRendererD3D11/D3D11Renderer.swift`](/D:/Projects/swift-windowsui/Sources/SwiftWindowsRendererD3D11/D3D11Renderer.swift)

## Documentation

Additional framework notes live in [`docs/WinSwiftUI.md`](/D:/Projects/swift-windowsui/docs/WinSwiftUI.md).
