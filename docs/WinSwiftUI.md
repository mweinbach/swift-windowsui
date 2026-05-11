# WinSwiftUI

`WinSwiftUI` is the SwiftUI-shaped layer for the retained Windows runtime.

Its job is not to imitate SwiftUI internally. Its job is to let app code use a familiar SwiftUI-style surface while mapping directly into:

- `RetainedViewRuntime`
- `ViewNode`
- `RenderFrame`
- `GPUIScene`
- `Win32Window`
- `D3D11Renderer`
- `D3D11BatchRenderer`

The default demo path now uses `GPUIScene` -> `D3D11BatchRenderer`, with
`RenderFrame` -> `D3D11Renderer` kept as an automatic fallback and explicit
debug override.

To force the frame fallback locally:

```powershell
$env:SWIFT_WINDOWSUI_FRAME_DEBUG = "1"
swift run swift-windowsui
```

The host also keeps a coalesced frame pump alive during resize, scroll, and
other high-rate input instead of forcing synchronous redraws directly from each
event callback. Duplicate invalidates are coalesced, and high-rate input only
extends the timer when an interaction actually dirtied presentation state.

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
  - `Text(verbatim:)`
  - `StringProtocol` inputs
  - `LocalizedStringKey` inputs
  - flattened `Text + Text` concatenation
- `Image(_:)`
  - `Image(_:bundle:label:)`
  - `Image(decorative:bundle:)`
- `Image(systemName:)`
  - `Image(systemName:variableValue:)`
  - `resizable(capInsets:resizingMode:)`
- `LabeledContent`
  - `StringProtocol` title inputs
  - title/value inputs
- `Label`
  - `StringProtocol` title inputs
  - `Label { title } icon: { icon }`
- `Link`
  - `StringProtocol` title inputs
  - `Link(destination:label:)`
- `SettingsLink`
- `ContentUnavailableView`
  - `ContentUnavailableView(_:systemImage:description:)`
  - builder label/description/actions forms
  - `ContentUnavailableView.search`
- `Rectangle`
- `RoundedRectangle(cornerRadius:style:)`
- `Capsule(style:)`
- `Circle`
- `Ellipse`
- `Shape`
- `Spacer`
- `Divider`
- `Group`
- `ForEach`, including open and closed integer ranges
- `GeometryReader`
- `ViewThatFits`
- `NavigationStack`
- `NavigationView`
- `NavigationSplitView`
- `NavigationLink`
  - `NavigationLink { destination } label: { label }`
  - `StringProtocol` title inputs
- `TabView`
- `VStack`
- `HStack`
- `LazyVStack`
- `LazyHStack`
- `Grid`
- `GridRow`
- `ZStack`
- `ScrollView`
- `List`
  - `List(data, id:content:)`
  - `List(data, content:) where Element: Identifiable`
- `Form`
- `Section`
  - `StringProtocol` title inputs
  - `Section { content } header: { header } footer: { footer }`
- `GroupBox`
  - `StringProtocol` title inputs
- `DisclosureGroup`
  - `StringProtocol` title inputs
- `ControlGroup`
  - `StringProtocol` title inputs
- `HSplitView`
- `VSplitView`
- `Menu`
  - `StringProtocol` title inputs
  - `Menu(_:systemImage:content:)`
- `Button`
  - `StringProtocol` title inputs
  - `Button(_:systemImage:...)`
  - `ButtonRole.destructive`
  - `ButtonRole.cancel`
- `RenameButton`
- `EditButton`
- `TextField`
  - `prompt: Text?` overloads
  - `axis:` overloads
- `SecureField`
  - `prompt: Text?` overloads
- `TextEditor`
- `DatePicker`
  - date/time displayed component options
  - closed and partial-range initializer overloads
- `ColorPicker`
  - `supportsOpacity` initializer labels
- `Toggle`
  - `StringProtocol` title inputs
- `Picker`
  - `StringProtocol` title inputs
  - `.pickerStyle(.segmented)`
  - `.pickerStyle(.menu)`
- `Stepper`
  - `StringProtocol` title inputs
  - `onIncrement` / `onDecrement` action overloads
- `Slider`
  - `Slider(value:in:step:onEditingChanged:)`
  - minimum, maximum, and main label overloads
- `ProgressView`
  - `StringProtocol` title inputs
  - title, label, and current-value label overloads
- `Gauge`
  - `StringProtocol` title inputs
  - label, current-value, minimum-value, and maximum-value label overloads

Modifiers:

- `frame`, including fixed and min/ideal/max overloads
- `fixedSize`
- `ignoresSafeArea`
- `edgesIgnoringSafeArea`
- `safeAreaPadding`
- `aspectRatio`
- `scaledToFit`
- `scaledToFill`
- `padding`
  - optional-length overloads such as `padding(nil)` and `padding(.horizontal, nil)`
- `background`, including stored `ForegroundStyle`, optional `Color?` inputs, and `ignoresSafeAreaEdges:` color/gradient/style overloads
- `background(_:alignment:)`
- `background(alignment:content:)`
- `overlay`, including color/gradient/stored `ForegroundStyle` overloads
- `overlay(_:alignment:)`
- `overlay(alignment:content:)`
- `foregroundColor`, including optional `Color?` inputs
- `foregroundStyle` for solid `Color`, stored `ForegroundStyle`, `LinearGradient` shape fills, and primary-style multi-argument overloads
- `imageScale`
- `tint`, including optional `Color?` inputs
- `accentColor`
- `buttonStyle`
- `buttonRepeatBehavior`
- `buttonSizing`
- `buttonBorderShape`
- `menuIndicator`
- `pickerStyle`
- `labelStyle`
- `toggleStyle`
- `textFieldStyle`
- `labelsHidden`
- `controlSize`
- `navigationTitle`
- `navigationBarTitle`
- `navigationBarTitleDisplayMode`
- `navigationDestination`
- `tabItem`
- `environment`
- `transformEnvironment`
- `focusedValue`
- `focusedSceneValue`
- `preferredColorScheme`
- `dynamicTypeSize`
- `font`
- `fontDesign`
- `fontWeight`
- `bold`
- `monospaced`
- `multilineTextAlignment`
- `lineLimit`
  - `lineLimit(_:reservesSpace:)`
