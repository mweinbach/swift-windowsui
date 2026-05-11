# swift-windowsui

`swift-windowsui` is a custom-rendered Windows UI toolkit prototype with a retained runtime, renderer-neutral frame and scene contracts, a Win32 host, and Direct3D 11 presentation backends.

The repo now also includes `WinSwiftUI`, a SwiftUI-shaped compatibility layer for the retained runtime. The demo app is written against that layer so the same demo source can be used in a macOS SwiftUI app by changing the import from `WinSwiftUI` to `SwiftUI`.

## What It Is

- A custom-rendered UI stack, not a wrapper around native Win32 widgets
- A retained `ViewNode` runtime with mutable state, subtree layout/measurement reuse, frame/scene replay for clean subtrees, hit testing, focus, clipping, and animation
- Renderer-neutral `RenderFrame` and `GPUIScene` contracts
- A frame fallback renderer that consumes the `fillRect` and `drawBitmap` subset of the shared frame contract
- An active demo path that now defaults to `GPUIScene` -> `D3D11BatchRenderer`, with the `RenderFrame` -> `D3D11Renderer` path kept as an automatic same-session fallback and explicit debug override
- A `WinSwiftUI` host loop that coalesces rebuilds, avoids duplicate invalidates, and only sustains high-rate frame pumping when input actually dirties presentation state
- An experimental batch scene path that scales primitives into device pixels, keeps replayable scene paint records plus per-layer family operations as metadata, carries semantic content masks on typed primitives, assigns bounds-based draw orders from masked bounds inside `GPUIScene`, sorts typed primitive families into ordered batches before upload, uses a runtime-owned logical text layout cache plus a native glyph atlas, and now routes deferred-subtree prepaint plus deferred paint records through runtime-owned prepaint dispatch state while it is still being brought up toward Zed-style sprite batching
- A Windows-only implementation for the runtime/host/renderer layers today

## Same-Source Goal

The current portability target is shared app source, not full package portability.

- On Windows, app code can import `WinSwiftUI`
- On macOS, the same view/app source can import `SwiftUI`
- The demo in `Sources/SwiftWindowsDemo/DemoDashboard.swift` stays inside that shared subset

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
- `SwiftWindowsGraphics`: `RenderBackend`, `RenderFrame`, `GPUIScene`, gradients, and render commands
- `SwiftWindowsScene`: alternate scene abstraction
- `SwiftWindowsLayout`: stack layout primitives and experimental generic layout helpers
- `SwiftWindowsPlatform`: Win32 windowing, input, timers, and delegate bridge
- `SwiftWindowsRendererD3D11`: Direct3D 11 renderer
- `SwiftWindowsUI`: retained `ViewNode` tree, runtime, controls, bitmap/native text plumbing, and `FoundationApp`
- `WinSwiftUI`: `App`, `Scene`, `WindowGroup`, common views/modifiers, observation wrappers, and the retained-runtime host bridge
- `SwiftWindowsDemo`: the shared-source demo screen
- `swift-windowsui`: the demo app entry point

## Active Demo Path

The default running demo now goes through:

1. [`Sources/swift-windowsui/AppEntry.swift`](/D:/Projects/swift-windowsui/Sources/swift-windowsui/AppEntry.swift)
2. `WinSwiftUI.App` / `WindowGroup`
3. `WinSwiftUIWindowHost`
4. `Win32Window` delegate callbacks
5. `RetainedViewRuntime`
6. `GPUIScene`
7. `D3D11BatchRenderer`

The explicit frame-debug path is still available and can be forced with:

```powershell
$env:SWIFT_WINDOWSUI_FRAME_DEBUG = "1"
swift run swift-windowsui
```

`FoundationApp` still exists, but it is no longer the primary demo bootstrap path.

`GPUIScene` -> `D3D11BatchRenderer` is the default demo presentation path. It now keeps replayable scene paint records plus per-layer family paint
operations, carries semantic content masks on typed primitives, assigns
Zed-style bounds-based draw orders from masked bounds inside each scene layer,
finishes scenes into ordered family batches before upload, caches logical
native text layout per runtime, reuses cached subtree layout/measurement state
plus frame/scene ranges when bounds and inherited paint context stay stable,
collects deferred subtree prepaint work and deferred paint records into
runtime-owned queues shared by the frame and scene paths, stores rerunnable
deferred payloads plus cached output ranges, reuses runtime-owned prepaint
dispatch metadata for hit testing, focus traversal, scroll targeting, and
draggable ancestor lookup, remaps deferred priorities when clean subtrees are
reused, and replays cached deferred frame and scene ranges after the deferred
prepaint phase has rebuilt its dispatch metadata,
only attaches atlas snapshots to freshly-built scenes, and uploads typed
primitive ranges without materializing per-operation slice arrays. It now
follows GPUI-style inherited opacity propagation instead of inventing a
save-layer opacity model.

## WinSwiftUI Coverage

The current `WinSwiftUI` surface is intentionally a subset. It is designed to cover the demo and common dashboard-style composition patterns first.

