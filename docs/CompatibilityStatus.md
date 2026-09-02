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

`SwiftWindowsCore`, `SwiftWindowsGraphics`, `SwiftWindowsLayout`, and
`SwiftWindowsScene` are independently packaged portable foundations. Their
platform host, clipboard, monotonic clock, offscreen surface, and backend
capability contracts are renderer-neutral; the CPU renderer needs no fake
window handle. On macOS the same demo source builds against native Apple
SwiftUI. The complete retained `WinSwiftUI` engine, Win32 host, native text,
accessibility bridge, and D3D11 presenter remain Windows-only. See
[`PlatformArchitecture.md`](PlatformArchitecture.md) for the precise matrix.

Detailed API notes live in [`docs/WinSwiftUI.md`](WinSwiftUI.md). Design and
animation numeric parity tables live in [`docs/MacOSDesignParity.md`](MacOSDesignParity.md)
and [`docs/AnimationParity.md`](AnimationParity.md).
The complete desktop SDK audit target is pinned separately in
[`SwiftUIBaseline.md`](SwiftUIBaseline.md); the implemented subset below does
not reduce that target or establish conformance to it.

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

These categories describe the current subset for settings-style and dashboard
composition in coordinator-managed, custom-rendered windows. Their stated
limits still apply; this is not the completed product in `goal.md`.

### App hosting — Implemented (multi-window via coordinator)

| API | Status | Notes |
| --- | --- | --- |
| `App`, `Scene`, `SceneBuilder`, `WindowGroup` | **Implemented** | Primary host path; static multi-scene declarations and availability checks preserve scene order and modifiers, and startup opens the first ordinary window scene. Ordinary WindowGroup builders construct fresh root content once per hosted window and preserve those values across that host's rebuilds; scene environments remain inherited. Explicitly replacing a configuration's content overrides its builder. Scene registration is not dynamically reconciled; this is not general State/StateObject lifetime conformance |
| `Window`, `WindowScene` | **Partial** | Configurations participate in coordinator hosting; full native scene-specific uniqueness and restoration semantics remain incomplete |
| Host loop / invalidation coalescing | **Partial** | The native-capable App path now separates the public main-dispatch entry point from a dedicated Win32 owner for HWNDs, messages, dialogs, and presentation. Copied requests and actual completion receipts connect that owner to the MainActor runtime. This source implementation still requires compilation and native input, UIA, modal, rendering, failure, and idle-wake qualification; it does not establish the dashboard loader's live load/retry/cancel workflow. Custom factories without native-owner capabilities retain the legacy synchronous loop, which does not service arbitrary MainActor jobs. See [platform ownership](PlatformArchitecture.md); historical failed experiments remain recorded in `goal.md` |

### Layout containers — Implemented / Partial

| API | Status | Notes |
| --- | --- | --- |
| `VStack`, `HStack`, `ZStack` | **Implemented** | Optional spacing (`nil` → retained default `0`) |
| `LazyVStack`, `LazyHStack` | **Partial** | Layout is virtualized: rows the scroll viewport plus a viewport of overscan cannot reach are placed but not laid out recursively, and are projected to accessibility as flagged placeholders with their real bounds. Construction is **not** — every row's node is still built and measured, so a long list costs O(rows) nodes (two per row for a simple row, pinned by `LazyStackVirtualizationTests`; deferring it needs a data-driven API, not a runtime change — `docs/GPURenderingPipeline.md`, "Why lazy construction needs an API", carries the source-verified blocker and "The shape the seam would have", the four-step design it would take). `onLayout` does not fire for a deferred row. Falls back to eager behaviour verbatim with no scrollable ancestor |
| `LazyVGrid`, `LazyHGrid` | **Partial** | Retained row/column stack layout from `GridItem` specs; not viewport-lazy |
| `Grid`, `GridRow` | **Partial** | Shared measured tracks, contiguous spans, full-width children, cell anchors and unsized flexible demand; standalone-row/default-spacing and general native solver parity remain open ([details](GridLayout.md)) |
| `Spacer`, `Divider`, `Group`, `EmptyView` | **Implemented** | |
| `ScrollView` | **Partial** | One primary axis; `.all` resolves to vertical. Indicators are macOS **overlay scrollers**: hidden at rest, revealed by a scroll or a flash, faded out after a beat — so a static screenshot shows no scrollbar, as a real macOS app does. `.scrollIndicators(.visible)` opts into the legacy always-on bar; `.scrollIndicatorsFlash(onAppear:)` / `(trigger:)` ride the same lifecycle pass `onAppear` does |
| `ScrollViewReader` / `ScrollViewProxy.scrollTo(_:anchor:)` | **Implemented** | Scrolls explicit `.id(...)` and implicit `ForEach` targets on either retained axis, including off-screen virtualized lazy-stack rows; preserves minimal-reveal behavior, explicit anchors, content-bound clamping, nested-reader isolation, and requests queued before the first or a later scene/frame layout. Captured transactions preserve authored animation timing and explicit suppression through deferred requests; retargeting starts from the presented offset, input interrupts motion, and lazy target refinement keeps the original deadline. `.scrollDisabled` suppresses input without blocking these programmatic requests. Internal chrome tags do not become scroll targets. Each scroll container supports one primary axis; reusing the same reader value in multiple runtimes safely disables its ambiguous proxy. Native animation and timing comparison remains unqualified |
| `List` | **Partial** | Flat data and builder-authored `ForEach` declarations now use a deferred source projection with bounded native viewport construction, keyed State/StateObject preservation, physical task retirement, logical UIA enumeration/realization, and guarded selection/scroll requests. Explicit static rows retain their existing eager construction and layout-virtualization route. Focused Windows checkpoints have compiled and run, but pending-replacement UIA settlement and some inactive-state cases still fail. Tree/opaque-container projection, nonidentity removal transitions, animated continuation integration, and other limits remain open; see [DeferredListConstruction.md](DeferredListConstruction.md) and [ListKeyboardNavigation.md](ListKeyboardNavigation.md). |
| `Form`, `Section` | **Partial** | Grouped-form layout is macOS-shaped: a 640pt content column centred in the window, rows as a two-column grid (one trailing-aligned label column shared across every section of the form, leading value column), section headers outside and above near-flat group boxes. Styles map to retained spacing/shells; the grid is `Form`-scoped and does not span arbitrary containers |
| `LabeledContent` | **Partial** | Label/value row; inside a `Form` it is the grouped-form row with the form-wide shared label column |
| `GroupBox`, `DisclosureGroup`, `ControlGroup` | **Partial** | Functional retained chrome; style enums are mostly visual profiles / metadata. `GroupBox` draws the grouped-container material (`ControlPalette.raisedSurfaceFill` / `raisedSurfaceRing`, `MacOSControlMetrics.GroupBox` geometry), so it resolves per appearance and matches a `Form` section box |
| `HSplitView`, `VSplitView` | **Implemented** | Draggable retained splitters with ratio / min extents |
| `OutlineGroup` | **Partial** | Expand/collapse tree via retained disclosure chrome |
| `Table` | **Partial** | Data + columns as retained header/row grid; not a native Windows list-view |
| `ViewThatFits` | **Partial** | First child whose intrinsic size fits canvas axes; no full proposal probing |
| `GeometryReader` | **Partial** | Reports its resolved slot: the proxy is seeded from the build canvas, then the runtime re-invokes the body against the frame layout actually gave it (capped at four convergence rounds). Coordinate spaces are simplified; safe-area insets are zero |