- `minimumScaleFactor`
- `truncationMode`
- `lineSpacing`
- `kerning`
- `tracking`
- `allowsTightening`
- `textCase`
- `textInputAutocapitalization`
- `autocorrectionDisabled`
- `underline`
- `strikethrough`
- `cornerRadius(_:antialiased:)`
- `clipped(antialiased:)`
- `clipShape(_:style:)`
- `contentShape`
- `border`, including stored `ForegroundStyle` and `LinearGradient` overloads
- `shadow`, including SwiftUI-style default-color `shadow(radius:x:y:)`
- `layoutPriority`
- `gridCellColumns`
- `allowsHitTesting`
- `focusable`
- `hoverEffect`
- `defaultHoverEffect`
- `hoverEffectDisabled`
- `focusEffectDisabled`
- `keyboardShortcut`
- `redacted`
- `unredacted`
- `privacySensitive`
- `opacity`
- `hidden`
- `zIndex`
- `offset`
- `scaleEffect`
- `rotationEffect`
- `blur`
- `animation`
- `disabled`
- `scrollDisabled`
- `scrollClipDisabled`
- `scrollContentBackground`
- `scrollIndicators`
- `scrollDismissesKeyboard`
- `defaultWheelPickerItemHeight`
- `listRowBackground`
- `listRowInsets`
- `listRowSpacing`
- `listStyle`
- `headerProminence`
- `badge`
- `badgeProminence`
- `task`
- `searchable`
- `renameAction`
- `onAppear`
- `onDisappear`
- `onChange`
- `onSubmit`
- `submitScope`
- `submitLabel`
- `onHover`
- `onTapGesture`
- `accessibilityLabel`
- `accessibilityValue`
- `accessibilityHint`
- `accessibilityIdentifier`
- `accessibilityHidden`
- accessibility preference/state environment values: `accessibilityAssistiveAccessEnabled`, `accessibilityDimFlashingLights`, `accessibilityDifferentiateWithoutColor`, `accessibilityEnabled`, `accessibilityInvertColors`, `accessibilityLargeContentViewerEnabled`, `accessibilityPlayAnimatedImages`, `accessibilityPrefersHeadAnchorAlternative`, `accessibilityQuickActionsEnabled`, `accessibilityReduceHighlightingEffects`, `accessibilityReduceMotion`, `accessibilityReduceTransparency`, `accessibilityShowButtonShapes`, `accessibilityShowBorders`, `accessibilitySwitchControlEnabled`, and `accessibilityVoiceOverEnabled`
- `help`
- `tag`
- `modifier`

Compatibility helpers:

- `ViewModifier`
- `ViewModifier.Content`
- `ModifiedContent`
- `ListStyle`
- `Color(red:green:blue:opacity:)`
- `Color(white:opacity:)`
- `Color(hue:saturation:brightness:opacity:)`
- common `Color` constants such as `red`, `blue`, `gray`, `primary`, `secondary`, and `accentColor`
- `Color.opacity(_:)`
- named `Font` styles such as `body`, `title`, `headline`, and `caption`
- `Font.system(_:design:weight:)` with `Font.TextStyle` presets
- `Font.monospaced()`
- `Animation`
- `withAnimation`
- `LinearGradient(colors:startPoint:endPoint)`
- `UnitPoint`
- `Angle`
- `Axis`
- `HoverEffect`
- `RedactionReasons`
- `ColorSchemeContrast`
- `LegibilityWeight`
- `LayoutDirection`
- `DynamicTypeSize`
- `KeyEquivalent`
- `EventModifiers`
- `KeyboardShortcut`
- `ButtonRepeatBehavior`
- `ButtonSizing`
- `ButtonBorderShape`
- `ScrollDismissesKeyboardMode`
- `SubmitTriggers`
- `SubmitLabel`
- `TextInputAutocapitalization`
- `Visibility`
- `Prominence`
- `BackgroundProminence`
- `BadgeProminence`
- `ScenePhase`
- `ControlActiveState`
- `EditMode`
- `RefreshAction`
- `DismissSearchAction`
- `RenameAction`
- `SearchFieldPlacement`
- `OpenWindowAction`
- `DismissWindowAction`
- `OpenSettingsAction`
- `RequestReviewAction`
- `FocusedValueKey`
- `FocusedValues`
- `FocusedValue`
- `FocusedBinding`
- `UndoManager`
- `UserInterfaceSizeClass`
- `LocalizedStringKey`
- `CGFloat`, `CGPoint`, `CGSize`, `CGRect` aliases
- `EdgeInsets()`
- minimal `Binding`, `State`, `Environment`, `EnvironmentValues`, `FocusedValue`, `FocusedBinding`, `OpenURLAction`, `DismissAction`, `DismissSearchAction`, `RenameAction`, `RefreshAction`, `OpenWindowAction`, `DismissWindowAction`, `OpenSettingsAction`, `RequestReviewAction`, `UndoManager`, `EditMode`, `ObservableObject`, `Published`, `ObservedObject`, and `StateObject`

Surface direction:

- default retained buttons now use lighter rounded chrome with hover, focus, press, and activation transitions
- the demo’s cards and chips are built from shared-source-friendly layered gradients and translucent strokes rather than WinSwiftUI-only styling hooks

## Mapping Notes

