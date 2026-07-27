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
- A GPUI-inspired batch scene path in native Swift that scales primitives into device pixels, keeps replayable scene paint records plus a per-layer `paintOperations` presentation stream, carries semantic content masks on typed primitives, assigns bounds-based draw orders from masked bounds inside `GPUIScene`, keeps family batches as an optimization surface, uses a runtime-owned logical text layout cache plus a native glyph atlas, and routes deferred-subtree prepaint plus deferred paint records through runtime-owned prepaint dispatch state while it is still being brought up toward Zed-style sprite batching
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

`GPUIScene` -> `D3D11BatchRenderer` is the default demo presentation path. It keeps replayable scene paint records plus a per-layer `paintOperations` stream that is the source of truth for visible presentation order. Typed primitive families and ordered batches remain optimization surfaces, but CPU screenshots and D3D11 presentation consume the paint stream so mixed primitive families preserve retained-runtime order. The scene path also carries semantic content masks on typed primitives, assigns Zed-style bounds-based draw orders from masked bounds inside each scene layer, caches logical native text layout per runtime, reuses cached subtree layout/measurement state plus frame/scene ranges when bounds and inherited paint context stay stable, collects deferred subtree prepaint work and deferred paint records into runtime-owned queues shared by the frame and scene paths, stores rerunnable deferred payloads plus cached output ranges, reuses runtime-owned prepaint dispatch metadata for hit testing, focus traversal, scroll targeting, and draggable ancestor lookup, remaps deferred priorities when clean subtrees are reused, replays cached deferred frame and scene ranges after the deferred prepaint phase has rebuilt its dispatch metadata, only attaches atlas snapshots to freshly-built scenes, and uploads typed primitive ranges without materializing per-operation slice arrays. It follows GPUI-style inherited opacity propagation instead of inventing a save-layer opacity model.

## WinSwiftUI Coverage

The current `WinSwiftUI` surface is intentionally a subset. It is designed to cover the demo and common dashboard-style composition patterns first. The per-API safety matrix (Implemented / Partial / Shim / Placeholder) lives in [`docs/CompatibilityStatus.md`](docs/CompatibilityStatus.md); prefer it over scanning public symbols.

Included today:

