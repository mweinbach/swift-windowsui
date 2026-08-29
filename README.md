# swift-windowsui

`swift-windowsui` is a custom-rendered Windows UI toolkit prototype with a retained runtime, renderer-neutral frame and scene contracts, a Win32 host, and Direct3D 11 presentation backends.

The repo now also includes `WinSwiftUI`, a SwiftUI-shaped compatibility layer for the retained runtime. The demo app is written against that layer so the same demo source can be used in a macOS SwiftUI app by changing the import from `WinSwiftUI` to `SwiftUI`.

The long-term target is a complete SwiftUI experience on Windows, including the
rendering engine, animation, controls, and reusable application templates. See
[`goal.md`](goal.md) for the intended end state and acceptance criteria;
[`docs/CompatibilityStatus.md`](docs/CompatibilityStatus.md) describes what
works today.

## What It Is

- A custom-rendered UI stack, not a wrapper around native Win32 widgets
- A retained `ViewNode` runtime with mutable state, subtree layout/measurement reuse, frame/scene replay for clean subtrees, hit testing, focus, clipping, and animation
- Renderer-neutral `RenderFrame` and `GPUIScene` contracts
- A frame fallback renderer that consumes the `fillRect` and `drawBitmap` subset of the shared frame contract
- An active demo path that now defaults to `GPUIScene` -> `D3D11BatchRenderer`, with the `RenderFrame` -> `D3D11Renderer` path kept as an automatic same-session fallback and explicit debug override
- A `WinSwiftUI` host loop that coalesces rebuilds, avoids duplicate invalidates, and only sustains high-rate frame pumping when input actually dirties presentation state
- A GPUI-inspired batch scene path in native Swift that scales primitives into device pixels, keeps replayable scene paint records plus a per-layer `paintOperations` presentation stream, carries semantic content masks on typed primitives, assigns bounds-based draw orders from masked bounds inside `GPUIScene`, keeps family batches as an optimization surface, uses a runtime-owned logical text layout cache plus a native glyph atlas, and routes deferred-subtree prepaint plus deferred paint records through runtime-owned prepaint dispatch state while it is still being brought up toward Zed-style sprite batching
- Linear gradients that retain authored intermediate color stops, custom stop positions, hard stops, and reversed endpoints across CPU snapshots, the D3D11 scene backend, and the live Direct2D/D3D11 frame fallback; rectangular Canvas fills additionally promote diagonal, inset, transformed, and rounded multistop gradients directly to instanced GPU quads
- GPU-native radial and angular shape gradients with authored centers, start/end radii or signed angular sweeps, intermediate and hard stops, transparency, rounded coverage, transforms, clips, and matching CPU snapshots
- Native Windows character input with Unicode, keyboard-layout-aware punctuation, supplementary-plane characters, existing IME composition, and selection-safe editing; mouse, primary-touch, double-click, horizontal-wheel, and lost-capture interactions share the retained input path
- Portable public Core, Graphics, Layout, and Scene products with a genuinely
  headless CPU renderer; the full retained `WinSwiftUI` runtime and native
  presentation remain Windows implementations today

## Same-Source Goal

Shared app source and the renderer-neutral package foundation are portable; the
full retained runtime and Windows host are not yet interchangeable as a unit.

- On Windows, app code can import `WinSwiftUI`
- On macOS, the same view/app source can import native `SwiftUI` and build as
  the `swift-windowsui` executable without Win32 or Direct3D dependencies
- On Linux and macOS, clients can import the independently packaged
  `SwiftWindowsCore`, `SwiftWindowsGraphics`, `SwiftWindowsLayout`, and
  `SwiftWindowsScene` products and use the genuine offscreen CPU renderer
- Every demo source under `Sources/SwiftWindowsDemo/` stays inside that shared
  SwiftUI-compatible subset

Important limit:

- `WinSwiftUI`, the complete retained UI engine, native accessibility,
  DirectWrite/WIC text and image services, the Win32 host, and the D3D11
  presenter remain Windows-only. Portable host contracts do not yet mean the
  complete retained app can boot on another operating system.