### Text, images, shapes — Implemented / Partial

| API | Status | Notes |
| --- | --- | --- |
| `Text` (string / verbatim / key) | **Partial** | Native glyphs preserve shrinking transforms and bidirectional placement; wrapped text measures at its allocated width, and weight modifiers preserve inherited fonts. Localization keys resolve to plain strings (no bundle tables) |
| `Text` date / format / attributed | **Partial** | Deterministic string resolution; rich runs / live timers incomplete |
| `Label`, `Image(systemName:)` | **Partial** | System icons render as real Segoe Fluent/MDL2 glyphs (native bitmap) with a drawn-vector fallback — never `?`; ~40 common SF Symbols mapped, variants/scale honored |
| `Image(_:)` named / file / resource | **Partial** | WIC PNG/JPEG/BMP; no full asset-catalog pipeline |
| Bitmap `Image.resizable()` | **Partial** | Ordinary stretch and a bounded cap/tile subset accept finite proposals while keeping one retained image and the original source pixels. Nonresizable images retain intrinsic sizing. Unsupported cap, center, source-region, and tile-phase inputs report typed failures. Full aspect-fit/fill negotiation, fractional/oversized caps, asset density/orientation, RTL mirroring, and native pixel conformance remain incomplete; see [bitmap sizing](BitmapImageSizing.md) |
| `AsyncImage` | **Partial** | Mounted `StateObject`/`task(id:)` ownership, per-host bounded fetch/decode admission, streamed byte limits, real cooperative cancellation, and source-checked MainActor phase publication replace global URL loaders and temporary files. Scale and the latest adopted transaction affect presentation without refetching a matching URL. Native phase completion and full network/image parity remain unqualified; see [bounds and validation scope](AsyncImageLoading.md) |
| Basic shapes (`Rectangle`, `RoundedRectangle`, `Capsule`, `Circle`, `Ellipse`, …) | **Implemented** | Fill/stroke/border through retained primitives |
| `LinearGradient` | **Partial** | Axis-aligned shape fills preserve authored intermediate colors, nonuniform stop positions, duplicate-position hard stops, transparent stops, and reversed endpoints on CPU, the D3D11 scene path, and both live frame-fallback presenters; promoted rectangular Canvas fills additionally preserve diagonal, inset, transformed, and rounded gradient vectors on the CPU and D3D11 scene paths |
| `RadialGradient`, `AngularGradient` | **Partial** | Retained shape fills preserve authored multistop colors, hard stops, opacity, unit-space centers, radial start/end radii, angular start/end angles and signed partial or reversed sweeps on CPU snapshots and native D3D11 GPU quads, including rounded/transformed/clipped surfaces; the legacy frame fallback degrades to a solid base color, and Canvas radial/conic path shading remains unavailable |
| `StrokeStyle` on any outline | **Partial** | Retained shape producers preserve authored width, cap, join, miter, dash and phase metadata. The scene route resolves border dashes through `BorderSegments` and custom-path dashes through `PathDashing`; legacy background-path commands preserve width/cap/join/miter but currently omit dash/phase. Exact `strokeBorder`, trim geometry and native parity remain unqualified |
| `UnevenRoundedRectangle` | **Partial** | Direct fill/border and retained interaction content shapes preserve four RTL-aware radii; public paths use circular corner arcs. Scene visual clips now carry the original rectangle and four radii through rectangular crops; this new CPU/D3D11 transport and its changed buffer ABI still require execution. Continuous corners, uniform shadow/outline and legacy frame fallbacks, nested rounded intersections, and other shape-composition limits remain open |
| `Canvas` + `GraphicsContext` | **Partial** | Scene-path drawing; `Path(_:)` / `Path(roundedRect:cornerRadius:)` / `Path(ellipseIn:)` build a fillable path without a `Shape`, and a convex fill is emitted as one unbroken span per row. Multistop linear-gradient path fills **and strokes** preserve authored stops, inset or diagonal endpoint vectors, and context transforms on the CPU and D3D11 scene paths; rectangle and rounded-rectangle gradient fills promote directly to instanced GPU quads while retaining diagonal/inset/transformed endpoints, rounded coverage, hard stops, transparency, and clips. Complex fills and gradient strokes retain the bounded cached CPU-path lane; the legacy `RenderFrame` fallback uses the first stop for gradient-shaded paths. Tagged `symbols:` resolve in the inherited environment and draw through scene-backed images; copied contexts share draw order with independent graphics state, and authored symbol affine placement is retained. See [Canvas symbols](CanvasSymbols.md) for bounds and unqualified native semantics. Full blend/filter/layer behavior, `withCGContext`, and radial/conic path gradients remain unsupported |
| `ContentUnavailableView` | **Implemented** | Retained empty-state chrome |