Included today:

- App hosting: `App`, `Scene`, `WindowGroup`
- Core views: `Text`, including `Text(verbatim:)`, `StringProtocol`, and `LocalizedStringKey` inputs, `Image(systemName:)`, `Label`, `Link`, `Rectangle`, `RoundedRectangle`, `Capsule`, `Shape`, `Spacer`, `Divider`, `Group`, `GeometryReader`, `NavigationLink`
- Containers: `NavigationStack`, `NavigationView`, `NavigationSplitView`, `TabView`, `VStack`, `HStack`, `LazyVStack`, `LazyHStack`, `Grid`, `GridRow`, `ZStack`, `ScrollView`, `List` including data-driven row initializers, `Form`, `Section` including header/footer builder overloads, `GroupBox`, `DisclosureGroup`, `HSplitView`, `VSplitView`; stack spacing accepts SwiftUI-style `nil`
- Collection helpers: `ForEach`, including open and closed integer ranges
- Controls: `Button` including `ButtonRole` and `systemImage` overloads, `SettingsLink`, `RenameButton`, `EditButton`, `Menu`, `TextField`, `SecureField`, `TextEditor`, `DatePicker`, `ColorPicker`, `Toggle`, `Picker` including segmented and menu styles, `Stepper`, `Slider` including `step` and label overloads, `ProgressView` including label and current-value label overloads, `Gauge` including title/current/minimum/maximum label overloads
- Modifiers: `frame`, including fixed and min/ideal/max overloads, `fixedSize`, `ignoresSafeArea`, `edgesIgnoringSafeArea`, `aspectRatio`, `scaledToFit`, `scaledToFill`, `padding` including optional-length overloads, `background`, `background(_:alignment:)`, `background(alignment:content:)`, `overlay(_:alignment:)`, `overlay(alignment:content:)`, `foregroundColor`, `foregroundStyle`, `tint`, `accentColor`, `buttonStyle`, `buttonRepeatBehavior`, `buttonSizing`, `buttonBorderShape`, `menuIndicator`, `pickerStyle`, `listStyle`, `navigationTitle`, `navigationBarTitle`, `navigationBarTitleDisplayMode`, `navigationDestination`, `tabItem`, `environment`, `transformEnvironment`, `focusedValue`, `focusedSceneValue`, `preferredColorScheme`, `dynamicTypeSize`, `legibilityWeight`, `font`, `fontWeight`, `bold`, `multilineTextAlignment`, `lineLimit`, `minimumScaleFactor`, `cornerRadius(_:antialiased:)`, `clipped`, `clipShape`, `border`, `shadow`, `layoutPriority`, `gridCellColumns`, `allowsHitTesting`, `focusable`, `hoverEffect`, `defaultHoverEffect`, `hoverEffectDisabled`, `focusEffectDisabled`, `keyboardShortcut`, `redacted`, `unredacted`, `privacySensitive`, `opacity`, `hidden`, `zIndex`, `offset`, `scaleEffect`, `rotationEffect`, `blur`, `transition`, `contentTransition`, `contentTransitionAddsDrawingGroup`, `animation`, `disabled`, `scrollDismissesKeyboard`, `defaultWheelPickerItemHeight`, `task`, `refreshable`, `searchable`, `renameAction`, `onAppear`, `onDisappear`, `onChange`, `onHover`, `onTapGesture`, `tag`, `modifier`
- Compatibility helpers: `ViewModifier`, `ModifiedContent`, `ListStyle`, `Color(red:green:blue:opacity:)`, `Color(white:opacity:)`, `Color(hue:saturation:brightness:opacity:)`, common `Color` constants, `Color.opacity(_:)`, named `Font` styles, `Font.system(_:design:weight:)`, `Animation`, `AnyTransition`, `ContentTransition`, `withAnimation`, `LinearGradient(colors:startPoint:endPoint)`, `UnitPoint`, `Angle`, `HoverEffect`, `RedactionReasons`, `ColorSchemeContrast`, `ScenePhase`, `ControlActiveState`, `EditMode`, `LegibilityWeight`, `LayoutDirection`, `UserInterfaceSizeClass`, `DynamicTypeSize`, `KeyEquivalent`, `EventModifiers`, `KeyboardShortcut`, `ButtonRepeatBehavior`, `ButtonSizing`, `ButtonBorderShape`, `BackgroundProminence`, `LocalizedStringKey`, `RefreshAction`, `DismissSearchAction`, `RenameAction`, `SearchFieldPlacement`, `OpenWindowAction`, `DismissWindowAction`, `OpenSettingsAction`, `RequestReviewAction`, `FocusedValueKey`, `FocusedValues`, `FocusedValue`, `FocusedBinding`, `UndoManager`
- Shared-source support: `CGFloat`/`CGPoint`/`CGSize`/`CGRect` aliases and minimal `Binding` / `State` / `Environment` / `EnvironmentValues` including scene phase, capture/luminance/tab-section/background-prominence metadata, control active appearance, presentation state, multiple-window support metadata, edit mode, focus state/effect metadata, focused values, size classes, display scale, pixel length, calendar/time zone/locale, dismiss, search dismissal, rename, refresh, review request, window/settings actions, undo manager, button/menu/scroll input metadata, and accessibility preference/state values / `ObservableObject` / `Published` / `ObservedObject` / `StateObject`
- Modernized defaults: rounded translucent button chrome, hover/focus/press states, and softer glass-style surface styling in the demo
- Text fitting: `minimumScaleFactor(_:)` reduces the retained effective text size before truncation when constrained width requires it, and `lineLimit(_:reservesSpace:)` reserves retained measurement height for the requested line count across native and pixel text paths