## Run The Demo

Start the custom-rendered Windows app from the repository root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run-demo.ps1
```

Choose the rendering engine explicitly without changing application code:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run-demo.ps1 -Backend d3d11
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run-demo.ps1 -Backend software
```

The app includes four same-source SwiftUI screens: an interactive rendering
dashboard, appearance and application settings, a searchable component
inspector, and an interactive component gallery. The gallery provides searchable
control, rendering, typography, material, and presentation examples with real
editable bindings, pickers, sliders, progress, sheets, popovers, and dialogs.
Press `Ctrl+K` from any screen to open the keyboard-navigable command palette,
or `Ctrl+G` to jump directly to the gallery, including at the minimum window
size. Panel commands collapse or restore the sidebar and inspector without
losing their content. Data-column headers toggle semantic sort order,
pagination follows the filtered result set, and restarting a degraded component
updates its real health and load. Settings expose dirty-state tracking,
validation, `Ctrl+S` saving, and reset confirmation. Shorter windows adapt the
dashboard, gallery, command palette, and inspector. Pass `-FrameDebug` to the
same script to exercise fallback presentation instead of the default D3D11
scene renderer.

## Package Layout

Products:

- `SwiftWindowsCore`, `SwiftWindowsGraphics`, `SwiftWindowsLayout`,
  `SwiftWindowsScene`: independently consumable cross-platform foundations
- `SwiftWindowsUI`: retained runtime and controls
- `WinSwiftUI`: SwiftUI-shaped compatibility layer over the retained runtime
- `SwiftWindowsApp`: app shell and D3D11 wiring
- `swift-windowsui`: demo executable

See [`docs/PlatformArchitecture.md`](docs/PlatformArchitecture.md) for the
platform-versus-engine portability matrix, real swap boundaries, offscreen
surface contract, and remaining work before a second retained-runtime host.

Targets:

- `SwiftWindowsCore`: geometry, color, input, surface, and shared utility types
- `SwiftWindowsGraphics`: `RenderBackend`, `RenderFrame`, `GPUIScene`, gradients, and render commands
- `SwiftWindowsScene`: alternate scene abstraction
- `SwiftWindowsLayout`: stack layout primitives and experimental generic layout helpers
- `SwiftWindowsPlatform`: Win32 windowing, input, timers, and delegate bridge
- `SwiftWindowsRendererD3D11`: Direct3D 11 renderer
- `SwiftWindowsUI`: retained `ViewNode` tree, runtime, controls, bitmap/native text plumbing, and `FoundationApp`
- `WinSwiftUI`: `App`, `Scene`, `WindowGroup`, common views/modifiers, observation wrappers, and the retained-runtime host bridge
- `SwiftWindowsDemo`: the four-screen shared-source app and interactive
  component gallery
- `swift-windowsui`: the demo app entry point

## Active Demo Path

The default running demo now goes through:

