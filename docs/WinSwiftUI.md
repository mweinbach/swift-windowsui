# WinSwiftUI

`WinSwiftUI` is the SwiftUI-shaped layer for the retained Windows runtime.

Its job is not to imitate SwiftUI internally. Its job is to let app code use a familiar SwiftUI-style surface while mapping directly into:

- `RetainedViewRuntime`
- `ViewNode`
- `RenderFrame`
- `Win32Window`
- `D3D11Renderer`

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
- `WinSwiftUIInspection.snapshot(of:)` for retained-tree/render-command diagnostics without opening a window

Views and containers:

- `Text`
- `Image(systemName:)`
- `Label`
- `Spacer`
- `Group`
- `GeometryReader`
- `ForEach`
- `VStack`
- `HStack`
- `ZStack`
- `ScrollView`
- `List`
- `Section`
- `HSplitView`
- `VSplitView`
- `Button`
- `TextField`
- `Toggle`
- `Slider`
- `ProgressView`
- `Picker`

Modifiers:

- `frame`
- `padding`
- `foregroundColor`
- `font`
- `multilineTextAlignment`
- `lineLimit`
- `background`
- `overlay`
- `cornerRadius`
- `clipped`
- `clipShape`
- `border`
- `shadow`
- `opacity`
- `blur`
- `offset`
- `scaleEffect`
- `rotationEffect`
- `zIndex`
- `layoutPriority`
- `allowsHitTesting`
- `disabled`
- `onAppear`
- `onDisappear`
- `onTapGesture`
- `gesture` with `DragGesture`
- `tag`

Compatibility helpers:

- `Color(red:green:blue:opacity:)`
- `Color.opacity(_:)`
- `LinearGradient(colors:startPoint:endPoint)`
- `UnitPoint`
- `Angle`
- `Rectangle`
- `RoundedRectangle`
- `FillStyle`
- `DragGesture`
- `CGFloat`, `CGPoint`, `CGSize`, `CGRect` aliases
- minimal `State`, with projected bindings tied into retained-runtime invalidation
- minimal `ObservableObject`, `Published`, and `ObservedObject`
- minimal `Binding`, including projected `@ObservedObject` bindings

Surface direction:

- default retained buttons now use lighter rounded chrome with hover, focus, press, and activation transitions
- bindings now cover direct `Binding(get:set:)`, projected `@State`, and projected `@ObservedObject` members for controls such as `TextField`, `Toggle`, and `Slider`
- the demo’s cards and chips are built from shared-source-friendly layered gradients and translucent strokes rather than WinSwiftUI-only styling hooks

## Mapping Notes

- `Text` maps into retained label nodes and the current text renderer path.
- `Image(systemName:)` maps known SF Symbol names into the project icon set.
- `Button` maps into retained button controls and preserves focus/press/activate animation state.
- `Button` now also resolves hover-aware border and shadow states so retained controls feel closer to modern desktop/mobile system chrome.
- `TextField` maps into a retained single-line editable control. Win32 `WM_CHAR` and IME character messages flow through the runtime text-input hook to the focused node, while arrows, home/end, backspace, and delete update the retained caret/editing state.
- `Toggle`, `Slider`, and `ProgressView` map into retained controls while exposing SwiftUI-shaped binding/value initializers.
- `Picker` maps tagged `Text` options into the retained dropdown control; the current compatibility layer supports integer tags.
- `ScrollView` maps into retained scroll panels with indicator state handled in the runtime.
- `ForEach` expands child views in result builders and assigns stable node tags from the supplied identity.
- `List` maps into a styled vertical retained scroll panel and preserves the same offscreen culling path as `ScrollView`.
- `HSplitView` and `VSplitView` map into the retained split-view control and can infer an initial ratio from content.
- `GeometryReader` uses the current build context canvas size.
- Generic text modifiers (`foregroundColor`, `font`, `multilineTextAlignment`, and `lineLimit`) walk the retained subtree and update text descendants. `font` preserves the Segoe Fluent Icons family for `Image(systemName:)` glyphs while still changing their size and weight.
- View `background` and `overlay` content closures map to retained absolute-layout wrappers; the base view keeps layout ownership while the added layer is aligned within the resolved base bounds.
- `disabled` maps to retained hit-testing/focus state for generic views. Controls with dedicated disabled support, including `Button`, also update retained control chrome and suppress activation.
- Visual effect modifiers map to existing retained node properties (`opacity`, `blurRadius`, `transform`, and `zIndex`) so the shared render-frame path can paint them without a separate compatibility layer.
- Clipping modifiers map to retained `clipsToBounds`; `RoundedRectangle` also sets the retained corner radius. Current renderer clipping is rectangular/bounds-based, so this is API-compatible but not full vector mask parity.
- Lifecycle modifiers map to retained `onAppear` and `onDisappear` callbacks. Reconciliation refreshes node handlers in place so rebuilt declarative closures stay current without replacing the retained node.
- `onTapGesture` maps to retained pointer-up-inside callbacks and makes the target node hit-test visible. The current compatibility surface supports single-tap activation; multi-tap counting is intentionally not wired until the runtime tracks click sequences.
- `gesture(DragGesture(...))` maps to retained drag start/change/end callbacks with `minimumDistance`, `onChanged`, and `onEnded` support. Coordinate spaces are accepted for call-site compatibility but currently resolve through the runtime's logical window coordinates.

## Observation Model

`WinSwiftUI` now supports a minimal SwiftUI-style observation path for shared source:

- `ObservableObject`
- `@Published`
- `@ObservedObject`

Observed object changes are coalesced by the host before rebuilding the retained tree so one logical update does not trigger multiple immediate redraw passes.

This is intentionally small. It exists to support shared app source and runtime invalidation, not to reproduce the full SwiftUI observation stack.

## Inspection

`WinSwiftUIInspection.snapshot(of:)` builds any `WinSwiftUI.View` into the retained runtime and returns a lightweight diagnostic summary: retained node counts, text/focus/hit-test counts, root layout kind, text samples, invalidations during build, and render-command counts. The `swift-windowsui-inspect` executable uses this alongside lower-level retained/runtime probes so compatibility work can be checked from the console without launching the GUI demo.

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
- Text behavior still reflects the current runtime text system rather than native Apple text rendering.
- API coverage should be extended from real demo/app needs, not by cloning SwiftUI surface area speculatively.
