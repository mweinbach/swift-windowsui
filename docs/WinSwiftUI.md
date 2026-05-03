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

`LocalizedStringKey` and `LocalizedStringResource` are currently identity aliases to `String` for source compatibility. They preserve common SwiftUI call-site shapes, but they do not perform localization table lookup yet.

Common title-bearing views and controls accept `StringProtocol` title values so shared source can pass `String`, `Substring`, and the current localization aliases without pre-converting to `String`.

## Current Surface

App/scene hosting:

- `App`
- `Scene`
- `WindowGroup`
- `WinSwiftUIInspection.snapshot(of:)` for retained-tree/render-command diagnostics without opening a window

Views and containers:

- `Text`
- `Image(systemName:)`
- `Label` with title/system image and custom title/icon builder forms
- `ContentUnavailableView`
- `LabeledContent`
- `ControlGroup`
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
- `LazyVStack`
- `LazyHStack`
- `LazyVGrid`
- `LazyHGrid`
- `ScrollView`
- `List`
- `Form`
- `TabView`
- `NavigationStack`
- `NavigationLink`
- `NavigationSplitView`
- `ToolbarItem`
- `ToolbarItemGroup`
- `GroupBox`
- `DisclosureGroup`
- `Section`
- `HSplitView`
- `VSplitView`
- `Button`
- `Link`
- `Menu`
- `TextField`
- `SecureField`
- `TextEditor`
- `Toggle`
- `Stepper`
- `Slider`
- `DatePicker`
- `ColorPicker`
- `ProgressView`
- `Gauge`
- `Picker`
- `PinnedScrollableViews`
- `GridItem`

Modifiers:

- `frame`
- `fixedSize`
- `padding`
- `foregroundColor`
- `foregroundStyle`
- `font`
- `fontDesign`
- `textCase`
- `kerning`
- `tracking`
- `lineSpacing`
- `fontWeight`
- `bold`
- `italic`
- `monospaced`
- `underline`
- `strikethrough`
- `multilineTextAlignment`
- `lineLimit`
- `truncationMode`
- `tint`
- `controlSize`
- `searchable`
- `textFieldStyle`
- `progressViewStyle`
- `gaugeStyle`
- `datePickerStyle`
- `menuStyle`
- `controlGroupStyle`
- `buttonStyle`
- `labelStyle`
- `toggleStyle`
- `pickerStyle`
- `listStyle`
- `scrollIndicators`
- `labelsHidden`
- `background`
- `overlay`
- `alert`
- `sheet`
- `popover`
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
- `navigationDestination`
- `navigationTitle`
- `toolbar`
- `tabItem`
- `id`
- `tag`

Compatibility helpers:

- `Color(red:green:blue:opacity:)`
- `Color(white:opacity:)`
- `Color(hue:saturation:brightness:opacity:)`
- common named `Color` values such as `primary`, `secondary`, `accentColor`, `red`, `green`, `blue`, `gray`, `orange`, and `purple`
- `Color.opacity(_:)`
- `Material` presets such as `ultraThinMaterial`, `thinMaterial`, `regularMaterial`, `thickMaterial`, `ultraThickMaterial`, and `bar`
- `LinearGradient(colors:startPoint:endPoint)`
- `EdgeInsets()` and partially specified `EdgeInsets(top:leading:bottom:trailing:)` initializers with zero defaults
- shape `fill(_:)` for colors and linear gradients
- shape `stroke(_:lineWidth:)`
- `UnitPoint`
- `Angle`
- `FillStyle`
- `DragGesture`
- `ControlSize`
- `SearchFieldPlacement`
- `DatePickerComponents`
- common `TextFieldStyle`, `ProgressViewStyle`, `GaugeStyle`, `DatePickerStyle`, `MenuStyle`, `ControlGroupStyle`, `LabelStyle`, `ToggleStyle`, `PickerStyle`, and `ListStyle` presets
- value-based `NavigationLink` routing through `navigationDestination(for:destination:)`
- `CGFloat`, `CGPoint`, `CGSize`, `CGRect` aliases
- minimal `State`, with projected bindings tied into retained-runtime invalidation
- minimal `ObservableObject`, `Published`, `ObservedObject`, and `StateObject`
- minimal `Binding`, including projected `@ObservedObject` and `@StateObject` bindings

