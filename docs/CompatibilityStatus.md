# WinSwiftUI Compatibility Status

Honest matrix of what is safe to use today in `WinSwiftUI`.

This document is for app authors targeting the shared-source subset
(`import WinSwiftUI` on Windows, `import SwiftUI` on macOS). It is **not** a
claim of full SwiftUI parity.

## Architecture (read this first)

WinSwiftUI is a **custom-rendered** Windows UI toolkit with a SwiftUI-shaped
surface. It is **not** a wrapper around native Win32 widgets, AppKit bridges,
or WebView-hosted SwiftUI.

App code maps into:

| Layer | Role |
| --- | --- |
| `WinSwiftUI` | SwiftUI-shaped views, modifiers, environment, app/scene types |
| `RetainedViewRuntime` / `ViewNode` | Retained layout, hit testing, focus, clipping, animation, invalidation |
| `GPUIScene` / `RenderFrame` | Renderer-neutral paint contracts |
| `Win32Window` | Windowing, input, timers |
| `D3D11BatchRenderer` / `D3D11Renderer` | Direct3D 11 presentation (scene path default; frame path fallback) |

Default demo path:

`App` / `WindowGroup` → `WinSwiftUIWindowHost` → `Win32Window` →
`RetainedViewRuntime` → `GPUIScene` → `D3D11BatchRenderer`

Screenshot validation is raw retained-runtime output via
`swift-windowsui-snapshot` and `GPUIRawSceneRasterizer`, not desktop capture.

Detailed API notes live in [`docs/WinSwiftUI.md`](WinSwiftUI.md). Design and
animation numeric parity tables live in [`docs/MacOSDesignParity.md`](MacOSDesignParity.md)
and [`docs/AnimationParity.md`](AnimationParity.md).

## Status legend

| Status | Meaning | Safe for production UI? |
| --- | --- | --- |
| **Implemented** | Maps to retained runtime behavior with usable interaction and paint | Yes, for the described scope |
| **Partial** | Compiles and does something useful, but diverges from SwiftUI semantics or completeness | Yes with care; read the notes |
| **Shim / no-op** | Present for source compatibility; stores metadata or passes through without the expected effect | Only when you do not depend on the behavior |
| **Placeholder panel** | Renders a labeled non-interactive panel (or empty chrome) instead of the native feature | No for real product flows |
| **Unsupported** | No meaningful Windows integration; avoid for shared behavior you care about | No |

Many symbols accept SwiftUI call shapes so shared sources compile. **API
presence alone does not mean runtime parity.** Prefer this matrix over scanning
public symbols.

---

## Safe today (dashboard-style apps)

These categories are the intended production subset: settings-style and
dashboard composition on a single custom-rendered window.

### App hosting — Implemented (multi-window via coordinator)

| API | Status | Notes |
| --- | --- | --- |
| `App`, `Scene`, `WindowGroup` | **Implemented** | Primary host path; boots one live window |
| `Window`, `WindowScene` | **Partial** | Accept content and produce a window configuration; multi-window lifecycle is not hosted |
| Host loop / invalidation coalescing | **Implemented** | Coalesced rebuilds; high-rate pumping only when input dirties presentation |

### Layout containers — Implemented / Partial

