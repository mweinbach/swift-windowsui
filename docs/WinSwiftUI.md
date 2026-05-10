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
- `Label`
  - `StringProtocol` title inputs
  - `Label { title } icon: { icon }`
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
- `HSplitView`
- `VSplitView`
- `Menu`
- `Button`
  - `StringProtocol` title inputs
  - `Button(_:systemImage:...)`
  - `ButtonRole.destructive`
  - `ButtonRole.cancel`
- `TextField`
  - `prompt: Text?` overloads
  - `axis:` overloads
- `SecureField`
  - `prompt: Text?` overloads
- `TextEditor`
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
- `preferredColorScheme`
- `font`
- `fontDesign`
- `fontWeight`
- `bold`
- `monospaced`
- `multilineTextAlignment`
- `lineLimit`
  - `lineLimit(_:reservesSpace:)`
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
- `allowsHitTesting`
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
- `listRowBackground`
- `listRowInsets`
- `onAppear`
- `onDisappear`
- `onChange`
- `onSubmit`
- `submitLabel`
- `onHover`
- `onTapGesture`
- `accessibilityLabel`
- `accessibilityValue`
- `accessibilityHint`
- `accessibilityIdentifier`
- `accessibilityHidden`
- `help`
- `tag`

Compatibility helpers:

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
- `SubmitTriggers`
- `SubmitLabel`
- `TextInputAutocapitalization`
- `Visibility`
- `LocalizedStringKey`
- `CGFloat`, `CGPoint`, `CGSize`, `CGRect` aliases
- `EdgeInsets()`
- minimal `Binding`, `State`, `Environment`, `EnvironmentValues`, `ObservableObject`, `Published`, `ObservedObject`, and `StateObject`

Surface direction:

- default retained buttons now use lighter rounded chrome with hover, focus, press, and activation transitions
- the demo’s cards and chips are built from shared-source-friendly layered gradients and translucent strokes rather than WinSwiftUI-only styling hooks

## Mapping Notes