- `Text` maps into retained label nodes and the current runtime text renderer path.
- `LocalizedStringKey` is a source-compatibility shim that resolves to plain retained text today; it does not perform bundle lookup or real localization yet. Common title-bearing controls and titled containers also accept `StringProtocol` inputs such as `Substring` and forward them through the same retained label paths as `String` titles.
- Named `Font` styles and `Font.system(_:design:weight:)` text-style overloads are fixed point-size and weight presets before environment scaling. `dynamicTypeSize(_:)` and `EnvironmentValues.dynamicTypeSize` scale retained `Text` and text-input font sizes with SwiftUI-shaped cases from `.xSmall` through `.accessibility5`; this is a deterministic retained scale table, not a Windows system text-size subscription yet. `legibilityWeight(_:)` and `EnvironmentValues.legibilityWeight` accept `.regular`, `.bold`, or `nil`; retained text maps that value through the existing font-weight path unless an explicit `.fontWeight(_:)` overrides it. This is an inherited compatibility value, not yet a Windows Bold Text accessibility subscription. `Font.monospaced()`, `Text.monospaced()`, and `fontDesign(_:)` resolve through the same retained font family mapping as `.system(..., design: .monospaced)`. `font(_:)` accepts `Font?`, bridges through `EnvironmentValues.font`, and `.font(nil)` resets a subtree to the retained default font. `Text.fontWeight(nil)` clears a previously applied explicit text weight while preserving inherited container weight when no explicit text font is present.
- SwiftUI-shaped RGB, white, and HSB `Color` initializers reduce to the renderer-neutral RGBA color type used by the retained scene.
- `frame(minWidth:idealWidth:maxWidth:minHeight:idealHeight:maxHeight:alignment:)` maps finite constraints into retained `LayoutConstraints`; infinite maximum values are accepted for call-site compatibility, with expansion still depending on the surrounding retained layout mode.
- `fixedSize()` and `fixedSize(horizontal:vertical:)` map to retained measurement axes that ignore incoming maximum constraints on selected axes; final placement can still be limited by the parent layout mode.
- `padding` accepts SwiftUI-style optional lengths; `nil` resolves to the retained default of `16`.
- `ignoresSafeArea` and `edgesIgnoringSafeArea` are accepted for source compatibility but currently pass through unchanged because the Win32 host renders into a client-area surface with no derived unsafe insets. `safeAreaPadding` maps onto the retained padding wrapper, so shared-source layouts that request safe-area padding still get deterministic retained spacing on Windows.
- `EnvironmentValues.scenePhase` accepts `.active`, `.inactive`, and `.background`, defaults to `.active`, and can be overridden with `.environment(\.scenePhase, ...)` for shared-source app logic. Hosted Win32 windows update this value from app activation and visibility events, mapping visible active windows to `.active`, visible inactive windows to `.inactive`, and hidden windows to `.background`.
- `EnvironmentValues.controlActiveState` accepts `.key`, `.active`, and `.inactive`, while `EnvironmentValues.appearsActive` provides the newer Boolean active-appearance hint. Hosted Win32 windows map the single live window to `.key` while active and visible, `.inactive` while inactive or hidden, and update `appearsActive` from the same active/visible state.
- `EnvironmentValues.isLuminanceReduced`, `EnvironmentValues.isSceneCaptured`, and `EnvironmentValues.isTabBarShowingSections` are readable and overrideable compatibility values. They default to `false`; the Win32 host does not yet derive them from display power/luminance policy, capture/recording state, or adaptive tab layout.
- `EnvironmentValues.isPresented` defaults to `false` and becomes `true` for retained `NavigationStack` / `NavigationView` destination content, including path, pushed link, and binding-driven navigation destinations. Other presentation APIs such as sheets, popovers, alerts, and native windows are not modeled yet.
- `EnvironmentValues.supportsMultipleWindows` is readable and overrideable for shared-source scene/window conditionals. It defaults to `false` because the current WinSwiftUI host boots one live `WindowGroup`; multi-window lifecycle support is not implemented yet.
- `EnvironmentValues.editMode` accepts an optional `Binding<EditMode>` with `.inactive`, `.transient`, and `.active` values. `EditButton` reads that binding and toggles between `.inactive` and `.active`; retained `List` rows do not yet implement reorder/delete edit chrome.
- `EnvironmentValues.layoutDirection` accepts `.leftToRight` and `.rightToLeft`. Right-to-left direction flips retained leading/trailing alignment for `Text`, `Image(systemName:)`, text inputs, `frame(alignment:)`, `background(_:alignment:)`, `overlay(_:alignment:)`, `VStack`, `LazyVStack`, `Grid`, `ZStack`, `ScrollView`, and `Section`; it does not yet mirror arbitrary custom drawing or bitmap content.
- `EnvironmentValues.horizontalSizeClass` and `EnvironmentValues.verticalSizeClass` accept optional `.compact` / `.regular` `UserInterfaceSizeClass` values for shared-source adaptive layout checks. Hosted windows derive them from the current logical window size using WinSwiftUI's retained surface thresholds, and explicit environment overrides still take precedence inside modified subtrees.
- `EnvironmentValues.openWindow` and `EnvironmentValues.dismissWindow` provide SwiftUI-shaped scene action shims with `id:` and `Codable & Hashable` value overloads. The default actions are no-ops. Injected handlers can keep using the optional-id initializer or receive a `WindowActionPayload` containing the optional id and type-erased `Hashable` value. WinSwiftUI does not yet host multiple live windows or route typed scene values into `WindowGroup` content.
- `EnvironmentValues.openSettings` provides a SwiftUI-shaped `OpenSettingsAction`, and `SettingsLink` maps to a retained button that calls it. The default action is a no-op because WinSwiftUI does not yet model a `Settings` scene or native settings window lifecycle.
- `EnvironmentValues.requestReview` provides a SwiftUI/StoreKit-shaped `RequestReviewAction`. The default action is a no-op because Windows builds do not have App Store review prompt integration, but apps and tests can inject a handler for shared-source flows.
- `FocusedValueKey`, `FocusedValues`, `@FocusedValue`, `@FocusedBinding`, `focusedValue(_:_:)`, and `focusedSceneValue(_:_:)` are retained-context compatibility shims. Published focused values propagate through the modified subtree, and focused bindings can read/write their current binding, but the runtime does not yet retarget those values dynamically as native focus moves between nodes.
- `EnvironmentValues.undoManager` accepts an optional `UndoManager` for shared-source command and editing code. WinSwiftUI provides a small Windows shim with `registerUndo(withTarget:handler:)`, `setActionName(_:)`, `undo()`, `redo()`, `removeAllActions()`, and basic stack state; hosted windows install a stable per-window default undo manager, but it is not yet bridged to native edit commands.
- Text and foreground styling modifiers on containers propagate through `ViewBuildContext`, while explicit `Text`, `Image`, and `Label` styling still takes precedence. Solid `foregroundStyle` maps to inherited text/icon color, including stored `ForegroundStyle.color` values and semantic color shorthand such as `.foregroundStyle(.secondary)`. `EnvironmentValues.colorSchemeContrast` accepts `.standard` and `.increased`; increased contrast brightens retained `.secondary` foreground values for text, icons, labels, and inherited foreground styles, but it is not yet wired to Windows high-contrast settings or a full semantic color system. Multi-argument `foregroundStyle` overloads are accepted for source compatibility and currently use the primary style because retained nodes do not model hierarchical foreground style slots yet. `LinearGradient` and stored `ForegroundStyle.linearGradient` values map to retained gradient fills for `Rectangle`, `RoundedRectangle`, `Capsule`, `Circle`, and `Ellipse`, while text/icons use the gradient start color as a compatibility fallback. `background` and `overlay` also accept stored `ForegroundStyle` values and route them through the existing retained color/gradient panel paths. `Circle` uses the retained dynamic rounded path, and `Ellipse` currently uses the same capsule-style rounded fallback until true elliptical retained primitives are added. Shape `fill(_:)` also accepts stored `ForegroundStyle` values. `Text + Text` is accepted for source compatibility and flattens into one retained label; because retained text nodes do not have rich text runs yet, explicit styling resolves to a single node style with left-hand styling taking precedence when both sides set the same property. `lineSpacing(_:)`, `Text.kerning`, and `Text.tracking` map to retained text style; line spacing participates in retained measurement, while letter spacing is carried into the renderer text style for pixel/text-atlas paths. `minimumScaleFactor(_:)` is clamped to `0...1` and now reduces the effective retained text size before truncation when constrained width requires it, across DirectWrite, GDI, pixel fallback, and GPUI glyph scene paths. `allowsTightening(_:)` maps to the retained text kerning toggle until true glyph tightening is modeled. `textCase(_:)` applies inherited or explicit uppercase/lowercase transforms before retained label creation. `lineLimit(_:reservesSpace:)` maps the maximum line count and reserves retained measurement height for that many lines when requested. `multilineTextAlignment(_:)`, `lineLimit(_:)`, `lineSpacing(_:)`, `minimumScaleFactor(_:)`, `truncationMode(_:)`, `allowsTightening(_:)`, and `textCase(_:)` bridge through `EnvironmentValues`, so `@Environment` and `.environment(\.lineLimit, ...)` see the same inherited retained text values. `truncationMode(_:)` maps `.head`, `.tail`, and `.middle` to the retained text line-break modes when a line limit is active. `Text.underline` and `Text.strikethrough` map to retained text decoration flags; decoration colors are accepted for source compatibility but currently use the text color.
- `imageScale(_:)` propagates through `EnvironmentValues` and maps `.small`, `.medium`, and `.large` to retained symbol icon scale for `Image(systemName:)` and label icons.
- `tint` and `accentColor` propagate through `ViewBuildContext`; retained controls consume the inherited tint for toggle-on, slider-fill, progress-fill, and gauge-fill colors.
- `labelsHidden()` propagates through `ViewBuildContext` and suppresses retained label nodes for controls such as `Toggle`, `Picker`, `Stepper`, `Slider`, `ProgressView`, and `Gauge`.
- `EnvironmentValues.displayScale` and `EnvironmentValues.pixelLength` are populated from the retained runtime's current surface scale for hosted windows and `WinSwiftUIRendererSnapshotter` snapshots. They can also be overridden with `.environment(\.displayScale, ...)` and `.environment(\.pixelLength, ...)`; changing `displayScale` manually does not recompute `pixelLength` unless both values are set.
- `font(_:)`, `dynamicTypeSize(_:)`, `legibilityWeight(_:)`, `tint(_:)`, `accentColor(_:)`, `buttonRepeatBehavior(_:)`, `buttonSizing(_:)`, `buttonBorderShape(_:)`, `menuIndicator(_:)`, `submitLabel(_:)`, and `controlSize(_:)` bridge into `EnvironmentValues`, so `@Environment(\.font)`, `@Environment(\.dynamicTypeSize)`, `@Environment(\.legibilityWeight)`, `@Environment(\.tint)`, `@Environment(\.buttonRepeatBehavior)`, `@Environment(\.buttonSizing)`, `@Environment(\.buttonBorderShape)`, `@Environment(\.menuIndicatorVisibility)`, `@Environment(\.submitLabel)`, `@Environment(\.controlSize)`, `.environment(\.font, ...)`, `.environment(\.dynamicTypeSize, ...)`, `.environment(\.legibilityWeight, ...)`, `.environment(\.tint, ...)`, `.environment(\.buttonRepeatBehavior, ...)`, `.environment(\.buttonSizing, ...)`, `.environment(\.buttonBorderShape, ...)`, `.environment(\.menuIndicatorVisibility, ...)`, `.environment(\.submitLabel, ...)`, and `.environment(\.controlSize, ...)` share the same inherited values consumed by retained text and controls. Optional `Text.font(_:)` accepts concrete fonts and resets `nil` to the retained default text font. `buttonRepeatBehavior` accepts `.automatic`, `.enabled`, and `.disabled`; retained buttons with `.enabled` repeatedly invoke actions during prolonged pointer presses, while `.automatic` and `.disabled` keep single release activation. `buttonSizing` accepts `.automatic`, `.fitted`, and `.flexible`; `.flexible` maps retained `Button` nodes to layout priority `1`, while `.automatic` and `.fitted` keep the current content-fitted retained button sizing. `buttonBorderShape` accepts `.automatic`, `.roundedRectangle`, `.roundedRectangle(radius:)`, `.capsule`, and `.circle`; rounded rectangle values set retained button corner radii, while capsule/circle values compute a fully rounded retained button radius during layout. `menuIndicatorVisibility` now controls the retained `Menu` disclosure glyph, with `.hidden` suppressing it and `.automatic` / `.visible` showing it.
- `controlSize(_:)` maps to retained preferred sizes for text inputs, toggle, menu picker, stepper buttons, slider, progress bar, and gauge surfaces.
- `labelStyle(_:)` propagates through `EnvironmentValues` and maps `.automatic` / `.titleAndIcon`, `.iconOnly`, and `.titleOnly` to retained `Label` composition.
- `toggleStyle(_:)` propagates through `EnvironmentValues`; `.automatic` and `.switch` use the retained switch, `.checkbox` maps to retained checkbox chrome with arbitrary SwiftUI-shaped label content, and `.button` maps to retained selected/unselected button chrome.
- `textFieldStyle(_:)` propagates through `EnvironmentValues`; `.automatic` and `.roundedBorder` use the retained bordered input chrome, while `.plain` maps to a borderless retained input surface.
- `background(_:alignment:)` and `overlay(_:alignment:)` forward to the retained absolute layering path used by the builder-based overloads.
- `Section` supports title, header, footer, and content-only forms, all mapped to the retained vertical section panel.
- `GroupBox` maps title and builder-label forms to a retained vertical panel with lightweight default chrome.
- `NavigationStack` and `NavigationView` preserve `navigationTitle` / `navigationBarTitle` metadata, render lightweight retained title chrome, and support local push/pop presentation for direct `NavigationLink(destination:)` and `NavigationLink { destination } label: { ... }` links plus `NavigationLink(value:)` routes resolved by `navigationDestination(for:)`. `NavigationStack(path:)` syncs value-link pushes and back navigation with `NavigationPath` or generic mutable collection bindings, including nested path restoration as each resolved destination contributes its own registered destinations. Boolean and item `navigationDestination` overloads render binding-driven retained destinations and clear their bindings through the back control or `@Environment(\.dismiss)`. Platform-native navigation transitions are not implemented yet.
- `NavigationSplitView` maps two- and three-column source-compatible initializers to a retained horizontal stack. `NavigationSplitViewVisibility` bindings drive coarse retained column filtering for `.all`, `.doubleColumn`, and `.detailOnly`; adaptive platform breakpoint collapsing is not implemented yet.
- `TabView` renders retained tab chrome from `.tabItem` labels, shows the first page by default, and shows the page whose `.tag(_:)` matches the `selection:` binding. Activating a tab updates local selection state or writes through a tagged `selection:` binding. Badges applied after `.tabItem` render in the tab chrome instead of the selected page content. Platform-specific tab styling and overflow behavior are still minimal.
- `task(priority:_:)` launches an async Swift task when the retained node first appears and cancels it when that retained subtree disappears. `task(id:priority:_:)` accepts SwiftUI-shaped id call sites, relaunches when rebuilt with a changed id, and cancels the previous retained lifecycle task before starting the replacement.
- `refreshable(action:)` propagates `EnvironmentValues.refresh` as a SwiftUI-shaped async `RefreshAction` for descendant views. Native pull-to-refresh gestures and retained scroll chrome are not implemented yet.
- `searchable(text:placement:prompt:)` and `searchable(text:isPresented:placement:prompt:)` prepend a retained search `TextField` to the modified subtree and propagate `EnvironmentValues.isSearching` plus `EnvironmentValues.dismissSearch` to descendants. `DismissSearchAction` clears the bound text, clears the presentation binding when present, and invalidates the retained runtime. `SearchFieldPlacement` accepts `.automatic`, `.navigationBarDrawer`, `.navigationBarDrawer(displayMode:)`, `.sidebar`, and `.toolbar` for source compatibility; placement-specific native navigation or toolbar integration, token search, scopes, and suggestions are not implemented yet.
- `renameAction(_:)` stores a `RenameAction` in `EnvironmentValues.rename`, and `RenameButton` maps to a retained button that invokes that action when present. The button is disabled when no rename action is available. Native context menu integration and focus-target retargeting are not modeled yet.
- `onAppear` fires when the retained node first renders, `onDisappear` fires when an appeared retained subtree is removed or replaced, and `onChange(of:)` keeps lightweight call-site state so rebuilt SwiftUI-shaped views can observe `Equatable` value transitions.
- `onSubmit(of:_:)` hooks retained Enter key input into SwiftUI-shaped submit actions for text/search triggers on the modified retained subtree. It preserves existing non-submit key handling and invalidates after the submit action runs. `submitScope(_:)` marks a retained subtree boundary that blocks outer submit handlers while allowing handlers inside the scope to run; platform keyboard return-key labels are not modeled yet.
- `submitLabel(_:)` propagates `EnvironmentValues.submitLabel` and stores the requested return-key label on retained `TextField`, `SecureField`, and `TextEditor` nodes as renderer-neutral text-input metadata. It does not alter hardware keyboard behavior on the retained Windows input path today.
- `onHover` opts the retained node into hit testing and forwards pointer enter/exit transitions as `true`/`false`.
- `onTapGesture` opts the retained node into hit testing and handles pointer tap activation. Multi-tap `count` values require consecutive inside releases and reset after an outside release; platform-native tap timing thresholds are not modeled yet.
- `contentShape` and `ContentShapeKinds` are accepted for source compatibility. `.interaction` content shapes now constrain retained pointer hit testing for `Rectangle`, `RoundedRectangle`, `Capsule`, `Circle`, and `Ellipse`; other shape inputs fall back to rectangular interaction geometry. Non-interaction kinds are retained as metadata until focus, preview, hover, and accessibility geometry consume them directly.
- `focusable(_:)` maps to the retained node focus flag and enables hit testing when focusability is turned on. `EnvironmentValues.isFocused` is readable and overrideable, but defaults to `false` because retained focus does not yet flow back into SwiftUI-shaped environment reads. Programmatic `FocusState` bindings are not modeled yet.
- `hoverEffect(_:)`, `defaultHoverEffect(_:)`, `hoverEffectDisabled(_:)`, and `focusEffectDisabled(_:)` store retained interaction-effect metadata for source-compatible call sites. `hoverEffect(_:)` also opts the node into hit testing so the runtime can identify hoverable content, while `focusEffectDisabled(_:)` propagates `EnvironmentValues.isFocusEffectEnabled` to descendants. Lift/highlight rendering and platform focus-effect visuals are not drawn yet.
- `keyboardShortcut(_:)` stores retained shortcut metadata on the modified node and routes matching `RetainedViewRuntime.keyDown` events to that node's activation handler. SwiftUI `.command` shortcuts map to Windows Control-key shortcuts, `.option` maps to Alt, and `.defaultAction` / `.cancelAction` use Enter / Escape without modifiers. Menu command routing and platform-reserved shortcut arbitration are not modeled yet.
- `redacted(reason:)` and `unredacted()` propagate `EnvironmentValues.redactionReasons` and store retained redaction metadata on affected nodes. Placeholder redaction draws renderer-neutral rounded placeholder fills for retained text and bitmap nodes on both the frame and GPUI scene paths.
- `privacySensitive(_:)` propagates inherited privacy metadata and stores it on retained nodes. The Win32 host does not yet request OS-level capture exclusion or automatic redaction for privacy-sensitive surfaces.
- Accessibility preference/state environment values for assistive technology state, Assistive Access, flashing-light reduction, differentiating without color, inverting colors, large content viewer, animated-image playback, head-anchor alternatives, quick actions, bright-effect reduction, motion reduction, transparency reduction, showing button shapes, showing borders, Switch Control, and VoiceOver can be read with `@Environment` and overridden with `.environment`. `accessibilityPlayAnimatedImages` defaults to `true`; the other accessibility booleans default to `false`. `accessibilityReduceMotion` suppresses retained `.animation(...)` state creation for affected subtrees; the other values are compatibility metadata until the retained control, accessibility, and rendering layers consume them visually or subscribe to Windows system settings.
- `Image(systemName:)` maps known SF Symbol names into the project icon set.
- `Image(_:bundle:label:)`, `Image(decorative:bundle:)`, and `Image(systemName:variableValue:)` are accepted for source compatibility and reuse the same retained bitmap/icon rendering paths. Image labels and decorative flags map to retained accessibility metadata; variable symbol values are stored on retained icon nodes as API-shape compatibility metadata until variable SF Symbol rendering exists.
- `Image(systemName:)` currently resolves to retained icon labels that render through the scene glyph atlas or the frame fallback text path.
- `Image(_:)` resolves direct file paths or bundle resources through the WIC-backed image loader and maps decoded bitmaps onto retained bitmap nodes that emit `DrawBitmapCommand`/`ImagePrimitive` resources. PNG/JPEG/BMP resources are supported through WIC; asset-catalog lookup is not implemented yet.
- `Image.resizable`, image `aspectRatio`, `scaledToFit`, and `scaledToFill` map system icon glyphs and decoded bitmap images to retained preferred sizes based on font size or native bitmap size, image scale, and aspect ratio. Generic view `aspectRatio`, `scaledToFit`, and `scaledToFill` wrap retained content with a preferred-size container derived from the child intrinsic size. `resizingMode` is retained as compatibility metadata; real tile rendering is not implemented yet.
- `LabeledContent` maps title/value and builder-label forms to a retained horizontal row with secondary leading label text and trailing content, matching common settings and form call sites without adding native control dependencies.
- `Link` maps title and builder labels onto a retained plain button. Activation calls `EnvironmentValues.openURL`, whose default action asks the Windows shell to open the destination URL; tests and apps can inject an `OpenURLAction` through `.environment(\.openURL, ...)`.
- `ContentUnavailableView` maps placeholder label, description, and action builders to retained centered vertical chrome. The title/system-image and search convenience forms reuse retained `Label` / text / button composition; platform-specific empty-state styling is intentionally minimal.
- `ViewThatFits(in:_:)` chooses the first retained child whose intrinsic size fits the current build context canvas along the requested axes, then falls back to the last child when none fit. It does not yet perform SwiftUI-style proposal probing through nested layout.
- Custom `ViewModifier` types work through `modifier(_:)` and rebuild their body into the retained component pipeline. The compatibility wrapper preserves common metadata such as tags and tab items from the modified content, but advanced SwiftUI modifier identity and transaction semantics are not modeled yet.
- `listStyle(_:)` stores a SwiftUI-shaped `ListStyle` in `EnvironmentValues` and maps `plain`, `grouped`, `inset`, `insetGrouped`, and `sidebar` styles to retained scroll-panel spacing, padding, and chrome. It is a compatibility value, not SwiftUI's protocol-based custom list style system.
- `Rectangle`, `RoundedRectangle`, `Capsule`, `Circle`, and `Ellipse` map to retained fill/border/corner-radius nodes; `fill` uses explicit colors or the inherited foreground style, `stroke` and `strokeBorder` accept `Color`, stored `ForegroundStyle`, `LinearGradient`, and `StrokeStyle` overloads. `StrokeStyle.lineWidth` maps to retained border width; line caps, joins, miter limits, and dash patterns are accepted for source compatibility but are not rendered by the retained border path yet. Rounded corner styles currently share the same retained rounded-rect path.
- `Divider()` maps to a retained separator node and picks a horizontal or vertical preferred size from the inherited stack axis.
- `ForEach` expands into builder children instead of adding an extra layout wrapper, and generated children receive stable retained node tags derived from the SwiftUI-style id. `Range<Int>` and `ClosedRange<Int>` support the SwiftUI-style shorthand initializer.
- `VStack`, `HStack`, `LazyVStack`, and `LazyHStack` accept SwiftUI-style optional spacing; `nil` resolves to the current retained default spacing of `0`. Lazy stacks currently map to the same retained stack panels as eager stacks, and accept `pinnedViews` for source compatibility without sticky section behavior yet.
- `Grid` and `GridRow` map to retained vertical and horizontal stack panels. `Grid` accepts SwiftUI-shaped alignment and spacing parameters, with vertical spacing, horizontal row spacing, and row alignment mapped today. `gridCellColumns(_:)` maps to retained horizontal growth priority so simple spanning call sites can claim more row space, but full SwiftUI column sizing, spanning, and grid-cell alignment semantics are not implemented yet.
- `Button` maps into retained button controls and preserves focus/press/activate animation state.
- `Button` now also resolves hover-aware border and shadow states so retained controls feel closer to modern desktop/mobile system chrome.
- `Button(_:systemImage:...)` maps into the existing retained button path with a `Label`; `.buttonStyle` propagates through `ViewBuildContext`, with `.bordered` and `.borderedProminent` mapping to the default retained button chrome and `.borderless` mapping to plain chrome.
- `Toggle` maps into the retained switch control and writes through a SwiftUI-shaped `Binding<Bool>`.
- `Picker` maps tagged child content into a retained segmented selection group by default and writes through a SwiftUI-shaped `Binding` when an option activates. `.tag(_:)` supplies the SwiftUI-style selection value; untagged options fall back to integer indices for `Binding<Int>` pickers. `.pickerStyle(.menu)` maps the same tagged options into the retained dropdown control using the first retained text node as the option title.
- `Stepper` maps to a retained horizontal stack with label content and two retained buttons that mutate `Binding<Int>` or `Binding<Double>` values.
- `Slider(value:in:)` maps into the retained draggable slider and writes through a SwiftUI-shaped `Binding<Double>`. The `step` initializer snaps written values relative to the lower bound and reports drag editing state through the retained control lifecycle. Minimum, maximum, and main label overloads wrap the retained slider in small retained stacks while preserving the same binding/editing behavior.
- `ProgressView(value:total:)` maps into the retained progress bar control; title, builder-label, and current-value label overloads wrap that retained bar in small retained stacks.
- `Gauge(value:in:)` maps SwiftUI-shaped scalar gauges onto the retained progress bar control. Title, current-value, minimum-value, and maximum-value label builders compose retained label chrome around the same renderer-neutral fill primitive, with `.tint` driving the filled segment.
- Accessibility modifiers store retained metadata on `ViewNode` (`label`, `value`, `hint`, `identifier`, and hidden state) so the tree has stable semantic data. `help(_:)` maps to the same retained hint metadata for desktop shared-source compatibility. Native Win32 UI Automation exposure is not implemented yet.
- `cornerRadius(_:antialiased:)` maps to a retained rounded rectangular clipping wrapper; the antialiasing flag is accepted for call-site compatibility but is not distinguished by the retained renderer today.
- `clipped(antialiased:)` maps to retained rectangular bounds clipping; the antialiasing flag is accepted for call-site compatibility but is not distinguished by the retained renderer today.
- `clipShape(_:style:)` maps `Rectangle`, `RoundedRectangle`, and `Capsule` to retained bounds clipping with matching retained corner-radius behavior. Other `Shape` conformers currently degrade to rectangular clipping until renderer-neutral path clipping grows beyond the existing render graph fallback.
- `border` maps to retained panel border fields. Stored `ForegroundStyle.color` values map directly, while gradient border inputs use the gradient start color until renderer-neutral gradient stroke primitives exist.
- `opacity(_:)` and `hidden(_:)` map directly onto retained node paint and visibility state.
- `zIndex(_:)`, `offset`, `scaleEffect`, and `rotationEffect` map directly onto retained node ordering and `Transform2D` state.
- `blur(radius:)` maps directly onto retained node blur radius state. Blur commands are still backend-limited as noted below.
- `animation(_:)` and `animation(_:value:)` attach retained animation state for properties the runtime can interpolate today, currently focused on opacity and background color. `withAnimation` accepts SwiftUI-shaped call sites and executes the body immediately.
- `disabled(_:)` propagates an inherited enabled-state environment through `ViewBuildContext`, and retained controls consume that state while they are built.
- `scrollDisabled(_:)` propagates `EnvironmentValues.isScrollEnabled`; retained `ScrollView`, `List`, and scrolling `Section` nodes keep their layout and clipping but remove their scroll axis and indicators when disabled.
- `scrollClipDisabled(_:)` maps to retained scroll container bounds clipping for `ScrollView`, `List`, and scrolling `Section` nodes. Non-scroll `Section` panels keep their rounded clipping.
- `scrollContentBackground(_:)` accepts SwiftUI `Visibility` values. `.hidden` clears retained scroll-container background chrome for `ScrollView` and scrolling `Section` nodes; `.automatic` and `.visible` preserve the current retained style background. Non-scroll `Section` panels keep their normal background.
- `scrollIndicators(_:axes:)` propagates horizontal and vertical `ScrollIndicatorVisibility` environment values. `.hidden` and `.never` suppress retained indicators for matching axes, while `.automatic` and `.visible` keep the current retained indicator behavior.
- `scrollDismissesKeyboard(_:)` propagates `EnvironmentValues.scrollDismissesKeyboardMode` with `.automatic`, `.immediately`, `.interactively`, and `.never` for source-compatible scroll/input code. It is metadata today because the Windows retained text input path does not host a software keyboard.
- `defaultWheelPickerItemHeight(_:)` propagates `EnvironmentValues.defaultWheelPickerItemHeight`, defaulting to `32`. WinSwiftUI does not yet implement wheel-style picker chrome, so this value is readable/overrideable compatibility metadata.
- `ScrollView` maps into retained scroll panels with indicator state handled in the runtime.
- `List` maps to a retained vertical scroll panel, while `Form` maps to a retained vertical stack with form-like spacing and padding. Row styling remains intentionally minimal.
- `headerProminence(_:)` propagates `EnvironmentValues.headerProminence`; `.increased` maps direct `Section` headers to a bolder retained header font unless the header text sets an explicit font.
- `EnvironmentValues.backgroundProminence` accepts `.standard` and `.increased` for shared-source foreground styling decisions above custom or selected backgrounds. It is readable and overrideable compatibility metadata today; retained lists do not yet derive it from selected-row state.
- `EnvironmentValues.defaultMinListHeaderHeight` maps to retained minimum-height constraints on direct `Section` header nodes, preserving stronger header constraints.
- `badge(_:)` accepts integer, optional string, optional localized key, and optional `Text` badges, then maps visible badges to retained trailing badge chrome. Integer `0` and `nil` optional badges preserve the base row unchanged. `badgeProminence(_:)` propagates `EnvironmentValues.badgeProminence` and maps `.decreased`, `.standard`, and `.increased` to retained badge colors.
- `listRowBackground(_:)` accepts optional retained views, colors, gradients, and stored foreground styles. Color and gradient inputs wrap the row in a retained background panel; view inputs are layered behind the row and stretched to the row bounds.
- `listRowInsets(_:)` and `listRowInsets(_:_:)` map to retained row padding wrappers. Passing `nil` preserves the row unchanged.
- `listRowSpacing(_:)` maps optional row spacing to the retained `List` stack layout. Passing `nil` restores the retained default spacing of `0`.
- `EnvironmentValues.defaultMinListRowHeight` maps to retained minimum-height constraints on direct `List` rows, preserving stronger row constraints.
- `DisclosureGroup` maps optional binding-backed expansion state into a retained disclosure header button plus an indented retained content stack; toggling writes through `Binding<Bool>` when supplied, otherwise uses local retained expansion state, and invalidates the host for rebuild.
- `Menu` maps to a retained menu button and an inline retained action stack. It preserves SwiftUI-shaped menu syntax and button actions, but does not yet present as a native popup overlay.
- `ControlGroup` maps to compact retained horizontal group chrome, accepts title and builder-label forms, and preserves nested control actions while applying borderless button style to grouped buttons.
- `TextField`, `SecureField`, and `TextEditor` map a `Binding<String>` to a retained focusable input surface with basic virtual-key text insertion, backspace, forward delete, and caret movement with left/right/home/end. `TextField` and `SecureField` provide placeholder rendering from the title or SwiftUI-style `prompt: Text?` overloads, `TextField(axis: .vertical)` maps to the retained multiline input path, `SecureField` masks the displayed value, and `TextEditor` enables multiline wrapping/newline insertion. `textInputAutocapitalization(_:)` propagates through `EnvironmentValues` and transforms inserted retained keyboard text for `.characters`, `.words`, and `.sentences`; `autocorrectionDisabled(_:)` propagates for source compatibility but has no spelling engine behind it yet. These controls do not yet provide selection, IME composition, or full text-editing commands.
- `DatePicker` accepts SwiftUI-shaped date, time, closed-range, and partial-range initializer labels and maps the selected `Date` into retained label/value text. It reads `EnvironmentValues.calendar` and `EnvironmentValues.timeZone` before formatting its deterministic retained value text, and non-current `EnvironmentValues.locale` overrides use `DateFormatter` for locale-specific date/time text. Retained date pickers are focusable and write the selection binding from arrow-key increments while respecting the supplied range. Calendar popovers and direct text entry are not implemented yet.
- `ColorPicker` accepts SwiftUI-shaped title, builder-label, and `supportsOpacity` initializer labels, then maps the selected `Color` into a retained swatch plus hex value. Retained color pickers are focusable and provide keyboard binding writes: left/right cycle a deterministic retained color palette, and up/down adjust opacity when `supportsOpacity` is true. Native color dialogs, color wells, and direct channel text entry are not implemented yet.
- `HSplitView` and `VSplitView` map into the retained split-view control and can infer an initial ratio from content.
- `GeometryReader` uses the current build context canvas size and now reevaluates correctly after canvas-size changes.
- The default scene path scales quads, shadows, clips, and glyphs into device pixels before batch rendering.
- `GPUIScene` now carries replayable scene paint records plus per-layer family operations as metadata, stores semantic content masks on typed primitives, assigns bounds-based draw orders from masked bounds per primitive family, and finishes layers into ordered batch ranges before the batch renderer uploads them.
- `RetainedViewRuntime` now reuses cached `sizeThatFits`/layout results for clean subtrees and replays clean frame/scene ranges, which keeps paint-only updates and scroll movement from relaying out the full tree.
- `RetainedViewRuntime` now builds reusable prepaint dispatch state for interaction hit regions, focus order, ancestor routing, deferred-subtree prepaint work, and deferred paint metadata such as scroll indicators, and both rendering plus pointer/focus/scroll/drag routing consume that shared state instead of each walking the tree separately.
- Deferred runtime work is now split into a deferred-subtree prepaint queue plus deferred paint records with rerunnable payloads and cached frame/scene replay ranges, so clean subtree reuse can preserve deferred ordering and cross-backend fallback can still regenerate late draws when only one cached path exists.
- Native scene text now goes through a runtime-owned logical `WindowTextSystem` cache before scene paint, and cached scenes no longer keep re-uploading stale atlas snapshots after the first presentation.
- Standard text on the frame fallback path still goes through native bitmap rasterization; the default scene path now captures DirectWrite glyph IDs/font faces for atlas-backed glyphs, while icon/private-use glyphs still fall back to the pixel atlas.
- `D3D11BatchRenderer` now renders finished ordered batch ranges directly from scene storage instead of replaying per-layer paint operations or allocating temporary arrays per operation, and batch shadows now honor the same content-mask clipping as quads and glyphs.