- App hosting: `App`, `Scene`, `WindowGroup`
- Multi-window: default `openWindow` / `dismissWindow` routing through `WinSwiftUIWindowCoordinator` — each window gets its own host, retained runtime, and renderer; `supportsMultipleWindows` is true for coordinator-managed hosts. `openSettings` / `Settings` scenes remain unsupported
- Accessibility: retained accessibility metadata is projected to Windows UI Automation (fragment tree, trait-derived control types, InvokePattern activation, focus/structure events); advanced Value/Text/Selection/Toggle patterns and live regions are not implemented
- Text input: caret, highlighted selection, mouse-drag selection, clipboard shortcuts (Ctrl+C/X/V/A), and IME composition (marked text, candidate window positioned at the caret)
- Platform integrations: real Win32 open/save dialogs behind `fileImporter` / `fileExporter`, Unicode text and file-list (`CF_HDROP`) clipboard, OS file drops (`WM_DROPFILES`) delivered to `onDrop`, an opt-in native `ChooseColorW` dialog for `ColorPicker`, and `Link` / `openURL` via `ShellExecuteW`
- System appearance: light/dark and high contrast sampled at startup and re-sampled on `WM_SETTINGCHANGE` / `WM_SYSCOLORCHANGE`; app overrides (`preferredColorScheme`, explicit environment sets) take precedence
- Core views: `Text`, including `Text(verbatim:)`, `StringProtocol`, and `LocalizedStringKey` inputs, `Image(systemName:)`, `Label`, `Link`, `Rectangle`, `RoundedRectangle`, `UnevenRoundedRectangle`, `Capsule`, `Circle`, `Ellipse`, `ContainerRelativeShape`, `AnyShape`, `Shape`, `Spacer`, `Divider`, `Group`, `GeometryReader`, `NavigationLink`
- Containers: `NavigationStack`, `NavigationView`, `NavigationSplitView`, `TabView`, `VStack`, `HStack`, `LazyVStack`, `LazyHStack`, `Grid`, `GridRow`, `ZStack`, `ScrollView`, `ScrollViewReader`, `List` including data-driven and binding-backed row initializers, `Form`, `Section` including header/footer builder overloads, `GroupBox`, `DisclosureGroup`, `HSplitView`, `VSplitView`; stack spacing accepts SwiftUI-style `nil`
- Collection helpers: `ForEach`, including open and closed integer ranges plus binding-backed mutable collections
- Controls: `Button` including `ButtonRole` and `systemImage` overloads, `SettingsLink`, `RenameButton`, `EditButton`, `Menu`, `TextField`, `SecureField`, `TextEditor`, `DatePicker`, `ColorPicker`, `Toggle`, `Picker` including segmented and menu styles, `Stepper`, `Slider` including `step` and label overloads, `ProgressView` including label and current-value label overloads, `Gauge` including title/current/minimum/maximum label overloads
- Modifiers: `frame`, including fixed and min/ideal/max overloads, `containerRelativeFrame`, `fixedSize`, `ignoresSafeArea`, `edgesIgnoringSafeArea`, `aspectRatio`, `scaledToFit`, `scaledToFill`, `padding` including optional-length overloads, `background`, `background(_:alignment:)`, `background(_:in:fillStyle:)`, `background(alignment:content:)`, `backgroundPreferenceValue`, `overlay(_:alignment:)`, `overlay(_:in:fillStyle:)`, `overlay(alignment:content:)`, `overlayPreferenceValue`, `mask`, `foregroundColor`, `foregroundStyle`, `tint`, `accentColor`, `buttonStyle`, `buttonRepeatBehavior`, `buttonSizing`, `buttonBorderShape`, `menuIndicator`, `pickerStyle`, `listStyle`, `listItemTint`, `listRowSeparator`, `listRowSeparatorTint`, `listSectionSeparator`, `listSectionSeparatorTint`, `listSectionMargins`, `listSectionSpacing`, `navigationTitle`, `navigationSubtitle`, `navigationBarTitle`, `navigationBarTitleDisplayMode`, `navigationDestination`, `tabItem`, `environment`, `transformEnvironment`, `preference`, `transformPreference`, `anchorPreference`, `transformAnchorPreference`, `onPreferenceChange`, `focusedValue`, `focusedSceneValue`, `preferredColorScheme`, `dynamicTypeSize`, `legibilityWeight`, `font`, `fontDesign`, `fontWidth`, `fontWeight`, `bold`, `multilineTextAlignment`, `lineLimit`, `lineSpacing`, `kerning`, `tracking`, `baselineOffset`, `textScale`, `textRenderer`, `minimumScaleFactor`, `cornerRadius(_:antialiased:)`, `clipped`, `clipShape`, `border`, `shadow`, `layoutPriority`, `alignmentGuide`, `gridCellColumns`, `gridCellAnchor`, `gridCellUnsizedAxes`, `gridColumnAlignment`, `allowsHitTesting`, `focusable`, `hoverEffect`, `defaultHoverEffect`, `hoverEffectDisabled`, `focusEffectDisabled`, `keyboardShortcut`, `itemProvider`, `onDrag`, `draggable`, `onDrop`, `dropConfiguration`, `dropPreviewsFormation`, `springLoadingBehavior`, `onDelete`, `onMove`, `onInsert`, `dropDestination`, `onDeleteCommand`, `onMoveCommand`, `onExitCommand`, `pageCommand`, `onPlayPauseCommand`, `gesture`, `highPriorityGesture`, `simultaneousGesture`, `redacted`, `unredacted`, `privacySensitive`, `opacity`, `blendMode`, `compositingGroup`, `drawingGroup`, `brightness`, `contrast`, `colorInvert`, `colorMultiply`, `saturation`, `grayscale`, `hueRotation`, `luminanceToAlpha`, `hidden`, `zIndex`, `offset`, `scaleEffect`, `rotationEffect`, `rotation3DEffect`, `transformEffect`, `projectionEffect`, `blur`, `transition`, `contentTransition`, `contentTransitionAddsDrawingGroup`, `symbolEffect`, `symbolEffectsRemoved`, `sensoryFeedback`, `animation`, `disabled`, `selectionDisabled`, `deleteDisabled`, `moveDisabled`, `scrollIndicatorsFlash`, `scrollPosition`, `scrollTransition`, `onScrollGeometryChange`, `onScrollPhaseChange`, `onScrollVisibilityChange`, `onScrollTargetVisibilityChange`, `scrollBounceBehavior`, `scrollTargetBehavior`, `scrollTargetLayout`, `scrollInputBehavior`, `contentMargins` including scalar and `EdgeInsets` overloads, `defaultScrollAnchor`, `scrollDismissesKeyboard`, `defaultWheelPickerItemHeight`, `task`, `refreshable`, `searchable`, `renameAction`, `onAppear`, `onDisappear`, `onChange`, `onReceive`, `onHover`, `onContinuousHover`, `onTapGesture`, `onLongPressGesture`, `tag`, `modifier`
- Compatibility helpers: `ViewModifier`, `ModifiedContent`, `Optional<View>`, `PreferenceKey`, `Anchor`, `DynamicViewContent`, `UTType`, `NSItemProvider`, `Transferable`, `DropInfo`, `DropDelegate`, `DropProposal`, `DropOperation`, `DropSession`, `DropConfiguration`, `DragDropPreviewsFormation`, `SpringLoadingBehavior`, `ListStyle`, `ListSectionSpacing`, `InsettableShape`, `InsetShape`, generic `ShapeStyle` overloads, `AnyShapeStyle`, `HierarchicalShapeStyle`, `Material`, `Color(red:green:blue:opacity:)`, `Color(white:opacity:)`, `Color(hue:saturation:brightness:opacity:)`, common `Color` constants, `Color.opacity(_:)`, named `Font` styles, `Font.system(_:design:weight:)`, `Font.Width`, `Font.width(_:)`, `Font.bold(_:)`, `Font.italic(_:)`, `Font.monospacedDigit()`, `Font.smallCaps(_:)`, `Font.lowercaseSmallCaps(_:)`, `Font.uppercaseSmallCaps(_:)`, `Text.Scale`, `Text.Layout`, `TextRenderer`, `TextAttribute`, `TextProxy`, `ProposedViewSize`, `Animatable`, `EmptyAnimatableData`, `VectorArithmetic`, `Animation`, `AnimationCompletionCriteria`, `Transaction`, `withAnimation`, `withTransaction`, `AnyTransition`, `ContentTransition`, `SymbolEffect`, `SymbolEffectOptions`, `SensoryFeedback`, `LinearGradient(colors:startPoint:endPoint)`, `Gradient` (including `init(stops: [Gradient.Stop])` with preserved `Double` `location` values), `UnitPoint`, `UnitPoint3D`, `RotationAxis3D`, `CGAffineTransform`, `ProjectionTransform`, `BlendMode`, `ColorRenderingMode`, `Angle`, `HoverEffect`, `HoverPhase`, `RedactionReasons`, `ColorSchemeContrast`, `ScenePhase`, `ControlActiveState`, `EditMode`, `LegibilityWeight`, `LayoutDirection`, `UserInterfaceSizeClass`, `DynamicTypeSize`, `KeyEquivalent`, `EventModifiers`, `KeyboardShortcut`, `MoveCommandDirection`, `CoordinateSpace`, `Gesture`, `AnyGesture`, `SimultaneousGesture`, `SequenceGesture`, `ExclusiveGesture`, `GestureMask`, `TapGesture`, `SpatialTapGesture`, `LongPressGesture`, `DragGesture`, `GestureState`, `ButtonRepeatBehavior`, `ButtonSizing`, `ButtonBorderShape`, `ScrollBounceBehavior`, `ScrollTarget`, `ScrollTargetBehavior`, `ScrollTargetBehaviorContext`, `ScrollTargetBehaviorProperties`, `ScrollTargetBehaviorPropertiesContext`, `PagingScrollTargetBehavior`, `ViewAlignedScrollTargetBehavior`, `AnyScrollTargetBehavior`, `ScrollInputBehavior`, `ScrollInputKind`, `ScrollPosition`, `ScrollViewProxy`, `CGVector`, `ScrollGeometry`, `ScrollPhase`, `ScrollPhaseChangeContext`, `VisualEffect`, `EmptyVisualEffect`, `UnitCurve`, `ScrollTransitionPhase`, `ScrollTransitionConfiguration`, `BackgroundProminence`, `LocalizedStringKey`, `RefreshAction`, `DismissSearchAction`, `RenameAction`, `SearchFieldPlacement`, `OpenWindowAction`, `DismissWindowAction`, `OpenSettingsAction`, `RequestReviewAction`, `FocusedValueKey`, `FocusedValues`, `FocusedValue`, `FocusedBinding`, `UndoManager`
- Canvas drawing: `Canvas { ctx, size in ... }` paints through the default GPUIScene path, with a SwiftUI-shape `GraphicsContext` exposing `Shading.color(_:)` and `Shading.linearGradient(_:startPoint:endPoint:)` (CGPoint endpoints), `fill`/`stroke` for `Path` and `CGRect`, `draw` for `BitmapSurface`/`Text`/`String` with `PixelTextStyle`, mutable `opacity` and `transform` with `translateBy`/`scaleBy`/`rotate`/`concatenate`, `clip(to:)` plus `popClip()`, and `drawLayer { sub in ... }` for parent-transform-inheriting sub-contexts whose mutations do not leak back out
- Path hit testing: `Path.contains(_:eoFill:)` flattens curves/arcs and ray-casts to support both non-zero winding (default) and even-odd fill rules
- Shared-source support: `CGFloat`/`CGPoint`/`CGSize`/`CGRect` aliases and minimal `Binding` with dynamic-member projections, mutable-collection element bindings, and optional bridging / `State` / `Environment` / `EnvironmentValues` including scene phase, capture/luminance/tab-section/background-prominence metadata, control active appearance, presentation state, multiple-window support metadata, edit mode, focus state/effect metadata, focused values, size classes, display scale, pixel length, calendar/time zone/locale, dismiss, search dismissal, rename, refresh, review request, window/settings actions, undo manager, default app storage, button/menu/scroll input metadata, and accessibility preference/state values / `AppStorage` and `SceneStorage` optional primitive storage plus optional and non-optional raw-value enum persistence / `ObservableObject` with subscribable `objectWillChange` / `Just` / `PassthroughSubject` including `Void.send()` / `CurrentValueSubject` / `AnyPublisher` / `Published` projected publisher sink, `assign(to:on:)`, `eraseToAnyPublisher`, `map`, `compactMap`, `filter`, `dropFirst`, `removeDuplicates`, `AnyCancellable` storage, and `onReceive` subscription / `ObservedObject` and `StateObject` with projected member bindings
- Modernized defaults: rounded translucent button chrome, hover/focus/press states, and softer glass-style surface styling in the demo
- Text fitting: `minimumScaleFactor(_:)` reduces the retained effective text size before truncation when constrained width requires it, and `lineLimit(_:reservesSpace:)` reserves retained measurement height for the requested line count across native and pixel text paths