Canvas path fills honor the `FillStyle(eoFill:)` rule for solid and linear-gradient
paint, including retained placement and legacy frame degradation. The
`antialiased` flag and general shape/clip fill-style semantics remain incomplete;
see [Canvas fill rules](CanvasFillRules.md) for GPU promotion, cache behavior and
the precise limits.

Public `Shape.fill(_:style:)` also preserves `eoFill` when the authored style
is stored on the retained node that owns the background path: direct custom
shapes, leaf `AnyShape` wrappers and direct inset builders use the same scene,
CPU, cached D3D11 and legacy frame fill-rule routes. Ancestor `clipShape` style
metadata does not override the child's fill rule. Shape-path gradients still
use their existing first-stop color fallback; antialiasing is unchanged.
The producer follow-up assigns the complete fill/stroke bundle for
`TrimmedShape`, and routes active `AnyShape`/`InsetShape` paint through known
inset, erasure and transform wrappers to the shape owner. Padding remains
unpainted; the existing absolute inset-radius adjustment applies to that owner.
Unstyled wrappers still delegate, and active outer styling clears obsolete
gradient, rule and stroke fields. Arc assigns paint during construction and
updates geometry through a layout callback receiving the live retained node,
so layout does not restore captured inner paint or target a discarded node.
`ShapePaintProducerTests` covers public paint/ownership and callback controls.

Arc's layout callback stores normalized coordinates for the existing
border-inset paint rectangle, reading the live node's stroke width. Point axes
and arc radii use their respective renderer scales, so ordinary rectangular
layout does not scale actual coordinates twice or add the layout origin twice.
Collapsed inner dimensions retain an empty path rather than falling back to a
rectangular background. Public `Arc.path(in:)` still uses the supplied rectangle.
`ArcCoordinateTests` covers independent geometry and pixel oracles. All twelve
tests passed in the focused 350-case run on `3fb9e55`, after a fresh Quick build.
The run and generated registration files are captured; independent reconciliation
of those copies is tracked in [goal.md](../goal.md).
Arc is a repository utility, not a native Arc declaration in the pinned macOS
SwiftUI/SwiftUICore interfaces. Bordered or arbitrary view transforms and rotated
legacy-frame parity remain separate from ordinary layout and display scaling.

Transform decomposition now preserves a finite surviving second matrix column
when the first column is exactly zero and its recovered norm is representable.
This keeps `.scaleEffect(x: 0, y: 1)` from also collapsing the Y axis. Thirteen new
literal matrix/point controls await execution; the original UIA visibility test
is unchanged. The normal decomposition branch is unchanged. Nonzero first-column
norm underflow, unrepresentable norms and parallel nonzero rank-one columns
remain open, so this is not complete singular-transform support.

Partial `Path.trimmedPath(from:to:)` and retained `Shape.trim(from:to:)` now have
distance-based geometry implementations. Retained partial shapes measure their
resolved inner paint size before normalizing the result for presentation; empty
or rejected selections remain empty paths. At `a3dfc5f`, all 26 original portable
trimming tests, six added reversal controls and 12 retained trimming tests passed.
The sibling-allowance repair fixes the earlier retraced-quadratic rejection
without changing tolerances or limits. The complete 98-case shape/selection
cohort passed, and one fresh retained CPU gallery image was visually inspected;
neither establishes native parity or an approved baseline.
The rectangle/ordered-point-inset trim route now preserves point units through
erasure and resolves geometry at actual inner paint bounds, including full range.
Its eighteen new analytic/retained-pixel controls are not yet compiled or run;
the earlier results do not qualify this source. Bounds-dependent custom shapes,
nested trims, other inset shape composition, trim hit/clip behavior, animated
fractions and native parity remain unqualified; see [path trimming](PathTrimming.md).
Inset's existing `.inset(by:)` reconstruction can discard stored styling.
General path clipping, arbitrary custom component paint ownership, shape-path
gradient fidelity, dashes, antialiasing and native rendering parity remain separate.

### Controls — Implemented / Partial