- `Text` maps into retained label nodes and the current runtime text renderer path.
- `LocalizedStringKey` is a source-compatibility shim that resolves to plain retained text today; it does not perform bundle lookup or real localization yet. Common title-bearing controls and titled containers also accept `StringProtocol` inputs such as `Substring` and forward them through the same retained label paths as `String` titles.
- Named `Font` styles and `Font.system(_:design:weight:)` text-style overloads are fixed point-size and weight presets today; they do not implement Dynamic Type scaling yet. `Font.monospaced()`, `Text.monospaced()`, and `fontDesign(_:)` resolve through the same retained font family mapping as `.system(..., design: .monospaced)`. `font(_:)` accepts `Font?`, bridges through `EnvironmentValues.font`, and `.font(nil)` resets a subtree to the retained default font.
- SwiftUI-shaped RGB, white, and HSB `Color` initializers reduce to the renderer-neutral RGBA color type used by the retained scene.
- `frame(minWidth:idealWidth:maxWidth:minHeight:idealHeight:maxHeight:alignment:)` maps finite constraints into retained `LayoutConstraints`; infinite maximum values are accepted for call-site compatibility, with expansion still depending on the surrounding retained layout mode.
- `fixedSize()` and `fixedSize(horizontal:vertical:)` map to retained measurement axes that ignore incoming maximum constraints on selected axes; final placement can still be limited by the parent layout mode.
- `padding` accepts SwiftUI-style optional lengths; `nil` resolves to the retained default of `16`.
- `ignoresSafeArea`, `edgesIgnoringSafeArea`, and `safeAreaPadding` are accepted for source compatibility but currently pass through unchanged because the Win32 host does not expose safe-area insets.
- Text and foreground styling modifiers on containers propagate through `ViewBuildContext`, while explicit `Text`, `Image`, and `Label` styling still takes precedence. Solid `foregroundStyle` maps to inherited text/icon color, including stored `ForegroundStyle.color` values and semantic color shorthand such as `.foregroundStyle(.secondary)`. Multi-argument `foregroundStyle` overloads are accepted for source compatibility and currently use the primary style because retained nodes do not model hierarchical foreground style slots yet. `LinearGradient` and stored `ForegroundStyle.linearGradient` values map to retained gradient fills for `Rectangle`, `RoundedRectangle`, `Capsule`, `Circle`, and `Ellipse`, while text/icons use the gradient start color as a compatibility fallback. `background` and `overlay` also accept stored `ForegroundStyle` values and route them through the existing retained color/gradient panel paths. `Circle` uses the retained dynamic rounded path, and `Ellipse` currently uses the same capsule-style rounded fallback until true elliptical retained primitives are added. Shape `fill(_:)` also accepts stored `ForegroundStyle` values. `Text + Text` is accepted for source compatibility and flattens into one retained label; because retained text nodes do not have rich text runs yet, explicit styling resolves to a single node style with left-hand styling taking precedence when both sides set the same property. `lineSpacing(_:)`, `Text.kerning`, and `Text.tracking` map to retained text style; line spacing participates in retained measurement, while letter spacing is carried into the renderer text style for pixel/text-atlas paths. `allowsTightening(_:)` maps to the retained text kerning toggle until true glyph tightening is modeled. `textCase(_:)` applies inherited or explicit uppercase/lowercase transforms before retained label creation. `lineLimit(_:reservesSpace:)` maps the maximum line count and accepts the reserve-space flag for source compatibility, but retained text measurement does not reserve extra empty-line height yet. `multilineTextAlignment(_:)`, `lineLimit(_:)`, `lineSpacing(_:)`, `truncationMode(_:)`, `allowsTightening(_:)`, and `textCase(_:)` bridge through `EnvironmentValues`, so `@Environment` and `.environment(\.lineLimit, ...)` see the same inherited retained text values. `truncationMode(_:)` maps `.head`, `.tail`, and `.middle` to the retained text line-break modes when a line limit is active. `Text.underline` and `Text.strikethrough` map to retained text decoration flags; decoration colors are accepted for source compatibility but currently use the text color.
- `imageScale(_:)` propagates through `EnvironmentValues` and maps `.small`, `.medium`, and `.large` to retained symbol icon scale for `Image(systemName:)` and label icons.
- `tint` and `accentColor` propagate through `ViewBuildContext`; retained controls consume the inherited tint for toggle-on, slider-fill, and progress-fill colors.
- `labelsHidden()` propagates through `ViewBuildContext` and suppresses retained label nodes for controls such as `Toggle`, `Picker`, `Stepper`, `Slider`, and `ProgressView`.
- `font(_:)`, `tint(_:)`, `accentColor(_:)`, and `controlSize(_:)` bridge into `EnvironmentValues`, so `@Environment(\.font)`, `@Environment(\.tint)`, `@Environment(\.controlSize)`, `.environment(\.font, ...)`, `.environment(\.tint, ...)`, and `.environment(\.controlSize, ...)` share the same inherited values consumed by retained text and controls. Optional `Text.font(_:)` accepts concrete fonts and resets `nil` to the retained default text font.
- `controlSize(_:)` maps to retained preferred sizes for text inputs, toggle, menu picker, stepper buttons, slider, and progress bar surfaces.
- `labelStyle(_:)` propagates through `EnvironmentValues` and maps `.automatic` / `.titleAndIcon`, `.iconOnly`, and `.titleOnly` to retained `Label` composition.
- `toggleStyle(_:)` propagates through `EnvironmentValues`; `.automatic` and `.switch` use the retained switch, `.checkbox` maps to retained checkbox chrome with arbitrary SwiftUI-shaped label content, and `.button` maps to retained selected/unselected button chrome.
- `textFieldStyle(_:)` propagates through `EnvironmentValues`; `.automatic` and `.roundedBorder` use the retained bordered input chrome, while `.plain` maps to a borderless retained input surface.
- `background(_:alignment:)` and `overlay(_:alignment:)` forward to the retained absolute layering path used by the builder-based overloads.
- `Section` supports title, header, footer, and content-only forms, all mapped to the retained vertical section panel.
- `GroupBox` maps title and builder-label forms to a retained vertical panel with lightweight default chrome.
- `NavigationStack` and `NavigationView` preserve `navigationTitle` / `navigationBarTitle` metadata, render lightweight retained title chrome, and support local push/pop presentation for direct `NavigationLink(destination:)` and `NavigationLink { destination } label: { ... }` links plus `NavigationLink(value:)` routes resolved by `navigationDestination(for:)`. `NavigationStack(path:)` syncs value-link pushes and back navigation with `NavigationPath` or generic mutable collection bindings, including nested path restoration as each resolved destination contributes its own registered destinations. Boolean and item `navigationDestination` overloads render binding-driven retained destinations and clear their bindings through the back control. Platform-native navigation transitions are not implemented yet.
- `NavigationSplitView` maps two- and three-column source-compatible initializers to a retained horizontal stack. `NavigationSplitViewVisibility` bindings drive coarse retained column filtering for `.all`, `.doubleColumn`, and `.detailOnly`; adaptive platform breakpoint collapsing is not implemented yet.
- `TabView` renders retained tab chrome from `.tabItem` labels, shows the first page by default, and shows the page whose `.tag(_:)` matches the `selection:` binding. Activating a tab updates local selection state or writes through a tagged `selection:` binding, but platform-specific tab styling and overflow behavior are still minimal.
- `onAppear` fires when the retained node first renders, `onDisappear` fires when an appeared retained subtree is removed or replaced, and `onChange(of:)` keeps lightweight call-site state so rebuilt SwiftUI-shaped views can observe `Equatable` value transitions.
- `onSubmit(of:_:)` hooks retained Enter key input into SwiftUI-shaped submit actions for text/search triggers on the modified retained subtree. It preserves existing non-submit key handling and invalidates after the submit action runs; submit scopes and platform keyboard return-key labels are not modeled yet.
- `submitLabel(_:)` accepts SwiftUI return-key label call sites for source compatibility. It does not alter hardware keyboard behavior on the retained Windows input path today.
- `onHover` opts the retained node into hit testing and forwards pointer enter/exit transitions as `true`/`false`.
- `onTapGesture` opts the retained node into hit testing and handles pointer tap activation. Multi-tap `count` values require consecutive inside releases and reset after an outside release; platform-native tap timing thresholds are not modeled yet.
- `contentShape` and `ContentShapeKinds` are accepted for source compatibility. Retained hit testing remains rectangular today, so the shape and kind values do not alter pointer, focus, preview, or accessibility geometry yet.
- `Image(systemName:)` maps known SF Symbol names into the project icon set.
- `Image(_:bundle:label:)`, `Image(decorative:bundle:)`, and `Image(systemName:variableValue:)` are accepted for source compatibility and reuse the same retained bitmap/icon rendering paths. Image labels and decorative flags map to retained accessibility metadata; variable symbol values are retained as API-shape compatibility only until variable SF Symbol rendering exists.
- `Image(systemName:)` currently resolves to retained icon labels that render through the scene glyph atlas or the frame fallback text path.
- `Image(_:)` resolves direct file paths or bundle resources through the WIC-backed image loader and maps decoded bitmaps onto retained bitmap nodes that emit `DrawBitmapCommand`/`ImagePrimitive` resources. PNG/JPEG/BMP resources are supported through WIC; asset-catalog lookup is not implemented yet.
- `Image.resizable`, `aspectRatio`, `scaledToFit`, and `scaledToFill` map system icon glyphs and decoded bitmap images to retained preferred sizes based on font size or native bitmap size, image scale, and aspect ratio. `resizingMode` is retained as compatibility metadata; real tile rendering is not implemented yet.
- `Rectangle`, `RoundedRectangle`, `Capsule`, `Circle`, and `Ellipse` map to retained fill/border/corner-radius nodes; `fill` uses explicit colors or the inherited foreground style, `stroke` and `strokeBorder` accept `Color`, stored `ForegroundStyle`, `LinearGradient`, and `StrokeStyle` overloads. `StrokeStyle.lineWidth` maps to retained border width; line caps, joins, miter limits, and dash patterns are accepted for source compatibility but are not rendered by the retained border path yet. Rounded corner styles currently share the same retained rounded-rect path.
- `Divider()` maps to a retained separator node and picks a horizontal or vertical preferred size from the inherited stack axis.
- `ForEach` expands into builder children instead of adding an extra layout wrapper, and generated children receive stable retained node tags derived from the SwiftUI-style id. `Range<Int>` and `ClosedRange<Int>` support the SwiftUI-style shorthand initializer.
- `VStack`, `HStack`, `LazyVStack`, and `LazyHStack` accept SwiftUI-style optional spacing; `nil` resolves to the current retained default spacing of `0`. Lazy stacks currently map to the same retained stack panels as eager stacks, and accept `pinnedViews` for source compatibility without sticky section behavior yet.
- `Button` maps into retained button controls and preserves focus/press/activate animation state.
- `Button` now also resolves hover-aware border and shadow states so retained controls feel closer to modern desktop/mobile system chrome.
- `Button(_:systemImage:...)` maps into the existing retained button path with a `Label`; `.buttonStyle` propagates through `ViewBuildContext`, with `.bordered` and `.borderedProminent` mapping to the default retained button chrome and `.borderless` mapping to plain chrome.
- `Toggle` maps into the retained switch control and writes through a SwiftUI-shaped `Binding<Bool>`.
- `Picker` maps tagged child content into a retained segmented selection group by default and writes through a SwiftUI-shaped `Binding` when an option activates. `.tag(_:)` supplies the SwiftUI-style selection value; untagged options fall back to integer indices for `Binding<Int>` pickers. `.pickerStyle(.menu)` maps the same tagged options into the retained dropdown control using the first retained text node as the option title.
- `Stepper` maps to a retained horizontal stack with label content and two retained buttons that mutate `Binding<Int>` or `Binding<Double>` values.
- `Slider(value:in:)` maps into the retained draggable slider and writes through a SwiftUI-shaped `Binding<Double>`. The `step` initializer snaps written values relative to the lower bound and reports drag editing state through the retained control lifecycle. Minimum, maximum, and main label overloads wrap the retained slider in small retained stacks while preserving the same binding/editing behavior.
- `ProgressView(value:total:)` maps into the retained progress bar control; title, builder-label, and current-value label overloads wrap that retained bar in small retained stacks.
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
- `ScrollView` maps into retained scroll panels with indicator state handled in the runtime.
- `List` maps to a retained vertical scroll panel, while `Form` maps to a retained vertical stack with form-like spacing and padding. Row styling remains intentionally minimal.
- `listRowBackground(_:)` accepts optional retained views, colors, gradients, and stored foreground styles. Color and gradient inputs wrap the row in a retained background panel; view inputs are layered behind the row and stretched to the row bounds.
- `listRowInsets(_:)` and `listRowInsets(_:_:)` map to retained row padding wrappers. Passing `nil` preserves the row unchanged.
- `DisclosureGroup` maps optional binding-backed expansion state into a retained disclosure header button plus an indented retained content stack; toggling writes through `Binding<Bool>` when supplied, otherwise uses local retained expansion state, and invalidates the host for rebuild.
- `Menu` maps to a retained menu button and an inline retained action stack. It preserves SwiftUI-shaped menu syntax and button actions, but does not yet present as a native popup overlay.
- `TextField`, `SecureField`, and `TextEditor` map a `Binding<String>` to a retained focusable input surface with basic virtual-key text insertion/backspace. `TextField` and `SecureField` provide placeholder rendering from the title or SwiftUI-style `prompt: Text?` overloads, `TextField(axis: .vertical)` maps to the retained multiline input path, `SecureField` masks the displayed value, and `TextEditor` enables multiline wrapping/newline insertion. `textInputAutocapitalization(_:)` propagates through `EnvironmentValues` and transforms inserted retained keyboard text for `.characters`, `.words`, and `.sentences`; `autocorrectionDisabled(_:)` propagates for source compatibility but has no spelling engine behind it yet. These controls do not yet provide caret movement, selection, IME composition, or full text-editing commands.
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
- `ObservableObject`
- `@Published`
- `@ObservedObject`
- `@StateObject`

`@Environment` can read retained-context values such as `isEnabled`, `isScrollEnabled`, `horizontalScrollIndicatorVisibility`, `verticalScrollIndicatorVisibility`, `colorScheme`, `font`, `multilineTextAlignment`, `lineLimit`, `lineSpacing`, `truncationMode`, `allowsTightening`, `textCase`, `textInputAutocapitalization`, `isAutocorrectionDisabled`, `tint`, `controlSize`, `imageScale`, `labelStyle`, `toggleStyle`, and `textFieldStyle`, and app-defined `EnvironmentKey` values can be exposed through `EnvironmentValues` extensions. `environment(_:_:)` and `preferredColorScheme(_:)` override inherited values through the retained build context.
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