Current gaps:

- This is not full SwiftUI API parity
- Observation support is intentionally small and tuned for retained-runtime invalidation
- Text on the frame fallback path still uses native bitmap draws; the default scene path now has a runtime-owned logical layout cache, subtree layout/measurement reuse, runtime-owned prepaint dispatch state plus split deferred-subtree prepaint and deferred paint replay for interaction/focus/late-paint metadata and ancestor routing, semantic content masks, inherited-opacity propagation, and DirectWrite glyph-run capture, but it still lacks GPUI-style shaped runs, per-deferred prepaint replay ranges, subpixel sprite families, and text-system-owned line layout
- `D3D11Renderer` only executes `fillRect` and `drawBitmap`; the default scene path currently covers shadows, quads, paths (incl. `Canvas` content), and atlas-backed glyphs
- Canvas's `symbols:` closure and `GraphicsContext.resolveSymbol(id:)` are not wired through yet; Canvas's `blendMode` and `withCGContext` escape hatch are also not implemented

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
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/agent-check.ps1 -ContractsOnly
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/lint.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/agent-check.ps1 -Quick
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/build.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/demo-probe.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/demo-screenshot.ps1
```

`scripts/check-contracts.ps1` encodes project-specific invariants that generic Swift lint cannot see: the SwiftUI-on-Windows goal, the GPUI-inspired retained scene pipeline, raw screenshot validation, `paintOperations` presentation order, offscreen compositing cache safety, and shared-demo source compatibility. `scripts/agent-check.ps1` runs those checks plus the focused validation ladder serially so agents do not collide on SwiftPM's `.build/build.db`.

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

Additional framework notes live in [`docs/WinSwiftUI.md`](docs/WinSwiftUI.md).
Testing and visual-check commands live in [`docs/Testing.md`](docs/Testing.md).
Release history and the versioning policy live in [`CHANGELOG.md`](CHANGELOG.md); the release smoke procedure lives in [`docs/ReleaseChecklist.md`](docs/ReleaseChecklist.md). Enforced performance budgets are listed in [`docs/PerformanceBudgets.md`](docs/PerformanceBudgets.md).
Agent handoff and architecture guardrails live in [`AGENTS.md`](AGENTS.md), which `CLAUDE.md` imports.