| API | Status | Notes |
| --- | --- | --- |
| `VStack`, `HStack`, `ZStack` | **Implemented** | Optional spacing (`nil` → retained default `0`) |
| `LazyVStack`, `LazyHStack` | **Partial** | Layout is virtualized: rows the scroll viewport plus a viewport of overscan cannot reach are placed but not laid out recursively, and are projected to accessibility as flagged placeholders with their real bounds. Construction is **not** — every row's node is still built and measured, so a long list costs O(rows) nodes. `onLayout` does not fire for a deferred row. Falls back to eager behaviour verbatim with no scrollable ancestor |
| `LazyVGrid`, `LazyHGrid` | **Partial** | Retained row/column stack layout from `GridItem` specs; not viewport-lazy |
| `Grid`, `GridRow` | **Partial** | Stack-based; simple `gridCellColumns` growth; full column sizing / cell anchors are incomplete |
| `Spacer`, `Divider`, `Group`, `EmptyView` | **Implemented** | |
| `ScrollView` | **Partial** | One primary axis; `.all` resolves to vertical; indicators managed in runtime |
| `List` | **Partial** | Vertical scroll panel, stable row metrics, hover/selection chrome, arrow-key selection with scroll-into-view; limited edit chrome. **Not virtualized**: arrow-key scroll-into-view mirrors row frames through `onLayout`, which deferral silences for exactly the off-screen rows it needs — see `docs/GPURenderingPipeline.md`, “Why `List` is not virtualized yet” |
| `Form`, `Section` | **Partial** | Form chrome and section headers/footers; styles map to retained spacing/shells |
| `GroupBox`, `DisclosureGroup`, `ControlGroup` | **Partial** | Functional retained chrome; style enums are mostly visual profiles / metadata |
| `HSplitView`, `VSplitView` | **Implemented** | Draggable retained splitters with ratio / min extents |
| `OutlineGroup` | **Partial** | Expand/collapse tree via retained disclosure chrome |
| `Table` | **Partial** | Data + columns as retained header/row grid; not a native Windows list-view |
| `ViewThatFits` | **Partial** | First child whose intrinsic size fits canvas axes; no full proposal probing |
| `GeometryReader` | **Partial** | Canvas size; coordinate spaces are simplified; safe-area insets are zero |

### Text, images, shapes — Implemented / Partial

| API | Status | Notes |
| --- | --- | --- |
| `Text` (string / verbatim / key) | **Partial** | Retained text; localization keys resolve to plain strings (no bundle tables) |
| `Text` date / format / attributed | **Partial** | Deterministic string resolution; rich runs / live timers incomplete |
| `Label`, `Image(systemName:)` | **Partial** | System icons render as real Segoe Fluent/MDL2 glyphs (native bitmap) with a drawn-vector fallback — never `?`; ~40 common SF Symbols mapped, variants/scale honored |
| `Image(_:)` named / file / resource | **Partial** | WIC PNG/JPEG/BMP; no full asset-catalog pipeline |
| `AsyncImage` | **Partial** | URL load into retained image phases; not a full network image stack |
| Basic shapes (`Rectangle`, `RoundedRectangle`, `Capsule`, `Circle`, `Ellipse`, …) | **Implemented** | Fill/stroke/border through retained primitives |
| `StrokeStyle` on any outline | **Implemented** | `lineWidth`, `lineCap`, `lineJoin`, `miterLimit`, `dashPattern`, `dashOffset` reach both stroke routes. Rect and rounded-rect borders resolve dashes through `BorderSegments`; every other outline (custom `Shape`, trimmed shape, `Canvas` `strokePath`) through `PathDashing`. A miter sharper than 4 half-widths degrades to a bevel so the drawn spike cannot exceed the raster sized for it |
| `UnevenRoundedRectangle` | **Implemented** | Per-corner radii end-to-end (RTL-aware); uniform-only consumers (shadow/outline/clip) fall back to max radius |
| `Canvas` + `GraphicsContext` | **Partial** | Scene-path drawing; `symbols:` / `resolveSymbol`, blendMode, `withCGContext` not wired |
| `ContentUnavailableView` | **Implemented** | Retained empty-state chrome |

### Controls — Implemented / Partial