| API | Status | Notes |
| --- | --- | --- |
| `Button` (+ roles, systemImage) | **Implemented** | Focus / press / activate lifecycle on retained chrome; disabled state blocks pointer and accessibility activation |
| `Toggle` | **Implemented** | Binding-backed switch; styles map to retained variants and expose their disabled accessibility state |
| `Picker` | **Partial** | Segmented, menu, inline, radio, wheel-style shells with appearance-aware control chrome; not native OS pickers |
| `Stepper`, `Slider` | **Implemented** | Binding writes with ranges / steps; sliders acquire retained keyboard focus, support keyboard adjustment, and expose disabled accessibility state |
| `ProgressView`, `Gauge` | **Partial** | Determinate / indeterminate retained chrome. Custom struct `ProgressViewStyle` bodies and configuration delegation passed a focused Windows run (38 new cases plus 133 preserved regressions); the existing primitive path is preserved. Class/enum style installation, full source conformance, automatic ticking, and native style behavior remain open. See [ProgressView styles](ProgressViewStyles.md) |
| `TextField`, `SecureField`, `TextEditor` | **Partial** | Focusable retained input; keyboard-layout-aware Unicode `WM_CHAR` entry with UTF-16 surrogate pairing, caret, grapheme/Unicode-aware Ctrl+Left/Right word movement, Ctrl+Shift word selection with bound affinity, character shift-selection, select-all, clipboard shortcuts, mouse-drag selection, IME composition (marked text, candidate window at caret; secure fields block copy/cut). Modified horizontal word-navigation keys reach focused text inputs even inside horizontal scroll containers. Inside a grouped `Form`, `TextField` **and** `SecureField` move their title into the form-wide label column and leave the well showing only an explicit `prompt`, as macOS does. Text-input controllers preserve unbound caret/selection, IME composition, and drag anchors across reconciliation while adopting current bindings; explicit selection bindings take precedence. Ordinary nonsecure inputs register accepted edit deltas with the inherited undo manager and route exact Ctrl+Z/Ctrl+Shift+Z/Ctrl+Y. Session-owned document bindings register one model inverse with an optional selection receipt; ordinary secure inputs do not store automatic history, and managed secure document input is unsupported. [TextInputUndo.md](TextInputUndo.md) records identity, programmatic-write, and lifecycle limits. TextEditor shares shaped visual fragments across Up/Down navigation, selection, pointer/IME geometry, and editor-owned keyboard caret reveal; Home/End use visual lines and Ctrl variants use document boundaries. [TextEditorNavigation.md](TextEditorNavigation.md) records affinity, viewport ownership, unsupported typography, and validation limits. Typing groups, full editor scrolling, UIA text patterns, and native parity remain unqualified |
| `DatePicker` | **Partial** | Graphical month/day selection with mounted browsing State, inherited calendar settings, range checks, retained buttons, and existing arrow increments; clock picking and native calendar/API parity remain open ([details](GraphicalDatePicker.md)) |
| `MultiDatePicker` | **Partial, not qualified** | Retained month browsing and multi-selection source compiles, but the first new control test terminates on a fatal `DateComponents` set error during calendar construction. All 32 new test outcomes remain unverified; ranges, native calendar focus, API availability, and visual parity remain open ([details](MultiDatePicker.md)) |
| `ColorPicker` | **Partial** | NSColorWell-shaped bezel (`MacOSControlMetrics.ColorWell`) with an inset swatch and the bordered-control hover/pressed ramp; palette keyboard cycle (default); native `ChooseColorW` dialog opt-in via `\.colorPickerUsesNativeDialog` |
| `Menu` | **Partial** | Retained popup: canvas-clamped placement, scrim/Escape dismissal, focus restore, deferred layering; not a native Win32 menu bar |
| `Link` | **Implemented** | Button that invokes `openURL` (ShellExecute on Windows) |
| `NavigationStack` / `NavigationView` / `NavigationLink` | **Partial** | Local push/pop + title chrome; not UINavigationController semantics. macOS puts the window title in title-bar chrome this stack does not own, so `.navigationTitle` renders as a *content pane* header — largeTitle 26, or title2 17 semibold under `.navigationBarTitleDisplayMode(.inline)` |
| `NavigationSplitView` | **Partial** | Horizontal columns + visibility; no adaptive breakpoint collapsing |
| `TabView` | **Partial** | Retained tab bar + page; limited platform tab features |
| `searchable` | **Partial** | Prepends retained search field; placement chrome differs by placement |
| `toolbar` / `ToolbarItem` | **Partial** | Compact retained command row; not a native title-bar toolbar |
| `sheet`, `fullScreenCover`, `popover` | **Partial** | Retained overlays: deferred layering, scrim dismissal, clamped placement, focus restoration (fullScreenCover: layering only); detents approximated; no native presentation |
| `alert` | **Partial** | Boolean, item, builder, and error overloads share retained chrome. Hosted alerts preserve background identity, use accepted-generation action/reset guards and `presenting:` snapshots, and restore focus only after accepted absence and retained build settlement. Scrim clicks do not dismiss. Raw clients require live attachment and lack hosted lifetime guarantees. Native callback ordering and visual equivalence remain unqualified. See [Retained alerts](RetainedAlerts.md) |
| `confirmationDialog`, `actionSheet` | **Partial** | Retained modal chrome: deferred layering, Escape/scrim dismissal, and focus restoration; precise native behavior remains unqualified |
| `contextMenu` | **Partial** | Retained menu overlay: clamped anchor, scrim/Escape dismissal, focus restoration |
| `ShareLink` | **Partial** | Copies transferable items to clipboard — real file references (CF_HDROP) for file URLs, absolute strings otherwise (not system share sheet) |
| `PasteButton` | **Partial** | Delivers supported clipboard text and URLs; `.fileURL` and `.url` consume complete Unicode `CF_HDROP` file lists, while overlapping accepted URL/text types are deduplicated. Plain-text web URLs remain `.url`-only |
| `PhotosPicker` | **Partial** | Opens file dialog; not Photos framework |
| `fileImporter` / `fileExporter` | **Partial** | Real Win32 open/save dialogs deliver filesystem URLs; a single `FileDocument` regular-file wrapper is serialized and written with Foundation's atomic-save option before export reports success. Export cancellation resets presentation without completion or writes. Native failures are distinct from cancellation, and retained requests use their own HWND. Owner/presenter revocation blocks stale IO and callbacks; normal reset preserves the captured completion. Legacy providers keep their existing arguments and cannot establish native ownership/error distinctions. Writable-type fallback is applied. Directory/package, multiple-document, ReferenceFileDocument/Transferable, and background-encoding parity remain open; unsupported export representations fail explicitly. See [FileDocument export](FileDocumentExport.md). Native dialog buffers remain valid throughout the call; import filters and Unicode multi-selection remain supported, with approximate category filters |
| `SettingsLink` / `RenameButton` / `EditButton` | **Partial** | Buttons wired to environment actions / edit mode where present |