1. [`Sources/swift-windowsui/AppEntry.swift`](Sources/swift-windowsui/AppEntry.swift)
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
- Multi-window: default `openWindow` / `dismissWindow` routing through `WinSwiftUIWindowCoordinator` — each window gets its own host, retained runtime, and renderer; `supportsMultipleWindows` is true for coordinator-managed hosts. Static `SceneBuilder` composition registers multiple scenes, and `openSettings` / `SettingsLink` open or reactivate one declared Settings window. The demo uses shared Settings content and an injectable persistent store; see [TemplateCatalog](docs/TemplateCatalog.md) for scope and remaining workflow limits
- Accessibility: retained accessibility metadata is projected to Windows UI Automation (fragment tree, trait-derived control types, transform-aware/offscreen bounds, disabled-state-safe InvokePattern, editable non-password ValuePattern, TogglePattern, List/Table SelectionPattern and SelectionItemPattern, virtualized-row realization, focus/structure events, and an explicit live-region event bridge); rich TextPattern, automatic live-region observation, and fine-grained structure notifications remain unsupported
- Text input: keyboard-layout-aware `WM_CHAR` Unicode entry, supplementary-plane characters, caret and highlighted selection, Unicode/grapheme-aware Ctrl+Left/Right word navigation and Ctrl+Shift word selection, mouse-drag selection, clipboard shortcuts (Ctrl+C/X/V/A), and IME composition (marked text, candidate window positioned at the caret)
- Environment consistency: `.environment(\.isEnabled, ...)`, `.disabled(...)`, button/picker styles, foreground colors, accent colors, and nested dynamic-type limits propagate coherently into controls, `@Environment` readers, and `@ScaledMetric`; sliders support pointer focus and keyboard adjustment
- Programmatic scrolling: `ScrollViewReader` / `ScrollViewProxy.scrollTo(_:anchor:)` resolve retained identifiers against the nearest scroll container, including deferred lazy-stack rows, with axis-aware anchors, captured animation transactions, and interruption handling. Geometry, phase, and visibility callbacks report retained presentation; the gallery demonstrates their readouts alongside an animated binding
- List keyboard navigation: synchronous rebuilds preserve the current selection request while stale handlers and layout receipts cannot move focus. [List keyboard navigation](docs/ListKeyboardNavigation.md) documents deferred-row reveal, eager construction, and the remaining animated deferred-focus completion gap
- Platform integrations: real Win32 open/save dialogs behind `fileImporter` / `fileExporter`, [atomic regular-file `FileDocument` export](docs/FileDocumentExport.md), Unicode text and validated file-list (`CF_HDROP`) clipboard with fail-closed, type-aware `PasteButton` delivery, OS file drops (`WM_DROPFILES`) delivered to `onDrop`, an opt-in native `ChooseColorW` dialog for `ColorPicker`, and `Link` / `openURL` via `ShellExecuteW`
- System appearance: light/dark and high contrast sampled at startup and re-sampled on `WM_SETTINGCHANGE` / `WM_SYSCOLORCHANGE`; actual Windows contrast-theme window, text, control, selection, disabled, and link colors propagate through the inherited environment and semantic control/text palette; app overrides (`preferredColorScheme`, explicit environment sets) take precedence
- Core views: `Text`, including `Text(verbatim:)`, `StringProtocol`, and `LocalizedStringKey` inputs, `Image(systemName:)`, `Label`, `Link`, `Rectangle`, `RoundedRectangle`, `UnevenRoundedRectangle`, `Capsule`, `Circle`, `Ellipse`, `ContainerRelativeShape`, `AnyShape`, `Shape`, `Spacer`, `Divider`, `Group`, `GeometryReader`, `NavigationLink`
- Bitmap images: ordinary stretch plus bounded cap inset and tile sampling on the CPU and D3D11 paths, with unchanged source pixels and one image primitive. [Bitmap sizing](docs/BitmapImageSizing.md) documents admission limits and the remaining aspect, asset, and native parity gaps
- Containers: `NavigationStack`, `NavigationView`, `NavigationSplitView`, `TabView`, `VStack`, `HStack`, `LazyVStack`, `LazyHStack`, `Grid`, `GridRow`, `ZStack`, `ScrollView`, `ScrollViewReader`, `List` including data-driven and binding-backed row initializers, `Form`, `Section` including header/footer builder overloads, `GroupBox`, `DisclosureGroup`, `HSplitView`, `VSplitView`; stack spacing accepts SwiftUI-style `nil`
- Collection helpers: `ForEach`, including open and closed integer ranges plus binding-backed mutable collections
- Controls: `Button` including `ButtonRole` and `systemImage` overloads, `SettingsLink`, `RenameButton`, `EditButton`, `Menu`, `TextField`, `SecureField`, `TextEditor`, `DatePicker`, `ColorPicker`, `Toggle`, `Picker` including segmented and menu styles, `Stepper`, `Slider` including `step` and label overloads, `ProgressView` including label and current-value label overloads, `Gauge` including title/current/minimum/maximum label overloads
- Modifiers: `frame`, including fixed and min/ideal/max overloads, `containerRelativeFrame`, `fixedSize`, `ignoresSafeArea`, `edgesIgnoringSafeArea`, `aspectRatio`, `scaledToFit`, `scaledToFill`, `padding` including optional-length overloads, `background`, `background(_:alignment:)`, `background(_:in:fillStyle:)`, `background(alignment:content:)`, `backgroundPreferenceValue`, `overlay(_:alignment:)`, `overlay(_:in:fillStyle:)`, `overlay(alignment:content:)`, `overlayPreferenceValue`, `mask`, `foregroundColor`, `foregroundStyle`, `tint`, `accentColor`, `buttonStyle`, `buttonRepeatBehavior`, `buttonSizing`, `buttonBorderShape`, `menuIndicator`, `pickerStyle`, `listStyle`, `listItemTint`, `listRowSeparator`, `listRowSeparatorTint`, `listSectionSeparator`, `listSectionSeparatorTint`, `listSectionMargins`, `listSectionSpacing`, `navigationTitle`, `navigationSubtitle`, `navigationBarTitle`, `navigationBarTitleDisplayMode`, `navigationDestination`, `tabItem`, `environment`, `transformEnvironment`, `preference`, `transformPreference`, `anchorPreference`, `transformAnchorPreference`, `onPreferenceChange`, `focusedValue`, `focusedSceneValue`, `preferredColorScheme`, `dynamicTypeSize`, `legibilityWeight`, `font`, `fontDesign`, `fontWidth`, `fontWeight`, `bold`, `multilineTextAlignment`, `lineLimit`, `lineSpacing`, `kerning`, `tracking`, `baselineOffset`, `textScale`, `textRenderer`, `minimumScaleFactor`, `cornerRadius(_:antialiased:)`, `clipped`, `clipShape`, `border`, `shadow`, `layoutPriority`, `alignmentGuide`, `gridCellColumns`, `gridCellAnchor`, `gridCellUnsizedAxes`, `gridColumnAlignment`, `allowsHitTesting`, `focusable`, `hoverEffect`, `defaultHoverEffect`, `hoverEffectDisabled`, `focusEffectDisabled`, `keyboardShortcut`, `itemProvider`, `onDrag`, `draggable`, `onDrop`, `dropConfiguration`, `dropPreviewsFormation`, `springLoadingBehavior`, `onDelete`, `onMove`, `onInsert`, `dropDestination`, `onDeleteCommand`, `onMoveCommand`, `onExitCommand`, `pageCommand`, `onPlayPauseCommand`, `gesture`, `highPriorityGesture`, `simultaneousGesture`, `redacted`, `unredacted`, `privacySensitive`, `opacity`, `blendMode`, `compositingGroup`, `drawingGroup`, `brightness`, `contrast`, `colorInvert`, `colorMultiply`, `saturation`, `grayscale`, `hueRotation`, `luminanceToAlpha`, `hidden`, `zIndex`, `offset`, `scaleEffect`, `rotationEffect`, `rotation3DEffect`, `transformEffect`, `projectionEffect`, `blur`, `transition`, `contentTransition`, `contentTransitionAddsDrawingGroup`, `symbolEffect`, `symbolEffectsRemoved`, `sensoryFeedback`, `animation`, `disabled`, `selectionDisabled`, `deleteDisabled`, `moveDisabled`, `scrollIndicatorsFlash`, `scrollPosition`, `scrollTransition`, `onScrollGeometryChange`, `onScrollPhaseChange`, `onScrollVisibilityChange`, `onScrollTargetVisibilityChange`, `scrollBounceBehavior`, `scrollTargetBehavior`, `scrollTargetLayout`, `scrollInputBehavior`, `contentMargins` including scalar and `EdgeInsets` overloads, `defaultScrollAnchor`, `scrollDismissesKeyboard`, `defaultWheelPickerItemHeight`, `task`, `refreshable`, `searchable`, `renameAction`, `onAppear`, `onDisappear`, `onChange`, `onReceive`, `onHover`, `onContinuousHover`, `onTapGesture`, `onLongPressGesture`, `tag`, `modifier`
- Compatibility helpers: `ViewModifier`, `ModifiedContent`, `Optional<View>`, `PreferenceKey`, `Anchor`, `DynamicViewContent`, `UTType`, `NSItemProvider`, `Transferable`, `DropInfo`, `DropDelegate`, `DropProposal`, `DropOperation`, `DropSession`, `DropConfiguration`, `DragDropPreviewsFormation`, `SpringLoadingBehavior`, `ListStyle`, `ListSectionSpacing`, `InsettableShape`, `InsetShape`, generic `ShapeStyle` overloads, `AnyShapeStyle`, `HierarchicalShapeStyle`, `Material`, `Color(red:green:blue:opacity:)`, `Color(white:opacity:)`, `Color(hue:saturation:brightness:opacity:)`, common `Color` constants, `Color.opacity(_:)`, named `Font` styles, `Font.system(_:design:weight:)`, `Font.Width`, `Font.width(_:)`, `Font.bold(_:)`, `Font.italic(_:)`, `Font.monospacedDigit()`, `Font.smallCaps(_:)`, `Font.lowercaseSmallCaps(_:)`, `Font.uppercaseSmallCaps(_:)`, `Text.Scale`, `Text.Layout`, `TextRenderer`, `TextAttribute`, `TextProxy`, `ProposedViewSize`, `Animatable`, `EmptyAnimatableData`, `VectorArithmetic`, `Animation`, `AnimationCompletionCriteria`, `Transaction`, `withAnimation`, `withTransaction`, `AnyTransition`, `ContentTransition`, `SymbolEffect`, `SymbolEffectOptions`, `SensoryFeedback`, `LinearGradient(colors:startPoint:endPoint)`, `Gradient` (including `init(stops: [Gradient.Stop])` with preserved `Double` `location` values), `UnitPoint`, `UnitPoint3D`, `RotationAxis3D`, `CGAffineTransform`, `ProjectionTransform`, `BlendMode`, `ColorRenderingMode`, `Angle`, `HoverEffect`, `HoverPhase`, `RedactionReasons`, `ColorSchemeContrast`, `ScenePhase`, `ControlActiveState`, `EditMode`, `LegibilityWeight`, `LayoutDirection`, `UserInterfaceSizeClass`, `DynamicTypeSize`, `KeyEquivalent`, `EventModifiers`, `KeyboardShortcut`, `MoveCommandDirection`, `CoordinateSpace`, `Gesture`, `AnyGesture`, `SimultaneousGesture`, `SequenceGesture`, `ExclusiveGesture`, `GestureMask`, `TapGesture`, `SpatialTapGesture`, `LongPressGesture`, `DragGesture`, `GestureState`, `ButtonRepeatBehavior`, `ButtonSizing`, `ButtonBorderShape`, `ScrollBounceBehavior`, `ScrollTarget`, `ScrollTargetBehavior`, `ScrollTargetBehaviorContext`, `ScrollTargetBehaviorProperties`, `ScrollTargetBehaviorPropertiesContext`, `PagingScrollTargetBehavior`, `ViewAlignedScrollTargetBehavior`, `AnyScrollTargetBehavior`, `ScrollInputBehavior`, `ScrollInputKind`, `ScrollPosition`, `ScrollViewProxy`, `CGVector`, `ScrollGeometry`, `ScrollPhase`, `ScrollPhaseChangeContext`, `VisualEffect`, `EmptyVisualEffect`, `UnitCurve`, `ScrollTransitionPhase`, `ScrollTransitionConfiguration`, `BackgroundProminence`, `LocalizedStringKey`, `RefreshAction`, `DismissSearchAction`, `RenameAction`, `SearchFieldPlacement`, `OpenWindowAction`, `DismissWindowAction`, `OpenSettingsAction`, `RequestReviewAction`, `FocusedValueKey`, `FocusedValues`, `FocusedValue`, `FocusedBinding`, `UndoManager`
- Canvas drawing: `Canvas { ctx, size in ... }` paints through the default GPUIScene path, with a SwiftUI-shape `GraphicsContext` exposing `Shading.color(_:)` and `Shading.linearGradient(_:startPoint:endPoint:)` (CGPoint endpoints), multi-stop gradient `fill`/`stroke` for `Path` and `CGRect` that preserves authored, inset, diagonal, and transformed path-gradient endpoints, `draw` for `BitmapSurface`/`Text`/`String` with `PixelTextStyle`, mutable `opacity` and `transform` with `translateBy`/`scaleBy`/`rotate`/`concatenate`, `clip(to:)` plus `popClip()`, and `drawLayer { sub in ... }` for parent-transform-inheriting sub-contexts whose mutations do not leak back out; the frame fallback still reduces path gradients to their first stop
- Path hit testing: `Path.contains(_:eoFill:)` flattens curves/arcs and ray-casts to support both non-zero winding (default) and even-odd fill rules
- Shared-source support: `CGFloat`/`CGPoint`/`CGSize`/`CGRect` aliases and minimal `Binding` with dynamic-member projections, mutable-collection element bindings, and optional bridging / `State` / `Environment` / `EnvironmentValues` including scene phase, capture/luminance/tab-section/background-prominence metadata, control active appearance, presentation state, multiple-window support metadata, edit mode, focus state/effect metadata, focused values, size classes, display scale, pixel length, calendar/time zone/locale, dismiss, search dismissal, rename, refresh, review request, window/settings actions, undo manager, default app storage, button/menu/scroll input metadata, and accessibility preference/state values / `AppStorage` and `SceneStorage` optional primitive storage plus optional and non-optional raw-value enum persistence / `ObservableObject` with subscribable `objectWillChange` / `Just` / `PassthroughSubject` including `Void.send()` / `CurrentValueSubject` / `AnyPublisher` / `Published` projected publisher sink, `assign(to:on:)`, `eraseToAnyPublisher`, `map`, `compactMap`, `filter`, `dropFirst`, `removeDuplicates`, `AnyCancellable` storage, and `onReceive` subscription / `ObservedObject` and `StateObject` with projected member bindings
- Modernized defaults: rounded translucent button chrome, hover/focus/press states, and softer glass-style surface styling in the demo
- Text fitting: `minimumScaleFactor(_:)` reduces the retained effective text size before truncation when constrained width requires it, and `lineLimit(_:reservesSpace:)` reserves retained measurement height for the requested line count across native and pixel text paths. Wrapped paragraphs and horizontal stacks measure height at their allocated widths; shrinking transforms rasterize glyphs at the effective device size
- Motion: value-triggered animations and scoped transactions preserve in-flight retained properties across unrelated rebuilds. Spring evaluation and runtime-owned scroll momentum use consistent elapsed-time behavior; native wheel streams are not given a second synthetic glide. Remaining animation and scrolling limits are listed in [CompatibilityStatus](docs/CompatibilityStatus.md)