| API | Status | Notes |
| --- | --- | --- |
| `Button` (+ roles, systemImage) | **Implemented** | Focus / press / activate lifecycle on retained chrome |
| `Toggle` | **Implemented** | Binding-backed switch; styles map to retained variants |
| `Picker` | **Partial** | Segmented, menu, inline, radio, wheel-style shells; not native OS pickers |
| `Stepper`, `Slider` | **Implemented** | Binding writes with ranges / steps |
| `ProgressView`, `Gauge` | **Partial** | Determinate / indeterminate retained chrome |
| `TextField`, `SecureField`, `TextEditor` | **Partial** | Focusable retained input; caret, shift-selection, select-all, clipboard shortcuts, mouse-drag selection, IME composition (marked text, candidate window at caret; secure fields block copy/cut) |
| `DatePicker` | **Partial** | Label/value + arrow increments; style shells; not a native calendar UI |
| `MultiDatePicker` | **Partial** | Month grid multi-select for current month |
| `ColorPicker` | **Partial** | Swatch + palette keyboard cycle (default); native `ChooseColorW` dialog opt-in via `\.colorPickerUsesNativeDialog` |
| `Menu` | **Partial** | Retained popup: canvas-clamped placement, scrim/Escape dismissal, focus restore, deferred layering; not a native Win32 menu bar |
| `Link` | **Implemented** | Button that invokes `openURL` (ShellExecute on Windows) |
| `NavigationStack` / `NavigationView` / `NavigationLink` | **Partial** | Local push/pop + title chrome; not UINavigationController semantics |
| `NavigationSplitView` | **Partial** | Horizontal columns + visibility; no adaptive breakpoint collapsing |
| `TabView` | **Partial** | Retained tab bar + page; limited platform tab features |
| `searchable` | **Partial** | Prepends retained search field; placement chrome differs by placement |
| `toolbar` / `ToolbarItem` | **Partial** | Compact retained command row; not a native title-bar toolbar |
| `sheet`, `fullScreenCover`, `popover` | **Partial** | Retained overlays: deferred layering, scrim dismissal, clamped placement, focus restoration (fullScreenCover: layering only); detents approximated; no native presentation |
| `alert`, `confirmationDialog`, `actionSheet` | **Partial** | Retained modal chrome: deferred layering, Escape/scrim dismissal per SwiftUI semantics, focus restoration |
| `contextMenu` | **Partial** | Retained menu overlay: clamped anchor, scrim/Escape dismissal, focus restoration |
| `ShareLink` | **Partial** | Copies transferable items to clipboard — real file references (CF_HDROP) for file URLs, absolute strings otherwise (not system share sheet) |
| `PhotosPicker` | **Partial** | Opens file dialog; not Photos framework |
| `fileImporter` / `fileExporter` | **Partial** | Real Win32 open/save dialogs delivering URLs to the app closure; `allowedContentTypes` map to extension filters (category types approximate) |
| `SettingsLink` / `RenameButton` / `EditButton` | **Partial** | Buttons wired to environment actions / edit mode where present |

### Modifiers commonly safe

| Category | Status | Examples |
| --- | --- | --- |
| Sizing / padding / background / overlay / border / corner / clip | **Implemented** / **Partial** | `frame`, `padding`, `background`, `overlay`, `border`, `cornerRadius`, `clipped`, basic `clipShape` |
| Color / font / line limit / opacity / hidden / zIndex / offset / 2D scale & rotation | **Implemented** / **Partial** | Propagates via `ViewBuildContext` / node transforms |
| Interaction | **Implemented** / **Partial** | `onTapGesture`, `onHover`, `disabled`, `focusable`, `@FocusState`, keyboard shortcuts on activation |
| List row chrome | **Partial** | Separators, insets, backgrounds, selection styling |
| Animation (opacity / background) | **Partial** | `animation`, `withAnimation` for interpolatable retained properties; springs have numeric parity tables |
| State wrappers | **Implemented** / **Partial** | `@State`, `Binding`, `@ObservedObject`, `@StateObject`, `@Published` (lightweight), `@AppStorage` |

---

## Partial (usable, but not SwiftUI-complete)

Use these when you accept retained approximations.