Surface direction:

- default retained buttons now use lighter rounded chrome with hover, focus, press, and activation transitions
- bindings now cover direct `Binding(get:set:)`, projected `@State`, projected `@ObservedObject`, and projected `@StateObject` members for controls such as `TextField`, `Toggle`, and `Slider`
- the demo’s cards and chips are built from shared-source-friendly layered gradients and translucent strokes rather than WinSwiftUI-only styling hooks

## Mapping Notes

- `Text` maps into retained label nodes and the current text renderer path. Plain strings, `StringProtocol` values, `Text(verbatim:)`, `Text` concatenation with retained span style metadata, and common inline styling modifiers such as `foregroundColor`, `foregroundStyle(Color)`, `bold`, `italic`, `fontWeight`, `fontDesign`, `textCase`, `monospaced`, `kerning`, `tracking`, `lineSpacing`, `truncationMode`, `underline`, and `strikethrough` are accepted for source compatibility.
- `Image(systemName:)` maps known SF Symbol names into the project icon set, including common action, status, navigation, people, media, lock, and share glyph aliases. Typed `foregroundColor`, `foregroundStyle(Color)`, `font`, and alignment modifiers preserve concrete `Image` chaining.
- `Label` maps system-image labels and custom `title`/`icon` builder labels into retained horizontal stacks. Label-level `foregroundColor`, `foregroundStyle(Color)`, and `font` modifiers style descendant text while preserving the icon font family. `labelStyle` supports `.automatic`, `.titleAndIcon`, `.titleOnly`, and `.iconOnly` style values plus common concrete wrappers such as `IconOnlyLabelStyle()`, flowing through the build context to descendant labels.
- `ContentUnavailableView` maps common empty-state and search-empty call sites into centered retained stacks with title/icon, optional description, and optional action content.
- `LabeledContent` maps common settings rows into retained horizontal stacks with leading labels and trailing value/content views.
- `ControlGroup` maps grouped controls into a rounded retained horizontal stack with translucent chrome while preserving each child control's focus and activation behavior. `controlGroupStyle` supports `.automatic`, `.navigation`, `.palette`, `.menu`, and `.compactMenu` style values plus common concrete wrappers such as `PaletteControlGroupStyle()`, flowing through the build context to descendant groups.
- `Divider` maps into a thin retained panel and uses the nearest stack axis to choose a horizontal or vertical separator.
- `Rectangle`, `RoundedRectangle`, `Circle`, `Ellipse`, and `Capsule` map into passive retained panels. Shape fills set panel backgrounds or gradients; shape strokes set retained border color and width.
- `RoundedRectangle` carries its corner radius into the retained node so fills, strokes, overlays, and clipping stay aligned. `Circle`, `Ellipse`, and `Capsule` use the retained rounded-rect renderer's maximum capsule radius until path-backed shape views provide true vector ellipse masking.
- `Button` maps into retained button controls and preserves focus/press/activate animation state. SwiftUI-shaped role and `systemImage` initializers are available; `.destructive` maps to a red-tinted retained button surface while `.cancel` currently keeps the automatic surface.
- `buttonStyle` supports `.automatic`, `.bordered`, `.borderedProminent`, `.borderless`, and `.plain` on both individual `Button` values and ancestor views. Descendant buttons inherit the style through the build context unless they set their own explicit button style. `.borderedProminent` maps to a blue translucent retained surface; `.borderless` and `.plain` map to transparent chrome.
- `Button` now also resolves hover-aware border and shadow states so retained controls feel closer to modern desktop/mobile system chrome.
- `Menu` maps common title, `systemImage`, and custom-label call sites into a retained disclosure-style action cluster. `menuStyle` supports `.automatic`, `.button`, `.borderedButton`, and `.borderlessButton` style values plus common concrete wrappers such as `BorderlessButtonMenuStyle()`, flowing through the build context to descendant menus. Expanded content is currently rendered inline rather than through a native popup surface, but child controls keep their normal retained focus and activation behavior.
- `TextField` maps into a retained single-line editable control. StringProtocol title and `prompt: Text` initializer shapes are accepted, with prompt text used as the retained placeholder. Win32 `WM_CHAR` and IME character messages flow through the runtime text-input hook to the focused node, while pointer clicks/drags, arrows, shift-selection, home/end, backspace, delete, `Ctrl+A`, and injected clipboard shortcuts update the retained caret/editing state. `textFieldStyle` supports `.automatic`, `.roundedBorder`, and `.plain` style values plus common concrete wrappers such as `PlainTextFieldStyle()`, flowing through the build context to descendant text fields.
- `searchable(text:placement:prompt:)` wraps the view with a retained inline search field that reuses the same `TextField` editing, focus, submit, and binding behavior. `SearchFieldPlacement` accepts `.automatic`, `.toolbar`, `.sidebar`, `.navigationBarDrawer`, and `.navigationBarDrawer(displayMode:)` call sites for source compatibility, but placement is advisory for now and lowers to an inline retained field above the modified content.
- `SecureField` reuses the retained text-field control with masked display text while keeping the bound string unmasked. It supports the same string-title, `prompt: Text` placeholder initializer shapes, and inherited `textFieldStyle` chrome as `TextField`. Paste is allowed through the injected clipboard bridge, but copy/cut do not expose selected secure text.
- `TextEditor(text:)` reuses the retained text-input path in multiline mode. Return/enter inserts newlines, text wraps inside the editor surface, and the caret tracks explicit line breaks with pointer clicks/drags plus up/down arrow movement across explicit lines. Keyboard and pointer range/select-all replacement/deletion plus injected clipboard shortcuts are supported, while rich text and full platform text services are still future work.
- Clipboard shortcuts use the runtime-level `TextClipboard` injection point. `SwiftWindowsPlatform.Win32TextClipboard` provides `CF_UNICODETEXT` read/write with Windows CRLF normalization, and both `FoundationApp` and `WinSwiftUIWindowHost` install it for retained text controls.
- `Toggle`, `Stepper`, `Slider`, `DatePicker`, `ColorPicker`, `ProgressView`, and `Gauge` map into retained controls while exposing SwiftUI-shaped binding/value initializers. `toggleStyle` supports `.automatic`, `.switch`, `.checkbox`, and `.button` style values plus common concrete wrappers such as `CheckboxToggleStyle()`; descendant toggles inherit the style through the build context unless they set their own explicit style. `Stepper` supports bounded integer and double values with title or custom-label call sites. `Slider(value:in:step:)` snaps dragged binding updates to the requested step. `DatePicker` supports string/custom-label `Binding<Date>` call sites, date/time displayed components, closed and one-sided ranges, retained +/- date and time steppers, `labelsHidden`, and `datePickerStyle` presets `.automatic`, `.compact`, `.field`, `.stepperField`, `.graphical`, and `.wheel`; these are retained compact fields rather than native popup calendars for now. `ColorPicker` supports string/custom-label `Binding<Color>` call sites, `supportsOpacity`, `labelsHidden`, a retained swatch, hex value text, and RGB/A channel steppers; it is a retained inline picker rather than a native color-panel bridge for now. `ProgressView` also supports a string-title initializer that composes a retained label with the progress indicator. `progressViewStyle` supports `.automatic`, `.linear`, and `.circular`; circular style lowers to renderer-neutral stroked paths. `Gauge(value:in:label:currentValueLabel:minimumValueLabel:maximumValueLabel:)` reuses the retained progress path with optional label rows plus inherited tint and control sizing. `gaugeStyle` supports linear and accessory/circular style presets, with circular variants backed by the same stroked path ring.
- `Picker` maps tagged `Text` options into retained selection controls and supports hashable selection tags, including integers, strings, and enum values. `pickerStyle` supports `.automatic`, `.menu`, `.segmented`, `.radioGroup`, and `.inline` style values plus common concrete wrappers such as `SegmentedPickerStyle()`. Menu style lowers to the retained dropdown, segmented style lowers to the retained tab-bar/segmented control, and radio-group/inline style lowers to retained radio rows.
- `ScrollView` maps into retained scroll panels with indicator state handled in the runtime.
- `scrollIndicators(_:)` accepts `.automatic`, `.visible`, and `.hidden` and updates descendant retained scroll containers, including `List`, without changing scroll culling or input behavior.
- `VStack` and `HStack` accept SwiftUI-style optional spacing; nil spacing currently lowers to the retained stack path's zero-spacing default.
- `LazyVStack` and `LazyHStack` preserve common lazy-stack call sites and lower to the retained stack layout path. The runtime already clips and culls offscreen render commands inside scroll panels; child view construction is still eager, and pinned section headers/footers are accepted for compatibility but not pinned yet.
- `LazyVGrid` maps `GridItem` column declarations into the retained grid layout path. Fixed and flexible columns resolve against the current build context width, and adaptive columns expand from their minimum width; pinned headers/footers are accepted for compatibility but not pinned yet.
- `LazyHGrid` preserves the SwiftUI-shaped row initializer and currently lowers to retained nested stacks in column-major order. Fixed, flexible, and adaptive row declarations resolve against the current build context height; shared row sizing, true lazy construction, and pinned headers/footers are still future work.
- `ForEach` expands child views in result builders and assigns stable node tags from the supplied identity. Identifiable collections, explicit `id:` key paths, open integer ranges, and closed integer ranges are supported.
- `id(_:)` accepts hashable values and stores their string description as the retained node tag for reconciliation.
- `List` maps into a styled vertical retained scroll panel and preserves the same offscreen culling path as `ScrollView`.
- `listStyle` supports `.automatic`, `.plain`, `.inset`, `.grouped`, `.insetGrouped`, and `.sidebar` style values plus common concrete style wrappers such as `PlainListStyle()`. List styles flow through the build context to descendant `List` values unless a list is created with an explicit retained `ScrollViewStyle`.
- `Form` maps into a grouped vertical retained scroll panel with macOS-style translucent chrome and composes directly with `Section` rows.
- `TabView` maps tagged pages into a retained segmented tab bar plus the selected content subtree. The `selection:` initializer supports typed `Binding` values, while unbound tabs keep local `@State` selection.
- `NavigationStack` keeps a local retained route stack for simple drill-in flows. `NavigationLink` renders as an interactive retained row and pushes destination content when built inside a `NavigationStack`. In addition to direct destination closures, value-based `NavigationLink(value:label:)` and title/value links resolve through the nearest typed `navigationDestination(for:destination:)` modifier.
- `Link` maps title and custom-label URL links into retained borderless controls. Activating a link uses the Windows shell URL opener by default so the destination can open in the associated app or default browser; tests can inject the opener to validate activation without launching a process.
- `navigationTitle(_:)` wraps content in a retained translucent title strip. This is visual retained chrome rather than full platform navigation-bar integration; pushed `NavigationStack` destinations still use the route title from `NavigationLink` for the back bar.
- `NavigationSplitView` maps the common two- and three-column closure forms onto retained nested `HSplitView`s with styled sidebar/content/detail columns.
- `toolbar` wraps a view in a retained translucent action bar. `ToolbarItem` and `ToolbarItemGroup` preserve common SwiftUI call-site shapes while lowering their contents into retained controls. Placement values are accepted for compatibility, but currently render in one horizontal action row.
- `GroupBox` maps title and custom-label call sites into retained `Section`-style rounded panels for settings and dashboard groups.
- `DisclosureGroup` maps expanded-state bindings into retained stack content with a button-backed header; collapsed groups keep only the header in the retained tree.
- `Section` supports the styled string-title initializer plus SwiftUI-shaped content/header/footer builder forms. Custom header and footer views are rendered as supplied retained subtrees.
- `HSplitView` and `VSplitView` map into the retained split-view control and can infer an initial ratio from content.
- `GeometryReader` uses the current build context canvas size.
- `frame` supports fixed dimensions plus the common min/ideal/max overload. Infinite maximums, such as `maxWidth: .infinity`, map to retained fill-available behavior and participate in stack growth.
- `fixedSize(horizontal:vertical:)` marks selected axes for unconstrained retained measurement, prevents flexible growth on those axes, and makes stack compression respect the measured fixed extent before shrinking other siblings. It preserves SwiftUI's common fixed-size source shape but is still bounded by explicit finite `maximumSize` values.
- `padding` accepts explicit lengths, edge sets, `EdgeInsets`, and optional lengths where `nil` resolves to the retained default padding.
- Generic text modifiers (`foregroundColor`, `foregroundStyle(Color)`, `font`, `fontDesign`, `textCase`, `kerning`, `tracking`, `lineSpacing`, `fontWeight`, `bold`, `italic`, `monospaced`, `underline`, `strikethrough`, `multilineTextAlignment`, `lineLimit`, and `truncationMode`) walk the retained subtree and update text descendants. Optional `foregroundColor(nil)` and `foregroundStyle(nil)` are accepted for SwiftUI source compatibility and leave retained text colors unchanged. `font` preserves the Segoe Fluent Icons family for `Image(systemName:)` glyphs while still changing their size and weight; `fontDesign` and `monospaced` also preserve icon glyph families. `textCase` rewrites retained text and span ranges for uppercase/lowercase source compatibility. `lineLimit` and `truncationMode` map onto retained maximum-line and head/tail/middle line-break metadata. `kerning` and `tracking` update retained `letterSpacing` metadata; `lineSpacing` updates retained line gap metadata. These spacing values are honored by the bitmap text path and kept available to native text backends.
- `Font` supports `system(size:weight:design:)`, `system(_:design:weight:)`, `custom(_:size:)`, `custom(_:fixedSize:)`, and common named presets such as `largeTitle`, `title`, `headline`, `body`, `caption`, and `footnote`. `font(nil)` is accepted for SwiftUI source compatibility and leaves retained text styles unchanged.
- `tint` is carried through the build context so descendant `Toggle`, `Slider`, `ProgressView`, and `Gauge` controls inherit a shared accent color unless they set their own control-specific tint. `tint(nil)` is accepted for SwiftUI source compatibility and leaves the current inherited or control-specific tint unchanged. `accentColor(_:)` is accepted as a source-compatibility alias for the same retained control accent pipeline; it does not yet provide full dynamic semantic color resolution for every `Color.accentColor` use.
- `controlSize` is carried through the build context and supports `.mini`, `.small`, `.regular`, `.large`, and `.extraLarge`. Buttons, switches, checkbox/button-style toggles, text fields, text editors, sliders, progress bars/rings, menu pickers, segmented pickers, and radio picker rows use it to choose retained hit targets, preferred sizes, padding, and corner radii.
- `searchable` uses the supplied search text binding as the retained search field storage. Search suggestions, tokens, scopes, environment-driven dismissal, and native toolbar/sidebar placement are still future work.
- `textFieldStyle` is carried through the build context so descendant `TextField` and `SecureField` controls can share rounded-border or plain retained chrome unless they set their own explicit style.
- `progressViewStyle` and `gaugeStyle` are carried through the build context so descendant progress and gauge controls can share linear or circular retained indicators unless they set explicit styles.
- `datePickerStyle` is carried through the build context so descendant date pickers can share compact, field, graphical, or wheel-inspired retained chrome unless they set explicit styles.
- `controlGroupStyle` is carried through the build context so toolbar and menu control clusters can share retained group chrome unless a descendant group sets an explicit style.
- `menuStyle` is carried through the build context so menu trigger chrome can be set at a container boundary while still allowing descendant menus to override the inherited style.
- `labelsHidden()` is supported on `Toggle` and `Picker`; it removes the retained label/title wrapper while preserving the interactive switch, dropdown, segmented control, or radio rows.
- View `background` and `overlay` overloads map to retained absolute-layout wrappers; the base view keeps layout ownership while the added layer is aligned within the resolved base bounds. Zero-intrinsic layers such as `Color`, `Rectangle`, stroked `RoundedRectangle`, and `Material` fill the base bounds by default.
- `alert(_:isPresented:actions:message:)` maps to a retained modal overlay with a dimming scrim, rounded glass-style card, message content, and action buttons. Default alerts provide an `OK` button, custom retained actions dismiss after activation, and the current implementation is an in-window overlay rather than a separate native dialog surface.
- `sheet(isPresented:onDismiss:content:)` maps to a retained in-window sheet with a dimming scrim and a wider glass-style bottom panel. Scrim dismissal updates the presentation binding and calls `onDismiss`; content-driven dismissal should update the supplied binding directly.
- `popover(isPresented:attachmentAnchor:arrowEdge:content:)` maps to a retained floating glass card with a transparent dismissal layer and a renderer-neutral vector arrow on the requested edge. The common `.rect(.bounds)` attachment anchor is accepted for source compatibility; precise source-rect anchoring is still future work, so placement currently follows the requested `arrowEdge` within the window.
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