Current gaps:

- This is not full SwiftUI API parity
- Observation support is intentionally small and tuned for retained-runtime invalidation
- Text on the frame fallback path still uses native bitmap draws; the default scene path now has a runtime-owned logical layout cache, subtree layout/measurement reuse, runtime-owned prepaint dispatch state plus split deferred-subtree prepaint and deferred paint replay for interaction/focus/late-paint metadata and ancestor routing, semantic content masks, inherited-opacity propagation, and DirectWrite glyph-run capture, but it still lacks GPUI-style shaped runs, per-deferred prepaint replay ranges, subpixel sprite families, and text-system-owned line layout
- `D3D11Renderer` only executes `fillRect` and `drawBitmap`; the default scene path currently covers shadows, quads, paths (incl. `Canvas` content), and atlas-backed glyphs
- Canvas's complete blend/filter/layer behavior and `withCGContext` escape hatch remain incomplete. Tagged `symbols:` and `GraphicsContext.resolveSymbol(id:)` use the retained scene path; [Canvas symbols](docs/CanvasSymbols.md) records its limits

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
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Filter RetainedViewRuntimeTests
```

The screenshot helper builds the same shared demo view through the WinSwiftUI
retained runtime, pulls the raw scene/frame data, rasterizes it offscreen, and
writes `artifacts/demo-screenshot.png`. Use
`-Screen dashboard|settings|data|gallery` to render one particular tab,
`-AllScreens` for all four, or `-FrameDebug` to force the `RenderFrame` fallback
path for visual comparison.

The separate retained-runtime visual gallery contains 144 examples, including
85 reviewed dark, interaction-state, and light-appearance regression fixtures.
Its generated review portal supports searching and filtering examples, while
the regression gate can list or compare selected fixture groups:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gallery-compare.ps1 -List
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gallery-compare.ps1 -Appearance light
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gallery-compare.ps1 -Pattern "canvas-*"
```

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