| Area | What works | What does not |
| --- | --- | --- |
| **Text system** | Readable labels, scaling, line limits, minimum scale factor | Full font shaping, rich attributed runs, true localization catalogs, live `Text` timers |
| **SF Symbols** | Named glyph path + limited variants / rendering modes | Multi-layer multicolor symbols, variable values, animated symbol effects |
| **Scrolling** | Wheel/drag offset, indicators, bounce metadata | True two-axis scroll, paging / view-aligned deceleration, scroll observation callbacks, `ScrollViewReader` offset connection |
| **Gestures** | Tap, long-press (release-inside), drag mapped to pointer | Duration thresholds, full gesture composition/arbitration, simultaneous value streaming |
| **Focus** | Focus rings, `@FocusState`, activation | Dynamic `@FocusedValue` retargeting as focus moves; environment `isFocused` live transitions |
| **Drag and drop** | API + metadata on nodes; OS file drops (WM_DROPFILES) delivered to `onDrop` destinations as file URLs | Full delete/reorder/drop affordances, drag-over highlighting, OLE drag sessions |
| **Accessibility** | Metadata on `ViewNode` + derived `AccessibilityElementProjection` + Win32 UI Automation provider (`WM_GETOBJECT`, fragment tree, InvokePattern, focus/structure events); default traits on Supported controls; rows a lazy stack has deferred project as one childless `isVirtualizedPlaceholder` element carrying their real bounds instead of a subtree of zero-size rectangles | Value/Text/Selection/Toggle patterns, live regions, fine-grained structure-changed events, the `VirtualizedItem` pattern (placeholders are flagged but the provider cannot yet realize one) |
| **Materials / blur** | True separable-Gaussian backdrop blur on both paths (D3D11: backbuffer region copy + two-pass GPU blur, same kernel as CPU); wide radii reduce through a shared downsample chain whose halving rule both backends derive from one place; `.blur(radius:)` is an **isolated** pass — the subtree is rendered into its own buffer, blurred there and composited, so it cannot touch a sibling's pixels — including the deferred subtrees (pinned headers) under it | Rotated material quads approximate; a Material inside **any** offscreen pass (`.drawingGroup()`, `.compositingGroup()` or the `.blur(radius:)` isolation pass) has no backdrop to blur — the sub-scene clears to transparent, and seeding it fights the pixels/cache-key/source-over trio recorded in `docs/GPURenderingPipeline.md`; a blurred scroll view's *own* indicator stays sharp (a scroll view nested inside the blurred subtree has its indicator blurred with it); a blurred subtree too large for the offscreen budget degrades to a hard-edged backdrop blur, and still draws its deferred headers |
| **Blend / drawing groups** | Metadata only — both backends composite source-over, gated by `CPUGPUBlendModeContractTests` | Separable blend modes on the GPU (batch split + blend-state swap); scene-path offscreen group compositing as full SwiftUI drawing groups |
| **2D transforms** | Translation, uniform scale and rotation lower onto the scene contract; a `rotationEffect` card draws rotated on both backends, and so does everything in it — shadows, text, images, `Shape` backgrounds and `Canvas` content all turn, and a rotated `.clipped()` clips to the turned shape (an offscreen pass composited back rotated) for both the eye and the pointer; ancestors compose before descendants, and the pointer inverse follows | Shears, mirrors and non-uniform scales degrade to the axis-aligned bounding box; the fallback frame renderer has no rotation encoding at all, so under it a rotated subtree draws — and clips — as its bounding box; a rotated clip whose buffer is past the offscreen budget falls back to the same box |
| **3D transforms** | Z-axis rotation maps to 2D; metadata stored | Full 3D projection pipeline |
| **Color effects / shaders** | Metadata for invalidation / source shape | No compiled Metal/HLSL filter application yet |
| **Navigation deep stacks** | Push/pop for common link patterns | Full path binding, deep-link multi-window routing |
| **Preferences / anchors** | Preference keys and some propagation | Full SwiftUI preference/anchor geometry system |
| **Observation** | Invalidation tuned for retained rebuilds | Full Observation / Combine feature set |
| **Safe area** | Client-area host; `safeAreaPadding` / inset composition | Platform unsafe insets; `ignoresSafeArea` is effectively pass-through |

---

## Compatibility shims and no-ops

These exist so shared sources compile. **Do not depend on them for product
behavior** unless a note says otherwise.

### Scene and platform actions