### Modifiers commonly safe

| Category | Status | Examples |
| --- | --- | --- |
| Sizing / padding / background / overlay / border / corner / clip | **Implemented** / **Partial** | `frame`, `padding`, `background`, `overlay`, `border`, `cornerRadius`, `clipped`, basic `clipShape` |
| Color / font / line limit / opacity / hidden / zIndex / offset / 2D scale & rotation | **Implemented** / **Partial** | Propagates via `ViewBuildContext` / node transforms |
| Interaction | **Implemented** / **Partial** | `onTapGesture`, `onHover`, `disabled`, inherited `\.isEnabled`, `focusable`, `@FocusState`, primary-touch and mouse routing, double-click presses, drag-to-focus, capture-loss cancellation, keyboard shortcuts on activation |
| List row chrome | **Partial** | Separators, insets, backgrounds, selection styling. `.automatic` / `.plain` / `.inset` paint a `textBackgroundColor` body; `.inset` rounds and rings it and insets its rows into it, and stripes replace row rules rather than joining them |
| Animation (retained properties) | **Partial** | Opacity, background, explicit frame dimensions and 2D transforms; value-triggered `animation`, scoped transactions and in-flight continuity across unrelated rebuilds. Springs use damped physical timing. Delays, repeats, completion criteria and arbitrary `Animatable` data remain incomplete |
| Retained view identity | **Partial** | Reconciliation distinguishes concrete view types, builder positions and branches, auxiliary builder roles, and typed Hashable IDs. Keyed rows retain their nodes through reordering without relying on description strings; type or branch changes replace them. Type erasure and flattened fragments preserve those boundaries without extra layout nodes. Ordinary State now uses these paths for ownership; modifier-kind erasure and complete specialized-container lifetime remain incomplete |
| State wrappers | **Partial** | Ordinary `@State` and `@StateObject` in custom struct views belong to their mounted identity and host, survive reconstruction and keyed reordering, and retire with their generation. StateObject invokes its factory lazily for a new owner/slot and observes even projection-only use; supplied instances intentionally remain aliases. Escaped bindings retain the last readable value but reject writes after removal or close. Private/nested struct dynamic properties install before body evaluation through typed reflection metadata. Other wrappers retain their legacy mechanisms. Metadata limits, unmounted App/Scene ownership, inactive opaque bodies, and native lifetime/transaction qualification remain open; StateObject's mutable setter and projected-self API remain nonnative extensions. See [MountedState.md](MountedState.md) |
| `UndoManager` | **Partial** | Main-actor action stacks support weak targets, target-specific removal, reciprocal undo/redo registration, action names, and nested registration disabling. Reentrant replay is refused and dead targets are pruned. Ordinary nonsecure editors register accepted deltas; explicit document-session bindings register one model inverse instead, with selection attached to that action's receipt. Focused keyboard fallback validates before consumption. Native Edit-menu integration, grouping, and full Foundation behavior remain incomplete; see [TextInputUndo.md](TextInputUndo.md) |

---

Mounted `onChange` also uses the host's typed view identity and retires its
history on removal. Its accepted actions run after tree adoption under the
captured transaction; discarded candidates do not publish observations. Raw
components without a mount coordinator do not provide this lifetime. Native
scheduling parity remains unqualified, and the separate preference/task-ID
adapters still use their older bookkeeping. See
[MountedOnChange.md](MountedOnChange.md).

## Partial (usable, but not SwiftUI-complete)

Use these when you accept retained approximations.