- [`Sources/WinSwiftUI/Core.swift`](Sources/WinSwiftUI/Core.swift)
- [`Sources/WinSwiftUI/Views.swift`](Sources/WinSwiftUI/Views.swift)
- [`Sources/WinSwiftUI/App.swift`](Sources/WinSwiftUI/App.swift)
- [`Sources/swift-windowsui/AppEntry.swift`](Sources/swift-windowsui/AppEntry.swift)
- [`Sources/SwiftWindowsDemo/DemoDashboard.swift`](Sources/SwiftWindowsDemo/DemoDashboard.swift)
- [`Sources/SwiftWindowsDemo/DemoGalleryScreen.swift`](Sources/SwiftWindowsDemo/DemoGalleryScreen.swift)
- [`Sources/swift-windowsui-gallery/GalleryMain.swift`](Sources/swift-windowsui-gallery/GalleryMain.swift)
- [`Sources/WinSwiftUI/RenderSnapshot.swift`](Sources/WinSwiftUI/RenderSnapshot.swift)
- [`Sources/SwiftWindowsGraphics/SceneRasterizer.swift`](Sources/SwiftWindowsGraphics/SceneRasterizer.swift)
- [`Sources/SwiftWindowsUI/Runtime.swift`](Sources/SwiftWindowsUI/Runtime.swift)
- [`Sources/SwiftWindowsUI/Controls.swift`](Sources/SwiftWindowsUI/Controls.swift)
- [`Sources/SwiftWindowsPlatform/Win32Host.swift`](Sources/SwiftWindowsPlatform/Win32Host.swift)
- [`Sources/SwiftWindowsRendererD3D11/D3D11Renderer.swift`](Sources/SwiftWindowsRendererD3D11/D3D11Renderer.swift)

## Documentation

Additional framework notes live in [`docs/WinSwiftUI.md`](docs/WinSwiftUI.md).
Ordinary mounted `@State` ownership, dynamic-property installation, and their
current toolchain and lifetime limits are in
[`docs/MountedState.md`](docs/MountedState.md).
The fixed desktop SDK audit baseline and capture procedure live in
[`docs/SwiftUIBaseline.md`](docs/SwiftUIBaseline.md). The API audit ledger
format and its unreviewed evidence limits are in
[`docs/SwiftUIAPIAudit.md`](docs/SwiftUIAPIAudit.md). The current application
templates, persistence adapters, and remaining catalog requirements are in
[`docs/TemplateCatalog.md`](docs/TemplateCatalog.md).
Testing and visual-check commands live in [`docs/Testing.md`](docs/Testing.md).
Release history and the versioning policy live in [`CHANGELOG.md`](CHANGELOG.md); the release smoke procedure lives in [`docs/ReleaseChecklist.md`](docs/ReleaseChecklist.md). Enforced performance budgets are listed in [`docs/PerformanceBudgets.md`](docs/PerformanceBudgets.md).
Agent handoff and architecture guardrails live in [`AGENTS.md`](AGENTS.md), which `CLAUDE.md` imports.