| API | Status | Behavior today |
| --- | --- | --- |
| `openWindow` / `dismissWindow` | **Implemented** (default routing) | Coordinator opens independent windows (own host/runtime/renderer) for id- and value-based WindowGroups; dismiss closes the calling scene's window or matches by id/value |
| `openSettings` | **Shim / no-op** (default) | `SettingsLink` button calls it; no Settings scene lifecycle |
| `requestReview` | **Shim / no-op** (default) | No StoreKit / Microsoft Store review prompt |
| `Settings`, `DocumentGroup`, `MenuBarExtra` | **Shim / Partial** | Types and configs exist; not first-class hosted scene products |
| `ImmersiveSpace`, `Volume`, Widget configs | **Shim** | Source shapes only; no visionOS / widget runtime |
| `supportsMultipleWindows` | **Implemented** | True for coordinator-managed hosts; false otherwise |

### Window scene modifiers

The window is created at the requested size *in logical points*: the client
size is scaled by the target monitor's DPI and turned into a window rect with
`AdjustWindowRectExForDpi`, so `WindowGroup(size:)` means the same thing at
100 % and 200 %.

| API | Status | Behavior today |
| --- | --- | --- |
| `windowMinSize` / `windowMaxSize` | **Implemented** | `WM_GETMINMAXINFO` track sizes, converted from logical points at the window's current DPI |
| `windowIdealSize` | **Implemented** | The size the window opens at, clamped into min/max |
| `windowResizability(.contentSize)` | **Implemented** | Fixed size: no sizing border, no maximize box, one track size |
| `windowResizability(.minSize / .maxSize)` | **Partial** | Stays resizable; the declared min/max ride the track sizes above |
| `defaultPosition` | **Implemented** | Placed at the normalized position within the target monitor's work area |
| `windowLevel` | **Partial** | Any non-`.normal`/`.base` level becomes `HWND_TOPMOST`; Win32 has no finer z-band vocabulary |
| `windowToolbarStyle`, `navigationSubtitle`, `windowStyle`, `menuBarExtraStyle`, restoration / launch / activation / background-drag behaviors, `windowManagerRole`, `allowsWindowInlining` | **Shim** | Parsed and reported once at window creation (`unsupportedWindowConfigurationModifiers`), never silently dropped |

### Environment / system flags

| API | Status | Behavior today |
| --- | --- | --- |
| `isLuminanceReduced`, `isSceneCaptured`, `isTabBarShowingSections` | **Shim** | Overrideable; not derived from OS |
| Most accessibility environment booleans | **Shim** | Readable/overrideable; only `accessibilityReduceMotion` affects retained animation creation |
| `privacySensitive` | **Shim** | Metadata; no OS capture exclusion |
| `colorSchemeContrast` | **Partial** | Derived from Windows high contrast via `SystemAppearanceSnapshot` (WM_SETTINGCHANGE/WM_SYSCOLORCHANGE); affects secondary foreground + hierarchical greys |
| `scrollDismissesKeyboard` | **Shim** | No software keyboard host |
| Dictation / writing tools / keyboard type / content type text metadata | **Shim** | Stored; not wired to IME policy |

**System appearance precedence:** app override (`preferredColorScheme`,
explicit `.environment(_:_:)` sets) > system snapshot (Windows high contrast,
light/dark preference, reduce motion — sampled at startup and on
`WM_SETTINGCHANGE`/`WM_SYSCOLORCHANGE`) > toolkit default. Snapshot fields
that are unavailable (e.g. undeterminable theme preference) leave the
existing environment value untouched.

### Visual / animation metadata without full runtime