| Area | What works | What does not |
| --- | --- | --- |
| **Text system** | Readable labels, scaling, line limits, minimum scale factor; nested dynamic-type bounds agree across retained text, `@Environment`, and `@ScaledMetric` | Full font shaping, rich attributed runs, true localization catalogs, live `Text` timers |
| **Source builders / geometry** | Inherited `@ViewBuilder` bodies with empty, concrete/opaque single, multiple, optional and conditional content; explicit-return bodies retain ordinary Swift semantics; WinSwiftUI geometry values at its drawing boundary | Focused checks still fail for some mounted optional/conditional/iteration updates and projected List tags/state. Full native builder/container qualification remains incomplete; [ViewBuilder.md](ViewBuilder.md) records remaining composition boundaries and Windows-only array/loop behavior. Co-imported Foundation CGRect/CGSize can be ambiguous or differ from WinSwiftUI's current aliases; qualified integration fixtures do not establish Foundation geometry interoperability |
| **SF Symbols** | Named glyph path + limited variants / rendering modes | Multi-layer multicolor symbols, variable values, animated symbol effects |
| **Scrolling** | Vertical/horizontal native-wheel and drag offset, indicators, rendered keyboard glides and edge bounce, scoped `ScrollViewReader.scrollTo`, and geometry/phase/visibility callbacks sampled from retained presentation. Native wheel streams do not receive duplicate synthetic inertia; runtime-owned momentum uses elapsed-time integration | True two-axis scroll, paging / view-aligned deceleration, target-visibility collection callbacks, binding-driven `scrollPosition`, and native-reference qualification of observation timing/thresholds |
| **Gestures** | Tap, timed long-press with logical movement limits and cancellation, primary-touch and mouse drag mapped to the same pointer lifecycle. Long-press attempts survive retained reconciliation and finish once; GestureState cleanup preserves newer reentrant updates | Native-reference callback ordering, multitouch gesture arbitration, full gesture composition, simultaneous value streaming, and general mounted GestureState lifetime |
| **Focus** | Focus rings, `@FocusState`, activation | Dynamic `@FocusedValue` retargeting as focus moves; environment `isFocused` live transitions |
| **Drag and drop** | API + metadata on nodes; OS file drops (WM_DROPFILES) delivered to `onDrop` destinations as file URLs | Full delete/reorder/drop affordances, drag-over highlighting, OLE drag sessions |
| **Accessibility** | Metadata on `ViewNode` + derived `AccessibilityElementProjection` + Win32 UI Automation provider (`WM_GETOBJECT`, fragment tree, transform-aware/offscreen bounds, disabled-safe InvokePattern, non-password editable ValuePattern, checkbox/switch TogglePattern, List/Table SelectionPattern + SelectionItemPattern, and VirtualizedItemPattern realization); default control traits, secure-field `IsPassword`, focus/structure events, and an explicit live-region announcement bridge | Rich TextPattern/text ranges, automatic live-region observation, fine-grained structure-changed events, and advertised multi-selection container metadata |
| **Materials / blur** | Separable-Gaussian backdrop blur on CPU and D3D11, including a shared wide-radius reduction chain. Contained, even-origin, 1:1 plain drawing/compositing groups read the enclosing backdrop at each occurrence through replacement and replay. Their 25 new CPU/D3D11 tests passed in the isolated material run and were included in the successful joined local Full run at `a2cad23`. Material-dependent content blur now has source implementations for separate foreground/replacement coverage, nested sources, full halos and deferred clips; material-free content blur keeps its bitmap cache | The new content-blur CPU/GPU tests and migrated historical smoothing assertion are **uncompiled and unrun** in this packet. Independent color-effect/Canvas boundaries, unsupported group mappings, rotated-material approximation, native modifier-order/edge/opacity parity, and performance remain open. A blurred scroll view's own indicator stays sharp. Dependent pass budgets reject explicitly; the old material-free oversize path retains its hard-edged fallback and still draws deferred headers |
| **Blend / drawing groups** | Authored blend-mode metadata only — ordinary primitives composite source-over, gated by `CPUGPUBlendModeContractTests`. Backdrop materials and admitted current-target group images separately replace covered destination pixels to preserve translucent alpha | Separable blend modes on the GPU; general drawing-group mappings, opaque/color-mode options, and full SwiftUI drawing-group semantics. The bounded group route has isolated CPU/D3D11 test evidence, not native-reference or performance qualification |
| **2D transforms** | Translation, uniform scale and rotation lower onto the scene contract; a `rotationEffect` card draws rotated on both backends, and so does everything in it — shadows, text, images, `Shape` backgrounds and `Canvas` content all turn, and a rotated `.clipped()` clips to the turned shape (an offscreen pass composited back rotated) for both the eye and the pointer; ancestors compose before descendants, and the pointer inverse follows; a mirror (`scaleEffect(x: -1)`, `flipsForRightToLeftLayoutDirection`) survives composition as a reflection, so a mirrored subtree's descendants and its pointer inverse mirror with it | Shears, mirrors and non-uniform scales degrade to the axis-aligned bounding box, so a mirrored subtree's *content* is placed mirrored but not itself mirrored (text stays readable, an image is not flipped); the fallback frame renderer has no rotation encoding at all, so under it a rotated subtree draws — and clips — as its bounding box; a rotated clip whose buffer is past the offscreen budget falls back to the same box |
| **3D transforms** | Z-axis rotation maps to 2D; metadata stored | Full 3D projection pipeline |
| **Color effects / shaders** | Ordered brightness, contrast, inversion, multiply, saturation, grayscale, hue, and luminance-to-alpha effects on isolated subtrees. CPU and D3D11 execute the same scene image-pass contract; the D3D11 effect path keeps the child scene and filter on the GPU | Custom shader compilation, effect-parameter animation, complete color-space qualification, and full SwiftUI drawing-group/blend semantics |
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
| `openWindow` / `dismissWindow` | **Implemented** (default routing) | Coordinator opens independent windows (own host/runtime/renderer) for id- and value-based WindowGroups; dismiss requests close of the calling scene's window or matches by id/value. Ordinary requests respect the current `windowDismissBehavior` before native teardown; destructive dismissal transactions and document save decisions remain unsupported |
| `openSettings`, `SettingsLink` | **Implemented** for coordinator hosts | Opens the first declared Settings scene on demand, reuses its existing window, and requests restore/foreground activation. Closing permits reopening. Windows can decline foreground activation; no duplicate is created. No declared Settings scene or standalone host means no default routing |
| `requestReview` | **Shim / no-op** (default) | No StoreKit / Microsoft Store review prompt |
| `Settings` | **Partial** | Real on-demand singleton alongside ordinary window scenes, with per-window runtime, renderer, environment, and scene-storage scope. Automatic native Settings menus, Settings-only startup, dynamic scene changes, and full scene restoration remain unsupported |
| `DocumentGroup` | **Partial, native activation disabled** | Typed declaration factories, standard writable `configuration.$document`, real regular-file UTF-8 open/save, per-window session/checkpoint/undo ownership, and deterministic close intents exist behind explicit internal headless services and host hooks. Native activation fails closed until final close approval and deferred delivery are integrated; the default application is unchanged. Known reference documents reject activation. See [DocumentSessions.md](DocumentSessions.md) |
| `MenuBarExtra` | **Shim / Partial** | Types and configs exist; not a first-class hosted scene product |
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
| `windowDismissBehavior` | **Partial** | `.disabled` disables native Close and refuses titlebar/system/programmatic `WM_CLOSE` requests before teardown. `.enabled`, `.automatic`, and modifier removal restore ordinary close. Managed preflight flushes at most one pending observed batch and captures bounded layout/policy evidence; a final package authority checks that same receipt after all delegate votes. Queued builds, stale geometry, changed participants, and unavailable evidence cannot authorize destruction. Enclosing declarations win, then source order. The owned deferred-close capability does not activate document scenes. Conflicting-modifier native precedence, silent raw layout-metadata mutation, destructive dismissal transactions, and unsaved-document workflows remain unqualified. See [Window close ownership](WindowClose.md) |
| `windowToolbarStyle`, `navigationSubtitle`, `windowStyle`, `menuBarExtraStyle`, restoration / launch / activation / background-drag behaviors, `windowManagerRole`, `allowsWindowInlining` | **Shim** | Parsed and reported once at window creation (`unsupportedWindowConfigurationModifiers`), never silently dropped |

