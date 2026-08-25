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

## Rendering Contract

`GPUIScene.paintOperations` is the source-of-truth paint stream for typed
scene primitives. CPU screenshots and `D3D11BatchRenderer` must both consume
that stream so mixed primitive families preserve retained-runtime paint order.
Family-specific sorted batches remain an optimization surface, but they must
not replace the paint stream for presentation.

Offscreen compositing and `drawingGroup` passes render into a temporary
`GPUIScene`. Those passes must not update `ViewNode.cachedScenePaintRange`,
because the cached ranges refer to the outer scene's `paintRecords`. The
temporary scene does carry the frame's glyph atlases — without them the CPU
rasterizer drops every glyph, so all text inside the group disappears — but it
reads them through `NativeGlyphAtlas.currentSnapshot()`, which does not consume
the frame's dirty region. The group's buffer is sized from its frame *clamped to
the effective clip* and refuses to allocate past an area budget, falling back to
inline painting; see `docs/GPURenderingPipeline.md` §2b.

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
  - `Text(LocalizedStringKey, tableName:bundle:comment:)`
  - `LocalizedStringResource` inputs
  - `Text(Date, style:)`
  - `Text(DateInterval)`
  - `Text(timerInterval:pauseTime:countsDown:showsHours:)`
  - `Text(_:formatter:)`
  - `Text(_:format:)`
  - `Text(AttributedString)`
  - flattened `Text + Text` concatenation
- `Image(_:)`
  - `ImageResource(name:bundle:)`
  - `Image(ImageResource)`
  - `Image(_:bundle:label:)`
  - `Image(_:variableValue:bundle:)`
  - `Image(_:variableValue:bundle:label:)`
  - `Image(decorative:bundle:)`
  - `Image(decorative:variableValue:bundle:)`
- `Image(systemName:)`
  - `Image(systemName:label:)`
  - `Image(systemName:variableValue:)`
  - `Image(systemName:variableValue:label:)`
  - `renderingMode(_:)`
  - `interpolation(_:)`
  - `antialiased(_:)`
  - `resizable(capInsets:resizingMode:)`
- `LabeledContent`
  - `labeledContentStyle` compatibility metadata
  - `StringProtocol` title inputs
  - title/value inputs
  - `value:format:` overloads
- `ToolbarItem`
- `ToolbarItemGroup`
- `Label`
  - `StringProtocol` title inputs
  - `Label(_:image:)`
  - `Label { title } icon: { icon }`
- `Link`
  - `StringProtocol` title inputs
  - `Link(destination:label:)`
- `SettingsLink`
- `ContentUnavailableView`
  - `ContentUnavailableView(_:image:description:)`
  - `ContentUnavailableView(_:systemImage:description:)`
  - builder label/description/actions forms
  - `ContentUnavailableView.search`
- `Rectangle`
- `RoundedRectangle(cornerRadius:style:)`
- `RoundedRectangle(cornerSize:style:)`
- `UnevenRoundedRectangle`
- `RectangleCornerRadii`
- `Capsule(style:)`
- `Circle`
- `Ellipse`
- `ContainerRelativeShape`
- `AnyShape`
- `InsettableShape`
- `InsetShape`
- `Shape` static factories for `rect`, rounded `rect(...)`, uneven `rect(...)`, `capsule`, `circle`, `ellipse`, and `containerRelative`
- `Shape`
- `Spacer`
- `Divider`
- `Group`
- `EquatableView`
- `ForEach`, including open and closed integer ranges plus binding-backed mutable collections
- `GeometryReader`
- `ViewThatFits`
- `PhaseAnimator`
- `NavigationStack`
- `NavigationView`
- `NavigationSplitView`
- `NavigationLink`
  - `NavigationLink { destination } label: { label }`
  - `NavigationLink(destination:isActive:label:)`
  - `NavigationLink(destination:tag:selection:label:)`
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
  - `ScrollView(_:showsIndicators:content:)` compatibility initializer
- `ScrollViewReader`
- `List`
  - `List(data, id:content:)`
  - `List(data, content:) where Element: Identifiable`
  - `List($data, id:content:)`
  - `List($data, content:) where Element: Identifiable`
  - single and multiple `selection:` overloads for tagged/static rows and data-backed rows
- `Form`
  - `formStyle` compatibility metadata
- `Section`
  - `StringProtocol` title inputs
  - `Section(_:isExpanded:content:)`
  - `Section(isExpanded:content:header:)`
  - `Section { content } footer: { footer }`
  - `Section { content } header: { header } footer: { footer }`
  - deprecated direct `Section(header:content:)`, `Section(footer:content:)`, and `Section(header:footer:content:)`
- `GroupBox`
  - `StringProtocol` title inputs
  - `groupBoxStyle` compatibility metadata
- `DisclosureGroup`
  - `StringProtocol` title inputs
  - `disclosureGroupStyle` compatibility metadata
- `ControlGroup`
  - `StringProtocol` title inputs
  - `ControlGroup(_:image:content:)`
  - `ControlGroup(_:systemImage:content:)`
  - `controlGroupStyle` compatibility metadata
- `HSplitView`
- `VSplitView`
- `Menu`
  - `StringProtocol` title inputs
  - `Menu(_:image:content:)`
  - `Menu(_:systemImage:content:)`
  - `Menu(_:content:primaryAction:)`
  - `Menu(_:image:content:primaryAction:)`
  - `Menu(_:systemImage:content:primaryAction:)`
  - `menuStyle` compatibility metadata
- `Button`
  - `StringProtocol` title inputs
  - `Button(_:image:...)`
  - `Button(_:systemImage:...)`
  - `ButtonRole.destructive`
  - `ButtonRole.cancel`
- `RenameButton`
- `EditButton`
- `TextField`
  - `prompt: Text?` overloads
  - `axis:` overloads
  - `selection: Binding<TextSelection?>` overloads
  - `value:formatter:` overloads
  - `value:format:` overloads
  - builder-label `text:prompt:label:` and `text:prompt:axis:label:` overloads
  - deprecated text, formatter, and optional formatter `onEditingChanged` / `onCommit` initializer overloads
- `SecureField`
  - `prompt: Text?` overloads
  - builder-label `text:prompt:label:` overloads
  - deprecated `onCommit` initializer overloads
- `TextEditor`
  - `selection: Binding<TextSelection?>` overload
- `DatePicker`
  - date/time displayed component options
  - closed and partial-range initializer overloads
  - `datePickerStyle` compatibility metadata
- `ColorPicker`
  - `supportsOpacity` initializer labels
- `Toggle`
  - `StringProtocol` title inputs
  - `image:` and `systemImage:` label inputs
  - collection-backed `sources:isOn:` overloads
- `Picker`
  - `StringProtocol` title inputs
  - builder-label `selection:content:label:currentValueLabel:` overloads
  - `.pickerStyle(.automatic)`, `.inline`, `.segmented`, `.menu`, `.navigationLink`, `.palette`, `.radioGroup`, and `.wheel`
  - concrete built-in picker style types such as `DefaultPickerStyle`, `MenuPickerStyle`, and `WheelPickerStyle`
- `Stepper`
  - `StringProtocol` title inputs
  - generic `Strideable` value overloads
  - `onIncrement` / `onDecrement` action overloads
- `Slider`
  - generic `BinaryFloatingPoint` value overloads
  - `Slider(value:in:step:onEditingChanged:)`
  - builder-label `Slider(value:in:label:onEditingChanged:)` and `Slider(value:in:step:label:onEditingChanged:)`
  - minimum, maximum, and main label overloads
- `ProgressView`
  - `BinaryFloatingPoint` value and total overloads
  - `StringProtocol` title inputs
  - title, label, and current-value label overloads
  - `timerInterval:countsDown:` overloads
- `Gauge`
  - `BinaryFloatingPoint` value and range overloads
  - `StringProtocol` title inputs
  - label, current-value, minimum-value, maximum-value, and marked-value label overloads

Modifiers:

- `frame`, including fixed and min/ideal/max overloads
- `containerRelativeFrame`
- `fixedSize`
- `ignoresSafeArea`
- `edgesIgnoringSafeArea`
- `safeAreaPadding`
- `safeAreaInset`
- `toolbar`
- `toolbarBackground`
- `toolbarColorScheme`
- `toolbarRole`
- `toolbarTitleDisplayMode`
- `navigationBarItems`
- `contextMenu`
- `sheet`
- `fullScreenCover`
- `popover`
- `presentationDetents`
- `presentationDragIndicator`
- `presentationBackground`
- `presentationCornerRadius`
- `presentationBackgroundInteraction`
- `presentationContentInteraction`
- `presentationCompactAdaptation`
- `interactiveDismissDisabled`
- `alert`
- `actionSheet`
- `confirmationDialog`
- `aspectRatio`
- `scaledToFit`
- `scaledToFill`
- `padding`
  - optional-length overloads such as `padding(nil)` and `padding(.horizontal, nil)`
- `background`, including stored `ForegroundStyle`, generic `ShapeStyle`, optional `Color?` inputs, and `ignoresSafeAreaEdges:` color/gradient/style overloads
- `background(ignoresSafeAreaEdges:)`
- `background(_:alignment:)`
- `background(_:in:fillStyle:)`
- `background(in:fillStyle:)`
- `background(alignment:content:)`
- `backgroundStyle`
- `containerBackground(_:for:)`
- `containerBackground(for:alignment:content:)`
- `overlay`, including color/gradient/stored `ForegroundStyle`/generic `ShapeStyle` overloads
- `overlay(_:alignment:)`
- `overlay(_:in:fillStyle:)`
- `overlay(alignment:content:)`
- `mask(alignment:_:)`
- `foregroundColor`, including optional `Color?` inputs
- `foregroundStyle` for solid `Color`, stored `ForegroundStyle`, generic `ShapeStyle`, `AnyShapeStyle`, `LinearGradient` shape fills, `Text` value styling, and primary-style multi-argument overloads
- `imageScale`
- `symbolRenderingMode`
- `symbolVariant`
- `tint`, including optional `Color?` inputs
- `accentColor`
- `buttonStyle`
- `buttonRepeatBehavior`
- `buttonSizing`
- `buttonBorderShape`
- `menuIndicator`
- `pickerStyle`
- `labelStyle`
- `labeledContentStyle`
- `formStyle`
- `groupBoxStyle`
- `disclosureGroupStyle`
- `menuStyle`
- `controlGroupStyle`
- `progressViewStyle`
- `gaugeStyle`
- `datePickerStyle`
- `toggleStyle`
- `textFieldStyle`
- `labelsHidden`
- `controlSize`
- `navigationTitle`
- `navigationBarTitle`
- `navigationBarTitleDisplayMode`
- `navigationBarBackButtonHidden`
- `navigationBarHidden`
- `navigationDestination`
- `navigationViewStyle`
- `tabItem`
- `environment`
- `transformEnvironment`
- `focusedValue`
- `focusedSceneValue`
- `preferredColorScheme`
- `dynamicTypeSize`
- `font`
- `fontDesign`
- `fontWidth`
- `fontWeight`
- `bold`
- `italic`
- `monospaced`
- `monospacedDigit`
- `multilineTextAlignment`
- `lineLimit`
  - `lineLimit(_:reservesSpace:)`
  - range overloads: `lineLimit(...max)`, `lineLimit(min...)`, and `lineLimit(min...max)`
- `minimumScaleFactor`
- `truncationMode`
- `lineSpacing`
- `kerning`
- `tracking`
- `baselineOffset`
- `textScale`
- `textRenderer`
- `allowsTightening`
- `textCase`
- `textSelection`
- `textSelectionAffinity`
- `textInputAutocapitalization`
- `textContentType`
- `keyboardType`
- `textInputCompletion`
- `textInputSuggestions`
- `writingToolsBehavior`
- `writingToolsAffordanceVisibility`
- `autocorrectionDisabled`
- `disableAutocorrection`
- `findDisabled`
- `replaceDisabled`
- `findNavigator`
- `underline`
- `strikethrough`
- `cornerRadius(_:antialiased:)`
- `clipped(antialiased:)`
- `clipShape(_:style:)`
- `contentShape`
- `border`, including stored `ForegroundStyle`, generic `ShapeStyle`, and `LinearGradient` overloads
- `shadow`, including SwiftUI-style default-color `shadow(radius:x:y:)`
- `layoutPriority`
- `alignmentGuide`
- `gridCellColumns`
- `gridCellAnchor`
- `gridCellUnsizedAxes`
- `gridColumnAlignment`
- `allowsHitTesting`
- `focusable`
- `hoverEffect`
- `defaultHoverEffect`
- `hoverEffectDisabled`
- `focusEffectDisabled`
- `keyboardShortcut`
- `itemProvider`
- `onDrag`
- `draggable`
- `onDrop`
- `dropConfiguration`
- `dropPreviewsFormation`
- `springLoadingBehavior`
- `onDelete`
- `onMove`
- `onInsert`
- `dropDestination`
- `onDeleteCommand`
- `onMoveCommand`
- `onExitCommand`
- `pageCommand`
- `onPlayPauseCommand`
- `redacted`
- `unredacted`
- `privacySensitive`
- `opacity`
- `blendMode`
- `compositingGroup`
- `drawingGroup`
- `brightness`
- `contrast`
- `colorInvert`
- `colorMultiply`
- `saturation`
- `grayscale`
- `hueRotation`
- `luminanceToAlpha`
- `hidden`
- `zIndex`
- `offset`
- `scaleEffect`
- `flipsForRightToLeftLayoutDirection`
- `rotationEffect`
- `rotation3DEffect`
- `perspectiveRotationEffect`
- `transformEffect`
- `projectionEffect`
- `visualEffect`
- `visualEffect3D`
- `colorEffect`
- `distortionEffect`
- `layerEffect`
- `blur(radius:opaque:)`
- `transition`
- `contentTransition`
- `contentTransitionAddsDrawingGroup`
- `symbolEffect`
- `symbolEffectsRemoved`
- `sensoryFeedback`
- `animation`
- `phaseAnimator`
- `disabled`
- `scrollDisabled`
- `scrollClipDisabled`
- `scrollContentBackground`
- `scrollIndicators`
- `scrollIndicatorsFlash`
- `scrollPosition`
- `scrollTransition`
- `onScrollGeometryChange`
- `onScrollPhaseChange`
- `onScrollVisibilityChange`
- `onScrollTargetVisibilityChange`
- `scrollBounceBehavior`
- `scrollTargetBehavior`
- `scrollTargetLayout`
- `scrollInputBehavior`
- `contentMargins`
- `defaultScrollAnchor`
- `scrollDismissesKeyboard`
- `searchDictationBehavior`
- `defaultWheelPickerItemHeight`
- `listRowBackground`
- `listRowInsets`
- `listItemTint`
- `listRowSeparator`
- `listRowSeparatorTint`
- `listSectionSeparator`
- `listSectionSeparatorTint`
- `listSectionMargins`
- `listSectionSpacing`
- `selectionDisabled`
- `deleteDisabled`
- `moveDisabled`
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
- `onContinuousHover`
- `onTapGesture`
- `onLongPressGesture`
- `gesture`
- `highPriorityGesture`
- `simultaneousGesture`
- `accessibilityLabel`
- `accessibilityValue`
- `accessibilityHint`
- `accessibilityIdentifier`
- `accessibilityHidden`
- `accessibilityAddTraits`
- `accessibilityRemoveTraits`
- `accessibilityElement`
- `accessibilitySortPriority`
- `accessibilityAction`
- accessibility preference/state environment values: `accessibilityAssistiveAccessEnabled`, `accessibilityDimFlashingLights`, `accessibilityDifferentiateWithoutColor`, `accessibilityEnabled`, `accessibilityInvertColors`, `accessibilityLargeContentViewerEnabled`, `accessibilityPlayAnimatedImages`, `accessibilityPrefersHeadAnchorAlternative`, `accessibilityQuickActionsEnabled`, `accessibilityReduceHighlightingEffects`, `accessibilityReduceMotion`, `accessibilityReduceTransparency`, `accessibilityShowButtonShapes`, `accessibilityShowBorders`, `accessibilitySwitchControlEnabled`, and `accessibilityVoiceOverEnabled`
- `help`
- `tag`
- `modifier`

Compatibility helpers:

- `ViewModifier`
- `ViewModifier.Content`
- `ModifiedContent`
- `PlaceholderContentView`
- `AnyTransition`
- `ContentTransition`
- `SymbolEffect`
- `SymbolEffectOptions`
- `SensoryFeedback`
- `ListStyle`
- generic `ShapeStyle` overloads
- `AnyShapeStyle`
- `OpacityShapeStyle`
- `BackgroundStyle`
- `SelectionShapeStyle`
- `SeparatorShapeStyle`
- `TintShapeStyle`
- `PlaceholderTextShapeStyle`
- `LinkShapeStyle`
- `FillShapeStyle`
- `WindowBackgroundShapeStyle`
- `HierarchicalShapeStyle`
- `Material`
- `ContainerBackgroundPlacement`
- `LocalizedStringResource` text inputs
- `String(localized: LocalizedStringResource)`
- `ColorResource(name:bundle:)`
- `Color(_:bundle:)`
- `Color(ColorResource)`
- `Color.RGBColorSpace`
- `Color(_:red:green:blue:opacity:)`
- `Color(_:white:opacity:)`
- `Color(red:green:blue:opacity:)`
- `Color(white:opacity:)`
- `Color(hue:saturation:brightness:opacity:)`
- common `Color` constants such as `red`, `blue`, `gray`, `primary`, `secondary`, and `accentColor`
- `Color.opacity(_:)`
- named `Font` styles such as `body`, `title`, `headline`, and `caption`
- `Font.system(_:design:weight:)` with `Font.TextStyle` presets
- `Font.custom(_:size:)`
- `Font.custom(_:fixedSize:)`
- `Font.custom(_:size:relativeTo:)`
- `Font.leading(_:)`
- `Font.width(_:)`
- `Font.bold(_:)`
- `Font.italic(_:)`
- `Font.monospacedDigit()`
- `Font.smallCaps(_:)`
- `Font.lowercaseSmallCaps(_:)`
- `Font.uppercaseSmallCaps(_:)`
- `Text.Scale`
- `Text.Layout`
- `TextRenderer`
- `TextAttribute`
- `TextProxy`
- `GraphicsContext` (SwiftUI-shape Canvas drawing context: `Shading.color(_:)` and `Shading.linearGradient(_:startPoint:endPoint:)` with `CGPoint` endpoints; `fill`/`stroke` for `Path` and `CGRect`; `draw` for `BitmapSurface`, `Text`, `String`; mutable `opacity`; mutable `transform` with `translateBy`/`scaleBy`/`rotate`/`concatenate` (CG-style pre-multiply); `clip(to:)`/`popClip()`; `drawLayer { sub in ... }` for parent-transform-inheriting sub-contexts)
- `Canvas { ctx, size in ... }` paints through the default GPUIScene path
- `Path.contains(_:eoFill:)` (ray-cast hit testing, non-zero and even-odd fill rules)
- `Gradient.init(stops: [Gradient.Stop])` preserves custom `Double` `location`
  values; axis-aligned fills render intermediate stops, hard transitions,
  transparent stops, and reversed endpoints on CPU, the D3D11 scene path, and
  both live frame-fallback presenters
- `ProposedViewSize`
- `ViewSpacing`
- `LayoutProperties`
- `LayoutValueKey`
- `HStackLayout`
- `VStackLayout`
- `ZStackLayout`
- `AnyLayout`
- `ContainerValueKey`
- `ContainerValues`
- `Animatable`
- `EmptyAnimatableData`
- `VectorArithmetic`
- `Font.monospaced()`
- `Animation`
- `AnimationCompletionCriteria`
- `Transaction`
- `withAnimation`
- `withTransaction`
- `LinearGradient(colors:startPoint:endPoint)`
- `UnitPoint`
- `UnitPoint3D`
- `RotationAxis3D`
- `Size3D`
- `Point3D`
- `Rect3D`
- `EdgeInsets3D`
- `Rotation3D`
- `AffineTransform3D`
- `CGAffineTransform`
- `ProjectionTransform`
- `BlendMode`
- `ColorRenderingMode`
- `Angle`
- `Axis`
- `HoverEffect`
- `HoverPhase`
- `RedactionReasons`
- `ColorSchemeContrast`
- `LegibilityWeight`
- `LayoutDirection`
- `DynamicTypeSize`
- `KeyEquivalent`
- `EventModifiers`
- `KeyboardShortcut`
- `MoveCommandDirection`
- `CoordinateSpace`
- `CoordinateSpaceProtocol`
- `GlobalCoordinateSpace`
- `LocalCoordinateSpace`
- `NamedCoordinateSpace`
- `Gesture`
- `AnyGesture`
- `SimultaneousGesture`
- `SequenceGesture`
- `ExclusiveGesture`
- `GestureMask`
- `TapGesture`
- `SpatialTapGesture`
- `LongPressGesture`
- `DragGesture`
- `GestureState`
- `ButtonRepeatBehavior`
- `ButtonSizing`
- `ButtonBorderShape`
- `ScrollBounceBehavior`
- `ScrollTarget`
- `ScrollTargetBehavior`
- `ScrollTargetBehaviorContext`
- `ScrollTargetBehaviorProperties`
- `ScrollTargetBehaviorPropertiesContext`
- `PagingScrollTargetBehavior`
- `ViewAlignedScrollTargetBehavior`
- `AnyScrollTargetBehavior`
- `ScrollInputBehavior`
- `ScrollInputKind`
- `ScrollPosition`
- `ScrollViewProxy`
- `CGVector`
- `ScrollGeometry`
- `ScrollPhase`
- `ScrollPhaseChangeContext`
- `VisualEffect`
- `EmptyVisualEffect`
- `UnitCurve`
- `ScrollTransitionPhase`
- `ScrollTransitionConfiguration`
- `ScrollDismissesKeyboardMode`
- `ListSectionSpacing`
- `SubmitTriggers`
- `SubmitLabel`
- `TextInputAutocapitalization`
- `TextSelection`
- `TextSelectionAffinity`
- `UIKeyboardType`
- `WritingToolsBehavior`
- `TextInputDictationActivation`
- `TextInputDictationBehavior`
- `NSTextContentType`
- `Visibility`
- `AccessibilityTraits`
- `AccessibilityChildBehavior`
- `AccessibilityActionKind`
- `TextSelectability`
- `Prominence`
- `BackgroundProminence`
- `BadgeProminence`
- `ContainerBackgroundPlacement`
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
- `FocusedObject`
- `EnvironmentObject`
- `DynamicProperty`
- `DynamicViewContent`
- `UTType`
- `NSItemProvider`
- `Transferable`
- `DropInfo`
- `DropDelegate`
- `DropProposal`
- `DropOperation`
- `DropSession`
- `DropConfiguration`
- `DragDropPreviewsFormation`
- `SpringLoadingBehavior`
- `Namespace`
- `MatchedGeometryProperties`
- `AppStorage`
- `SceneStorage`
- `ScaledMetric`
- `UndoManager`
- `UserInterfaceSizeClass`
- `LocalizedStringKey`
- `CGFloat`, `CGPoint`, `CGSize`, `CGRect` aliases
- `EdgeInsets()`
- minimal `Binding`, `State`, `DynamicProperty`, `Namespace`, `AppStorage`, `SceneStorage`, `ScaledMetric`, `FocusState`, `GestureState`, `Environment`, `EnvironmentValues`, `EnvironmentObject`, `FocusedValue`, `FocusedBinding`, `FocusedObject`, `OpenURLAction`, `DismissAction`, `DismissSearchAction`, `RenameAction`, `RefreshAction`, `OpenWindowAction`, `DismissWindowAction`, `OpenSettingsAction`, `RequestReviewAction`, `UndoManager`, `EditMode`, `ObservableObject`, `ObservableObjectPublisher`, `Published`, `ObservedObject`, and `StateObject`

Surface direction:

- default retained buttons now use lighter rounded chrome with hover, focus, press, and activation transitions
- the demo’s cards and chips are built from shared-source-friendly layered gradients and translucent strokes rather than WinSwiftUI-only styling hooks

## Size proposals and greedy views

The retained layout engine measures intrinsically: `ViewNode.sizeThatFits(in:)`
answers "how big is my content" for a set of `LayoutConstraints`. That alone
cannot express SwiftUI's *greedy* views — a `ScrollView`, a `List`, a `Form`, a
`Color`, a `Divider` across its cross axis, or anything given
`.frame(maxWidth: .infinity)` — all of which take the space their parent
proposes rather than the size of their content. Without that concept every
container shrink-wrapped, and an idiomatic screen (NavigationStack > ScrollView
> Form) rendered into a fraction of the window with the rest left as clear
colour.

`ViewNode.layoutFillAxes` is the runtime's model of it:

- **Measurement.** A greedy axis takes the proposal whenever the proposal is
  finite. Against an unconstrained axis the node still reports its content
  size, so an intrinsic measurement of a greedy subtree stays finite and a
  greedy child never inflates its parent's intrinsic size to infinity.
- **Stack main axis.** A stack proposes only its cross extent to children, so a
  greedy child measures its content along the main axis and then *grows* into
  the stack's leftover extent (`growMainSizes`). That is what keeps
  `VStack { Text; ScrollView }` from over-subscribing the track.
- **Squeeze.** When a track is over-subscribed the greedy children give their
  extra back first (`shrinkMainSizes`), before any sibling that asked only for
  the size of its content. A scroll view whose content is taller than the
  window no longer squeezes the tab bar or toolbar beside it.
- **Precedence.** An explicit frame (`.frame(width:height:)`, `ViewNode.frame`)
  is the author's own answer and always wins. A `preferredSize` is only an
  *ideal*: a greedy node with one (a slider, a scroll panel) reports it when
  nothing proposes an extent, and fills when something does.

Greedy today: `ScrollView` (both axes), `List`, `Form` (horizontal, capped at
`MacOSControlMetrics.Form.contentMaxWidth` and centred in the leftover),
`NavigationStack`/`NavigationView` containers, the `TabView` container and its
tab band, `GeometryReader`, `Divider` (cross axis), `Slider` (horizontal), a
grouped-form row's value column, and any node given an infinite `frame`
maximum.

The segmented picker track is **not** greedy: an `NSSegmentedControl` is
intrinsically sized (equal segments as wide as the widest label) and stretches
only when something explicitly asks — a `.frame(width:)`, a `.stretch`
container. It used to declare itself greedy, which is how a three-segment
picker came to be 1215pt wide in a settings pane.

The runtime root stays `.absolute`, and its children are measured against the
window's extent — so a greedy top-level view fills the window the way an
`NSWindow` content view does, while a non-greedy one keeps its intrinsic size
at the origin.

## Mapping Notes