| API | Status | Behavior today |
| --- | --- | --- |
| `transition`, `contentTransition` | **Shim** | No insertion/removal transition playback |
| `symbolEffect`, `symbolEffectsRemoved` | **Shim** | No symbol layer animation |
| `sensoryFeedback` | **Shim** | No haptics/audio |
| `matchedGeometryEffect` | **Shim** | Records metadata; no geometry interpolation |
| `visualEffect` / `visualEffect3D` | **Shim** | Stores identity-effect metadata |
| `scrollTransition` | **Shim** | No phase-driven scroll effects |
| `scrollIndicatorsFlash` | **Shim** | Metadata only; no timed flash |
| `onScrollGeometryChange` / phase / visibility observers | **Shim** | Closures stored; not dispatched |
| `scrollTargetBehavior` (paging / viewAligned) | **Shim** | Metadata; no deceleration behavior |
| `PhaseAnimator` continuous cycling | **Partial** | Initial phase renders; continuous/trigger advancement limited |
| `KeyframeAnimator` | **Partial** / **Shim** | API shape; not full keyframe timeline engine |
| Color effects (`brightness`, `contrast`, `colorInvert`, …) | **Shim** | Metadata; not applied by GPU path yet |
| `colorEffect` / `distortionEffect` / `layerEffect` / `Shader*` | **Shim** | Metadata only |
| Style enums that only change chrome profiles | **Partial** | e.g. many `listStyle`, `formStyle`, `menuStyle`, `groupBoxStyle` values map to retained shells or metadata, not protocol-based custom styles |
| `ignoresSafeArea` / `edgesIgnoringSafeArea` | **Shim** | Pass-through on client-area surface |
| `coordinateSpace` naming | **Shim** | Metadata boundary; simplified frame resolution |
| `LocalizedStringKey` / resource localization | **Shim** | Resolves to plain string; no table lookup |
| `EquatableView` / `.equatable()` | **Shim** | Renders content; no Equatable skip-rebuild |
| Binding `.transaction` / `.animation` | **Shim** | No transaction propagation into animation state |
| `@AppStorage` external observation | **Partial** | Reads/writes UserDefaults; does not observe external process changes |
| `DynamicProperty.update()` sweep | **Shim** | Marker only |

### Gestures / editing extras

| API | Status | Behavior today |
| --- | --- | --- |
| `onDelete` / `onMove` / `onInsert` / list edit affordances | **Shim** / **Partial** | Actions can be stored; UI affordances incomplete |
| Advanced `DropDelegate` / spring loading | **Shim** | Types present; limited OS integration |
| Command selectors (`onDeleteCommand`, `pageCommand`, …) | **Partial** / **Shim** | Source shape; host routing incomplete |

---

## Placeholder panels (not real integrations)

These APIs compile and paint a **non-interactive labeled panel** (or empty
chrome) so shared sources type-check. They are **not** product-ready features.

| API | Placeholder label (typical) |
| --- | --- |
| `Map`, `MapKitMap` | Map |
| `VideoPlayer`, `AVPlayerView` | Video Player / AVPlayer |
| `Camera` | Camera |
| `Live Photo` surfaces | Live Photo |
| `QuickLookPreview` | Quick Look |
| PDF preview surfaces | PDF |
| `WebView` | WebView |
| SceneKit / RealityKit-style views | SceneKit / 3D Model |
| `Chart` (+ chart axis helpers as chrome) | Chart |
| TipKit-style tip views | Tip |
| StoreKit product / purchase / App Store views | Product / Purchase / App Store |
| `LookAroundViewer` | Empty/non-hit panel chrome |
| `ShortcutsLink` | Minimal non-functional panel |

Related: `MapReader` / `MapProxy` accept builders but convert APIs return `nil`.
`Marker` / `Annotation` do not drive a real map.

---

## Unsupported native integrations

Do not expect these Apple/platform integrations on Windows retained runtime:

| Domain | Why |
| --- | --- |
| Native Win32 control hosting | Architecture is custom-rendered, not HWND-per-control |
| UIKit / AppKit / SwiftUI macOS runtime embedding | Separate platforms; shared **source**, not shared package |
| MapKit, AVFoundation video playback, Camera capture | Placeholder only |
| WKWebView / SafariViewController | Placeholder only |
| StoreKit, App Store review, In-App Purchase UI | Placeholders / no-op review action |
| PhotosUI / PHPicker | File dialog stand-in only |
| CloudKit, WidgetKit timelines as system widgets, App Intents | Scene/API shims only |
| visionOS ImmersiveSpace / Volume | Shims only |
| Full SF Symbols library + multicolor layers | Deterministic retained glyphs |
| Asset catalogs as on Apple platforms | Path/WIC + hex color-name fallbacks |
| UI Automation / VoiceOver parity | Core UIA provider implemented (read/invoke/focus); advanced patterns and live regions missing |
| Multi-window document architecture | Multi-window hosting implemented (coordinator); DocumentGroup remains a shim |
| Software keyboard / dictation | Not hosted |