### Environment / system flags

| API | Status | Behavior today |
| --- | --- | --- |
| `isLuminanceReduced`, `isSceneCaptured`, `isTabBarShowingSections` | **Shim** | Overrideable; not derived from OS |
| Most accessibility environment booleans | **Shim** | Readable/overrideable; only `accessibilityReduceMotion` affects retained animation creation |
| `privacySensitive` | **Shim** | Metadata; no OS capture exclusion |
| `colorScheme` / `preferredColorScheme` | **Implemented** / **Partial** | Both the chrome and the *content* resolve per appearance. Control chrome reads `ViewBuildContext.controlPalette` (`ControlPalette`); text reads the semantic label ladder — `Color.primary`/`.secondary`/`.tertiary` are rungs that `resolvedForVisualEnvironment(colorScheme:contrast:backgroundProminence:)` turns into near-white or near-black, and the ambient foreground default is `.primary` rather than a literal white. The navigation band, tab bar, `Form`/`Section` boxes, `List` bodies and hairlines, the scroller thumb and the window backdrop all follow the appearance. Floating panels — menu, popover, sheet, alert, confirmation dialog, context menu, inspector, full-screen cover — sit on the appearance-resolved `elevatedSurface`, and `Table` chrome and the `searchable` field resolve from the palette too. Recognition of a semantic colour is by exact rung, so `Color.primary.opacity(0.5)` is an app-authored colour and does not adapt — ask for `.secondary` instead. Resolution is a property of the *colour*, not of the slot it lands in: `.background(.quaternary)` and `.background(Color.red)` resolve exactly as the foreground path does, so a semantic scrim darkens a light window and lightens a dark one (it used to reach the panel unresolved and paint a white bar on a light page). The saturated system colours adapt too: `Color.red`/`.orange`/`.blue` and their ten siblings hold Apple's *light* sRGB value and resolve to the published dark twin (`#FF9500` → `#FF9F0A`) in a dark appearance, matching a dynamic `NSColor`; see the pair table in docs/MacOSDesignParity.md. Matching is on RGB, so a system colour keeps adapting through `.opacity(_:)`, and the tint is exempt — control accents come from `ControlPalette`. Render either appearance with `swift-windowsui-snapshot --appearance light\|dark`. The light appearance is pixel-gated, not only unit-tested: the gallery gate carries a `light-` tier (19 entries — grooves, container surfaces, and the hover/pressed/focus ramps on white) alongside its dark twins. |
| `colorSchemeContrast` | **Partial** | Derived from Windows high contrast via `SystemAppearanceSnapshot` (WM_SETTINGCHANGE/WM_SYSCOLORCHANGE). Active contrast themes sample the actual native window/text/control/highlight/disabled/link colors through `GetSysColor`; inherited environments propagate those roles into `ControlPalette`, semantic text/background colors, selection, borders, and the default accent. Dark/light identity follows the chosen theme's actual background while explicit app appearance/tint overrides still win |
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
| `scrollIndicatorsFlash` | **Partial** | Reveals the retained overlay scroller and lets the runtime fade it back out; on-appear behavior follows the retained view lifecycle |
| `onScrollGeometryChange` / `onScrollPhaseChange` / `onScrollVisibilityChange` | **Partial** | Real callbacks after retained paint, derived-value deduplication, presented offsets, nested scroll ownership, transformed rectangular clipping, and history across rebuilds. Native initial-delivery timing, precise phase cadence, and threshold semantics still require reference comparison; visibility is geometric, not sibling-occlusion testing |
| `onScrollTargetVisibilityChange` / `onScroll` | **Shim** | Metadata only; callbacks are not dispatched |
| `scrollTargetBehavior` (paging / viewAligned) | **Shim** | Metadata; no deceleration behavior |
| `PhaseAnimator` continuous cycling | **Partial** | Initial phase renders; continuous/trigger advancement limited |
| `KeyframeAnimator` / `keyframeAnimator` | **Partial** | Typed linear, cubic, spring and move timelines with managed retained playback, interruption and bounded repeats. Unmanaged durable playback and native curve, lifecycle, Reduce Motion and long-gap parity remain incomplete; see [KeyframeAnimations.md](KeyframeAnimations.md) |
| Color effects (`brightness`, `contrast`, `colorInvert`, …) | **Partial** | Ordered effects apply to the composited subtree, including glyphs, images, paths, shadows, and nested effect passes. Contrast and saturation use 1 as identity. Native color-space conformance, animated parameters, and surrounding group/blend semantics remain incomplete |
| `colorEffect` / `distortionEffect` / `layerEffect` / `Shader*` | **Shim** | Metadata only |
| Style enums that only change chrome profiles | **Partial** | e.g. many `listStyle`, `formStyle`, `menuStyle`, `groupBoxStyle` values map to retained shells or metadata, not protocol-based custom styles |
| `ignoresSafeArea` / `edgesIgnoringSafeArea` | **Shim** | Pass-through on client-area surface |
| `coordinateSpace` naming | **Shim** | Metadata boundary; simplified frame resolution |
| `LocalizedStringKey` / resource localization | **Shim** | Resolves to plain string; no table lookup |
| `EquatableView` / `.equatable()` | **Shim** | Renders content; no Equatable skip-rebuild |
| Binding `.transaction` / `.animation` | **Partial** | Transaction-aware setters and writes through dynamic-member, collection, and optional projections carry their configured transaction into synchronous state observation and retained animation. Nested writes restore ambient context; explicit nil animation suppresses motion. Conflicting ambient/binding precedence and deferred updates still need native reference qualification (`BindingTransactionTests`) |
| `@AppStorage` external observation | **Partial** | Reads/writes UserDefaults; does not observe external process changes |
| `DynamicProperty.update()` sweep | **Partial** | Installs supported struct declarations into a copy before body evaluation, updates nested properties before their parent, and diagnoses unsupported owning/immutable/class/enum or ambiguous metadata. Trusted non-owning leaves keep legacy behavior; full wrapper and toolchain conformance remain open |

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
| UI Automation / VoiceOver parity | UIA fragment, Invoke/Value/Toggle/Selection/SelectionItem/VirtualizedItem patterns and explicit live-region events implemented; rich text ranges, automatic announcements, and complete VoiceOver equivalence remain unsupported |
| Multi-window document architecture | Typed per-window document sessions have explicit headless hosting; native DocumentGroup activation, final close delivery, and the complete application workflow remain blocked |
| Software keyboard / dictation | Not hosted |

