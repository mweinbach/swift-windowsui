# WinSwiftUI

`WinSwiftUI` is the SwiftUI-shaped layer for the retained Windows runtime.

Its job is not to imitate SwiftUI internally. Its job is to let app code use a familiar SwiftUI-style surface while mapping directly into:

- `RetainedViewRuntime`
- `ViewNode`
- `GPUIScene`
- `Win32Window`
- `D3D11BatchRenderer`

The active demo path now prefers `GPUIScene` -> `D3D11BatchRenderer`. The
older `RenderFrame` -> `D3D11Renderer` route remains available as a fallback
for explicit opt-out and frame-graph compatibility.

## Goal

The intended workflow is:

- Windows app code imports `WinSwiftUI`
- macOS app code imports `SwiftUI`
- shared view/app source stays the same aside from that import

That is why the demo source uses:

```swift
#if canImport(SwiftUI)
import SwiftUI
#else
import WinSwiftUI
#endif
```

## Current Surface

App/scene hosting:

- `App`
- `Scene`
- `WindowGroup`

Views and containers:

- `Text`
- `Image(systemName:)`
- `Label`
- `Spacer`
- `Group`
- `GeometryReader`
- `VStack`
- `HStack`
- `ZStack`
- `ScrollView`
- `Section`
- `HSplitView`
- `VSplitView`
- `Button`

Modifiers:

- `frame`
- `padding`
- `background`
- `cornerRadius`
- `border`
- `shadow`
- `layoutPriority`
- `allowsHitTesting`

Compatibility helpers:

- `Color(red:green:blue:opacity:)`
- `Color.opacity(_:)`
- `LinearGradient(colors:startPoint:endPoint)`
- `UnitPoint`
- `CGFloat`, `CGPoint`, `CGSize`, `CGRect` aliases
- minimal `ObservableObject`, `Published`, and `ObservedObject`

Surface direction:

- default retained buttons now use lighter rounded chrome with hover, focus, press, and activation transitions
- the demo’s cards and chips are built from shared-source-friendly layered gradients and translucent strokes rather than WinSwiftUI-only styling hooks

## Mapping Notes

- `Text` maps into retained label nodes and the current text renderer path.
- `Image(systemName:)` maps known SF Symbol names into the project icon set.
- `Image(systemName:)` currently resolves to retained icon labels that render through the scene glyph atlas or the frame fallback text path.
- `Button` maps into retained button controls and preserves focus/press/activate animation state.
- `Button` now also resolves hover-aware border and shadow states so retained controls feel closer to modern desktop/mobile system chrome.
- `ScrollView` maps into retained scroll panels with indicator state handled in the runtime.
- `HSplitView` and `VSplitView` map into the retained split-view control and can infer an initial ratio from content.
- `GeometryReader` uses the current build context canvas size.

## Observation Model

`WinSwiftUI` now supports a minimal SwiftUI-style observation path for shared source:

- `ObservableObject`
- `@Published`
- `@ObservedObject`

Observed object changes are coalesced by the host before rebuilding the retained tree so one logical update does not trigger multiple immediate redraw passes.

This is intentionally small. It exists to support shared app source and runtime invalidation, not to reproduce the full SwiftUI observation stack.

## Demo Contract

The demo in [`Sources/swift-windowsui/DemoDashboard.swift`](/D:/Projects/swift-windowsui/Sources/swift-windowsui/DemoDashboard.swift) is the reference for the supported same-source subset.

When adding features, prefer:

- matching SwiftUI call-site names and argument labels
- shared-source-friendly types such as `CGFloat`, `CGSize`, and `CGRect`
- generic `Content: View` patterns in demo code
- framework changes over demo-only workarounds

Avoid:

- demo code that depends on WinSwiftUI-only helper APIs when a SwiftUI-shaped equivalent can exist
- introducing a second UI abstraction path parallel to the retained runtime

## Limits

- This is not full SwiftUI parity.
- The repository is still Windows-only because the platform and renderer targets are Win32/D3D11-specific.
- Text behavior still reflects the current runtime pixel-font/native bitmap system rather than shaped text rendering.
- `D3D11Renderer` still only executes `fillRect` and `drawBitmap`; `GPUIScene` is the richer active presentation path.
- API coverage should be extended from real demo/app needs, not by cloning SwiftUI surface area speculatively.