`Link` / `openURL` **does** shell-open URLs on Windows via `ShellExecuteW` — that
is an intentional small native bridge, not a general native-control strategy.

---

## Rendering path honesty

| Path | Status | Notes |
| --- | --- | --- |
| `GPUIScene` → `D3D11BatchRenderer` | **Implemented** (default) | Presentation order from `paintOperations`; shadows, quads, paths, atlas glyphs |
| `RenderFrame` → `D3D11Renderer` | **Partial** (fallback / debug) | Primarily `fillRect` + `drawBitmap` |
| CPU screenshot rasterizer | **Implemented** | Raw scene/frame for CI/visual checks |
| Offscreen `drawingGroup` compositing | **Partial** | Temporary scenes must not poison outer `cachedScenePaintRange`; sub-scene carries the frame's glyph atlases, buffer clamped to the clip and area-capped (falls back to inline painting); the composited bitmap is cached on the node's paint key + clean subtree, so an unchanged group is not re-rasterized per frame |
| Text | **Partial** | Scene path: logical layout cache + DirectWrite glyph runs (not full shaped runs); frame path still bitmap-heavy |

---

## Same-source contract

Preserve this pattern for shared demo/app views:

```swift
#if canImport(SwiftUI)
import SwiftUI
#else
import WinSwiftUI
#endif
```

Rules of thumb for shared sources:

1. Prefer APIs marked **Implemented** or carefully scoped **Partial** above.
2. Avoid placeholder panels and no-op platform actions for behavior you ship.
3. Do not add Windows-only APIs to shared demo source to “fix” rendering bugs.
4. Treat style and environment enums as retained approximations unless noted.
5. Validate visuals with `scripts/demo-screenshot.ps1` and inspect
   `artifacts/demo-screenshot.png`.

---

## Quick “is this safe?” checklist

| Goal | Recommendation |
| --- | --- |
| Settings / dashboard UI | Safe: stacks, lists, forms, buttons, toggles, pickers, text fields, navigation stack, tabs, sheets |
| Custom drawing | Safe with limits: `Canvas`, shapes, gradients on scene path |
| Maps, video, web, charts, IAP UI | Not safe: placeholders only |
| Secondary windows via `openWindow` / `dismissWindow` | Safe within limits: coordinator-hosted independent windows for id/value-based `WindowGroup`s (`WindowCoordinatorTests`) |
| Settings scene / document architecture | Not safe as hosted products (`openSettings` and `DocumentGroup` remain shims) |
| Pixel-perfect macOS SwiftUI | Not the goal; use design/animation parity docs for constants only |
| Accessibility for AT | Core UIA tree readable with invoke + focus events; advanced patterns (Value/Text/Selection) not yet |
| Production Windows product shell | Safe within retained subset; keep host/renderer validation in the loop |

---

## Related docs

- [`docs/WinSwiftUI.md`](WinSwiftUI.md) — exhaustive surface + behavioral footnotes
- [`docs/Testing.md`](Testing.md) — validation commands
- [`docs/GPURenderingPipeline.md`](GPURenderingPipeline.md) — presentation pipeline
- [`docs/AnimationParity.md`](AnimationParity.md) — animation numeric parity
- [`docs/MacOSDesignParity.md`](MacOSDesignParity.md) — design constant parity
- [`README.md`](../README.md) — package overview and coverage summary

## Maintenance

Update this matrix when:

- A placeholder gains retained implementation
- A shim gains real runtime effect
- A partial control’s interaction model changes
- Hosting multi-window or native bridges are intentionally added

When in doubt, prefer under-claiming. Source compatibility is wide; retained
behavior is narrower and custom-rendered by design.