`Link` / `openURL` **does** shell-open URLs on Windows via `ShellExecuteW` — that
is an intentional small native bridge, not a general native-control strategy.

---

## Rendering path honesty

| Path | Status | Notes |
| --- | --- | --- |
| `GPUIScene` → `D3D11BatchRenderer` | **Implemented** (default) | Presentation order from `paintOperations`; shadows, quads, paths, atlas glyphs |
| `RenderFrame` → `D3D11Renderer` | **Partial** (fallback / debug) | Primarily `fillRect` + `drawBitmap`; both its Direct2D presenter and pure D3D11 fallback preserve axis-aligned intermediate linear-gradient stops, while radial/conic gradients, nonuniform corners, rotated geometry, and soft shadows remain limited |
| CPU screenshot rasterizer | **Implemented** | Raw scene/frame for CI/visual checks |
| Offscreen `drawingGroup` compositing | **Partial** | Ordinary groups retain the bounded bitmap cache and replay protections. Admitted material groups retain a current-target scene source and final-attempt glyph atlases. A dependent group inside the new content-blur path returns foreground plus replacement coverage instead of baked parent pixels; structural and occurrence budgets reject before allocation. The historical isolated group run passed 213 cases with one content-blur skip, and joined local Full passed at `a2cad23` with that skip still present. Those results qualify their source snapshots, not the new content-blur implementation. New content-blur execution, unsupported mappings, independent capture semantics, opaque/color-mode options, and native-reference/performance qualification remain open |
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
| Settings scene | Hosted alongside ordinary windows; use `SettingsLink` or `openSettings`, with the lifecycle and menu limits above |
| Document architecture | Internal real-file session stage only; default/native DocumentGroup activation is disabled. See [DocumentSessions.md](DocumentSessions.md) for supported value documents and required native integration |
| Pixel-perfect macOS SwiftUI | Not the goal; use design/animation parity docs for constants only |
| Accessibility for AT | UIA tree, focus/offscreen state, secure-aware Value, Toggle, Selection/SelectionItem, virtualized-row realization, and explicit live-region events; rich TextPattern and automatic announcements remain unsupported |
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