- `Text` maps into retained label nodes and the current runtime text renderer path.
- `LocalizedStringKey` is a source-compatibility shim that resolves to plain retained text today; it does not perform bundle/table lookup or real localization yet. `Text(LocalizedStringKey, tableName:bundle:comment:)` accepts SwiftUI's localized text metadata labels but currently resolves the key through the same retained text path. Common title-bearing controls and titled containers also accept `StringProtocol` inputs such as `Substring` and forward them through the same retained label paths as `String` titles.
- Named `Font` styles and `Font.system(_:design:weight:)` text-style overloads are fixed point-size and weight presets before environment scaling. `Font.custom(_:size:)` stores the supplied Windows font family name and participates in the retained dynamic type scale; `Font.custom(_:fixedSize:)` stores the same family but bypasses dynamic type scaling; `Font.custom(_:size:relativeTo:)` keeps the supplied family and point size while inheriting retained weight/design/leading defaults from the referenced text style. `Font.leading(_:)` maps `.standard`, `.tight`, and `.loose` onto retained line spacing values of `2`, `0`, and `6`; explicit `lineSpacing(_:)` still takes precedence. `Font.Width` accepts `.compressed`, `.condensed`, `.standard`, and `.expanded`; `Font.width(_:)`, `Text.fontWidth(_:)`, and container `fontWidth(_:)` retain width metadata, pass it to DirectWrite as font stretch, and provide a deterministic GDI fallback width hint. `Font.bold(_:)`, `Font.italic(_:)`, and `Font.monospacedDigit()` retain the matching text weight, italic, and tabular-digit metadata when the font is applied to retained `Text` or text input labels. `Font.smallCaps(_:)`, `Font.lowercaseSmallCaps(_:)`, and `Font.uppercaseSmallCaps(_:)` retain small-capital typography intent and pass OpenType `smcp` / `c2sc` feature tags to DirectWrite when native text layout is available; fallback paths preserve metadata and render without synthetic small-cap glyph substitution. `dynamicTypeSize(_:)` and `EnvironmentValues.dynamicTypeSize` scale retained `Text` and text-input font sizes with SwiftUI-shaped cases from `.xSmall` through `.accessibility5`; this is a deterministic retained scale table, not a Windows system text-size subscription yet. `legibilityWeight(_:)` and `EnvironmentValues.legibilityWeight` accept `.regular`, `.bold`, or `nil`; retained text maps that value through the existing font-weight path unless an explicit `.fontWeight(_:)` overrides it. This is an inherited compatibility value, not yet a Windows Bold Text accessibility subscription. `Text.bold(_:)`, `Text.italic(_:)`, `Text.monospaced(_:)`, and the matching container modifiers accept SwiftUI-shaped Boolean toggles for source compatibility and retained subtree overrides. `Text.italic()` and container `.italic()` carry retained italic text style through native DirectWrite/GDI font creation and glyph/text caches. `Font.Design.default` and `.rounded` map to Segoe UI, `.serif` maps to Georgia, and `.monospaced` maps to Cascadia Mono. `Font.monospaced()`, `Font.monospaced(_:)`, `Text.monospaced()`, and `fontDesign(_:)` resolve through the same retained font family mapping as `.system(..., design: .monospaced)`. `Text.monospacedDigit()` and container `.monospacedDigit()` retain fixed-width digit intent and request DirectWrite tabular figures on the native text path; fallback text paths keep the metadata and otherwise render with their current font support. `font(_:)` accepts `Font?`, bridges through `EnvironmentValues.font`, and `.font(nil)` resets a subtree to the retained default font. `Text.fontWeight(nil)` clears a previously applied explicit text weight while preserving inherited container weight when no explicit text font is present.
- SwiftUI-shaped RGB, white, and HSB `Color` initializers reduce to the renderer-neutral RGBA color type used by the retained scene. `Color.RGBColorSpace.sRGBLinear` converts linear component values through the standard sRGB transfer curve before retaining them; `.sRGB` preserves supplied components, and `.displayP3` is accepted but currently stored as renderer-neutral RGB channels without gamut conversion.
- `frame(minWidth:idealWidth:maxWidth:minHeight:idealHeight:maxHeight:alignment:)` maps finite constraints into retained `LayoutConstraints`; an *infinite* maximum is not a constraint at all but SwiftUI's "be greedy on this axis", and maps to `ViewNode.layoutFillAxes` (see "Size proposals and greedy views" below), so `.frame(maxWidth: .infinity)` takes the width its parent proposes.
- `containerRelativeFrame` maps requested axes to deterministic retained frame sizes derived from the current `ViewBuildContext.canvasSize`. The direct axes overload uses the full container length, the closure overload receives the current container length and axis, and the `count` / `span` / `spacing` overload computes grid-slot lengths for the requested axes. This is based on the retained build context rather than SwiftUI's full container proposal hierarchy.
- `fixedSize()` and `fixedSize(horizontal:vertical:)` map to retained measurement axes that ignore incoming maximum constraints on selected axes; final placement can still be limited by the parent layout mode.
- `padding` accepts SwiftUI-style optional lengths; `nil` resolves to the retained default of `16`.
- `ignoresSafeArea` and `edgesIgnoringSafeArea` are accepted for source compatibility but currently pass through unchanged because the Win32 host renders into a client-area surface with no derived unsafe insets. `safeAreaPadding` maps onto the retained padding wrapper, so shared-source layouts that request safe-area padding still get deterministic retained spacing on Windows. `safeAreaInset(edge:alignment:spacing:content:)` accepts `VerticalEdge` and `HorizontalEdge` call sites and composes the inset content before or after the base view with retained stacks, resolving leading/trailing through `layoutDirection`; it does not yet reserve platform-derived unsafe regions.
- `EnvironmentValues.scenePhase` accepts `.active`, `.inactive`, and `.background`, defaults to `.active`, and can be overridden with `.environment(\.scenePhase, ...)` for shared-source app logic. Hosted Win32 windows update this value from app activation and visibility events, mapping visible active windows to `.active`, visible inactive windows to `.inactive`, and hidden windows to `.background`.
- `EnvironmentValues.controlActiveState` accepts `.key`, `.active`, and `.inactive`, while `EnvironmentValues.appearsActive` provides the newer Boolean active-appearance hint. Hosted Win32 windows map the single live window to `.key` while active and visible, `.inactive` while inactive or hidden, and update `appearsActive` from the same active/visible state.
- `EnvironmentValues.isLuminanceReduced`, `EnvironmentValues.isSceneCaptured`, and `EnvironmentValues.isTabBarShowingSections` are readable and overrideable compatibility values. They default to `false`; the Win32 host does not yet derive them from display power/luminance policy, capture/recording state, or adaptive tab layout.
- `EnvironmentValues.isPresented` defaults to `false` and becomes `true` for retained `NavigationStack` / `NavigationView` destination content, retained sheet content, retained full-screen cover content, retained popover content, retained alert message/action content, retained action sheet content, retained confirmation dialog message/action content, and retained context menu content, including path, pushed link, and binding-driven navigation destinations. Other presentation APIs such as native windows are not modeled yet.
- `EnvironmentValues.supportsMultipleWindows` is readable and overrideable for shared-source scene/window conditionals. It is `true` for coordinator-managed hosts — `WinSwiftUIWindowCoordinator` hosts multiple live windows, each with its own host, retained runtime, and renderer — and `false` otherwise.
- `EnvironmentValues.editMode` accepts an optional `Binding<EditMode>` with `.inactive`, `.transient`, and `.active` values. `EditButton` reads that binding and toggles between `.inactive` and `.active`; selection-capable retained `List` rows show leading selection indicators while editing. Reorder/delete edit chrome is not implemented yet.
- `EnvironmentValues.layoutDirection` accepts `.leftToRight` and `.rightToLeft`. Right-to-left direction flips retained leading/trailing alignment for `Text`, `Image(systemName:)`, text inputs, `frame(alignment:)`, `background(_:alignment:)`, `overlay(_:alignment:)`, `VStack`, `LazyVStack`, `Grid`, `ZStack`, `ScrollView`, and `Section`. `flipsForRightToLeftLayoutDirection(_:)` applies a centered retained horizontal transform when enabled under `.rightToLeft`, so shared-source icons, bitmaps, and custom retained subtrees can opt into explicit mirroring. Layout direction does not yet automatically mirror arbitrary custom drawing or bitmap content unless that modifier is applied.
- `EnvironmentValues.horizontalSizeClass` and `EnvironmentValues.verticalSizeClass` accept optional `.compact` / `.regular` `UserInterfaceSizeClass` values for shared-source adaptive layout checks. Hosted windows derive them from the current logical window size using WinSwiftUI's retained surface thresholds, and explicit environment overrides still take precedence inside modified subtrees.
- `EnvironmentValues.openWindow` and `EnvironmentValues.dismissWindow` provide SwiftUI-shaped scene actions with `id:` and `Codable & Hashable` value overloads. The default actions route through `WinSwiftUIWindowCoordinator`: `openWindow` spawns an independent window (own host, retained runtime, and renderer) for the matching id- or value-based `WindowGroup`, and `dismissWindow` closes the calling scene's window or matches a window by id/value. Injected handlers can keep using the optional-id initializer or receive a `WindowActionPayload` containing the optional id and type-erased `Hashable` value.
- `EnvironmentValues.openSettings` provides a SwiftUI-shaped `OpenSettingsAction`, and `SettingsLink` maps to a retained button that calls it. The default action is a no-op because WinSwiftUI does not yet model a `Settings` scene or native settings window lifecycle.
- `EnvironmentValues.requestReview` provides a SwiftUI/StoreKit-shaped `RequestReviewAction`. The default action is a no-op because Windows builds do not have App Store review prompt integration, but apps and tests can inject a handler for shared-source flows.
- `@EnvironmentObject` and `environmentObject(_:)` propagate typed `ObservableObject` instances through retained environment context and observe `@Published` changes and manual `objectWillChange.send()` notifications through the same invalidation path as `@ObservedObject`.
- `FocusedValueKey`, `FocusedValues`, `@FocusedValue`, `@FocusedBinding`, `@FocusedObject`, `focusedValue(_:_:)`, `focusedSceneValue(_:_:)`, `focusedObject(_:)`, and `focusedSceneObject(_:)` are retained-context compatibility shims. Published focused values and objects propagate through the modified subtree, focused bindings can read/write their current binding, and focused objects observe `@Published` changes through the retained invalidation path, but the runtime does not yet retarget those values dynamically as native focus moves between nodes.
- `EnvironmentValues.undoManager` accepts an optional `UndoManager` for shared-source command and editing code. WinSwiftUI provides a small Windows shim with `registerUndo(withTarget:handler:)`, `setActionName(_:)`, `undo()`, `redo()`, `removeAllActions()`, and basic stack state; hosted windows install a stable per-window default undo manager, but it is not yet bridged to native edit commands.
- `LocalizedStringResource` is accepted as a lightweight compatibility value on Windows toolchains where Foundation does not expose the Apple type. `Text(LocalizedStringResource)` and `String(localized: LocalizedStringResource)` resolve the stored resource text before creating retained text or plain strings. The current retained text node stores the resolved string only; it does not keep late-bound localization metadata after build.
- `Text(Date, style:)` and `Text(DateInterval)` are accepted for SwiftUI-shaped source compatibility and render deterministic UTC retained strings today. `.date` maps to `yyyy-MM-dd`, `.time` maps to `HH:mm`, intervals map to `yyyy-MM-dd HH:mm - yyyy-MM-dd HH:mm`, and `.relative`, `.offset`, and `.timer` currently use the static date/time fallback; they do not live-update or schedule retained invalidations yet.
- `Text(timerInterval:pauseTime:countsDown:showsHours:)` accepts SwiftUI's timer text initializer and renders a retained static duration string from `pauseTime` or the current build-time `Date`. It clamps before/after the interval, supports count-up/count-down direction, and formats as `m:ss`, `h:mm:ss`, or total-minute `m:ss` when `showsHours` is false. Automatic ticking updates are not modeled yet.
- `Text(_:formatter:)` accepts Foundation `Formatter` values such as `NumberFormatter` and `DateFormatter`, resolves their current string output during retained view construction, and falls back to `String(describing:)` if the formatter cannot represent the supplied value. The retained text node stores only that resolved string and does not keep formatter metadata for later locale or value updates.
- `Text(_:format:)` accepts `FormatStyle` values that produce `String` or `AttributedString` output. String-producing styles map directly to retained text, while attributed output is flattened to plain retained text until rich text runs are modeled.
- `Text(AttributedString)` accepts styled attributed text input and flattens it to plain retained text. Attribute scopes such as emphasis, foreground color, links, and Markdown-derived runs are not preserved until retained text supports rich runs.
- `ShapeStyle` and `AnyShapeStyle` bridge `Color`, `LinearGradient`, `OpacityShapeStyle`, `HierarchicalShapeStyle`, `BackgroundStyle`, `SelectionShapeStyle`, `SeparatorShapeStyle`, `TintShapeStyle`, `PlaceholderTextShapeStyle`, `LinkShapeStyle`, `FillShapeStyle`, `WindowBackgroundShapeStyle`, `Material`, and stored `ForegroundStyle` values into the retained foreground path. Generic `ShapeStyle` overloads are accepted by `foregroundStyle`, `background`, `overlay`, `border`, `Text.foregroundStyle`, `Label.foregroundStyle`, and retained shape `fill`/`stroke`/`strokeBorder` methods. `ShapeStyle.opacity(_:)` multiplies retained alpha for solid colors and every retained linear-gradient stop before the style reaches the renderer-neutral fill paths. `HierarchicalShapeStyle.primary`, `secondary`, `tertiary`, `quaternary`, and `quinary` are accepted, including contextual leading-dot spellings such as `.tertiary`, and degrade to deterministic retained semantic foreground colors because retained nodes do not model hierarchical foreground style slots yet. Semantic styles such as `.foreground`, `.background`, `.selection`, `.separator`, `.tint`, `.placeholder`, `.link`, `.fill`, and `.windowBackground` are accepted with deterministic retained fallback colors because WinSwiftUI does not yet resolve all platform semantic colors from the full environment. `Material.ultraThin`, `thin`, `regular`, `thick`, `ultraThick`, and `bar` are accepted, as are contextual style members such as `.regularMaterial` and `.bar`; they currently degrade to deterministic translucent retained fills because backdrop blur, vibrancy, active appearance, and custom environment-resolved shape styles are not modeled yet.
- Text and foreground styling modifiers on containers propagate through `ViewBuildContext`, while explicit `Text`, `Image`, and `Label` styling still takes precedence. Solid `foregroundStyle` maps to inherited text/icon color, including stored `ForegroundStyle.color` values and semantic color shorthand such as `.foregroundStyle(.secondary)`. `Text.foregroundStyle(...)` also returns `Text` for source-compatible text concatenation, and `Label.foregroundStyle(...)` returns `Label` for source-compatible label styling chains; both use the primary style for multi-argument overloads and the gradient start color for retained text/icon fallback. `EnvironmentValues.colorSchemeContrast` accepts `.standard` and `.increased`; increased contrast brightens retained `.secondary` foreground values for text, icons, labels, and inherited foreground styles, and hierarchical greys snap to a legible high-contrast ramp. The value is derived from Windows high contrast via `SystemAppearanceSnapshot`, sampled at startup and re-sampled on `WM_SETTINGCHANGE`/`WM_SYSCOLORCHANGE`; app overrides (`preferredColorScheme`, explicit `.environment(_:_:)` sets) take precedence over the system snapshot. It is not a full semantic color system. `EnvironmentValues.backgroundProminence(.increased)` also brightens retained `.secondary` text/icon foregrounds, including selected `List` row content that derives increased prominence. Multi-argument `foregroundStyle` overloads are accepted for source compatibility and currently use the primary style because retained nodes do not model hierarchical foreground style slots yet. `LinearGradient` and stored `ForegroundStyle.linearGradient` values map to retained gradient fills for `Rectangle`, `RoundedRectangle`, `Capsule`, `Circle`, and `Ellipse`, while text/icons use the gradient start color as a compatibility fallback. `background` and `overlay` also accept stored `ForegroundStyle` values and route them through the existing retained color/gradient panel paths. `Circle` uses the retained dynamic rounded path, and `Ellipse` currently uses the same capsule-style rounded fallback until true elliptical retained primitives are added. Shape `fill(_:)` also accepts stored `ForegroundStyle` values. `Text + Text` is accepted for source compatibility and flattens into one retained label; because retained text nodes do not have rich text runs yet, explicit styling resolves to a single node style with left-hand styling taking precedence when both sides set the same property. `lineSpacing(_:)`, `kerning(_:)`, and `tracking(_:)` map to retained text style for whole subtrees as well as direct `Text` values; line spacing participates in retained measurement, and letter spacing is applied by the DirectWrite glyph path to both measurement and painted glyph positions (via `PixelTextStyle.nativeLetterSpacing`, which is separate from `letterSpacing` — that field is the 5×7 bitmap atlas gap in atlas units, not points). The legacy bitmap raster path cannot express tracking and reports the drop through `TextRenderDiagnostics.letterSpacingDroppedRasterizations`. `baselineOffset(_:)` maps to retained vertical `Transform2D` metadata on descendant text nodes, with explicit `Text.baselineOffset(_:)` taking precedence over inherited container offsets. `Text.Scale.default`, `Text.Scale.secondary`, `Text.textScale(_:isEnabled:)`, and container `textScale(_:isEnabled:)` map to deterministic retained font-size scaling for descendant text and text-input labels; `.secondary` currently uses a fixed 0.85 multiplier until WinSwiftUI models Apple's full logical text-scale behavior. `TextRenderer`, `Text.Layout`, `TextProxy`, `GraphicsContext`, `TextAttribute`, `Animatable`, `EmptyAnimatableData`, `VectorArithmetic`, and `textRenderer(_:)` are accepted as source-compatibility shims; the retained runtime still renders text through its native/pixel glyph paths and does not invoke custom renderer drawing yet. `minimumScaleFactor(_:)` is clamped to `0...1` and now reduces the effective retained text size before truncation when constrained width requires it, across DirectWrite, GDI, pixel fallback, and GPUI glyph scene paths. `allowsTightening(_:)` maps to the retained text kerning toggle until true glyph tightening is modeled. `textCase(_:)` applies inherited or explicit uppercase/lowercase transforms before retained label creation. `textSelection(_:)` retains `.enabled` or `.disabled` selectability intent on text nodes inherited through the build context, but selection UI and clipboard gestures are not implemented yet. `textSelectionAffinity(_:)` accepts `.automatic`, `.upstream`, and `.downstream`, propagates through `EnvironmentValues.textSelectionAffinity`, and stores cursor/selection affinity metadata on retained text and text-input nodes for future selection behavior. `lineLimit(_:reservesSpace:)` maps the maximum line count and reserves retained measurement height for that many lines when requested. Range-shaped line limits are also accepted: `...max` maps to a retained maximum, `min...` reserves minimum retained line height without imposing a maximum, and `min...max` combines both. `multilineTextAlignment(_:)`, `lineLimit(_:)`, `lineSpacing(_:)`, `minimumScaleFactor(_:)`, `truncationMode(_:)`, `allowsTightening(_:)`, `textSelection(_:)`, `textSelectionAffinity(_:)`, and `textCase(_:)` bridge through `EnvironmentValues`, so `@Environment` and `.environment(\.lineLimit, ...)` see the same inherited retained text values. `truncationMode(_:)` maps `.head`, `.tail`, and `.middle` to the retained text line-break modes when a line limit is active. `Text.LineStyle`, pattern-aware `underline`/`strikethrough` overloads, and matching container modifiers retain solid/dot/dash/dash-dot-dot metadata; both the GPUI scene path and legacy `RenderFrame` fallback emit those decorations as renderer-neutral solid or segmented fill quads/rect commands.
- `imageScale(_:)` propagates through `EnvironmentValues` and maps `.small`, `.medium`, and `.large` to retained symbol icon scale for `Image(systemName:)` and label icons.
- `symbolRenderingMode(_:)` propagates optional `.monochrome`, `.hierarchical`, `.palette`, and `.multicolor` metadata through `EnvironmentValues` and onto retained image nodes for `Image(systemName:)` and label icons. Retained system icons consume those modes with deterministic renderer-neutral color treatments: monochrome keeps the resolved foreground color, hierarchical dims it, palette uses the inherited tint, and multicolor uses a fixed accent color until true multi-layer symbol drawing exists.
- `symbolVariant(_:)` propagates `SymbolVariants` metadata such as `.fill`, `.slash`, `.circle`, `.square`, and `.rectangle` through `EnvironmentValues` and onto retained image nodes for `Image(systemName:)` and label icons. Retained system icons now consume common variants with renderer-neutral chrome: `.fill` requests heavier icon text, `.circle` / `.square` / `.rectangle` wrap the icon in matching retained outline or filled shape chrome, and `.slash` overlays a retained slash segment. Full SF Symbol variant lookup and multicolor symbol drawing are still not implemented.
- `tint` and `accentColor` propagate through `ViewBuildContext`; retained controls consume the inherited tint for toggle-on, slider-fill, progress-fill, and gauge-fill colors.
- `labelsHidden()` propagates through `ViewBuildContext` and suppresses retained label nodes for controls such as `Toggle`, `Picker`, `Stepper`, `Slider`, `ProgressView`, and `Gauge`.
- `EnvironmentValues.displayScale` and `EnvironmentValues.pixelLength` are populated from the retained runtime's current surface scale for hosted windows and `WinSwiftUIRendererSnapshotter` snapshots. They can also be overridden with `.environment(\.displayScale, ...)` and `.environment(\.pixelLength, ...)`; changing `displayScale` manually does not recompute `pixelLength` unless both values are set.
- Icon rasterization is per-window correct: every WinSwiftUI icon passes `ViewBuildContext.iconRasterDisplayScale`, which reads `EnvironmentValues.displayScale`. The process-global `NativeTextRenderer.defaultIconDisplayScale` remains only as the last-resort default of `Controls.icon` for callers with no view environment (`DeclarativeUI`, tools, tests). Hosts claim it through `NativeTextRenderer.claimDefaultIconDisplayScale(_:owner:)`, which writes only while exactly one window host is live — so the sole window keeps it correct across DPI changes and monitor moves, and a second window can no longer decide the icon raster scale for the first. **Known limitation:** in a multi-window mixed-DPI process, environment-less callers get the first live window's scale for every window. De-globalizing that default is the real fix and is not done yet.
- `font(_:)`, `fontWidth(_:)`, `dynamicTypeSize(_:)`, `legibilityWeight(_:)`, `tint(_:)`, `accentColor(_:)`, `buttonRepeatBehavior(_:)`, `buttonSizing(_:)`, `buttonBorderShape(_:)`, `menuIndicator(_:)`, `submitLabel(_:)`, and `controlSize(_:)` bridge into `EnvironmentValues`, so `@Environment(\.font)`, `@Environment(\.fontWidth)`, `@Environment(\.dynamicTypeSize)`, `@Environment(\.legibilityWeight)`, `@Environment(\.tint)`, `@Environment(\.buttonRepeatBehavior)`, `@Environment(\.buttonSizing)`, `@Environment(\.buttonBorderShape)`, `@Environment(\.menuIndicatorVisibility)`, `@Environment(\.submitLabel)`, `@Environment(\.controlSize)`, `.environment(\.font, ...)`, `.environment(\.fontWidth, ...)`, `.environment(\.dynamicTypeSize, ...)`, `.environment(\.legibilityWeight, ...)`, `.environment(\.tint, ...)`, `.environment(\.buttonRepeatBehavior, ...)`, `.environment(\.buttonSizing, ...)`, `.environment(\.buttonBorderShape, ...)`, `.environment(\.menuIndicatorVisibility, ...)`, `.environment(\.submitLabel, ...)`, and `.environment(\.controlSize, ...)` share the same inherited values consumed by retained text and controls. Optional `Text.font(_:)` accepts concrete fonts and resets `nil` to the retained default text font; optional `Text.fontWidth(_:)` and container `fontWidth(_:)` clear inherited font-width metadata when passed `nil`. `buttonRepeatBehavior` accepts `.automatic`, `.enabled`, and `.disabled`; retained buttons with `.enabled` repeatedly invoke actions during prolonged pointer presses, while `.automatic` and `.disabled` keep single release activation. `buttonSizing` accepts `.automatic`, `.fitted`, and `.flexible`; `.flexible` maps retained `Button` nodes to layout priority `1`, while `.automatic` and `.fitted` keep the current content-fitted retained button sizing. `buttonBorderShape` accepts `.automatic`, `.roundedRectangle`, `.roundedRectangle(radius:)`, `.capsule`, and `.circle`; rounded rectangle values set retained button corner radii, while capsule/circle values compute a fully rounded retained button radius during layout. `menuIndicatorVisibility` now controls the retained `Menu` disclosure glyph, with `.hidden` suppressing it and `.automatic` / `.visible` showing it.
- `controlSize(_:)` maps to retained preferred sizes for text inputs, toggle, menu picker, stepper buttons, slider, progress bar, and gauge surfaces.
- `Label(_:image:)` maps named image resources into the retained label icon slot, while `Label(_:systemImage:)` uses retained system icons. `labelStyle(_:)` propagates through `EnvironmentValues` and maps `.automatic` / `.titleAndIcon`, `.iconOnly`, `.titleOnly`, `DefaultLabelStyle`, `TitleAndIconLabelStyle`, `IconOnlyLabelStyle`, and `TitleOnlyLabelStyle` to retained `Label` composition.
- `toggleStyle(_:)` propagates through `EnvironmentValues`; `.automatic`, `.switch`, `DefaultToggleStyle`, and `SwitchToggleStyle` use the retained switch, `.checkbox` and `CheckboxToggleStyle` map to retained checkbox chrome with arbitrary SwiftUI-shaped label content, and `.button` plus `ButtonToggleStyle` map to retained selected/unselected button chrome.
- `textFieldStyle(_:)` propagates through `EnvironmentValues`; `.automatic`, `.roundedBorder`, `DefaultTextFieldStyle`, and `RoundedBorderTextFieldStyle` use the retained rounded input chrome, `.plain` and `PlainTextFieldStyle` map to a borderless retained input surface, and `.squareBorder` plus `SquareBorderTextFieldStyle` map to retained square-corner bordered chrome.
- `background(_:alignment:)` and `overlay(_:alignment:)` forward view inputs to the retained absolute layering path used by the builder-based overloads. Color, optional color, stored `ForegroundStyle`, and `LinearGradient` inputs also accept the `alignment:` label for SwiftUI source compatibility; those style fills continue to cover the base layout bounds. `BackgroundStyle`, `ShapeStyle.background`, `backgroundStyle(_:)`, `background(ignoresSafeAreaEdges:)`, and `background(in:fillStyle:)` are accepted and feed retained default background style layers, with deterministic retained fallback colors or explicit `backgroundStyle` overrides. `containerBackground(_:for:)` and `containerBackground(for:alignment:content:)` accept SwiftUI placement values and currently map to retained background layers; placement-specific parent-container filling, native window styling, StoreKit behavior, and widget semantics are not modeled yet. `background(_:in:fillStyle:)` and `overlay(_:in:fillStyle:)` accept retained `ShapeStyle` values such as `Color`, `LinearGradient`, and `Material`, draw a separate retained style layer behind or above the base content, and clip that style layer to retained shape fallbacks while preserving `FillStyle` metadata. The shaped style layer fills the base layout bounds; arbitrary path geometry, environment-resolved system background appearance, and material backdrop blur are still not modeled.
- `Section` supports title, header, footer, content-only, and `isExpanded` binding forms, all mapped to the retained vertical section panel. Collapsible sections wrap the header in a retained disclosure-style button, write through the expansion binding, and conditionally include section content; context-specific SwiftUI sidebar/list disclosure styling is not modeled yet.
- `GroupBox` maps title and builder-label forms to a retained vertical panel carrying the same grouped-container chrome a `Form` section box does: `ControlPalette.raisedSurface` under `raisedSurfaceFill`, a `raisedSurfaceRing` hairline, the `MacOSControlMetrics.GroupBox` corner radius and contact shadow. It previously carried dark literals no appearance resolved. `groupBoxStyle(_:)`, `EnvironmentValues.groupBoxStyle`, `GroupBoxStyle.automatic`, and `DefaultGroupBoxStyle` are accepted as source-compatible metadata; retained rendering still uses the default group box chrome.
- `NavigationStack` and `NavigationView` preserve `navigationTitle` / `navigationSubtitle` / `navigationBarTitle` metadata, render lightweight retained title/subtitle chrome, and support local push/pop presentation for direct `NavigationLink(destination:)`, `NavigationLink { destination } label: { ... }`, deprecated `NavigationLink(destination:isActive:label:)`, and deprecated `NavigationLink(destination:tag:selection:label:)` links plus `NavigationLink(value:)` routes resolved by `navigationDestination(for:)`. `navigationBarHidden(_:)` suppresses the retained navigation title/back chrome for content that opts out, while `navigationBarBackButtonHidden(_:)` suppresses only the retained back control for pushed destination content. `isActive` navigation links set their binding when activated and clear it when the retained back control dismisses that pushed destination; tag/selection navigation links set their selection to the tag when activated and clear it on retained back dismissal if it still matches the tag. `NavigationStack(path:)` syncs value-link pushes and back navigation with `NavigationPath` or generic mutable collection bindings, including nested path restoration as each resolved destination contributes its own registered destinations. Boolean and item `navigationDestination` overloads render binding-driven retained destinations and clear their bindings through the back control or `@Environment(\.dismiss)`. Platform-native navigation transitions are not implemented yet.
- `sheet(isPresented:onDismiss:content:)` and `sheet(item:onDismiss:content:)` compose retained bottom-aligned modal overlays above the modified view, install `EnvironmentValues.isPresented`, and provide a `DismissAction` that clears the Boolean or item binding, runs `onDismiss`, and invalidates the retained runtime. The retained sheet scrim dismisses the sheet by default, while `interactiveDismissDisabled(true)` disables that scrim activation and `interactiveDismissDisabled(false)` reenables it. `PresentationDetent` accepts `.medium`, `.large`, `.height(_:)`, and `.fraction(_:)`; `presentationDetents(_:)` applies deterministic retained sheet heights for those detents, and `presentationDetents(_:selection:)` reads the binding's current selected detent when sizing the retained sheet. `PresentationBackgroundInteraction` accepts `.automatic`, `.disabled`, `.enabled`, and `.enabled(upThrough:)`; `.enabled` and `.enabled(upThrough:)` keep the dimming scrim visible but make it visual-only so retained background controls can receive hits, while `.automatic` and `.disabled` keep the default blocking/dismiss scrim behavior. `PresentationContentInteraction` accepts `.automatic`, `.resizes`, and `.scrolls`; `.scrolls` wraps retained sheet content in a vertical scroll panel, while `.automatic` and `.resizes` keep the retained sheet's normal content-sizing behavior. `PresentationAdaptation` accepts `.automatic`, `.none`, `.popover`, `.sheet`, and `.fullScreenCover`; compact popovers with explicit `.sheet` or `.fullScreenCover` adaptation use the retained sheet or full-screen-cover presentation when the matching size-class axis is compact, while `.none`, `.popover`, `.automatic`, and presentations without an explicit compact adaptation keep the retained popover path. `presentationBackground(...)` color, foreground-style, gradient, and optional-color overloads now feed retained sheet, popover, and full-screen-cover panel backgrounds; builder-based `presentationBackground(alignment:content:)` renders retained background content behind the presented content; `presentationCornerRadius(_:)` feeds retained sheet/popover/full-screen-cover corner radius; and `presentationDragIndicator(.visible)` adds a retained handle above presented content while `.hidden` and `.automatic` keep the handle hidden. Native content gesture arbitration, detent-threshold background gating, interactive detent dragging, drag-to-dismiss gestures, and platform transition animations are not implemented yet.
- `fullScreenCover(isPresented:onDismiss:content:)` and `fullScreenCover(item:onDismiss:content:)` compose retained full-bounds cover panels above the modified view, install `EnvironmentValues.isPresented`, and provide a `DismissAction` that clears the Boolean or item binding, runs `onDismiss`, and invalidates the retained runtime. Native full-screen scene takeover, presentation transitions, and drag-to-dismiss gestures are not implemented yet.
- `popover(isPresented:attachmentAnchor:arrowEdge:content:)` and `popover(item:attachmentAnchor:arrowEdge:content:)` compose retained floating panels above the modified view, install `EnvironmentValues.isPresented`, and provide a `DismissAction` that clears the Boolean or item binding. `PopoverAttachmentAnchor` accepts `.rect(_:)` and `.point(_:)` source-compatible values and now feeds deterministic retained placement against the modified view's overlay bounds; `arrowEdge` chooses which side of the anchor the popover occupies, with leading/trailing resolved through `layoutDirection`. Native popover arrows and precise source-rect geometry are not implemented yet.
- `alert(isPresented:content:)`, `alert(item:content:)`, and the builder-style `alert(_:isPresented:actions:message:)` / `alert(_:isPresented:presenting:actions:message:)` overloads compose retained modal alert panels above the modified view. Legacy `Alert.Button` actions automatically dismiss after running their action, and builder-style alerts install `EnvironmentValues.dismiss` plus a default retained `OK` button when no actions are supplied. Native alert chrome, keyboard default/cancel routing, and automatic dismissal of arbitrary builder-supplied buttons are not modeled yet.
- `ActionSheet` and `actionSheet(isPresented:content:)` / `actionSheet(item:content:)` map deprecated SwiftUI action sheets onto the retained bottom-dialog presentation path. `ActionSheet.Button` supports default, cancel, and destructive roles; button actions run before clearing the Boolean or item binding. Native platform action-sheet chrome and keyboard default/cancel routing are not modeled yet.
- `confirmationDialog(_:isPresented:titleVisibility:actions:message:)` and `confirmationDialog(_:isPresented:presenting:titleVisibility:actions:message:)` compose retained bottom-aligned modal dialog panels above the modified view. Dialog content gets `EnvironmentValues.isPresented` and `dismiss`; empty action builders receive a default retained `Cancel` button that clears the Boolean binding. Platform-native action sheet chrome, keyboard default/cancel routing, and automatic dismissal of arbitrary builder-supplied buttons are not modeled yet.
- `navigationViewStyle(_:)` and `EnvironmentValues.navigationViewStyle` accept `.automatic`, `.stack`, `.doubleColumn`, `.columns`, `DefaultNavigationViewStyle`, `StackNavigationViewStyle`, `DoubleColumnNavigationViewStyle`, and `ColumnsNavigationViewStyle` for deprecated `NavigationView` call sites. The retained `NavigationView` path keeps the same push/pop behavior across styles, while stack, double-column, and columns styles now resolve to distinct renderer-neutral title/container chrome. Adaptive native column behavior is still not modeled.
- `NavigationSplitView` maps two- and three-column source-compatible initializers to a retained horizontal stack. `NavigationSplitViewVisibility` bindings drive coarse retained column filtering for `.all`, `.doubleColumn`, and `.detailOnly`; adaptive platform breakpoint collapsing is not implemented yet. `navigationSplitViewStyle(_:)` and `EnvironmentValues.navigationSplitViewStyle` accept `.automatic`, `.balanced`, `.prominentDetail`, `AutomaticNavigationSplitViewStyle`, `BalancedNavigationSplitViewStyle`, and `ProminentDetailNavigationSplitViewStyle`; automatic keeps the retained horizontal column stack with lightweight separators, balanced gives visible columns equal retained priority and shell hints, and prominent-detail gives the detail column higher retained priority with a stronger detail panel hint.
- `TabView` renders retained tab chrome from `.tabItem` labels, shows the first page by default, and shows the page whose `.tag(_:)` matches the `selection:` binding. Activating a tab updates local selection state or writes through a tagged `selection:` binding. Badges applied after `.tabItem` render in the tab chrome instead of the selected page content. `tabViewStyle(_:)` and `EnvironmentValues.tabViewStyle` accept `.automatic`, `.sidebarAdaptable`, `.tabBarOnly`, `.grouped`, `.page`, `.verticalPage`, `.carousel`, and concrete supporting types including `DefaultTabViewStyle`, `SidebarAdaptableTabViewStyle`, `TabBarOnlyTabViewStyle`, `GroupedTabViewStyle`, `PageTabViewStyle`, `VerticalPageTabViewStyle`, and `CarouselTabViewStyle`; each built-in style now resolves to distinct retained tab-bar geometry (spacing, padding, corner radius) while preserving the same page-selection behavior. The *chrome* is the segmented control's, because that is the control macOS draws a tab bar with: the band is `ControlPalette.segmentedTrackFill`, the selected tab is a raised `segmentedSelectedFill` pill carrying `segmentedSelectedLabel`, and unselected tabs draw no border at all. Page and vertical-page styles now render a renderer-neutral retained page indicator when there is more than one page and `PageTabViewStyle.IndexDisplayMode` is not `.never`; `indexViewStyle(_:)`, `EnvironmentValues.indexViewStyle`, and `PageIndexViewStyle` control that indicator's retained background shell. Platform-specific overflow behavior and native tab adaptation are still minimal.
- `task(priority:_:)` launches an async Swift task when the retained node first appears and cancels it when that retained subtree disappears. `task(id:priority:_:)` accepts SwiftUI-shaped id call sites, relaunches when rebuilt with a changed id, and cancels the previous retained lifecycle task before starting the replacement.
- `refreshable(action:)` propagates `EnvironmentValues.refresh` as a SwiftUI-shaped async `RefreshAction` for descendant views. Native pull-to-refresh gestures and retained scroll chrome are not implemented yet.
- `searchable(text:placement:prompt:)` and `searchable(text:isPresented:placement:prompt:)` prepend a retained search `TextField` to the modified subtree and propagate `EnvironmentValues.isSearching` plus `EnvironmentValues.dismissSearch` to descendants. `DismissSearchAction` clears the bound text, clears the presentation binding when present, and invalidates the retained runtime. `SearchFieldPlacement` accepts `.automatic`, `.navigationBarDrawer`, `.navigationBarDrawer(displayMode:)`, `.sidebar`, and `.toolbar`; toolbar, sidebar, and navigation-drawer placements now apply distinct retained search-field chrome while preserving the same deterministic subtree insertion. `searchDictationBehavior(_:)` accepts `.automatic`, `.preventDictation`, and `.inline(activation:)` with `TextInputDictationActivation.onLook` / `.onSelect`, and stores that metadata only on retained search fields produced by `searchable`. Windows builds do not provide a dictation microphone or speech recognition path yet. Native navigation/toolbar integration, token search, scopes, and suggestions are not implemented yet.
- `contextMenu(menuItems:)` and `contextMenu(menuItems:preview:)` attach retained right-click presentation to the modified subtree. The Win32 host routes secondary-click events through `RetainedViewRuntime.contextClick(at:)`, and the menu composes a custom retained overlay panel near the click point with `EnvironmentValues.dismiss` and `isPresented` installed for menu and preview content. Retained menu item activation automatically closes the overlay after running the action. Native Win32 menu chrome, keyboard menu navigation, and exact anchor geometry for deeply nested subtrees are not modeled yet.
- `renameAction(_:)` stores a `RenameAction` in `EnvironmentValues.rename`, and `RenameButton` maps to a retained button that invokes that action when present. The button is disabled when no rename action is available. Native focus-target retargeting is not modeled yet.
- `onAppear` fires when the retained node first renders, `onDisappear` fires when an appeared retained subtree is removed or replaced, and `onChange(of:initial:_:)` keeps lightweight call-site state so rebuilt SwiftUI-shaped views can observe `Equatable` value transitions. The modern zero-argument and two-argument action overloads are supported, along with the deprecated one-argument `perform:` form.
- `onSubmit(of:_:)` hooks retained Enter key input into SwiftUI-shaped submit actions for text/search triggers on the modified retained subtree. It preserves existing non-submit key handling and invalidates after the submit action runs. `submitScope(_:)` marks a retained subtree boundary that blocks outer submit handlers while allowing handlers inside the scope to run; platform keyboard return-key labels are not modeled yet.
- `submitLabel(_:)` propagates `EnvironmentValues.submitLabel` and stores the requested return-key label on retained `TextField`, `SecureField`, and `TextEditor` nodes as renderer-neutral text-input metadata. It does not alter hardware keyboard behavior on the retained Windows input path today.
- `onHover` opts the retained node into hit testing and forwards pointer enter/exit transitions as `true`/`false`.
- `onContinuousHover(coordinateSpace:perform:)` opts the retained node into hit testing and forwards retained pointer movement as `HoverPhase.active(location)` plus `HoverPhase.ended` on pointer exit. `.local`, `.global`, and `.named(...)` coordinate-space call sites are accepted, but locations currently use retained logical coordinates.
- `onTapGesture` opts the retained node into hit testing and handles pointer tap activation. The `count:coordinateSpace:perform:` overload reports retained pointer-up locations to SwiftUI-shaped call sites. Multi-tap `count` values require consecutive inside releases and reset after an outside release; platform-native tap timing thresholds are not modeled yet.
- `onLongPressGesture` accepts the current `perform:onPressingChanged:` overloads and deprecated `pressing:perform:` overloads, opts the retained node into hit testing, and forwards retained pointer down/up/exit state. The current compatibility path treats release-inside as recognition and does not yet enforce the requested minimum duration or maximum movement threshold.
- `TapGesture`, `SpatialTapGesture`, `LongPressGesture`, `DragGesture`, `AnyGesture`, `SimultaneousGesture`, `SequenceGesture`, `ExclusiveGesture`, `GestureMask`, `CoordinateSpace`, `gesture(_:including:)`, `gesture(_:isEnabled:)`, `gesture(_:name:isEnabled:)`, `highPriorityGesture`, and `simultaneousGesture` are source-compatibility shims that route tap, long-press, and drag gesture objects through retained pointer/drag paths. `AnyGesture` type-erases another gesture while preserving the retained gesture mask. `SimultaneousGesture` and `Gesture.simultaneously(with:)` apply both retained gesture mappings to the same node; `SequenceGesture` and `Gesture.sequenced(before:)` do the same with SwiftUI-shaped sequence value metadata. `ExclusiveGesture` and `Gesture.exclusively(before:)` preserve the SwiftUI call shape and give the first retained gesture mapping precedence. The combined `Value` shapes are present for source compatibility, but combined value streaming and SwiftUI-grade gesture arbitration are not modeled yet. `SpatialTapGesture.Value` reports the retained pointer-up location for the recognized tap. `DragGesture.Value` exposes retained start location, location, translation, and matching predicted-end fallbacks, while `minimumDistance` gates change/end callbacks. `DragGesture.updating` and `LongPressGesture.updating` can drive `@GestureState` values during retained gestures. `SpatialTapGesture(count:coordinateSpace:)` and `DragGesture(minimumDistance:coordinateSpace:)` accept `.local`, `.global`, and `.named(...)` call sites, but all values currently resolve through retained logical coordinates. Named gesture overloads accept and ignore the debug name today; disabled overloads leave the retained node unchanged. Priority and simultaneous gesture composition currently share the same retained callback slots, and advanced SwiftUI gesture arbitration is not modeled yet.
- `contentShape` and `ContentShapeKinds` are accepted for source compatibility. `.interaction` content shapes now constrain retained pointer hit testing for `Rectangle`, `RoundedRectangle`, `UnevenRoundedRectangle`, `Capsule`, `Circle`, `Ellipse`, `ContainerRelativeShape`, and `AnyShape` wrappers around those retained shapes; `.hoverEffect` and `.focusEffect` shapes now provide retained visual corner geometry for hover and focus fills on both frame and GPUI scene paths. Other shape inputs fall back to rectangular interaction or rounded-rect visual geometry until renderer-neutral path clipping exists. Drag-preview, context-menu-preview, and accessibility content shapes remain retained metadata.
- `focusable(_:)` maps to the retained node focus flag and enables hit testing when focusability is turned on. Focused retained nodes now draw a renderer-neutral focus ring on both frame and GPUI scene paths unless focus effects are disabled, and `.contentShape(.focusEffect, ...)` can shape the retained ring. `@FocusState` supports Boolean and optional value bindings through `.focused(...)`; retained focus enter/exit writes the binding, and a rebuilt node with a matching binding value requests focus. `EnvironmentValues.isFocused` is readable and overrideable, but retained focus does not yet dynamically flow back into SwiftUI-shaped environment reads during a focus transition.
- `hoverEffect(_:)`, `defaultHoverEffect(_:)`, `hoverEffectDisabled(_:)`, and `focusEffectDisabled(_:)` store retained interaction-effect metadata for source-compatible call sites. `hoverEffect(_:)` also opts the node into hit testing so the runtime can identify hoverable content, and retained hover state now draws renderer-neutral highlight/lift fills on both frame and GPUI scene paths while honoring `.contentShape(.hoverEffect, ...)` visual corner geometry. `focusEffectDisabled(_:)` propagates `EnvironmentValues.isFocusEffectEnabled` to descendants and suppresses retained focus-ring rendering.
- `keyboardShortcut(_:)` stores retained shortcut metadata on the modified node and routes matching `RetainedViewRuntime.keyDown` events to that node's activation handler. SwiftUI `.command` shortcuts map to Windows Control-key shortcuts, `.option` maps to Alt, and `.defaultAction` / `.cancelAction` use Enter / Escape without modifiers. Menu command routing and platform-reserved shortcut arbitration are not modeled yet.
- `onDeleteCommand(perform:)`, `onMoveCommand(perform:)`, `onExitCommand(perform:)`, `pageCommand(value:in:step:)`, and `onPlayPauseCommand(perform:)` attach retained key-command handlers to the modified node. Delete handles Backspace and Forward Delete, move handles arrow keys with `MoveCommandDirection`, exit handles Escape before the runtime clears focus, page command handles Page Up/Page Down for `BinaryInteger` bindings while preserving values that would move outside the supplied bounds, and play/pause handles the Windows media play-pause virtual key. The modifier marks the node focusable and hit-testable, but command bubbling from focused descendants is still limited.
- `redacted(reason:)` and `unredacted()` propagate `EnvironmentValues.redactionReasons` and store retained redaction metadata on affected nodes. Placeholder redaction draws renderer-neutral rounded placeholder fills for retained text and bitmap nodes on both the frame and GPUI scene paths.
- `privacySensitive(_:)` propagates inherited privacy metadata and stores it on retained nodes. The Win32 host does not yet request OS-level capture exclusion or automatic redaction for privacy-sensitive surfaces.
- Accessibility preference/state environment values for assistive technology state, Assistive Access, flashing-light reduction, differentiating without color, inverting colors, large content viewer, animated-image playback, head-anchor alternatives, quick actions, bright-effect reduction, motion reduction, transparency reduction, showing button shapes, showing borders, Switch Control, and VoiceOver can be read with `@Environment` and overridden with `.environment`. `accessibilityPlayAnimatedImages` defaults to `true`; the other accessibility booleans default to `false`. `accessibilityReduceMotion` suppresses retained `.animation(...)` state creation for affected subtrees; the other values are compatibility metadata until the retained control, accessibility, and rendering layers consume them visually or subscribe to Windows system settings.
- `Image(systemName:)` maps known SF Symbol names into the project icon set.
- `Image(_:bundle:label:)`, `Image(_:variableValue:bundle:)`, `Image(_:variableValue:bundle:label:)`, `Image(decorative:bundle:)`, `Image(decorative:variableValue:bundle:)`, `Image(systemName:label:)`, `Image(systemName:variableValue:)`, `Image(systemName:variableValue:label:)`, `Image.renderingMode(_:)`, `Image.interpolation(_:)`, `Image.antialiased(_:)`, and `resizable(capInsets:resizingMode:)` are accepted for source compatibility and reuse the same retained bitmap/icon rendering paths. Image labels and decorative flags map to retained accessibility metadata; `.renderingMode(.template)` tints retained bitmap images with the image or inherited foreground color while `.original` keeps decoded pixels. Variable symbol values, interpolation quality, antialiasing preference, resizing mode, and cap insets are stored on retained image/icon nodes as API-shape compatibility metadata until variable SF Symbol rendering, sampler selection, antialiasing behavior, and tile/nine-slice image rendering exist.
- `Image(systemName:)` currently resolves to retained icon labels that render through the scene glyph atlas or the frame fallback text path.
- `Image(_:)` resolves direct file paths or bundle resources through the WIC-backed image loader and maps decoded bitmaps onto retained bitmap nodes that emit `DrawBitmapCommand`/`ImagePrimitive` resources. PNG/JPEG/BMP resources are supported through WIC; asset-catalog lookup is not implemented yet.
- `ImageResource(name:bundle:)` is accepted as a lightweight generated-asset compatibility value. `Image(ImageResource)` and image-resource label/control overloads resolve through the same retained bitmap loading path as named images. `ColorResource(name:bundle:)`, `Color(ColorResource)`, and `Color(_:bundle:)` are accepted for generated color asset source compatibility; hex-like resource names such as `#336699`, `#33669980`, `0xF80`, and `0F08` resolve to retained colors, while ordinary asset names still use the deterministic retained fallback `Color.accentColor` until asset-catalog color lookup exists. `Image.resizable`, image `aspectRatio`, `scaledToFit`, and `scaledToFill` map system icon glyphs and decoded bitmap images to retained preferred sizes based on font size or native bitmap size, image scale, and aspect ratio. Generic view `aspectRatio`, `scaledToFit`, and `scaledToFill` wrap retained content with a preferred-size container derived from the child intrinsic size. `resizingMode` and `capInsets` are retained as compatibility metadata; real tile and nine-slice rendering are not implemented yet.
- `Color.RGBColorSpace` accepts `.sRGB`, `.sRGBLinear`, and `.displayP3` for SwiftUI source compatibility. `.sRGBLinear` component initializers convert linear channels into retained display sRGB values, while `.displayP3` currently preserves numeric components without platform color-management conversion because the shared retained `Color` type is renderer-neutral RGBA.
- `LabeledContent` maps title/value, `value:format:`, and builder-label forms to a retained horizontal row with secondary leading label text and trailing content, matching common settings and form call sites without adding native control dependencies. `labeledContentStyle(_:)`, `EnvironmentValues.labeledContentStyle`, `LabeledContentStyle.automatic`, and `AutomaticLabeledContentStyle` are accepted as source-compatible metadata; retained rendering still uses the same label/value row chrome.
- `ToolbarItem`, `ToolbarItemGroup`, and `toolbar(content:)` / `toolbar(id:content:)` accept common SwiftUI-shaped command definitions and compose them into a retained compact command row above the modified content. Toolbar item placements now feed deterministic retained command ordering: leading/navigation items render first, principal/status items render centrally, primary and trailing actions follow, and bottom/tab/keyboard/window toolbar placements keep stable fallback ordering after main actions. `toolbar(_:for:)`, `toolbarBackground(_:for:)`, and `toolbarColorScheme(_:for:)` now scope retained row changes to rows whose item placements match the requested bars, with `.navigationBar` covering common top/navigation placements such as `.primaryAction`, `.principal`, and navigation-bar leading/trailing items. `toolbar(_:for:)` maps `.hidden` and `.visible` onto retained toolbar row visibility, while `.automatic` leaves the row unchanged. Color, optional-color, foreground-style, and gradient `toolbarBackground(_:for:)` overloads style matching retained toolbar rows, and `toolbarBackground(.hidden, for:)` clears matching retained toolbar row backgrounds. `toolbarColorScheme(_:for:)` applies deterministic retained light/dark foreground and border treatments while preserving explicit gradient backgrounds, `toolbarRole(_:)` maps navigation-stack/editor/browser roles to retained row chrome, and `toolbarTitleDisplayMode(_:)` maps inline/inline-large/large modes to retained row padding. The legacy `navigationBarItems(leading:)`, `navigationBarItems(trailing:)`, and `navigationBarItems(leading:trailing:)` modifiers bridge into the same retained toolbar row with navigation-bar-leading/trailing placements for source compatibility. WinSwiftUI does not yet route toolbar placements into native window chrome, separate navigation bars, bottom bars, placement-specific styling, or user-customizable toolbar slots.
- `Link` maps title and builder labels onto a retained plain button. Activation calls `EnvironmentValues.openURL`, whose default action asks the Windows shell to open the destination URL; tests and apps can inject an `OpenURLAction` through `.environment(\.openURL, ...)`.
- `ContentUnavailableView` maps placeholder label, description, and action builders to retained centered vertical chrome. The title/named-image, title/system-image, and search convenience forms reuse retained `Label` / text / button composition; platform-specific empty-state styling is intentionally minimal.
- `ViewThatFits(in:_:)` chooses the first retained child whose intrinsic size fits the current build context canvas along the requested axes, then falls back to the last child when none fit. It does not yet perform SwiftUI-style proposal probing through nested layout.
- Custom `ViewModifier` types work through `modifier(_:)` and rebuild their body into the retained component pipeline. `Optional` values whose wrapped type is a `View` are accepted as views: `.some` renders the wrapped view and forwards common metadata such as tags and tab items, while `.none` renders an `EmptyView`. `EquatableView` and `.equatable()` are accepted for source compatibility and render their wrapped content; retained diffing does not yet skip body rebuilds based on `Equatable` comparison. The compatibility wrapper preserves common metadata such as tags and tab items from the modified content, but advanced SwiftUI modifier identity and transaction semantics are not modeled yet.
- `listStyle(_:)` stores a SwiftUI-shaped `ListStyle` in `EnvironmentValues` and maps `automatic`, `bordered`, `carousel`, `elliptical`, `plain`, `grouped`, `inset`, `insetGrouped`, and `sidebar` styles to retained scroll-panel spacing, padding, and chrome. Concrete supporting types including `DefaultListStyle`, `BorderedListStyle`, `CarouselListStyle`, `EllipticalListStyle`, `PlainListStyle`, `GroupedListStyle`, `InsetListStyle`, `InsetGroupedListStyle`, and `SidebarListStyle` are accepted for source compatibility; `.inset` is a *body* style: rows stand on the appearance's `textBackgroundColor` card, closed with `MacOSControlMetrics.List.insetCornerRadius` and a separator hairline, and are inset into it by `List.contentInset` horizontally and `List.insetVerticalInset` vertically. `InsetListStyle(alternatesRowBackgrounds:)` preserves the alternation flag and applies retained alternating row backgrounds when enabled; stripes and row rules are alternatives, as they are in AppKit, so a striped inset table does not also rule between its rows. It is a compatibility value, not SwiftUI's protocol-based custom list style system.
- `Rectangle`, `RoundedRectangle`, `UnevenRoundedRectangle`, `Capsule`, `Circle`, `Ellipse`, `ContainerRelativeShape`, `AnyShape` wrappers around retained shapes, and `InsetShape` wrappers map to retained fill/border/corner-radius nodes; `fill` uses explicit colors, generic `ShapeStyle` values, or the inherited foreground style, and accepts SwiftUI's `FillStyle` label while preserving even-odd/antialiasing metadata on the retained primitive node for future path-aware fill handling. `stroke` and `strokeBorder` accept `Color`, stored `ForegroundStyle`, generic `ShapeStyle`, `LinearGradient`, `StrokeStyle`, and line-width-only overloads such as `stroke(lineWidth:)` / `strokeBorder(lineWidth:)`. Linear-gradient stroke and border styles are retained on the border and render through renderer-neutral gradient fill quads/rect commands. `RoundedRectangle(cornerSize:style:)` exposes SwiftUI's corner-size initializer and public `cornerSize` / `style` properties; non-square corner sizes currently retain the largest supplied corner dimension as the uniform rounded-rectangle fallback. `StrokeStyle.lineWidth` maps to retained border width, and dash patterns plus dash phase render as segmented renderer-neutral fill quads/rect commands for square retained borders. Dashed square borders also honor butt, square, and round line caps by adjusting segment geometry and corner radius. Rounded borders still render through the solid rounded-rect fallback, while joins and miter limits remain retained metadata until renderer-neutral path stroking is wired into the GPUI scene path. Rounded corner styles currently share the same retained rounded-rect path.
- `Divider()` maps to a retained separator node and picks a horizontal or vertical preferred size from the inherited stack axis. The node is marked `isSeparatorRule`, which is how a container that rules between its own children (a `List`, a grouped `Form` section) knows one of them is already a rule and leaves it alone instead of drawing a second line beside it.
- A grouped `Form` section rules between every pair of rows on its own, the way macOS System Settings does; apps do not write those `Divider`s. The rule sits in the middle of the row gap and costs it no height, at any backing scale (docs/MacOSDesignParity.md).
- `ForEach` expands into builder children instead of adding an extra layout wrapper, and generated children receive stable retained node tags derived from the SwiftUI-style id plus a retained dynamic-content index. `Range<Int>` and `ClosedRange<Int>` support the SwiftUI-style shorthand initializer. Binding-backed mutable collections, including `ForEach($items)` for identifiable elements and `ForEach($items, id: \.key)`, pass retained `Binding<Element>` rows into the content builder so controls can mutate collection elements in place. `DynamicViewContent`, `ForEach.onDelete(perform:)`, `ForEach.onMove(perform:)`, `ForEach.onInsert(of:perform:)`, the deprecated string-identifier `onInsert` overload, and `ForEach.dropDestination(for:action:)` are accepted for source-compatible list editing code; retained rows store the source-relative edit/drop actions, insert content type identifiers, and drop payload type metadata, but WinSwiftUI does not yet draw delete/reorder/drop affordances or mutate collections automatically. `itemProvider(_:)`, `onDrag`, `draggable(_:)`, and the current container-aware `draggable` overloads retain drag-source provider/payload factories, payload type names, container item ids, namespace ids, and preview intent on the modified node. View-level `onDrop(of:isTargeted:perform:)`, `onDrop(of:delegate:)`, the deprecated `dropDestination(for:action:isTargeted:)`, and current `dropDestination(for:isEnabled:action:)` retain accepted content type identifiers, payload type metadata, target state hooks, provider/payload drop closures, and delegate lifecycle callbacks. `dropConfiguration(_:)`, `dropPreviewsFormation(_:)`, and `springLoadingBehavior(_:)` retain drop operation configuration factories, preview formation metadata, and spring-loading behavior metadata. Drag start and retained drop callback invocation evaluate those factories so the runtime can participate in drag-source/drop-target hit testing, but native Windows drag sessions, cross-process item-provider serialization, hover-driven drop targeting, spring-loaded activation, and rendered custom drag previews are not wired yet. `UTType`, `NSItemProvider`, `Transferable`, `DropInfo`, `DropDelegate`, `DropProposal`, `DropOperation`, `DropSession`, `DropConfiguration`, `DragDropPreviewsFormation`, and `SpringLoadingBehavior` are lightweight compatibility shims for these call sites rather than full UniformTypeIdentifiers/Foundation/CoreTransferable implementations; `String`, `URL`, and `Data` conform to the shim `Transferable`.
- `VStack`, `HStack`, `LazyVStack`, and `LazyHStack` accept SwiftUI-style optional spacing; `nil` resolves to `MacOSControlMetrics.Layout.defaultStackSpacing` (8pt, macOS's default adjacent-view spacing), and `spacing: 0` stays an explicit choice. Lazy grids use the same default. `Spacer(minLength:)` maps to a retained flexible panel that is *greedy* along the inherited stack axis (`layoutFillAxes`) and applies its minimum only along that axis, matching SwiftUI's main-axis spacer behavior in stacks. Greed travels: a stack holding a spacer along its own axis takes the width (or height) it is proposed rather than the extent of its content, which is what makes `HStack { Text; Spacer; Button }.frame(height:)` span its container. The chain stops at any ancestor that pins its own extent on that axis, so a `.frame(width:)` around a spacer row still measures at the author's width. `HStackLayout`, `VStackLayout`, `ZStackLayout`, and `AnyLayout` accept common SwiftUI layout-switching call sites and map back to the retained stack or absolute z-stack adapters; `ViewSpacing` and `LayoutProperties` are lightweight compatibility values for custom-layout source. `AlignmentID`, `HorizontalAlignment(_:)`, `VerticalAlignment(_:)`, and `alignmentGuide(_:computeValue:)` accept built-in and custom guide call sites, evaluate closures against lightweight retained `ViewDimensions`, store the resulting guide metadata on the node, and retained stacks consume matching cross-axis custom guide values for placement. `LayoutValueKey` and `layoutValue(key:value:)` store type-erased retained layout metadata on modified nodes for future custom-layout consumption. `ContainerValueKey`, `ContainerValues`, and `containerValue(_:_:)` accept SwiftUI's key-path based container-value call sites and store type-erased retained container metadata on modified nodes; `.tag(_:)` also records retained container tag metadata for `ContainerValues.tag(for:)` and `hasTag(_:)`. Direct-subview `SubviewsCollection` consumption is not modeled yet. `VerticalAlignment.firstTextBaseline` and `.lastTextBaseline` are accepted for `HStack`, `LazyHStack`, `GridRow`, `ViewDimensions`, and alignment-guide calls, using a deterministic retained baseline approximation until text-system-owned baseline metrics are available. Lazy stacks map to the same retained stack panels as eager stacks, but with `ViewLayoutMode.lazyStack`: rows the scroll viewport plus a full viewport of overscan cannot reach are still measured and placed — a stack cannot know where row 900 goes without knowing how tall rows 0…899 are — but their subtrees are not laid out recursively, and they project to accessibility as flagged placeholders carrying their real bounds rather than a subtree of zero-size rectangles. A lazy stack with nothing scrollable above it behaves exactly like an eager one. Two costs stay: row *construction* is not deferred (every row's node is built and measured — `ForEach` materializes one `AnyView` per element inside its own initializer and `ViewBuilder` flattens it into the enclosing block, so no closure survives for the runtime to call lazily), and `onLayout` does not fire for a deferred row. See `docs/GPURenderingPipeline.md`, "Virtualization: `.lazyStack`", including "Why lazy construction needs an API" and why `List` does not adopt it yet. `pinnedViews` retains section header/footer intent by marking matching `Section` header/footer nodes for deferred painting so they layer above section body content; true sticky scroll-position geometry is not implemented yet.
- `Grid` and `GridRow` map to retained vertical and horizontal stack panels. `Grid` accepts SwiftUI-shaped alignment and spacing parameters, with vertical spacing, horizontal row spacing, and row alignment mapped today. `gridCellColumns(_:)` maps to retained horizontal growth priority so simple spanning call sites can claim more row space, while `gridCellAnchor(_:)`, `gridCellUnsizedAxes(_:)`, and `gridColumnAlignment(_:)` store retained grid-cell metadata for source-compatible call sites. Full SwiftUI column sizing, spanning, unsized-axis, and grid-cell alignment semantics are not implemented yet.
- `Button` maps into retained button controls and preserves focus/press/activate animation state.
- `Button` now also resolves hover-aware border and shadow states so retained controls feel closer to modern desktop/mobile system chrome.
- `Button(_:image:...)` and `Button(_:systemImage:...)` map into the existing retained button path with a `Label`; `.buttonStyle` propagates through `ViewBuildContext`, with `.automatic`, `.accessoryBar`, `.accessoryBarAction`, `.bordered`, and `.card` mapping to the default retained button chrome, `.borderedProminent` mapping to tint-filled retained chrome, and `.plain`, `.borderless`, and `.link` mapping to plain chrome. Concrete supporting types including `DefaultButtonStyle`, `AccessoryBarButtonStyle`, `AccessoryBarActionButtonStyle`, `PlainButtonStyle`, `BorderedButtonStyle`, `BorderedProminentButtonStyle`, `BorderlessButtonStyle`, `CardButtonStyle`, and `LinkButtonStyle` are accepted for source compatibility.
- `Toggle` maps into the retained switch control and writes through a SwiftUI-shaped `Binding<Bool>`. Image and system-image initializers reuse retained `Label` composition for source-compatible icon labels. Collection-backed `sources:isOn:` overloads derive their displayed state from whether all source bindings are `true` and write activations back to every source binding; mixed-state visual chrome is not modeled yet.
- `Picker` maps tagged child content into a retained segmented selection group by default and writes through a SwiftUI-shaped `Binding` when an option activates. `.tag(_:)` supplies the SwiftUI-style selection value; untagged options fall back to integer indices for `Binding<Int>` pickers. Builder-label `currentValueLabel` overloads compose a retained header row above the picker. `.pickerStyle(.menu)`, `MenuPickerStyle`, and deprecated `PopUpButtonPickerStyle` map the same tagged options into the retained dropdown control using the first retained text node as the option title. `.pickerStyle(.inline)` and `InlinePickerStyle` map options into retained vertical inline rows with selected checkmark chrome. `.pickerStyle(.navigationLink)` and `NavigationLinkPickerStyle` map the selected option into a retained disclosure-style row backed by the same option-selection popup mechanics. `.pickerStyle(.radioGroup)` and `RadioGroupPickerStyle` map options into a retained vertical radio-button group. `.pickerStyle(.wheel)` and `WheelPickerStyle` map options into retained vertical wheel rows using `defaultWheelPickerItemHeight(_:)`. `.pickerStyle(.palette)` and `PalettePickerStyle` map options into a compact retained palette row. `.automatic`, `.segmented`, and their concrete built-in style structs currently share retained segmented chrome until additional picker-specific retained renderers are added.
- `Stepper` maps to a retained horizontal stack with label content and two retained buttons that mutate `Binding<Int>`, `Binding<Double>`, or generic `Strideable` values while clamping writes to the supplied range and reporting `onEditingChanged` around retained button activation.
- `Slider(value:in:)` maps into the retained draggable slider and writes through SwiftUI-shaped `Binding<Double>` or generic `BinaryFloatingPoint` bindings. The `step` initializer snaps written values relative to the lower bound and reports drag editing state through the retained control lifecycle. Current SwiftUI builder-label overloads, plus minimum, maximum, and main label overloads, wrap the retained slider in small retained stacks while preserving the same binding/editing behavior.
- `ProgressView(value:total:)` maps into retained progress chrome for `Double` and generic `BinaryFloatingPoint` values; title, builder-label, and current-value label overloads wrap that retained indicator in small retained stacks. `ProgressView(timerInterval:countsDown:)` overloads compute retained progress from the current `Date` at build time and accept custom label/current-value label builders; automatic ticking updates and SwiftUI's default date-progress label text are not modeled yet. `progressViewStyle(_:)` and `EnvironmentValues.progressViewStyle` accept `.automatic`, `.linear`, `.circular`, `DefaultProgressViewStyle`, `LinearProgressViewStyle`, and `CircularProgressViewStyle`; `.automatic` and `.linear` use the retained progress bar, while `.circular` composes a renderer-neutral retained circular segment indicator.
- `Gauge(value:in:)` maps SwiftUI-shaped scalar gauges onto retained gauge chrome. BinaryFloatingPoint values and ranges are converted into the retained `Double` progress path. Title, current-value, minimum-value, maximum-value, and marked-value label builders compose retained label chrome around the same renderer-neutral fill primitive, with `.tint` driving the filled segment. Marked value labels render as a retained caption row below the gauge. `gaugeStyle(_:)` and `EnvironmentValues.gaugeStyle` accept common built-in style values and concrete supporting types including `DefaultGaugeStyle`, `LinearGaugeStyle`, `LinearCapacityGaugeStyle`, `AccessoryLinearGaugeStyle`, `AccessoryLinearCapacityGaugeStyle`, `CircularGaugeStyle`, `AccessoryCircularGaugeStyle`, and `AccessoryCircularCapacityGaugeStyle`; automatic and linear styles use the retained progress bar, while circular and accessory circular styles use retained circular segment chrome.
- Accessibility modifiers store retained metadata on `ViewNode` (`label`, `value`, `hint`, `identifier`, hidden state, traits, child behavior, sort priority, and actions) so the tree has stable semantic data. `accessibilityAddTraits(_:)` and `accessibilityRemoveTraits(_:)` retain common SwiftUI-shaped `AccessibilityTraits` such as button, header, selected, image, link, search-field, keyboard-key, static-text, summary, media, direct-interaction, page-turn, and modal intent. `accessibilityElement(children:)` retains `.ignore`, `.combine`, and `.contain` grouping intent, and `accessibilitySortPriority(_:)` stores deterministic ordering metadata for future UI Automation projection. `accessibilityAction(...)` accepts default, kind-based, and named action closures and stores them on the retained node for future accessibility invocation. `help(_:)` maps to the same retained hint metadata for desktop shared-source compatibility. The retained tree is projected to native Windows UI Automation (`WM_GETOBJECT` fragment tree via `CUIAInterop` + `UIAProviderBridge`): traits map to UIA control types, bounds track layout after resize, stored default actions are invokable through InvokePattern, and focus/structure events are raised. Advanced patterns (Value/Text/Selection/Toggle), live regions, and fine-grained structure-changed events are not implemented.
- `cornerRadius(_:antialiased:)` maps to a retained rounded rectangular clipping wrapper and stores the antialiasing choice as retained clip metadata. The current retained renderer does not visually distinguish antialiased and non-antialiased clips.
- `clipped(antialiased:)` maps to retained rectangular bounds clipping and stores the antialiasing choice as retained clip metadata. The current retained renderer does not visually distinguish antialiased and non-antialiased clips. A frame boundary alone does not clip, matching SwiftUI: content inside a view collapsed to zero width or height still paints (both paint paths), and `clipped()` is what hides it. The collapsed view paints none of its own decoration, and hit testing still prunes a zero-extent subtree.
- `ContainerRelativeShape` maps to the retained dynamic rounded shape path used by capsule-style shape fallbacks. It supports the same color, foreground-style, gradient, stroke, and stroke-border overloads as the other retained basic shapes, and participates in `clipShape` / `contentShape` as a dynamic rounded retained shape. It does not yet derive a parent container's precise SwiftUI shape style.
- `UnevenRoundedRectangle` accepts `RectangleCornerRadii` and per-corner radius initializers for SwiftUI-shaped call sites. The current retained renderer stores the largest supplied corner radius as a uniform rounded-rectangle fallback until renderer-neutral per-corner rounded rect primitives are added.
- `AnyShape` type-erases retained shape values for source-compatible conditional shape call sites. It preserves retained clip and content-shape geometry from wrapped basic shapes, delegates direct rendering to the wrapped shape when no erased fill/stroke override is applied, and applies erased fill/stroke overrides through the current retained rectangle/rounded/capsule fallback paths.
- `InsettableShape` and `InsetShape` support `inset(by:)` on retained basic shapes. The current compatibility path wraps the rendered shape in retained padding, accumulates nested insets, and reduces retained rounded-rectangle radii by the inset amount; it does not yet provide path-level inset geometry for arbitrary custom shapes.
- SwiftUI's standard `Shape` factories are available for retained built-in shapes, including `.rect`, `.rect(cornerRadius:style:)`, `.rect(cornerSize:style:)`, uneven `.rect(...)`, `.capsule`, `.capsule(style:)`, `.circle`, `.ellipse`, and `.containerRelative`, so leading-dot shape arguments such as `.clipShape(.rect(cornerRadius: 8))` compile against WinSwiftUI.
- `clipShape(_:style:)` maps `Rectangle`, `RoundedRectangle`, `UnevenRoundedRectangle`, `Capsule`, `Circle`, `Ellipse`, `ContainerRelativeShape`, and `AnyShape` wrappers around those retained shapes to retained bounds clipping with matching retained corner-radius behavior, and preserves `FillStyle` even-odd plus antialiasing metadata for future renderer-neutral path clipping. Other `Shape` conformers currently degrade to rectangular clipping until renderer-neutral path clipping grows beyond the existing render graph fallback.
- `mask(alignment:_:)` accepts SwiftUI-shaped view-builder mask content, stores retained mask alignment metadata, and keeps the mask source as a non-rendered retained child for future alpha-mask rendering. Current renderers do not apply the mask visually yet.
- `border` maps to retained panel border fields. Stored `ForegroundStyle.color` values map directly, and stored or direct `LinearGradient` inputs retain the gradient for renderer-neutral border fill commands.
- `opacity(_:)` and `hidden(_:)` map directly onto retained node paint and visibility state. `BlendMode` accepts SwiftUI-shaped blend cases and `blendMode(_:)` stores renderer-neutral retained blend metadata. `compositingGroup()` and `drawingGroup(opaque:colorMode:)` retain offscreen-compositing intent and `ColorRenderingMode` metadata for source compatibility. The mode is lowered onto `QuadPrimitive.blendMode` and onto the `RenderFrame` commands, and carried through `GPUISceneBridge` when a frame is converted to a scene, but **no backend interprets it, on either path**: the HLSL declares the field and never reads it against a fixed `ONE / INV_SRC_ALPHA` blend state, the fallback `D3D11Renderer` owns exactly one blend state and no way to select another, and the CPU rasterizer composites source-over to match (`CPUGPUBlendModeContractTests` gates the scene path, the frame path, and the fact that the field survives both). So swapping presenters cannot change how `.blendMode(.multiply)` looks. Honouring the separable modes means splitting quad batches and swapping `ID3D11BlendState` — multiply, screen and plusLighter are expressible as fixed-function states, overlay is not. Retained drawing groups still paint normally until render-to-texture/offscreen group compositing is implemented.
- `brightness(_:)`, `contrast(_:)`, `colorInvert()`, `colorMultiply(_:)`, `saturation(_:)`, `grayscale(_:)`, `hueRotation(_:)`, and `luminanceToAlpha()` store ordered retained color-effect metadata for source compatibility and cache invalidation. `Shader`, `ShaderFunction`, and `ShaderLibrary` provide lightweight dynamic-member compatibility for `ShaderLibrary.default.someShader(...)` call sites, and `colorEffect(_:isEnabled:)`, `distortionEffect(_:maxSampleOffset:isEnabled:)`, and `layerEffect(_:maxSampleOffset:isEnabled:)` store retained shader-effect metadata on views. The current renderers do not compile or apply shader/filter effects visually yet; backend shader/filter work is still required.
- `zIndex(_:)`, `offset`, `scaleEffect`, anchor-aware scale overloads, `flipsForRightToLeftLayoutDirection(_:)`, `rotationEffect`, anchor-aware rotation overloads, `transformEffect(_:)`, and `projectionEffect(_:)` map directly onto retained node ordering and `Transform2D` state. A node's transform composes *after* its ancestors' (the transform is built around the node's screen-space centre), and the painter lowers a rotation onto `QuadPrimitive.rotationRadians` rather than to a bounding box — so a rotated card's background, border and outline draw rotated on both backends. Three deliberate residuals: shears, mirrors and non-uniform scales degrade to the axis-aligned bounding box, because the quad encoding carries an angle and not a matrix — a mirror is nonetheless a mirror in the transform algebra (`Transform2D` carries a reflection through its decomposition as a negative scale), so a mirrored subtree's descendants and the pointer inverse mirror with it even though its content is drawn unmirrored; text and images inside a rotated subtree stay upright, because `GlyphPrimitive` and `ImagePrimitive` have no rotation field — and neither do `ShadowPrimitive` or `PathPrimitive`, so shadows (`scene.addShadow`), `backgroundPath` fills/strokes and `Canvas` path content likewise paint axis-aligned into the rotated frame's bounding box; and a rotated `.clipped()` container clips to the bounding box of its rotated frame. See `docs/GPURenderingPipeline.md` §2b and "Residual: a rotated clip is still an AABB". `CGAffineTransform` and `ProjectionTransform` are lightweight compatibility values backed by the retained affine transform path. `UnitPoint3D`, `RotationAxis3D`, `Rotation3D`, `AffineTransform3D`, `rotation3DEffect(...)`, `perspectiveRotationEffect(...)`, and `transform3DEffect(_:)` accept modern SwiftUI-shaped 3D call sites; retained rendering maps z-axis rotation to the existing 2D transform and stores full 3D transforms as metadata until a renderer-neutral 3D transform contract exists.
- `@Namespace` creates stable SwiftUI-shaped namespace IDs, and `matchedGeometryEffect(id:in:properties:anchor:isSource:)` records retained metadata on the node. WinSwiftUI does not yet interpolate geometry across matched source/destination pairs, but the metadata is available to the retained runtime for future animation work.
- `blur(radius:opaque:)` maps onto `ViewNode.contentBlurRadius` — the subtree's *content* blur, distinct from the node's own backdrop effect (`blurRadius`, what a Material sets) — and preserves SwiftUI's opaque-output hint as renderer-neutral metadata. The painter resolves it as an isolated offscreen pass: the subtree renders into its own buffer, is blurred there, and is composited back, so a `.blur()` changes the pixels of the view it is on and no others, and every kind of content inside it (text, images, borders, paths, pinned headers) is blurred rather than only background quads. See `docs/GPURenderingPipeline.md`, "Content blur vs backdrop blur", for the cost model, the bitmap cache and the two residuals (a blurred scroll view's *own* indicator stays sharp — an indicator belonging to a scroll view nested inside the subtree is claimed and blurred with it; a subtree past the offscreen area budget degrades to a hard-edged backdrop blur). The frame path has no blur primitive and still degrades to sharp content.
- `transition(_:)` accepts common `AnyTransition` values such as `.identity`, `.opacity`, `.move(edge:)`, `.offset(...)`, `.push(from:)`, `.scale`, `.slide`, `.asymmetric(...)`, and `.combined(with:)` for source compatibility. Retained insertion/removal animation semantics are not modeled yet, so the modifier currently preserves the rendered subtree unchanged.
- `contentTransition(_:)`, `EnvironmentValues.contentTransition`, and `EnvironmentValues.contentTransitionAddsDrawingGroup` accept SwiftUI-shaped content transition metadata including `.identity`, `.interpolate`, `.opacity`, `.numericText(...)`, and `.symbolEffect`. Retained content-change interpolation is not modeled yet, so this currently propagates source-compatible environment metadata without changing rendered nodes.
- `SymbolEffect`, `SymbolEffectOptions`, `symbolEffect(...)`, `symbolEffectsRemoved(_:)`, and `ContentTransition.symbolEffect(...)` accept common SF Symbols effect call sites such as `.pulse`, `.bounce`, `.variableColor.reversing`, `.replace`, `.repeat(...)`, `.repeating`, and `.speed(...)`. WinSwiftUI currently preserves source compatibility and rendered symbol/text content; it does not yet animate SF Symbol layers on the retained renderer.
- `SensoryFeedback` accepts SwiftUI-shaped haptic/audio feedback values and `sensoryFeedback(...)` trigger modifiers for source compatibility. Windows retained rendering does not currently play haptics or audio feedback, so these modifiers preserve the rendered subtree unchanged.
- `animation(_:)` and `animation(_:value:)` attach retained animation state for properties the runtime can interpolate today, currently focused on opacity and background color. `PhaseAnimator`, `phaseAnimator(_:content:animation:)`, and `phaseAnimator(_:trigger:content:animation:)` accept SwiftUI-shaped phased animation call sites with `PlaceholderContentView` for the modifier form, render the initial phase through the supplied content closure, and retain phase, trigger, and animation metadata on the node. WinSwiftUI does not yet schedule continuous phase cycling or trigger-driven phase advancement. `withAnimation`, including the completion overload, `AnimationCompletionCriteria`, `Transaction`, including `isContinuous`, `scrollTargetAnchor`, `tracksVelocity`, and immediate completion callbacks, `withTransaction`, including the key-path/value overload, and `transaction(_:)` accept SwiftUI-shaped call sites and execute their body/transform closures, but transaction propagation is not yet modeled by the retained runtime.
- `disabled(_:)` propagates an inherited enabled-state environment through `ViewBuildContext`, and retained controls consume that state while they are built.
- `scrollDisabled(_:)` propagates `EnvironmentValues.isScrollEnabled`; retained `ScrollView`, `List`, and scrolling `Section` nodes keep their layout and clipping but remove their scroll axis and indicators when disabled.
- `scrollClipDisabled(_:)` maps to retained scroll container bounds clipping for `ScrollView`, `List`, and scrolling `Section` nodes. Non-scroll `Section` panels keep their rounded clipping.
- `scrollContentBackground(_:)` accepts SwiftUI `Visibility` values. `.hidden` clears retained scroll-container background chrome for `ScrollView` and scrolling `Section` nodes; `.automatic` and `.visible` preserve the current retained style background. Non-scroll `Section` panels keep their normal background.
- `scrollIndicators(_:axes:)` propagates horizontal and vertical `ScrollIndicatorVisibility` environment values. `.hidden` and `.never` suppress retained indicators for matching axes, while `.automatic` and `.visible` keep the current retained indicator behavior.
- `scrollIndicatorsFlash(onAppear:)` and `scrollIndicatorsFlash(trigger:)` store inherited retained flash metadata on `ScrollView`, `List`, and scrolling `Section` nodes. The current runtime records the on-appear Boolean and trigger identity for source compatibility; it does not yet schedule timed indicator flash animation.
- `scrollPosition(_:,anchor:)` and `scrollPosition(id:anchor:)` accept SwiftUI-shaped `Binding<ScrollPosition>` and ID bindings, then store semantic position metadata on retained `ScrollView`, `List`, and scrolling `Section` nodes. `ScrollPosition` supports ID, edge, point, x, and y construction plus `scrollTo(...)` mutations for shared-source code; retained runtime updates and programmatic scrolling are not wired yet.
- `onScrollGeometryChange(for:of:action:)`, `onScrollPhaseChange(_:)`, `onScrollVisibilityChange(threshold:_:)`, and `onScrollTargetVisibilityChange(idType:threshold:_:)` accept SwiftUI-shaped observation closures and store retained observation metadata. `ScrollGeometry`, `ScrollPhase`, `ScrollPhaseChangeContext`, and `CGVector` are available for shared-source callback code, but the runtime does not yet dispatch scroll observation callbacks.
- `visualEffect(_:)` accepts SwiftUI-shaped `VisualEffect` closures with a retained `GeometryProxy` built from the current canvas size, then stores the resulting identity-effect metadata on the retained node for source compatibility. `visualEffect3D(_:)` mirrors that path with lightweight `GeometryProxy3D`, `Size3D`, `Rect3D`, and `AffineTransform3D` compatibility values. The runtime does not yet apply generic visual-effect metadata during rendering.
- `scrollTransition(...)` accepts symmetric and asymmetric `ScrollTransitionConfiguration` values plus SwiftUI-shaped `VisualEffect` closures. `EmptyVisualEffect` accepts color-adjustment chains such as `brightness`, `contrast`, `colorInvert`, `colorMultiply`, `saturation`, `grayscale`, `hueRotation`, and `luminanceToAlpha`, shader metadata through `colorEffect`, `distortionEffect`, and `layerEffect`, blend metadata through `blendMode(_:)`, plus `opacity`, 2D and 3D `scaleEffect`, 2D and z-axis `offset`, `blur(radius:opaque:)`, `rotationEffect(_:anchor:)`, `rotation3DEffect(...)`, `perspectiveRotationEffect(...)`, `transform3DEffect(_:)`, and affine/projection `transformEffect(...)`. The retained node stores transition configuration, axis, and identity-effect metadata for source compatibility; the runtime does not yet apply phase-driven scroll transition rendering.
- `scrollBounceBehavior(_:axes:)` propagates horizontal and vertical `ScrollBounceBehavior` environment values, defaulting to the vertical axis like SwiftUI. `.automatic`, `.always`, `.basedOnSize`, and `.never` are stored as retained metadata on `ScrollView`, `List`, and scrolling `Section` nodes; the retained runtime still clamps scroll offsets and does not model overscroll physics yet.
- `scrollTargetBehavior(_:)` accepts SwiftUI-shaped `ScrollTargetBehavior` values such as `.paging`, `.viewAligned`, and custom behavior conformers, then stores retained behavior metadata on `ScrollView`, `List`, and scrolling `Section` nodes. `scrollTargetLayout(isEnabled:)` marks the modified retained node as the layout that contributes scroll targets. The current runtime does not yet perform paging or view-aligned deceleration.
- `scrollInputBehavior(_:for:)` accepts `ScrollInputBehavior.automatic`, `.enabled`, and `.disabled` for `ScrollInputKind.handGestureShortcut`, `.look`, and `.look(axes:)`, then stores inherited per-input metadata on retained `ScrollView`, `List`, and scrolling `Section` nodes. `scrollDisabled(true)` still disables retained scrolling for all inputs; the Win32 host does not yet route platform-specific look or hand-gesture input.
- `contentMargins(_:,for:)` and `contentMargins(_:_:for:)` accept SwiftUI-shaped scalar and `EdgeInsets` content-margin placement metadata. Retained `ScrollView`, `List`, and scrolling `Section` nodes resolve `.automatic` and `.scrollContent` margins into stack padding, while `.automatic` and `.scrollIndicators` margins feed retained scroll indicator inset geometry for drawing, hit testing, and dragging.
- `defaultScrollAnchor(_:)` and `defaultScrollAnchor(_:for:)` accept SwiftUI-shaped `UnitPoint` anchors. Retained scroll containers use the initial-offset anchor to seed `scrollOffset` after layout, the size-changes anchor when their content or frame size changes, and the alignment anchor to position smaller retained scroll content within its viewport.
- `scrollDismissesKeyboard(_:)` propagates `EnvironmentValues.scrollDismissesKeyboardMode` with `.automatic`, `.immediately`, `.interactively`, and `.never` for source-compatible scroll/input code. It is metadata today because the Windows retained text input path does not host a software keyboard.
- `defaultWheelPickerItemHeight(_:)` propagates `EnvironmentValues.defaultWheelPickerItemHeight`, defaulting to `32`, and retained wheel-style pickers use it as the minimum row height.
- `ScrollView` maps into retained scroll panels with indicator state handled in the runtime. The SwiftUI-shaped `Axis.Set` / `showsIndicators:` initializer is accepted for source compatibility; the retained runtime scrolls one primary axis today, so `.all` resolves to the vertical retained path until two-axis scrolling is modeled.
- `ScrollViewReader` provides a SwiftUI-shaped `ScrollViewProxy` to its content builder and records `scrollTo(_:anchor:)` requests as retained metadata. Programmatic scrolling through the proxy is not yet connected to retained scroll offset changes.
- `List` maps to a retained vertical scroll panel, while `Form` maps to retained vertical form chrome with style-specific spacing, padding, and shell treatment. Tagged static rows and data-backed rows support single and multiple `selection:` bindings, render lightweight retained selected-row chrome, and write bindings from row activation. Binding-backed mutable collection rows, including `List($items)` for identifiable elements and `List($items, id: \.key)`, pass retained `Binding<Element>` rows into the builder so row controls can mutate collection elements in place. `formStyle(_:)` and `EnvironmentValues.formStyle` accept `.automatic`, `.columns`, `.grouped`, `AutomaticFormStyle`, `ColumnsFormStyle`, and `GroupedFormStyle`; automatic uses the default retained form stack, columns uses a denser retained column-style stack profile, and grouped uses a retained rounded panel shell. A `Form` is a *centred content column*: it builds a centring box whose only child is the styled column, capped at `MacOSControlMetrics.Form.contentMaxWidth` (640), so a settings pane sits in a macOS-width column rather than stretching edge to edge. Inside a Form the rows are a two-column grid — `LabeledContent`, `Toggle`, `Picker`, `Stepper`, `Slider`, `TextField`, `ProgressView`, `Gauge`, `ColorPicker`, and `DatePicker` build a `groupedFormRowNode` with a trailing-aligned label column and a leading value column, each section resolves one shared column width for its own rows and registers it with the enclosing `Form`, which then widens every group to the widest — one label column across the whole form, the way a macOS settings pane aligns — and label-less rows (a bare `Button`) are indented to that same value column. A grouped `Section` also moves its header outside and above its box and draws that box near-flat (`MacOSControlMetrics.GroupBox` radius and contact shadow, `ControlPalette.groupedContainerShadow`) on the panel material (`ControlPalette.raisedSurfaceFill` and `raisedSurfaceRing`). Sections outside a Form keep the list-group treatment. Row styling remains intentionally minimal, and platform edit-mode selection rules are not modeled yet.
- `headerProminence(_:)` propagates `EnvironmentValues.headerProminence`; `.increased` maps direct `Section` headers to a bolder retained header font unless the header text sets an explicit font.
- `EnvironmentValues.backgroundProminence` accepts `.standard` and `.increased` for shared-source foreground styling decisions above custom or selected backgrounds. It is readable and overrideable compatibility metadata, and retained selection-capable `List` rows derive `.increased` prominence for selected row content.
- `EnvironmentValues.defaultMinListHeaderHeight` maps to retained minimum-height constraints on direct `Section` header nodes, preserving stronger header constraints.
- `badge(_:)` accepts integer, optional string, optional localized key, and optional `Text` badges, then maps visible badges to retained trailing badge chrome. Integer `0` and `nil` optional badges preserve the base row unchanged. `badgeProminence(_:)` propagates `EnvironmentValues.badgeProminence` and maps `.decreased`, `.standard`, and `.increased` to retained badge colors.
- `listRowBackground(_:)` accepts optional retained views, colors, gradients, and stored foreground styles. Color and gradient inputs wrap the row in a retained background panel; view inputs are layered behind the row and stretched to the row bounds.
- `listItemTint(_:)` accepts optional `Color` and `ListItemTint` values including `.fixed`, `.preferred`, and `.monochrome`, stores retained list-item tint metadata, and propagates the effective tint through retained list text/label content. Platform-specific sidebar icon-only and watchOS platter semantics are not modeled yet.
- `selectionDisabled(_:)` stores retained row selection metadata and prevents affected rows in retained selectable `List` containers from receiving selection chrome or activation handlers. Parent selection disabling propagates through list rows, and explicit `selectionDisabled(false)` on a row re-enables that row.
- `deleteDisabled(_:)` and `moveDisabled(_:)` store retained edit-list metadata on rows and propagate parent disable state through direct `List` rows while allowing explicit child `false` overrides. Reorder/delete edit chrome and collection mutation affordances are still future work.
- `listRowInsets(_:)` and `listRowInsets(_:_:)` map to retained row padding wrappers. Passing `nil` preserves the row unchanged.
- `listSectionMargins(_:_:)` maps to a retained section padding wrapper for the specified edges. A `nil` length resolves to the retained default optional spacing value of `16`.
- `listSectionSpacing(_:)` accepts scalar spacing plus `ListSectionSpacing.default`, `.compact`, and `.custom(_)`. Retained `List` maps list-level section spacing onto its single inter-child stack spacing; per-section half-spacing arbitration between adjacent sections is not modeled yet.
- `listRowSpacing(_:)` maps optional row spacing to the retained `List` stack layout. Passing `nil` restores the retained default spacing of `0`.
- `EnvironmentValues.defaultMinListRowHeight` maps to retained minimum-height constraints on direct `List` rows, preserving stronger row constraints.
- `listRowSeparator(_:edges:)` stores retained row-separator visibility metadata and `VerticalEdge.Set` edge intent. `.visible` adds deterministic retained one-pixel separator panels on the requested row edges; `.automatic` and `.hidden` preserve source-compatible metadata without adding separator panels. `listRowSeparatorTint(_:edges:)` stores matching tint metadata and colors retained visible separator panels for the requested edges.
- `listSectionSeparator(_:edges:)` and `listSectionSeparatorTint(_:edges:)` mirror the retained row-separator model for section boundaries. Visible section separators wrap the section node in retained one-pixel separator panels for the requested top and bottom edges; automatic and hidden modes preserve source-compatible metadata without adding section panels.
- `DisclosureGroup` maps optional binding-backed expansion state into a retained disclosure header button plus an indented retained content stack; toggling writes through `Binding<Bool>` when supplied, otherwise uses local retained expansion state, and invalidates the host for rebuild. `disclosureGroupStyle(_:)`, `EnvironmentValues.disclosureGroupStyle`, `DisclosureGroupStyle.automatic`, and `AutomaticDisclosureGroupStyle` are accepted as source-compatible metadata; retained rendering still uses the same disclosure chrome.
- `Menu` maps to a retained menu button and custom retained popup overlay anchored below the button. Named-image and system-image label initializers reuse retained `Label` composition for bitmap or system icon labels. Menu content gets `EnvironmentValues.isPresented` and `dismiss`, and retained menu item activation automatically closes the overlay after running the action. Primary-action initializers run the primary closure on retained button activation instead of opening the overlay; secondary menu presentation gesture/chrome is not modeled yet. `menuStyle(_:)` and `EnvironmentValues.menuStyle` accept `.automatic`, `.button`, `.borderedButton`, `.borderlessButton`, `DefaultMenuStyle`, `ButtonMenuStyle`, `BorderedButtonMenuStyle`, and `BorderlessButtonMenuStyle`; bordered styles use retained button chrome, borderless styles use retained plain button chrome, and `showsMenuIndicator` controls the disclosure glyph unless an explicit `.menuIndicator(...)` modifier overrides it. Native Win32 menu chrome, keyboard menu navigation, and platform menu roles are not modeled yet.
- `ControlGroup` maps to compact retained horizontal group chrome, accepts title, named-image label, system-image label, and builder-label forms, and preserves nested control actions while applying a style-appropriate child button style to grouped buttons. `controlGroupStyle(_:)` and `EnvironmentValues.controlGroupStyle` accept `.automatic`, `.compactMenu`, `.menu`, `.navigation`, `.palette`, and the concrete supporting types `AutomaticControlGroupStyle`, `CompactMenuControlGroupStyle`, `MenuControlGroupStyle`, `NavigationControlGroupStyle`, and `PaletteControlGroupStyle`; automatic, compact-menu, menu, navigation, and palette styles now resolve to distinct retained shell spacing, padding, border, and corner profiles, with palette using bordered child buttons and tint-accented chrome.
- `TextField`, `SecureField`, and `TextEditor` map a `Binding<String>` to a retained focusable input surface with basic virtual-key text insertion, backspace, forward delete, and caret movement with left/right/home/end. `TextField` and `SecureField` provide placeholder rendering from the title, SwiftUI-style `prompt: Text?` overloads, or builder-label text when no prompt is supplied; explicit prompts take precedence over label-derived placeholder text. `TextField(value:formatter:)` overloads display values with `Formatter.string(for:)` and write parsed values back when a `NumberFormatter` or `DateFormatter` can produce the bound type; invalid edits leave the typed binding unchanged. Optional formatter-backed value bindings render `nil` as an empty field, set `nil` again when edited back to an empty string, and otherwise keep the last valid typed value on invalid edits. `TextField(value:format:)` overloads display values with `ParseableFormatStyle.format(_:)`; invalid edits leave non-optional typed bindings unchanged and set optional typed bindings to `nil`. `TextField(axis: .vertical)` maps to the retained multiline input path, `SecureField` masks the displayed value, and `TextEditor` enables multiline wrapping/newline insertion. `TextField` and `TextEditor` accept `Binding<TextSelection?>` selection overloads, store insertion, single-range, and `RangeSet` multi-selection metadata as retained text offsets, and update bound selections to insertion points while retained keyboard editing moves the caret, replaces a single selected range, or deletes that range. Highlighted selection, caret movement, shift-extend, select-all, clipboard shortcuts (Ctrl+C/X/V/A), and mouse-drag selection are implemented (secure fields block copy/cut); multi-range editing is not. Deprecated `TextField` text, formatter, and optional formatter `onEditingChanged` / `onCommit` and `SecureField` `onCommit` initializers bridge to retained focus enter/exit and Enter-key submit hooks. `textInputAutocapitalization(_:)` propagates through `EnvironmentValues` and transforms inserted retained keyboard text for `.characters`, `.words`, and `.sentences`; `textContentType(_:)` accepts lightweight `NSTextContentType` compatibility values and retains their raw semantic content hint on text-input nodes, but WinSwiftUI does not provide autofill, suggestions, or keyboard changes from the hint yet. `keyboardType(_:)` accepts SwiftUI's `UIKeyboardType` cases such as `.default`, `.emailAddress`, `.numberPad`, `.decimalPad`, `.URL`, and `.webSearch`, and stores the requested keyboard metadata on retained text-input nodes; Windows hardware input is not filtered and no software keyboard is presented. `textInputSuggestions { ... }`, data-driven `textInputSuggestions(_:content:)`, `textInputSuggestions(_:id:content:)`, and `textInputCompletion(_:)` retain display/completion pairs on text-input nodes for source-compatible suggestion call sites; WinSwiftUI does not present or activate a suggestion popup yet. `writingToolsBehavior(_:)` accepts `.automatic`, `.complete`, `.limited`, and `.disabled`, propagates through `EnvironmentValues.writingToolsBehavior`, and stores the requested behavior on retained text and text-input nodes; Windows builds do not integrate Apple Intelligence Writing Tools. `writingToolsAffordanceVisibility(_:)` accepts `.automatic`, `.visible`, and `.hidden`, propagates through `EnvironmentValues.writingToolsAffordanceVisibility`, and stores affordance visibility metadata on retained text-input nodes; no Writing Tools affordance chrome is presented on Windows yet. `autocorrectionDisabled(_:)` and deprecated `disableAutocorrection(_:)` propagate for source compatibility but have no spelling engine behind them yet. `findDisabled(_:)`, `replaceDisabled(_:)`, and `findNavigator(isPresented:)` retain find/replace gating and presentation metadata on retained text-input nodes for source-compatible `TextEditor` call sites, but WinSwiftUI does not present a find navigator yet. These controls support IME composition on Windows: WM_IME_* messages drive marked (underlined) composition text, commit, and a candidate window positioned at the caret (`TextInputIMECompositionTests`). Full desktop-grade text-editing commands are not complete.
- `DatePicker` accepts SwiftUI-shaped date, time, closed-range, and partial-range initializer labels and maps the selected `Date` into retained label/value text. It reads `EnvironmentValues.calendar` and `EnvironmentValues.timeZone` before formatting its deterministic retained value text, and non-current `EnvironmentValues.locale` overrides use `DateFormatter` for locale-specific date/time text. Retained date pickers are focusable and write the selection binding from arrow-key increments while respecting the supplied range. `datePickerStyle(_:)` and `EnvironmentValues.datePickerStyle` accept `.automatic`, `.compact`, `.field`, `.graphical`, `.stepperField`, `.wheel`, `DefaultDatePickerStyle`, `CompactDatePickerStyle`, `FieldDatePickerStyle`, `GraphicalDatePickerStyle`, `StepperFieldDatePickerStyle`, and `WheelDatePickerStyle`; automatic uses the default retained label/value row, compact uses a dropdown-style retained shell, field and stepper-field styles use bordered retained input chrome, wheel uses a clipped wheel-style retained shell, and graphical uses a retained calendar-panel hint around the formatted value. Calendar popovers, real graphical calendar/clock picking, wheel columns, editable fields, and direct text entry are not implemented yet.
- `ColorPicker` accepts SwiftUI-shaped title, builder-label, and `supportsOpacity` initializer labels, then maps the selected `Color` into a retained swatch plus hex value. Retained color pickers are focusable and provide keyboard binding writes: left/right cycle a deterministic retained color palette, and up/down adjust opacity when `supportsOpacity` is true. Native color dialogs, color wells, and direct channel text entry are not implemented yet.
- `HSplitView` and `VSplitView` map into the retained split-view control and can infer an initial ratio from content.
- `GeometryReader` reports the slot it actually occupies, resolved in two phases. It carries a node of its own — greedy on both axes (`layoutFillAxes = .both`), laying its body out absolutely — so there is always one node whose resolved frame *is* the slot; a collapsed reader would have none whenever its body pins its own extent. Phase one is the build: the proxy is seeded from the build context's canvas, which containers narrow as they consume chrome (`TabView` measures its tab band and hands the page a reduced canvas through `ViewBuildContext.withCanvasSize`). Build order cannot do better than a seed, because the reader's siblings have not been measured yet. Phase two is the runtime's: after each layout pass, `RetainedViewRuntime.resolveGeometryReaderSlots` re-invokes the body of every reader whose resolved frame differs from the size it was built against, adopts the rebuilt node onto the existing one (so the reader keeps its place, its frame, and everything the runtime hung on it) and lays out again. The loop terminates on `ViewNode.geometryReaderBuiltSize` matching the resolved slot, and is capped at four rounds so a reader under an unbounded proposal — a scroll axis, where the body's own size feeds the slot — settles instead of oscillating. Trees with no reader in them never enter the loop. This is deliberately *not* keyed on view identity: the seed is a hint and the resolved slot is the authority, so no per-identity build state is needed (`@State` still lives in the view struct — see `Known Gaps`). It reevaluates correctly after canvas-size changes. `GeometryProxy.size`, `safeAreaInsets`, `frame(in:)`, `CoordinateSpaceProtocol`, `GlobalCoordinateSpace`, `LocalCoordinateSpace`, `NamedCoordinateSpace`, and `bounds(of:)` are available for shared-source call sites; frame and bounds requests currently return deterministic retained canvas bounds for `.local`, `.global`, and named spaces, and safe-area insets are zero because the Win32 host renders into the client area. `GeometryProxy3D` provides matching source-compatible 3D geometry access for `visualEffect3D`, with depth defaulting to zero and transforms defaulting to identity. `coordinateSpace(_:)` and `coordinateSpace(name:)` are accepted as no-op retained metadata boundaries until full coordinate-space projection exists.
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
- `@AppStorage`
- `@SceneStorage`
- `@ScaledMetric`
- `@Environment`
- `@EnvironmentObject`
- `@FocusedValue`
- `@FocusedBinding`
- `@FocusedObject`
- `@FocusState`
- `@GestureState`
- `@Namespace`
- `DynamicProperty`
- `ObservableObject`
- `@Published`
- `@ObservedObject`
- `@StateObject`
- `PreferenceKey`
- `Anchor`

`@Environment` can read retained-context values such as `isEnabled`, `isFocused`, `isFocusEffectEnabled`, `isLuminanceReduced`, `isSceneCaptured`, `isTabBarShowingSections`, `isScrollEnabled`, `horizontalScrollIndicatorVisibility`, `verticalScrollIndicatorVisibility`, `horizontalScrollBounceBehavior`, `verticalScrollBounceBehavior`, `scrollTargetBehavior`, `scrollInputBehaviors`, `scrollIndicatorsFlashOnAppear`, `scrollIndicatorsFlashTrigger`, `scrollDismissesKeyboardMode`, `defaultMinListHeaderHeight`, `defaultMinListRowHeight`, `defaultWheelPickerItemHeight`, `backgroundProminence`, `headerProminence`, `badgeProminence`, `redactionReasons`, `isPrivacySensitive`, `colorScheme`, `colorSchemeContrast`, `scenePhase`, `controlActiveState`, `appearsActive`, `supportsMultipleWindows`, `isPresented`, `editMode`, `legibilityWeight`, `displayScale`, `pixelLength`, `calendar`, `timeZone`, `locale`, `dismiss`, `dismissSearch`, `isSearching`, `rename`, `refresh`, `openWindow`, `dismissWindow`, `openSettings`, `requestReview`, `undoManager`, `defaultAppStorage`, `accessibilityAssistiveAccessEnabled`, `accessibilityDimFlashingLights`, `accessibilityDifferentiateWithoutColor`, `accessibilityEnabled`, `accessibilityInvertColors`, `accessibilityLargeContentViewerEnabled`, `accessibilityPlayAnimatedImages`, `accessibilityPrefersHeadAnchorAlternative`, `accessibilityQuickActionsEnabled`, `accessibilityReduceHighlightingEffects`, `accessibilityReduceMotion`, `accessibilityReduceTransparency`, `accessibilityShowButtonShapes`, `accessibilityShowBorders`, `accessibilitySwitchControlEnabled`, `accessibilityVoiceOverEnabled`, `layoutDirection`, `horizontalSizeClass`, `verticalSizeClass`, `dynamicTypeSize`, `font`, `fontWidth`, `multilineTextAlignment`, `lineLimit`, `lineSpacing`, `minimumScaleFactor`, `truncationMode`, `allowsTightening`, `textCase`, `textSelectability`, `textSelectionAffinity`, `textInputAutocapitalization`, `isAutocorrectionDisabled`, `writingToolsBehavior`, `writingToolsAffordanceVisibility`, `tint`, `buttonRepeatBehavior`, `buttonSizing`, `buttonBorderShape`, `menuIndicatorVisibility`, `controlSize`, `imageScale`, `symbolRenderingMode`, `symbolVariants`, `labelStyle`, `labeledContentStyle`, `formStyle`, `groupBoxStyle`, `disclosureGroupStyle`, `menuStyle`, `controlGroupStyle`, `navigationViewStyle`, `navigationSplitViewStyle`, `progressViewStyle`, `gaugeStyle`, `datePickerStyle`, `tabViewStyle`, `indexViewStyle`, `toggleStyle`, `textFieldStyle`, `listItemTint`, `contentTransition`, `contentTransitionAddsDrawingGroup`, and `submitLabel`, and app-defined `EnvironmentKey` values can be exposed through `EnvironmentValues` extensions. `environment(_:_:)`, `transformEnvironment(_:_:)`, `defaultAppStorage(_:)`, and `preferredColorScheme(_:)` override inherited values through the retained build context.
`PreferenceKey`, `preference(key:value:)`, `transformPreference(_:_:)`, and `onPreferenceChange(_:perform:)` store type-erased preference metadata on retained `ViewNode`s and reduce descendant values in retained tree order. `transformPreference` rewrites the observed subtree value before it bubbles to ancestors, and removing the last emitted preference reports the key's default value. `Anchor`, `Anchor<Rect>.Source.bounds`, `anchorPreference(key:value:transform:)`, `transformAnchorPreference(key:value:transform:)`, `backgroundPreferenceValue`, `overlayPreferenceValue`, and `GeometryProxy[anchor]` are available for common bounds-anchor shared-source call sites. Bounds anchors resolve to deterministic retained node bounds based on the node's current intrinsic/preferred size at build time, with no full SwiftUI post-layout coordinate-space projection yet.
Observed object changes are coalesced by the host before rebuilding the retained tree so one logical update does not trigger multiple immediate redraw passes.
`DynamicProperty` is available as a source-compatibility marker with a default no-op `update()`. WinSwiftUI's built-in SwiftUI-shaped property wrappers conform to it, but the retained runtime does not yet perform SwiftUI's pre-body dynamic property update sweep.
`@Namespace` creates a stable namespace ID retained by the property wrapper value and exposes it through `$namespace`, which is enough for source-compatible `matchedGeometryEffect` call sites.
`Binding` supports read/write dynamic-member projections for writable key paths, so shared-source code can pass nested bindings such as `$settings.title` or `$settings.isEnabled` into retained controls. Mutable-collection bindings expose element bindings with subscript syntax, so `$items[index].title`-style call sites can edit array elements in place. It also accepts SwiftUI-shaped optional bridging: `Binding<Value?>($value)` promotes non-optional bindings and `Binding<Value>($optional)` unwraps optional bindings when a value exists. `Binding.transaction(_:)`, `Binding.animation(_:)`, and the transaction-aware setter initializer are accepted as source-compatible no-op transaction shims; the retained runtime does not yet propagate binding transactions into animation state.
`@State` stores values in a retained box captured by the view value and exposes `$state` as a `Binding`, which is enough for common controls such as `Toggle`.
`@AppStorage` supports common non-optional and optional `Bool`, `Int`, `Double`, `String`, `Data`, and `URL` values backed by `UserDefaults`, plus optional and non-optional `RawRepresentable` values with `String` or `Int` raw values for enum-backed preferences. Wrappers with an explicit `store:` keep using that store, while wrappers without one inherit `EnvironmentValues.defaultAppStorage` through `.defaultAppStorage(_:)` and remember that store for retained control actions. Optional nil writes remove the stored `UserDefaults` value. It exposes `$storage` as a `Binding` and invalidates the retained runtime after writes from the wrapper. It is a source-compatibility shim and does not yet observe external `UserDefaults` changes.
`@SceneStorage` stores non-optional and optional `Bool`, `Int`, `Double`, `String`, `Data`, and `URL` values in a retained in-memory scene-state table, supports optional and non-optional `RawRepresentable` values with `String` or `Int` raw values for enum-backed scene state, exposes `$storage` as a `Binding`, and invalidates after writes. Optional nil writes remove the retained scene value. The current implementation matches the single-window host scope and does not yet serialize scene restoration data or isolate values per future `WindowGroup` instance.
`@ScaledMetric` scales floating-point values with the same deterministic `DynamicTypeSize` table used by retained text, accepts `relativeTo:` for source compatibility, and exposes the requested text style as metadata. Closed and partial `.dynamicTypeSize(...)` ranges intersect inherited limits, and retained text, `@Environment(\.dynamicTypeSize)`, and `@ScaledMetric` all receive the same effective clamped size. It does not yet model SwiftUI's per-text-style scaling curves.
`@GestureState` stores transient gesture values in a retained wrapper box. `DragGesture.updating(_:body:)` and `LongPressGesture.updating(_:body:)` write through that state while retained pointer/drag callbacks are active and reset it to the initial value when the gesture ends or cancels. The generic SwiftUI gesture-state arbitration model is not implemented yet.
`ObservableObjectPublisher` supports source-compatible manual `objectWillChange.send()` invalidation for retained hosts and also behaves as a lightweight `Void` publisher for `sink` and `onReceive`. `Just`, `PassthroughSubject`, `CurrentValueSubject`, `AnyPublisher`, `ObservableObjectPublisher`, and `@Published` expose lightweight publishers with `sink(receiveValue:)`, `assign(to:on:)`, `eraseToAnyPublisher()`, `map`, `compactMap`, `filter`, `dropFirst`, `removeDuplicates`, and `AnyCancellable.store(in:)`; `@Published` and `CurrentValueSubject` subscribers receive the current value and later writes, while `PassthroughSubject` only sends future `send(_:)` values. `PassthroughSubject<Void, Failure>` also accepts `send()` for source-compatible event streams. Cancellables can be stored in `Set<AnyCancellable>` or array-like collections. `AnyCancellable` cancels on explicit `cancel()` or deinit, but this is not a full Combine publisher implementation and does not model failures, completion events, demand, or schedulers. `onReceive(_:perform:)` subscribes to WinSwiftUI lightweight publishers while the retained node is rendered and cancels the subscription when the node disappears. `@ObservedObject`, `@StateObject`, and `@EnvironmentObject` expose SwiftUI-shaped projected member bindings for writable object properties, so retained controls can consume shared-source bindings such as `$model.title` or `$model.isEnabled`. `@StateObject` currently shares the same observation and invalidation path as `@ObservedObject`; it is a source-compatibility shim, not a full SwiftUI lifetime model yet.

This is intentionally small. It exists to support shared app source and runtime invalidation, not to reproduce the full SwiftUI observation stack.

## Demo Contract

The demo in [`Sources/SwiftWindowsDemo/DemoDashboard.swift`](../Sources/SwiftWindowsDemo/DemoDashboard.swift)
is the reference for the supported same-source subset. Its dashboard, settings,
and searchable component-inspector screens all use ordinary SwiftUI-shaped
composition and run through the same retained runtime as application code.
Theme, accent color, and font-scale settings feed inherited appearance/tint/
Dynamic Type environments; the dashboard command field navigates modules and
screens, and the component table filters names, details, versions, and health
status while keeping inspector selection synchronized.

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
- `layoutPriority` is still read as a flex-grow weight by the stack allocator in rows that contain **no greedy child at all**, not only as SwiftUI's allocation *order* under pressure. Roughly twenty control builders are written against that meaning, so in such a row `.layoutPriority(1)` on app code inflates that subtree's frame instead of merely protecting its ideal size. Greedy fill (`layoutFillAxes`) has taken over the "grow into the leftover" half of the job wherever it applies: as soon as one child of the row is greedy — a `Spacer`, a `ScrollView`, a `.frame(maxWidth: .infinity)` — the leftover goes to the greedy children only and a `.layoutPriority(1)` fixed-width sibling keeps the width its author gave it. Retiring the weight reading entirely is a follow-up.
- The grouped-form two-column grid is `Form`-scoped. Outside a `Form`, a labelled `Slider`, `Toggle`, `Picker`, or `ProgressView` still stacks its label above (or beside) the control rather than routing through a label column; there is no `Grid`/`alignmentGuide`-driven column that spans arbitrary containers.
- The shared label column is resolved at build time from each row's intrinsic label width, so a label whose text changes size *after* the build (an animated `.font()` transition) keeps the column it was built with until the next rebuild.
- The repository is still Windows-only because the platform and renderer targets are Win32/D3D11-specific.
- Text behavior on the default path is still bitmap-based, while the experimental scene path has a partial native glyph-atlas port with cached logical layout, subtree layout/measurement reuse, runtime-owned prepaint dispatch state plus split deferred-subtree prepaint and deferred paint replay for interaction/focus/late-paint metadata and ancestor routing, semantic content masks, inherited-opacity propagation, and glyph-run capture that still stops short of GPUI-style shaped text runs, per-deferred prepaint replay ranges, and sprite families.
- `D3D11Renderer` still only executes `fillRect` and `drawBitmap`; `GPUIScene` remains the richer but still experimental presentation path.
- API coverage should be extended from real demo/app needs, not by cloning SwiftUI surface area speculatively.
