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
- `Divider`
- `Rectangle`
- `RoundedRectangle`
- `Circle`
- `Ellipse`
- `Capsule`
- `Group`
- `GeometryReader`
- `ForEach`
- `VStack`
- `HStack`
- `ZStack`
- `ScrollView`
- `List`
- `Form`
- `Section`
- `HSplitView`
- `VSplitView`
- `Button`
- `TextField`
- `SecureField`
- `Toggle`
- `Slider`
- `ProgressView`
- `Picker`

Modifiers:

- `frame`
- `padding`
- `foregroundColor`
- `foregroundStyle`
- `font`
- `multilineTextAlignment`
- `lineLimit`
- `tint`
- `background`
- `overlay`
- `cornerRadius`
- `clipped`
- `clipShape`
- `border`
- `shadow`
- `opacity`
- `hidden`
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
- `onSubmit`
- `onTapGesture`
- `gesture` with `DragGesture`
- `id`
- `tag`

Compatibility helpers:

- `Color(red:green:blue:opacity:)`
- common non-channel named `Color` values such as `primary`, `secondary`, `accentColor`, `gray`, `orange`, and `purple`
- `Color.opacity(_:)`
- `Material` presets such as `ultraThinMaterial`, `thinMaterial`, `regularMaterial`, `thickMaterial`, `ultraThickMaterial`, and `bar`
- `LinearGradient(colors:startPoint:endPoint)`
- shape `fill(_:)` for colors and linear gradients
- shape `stroke(_:lineWidth:)`
- `UnitPoint`
- `Angle`
- `FillStyle`
- `DragGesture`
- `CGFloat`, `CGPoint`, `CGSize`, `CGRect` aliases
- minimal `State`, with projected bindings tied into retained-runtime invalidation
- minimal `ObservableObject`, `Published`, `ObservedObject`, and `StateObject`
- minimal `Binding`, including projected `@ObservedObject` and `@StateObject` bindings

Surface direction:

- default retained buttons now use lighter rounded chrome with hover, focus, press, and activation transitions
- bindings now cover direct `Binding(get:set:)`, projected `@State`, projected `@ObservedObject`, and projected `@StateObject` members for controls such as `TextField`, `Toggle`, and `Slider`
- the demo’s cards and chips are built from shared-source-friendly layered gradients and translucent strokes rather than WinSwiftUI-only styling hooks

## Mapping Notes