Current gaps:

- This is not full SwiftUI API parity
- Observation support is intentionally small and tuned for retained-runtime invalidation
- Text on the frame fallback path still uses native bitmap draws; the default scene path now has a runtime-owned logical layout cache, subtree layout/measurement reuse, runtime-owned prepaint dispatch state plus split deferred-subtree prepaint and deferred paint replay for interaction/focus/late-paint metadata and ancestor routing, semantic content masks, inherited-opacity propagation, and DirectWrite glyph-run capture, but it still lacks GPUI-style shaped runs, per-deferred prepaint replay ranges, subpixel sprite families, and text-system-owned line layout
- `D3D11Renderer` only executes `fillRect` and `drawBitmap`; the default scene path currently covers shadows, quads, and atlas-backed glyphs

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
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/with-swift.ps1 -CheckOnly
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/build.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/demo-probe.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/demo-screenshot.ps1
```

Useful focused command:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Filter WinSwiftUITests
```

The screenshot helper builds the same shared demo view through the WinSwiftUI retained runtime, pulls the raw scene/frame data, rasterizes it offscreen, and writes `artifacts/demo-screenshot.png`. Pass `-FrameDebug` to force the `RenderFrame` fallback path for visual comparison.

To view the rendered screenshot after running the helper, open `artifacts/demo-screenshot.png`. The script also writes the raw source bitmap next to it as `artifacts/demo-screenshot.raw.bmp`, which is useful when checking the exact offscreen rasterizer output. This path does not capture the desktop or a foreground native window; it uses `WinSwiftUIRendererSnapshotter` and the retained runtime's `GPUIScene`/`RenderFrame` data.

For side-by-side comparison:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/demo-screenshot.ps1 -Mode scene -OutputPath artifacts/demo-screenshot-scene.png
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/demo-screenshot.ps1 -FrameDebug -OutputPath artifacts/demo-screenshot-frame.png
```

Verified in this pass:

```powershell
swift test
swift build --product swift-windowsui
```

The GUI demo was also launched with a short `swift run swift-windowsui` startup probe.

## Important Files

- [`Sources/WinSwiftUI/Core.swift`](/D:/Projects/swift-windowsui/Sources/WinSwiftUI/Core.swift)
- [`Sources/WinSwiftUI/Views.swift`](/D:/Projects/swift-windowsui/Sources/WinSwiftUI/Views.swift)
- [`Sources/WinSwiftUI/App.swift`](/D:/Projects/swift-windowsui/Sources/WinSwiftUI/App.swift)
- [`Sources/swift-windowsui/AppEntry.swift`](/D:/Projects/swift-windowsui/Sources/swift-windowsui/AppEntry.swift)
- [`Sources/SwiftWindowsDemo/DemoDashboard.swift`](/D:/Projects/swift-windowsui/Sources/SwiftWindowsDemo/DemoDashboard.swift)
- [`Sources/WinSwiftUI/RenderSnapshot.swift`](/D:/Projects/swift-windowsui/Sources/WinSwiftUI/RenderSnapshot.swift)
- [`Sources/SwiftWindowsGraphics/SceneRasterizer.swift`](/D:/Projects/swift-windowsui/Sources/SwiftWindowsGraphics/SceneRasterizer.swift)
- [`Sources/SwiftWindowsUI/Runtime.swift`](/D:/Projects/swift-windowsui/Sources/SwiftWindowsUI/Runtime.swift)
- [`Sources/SwiftWindowsUI/Controls.swift`](/D:/Projects/swift-windowsui/Sources/SwiftWindowsUI/Controls.swift)
- [`Sources/SwiftWindowsPlatform/Win32Host.swift`](/D:/Projects/swift-windowsui/Sources/SwiftWindowsPlatform/Win32Host.swift)
- [`Sources/SwiftWindowsRendererD3D11/D3D11Renderer.swift`](/D:/Projects/swift-windowsui/Sources/SwiftWindowsRendererD3D11/D3D11Renderer.swift)

## Documentation

Additional framework notes live in [`docs/WinSwiftUI.md`](/D:/Projects/swift-windowsui/docs/WinSwiftUI.md).
Testing and visual-check commands live in [`docs/Testing.md`](/D:/Projects/swift-windowsui/docs/Testing.md).