## Observation Model

`WinSwiftUI` now supports a minimal SwiftUI-style observation path for shared source:

- `Binding`
- `@State`
- `@Environment`
- `@FocusedValue`
- `@FocusedBinding`
- `ObservableObject`
- `@Published`
- `@ObservedObject`
- `@StateObject`

`@Environment` can read retained-context values such as `isEnabled`, `isFocused`, `isFocusEffectEnabled`, `isLuminanceReduced`, `isSceneCaptured`, `isTabBarShowingSections`, `isScrollEnabled`, `horizontalScrollIndicatorVisibility`, `verticalScrollIndicatorVisibility`, `scrollDismissesKeyboardMode`, `defaultMinListHeaderHeight`, `defaultMinListRowHeight`, `defaultWheelPickerItemHeight`, `backgroundProminence`, `headerProminence`, `badgeProminence`, `redactionReasons`, `isPrivacySensitive`, `colorScheme`, `colorSchemeContrast`, `scenePhase`, `controlActiveState`, `appearsActive`, `supportsMultipleWindows`, `isPresented`, `editMode`, `legibilityWeight`, `displayScale`, `pixelLength`, `calendar`, `timeZone`, `locale`, `dismiss`, `dismissSearch`, `isSearching`, `rename`, `refresh`, `openWindow`, `dismissWindow`, `openSettings`, `requestReview`, `undoManager`, `accessibilityAssistiveAccessEnabled`, `accessibilityDimFlashingLights`, `accessibilityDifferentiateWithoutColor`, `accessibilityEnabled`, `accessibilityInvertColors`, `accessibilityLargeContentViewerEnabled`, `accessibilityPlayAnimatedImages`, `accessibilityPrefersHeadAnchorAlternative`, `accessibilityQuickActionsEnabled`, `accessibilityReduceHighlightingEffects`, `accessibilityReduceMotion`, `accessibilityReduceTransparency`, `accessibilityShowButtonShapes`, `accessibilityShowBorders`, `accessibilitySwitchControlEnabled`, `accessibilityVoiceOverEnabled`, `layoutDirection`, `horizontalSizeClass`, `verticalSizeClass`, `dynamicTypeSize`, `font`, `multilineTextAlignment`, `lineLimit`, `lineSpacing`, `minimumScaleFactor`, `truncationMode`, `allowsTightening`, `textCase`, `textInputAutocapitalization`, `isAutocorrectionDisabled`, `tint`, `buttonRepeatBehavior`, `buttonSizing`, `buttonBorderShape`, `menuIndicatorVisibility`, `controlSize`, `imageScale`, `labelStyle`, `toggleStyle`, `textFieldStyle`, and `submitLabel`, and app-defined `EnvironmentKey` values can be exposed through `EnvironmentValues` extensions. `environment(_:_:)`, `transformEnvironment(_:_:)`, and `preferredColorScheme(_:)` override inherited values through the retained build context.
Observed object changes are coalesced by the host before rebuilding the retained tree so one logical update does not trigger multiple immediate redraw passes.
`@State` stores values in a retained box captured by the view value and exposes `$state` as a `Binding`, which is enough for common controls such as `Toggle`.
`@StateObject` currently shares the same observation and invalidation path as `@ObservedObject`; it is a source-compatibility shim, not a full SwiftUI lifetime model yet.

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
- Text behavior on the default path is still bitmap-based, while the experimental scene path has a partial native glyph-atlas port with cached logical layout, subtree layout/measurement reuse, runtime-owned prepaint dispatch state plus split deferred-subtree prepaint and deferred paint replay for interaction/focus/late-paint metadata and ancestor routing, semantic content masks, inherited-opacity propagation, and glyph-run capture that still stops short of GPUI-style shaped text runs, per-deferred prepaint replay ranges, and sprite families.
- `D3D11Renderer` still only executes `fillRect` and `drawBitmap`; `GPUIScene` remains the richer but still experimental presentation path.
- API coverage should be extended from real demo/app needs, not by cloning SwiftUI surface area speculatively.