- `Text` maps into retained label nodes and the current text renderer path. Plain strings, `StringProtocol` values, and `Text(verbatim:)` are accepted for source compatibility.
- `Image(systemName:)` maps known SF Symbol names into the project icon set, including common action glyphs such as `trash`.
- `Divider` maps into a thin retained panel and uses the nearest stack axis to choose a horizontal or vertical separator.
- `Rectangle`, `RoundedRectangle`, `Circle`, `Ellipse`, and `Capsule` map into passive retained panels. Shape fills set panel backgrounds or gradients; shape strokes set retained border color and width.
- `RoundedRectangle` carries its corner radius into the retained node so fills, strokes, overlays, and clipping stay aligned. `Circle`, `Ellipse`, and `Capsule` use the retained rounded-rect renderer's maximum capsule radius until path-backed shape views provide true vector ellipse masking.
- `Button` maps into retained button controls and preserves focus/press/activate animation state. SwiftUI-shaped role and `systemImage` initializers are available; `.destructive` maps to a red-tinted retained button surface while `.cancel` currently keeps the automatic surface.
- `buttonStyle` supports `.automatic`, `.bordered`, `.borderedProminent`, `.borderless`, and `.plain`. `.borderedProminent` maps to a blue translucent retained surface; `.borderless` and `.plain` map to transparent chrome.
- `Button` now also resolves hover-aware border and shadow states so retained controls feel closer to modern desktop/mobile system chrome.
- `TextField` maps into a retained single-line editable control. Win32 `WM_CHAR` and IME character messages flow through the runtime text-input hook to the focused node, while arrows, home/end, backspace, and delete update the retained caret/editing state.
- `SecureField` reuses the retained text-field control with masked display text while keeping the bound string unmasked.
- `Toggle`, `Slider`, and `ProgressView` map into retained controls while exposing SwiftUI-shaped binding/value initializers. `Slider(value:in:step:)` snaps dragged binding updates to the requested step. `ProgressView` also supports a string-title initializer that composes a retained label with the progress bar.
- `Picker` maps tagged `Text` options into the retained dropdown control and supports hashable selection tags, including integers, strings, and enum values.
- `ScrollView` maps into retained scroll panels with indicator state handled in the runtime.
- `ForEach` expands child views in result builders and assigns stable node tags from the supplied identity. Identifiable collections, explicit `id:` key paths, open integer ranges, and closed integer ranges are supported.
- `id(_:)` accepts hashable values and stores their string description as the retained node tag for reconciliation.
- `List` maps into a styled vertical retained scroll panel and preserves the same offscreen culling path as `ScrollView`.
- `Form` maps into a grouped vertical retained scroll panel with macOS-style translucent chrome and composes directly with `Section` rows.
- `Section` supports the styled string-title initializer plus SwiftUI-shaped content/header/footer builder forms. Custom header and footer views are rendered as supplied retained subtrees.
- `HSplitView` and `VSplitView` map into the retained split-view control and can infer an initial ratio from content.
- `GeometryReader` uses the current build context canvas size.
- `frame` supports fixed dimensions plus the common min/ideal/max overload. Infinite maximums, such as `maxWidth: .infinity`, map to retained fill-available behavior and participate in stack growth.
- Generic text modifiers (`foregroundColor`, `foregroundStyle(Color)`, `font`, `multilineTextAlignment`, and `lineLimit`) walk the retained subtree and update text descendants. `font` preserves the Segoe Fluent Icons family for `Image(systemName:)` glyphs while still changing their size and weight.
- `Font` supports `system(size:weight:design:)` plus common named presets such as `largeTitle`, `title`, `headline`, `body`, `caption`, and `footnote`.
- `tint` is carried through the build context so descendant `Toggle`, `Slider`, and `ProgressView` controls inherit a shared accent color unless they set their own control-specific tint.
- View `background` and `overlay` overloads map to retained absolute-layout wrappers; the base view keeps layout ownership while the added layer is aligned within the resolved base bounds. Zero-intrinsic layers such as `Color`, `Rectangle`, stroked `RoundedRectangle`, and `Material` fill the base bounds by default.
- `Material` presets lower to passive retained layers with translucent fills, blur radius, border, rounded corners, and soft shadow values for macOS-style glass surfaces.
- `disabled` maps to retained hit-testing/focus state for generic views. Controls with dedicated disabled support, including `Button`, also update retained control chrome and suppress activation.
- `onSubmit` is carried through the build context and currently routes the retained `TextField` enter-key submit hook.
- Visual effect modifiers map to existing retained node properties (`opacity`, `blurRadius`, `transform`, and `zIndex`) so the shared render-frame path can paint them without a separate compatibility layer. Opacity is inherited and resolved into renderer-neutral command alpha/bitmap opacity during frame generation.
- `hidden()` uses zero retained opacity plus recursive interaction suppression, so the view keeps its layout slot while emitting no render commands and taking no pointer/keyboard activation.
- Clipping modifiers map to retained `clipsToBounds`; `RoundedRectangle` also sets the retained corner radius. Current renderer clipping is rectangular/bounds-based, so this is API-compatible but not full vector mask parity.
- Lifecycle modifiers map to retained `onAppear` and `onDisappear` callbacks. Reconciliation refreshes node handlers in place so rebuilt declarative closures stay current without replacing the retained node.
- `onTapGesture` maps to retained pointer-up-inside callbacks and makes the target node hit-test visible. The current compatibility surface supports single-tap activation; multi-tap counting is intentionally not wired until the runtime tracks click sequences.
- `gesture(DragGesture(...))` maps to retained drag start/change/end callbacks with `minimumDistance`, `onChanged`, and `onEnded` support. Coordinate spaces are accepted for call-site compatibility but currently resolve through the runtime's logical window coordinates.

## Observation Model

`WinSwiftUI` now supports a minimal SwiftUI-style observation path for shared source:

- `ObservableObject`
- `@Published`
- `@ObservedObject`
- `@StateObject`

Observed object changes are coalesced by the host before rebuilding the retained tree so one logical update does not trigger multiple immediate redraw passes.

This is intentionally small. It exists to support shared app source and runtime invalidation, not to reproduce the full SwiftUI observation stack.

## Inspection

`WinSwiftUIInspection.snapshot(of:)` builds any `WinSwiftUI.View` into the retained runtime and returns a lightweight diagnostic summary: retained node counts, text/focus/hit-test counts, root layout kind, text samples, invalidations during build, and render-command counts. The `swift-windowsui-inspect` executable uses this alongside lower-level retained/runtime probes so compatibility work can be checked from the console without launching the GUI demo, and `swift run swift-windowsui-inspect -- --json --verify` emits those diagnostics as structured JSON for automation.

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
