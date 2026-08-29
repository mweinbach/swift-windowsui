# Goal: recreate SwiftUI on Windows

Build a complete, production-quality Swift UI stack that lets developers write
SwiftUI applications for Windows: a full rendering engine, correct declarative
layout and state, smooth animations, accessible controls, and reusable UI
templates. The result should be suitable for shipping real desktop software.

This document describes the destination, not what is implemented today.
[CompatibilityStatus.md](docs/CompatibilityStatus.md) records current support;
[StabilizationRoadmap.md](docs/StabilizationRoadmap.md) defines incremental
delivery work. Full desktop SwiftUI compatibility is now a long-term goal.
The smaller scope of an initial release does not cap that goal.

## 1. The application developer's experience

An app author should be able to compose ordinary SwiftUI views, bind them to
application state, add animation and navigation, and ship the result on Windows.
The same application and view source should build against Apple SwiftUI on
macOS and `WinSwiftUI` on Windows, with conditional imports and explicit
adapters for services that differ between operating systems.

Compatibility includes source syntax, state lifetime, layout, rendered output,
interaction, motion, and accessibility. A familiar initializer that compiles
but ignores its arguments does not satisfy the goal.

- Pin the public desktop SwiftUI API and SDK version used as the reference for
  each compatibility milestone. Expand that baseline deliberately as the
  framework evolves; do not make completion depend on an undefined moving
  target.
- Implement the full public desktop API and behavior surface of that baseline.
  Partial implementations, metadata-only modifiers, no-ops, and placeholder
  panels remain tracked gaps.
- Reproduce documented SwiftUI behavior and validate observable behavior with
  small reference applications where the documentation leaves room for doubt.
- Record Windows adaptations explicitly: window chrome, keyboard conventions,
  system fonts, file dialogs, accessibility services, and OS-specific features.
  An adaptation must preserve the app's intended behavior.
- Keep visual conformance fixtures separate from the demo's own design tokens.
  A custom demo theme is a valid style, but is not proof of default SwiftUI
  visual parity. Font and asset substitutions must be stated in comparisons.
- Keep platform-specific integrations behind adapters. Windows applications
  must not require Apple's runtime or private frameworks, and shared app code
  must not accumulate Windows-only rendering workarounds.

## 2. A complete rendering engine

The engine must draw every visual construct required by the compatibility
baseline, with consistent results during composition, animation, resizing,
scrolling, and changes in display scale.

- **Geometry:** rectangles, independent corner radii, ellipses, arbitrary
  paths, curves, fills, strokes, trimming, dashes, joins, caps, fill rules,
  tessellation, antialiasing, and pixel alignment at fractional DPI.
- **Paint:** solid colors, linear/radial/angular gradients with authored stops,
  images, symbols, glyphs, borders, shadows, blur, materials, and visual effects.
- **Composition:** nested clips and masks, transforms and projections, opacity,
  blend modes, drawing/compositing groups, offscreen layers, and correct
  ordering when primitive types are mixed. Group semantics must match the API
  rather than accidentally applying an effect once per child.
- **Color and images:** explicit color-space and alpha conventions, correct
  transparent edges, scaling and interpolation, asset decoding, asynchronous
  loading, and bounded image/texture caches.
- **GPU execution:** efficient D3D11 batching, glyph and image atlases, reusable
  buffers, bounded uploads, resource lifetime management, and reuse of clean
  subtrees. Common UI primitives must execute directly on the GPU; the normal
  hardware path must not rasterize the whole window in software each frame.
  Batching must never change visible draw order.
- **Reference rendering:** a deterministic CPU path for offscreen rendering,
  screenshots, and backend comparison. Supported features must agree with GPU
  output within documented tolerances; CPU screenshots alone are not evidence
  that the live GPU path is correct.
- **Resilience:** resize and DPI changes, device loss, atlas eviction,
  allocation failures, window closure, and backend recovery must keep resources
  valid and restore usable output through bounded recovery where possible.
  Unrecoverable failures must be explicit and diagnosable, without corruption
  or infinite retries. Software presentation must remain a real fallback with
  clearly reported capabilities and performance limits.
- **Extensibility:** new effects and backends use explicit scene and capability
  contracts. A GPU-specific feature must declare a tested fallback or a visible
  unsupported result instead of silently disappearing.

The completed engine should handle application graphics through reusable
primitives. Individual controls and templates must not need private drawing
paths or special cases in the renderer.

## 3. Correct state, layout, and UI primitives

The retained runtime must preserve the meaning of the declarative view tree as
data, identity, environment, and available space change.

- Preserve view identity and state across rebuilds, keyed collection changes,
  navigation, transitions, and multiple windows. Observation, bindings,
  preferences, tasks, cancellation, and lifecycle callbacks must have defined
  behavior and avoid unnecessary whole-window rebuilds.
- Implement layout proposals, measurement, placement, intrinsic sizing,
  min/ideal/max frames, layout priority, alignment guides, text baselines,
  coordinate spaces, anchors, safe areas, and custom layouts coherently.
- Supply real stack, grid, overlay, split, scroll, list, table, form, tab, and
  navigation primitives. Their semantics must compose at compact and expanded
  sizes without control-specific layout workarounds.
- Make lazy collections lazy in construction and realization as well as
  layout and paint. Visible work and retained row resources should scale with
  the viewport plus a bounded prefetch region, while preserving state,
  programmatic scrolling, keyboard selection, and accessibility.
- Make hit testing, focus, gestures, capture, clipping, and accessibility agree
  with the geometry that is actually presented, including animated transforms.
- Support reusable custom `View`, `ViewModifier`, `Shape`, layout, control style,
  and animation implementations through public APIs. App authors should not
  need to reach into `ViewNode` or renderer internals to extend the toolkit.

## 4. Smooth, correct animation

Motion must be part of the runtime's state and presentation model. It must
remain correct while views rebuild, input arrives, layout changes, and a window
moves between displays.

- Support implicit and explicit animation, scoped transactions, timing curves,
  physical springs, delays, speed changes, repeats, reversals, transitions,
  matched geometry, keyframes, phases, and animatable custom values in the
  chosen SwiftUI baseline.
- Preserve animation scope and start times through reconciliation. Retarget
  from the current presented value, preserve velocity where the animation
  requires it, and avoid jumps, restarts, snapping, or stale completion events.
- Animate geometry, color, opacity, transforms, clipping, drawing parameters,
  text changes, and control states consistently. Insertion and removal must
  remain correct under interruption and rapid state changes.
- Deliver responsive wheel and precision-touchpad scrolling, inertia,
  programmatic scrolling, drag interactions, and navigation transitions.
- Use one monotonic time model and refresh-aware scheduling. Render when
  input, invalidation, or active motion requires it; settled windows must not
  keep pumping frames. Minimized and occluded windows must not waste work.
- Respect reduced motion, accessibility settings, and cancellation. State and
  focus must reach the same valid outcome when motion is shortened or disabled.
- Test intermediate frames and interruption sequences, not just final values.
  Synthetic-time tests prove semantics; captures from the app's own rendering
  path verify rendered progression, and live presentation telemetry verifies
  frame delivery and pacing.

The hardware-rendered experience targets sustained 60 Hz on the published
baseline hardware and native 120/144 Hz pacing on qualified hardware. On the
declared template and stress workloads, target p95 active-frame work within one
refresh interval (16.7 ms at 60 Hz; 8.3 ms at 120 Hz), fewer than 1% missed
presentation deadlines during at least 30 seconds of steady interaction, and
p95 input-to-present latency within two refresh intervals. These are future
acceptance targets, not claims about current performance or the software fallback.

Qualification must publish the hardware, resolution, DPI, build configuration,
workload, warm-up, duration, and p50/p95/p99 results. Measure composition,
reconciliation, layout, text, paint, upload, GPU execution, and presentation;
include cold startup and first interaction separately. Use controlled hardware
runs for timing acceptance and deterministic structural budgets in normal CI,
as described in [PerformanceBudgets.md](docs/PerformanceBudgets.md).

## 5. Complete text, input, and accessibility

Text is a foundational subsystem, including layout and editing rather than
only drawing glyphs.

- Provide shaping, font fallback, emoji, rich text and styled runs,
  bidirectional text, Unicode grapheme boundaries, wrapping, truncation,
  baseline alignment, selection, caret geometry, localization, and right-to-left
  layout.
- Support native IME composition and candidate placement, clipboard operations,
  undo/redo, keyboard navigation, multiline editing, secure input, and text
  accessibility with consistent measurement and painting.
- Keep secure-field contents out of clipboard copy/cut, accessibility values,
  and diagnostic output.
- Integrate keyboard, mouse, precision touchpad, touch, pen, drag and drop,
  command routing, focus traversal, and gesture composition through the retained
  tree.
- Project semantic controls into Windows UI Automation with working actions,
  text/range/selection patterns, meaningful notifications, virtualized-item
  realization, and correct bounds. Validate complete flows with Narrator.
- Honor live light/dark appearance, high contrast, system colors, text scaling,
  reduced motion, and display changes. Keyboard-only and assistive-technology
  users must be able to complete the same workflows as pointer users.

## 6. A complete control and presentation library

Ship a coherent library of text and image views, shapes, buttons, toggles,
pickers, sliders, steppers, progress indicators, gauges, menus, date/color
inputs, editable text, lists, tables, forms, navigation, and presentations.

Each control must include its relevant idle, hover, pressed, focused, disabled,
selected, invalid, loading, and empty states. Styles, environment values,
labels, accessibility, keyboard behavior, and animation must compose through
the public API. An attractive idle screenshot is only one acceptance case.

Sheets, popovers, alerts, confirmation dialogs, tooltips, context menus, and
navigation destinations must handle placement, clipping, ownership, dismissal,
focus restoration, and competing input correctly. Multiple windows, settings
scenes, document lifecycles, persistence, file operations, and shell integration
must behave like complete desktop application features.

Charts, rich media, embedded web content, maps, and other integrations need
working implementations or explicit optional adapters with capability checks.
They may ship separately, but a placeholder cannot satisfy an in-scope feature.
Apple-service-specific behavior without a Windows equivalent must remain an
explicit compatibility exception.

## 7. Reusable UI templates and reference applications

Ship an inspectable component gallery and a template library that developers
can use as starting points for applications. Templates should demonstrate
composition through public SwiftUI-shaped APIs and share reusable styles and
components. They must not introduce a second UI framework or hide engine bugs.

| Template | Required working behavior |
| --- | --- |
| Application shell | Sidebar, toolbar, tabs or split navigation, command palette, shortcuts, window sizing, and multiple windows |
| Dashboard | Cards, metrics, charts, live model updates, filters, responsive layout, and useful empty/loading/error states |
| Settings and forms | Grouped fields, validation, dirty state, save/reset, persistence, keyboard navigation, and appearance controls |
| Data browser | Search, sort, filtering, large virtualized lists/tables, selection, pagination where appropriate, and detail inspector |
| Document or editor | Open/save, editable content, selection, undo/redo, unsaved-change handling, and document windows |
| Media or file browser | Grid/list layouts, asynchronous thumbnails, loading failures, selection, preview, and drag and drop |
| Navigation and presentations | Master/detail flows, sheets, popovers, dialogs, contextual commands, and reliable focus restoration |
| Animation and drawing lab | Shapes, paths, gradients, materials, compositing, transitions, springs, keyframes, and interruptible gestures |

Every template must have real local model behavior, deterministic sample data,
documented extension points, and a complete interaction path. A fake save or
nonfunctional button is not a finished template. Network services may be
optional, but loading, failure, retry, and cancellation must be demonstrable.

Each template must build from documented instructions, run on Windows, and
build from the same shared view source on macOS against native SwiftUI where
its declared adapters are available. Cover multiple window sizes, appearances,
DPI scales, keyboard flows, and accessibility settings. The gallery should
expose source, supported behavior, limitations, and reproducible render states.

## 8. Architecture that supports the whole product

Keep one primary application path:

```text
SwiftUI-shaped app source / WinSwiftUI
    -> WinSwiftUIWindowHost + ComponentHost
    -> RetainedViewRuntime / ViewNode
    -> GPUIScene
    -> selected rendering backend
    -> native Windows presentation
```

- `Runtime.swift` remains the source of truth for retained layout, interaction,
  clipping, and animation; UI-facing APIs and mutation remain main-actor-centric.
- `GPUIScene.presentationOrder()` remains the draw-order authority. Layers and
  their `paintOperations` determine presentation; `paintRecords` are replay
  data and primitive-family batches are storage/optimization surfaces.
- `WinSwiftUI` remains renderer-neutral. The executable composition root
  selects the D3D11 backend through `App.renderBackendFactory()`.
- Extend `ViewBuildContext` and inherited environment propagation instead of
  introducing global UI state. Preserve tested dependency direction.
- Use Win32 for native host and OS services while the retained engine draws
  the UI. `FoundationApp`, `SwiftWindowsScene`, native widget wrappers, and
  embedded web content do not become replacement primary rendering paths.
- Keep Core/Graphics/Layout/Scene and offscreen rendering portable. A second
  retained-runtime OS host is a separate deliverable, not a prerequisite for
  recreating SwiftUI on Windows or something neutral interfaces alone prove.
- Use `extern/zed` only as a read-only architectural reference. Implement and
  validate the engine in this repository.

## 9. Tooling, delivery, and proof of completion

The deliverable is a versioned Swift package, rendering engine, Windows host,
control library, template catalog, documentation, and validation tools. A new
developer should be able to create, build, test, package, and run an app using
documented PowerShell/SwiftPM workflows without private setup knowledge.

Provide view/scene inspection, layout and invalidation diagnostics, animation
traces, frame and resource measurements, backend health reporting, and
actionable errors for unsupported behavior. Document supported Windows and
Swift toolchain versions, application deployment requirements, compatibility
changes, and migrations.

The long-term goal is complete only when these gates are met:

- [ ] The full public desktop API and behavior surface of the pinned SwiftUI
      baseline is audited, implemented, and conformance-verified. No in-scope
      partial implementation, shim, no-op, or placeholder remains. Only
      explicitly justified platform-service exceptions are permitted.
- [ ] Every in-scope primitive, control, layout, modifier, and animation has
      relevant semantic, interaction, accessibility, and visual coverage.
- [ ] Shared reference apps pass compilation and behavior checks on Windows
      and macOS; reviewed comparisons distinguish true regressions from
      declared font, theme, and platform differences.
- [ ] CPU and D3D11 output agree on the supported scene contract, including
      mixed primitive order, transparency, effects, clipping, and fractional DPI.
- [ ] Animation and scrolling meet the published hardware performance targets;
      resource use is bounded during long sessions, repeated navigation, large
      collections, and window creation/destruction.
- [ ] The template catalog completes its advertised workflows with keyboard,
      pointer, and assistive technology, including loading and failure states.
- [ ] GPU recovery, software fallback, monitor/DPI changes, IME, native dialogs,
      and accessibility pass documented real-machine smoke tests.
- [ ] Architecture checks, tests, builds, and reviewed visual regression gates
      pass on the exact release commit in hosted CI. Timing qualification and
      manual checks are recorded separately rather than inferred from CI.
- [ ] A clean-machine installation can build and deploy a documented sample
      app, and releases include compatibility notes and reproducible evidence.

Use the existing validation ladder in [Testing.md](docs/Testing.md), including
serial SwiftPM execution. Screenshots must come from raw retained-runtime
output through `swift-windowsui-snapshot`; motion evidence must come from the
app's rendering pipeline, not desktop or window captures. Add GPU execution
tests and native interaction checks wherever static CPU images cannot prove
the behavior. Generated evidence belongs under `artifacts/` or the OS temp
directory, and reviewed baselines must not update themselves to hide failures.

Deliver this goal in cohesive slices: implement a capability through the full
stack, demonstrate it in the gallery or a template, validate it, document its
support level, and then expand coverage. Interim releases can ship useful
subsets without being described as the completed SwiftUI-on-Windows product.

## 10. Execution record and acceptance detail

This section adds implementation and verification detail to sections 1–9. It
does not replace their requirements, reduce the public API baseline to the
currently implemented subset, or turn a local test pass into product completion.
Keep the nine completion gates above open until their complete evidence exists.
Record unverified behavior and external qualification separately from work that
can be implemented and tested in this checkout.

### Starting point: 2026-08-27

- Starting revision: `38e855d` (`docs: define complete SwiftUI on Windows
  product goal`), with a clean `main` worktree.
- Fresh `scripts/agent-check.ps1 -ContractsOnly` passed before implementation.
  This is architecture evidence only; no fresh Full, macOS, hosted-CI, manual
  accessibility, or hardware-timing result is implied by it.
- The current compatibility matrix is an implementation inventory, not the
  full desktop SDK audit required by gate 1. The SDK baseline, complete symbol
  inventory, and behavior-to-evidence mapping still need to be recorded.
- Concrete source gaps include unhosted `Settings` scenes, binding transaction
  modifiers that discard their arguments, scroll observers that discard their
  closures, and demo settings whose Save action only updates memory. Color
  effects also have incomplete propagation and parameter semantics. Closing
  these gaps does not close their broader product gates by itself.

### Evidence required for each unchanged completion gate

The fixed API audit baseline is the complete public desktop SwiftUI surface
in the **macOS 26.5 SDK supplied with Xcode 26.6**, including SwiftUICore
re-exports, using its Apple Swift 6.3 toolchain in Swift 6 mode. The audit
includes both arm64 and x86_64 desktop declarations. Apple's
[SDK requirements](https://developer.apple.com/xcode/system-requirements)
identify those release versions; the exact installation build identifiers,
compiler build string, native reference OS build, and inventory hashes still
require an actual Mac capture and review. The package's macOS 15 deployment
minimum does not restrict this API baseline to macOS 15. Future SDK releases
do not automatically change this pinned target.

[`docs/SwiftUIBaseline.md`](docs/SwiftUIBaseline.md) and
[`docs/swiftui-baseline.json`](docs/swiftui-baseline.json) record this scope.
`scripts/export-swiftui-baseline.ps1` captures unmodified public symbol graphs,
interfaces, availability and extension metadata, and provenance on the pinned
Mac; it rejects mismatched versions and does not silently reduce extraction
options. `scripts/test-swiftui-baseline.ps1` passed 70 assertions on synthetic
fixtures under Windows PowerShell. That result validates tooling, not an Apple
SDK inventory or behavior. The full declaration/overlay review, native export,
and conformance evidence remain open under gates 1–3.
Follow-up tooling checks passed 75 assertions after covering Apple's
driver-prefixed compiler version output and retaining cross-import overlay
declarations. The upstream exporter can skip unloadable overlay modules, so
even a successful capture explicitly leaves overlay completeness unverified
until reconciled with the public SDK interfaces.

The candidate-capture workflow now selects the pinned Xcode installation on
`macos-26-intel`, records the exact source revision and runner provenance,
and retains exporter output or failure diagnostics. It runs on demand or when
the baseline capture inputs change on `main`; ordinary source edits do not
trigger another SDK extraction. Local YAML/PowerShell and simulated-outcome
checks passed, and the exporter fixtures again passed 75 assertions. These
are tooling checks only. The workflow never fills reviewed identity or marks
conformance complete; the actual capture must still run and be reviewed.

| Gate | Acceptance detail and evidence to retain |
| --- | --- |
| 1. Full desktop API and behavior | Pin SDK, toolchain, and OS reference versions; inventory public desktop declarations with stable identifiers; map each to implementation, behavioral fixtures, and any justified platform-service exception. A missing audit entry is a gap, not an implicit exception. |
| 2. Semantic, interaction, accessibility, and visual coverage | Associate each in-scope feature and applicable state with tests and reproducible fixtures. Include interruptions, invalid input, disabled controls, focus, nested composition, and custom public extensions. Source compilation alone cannot close a behavior requirement. |
| 3. Shared reference apps | Build the same view sources on both platforms at a recorded revision. Capture reference behavior and raw retained output; review font, theme, and platform substitutions explicitly. Unavailable macOS execution remains unverified. |
| 4. CPU and D3D11 scene agreement | Exercise actual D3D11 execution and readback as well as CPU rasterization, including effect chains, subtree composition, mixed primitive families, transparent edges, nested clips, and fractional DPI. Keep measured tolerances and skip counts visible. |
| 5. Motion and bounded resources | Preserve deterministic animation/collection/resource tests and publish hardware qualification with the workload and p50/p95/p99 measurements required in section 4. WARP or unit-test timing does not qualify hardware pacing. |
| 6. Complete template workflows | For every template in section 7, record start-to-finish pointer, keyboard, and accessibility flows, persisted state where advertised, loading/failure/retry/cancellation, and tests of restart and unsaved changes. Never report an unsuccessful or memory-only save as durable persistence. |
| 7. Native machine smoke tests | Record device recovery, software fallback, display changes, IME, native dialogs, and Narrator flows with machine/toolchain/build details. Headless unit tests support these checks but do not replace native smoke evidence. |
| 8. Exact release revision validation | Run contracts, lint, serial tests/builds, and reviewed visual gates on the candidate commit. Record hosted workflow URLs and their exact SHA; keep local results, manual checks, and hardware qualification distinct. |
| 9. Clean-machine delivery | Record installation, sample creation/build/deployment, package version, deployment dependencies, compatibility notes, and reproducible evidence from a clean machine. A working developer checkout alone is insufficient. |

### First implementation batch

These are bounded work items within the existing goal, not additional release
conditions or substitutes for the gates above. Add test results and remaining
limits here as each item is validated.

- [x] Host `Settings` alongside ordinary scenes through public scene composition;
      route `openSettings` to one reusable settings window and preserve normal
      window lifecycle, renderer injection, and focus requests.
      `SettingsSceneHostingTests` passed 18 tests and the existing
      `WindowCoordinatorTests` passed 11. Coverage includes multiple static
      scenes, availability conditions, deferred environment propagation,
      singleton reuse, closing/reopening, independent scene storage, failed
      startup rollback, and activation requests. Foreground activation remains
      subject to Windows policy. Dynamic scene registration, Settings-only
      startup, automatic native Settings menu installation, and native macOS
      lifecycle comparison remain outside this implemented slice and open
      under the original product gates.
- [x] Carry binding transactions through writes, projected bindings, state
      observation, and retained animation; restore ambient context after nested
      writes and explicit animation suppression.
      `BindingTransactionTests` passed 14 focused tests, including a real
      state-driven intermediate opacity frame, alongside the existing
      `SwitchKnobMotionTests`. This verifies synchronous retained propagation;
      conflicting ambient/binding precedence and deferred-update behavior
      remain native-reference qualification gaps under gates 1–3.
      A further 9 `BindingHostTransactionTests` now pass through the real
      window host and public Toggle input. They cover animation start/midpoint/
      completion, explicit nil inside a restored ambient animation, unrelated
      queued notifications, newer state writes, and coalesced reloads. State
      mutation and a control's follow-up invalidation carry distinct inherited
      context handlers, so an immediate redraw cannot discard the binding's
      captured transaction. These are Windows semantics tests, not native
      SwiftUI reference evidence.
- [x] Dispatch scroll geometry, phase, and visibility callbacks from retained
      presentation, preserving observer history across rebuilds and respecting
      scroll ownership, clipping, and animation.
      Validation exposed related defects in the existing presentation path:
      disabling a scroller removed its layout axis; animated proxy requests
      lost their transaction; unrelated keyboard input could cancel motion;
      shrinking the scroll range could produce a negative presentation; and
      returning clipped content could replay stale prepaint ranges. The
      implementation and regression cases now address these paths together.
      Paint-only culling at zero opacity needs separate frame/scene snapshot
      ownership because prepaint visibility alone cannot establish that a
      descendant contributed pixels to the prior output. Pixel regressions
      include in-bounds stale ranges that refer to another view's records,
      not only out-of-bounds crashes. The subsequent consolidated run passed
      all 24 targets in 20 serial invocations: 344 XCTest cases and 16 Swift
      Testing cases. The scrolling coverage includes 43 retained and 8 public
      observer tests, 7 retained and 6 public programmatic-animation tests,
      and a public keyboard activation test; 4 snapshot-ownership regressions
      and 2 real-host gallery tests also passed. The existing reader, runtime
      scrolling, window, rendering, binding, and Settings suites passed in
      that same run. This is focused Windows evidence, not the Full or hosted
      release gate.
      Geometry and phase observe the first enclosed scroller; multiple
      candidates produce a diagnostic. Geometry uses the same presented
      offset as paint and input, and history survives reconciliation. Visibility
      uses transformed rectangular intersections, without opacity, sibling
      occlusion, or complete rounded-mask coverage. Target visibility,
      binding-driven scroll position, scroll transitions, two-axis scrolling,
      native phase/threshold comparison, and hardware pacing remain open.
      Active-animation interruption is tested; whether a queued pre-layout
      proxy request should be superseded by newer input remains a separate
      audit/test item for the existing request queue.
- [x] Persist the settings template through an injectable local store; restore
      it on launch, validate saved data, preserve unsaved edits on write failure,
      and keep snapshots/tests isolated from user settings.
      `DemoSettingsPersistenceTests` passed 13 tests, including real file
      round trips, bounded and invalid input, atomic replacement, failed
      writes, retry/reset, keyboard Save and Settings routing, and isolated
      snapshot defaults. The live executable opts into per-user storage;
      tests and snapshots default to independent memory stores. The shared
      `DemoSettingsTemplate` and `docs/TemplateCatalog.md` expose the model,
      storage adapter, schema, and remaining template workflows. The store is
      synchronous and does not resolve concurrent-process edits. Audio and
      usage-sharing toggles persist configuration only; they do not provide
      those integrations. Native keyboard/Narrator and macOS qualification
      remain required by the original template gate.
- [x] Correct authored color-effect parameters and preserve sequential effects
      across relevant primitive and compositing paths, with CPU/D3D11 execution
      tests and explicitly recorded remaining limitations.
      `SceneColorEffectPassTests` passed 16 tests and
      `D3D11ImageRenderPassTests` passed 12 real WARP/contract tests. The
      renderer-neutral image source contains the child scene and ordered
      effects; D3D11 keeps child rendering and filtering on the device.
      Fractional-DPI isolation preserves the two-pixel derivative grid without
      loosening alpha tolerances. Shared checks bound each source to 4,194,304
      pixels, graph/execution source payload to 16,777,216 pixels, depth to 32,
      count to 1,024, and effect chains to 256. The cumulative limit accounts
      for 64 MiB of source BGRA8 payload, not total process/driver memory.
      CPU cache hits do not allocate again; repeated GPU realizations can
      exhaust execution limits and fail explicitly. Custom shaders, animated
      effect parameters, complete drawing-group/blend semantics, imported
      material backdrops, native color-space parity, and hardware pacing
      remain open under the original rendering and animation gates.

### Atlas resource ownership correction

Before pushing the first batch, source review identified paint-time memory
amplification in color-effect text passes. Each source retained an
intermediate native glyph-atlas snapshot; later glyph writes could copy the
full 2048-by-2048 BGRA atlas, or 16 MiB, for another small text source. The
source-image pixel budgets are checked later and do not bound those atlas
copies. This issue exists without the pending Canvas-symbol work and needs
an independent correction under the existing rendering/resource gates.

The correction must bind one completed atlas across the frame's nested
source namespaces and their ancestors, preserve previously returned scenes
as immutable values, and detach atlas references from retained replay copies.
Nested native-glyph use must participate in generation checks before cached
UVs can be rebound. Immediate CPU isolation rasterization needs a bound
snapshot only for its short rendering scope. A nested source sharing the
parent's already uploaded atlas must not request another full upload.

Required evidence includes many tiny distinct-glyph color sources sharing
one buffer, old-scene pixels after later writes/recycling, replay invalidation,
safe observer reentry, bounded retry behavior, and real WARP upload/namespace
checks. The current candidate's other passing tests do not prove these
ownership properties. The correction and its tests are prepared separately;
no arbitrary retention guard, increased tolerance, or reduced completion
scope substitutes for fixing the ownership.

### Additional text resilience detail

Native text tinting now clamps channels before converting them to integers;
NaN, infinities, and extreme finite color values cannot trap that conversion.
The shared tint path protects both GDI and DirectWrite text bitmaps and keeps
ordinary premultiplied pixels unchanged. Invalid native font dimensions,
inset coordinates, and unrepresentable UTF-16 lengths decline native rendering
before unsafe integer conversion. `NativeTextConversionSafetyTests` passed
10 tests, including normal-channel/coverage preservation and real GDI raster
checks. This advances sections 2 and 5; it does not close shaping, editing,
IME, accessibility, or native-machine qualification requirements.

### Audited follow-up within the existing gesture requirements

Long-press recognition is a concrete remaining gap under sections 3–5, not
a new completion condition. The current modifier discards minimum duration
and maximum distance and recognizes on release inside; build-local closure
state can also be lost during reconciliation. A complete correction must
retain the attempt in the runtime, measure logical-point movement against
the injected monotonic clock, recognize once at the deadline, and cancel
cleanly on early release, excess movement, removal, disabling, or lost capture.
Gesture state must reset on termination without fabricating a terminal
`updating` event. Tests must include callback-triggered rebuilds/removal,
late release between ticks, mouse/primary-touch routing, and a visible
retained-render interaction fixture. Exact native callback ordering and
gesture arbitration remain reference-qualification work, not assumed parity.

The original goal text and nine gates in sections 1–9 were compared against
starting revision `38e855d` during this batch and remain unchanged. All new
execution detail is recorded in this section.

### Next implementation detail within the existing requirements

The following source audit refines work already required by sections 1–7.
These are open implementation items, not new completion gates. Work prepared
in isolated branches is not counted as implemented in the validated main
checkout until it is integrated and tested.

- [ ] Correct retained long-press recognition as described above, including
      a shared-source gallery interaction and regression tests for callback
      reentry. Native callback ordering and gesture arbitration need separate
      reference evidence even after the retained behavior passes.
- [ ] Make Canvas symbols resolve tagged public views and draw through the
      existing renderer-neutral scene contract. Preserve the outer glyph-atlas
      frame and resource budgets. Context copies must share drawing order while
      retaining independent graphics state; symbol transforms must preserve
      authored affine placement. This does not by itself complete Canvas blend
      modes, Core Graphics adapters, gradients, or all inherited transforms.
- [ ] Resolve the overload ambiguity in ordinary public
      `Color(red: 1, green: 0, blue: 0)` source while preserving existing typed
      Core Float callers. Cover both public WinSwiftUI and portable Core
      initializer families; successful internal call sites do not establish
      ordinary shared-source compatibility.
- [ ] Make single-file FileDocument export serialize the document and write
      the accepted destination atomically before reporting success. The current
      code reports a save URL without consuming the document. Encoding/write
      failures must reach the completion handler, cancellation must not write,
      and unsupported payloads must fail explicitly. Migrate save-dialog test
      destinations to uniquely owned temporary directories before exercising
      real writes. Directory, multiple-document, and Transferable export remain
      separate gaps unless implemented and tested.
- [ ] Preserve TextEditor caret, selection, IME, and drag state across
      reconciliation and bind callbacks to the surviving node with the latest
      application bindings. The audit found that a mid-string caret can move
      to the end after an unrelated rebuild, and callbacks can target a
      discarded node. Exercise mid-string insertion, selected replacement,
      Unicode, composition geometry, removal, and callback-triggered rebuilds.

The document/editor template needs further work beyond those two input/file
fixes: real document sessions and projected document bindings, installed
new/open/save environment actions, undo/redo registration, vertical caret
navigation and scrolling, document commands, and unsaved-change handling.
`DocumentGroup` remains a shim and command descriptors are not native menus.
The initial audit also found that titlebar close reached destruction without
a veto or deferred decision. The second batch adds `WM_CLOSE` preflight
through concrete and neutral host delegates, consumes the latest retained
`windowDismissBehavior`, updates native Close availability, and keeps refused
windows and their renderers/accessibility/coordinator ownership alive.
Reentrant decisions, stale observed-state rebuilds, duplicate teardown, HWND
lifetime reuse, and failed-start cleanup have dedicated tests authored for
serial validation. Enclosing declarations take precedence on Windows;
conflicting native modifier precedence remains unqualified.

This is the host decision seam, not a completed document workflow.
Save/Discard/Cancel must still run before teardown, preserve edits on
cancellation or failure, and close exactly once after an approved result.
Destructive dismissal transactions and full modal dismissal behavior also
remain unimplemented. These remain requirements of the original document
lifecycle, text/input, and template gates; a successful dialog or close-policy
veto alone closes none of them.

### First integrated validation checkpoint

The first complete local validation checkpoint is revision `e4ec609` on
2026-08-27. Its production source and tests include the corrected disabled-List
regression check from `14603fc`; the later commit only adds audit detail.

- The focused implementation run passed 344 XCTest and 16 Swift Testing
  cases. The separate disabled-List recheck passed all eight cases.
- All 356 Swift files passed strict lint; the final List test correction also
  passed an individual format/lint check. Architecture contracts passed before
  implementation and again in the validation ladder.
- Quick passed from its first step after the obsolete List expectation was
  replaced with virtualization, blocked-input, and programmatic-access checks.
  It reported 994 XCTest cases and nine Swift Testing cases, with no failures.
- Full passed the portable tests, all 160 Windows test shards, app build,
  scene/frame screenshots, dark/light gallery screenshots, and all 85 reviewed
  gallery baselines within their existing thresholds. It reported 3,403
  XCTest cases and 134 Swift Testing cases, with no failures. These are
  reported executions, including the portable check followed by the full suite,
  not a claimed count of distinct product requirements.
- Both Quick and Full retained one existing skipped case,
  `testMaterialInsideADrawingGroupBlursNothing`. Materials inside offscreen
  groups still lack the parent backdrop. This is an unresolved rendering
  requirement, not a waived acceptance condition or a passing feature test.
- The real-window startup probes completed their initial render and selected
  D3D11 scene presentation by default and Direct2D frame presentation under
  the explicit frame-debug override. They do not qualify long-session pacing,
  display changes, recovery, IME, or Narrator workflows.

Evidence remains under `artifacts/`: `goal-integrated-validation-v2.log`,
`goal-list-virtualization-recheck.log`, `goal-all-swift-lint.log`,
`goal-agent-check-quick-v3.log`, `goal-agent-check-full.log`, both
`goal-native-*-probe.log` files, and the gallery comparison reports. Dashboard
and dark/light gallery images were opened and inspected as raw retained
renders. No baseline was regenerated to hide a mismatch. The gallery still
has 144 rendered fixtures and 85 reviewed regression entries; those counts
describe different sets.

The Settings render also exposed misleading existing copy about sending
telemetry. The pane now identifies that toggle as a sample preference and
states that the demo sends no telemetry, with a rendered-tree assertion in
the persistence workflow test. Persisting a flag is not a service integration.

Subsequent review found another concrete state-lifetime issue before push:
the new gallery observation values are held on the app-wide model, so one
window can display another window's offset, visibility, or scroll phase.
Long-press presentation state would have the same problem if stored there.
The correction must give each managed window its own interaction state while
preserving shared authored preferences and same-window rebuild continuity.
Non-data WindowGroup content is currently constructed once and reused, so
fresh per-window content construction is part of that correction. The general
nested StateObject lifetime remains a separate audited gap; a demo ownership
fix must not be presented as full property-wrapper conformance. The checkpoint
above predates this correction and must be rerun after integration.

The window correction subsequently passed 111 focused XCTest cases across
eight suites, including four WindowGroup content-identity tests and four
live gallery observation tests. Ordinary WindowGroup builders are now
main-actor closures materialized once per new host; explicit content
replacement and scene environment propagation remain supported. The demo's
window-owned readout state sits above its tabs, while the bright-preview
preference remains shared. Late opening, independent scroll phases/offsets,
same-window rebuilds, and tab remounts are covered. All 50 Swift files changed
in the batch passed strict lint, and the two builder actor annotations passed
an additional file lint after compilation identified their missing isolation.
Quick and Full then passed again at `afd56db`. Quick reported 1,000 XCTest
cases and nine Swift Testing cases; Full reported 3,409 XCTest cases and
134 Swift Testing cases. Both retained the same single material-backdrop
skip and had no failures. All 85 reviewed baselines still matched within
their existing thresholds. The logs are `goal-agent-check-quick-v4.log` and
`goal-agent-check-full-v2.log` under `artifacts/`. This checkpoint includes
the window ownership correction but still predates the atlas resource
ownership correction above, which must be verified before the batch is pushed.

The independent atlas correction then passed 247 focused XCTest cases across
14 targets in 12 serial invocations, without failures or skips. This includes
five new scene lifetime cases and two new real WARP resource cases. Completed
color-effect sources now share the final atlas across nested namespaces;
retained replay copies detach it recursively and guard descendant glyph UVs.
The tests exercise previously returned immutable scenes, recycling, observer
reentry, CPU isolation retries, and shared GPU uploads. All 52 changed Swift
files passed strict lint, and contracts passed before and after integration.
Evidence is in `artifacts/goal-atlas-lifetime-recheck.log` and
`artifacts/goal-batch-lint-atlas.log`. The new suites also gate Quick. Full
validation and startup/render probes must run on this corrected candidate
before the accumulated commits are pushed. This is a resource ownership fix,
not a total RAM bound or completion of the original rendering gate.

Full validation subsequently passed at `d648286`, including the atlas fix:
3,416 XCTest executions and 134 Swift Testing executions, with no failures
and the same one material-backdrop skip. All 161 Windows shards, the portable
check, app build, five raw screenshots, and all 85 reviewed gallery baselines
passed. The log is `artifacts/goal-agent-check-full-v3.log`; a separate copy of
the gallery reports and a machine-readable result are preserved under
`artifacts/goal-first-batch-d648286/` so later runs do not replace this evidence.
Fresh native probes selected D3D11 scene presentation by default and Direct2D
under frame debug, both after initial render returned. The refreshed dashboard,
gallery, and Settings raw images were opened and inspected; the Settings copy
now explicitly says that the demo sends no telemetry. These checks still do
not establish native interaction, accessibility, recovery, or timing
qualification. Sections 1 through 9 were compared against the starting commit
and are unchanged; all nine original completion gates remain open.

### Second implementation batch

The first 24 commits were pushed together as `4e14693` after the validation
above. Windows CI, portable CI, and the pinned SDK candidate capture started
for that exact revision; their results are not yet known. The following
prepared fixes are being integrated and remain subject to serial compiler,
semantic, renderer, and workflow validation before the next combined push.

Ordinary public RGB Color literals now prefer the public Double/opacity
initializer without making the existing Core Float/alpha overload unavailable.
Eight facade tests and four portable tests cover integer and fractional
literals, contextual initialization, typed variables, initializer references,
explicit labels, and unchanged extended components. This resolves an overload
boundary; it does not establish full native color-space conformance. Integrated
SwiftPM results are pending.

Retained long presses now have runtime-owned attempts with original duration
and logical movement thresholds. Reconciliation refreshes callbacks without
restarting a hold; recognition, cancellation, removal, modal changes, and
reentrant callbacks retire an attempt once. GestureState cleanup is tied to
its update revision and preserves the transaction supplied by its updater.
The shared-source gallery has independent window-owned hold readouts and a
Confirm once button alternative for keyboard and accessibility invocation.
There are 33 dedicated retained tests, three gallery workflow tests, and four
migrated legacy expectations awaiting integrated execution. Native callback
ordering, arbitration, mounted GestureState lifetime, and Narrator remain
separate acceptance work.

Text inputs now retain their editing state through an optional controller on
the surviving node. Fresh configuration adopts caret, selection, IME text,
and drag anchors while replacing application bindings and callbacks. Explicit
bound selection wins, shrinking text clamps offsets, and an in-flight setter
resolves the latest surviving control after a synchronous rebuild or removal.
Thirteen new hosted regressions await integrated execution. This does not
implement undo registration, vertical caret navigation, editor scrolling, or
document sessions; those original requirements remain open.

Single regular-file FileDocument export now serializes through a neutral Data
provider and uses Foundation's atomic writing option before reporting success.
Cancellation writes nothing and does not call export completion; encoding or
write failures propagate without reporting the chosen URL as a saved file.
Current configuration is captured per operation, and reentrant requests wait
for that operation's completion. Nineteen new tests and the migrated dialog
tests use only uniquely owned temporary destinations for real filesystem
writes; integrated execution is pending. This standalone path has no existing
document-session wrapper and encodes synchronously on the main actor.
Directory/package, multiple-document, ReferenceFileDocument/Transferable,
background-encoding, document ownership, and native workflow parity remain
requirements, not exceptions granted by this slice.

Ordinary native and programmatic window-close requests now consult the current
retained dismissal policy before destroying their HWND. Concrete and neutral
host vetoes both apply; refused windows keep their presentation/accessibility
resources and coordinator records. Teardown is guarded against duplicates and
late observed rebuilds or presenter retries. Failed-start rollback has a
separate unconditional destroy path so a veto cannot strand an unowned window.
Twenty-six new tests await integrated execution, including owned hidden native
windows. This establishes a close decision boundary, not document dirty-state
ownership or Save/Discard/Cancel behavior.

Integration with timed gestures exposed another teardown edge: direct close
or failed-start cleanup can bypass native focus/capture-loss messages. Close
now cancels pointer and keyboard focus unconditionally after marking the host
closed, and native/diagnostic input plus frame requests refuse later work.
Four additional tests cover mouse GestureState reset, callback reentry, late
input without repaint, and normal focus loss followed by a new hold.

Canvas tagged symbols now resolve public views in the inherited environment,
measure in logical coordinates, and record child scenes through the existing
image-pass contract. Copied contexts share authored draw order but retain
independent transform, opacity, and clip state. Context-authored symbol affine
placement uses a shared CPU/GPU contract and an 80-byte image ABI; general
inherited View affine fallbacks remain separate. Resource and declaration
traversal limits, a bounded legacy bitmap route, visible rejection markers,
and shared final atlas ownership are explicit. Scene equality also now
includes child passes. Fifty-two new regressions and the ABI updates await
integrated execution. Full layer/filter/blend/material semantics, arbitrary
builder allocation bounds, native symbol sizing/tag behavior, and hardware
qualification are not established by this implementation; details are in
`docs/CanvasSymbols.md`.

Diagnostic accounting now separates rebuild work before frame entry from work
already inside the frame and charges nested reload intervals once. Report
schema 2 keeps metric units but adds sample counts and uses null for missing
statistics, with no pre-warmup fallback. It publishes the available body,
construction, and reconciliation percentiles and labels synthetic input,
CPU timing, forced frames, and unavailable qualification measurements.
Fifteen injected-clock/report tests await integrated execution. Historical
reports are unchanged, and no new machine performance result is implied.
All second-batch semantic suites now gate Quick as well as Full; portable
RGB initializer coverage runs with the existing portable stage. The first
integration lint passed all 50 changed Swift files, but compiler and runtime
validation are still pending.

Initial compilation also exposed ambiguous default long-press call shapes:
the older `pressing:perform:` overloads competed with current trailing-closure
syntax. Those older spellings remain available but are now disfavored when
current overloads match; a direct compiler probe accepted six call shapes,
and the retained tests keep their ordinary unqualified calls. Test fixtures
also needed their intended actor/test access and explicit return annotations.
They now qualify WinSwiftUI geometry where Foundation defines competing names.
Foundation CGRect/CGSize interoperability and implicit View.body builder
behavior remain explicit source-compatibility gaps; these fixture corrections
must not be counted as conformance proof for those gaps.

The Canvas compile also found that unqualified planar scale anchors competed
with the optional UnitPoint3D adapter. The adapter overloads are now disfavored
when a planar form matches; typed depth anchors and explicit z arguments remain
callable. Six source/retained regressions cover View and visual-effect forms.
This fixes overload selection only: scale-anchor placement and actual depth
rendering still require their original semantic and visual qualification.

### Material backdrop acceptance clarification

Review of the existing skipped material case found that its name overstates
its scope: it builds retained compositing-group and content-blur examples,
not a public drawingGroup chain or nested color-effect fixture. It records
their current lack of parent-backdrop blur and then skips. Apple documents
group flattening, effect scope, and material blur, but those descriptions do
not settle every combination across an offscreen boundary. Pinned native
fixtures need separate group/filter/opacity cases and a positive capture
control before their pixels become conformance expectations.

Any parent-backed layer route must preserve earlier local content, transparent
parent alpha, geometric replacement coverage, occurrence-specific backdrop
sampling, and draw order. Copying the whole parent into an ordinary cached
image would not suffice. CPU memoization and GPU same-ID image batching are
valid for backdrop-independent sources only. Native behavior, the scene
contract, scratch-resource bounds, and CPU/WARP regressions remain required;
the skip must not be removed by narrowing its test or assuming native pixels.

### Additional state lifetime acceptance detail

A source audit found that the current State and StateObject wrappers follow
the lifetime of their stored Swift values, not mounted view identity.
Reconstructing a nested child in a parent's body allocates fresh State
storage and eagerly constructs another StateObject. Reusing the same view
value in two hosts instead shares its storage; State keeps only the latest
invalidation context. Retained node reconciliation happens after body
evaluation and cannot repair that lost or shared property state. Existing
tests that reuse a single view value or externally created observed model do
not exercise these cases. These are source-derived reproductions awaiting
dedicated executable tests, not new passing evidence.

The required correction belongs to section 3's existing identity and state
semantics. Resolve host-owned storage before body evaluation using a typed
hierarchy of parent identity, concrete view type, structural child/branch,
ForEach or explicit ID, and stable property declaration slot. The current
builder flattens conditional structure, siblings share a build context, and
`.id` stamps retained nodes only after child construction; all are relevant
identity boundaries. A property-read counter or a single last-bound storage
location cannot distinguish independent occurrences reliably.

Preserve eager evaluation of a State seed while retaining its mounted value;
hold StateObject's escaping construction factory and evaluate it once per
mounted owner. Removal must retire the owner and invalidator without allowing
stale bindings or transition overlays to target a replacement. Painting culls
or deferred layout do not end a mounted lifetime. Projected bindings need a
resolved owner/generation, and deferred builders, handlers, tasks, observation
capture, transactions, and custom DynamicProperty composition must retain the
right scope. Extend ViewBuildContext and per-host ownership, not global state.

Required regressions include a freshly reconstructed child responding to its
own action, unrelated parent updates, keyed reorder/insertion/removal, typed
IDs with equal descriptions, sibling and conditional slots, explicit-ID reset,
removal/reinsertion of a reused value, StateObject release, stale bindings,
two hosts using the same value, bound-only reads, nested custom wrappers,
and deferred geometry/task work. Managed-window content factories are a useful
scene correction, but cannot alone satisfy this general state-lifetime gate.

A separate Swift 6.3 compiler prototype demonstrated typed installation into
a local copy of private and nested struct property wrappers, including
existential declarations, without mutating Mirror values or using raw-memory
field writes. Six manually scoped assertion groups passed in debug and
optimized builds, with library evolution and stripped reflection names also
checked. These experiments establish a mechanism, not mounted runtime behavior.
They depend on underscored reflection/key-path facilities and runtime metadata;
metadata-disabled clients, immutable or reference-type custom wrappers, and
enum payloads still require explicit handling rather than silent shared-state
fallbacks. The adapter and compiler-upgrade qualification must remain isolated.

Production integration is staged: first preserve typed structural identities
through builders, erasure, explicit IDs, collection keys, and independent child
roles without adding layout nodes; then install validated properties before
body evaluation; finally commit and retire host/subtree ownership with lifecycle
and reentrancy tests. The first stage must not change State storage or claim
its lifetime fixed. Epochs must span both component composition and retained
node construction, including deferred geometry and selection/measurement
containers. The original identity/state completion requirement is unchanged.

### Additional performance evidence detail

The current diagnostic harness was audited against the unchanged section 4
targets. It is useful synthetic stress evidence, not hardware qualification:
it injects retained events instead of native input, has no input-to-present
correlation or GPU execution timing, and uses callback gaps and CPU thresholds
instead of measured presentation deadlines. Its wheel value of 120 means
120 logical lines, not one native wheel detent. A 30-second request contains
only about 28.2 seconds of scripted interaction after warmup; a 32-second
request provides approximately 30.2 seconds of that stated stress workload.

Deferred rebuilds can already be inside measured frame time, but the current
combined user-visible cost adds them again. Correct the overlap using
separate before-frame and in-frame intervals with injected-clock tests before
using that total for acceptance. Phase percentile coverage, cold start,
first interaction, sample eligibility, native input timestamps, GPU timing,
and actual presentation deadlines still need qualification instrumentation.
The detailed limitations and reproduction conditions are retained in
`docs/PerformanceBudgets.md`; prior timing tables are historical evidence,
not current results for this batch. No hardware target or tolerance is
changed by discovering these measurement gaps.

### Hosted validation follow-up

The starting revision's [Windows CI run](https://github.com/mweinbach/swift-windowsui/actions/runs/33081745181)
passed setup and contracts but stopped in `SymbolIconRenderingTests`: two
assertions assumed Segoe Fluent Icons was installed on Windows Server 2022,
although the supported Segoe MDL2 Assets fallback was selected. The tests now
inject availability when checking preference order and separately compare
actual installed-font pixels or require the explicit vector fallback. All
12 tests pass locally; production fallback selection is unchanged. This is
not a green hosted result for the new candidate. That exact-revision run
still has to execute after the validated commit batch is pushed.

The first combined push is `4e14693`. Its
[portable CI run](https://github.com/mweinbach/swift-windowsui/actions/runs/33101129537)
passed on Ubuntu 24.04 and macOS 15. The
[Windows CI run](https://github.com/mweinbach/swift-windowsui/actions/runs/33101129485)
passed contracts and started Full validation; its final result is pending.
The [pinned SDK candidate run](https://github.com/mweinbach/swift-windowsui/actions/runs/33101129489)
failed before running the exporter: checkout credential cleanup could not find
a `.gitmodules` URL for the existing `extern/zed` gitlink. The later upload
found no evidence directory and the run has zero artifacts. No Xcode, SDK,
compiler identity, or API inventory was captured. A verified metadata mapping
and a bounded checkout fixture are being integrated without fetching or
editing the reference checkout, changing SDK pins, or retaining credentials.

The metadata repair is now integrated. Its fixture passed 20 real Git
assertions locally, reproducing the original failure and showing that the
verified mapping permits cleanup while the reference remains uninitialized at
the same commit. Quick, Full, and the SDK workflow run that fixture. The new
mapping does not change `extern/zed`, fetch it, or weaken credential cleanup.
A new hosted candidate capture is still required after the next validated push.

The first-push Windows Full job subsequently stopped at shard 32 of 161 in
`DemoObservationShowcaseTests.testRealScrollReadoutsKeyboardResetAndBindingAnimation`.
The reset phase lacked Animating, opacity changed immediately, and no opacity
animation remained. The harness inherited system appearance, while the demo
correctly suppresses animation for reduced motion; that preference explains
the failure pattern but was not logged on the runner. The test now injects
normal motion through the existing appearance-provider seam without changing
its positive assertions. Two additional hosted tests exercise reduced motion
and app-disabled animation explicitly. No OS setting or production preference
handling is overridden. Integrated tests and a new exact-revision hosted run
are required; later shards in the failed run were not executed.

### Second-batch runtime validation in progress

The source and integration test modules compile at `7b70a81`. The focused run
then stopped in the branching Canvas symbol budget case. A direct invocation
of that case reproduced native exit `0xC00000FD` (stack overflow), without an
XCTest assertion failure. The accepted depth, count, and pixel budgets must
remain covered; reducing the fixture, skipping it, or increasing the process
stack alone would not establish a bounded implementation. Evidence is in
`artifacts/goal-batch-two-focused-v3.log` and
`artifacts/goal-canvas-branch-direct-v2.json`. The independently continued
suites are partial diagnostic evidence, not a passing validation gate.

That continuation also caught a fixture mistake in the new long-press
accessibility alternative: the raw projection exposes explicitly authored
accessibility actions, whereas ordinary Button invocation is provided by the
runtime's UI Automation adapter. The fixture now discovers the live adapter
element, checks enabled/default-action state, and invokes it through that same
adapter. This does not substitute for the still-required native Narrator flow.

The continued runs exposed an atlas-report conversion bug: passing
`Double.init` as an Optional.map function for UInt64 selected the bit-pattern
initializer, so 50 bytes became approximately 2.47e-322 rather than 50. An
explicit numeric conversion fixes the report; the original assertion remains,
with additional fractional-average coverage. A standalone Swift 6.3 probe
reproduced the overload selection. Native titlebarless window creation also
trapped while converting WS_POPUP's high bit to signed Int32. The style now
uses a bit-pattern conversion, with headless mask checks and the original
owned-HWND close-veto test. At `6dde57b`, all 36 diagnostic and native window
focused tests passed without failures or skips. The corrected gallery motion
and UI Automation invocation fixtures also passed in the continued run.

The public Canvas pixel fixtures revealed two separate preexisting API limits:
View scale anchors are ignored, and bitmap Image.resizable does not yet accept
the enclosing frame as its size. Those fixtures now author an 8-by-8 bitmap
directly and use a supported centered scale plus translation; all original
pixel assertions and tolerances remain. Image dimensions are checked using
both the rectangle and its affine basis, rather than treating the rectangle
alone as the painted footprint. This isolates the Canvas contract without
closing the separate anchor-placement or bitmap-resizing requirements.

Text-pointer tests also exposed a production geometry error when laid-out
stack origins differ from authored frames. Pointer/IME coordinate conversion
must use current retained layout and the visible text-content origin. Raw
callback fixtures must explicitly retain their runtime; restoring strong
runtime captures merely to keep those fixtures alive would risk ownership
cycles. Both the geometry regression and full Canvas recursion remain pending
correction and integrated validation; no original completion gate is closed.

The pointer correction now resolves layout without changing authored frames,
rejects hidden, detached, foreign, and reentrant geometry queries, and follows
the visible text-content child through reconciliation. The first serial run
passed all 15 hosted editor cases and the existing drag-selection, IME,
environment, caret, and selection suites. One new test's callback count needs
to include the runtime's existing second layout pass after a scheduled
after-layout callback; the nested query itself returned nil as intended.
The correction must assert that neither nested query increases either callback
count, then rerun the complete filter, including the native input shard that
the failed run did not reach. Weak runtime ownership remains required.

The Canvas stack correction keeps the original scene budgets unchanged. The
ordinary retained-tree traversal uses an explicit work list, with content,
child, and finish operations preserving the original presentation and cache
completion order. Large emission, source preparation, and bitmap-processing
frames return before nested sources record; only small coordination frames
remain on the stack. Five additional regressions exercise the full accepted
symbol depth, queued content/child order, and the full accepted depth with mixed
symbol/color-effect passes, drawing groups, and blur. Compiler frame inspection
and independent review support the change, but do not replace execution of
those cases, cache/atlas/order tests,
or the subsequent Full validation. The known material-backdrop skip remains
an unresolved feature requirement.

Canvas sources currently record at the captured environment display scale;
magnification filters that source's antialiasing instead of increasing its
raster density. The scale-only fixture now uses an opaque authored bitmap,
preserving its original position and opaque-pixel assertions. A separate
regression preserves the existing square-quad coverage contract: three corner
texels at 191/255 produce 195/255 under the specified bilinear magnification.
It checks CPU source/scene/frame bytes and D3D11 WARP output, without changing
the shared coverage kernel, sampling rules, or old test tolerances. Native
SwiftUI Canvas capture-density behavior is still unqualified; this records
current backend consistency rather than claiming native parity.

The integrated focused run now passes: 681 XCTest executions across 59
selected targets and 32 serial invocations, with zero failures and the one
preexisting material-backdrop skip. This includes the original branching
case, all five added depth/order cases, the CPU/frame/WARP sampling case,
all seven layout-geometry cases, and the native text-input shard. The original
branching case also passed independently in 0.166 seconds after previously
ending in stack overflow. Strict formatting passed for all 56 Swift files
changed since the first combined push; architecture contracts and diff checks
passed. Logs are `artifacts/goal-batch-two-final-focused.log`,
`artifacts/goal-canvas-stack-branch.log`, and
`artifacts/goal-batch-two-all-changed-lint.log`. These focused results do not
replace the pending Quick/Full, raw-render, hosted, or hardware qualification
gates, and none of the nine original completion gates is closed.

### Second-batch completed local validation

The clean source revision `74ee04b` passed Quick and Full serially. Quick
executed 1,253 XCTest cases and 9 Swift Testing cases; Full executed 3,619
XCTest cases and 134 Swift Testing cases across the portable check and 169
Windows shards. Both had zero failures and the one known material-backdrop
skip. These are test executions, not counts of distinct compatibility
requirements. The demo built, all 85 reviewed gallery baselines passed their
existing thresholds, and no baseline was updated.

Raw dashboard, dark/light gallery, frame-fallback, settings, and tall gallery
renders were inspected. The 1.25-scale, 1,280-by-3,400 logical gallery render
includes the new press-and-hold card and its ordinary-button alternative.
The frame-debug renders still visibly differ in corners, material treatment,
and text appearance; passing this regression ladder does not establish full
scene/frame or native SwiftUI visual parity. Native startup probes separately
confirmed the D3D11 batch presenter and the explicit Direct2D frame presenter
attached and returned an initial render. They do not establish recovery,
latency, long-session reliability, or Narrator completion.

The evidence is preserved under `artifacts/goal-second-batch-74ee04b/`, with
source revision, log hashes, raw renders, native probe results, and the gallery
comparison report. The final evidence note changes documentation only after
that validated source revision. The accumulated commits are ready for one
combined push, after which Windows/portable hosted validation and the repaired
pinned-SDK candidate capture must run on the pushed revision. Release and
hardware qualification remain false, and all original completion gates remain
open.

The next state work is ordered around actual ownership boundaries. Typed
structural identity must first pass its 37 authored regressions; it does not
install State storage. Ordinary custom-view State then needs copied-wrapper
installation, host-owned cells and mount generations, bindings that retain
their original cell, adoption/reentrancy hooks, staged observations, and
deferred GeometryReader scopes. Only actual abandoned candidates are rolled
back; nonthrowing View construction is not being replaced with a speculative
failure API. Outgoing generations lose write permission before cleanup while
retaining cleanup reads until cancellation/disappearance finishes. Declared,
evaluated, and adopted content must remain distinct; skipping a body or paint
cannot by itself retire its state. Lazy StateObject factory ownership follows
as a separate tested slice, with uninstalled/stale access policy and inactive
container behavior still requiring explicit native qualification.

The second combined push is `316ea9b`. Its portable hosted run passed on
Ubuntu and macOS; Windows Full validation and the repaired SDK export are in
progress. The SDK job has passed checkout and reached the actual exporter,
unlike the first attempt. This is not yet a reviewed inventory or a green
Windows result.

A subsequent optimized executable build failed before diagnostics could run.
Swift 6.3 rejected captures of COM context/resource pointers in the legacy
frame renderer's nested rectangle-submission helper. Explicitly annotating
that local function alone did not resolve the diagnostic. The fix must keep
immediate-context work on the main actor without unchecked Sendable claims or
unsafe isolation. Full validation is being extended to compile the release
executable as well as debug, so optimized compilation is checked automatically;
this still does not mean the XCTest suite runs in release or establish timing
qualification. No new timing sample exists for the failed build.

Typed structural identity is now applied for integration, with no State cells
enabled. A new test initially compared the non-Equatable ViewLayoutMode enum;
it now checks the stack case and compares its Equatable StackLayout payload.
Its geometry assertions use resolved frames rather than authored frames.
The editor attachment fixture now exercises explicit adoption into a raw
attached slot, preserving controller and caret assertions without asking
different concrete view types to share a typed identity. Production source
compilation succeeded; the corrected tests still need execution and broader
validation before this slice is accepted.

The corrected integration run passed the 15 raw identity tests and four
builder-role tests, then stopped at an existing close-policy test before the
18 facade identity cases ran. That test expected a conditional branch change
to preserve its node. The replacement fixture must instead prove both rules:
policy value changes keep the same typed node, while changing the branch
replaces it; a separate raw-slot case still requires adoption to clear removed
policy metadata. Earlier editor geometry cases passed. These are partial run
results, not a passing identity or compatibility gate.

The SDK capture on `316ea9b` completed all four compiler exports before its
inventory step failed while reading a 1.34 GB SwiftUI graph into one string.
The preserved artifact contains 32 files totaling 2,990,598,841 uncompressed
bytes; its ZIP SHA-256 is
`5c6aa4720ffde305c0ff0d31186ba387a1129181673bdf8647c0ac4a9bd11af8`.
The downloaded bytes match that hosted digest. Command provenance records
Xcode 26.6 build 17F113, macOS SDK 26.5 build 25F70, and Apple Swift 6.3.3
with swiftlang-6.3.3.1.3 / clang-2100.1.1.101. These are captured identities,
not a completed identity review or behavior conformance. The raw capture is
preserved unchanged under `artifacts/goal-sdk-33110144606/`. Repair must bound
both parsing and inventory output without dropping declarations, availability,
extensions, synthesized members, or either architecture, and without changing
the pinned baseline. Windows hosted Full validation is still in progress.

The optimized executable build now passes after moving rectangle submission
into a private main-actor renderer method with explicit context/resource
arguments and scoped uniform access. No COM ownership or draw ordering was
changed, and no unchecked isolation was introduced. The successful build took
240.69 seconds and is recorded in `artifacts/goal-release-outlined-build.log`.
Commit `9e9e575` also adds an explicit build configuration option and makes
Full compile the release executable. Its focused gradient and backend-lifetime
tests had passed before the unrelated close-policy fixture stopped that run.
This remains compile and functional evidence, not a release-mode XCTest run
or hardware qualification.

The next compatibility slices are applied for integration. UndoManager now
uses weak targets and safe target-specific clearing, guards reentrant replay,
and supports nested registration disabling; automatic editor registration,
grouping, document ownership, and native command routing remain open. Ordinary
bitmap stretch accepts finite layout proposals without enlarging its source
resource; aspect-fit/fill negotiation, tile/cap-inset rendering, symbol resizing,
and native pixel parity remain open. Their 30 and 10 authored tests still need
integrated execution. The bitmap fixtures required test-only imports to inspect
retained geometry; production access levels were not widened. The identity,
close-policy, undo, and bitmap filters are being rerun together, serially.

The first complete execution of those new suites passed all 30 undo tests,
10 bitmap tests, and 18 close-policy tests. It found one production identity
omission: the ordinary background builder did not append its background role,
so prestructured content and background could have identical paths. The
original failing assertion is unchanged; the builder now supplies that role.
The subsequent broader run passed 353 XCTest executions across 21 targets
and 17 serial invocations, with zero failures or skips. All 37 identity cases
passed, alongside existing binding, editor, geometry, window, Settings,
observation, scroll-reader, Canvas, gradient, and backend-lifetime checks.
Evidence is `artifacts/goal-third-batch-focused-v4.log` and its summary JSON.
Undo and bitmap changes are committed separately as `1e922d2` and `f6d098f`.
Expanded Quick/Full, raw renders, and the next combined push remain pending.

Mounted State implementation can now proceed on this tested identity
foundation. Retirement must release registry ownership and revoke writes and
invalidation without redirecting escaped bindings to a replacement mount.
An escaped binding or installed-value handle may legitimately retain the last
mounted Value until that external handle is released; a generic nonoptional
getter cannot promise both continued reads and zero retained payload. This is
a value snapshot, not a deep freeze of referenced objects. Tests must separate
registry-only release from externally retained values, cover stale projected
reads and rejected writes, and prove release after those external handles are
dropped. Native SwiftUI stale-access behavior remains unqualified. This refines
the lifecycle implementation detail without closing any original completion
gate or claiming State storage is already installed.

Material reference diagnostics now add six public SwiftUI fixtures with two
captures each: a bare pattern, flat tint, ordinary material, and material
inside compositing group, drawing group, and content blur. Fine/coarse contrast
and repeated-control checks reject missing, opaque, transparent, shifted, or
unstable captures instead of mistaking them for verified blur. The integrated
Windows helper passed 31 synthetic checks in debug and release; its native
capture mode correctly refused Windows without creating capture output.
Contracts, strict lint, and patch checks passed. These checks validate the
classifier, not AppKit compilation, native material behavior, or rendered parity.

The existing macOS reference workflow will capture these candidate observations
and provenance using its documented compatible toolchain. It is not the pinned
SDK qualification workflow. An unattached NSHostingView cache may omit
compositor effects; a failed positive control remains explicitly inconclusive.
Even a passing direct-material control does not qualify every isolation wrapper.
No production renderer, reviewed baseline, SDK pin, or skipped material test was
changed. Quick and Full now run the synthetic classifier, and Quick also gates
the tested undo-manager and bitmap-stretch suites. Native artifacts and review
remain pending until the accumulated commits are pushed and hosted jobs run.

Hosted Windows validation for `316ea9b` has now completed. All 169 Windows
functional shards, portable tests, builds, and five raw renders passed, but
the gallery gate failed on 67 of the 85 reviewed images. The runner also
skipped three variable-font tests because Segoe UI Variable was unavailable,
in addition to the existing material-backdrop skip. This is a failed hosted
Full run, not a passing release gate. Its gallery and demo artifacts are
preserved under `artifacts/goal-windows-ci-33110144711/`; their ZIP hashes are
`c320f5f6aa2a04434c4bd542c6f4934cc277373aca2ae4dc43c5cd9859c493fb` and
`2b3f9b35acaa2bb8284780245f3ce2891ef7af05271fece1f7f5e8623bb2fa17`.
Font-profile comparison is in progress. Neither the 85 reviewed baselines nor
their thresholds may be changed to conceal unexplained differences. The
portable Ubuntu/macOS workflow passed; the pinned SDK workflow remains failed
at inventory construction despite having exported all four requested graphs.

Optional asynchronous GPU timing is now integrated for validation. It uses an
eight-slot ring of disjoint/start/end queries and at most 24 nonblocking
GetData calls per drain, without flushing, waiting, or requesting a frame.
Results carry the issuing device generation and frame number; reports join
them to that frame's warmup and adapter classification instead of the later
polling frame. Missing, disjoint, full-ring, failed, cancelled, and recovery
outcomes remain explicit, and software-device measurements cannot qualify
hardware. Collection is disabled unless `--diagnostics-gpu-timing` is supplied.

The focused integration run passed 208 XCTest executions across 16 targets
and nine serial invocations, with zero failures or skips. This includes all
57 new query, host, and report cases, plus related renderer, recovery,
diagnostic-accounting, pacing, host, and ownership tests. Both native query
tests ran on Microsoft Basic Render Driver with `isSoftware=true`; they
checked completed intervals, cancellation, tracked COM release, pixel output,
and device recovery. Evidence is `artifacts/goal-gpu-focused.log`. A review
also found and corrected an expensive metadata lookup inside CPU frame timing
and stale draw/phase counters on skipped render attempts. Deterministic clock
tests preserve the existing CPU timing boundaries with collection on or off.
The release build, expanded Quick/Full, native telemetry sample, and combined
push still need completion. GPU command intervals do not measure display
completion or native input latency, and all hardware qualification flags remain
false until the original evidence requirements are met.

The integrated GPU timing sources now also pass the optimized executable build
in 225.66 seconds (`artifacts/goal-gpu-release-build.log`). Contracts and strict
lint pass. The four GPU timing suites were added to Quick; Full discovers them
with the rest of the test suite. This adds release compilation evidence while
leaving broader validation, live telemetry, and hardware acceptance pending.

### Third-batch validation and SDK indexing repair

At clean commit `fce78ec`, expanded Quick passed 1,387 XCTest executions and
nine Swift Testing cases across 88 XCTest invocations, plus the 31 synthetic
material-classifier checks. There were no failures and one existing
material-backdrop skip. The log and summary are
`artifacts/goal-third-batch-quick.log` and
`artifacts/goal-third-batch-quick-summary.json`. Full validation and hosted
qualification remain separate pending work.

Two 32-second release diagnostics runs completed with exit code zero on the
RTX 5090 at 1280 by 720 pixels, 96 DPI, and a reported 59 Hz display. The GPU
run joined 1,234 valid post-warmup intervals to their issuing frames; its one
remaining query was explicitly cancelled at finish, with no query failures,
dropped results, duplicate joins, or orphan results. The CPU-only control
issued no GPU queries and reported no GPU measurements. Their directories are
`artifacts/goal-native-gpu-89036e95907f46aeac50d863fd928f26/` and
`artifacts/goal-native-cpu-89faa19abc7a406295e825ac0f0efd33/`. The executable
SHA-256 was `e2a517a2764e303b831e90cb50ce3d5bf6c494f31223783807d587bc6569143c`.

These runs validate instrumentation only. The launcher's main-window probe
did not establish a visible window, other isolated agents could run compiler
or script work, and input was the declared synthetic retained-runtime script.
They do not qualify frame delivery, input latency, physical display identity,
or the 60/120/144 Hz targets. Existing pacing data was copied into a process
profile and the original file remained unchanged; Foundation continued to use
the real Windows known folder, whose demo-settings file was verified absent
before and after. An earlier harness attempt refused that path assumption
before launch; another retained a report but lost its process exit-code
observation. Those attempts remain recorded, not promoted to successful runs.

The CPU-only report also exposes substantial rebuild work worth investigating.
Its 287 rebuilds are accumulated into 235 frame samples: the 71.74 ms rebuild
p95 is a per-frame accumulated value, not a single-reload percentile. Node
construction includes nested child body evaluation and identity propagation,
so the small initial-composition timer cannot isolate all body work. A source
audit found repeated full identity-prefix copies/hashes and candidate-bucket
shifts; controlled attribution and safe optimization remain pending. No old
capture is treated as a comparable baseline or proof of a new regression.

The SDK inventory repair now streams JSON records, sorts case-sensitive
identifiers through bounded disk runs, and writes the final inventory without
a whole-file object graph. Raw numeric representations, metadata, declarations,
relationships, and both architecture exports remain intact. The exact LLVM
`arm64`/`aarch64` alias is accepted while preserving the graph's raw spelling;
unrelated architectures are still rejected. Record and nesting budgets fail
explicitly rather than truncate the API surface. No total SDK declaration or
file-size cutoff was added.

Integrated tooling tests passed 489 assertions on each of PowerShell 5.1 and
7.6.4, plus 18 large-memory assertions on each and 20 checkout assertions.
The large fixture exceeds the original whole-string limit: a 1,351,649,097-byte
graph with 160,003 declarations, 160,000 relationships, and an 80,003-occurrence
identifier. Peak working sets were 164.7 and 191.5 MiB. Contracts and whitespace
checks passed. Native Darwin peak-memory collection remains unexecuted locally;
its public getrusage adapter records actual kernel byte units and must run in CI.

Root reindexing of the actual 22 preserved graphs took 30.30 seconds and
168.5 MiB peak working set on PowerShell 5.1, and 44.32 seconds and 208.2 MiB
on PowerShell 7. Both produced exactly 134,147 identifiers, 300,436 declaration
occurrences, and 309,048 relationships, with a 1,012,693,296-byte inventory
whose SHA-256 is `e77f25fc01bf355d476740bf16ac4ea5fb54da7f0a7495e6fd5037686de4a063`.
The independently rehashed source graph set still matches
`cae2c67e354a2d82108809f28c7586dc7db1c764bb11234801fff345021227a8`.
Reports are under `artifacts/goal-sdk-root-actual-ps51/` and
`artifacts/goal-sdk-root-actual-ps7/`; the original capture still says failed.
Reindexing does not manufacture a successful native capture, review the pinned
identity, reconcile public interfaces and overlays, or prove API behavior.
The fixed hosted capture must still complete before those audits proceed.

The CI gallery investigation reproduced all 85 canonical baselines locally
(84 exact, one within the unchanged noise tolerance). Forcing the existing
classic-font diagnostic mode reproduced 68 hosted images exactly and passed
69 comparisons. Every remaining difference was confined to mapped icon
regions; ordinary text, chart geometry, and chrome outside those regions were
identical. Microsoft's documented MDL2 folder design matches the narrow folder
seen in CI, so this evidence does not justify changing the production renderer.
The original failed CI run did not record its actual icon face or font files.

Gallery tooling now records six allowlisted DirectWrite family-availability
queries, relevant registered font-file hashes and embedded versions, OS and
DirectWrite context, and separate executable/source observations. Initial
evidence survives build or render failure, and CI uploads it even when a later
step fails. Existing images, skipped builds, and failed builds are explicitly
distinguished from fresh successful invocations. The gallery JSON report gains
schema 2 provenance without changing its pixel comparison, thresholds, or
baseline selection. Actual glyph-face ownership and accepted font profiles
remain unqualified; a passing pixel comparison does not fill those gaps.

Root tooling tests passed all 44 assertions on PowerShell 5.1 and 7.6.4. The
native collector observed all six local families and embedded versions for
15 relevant files. Two raw retained-runtime smoke fixtures passed with default
fonts and correctly failed with forced classic fonts against the original
baselines. Both reports retain unqualified font-profile status. Evidence is
`artifacts/goal-font-root-native.json`, `artifacts/goal-font-root-default-smoke/`,
and `artifacts/goal-font-root-classic-smoke/`. No fonts were installed or copied,
and no baseline, pixel threshold, or runner was changed. A newer Server runner
label alone does not establish the required fonts. The next hosted artifact
must supply actual environment evidence before choosing a matching runner or
reviewing a separate supported font profile.

### Third-batch local validation checkpoint

Full passed at clean source commit `5859bcb`: 3,753 passing XCTest cases and
one existing material-backdrop skip, plus 134 passing Swift Testing cases.
All 178 Windows shards covering 282 targets passed, as did the separate
portable invocation, debug and release executable builds, five raw demo
renders, and all 85 reviewed gallery baselines with unchanged thresholds.
The 31 synthetic material-classifier checks, 489 SDK-tooling assertions, and
44 font-provenance assertions also passed. Strict lint passed all 30 Swift
files changed since the preceding push. The log is
`artifacts/goal-third-batch-full.log`, SHA-256
`241aaba535f14bb207ab7b025f6884ecfe8372ecaa0bc2fa20fc92154dc20df6`.

The summary counts were independently reconciled against individual test-case
outcomes. Full has 3,754 XCTest outcomes across 179 invocations when the skip
and separate portable invocation are included. The earlier Quick summary
omitted a suite reported with singular `test` wording: its exact total is
1,387 passed plus one skipped across 89 invocations, with nine Swift Testing
cases. This corrects reporting, not a test failure or an acceptance threshold.

All five new raw images were inspected. Scene output retains rounded controls
and backdrop filtering; frame fallback still has documented visible geometry,
text, and material differences. The local gallery pass neither qualifies that
fallback as visually equivalent nor resolves the hosted font-profile failure.
The unchanged skipped case is
`RenderPassAbstractionTests.testMaterialInsideADrawingGroupBlursNothing`;
native material evidence and the complete grouped-backdrop contract remain open.

A further 32.01-second release GPU-diagnostic run at the same clean source
completed with exit code zero, 1,226 valid post-warmup query intervals and one
explicit finish cancellation, without query failure, loss, or duplicate joins.
Its 30.51-second post-warmup sample span is recorded under
`artifacts/goal-native-gpu-29551ea17fa145b48bc476700984e98f/`.
A delayed five-second process probe still returned no main-window handle.
That observation is not proof of visibility or display delivery; all hardware,
input-latency, and presentation-deadline qualification remains false. Both
original user preference/pacing-file observations remained unchanged.

The pinned SDK workflow now has a separate serial material capture step after
a completed export. It verifies the captured compiler, SDK, source commit,
manifest hashes, native OS/architecture, and clean build inputs, then builds
the unchanged public fixtures in a fresh temporary scratch directory. It
preserves raw captures and provenance even for inconclusive controls. It does
not read the large API inventory, change pins, substitute another compiler,
or treat an Intel capture as arm64 native execution.

Root validation of this post-Full script/workflow addition passed 265 assertions
across 100 synthetic fixtures on each of PowerShell 5.1 and 7.6.4, plus parser,
workflow, and architecture checks. Quick and Full now run those synthetic
provenance checks too. Logs are
`artifacts/goal-material-provenance-root-ps51.log` and
`artifacts/goal-material-provenance-root-ps7.log`. No Swift production or test
source changed after the recorded Full run. Actual macOS compilation, capture,
control review, and hosted results still require the next combined push.

The next integration batch remains within the original state and editing
requirements: automatic nonsecure editor undo and mounted `State` ownership.
Their isolated source probes are not host-test evidence. A combined teardown
review found that state-value destruction can reenter undo, while undo-target
destruction can reenter a mounted binding. Integration must revoke both editor
replay and state writes before either cleanup releases application payloads;
real-host tests must cover both directions before this behavior is accepted.
All nine original completion gates remain open.

### Third-push hosted evidence and Unix-path correction

The nine third-batch commits were pushed together as `e33a9fa`. Ubuntu and
macOS portable jobs passed, and macOS reference run `33120203035` built and
captured its fixtures successfully. The separate pinned SDK run `33120202986`
failed in the material-provenance fixtures before export. Its first failure
was obscured by cleanup reaching the same broken filesystem resolver: on Unix,
PowerShell's parent-path operation lost the root qualifier while resolving
`/var` to the relative target `private/var`.

The resolver now combines a relative link target with its already resolved
filesystem parent. Canonical containment, alias depth, and owned-directory
cleanup checks remain enforced. A second cleanup failure preserves the first
exception and stack, and a cleanup-only failure still fails the test. Root
validation passed 272 assertions across 100 material-provenance fixtures on
each PowerShell version, plus all 489 existing SDK-tooling assertions. The
native Unix alias assertions and a successful pinned export still require a
new hosted run; local tests do not promote the earlier failed captures.

The successful floating macOS capture is an inconclusive material observation,
not normal-material or group conformance. Its manifest records macOS 15.7.7
build `24G720`, arm64, Xcode 26.3, SDK 26.2, and Swift 6.2.4, with Reduce
Transparency enabled. The ordinary material and every grouped variant are
opaque in the measured regions; the pattern and flat-tint controls remain
distinct. This accessibility setting and the unattached hosting view prevent
inferring ordinary backdrop behavior. No system preference was changed and
no threshold was relaxed. Verified raw artifacts are under
`artifacts/goal-macos-reference-33120203035/`; the material ZIP SHA-256 is
`4072e8e6c56ee0b1beb5137bb50fe4b8e4f3d606b1cd60e7d276670b6aa6e960`.

### Automatic editor undo integration

Nonsecure TextField and TextEditor now register accepted text changes with
their inherited undo manager, preserve grapheme replacement deltas and
selection, and use current bindings after reconciliation. Exact Ctrl+Z,
Ctrl+Shift+Z, and Ctrl+Y retain explicit command precedence and enforce
runtime, modal, enabled, and IME eligibility before consuming history.
SecureField stores no automatic plaintext undo history. A shared manager is
never cleared wholesale during editor cleanup. Typing coalescence, general
undo groups, native Edit-menu validation, document identity inference, and
the complete document template remain separate open work.

Integrated tests exposed and corrected two real regressions. Reconciliation
must preserve the attachment already established by a retained node's
controller setter, even when that slot previously had no controller. Sheets
must also retain the same wrapper and base-child slot while absent and
present; changing the wrapper had detached the background editor and erased
its valid history. Both Boolean and item sheet paths now preserve that
identity without weakening modal replay or removal cleanup.

The corrected focused run passed 275 XCTest cases across 16 targets and
13 serial invocations, with no failure or skip. It includes all 46 new host
undo cases, 18 session cases, four sheet identity/history cases, and existing
editing, geometry, IME, selection, modal, close, and host coverage. Evidence
is `artifacts/goal-editor-undo-focused-v4.log`. Earlier failed logs remain
preserved; a new sheet fixture's invalid test-hook spelling was corrected to
the existing four-argument testing override without changing its assertions.
Quick now includes the new suites. Mounted-State interaction and complete
batch validation still await the next integration; no native behavior or
release qualification is inferred from these focused tests.

### Mounted State integration and first production test pass

Ordinary custom struct views now receive host-owned State cells before body
evaluation. Typed structural identity selects an owner; typed declaration key
paths and concrete existential types select its property slots. The installer
rewrites a copy, leaving the source seed untouched. Reconstruction and keyed
reordering preserve surviving owners; separate occurrences and hosts receive
separate cells. Retired bindings keep their last readable value, reject writes
before projected getters or setters, and never reconnect to a new generation.
Reference values retain normal alias semantics rather than being deep-copied.

Root and deferred GeometryReader candidates use provisional ownership epochs.
Abandonment preserves the committed tree and its observations; adopted builds
finish before queued builds under their captured transaction. A host mutation
revision rejects obsolete requests without allowing a redundant control
invalidation to replace a binding transaction. Inactive known declarations,
disjoint ViewThatFits candidate scopes, and typed OutlineGroup rows have
specific coverage. Opaque inactive bodies, eager outline realization, and
independent simultaneous transaction behavior remain documented limits.

The adapter uses typed Swift reflection key paths, not raw field writes.
Unsupported class/enum dynamic properties, owning immutable declarations,
ambiguous metadata, and ownership replacement during custom update are
diagnosed. Consumer reflection metadata must stay enabled. StateObject
ownership and lazy initialization are not activated by this slice; inherited
View.body builder support and complete native lifecycle conformance also
remain open. [MountedState.md](docs/MountedState.md) records the implementation,
reentrancy, retirement, and toolchain constraints in more detail.

The first actual production build succeeded. Binding host transactions passed
nine cases and the installer passed all 24 cases before the combined editor
suite failed. A separate serial run then passed 81 cases across ten state,
container, epoch, queue, and accounting targets with no failures or skips.
Evidence is `artifacts/goal-mounted-state-focused.log` and
`artifacts/goal-mounted-state-independent.log`; these are partial integration
results, not a passing combined suite or Full validation.

The failing combined run exposed a stale selection index during a synchronous
editor rebuild after undo shortens text, plus disappearance fixtures whose
scene-only render had never delivered appearance callbacks. Both require
runtime corrections and preserved assertions before acceptance. The intended
teardown order revokes editor replay and State writes before releasing either
kind of application payload. Quick now includes these ownership suites, but
no new completion gate is checked by this first pass.

The existing identity, geometry, observation, settings, sheet, and transaction
regression selection also passed 179 cases across 18 targets and nine serial
invocations (`artifacts/goal-mounted-state-existing.log`). A narrow selection
correction now walks only valid boundaries in the current string, using an
incoming stale index for comparison rather than passing it to String APIs.
All eight new safety cases passed, including real mounted TextField and
TextEditor shortening. The combined suite now runs all eight cases without
the crash; six pass, while the two scene-disappearance cases still await the
shared lifecycle correction. Unknown foreign-string provenance permits only
a safe positional fallback, not reconstruction of the original logical caret.
These intermediate results are in `artifacts/goal-state-selection-correction.log`.

### Fourth-batch reference provenance and hosted review

Material captures now record effective SwiftUI environment observations,
system accessibility flags before and after each capture attempt, application
activation, host attachment/backing metadata, and AppKit's recommended bitmap
format. Unobserved values stay explicitly unknown. Reused environment
observations carry their original sample count/time rather than pretending to
be fresh reads. The old top-level accessibility record is retained and labeled
as an end-of-run sample; it cannot prove the settings of an earlier capture.

All six fixtures, two repetitions, 50 ms settling, fixed 2x RGBA capture,
public view-cache API, classifier thresholds, and system preferences remain
unchanged. The recommended bitmap is inspected after capture and never replaces
the actual bitmap. Root debug and release self-tests passed 46 checks, comprising
31 unchanged classifier checks and 15 added metadata checks. Native AppKit
compilation and capture remain pending; provenance alone cannot make the
previous opaque positive control conclusive.

Third-push Windows run `33120202997` completed 178 shards covering 282 targets:
3,750 XCTest cases passed, four were skipped, and none failed. Both debug and
release demo builds passed. The skips are the existing material case and three
variable-font cases. The run then failed the unchanged gallery gate with 67
of 85 entries regressed. Actual collected font metadata confirms absent Segoe
UI Variable families and Segoe Fluent Icons, with classic Segoe UI and MDL2
present. This is font availability evidence, not actual glyph-face ownership
or approval of a second baseline profile. Current pixel and font comparisons
are being reviewed without changing fonts, runner labels, or thresholds.

Verified artifacts are under `artifacts/goal-windows-ci-33120202997/`. The
gallery ZIP SHA-256 is
`2b1ce4bc531d364b0b2c96826023c31a10dd92449ded6eb5a277e8a1e4e94a22`;
the demo ZIP SHA-256 is
`d6caeb30bb3f1fe0a9e0d1051c448469af30237ea516f35df854aec11c2f6b5e`.
Hosted visual validation and the exact release-revision gate remain open.

### Identity matching experiment, not performance qualification

The isolated identity probe now compiles and verifies both an unmetered release
executable and a separate operation-count executable against frozen source
`fce78ec`. Both verification runs and the count run agree on all 3,842 matching
inputs across five algorithms and 3,624 construction-identity checks. The
count report has 105 matching observations across 21 inputs and 15 separate
construction/hashing observations. Recorded source, compiler, executable,
result, and log hashes were reconciled with no mismatch.

A direct single-child path avoids dictionary hashing for tested singleton
matches; an all-typed unchanged-order path replaces repeated dictionary work
with corresponding identity comparisons. These are candidate observations,
not an accepted production optimization. Payload counters omit segment
traversal, allocation, ARC, String-tag work, array shifting, and elapsed time.
No timing workload ran. Current reconciliation also performs a departure
prepass, which the frozen single-call probe does not measure as a whole.

The original probe preparation was stopped after PowerShell expanded provider
metadata attached to a compiler-version string during JSON serialization.
Version 2 uses plain file strings and bounded data-only serialization; its
44 guard assertions passed on PowerShell 5.1 and 7. Original inputs and failed
run artifacts remain unchanged. The version-2 source manifest SHA-256 is
`741e226ee4862a9b02f73fa6443b7a49478518bede10d9abaedb527b2cba0ce3`;
the build manifest SHA-256 is
`d97db4578ad58ffe8e2bfa18396ec0f33ed0e783d58be1dbe5e26dcbd98503fa`.
Root invocation records are `artifacts/goal-identity-probe-v2-prepare.log`,
`artifacts/goal-identity-probe-v2-verify.log`,
`artifacts/goal-identity-probe-v2-metered-verify.log`, and
`artifacts/goal-identity-probe-v2-counts.log`. Controlled timing, production
integration, and whole-app hardware acceptance remain separate open work.

### Editor adoption correction

The next existing-editor regression run exposed another teardown integration
error: moving a newly built editor from its unattached construction parent
revoked its fresh undo session before first adoption, blocking its first text
write. The correction must distinguish an attached departing editor from a
never-adopted candidate without reviving a retired session. Existing identity
replacement and sheet-close assertions remain unchanged. The failed run is
preserved in `artifacts/goal-selection-editor-regressions.log`.

### API audit ledger intake and complete captured records

`scripts/build-swiftui-api-audit.ps1` now builds an immutable first-stage
ledger only from a successful, hash-consistent candidate capture. It streams
every raw graph and the complete inventory, independently reconciling precise
identifiers, declaration occurrences, relationships, graph partitions, counts,
and hashes. Raw symbol mixins and signatures are retained, as are interface
and overlay source lines and producer headers. Selected work queues never
remove entries from the ledger. Every record remains unreviewed: an exported
identifier count is not an API implementation or conformance percentage.

The tool does not repair a capture, change the pinned SDK, infer native
behavior, or classify Windows implementations. It distinguishes interface
producer metadata from extractor identity and preserves unknown, deprecated,
underscored, synthesized, extension, and architecture-specific declarations
for review. Complete scope and remaining mapping work are documented in
[SwiftUIAPIAudit.md](docs/SwiftUIAPIAudit.md).

Root validation passed 391 ledger, 32 intake, 19 default memory, and 489
existing baseline-tooling assertions on each of PowerShell 5.1 and 7. The
original failed native capture was also rejected without modifying its status
or publishing a ledger. Both runtimes reindexed all 22 original raw graphs
after the streaming-reader extension and reproduced the same inventory
SHA-256, `e77f25fc01bf355d476740bf16ac4ea5fb54da7f0a7495e6fd5037686de4a063`.
This is a regression check of those captured bytes, not a successful export.
Logs use the `artifacts/goal-api-audit-` and
`artifacts/goal-fourth-sdk-reindex-` prefixes.

Separately, the isolated large synthetic regression passed 20 assertions on
each runtime with an inventory exceeding 2.74 GB and 320,038 declaration
occurrences, including one 320,000-occurrence group. Final measured process
peaks were 181.6 MiB on PowerShell 5.1 and 241.9 MiB on PowerShell 7; these
include generation, indexing, audit, and checks. They are not native API or
application frame-timing evidence. Quick, Full, and the pinned macOS workflow
now include the three default audit fixture scripts; the large case stays
opt-in. A fresh successful pinned export and actual declaration/interface
review remain required under the unchanged original gates.

The current CI font investigation also independently reproduced the retained
classic-font comparison: 68 of 85 images are exact, 69 pass the unchanged
thresholds, and every differing pixel in the remaining 17 images lies inside
the recorded icon regions. All 13 shared registered font files differ in
version/hash between the recorded machines, including MDL2 1.84 versus 1.86.
Those facts localize the discrepancy without identifying each final glyph's
font face. No renderer defect, accepted alternate baseline, or native glyph
ownership is inferred. The evidence manifest SHA-256 is
`795431fa0bb4a1e07dfa5cc3713d3d82a11fb435921c43f47272244d8b43379e`.

### Editor construction and lint validation follow-up

The editor adoption correction now requires an attached controller before
revoking its undo ownership. Moving a fresh editor out of an unattached
construction parent no longer disables its first write; reattaching an
already retired controller still cannot restore its session. Root validation
passed 117 tests across the undo, editor session, construction lifetime,
selection-index safety, editing, and geometry filters, with no failures or
skips. All three previously failing editor regressions passed unchanged.
The new construction tests cover both TextField and TextEditor. Their
construction preconditions use public tree structure rather than widening
access to the runtime's private attachment field. The exact run is retained
in `artifacts/goal-editor-construction-correction-v2.log`. Combined
disappearance tests still await the separate scene lifecycle correction;
this focused result is not Full validation.

`scripts/lint.ps1` now rejects every missing, blank, or directory entry in an
explicit `-Path` list before invoking the formatter. It does not split
literal comma-containing filenames or discard invalid members of mixed
lists. Default changed-file discovery, formatter policy, and ContractsOnly
behavior are unchanged. Root ran 27 synthetic cases and 67 assertions on
each of PowerShell 5.1 and 7; both passed. The new fixture script uses owned
temporary files and fake tools, so these results test selection and failure
propagation, not Swift formatting. Quick and Full include this fixture gate.
Root logs are `artifacts/goal-lint-paths-root-ps51.log` and
`artifacts/goal-lint-paths-root-ps7.log`. This closes the earlier misleading
no-files lint success without replacing the actual changed-file lint run.

### Shared scene and frame lifecycle integration

The primary scene renderer previously did not deliver the lifecycle callbacks
that the frame fallback delivered. This also prevented real disappearance
callbacks from running for scene-only hosts. The shared runtime now stages
appearance, node callbacks, task launches, and size changes after settled
layout on either render path, before paint recording. Layout queries, atlas
retries, isolated recordings, and cached paint replay do not create additional
appearances. Candidate revision checks preserve callback-driven invalidation
and postpone callbacks whose retained geometry or configuration changed.

Close and host release stop future delivery before revoking editor and State
ownership, then remove all owned task slots before invoking cancellation
handlers. A handler cannot launch new work on a closed owner. Deferred
appearance keeps the latest pending-only launches used by Timeline views and
does not duplicate a task already launched by the current node callback.
These are bounded runtime semantics; full native task identity, ordering,
and general task-key replacement/cancellation reentrancy remain unqualified.

The integrated increment has 26 new async tests and one strengthened existing
reentry test. Its first root compile exposed two accesses to a fileprivate
runtime field from ComponentHost. An internal node forwarding method fixes
that access without widening the field's visibility. The failed compile is
preserved in `artifacts/goal-scene-lifecycle-focused.log`; the corrected run
uses `artifacts/goal-scene-lifecycle-focused-v2.log` and is not yet a Full
validation result. Independent review also found that the two bitmap-only
ViewSnapshot overloads must cancel tasks when their temporary runtime ends,
including rendering failure. That narrow follow-up is being validated
separately; borrowed or explicitly returned runtimes must remain usable.

The second compile reached the test module and found the same private-field
assumption in one host fixture. The fixture now checks that the removed node
has no resolved layout frame and that changing its opacity cannot dirty its
former runtime. This tests the attachment behavior without exposing the
runtime field. The third focused run passed all 133 tests across ten targets
and seven serial invocations, with no failures or skips: all 26 new lifecycle
tests, three existing render-reentry tests, all eight combined State/editor
teardown cases, 18 mounted-State lifecycle cases, five editor-construction
cases, 46 editor-undo cases, 18 undo-session cases, and nine cache/replay cases.
The previously missing disappearance assertions passed unchanged.
`artifacts/goal-scene-lifecycle-focused-v3.log` is the passing run; the earlier
two compile failures remain recorded. The nonexistent
`GeometryReaderRuntimeTests` name selected no target in this invocation;
GeometryReader coverage comes from separately named suites and Full, not an
assumed extra result in this count.

Window-close lifecycle remains bounded: explicit close preserves the existing
pointer, focus, and window-closed callbacks, and both close paths revoke writes
before cancelling tasks. The retained tree is still inspectable afterward;
this increment does not add whole-tree `onDisappear` delivery when a window
closes. Full native window lifecycle behavior remains part of the original
requirement, not a completion claim from the conditional-removal tests.

The bitmap-only snapshot follow-up passed all 59 focused tests across seven
targets and three serial invocations, with no failures or skips. Its five new
async cases cover both owned overloads, genuine CPU-renderer invalid-size
failures after scene lifecycle delivery, cooperative task completion and
payload release, and unchanged caller ownership for borrowed and explicitly
returned runtimes. Nine existing snapshot tests and the lifecycle, combined
teardown, reentry, and selection-safety cases also passed. The run is
`artifacts/goal-snapshot-task-lifetime-focused.log`. Strict lint passed on all
12 remaining changed Swift files in
`artifacts/goal-fourth-working-swift-lint-v4.log`; earlier lint covered the
already committed State and selection changes. Full and hosted validation
of the combined revision remain required.

### Successful SDK export to unreviewed audit ledger

The pinned SDK workflow now passes explicit verified export paths, status,
counts, and hashes to `build-swiftui-api-audit-candidate.ps1`. It never selects
a newest directory after failure. Preflight rejects redirected artifact paths
and existing evidence directories; strict capture intake checks the compact
handoff against the actual source capture before ledger publication. Capture
bytes, seals, status, and SDK pins remain unchanged.

The workflow retains the complete raw capture, original inventory, complete
ledger, and small outcome records together. A material-capture failure does
not suppress an otherwise valid SDK ledger, but the job still reports that
failure. Cancellation skips the ledger. Every produced record remains
unreviewed, and a failed or merely reindexed capture remains ineligible.

Root passed 350 synthetic workflow assertions on each of PowerShell 5.1 and
7, with YAML parsing, four changed-script parser checks, and contracts also
passing. Logs are `artifacts/goal-api-audit-workflow-root-ps51.log` and
`artifacts/goal-api-audit-workflow-root-ps7.log`. Quick, Full, and the pinned
workflow now run all four default API-audit fixture scripts. Native export,
ledger creation from that successful export, and declaration/behavior review
remain pending; the synthetic result does not satisfy those requirements.

### Document/editor template implementation boundaries

The existing DocumentGroup constructors eagerly capture one document in a
binding that discards writes. Viewing/editing also attempt to construct from
an empty wrapper and can trap on a read failure. FileDocumentConfiguration
stores a Binding as its document value instead of providing the expected
value/projected-binding shape. The coordinator does not yet host document
sessions, and document environment actions remain no-ops. A selected file URL
or a successful standalone export is not a working document application.

The next document layer must reuse the existing coordinator and retained
controls, with a session per document and an owner-aware file service. A
first regular-file UTF-8 implementation is an incremental slice, not a cap
on the original document API or template requirements. Its acceptance must
include actual read/decode/write results, independent windows, recoverable
open/save failures, and correct saved-content checkpoints across undo/redo.
Save must not erase history or duplicate the editor's existing undo entries.

Dirty close needs one Save/Discard/Cancel decision per intent. Cancel, Escape,
cancelled Save As, or a write failure must keep the same editor and history
alive; Discard must not write. Only successful saving of the still-current
session/revision can approve a later close. Dialog results must recheck owner
and session validity before writing and again before applying completion.
The presentation binding alone cannot distinguish exporter cancellation from
success or failure. Vertical caret navigation, keyboard selection by visual
line, and caret-revealing editor scrolling are also still required for a
complete multiline template. These are implementation gaps, not exceptions
to sections 5, 6, or 7. The catalog now distinguishes implemented editor undo
from the remaining document workflow.

### Fourth combined Full run: tab-remount regression

The first Full attempt on clean revision `7b486f7` stopped at Windows shard
37 of 190. Tooling fixtures and portable tests passed, and the log contains
705 passing XCTest cases, one failing case, and 16 passing Swift Testing
cases before termination. It did not reach the debug/release product build,
screenshot, or gallery gates. The log is
`artifacts/goal-fourth-full-7b486f7.log`, SHA-256
`608b7bd512600420c5908d9467cc8a50c9e84db3ef5a8b044c3058d926eb53f2`.
This is a failed Full attempt, not qualification of the combined revision.

The unchanged observation-showcase remount test expected its new page's
appearance callback to reset the derived phase to Idle. The viewport was
replaced and its offset and visibility reset, but the phase remained the old
Idle-from-Interacting value. A focused rerun reproduced the failure. Temporary
instrumentation showed that the showcase and its printed ancestors had not
appeared; eight additional frames did not deliver the callback. That
instrumentation has been removed without changing the original assertions.

Source inspection traces the missing callback to removal-transition ownership:
adopting a fresh tab page first removes it from an unattached construction
parent. That removal currently starts a fade and marks the incoming page as
an outgoing overlay even though there is no runtime to register or retire
the overlay. The shared lifecycle stage correctly refuses callbacks through
an outgoing-overlay ancestor. The correction must require runtime ownership
before starting removal transitions, while preserving real outgoing fades,
disappearance, and the lifecycle eligibility check. Construction transfers,
unattached bulk removal, and tab changes on both render paths need regression
coverage before a new complete Full run.

The correction now checks the owning parent's runtime before either individual
or bulk removal can start a transition. Direct transition behavior and lifecycle
eligibility are unchanged. Four new async tests cover construction transfer,
unattached bulk removal, and public TabView switches from the first page to the
second and back on both scene and frame paths. They verify fresh incoming nodes,
descendant appearance, real outgoing overlays at intermediate and final times,
disappearance, and rebuilds that must not restart the incoming fade.

Root passed all 56 tests across nine targets and three serial invocations,
including the unchanged demo phase assertion, the four new cases, existing tab
crossfades, shared lifecycle and reentry, and combined editor/State teardown.
There were no failures or skips. The log is
`artifacts/goal-fourth-transition-focused.log`, SHA-256
`5717a0711b6d582129c94827047809078a94f7780e3577e4e72a095ea92a1fda`.
Contracts passed before and after the correction, and strict lint passed on
all three changed Swift files. Quick now includes both new suites. These tests
use retained rendering and controlled time; they do not qualify native frame
pacing or every reentrant transition-adoption scenario. A new Full run must
start at its first shard rather than reuse the failed run's partial result.

### Fourth Full retry: preserve the paint-invalidation test's purpose

The clean `8304d98` retry passed the previous remount failure and reached shard
107 of 190. It recorded 2,175 passing XCTest cases, one existing skip, one
failure, and 58 passing Swift Testing cases before stopping. The log is
`artifacts/goal-fourth-full-8304d98.log`, SHA-256
`cb55699c8f8abace9eee76246022f7e180b91b915f991f1caa37f0e109b21178`.
The product build, screenshot, and gallery gates were again not reached.

This failure was an obsolete fixture assumption: the paint-invalidation test
used `onAppear` to change an already-painted sibling and required a stale first
frame. Appearance now runs before painting, so that color change is already
visible in the first frame; its dirty-state and next-frame assertions still
passed. Independent source review confirmed the phase distinction.

The original test now makes its mutation from an actual Canvas paint callback
and runs on both render paths. It preserves the stale-first-frame, retained
invalidation, and corrected-next-frame assertions, and also requires the
follow-up pass to settle. A separate test checks appearance before paint on
both paths, retained invalidation, exactly one appearance, and a clean
follow-up. This changes the fixture to exercise the intended contract; no
production behavior or dirty-flag requirement was relaxed.

The corrected phase fixtures and related lifecycle, Canvas, prepaint, geometry,
animation, reentry, and cache suites passed 90 tests across ten targets and four
serial invocations, with no failures or skips. The main focused log is
`artifacts/goal-fourth-dirty-phase-focused.log` (68 cases), SHA-256
`6a8cd12a49ab1f3ce9306d562c429f9536ec1476af8d2b7183a8b41679b715e1`;
the additional 22 cache cases are in
`artifacts/goal-fourth-dirty-phase-cache.log`. An initially requested nonexistent
`SceneCommandCacheTests` filter contributed no cases; the separate cache run
selected the actual `CacheComplexityAndReclamationTests` and
`CompositingGroupBitmapCacheTests` suites. Strict lint and contracts passed.
The broader read-only test audit found no additional assertions depending on
the old appearance/paint ordering. This focused result still requires a fresh
complete Full run.

### Fourth Full retry: construction stack headroom

The clean `9e4a0cf` retry passed both earlier failures and stopped at shard
141 of 190. It recorded 2,803 passing XCTest cases, one existing skip, and
118 passing Swift Testing cases before the test process crashed. There was
no failed assertion: `testDeeplyNestedSwiftUIHierarchyStillEmitsItsLeaf`
started without returning a result. Product builds, screenshots, and gallery
comparison were not reached. The log is
`artifacts/goal-fourth-full-9e4a0cf.log`, SHA-256
`f34a768c3b8fcce1247b973c7027e0f6a078de8ed254258c5fefa11dcecd078c`.

An unchanged single-case rerun reproduced the crash. Windows Error Reporting
identified exception `0xc00000fd` (stack overflow). The dump backtrace in
`artifacts/goal-fourth-depth-dump-backtrace.log` shows typed component
construction and repeated deferred identity/context scopes through VStack
and padding; it does not show painting or lifecycle traversal. The snapshot
does not install a State coordinator, so registry installation is not on
this failing path. The debugger also emitted type-reconstruction diagnostics;
those are separate from the recorded process exception.

Each nested scope previously saved a complete ViewBuildContext across child
construction. The narrow correction under test stores the current context in
a private immutable box, saving and restoring references while keeping the
existing synchronous, main-actor, value-returning scope API. It must preserve
environment reads, identity, nesting, reentry, and payload release. This adds
a small allocation per scope; no timing or allocation improvement is claimed.
The existing 60-level hierarchy, leaf-glyph assertion, traversal depth limit,
and executable/thread stack settings remain unchanged. Focused scope and
headroom tests and a new complete Full run are still required.

The storage-only correction now passes the original crashing case without a
reference-taking overload or changes to deferred identity wrappers. Across
five serial invocations, 75 cases in twelve targets passed with no failures
or skips: 17 traversal/identity/dispatch/Canvas-sampling cases, 54 environment
and Canvas cases, and four new scope regressions. The separate first rerun of
the crashing case is additional reproduction evidence, not an extra distinct
case in that count. The logs are
`artifacts/goal-fourth-context-scope-regressions.log`,
`artifacts/goal-fourth-context-environment-regressions.log`, and
`artifacts/goal-fourth-context-scope-new-tests.log` (SHA-256
`380791ff9a62393aef5d7b4acb7cb5684542c25c1fa7256ec40c94b03a2f6bcd`).
Contracts and strict lint of both changed Swift files passed. Independent
source review confirmed scope restoration and immutable value-copy semantics.
Quick now includes both scope and traversal-headroom suites. A fresh Full
run is required before pushing the accumulated fourth batch.

### Native main-actor scheduling: isolated functional evidence

A standalone probe using the installed Swift 6.3 Windows runtime confirms a
live-host gap: the current GetMessage/TranslateMessage/DispatchMessage loop
delivered native messages but did not start or resume the queued MainActor
task before exit. A Foundation RunLoop variant delivered the same native
messages and both task phases on the HWND owner's thread. Each variant was
run twice from the same optimized executable and returned the requested
WM_QUIT code 73. Only a hidden message-only window was created; no visible
application, user setting, or project runtime was changed.

The experiment uses a thread-local WH_GETMESSAGE hook to retain the quit
result. Foundation removed WM_QUIT with flags 3 (PM_REMOVE plus PM_NOYIELD),
so the removal check must test the PM_REMOVE bit rather than equality with
1. The earlier equality-only probe hung and was terminated by its owned
process watchdog; that failed evidence is preserved separately. Final source
SHA-256 is
`fc3626e67508031bc05fd0e4e9cad0948c5ec42b0928c44475169fbb7bfd1df3`,
and executable SHA-256 is
`4a05cb38c885adb85386d16c0575514e27de43d5534c75a6b7f6679803ee0b6e`.
Compiler arguments and loaded-library paths/hashes accompany the four result
records in the owned temporary native-scheduling probe directory.

Stable outer-loop counters and an observed waiting thread are narrow idle
witnesses, not CPU, latency, or frame-pacing qualification. The production
host, nested/modal loops, UI Automation's main-queue calls, callback lifetime,
hook installation failure, and shutdown still require implementation and
validation. Async XCTest success alone does not establish native app task
progress, and this standalone result does not close the lifecycle or native
smoke-test gates.

A subsequent queued-character probe rejects adopting the plain Foundation
loop. With a Unicode window and ANSI code page 1252, successful PostMessageW
calls queued UTF-16 units `0041`, `00E9`, `6F22`, `D83D`, and `DE00`.
GetMessageW delivered all five unchanged. Foundation's retrieval hook also
observed all five originals, but its dispatch delivered `0041`, `00E9`, and
three `003F` question marks to the Unicode window procedure. Native messages,
quit code, and task progress still passed, so those checks alone would have
missed the text corruption. Separate Unicode source, executable, reports,
and logs preserve this failure without altering the earlier four results.
Any scheduling correction must preserve Unicode input and native modal
routing as well as task progress; the Foundation loop is not yet a usable
production replacement.

### Fourth Full retry: remaining fixture assumptions

The clean `80b9429` Full retry passed the previous three failures and reached
shard 175 of 190. Its log records 3,595 passing XCTest cases, one existing
skip, one failing case, and all 134 Swift Testing cases. Product builds,
screenshots, and gallery comparison were not reached. The log is
`artifacts/goal-fourth-full-80b9429.log`, SHA-256
`35ec710ed918671bcbb8b2561cce687a2f8434c90de0126eaf8c3702fd2b136e`.

The item-sheet fixture expected the dismissed Text to be the physical root
node. The stable sheet shell deliberately remains present, with that same
base content as its child, to preserve editor identity and undo through
presentation changes. Independent inspection confirmed that the text was not
removed. The corrected assertion requires the complete descendant text list
to equal `["ROOT"]`, so ROOT occurs exactly once and DETAIL/CLOSE are gone.
The selected-item and dismissal assertions are unchanged. Existing raw and
hosted sheet identity tests separately check the shell, base, editor,
selection, modal input isolation, and undo/redo. Production is unchanged.

A diagnostic-only continuation from shard 176 found one more fixture failure
at shard 189: four absolute reload-counter assertions in the host environment
test. Its snapshot counts and every environment-value assertion passed.
Counting actual ComponentHost build attempts now includes the existing
presenter-attachment rebuild; only constructor setup is excluded. The fixture
now records its post-startup count and requires exact subsequent increments,
including no increment for a duplicate notification and the previously
unchecked hidden-window active-state increment. It does not suppress a real
build or relax notification coalescing. Independent accounting review agrees
with the documented counter semantics and other accounting fixtures.

That diagnostic continuation recorded 366 passing cases and one failing case;
the final shard was checked separately and passed 18 cases. Both are partial
diagnostics, not a completed Full run or a substitute for restarting at the
first shard. Their logs are `artifacts/goal-fourth-tail-diagnostic-80b9429.log`
and `artifacts/goal-fourth-last-shard-diagnostic-80b9429.log`. Both original
failures reproduced in isolated focused invocations before the fixture edits.
Focused validation and a new clean complete Full run remain required.

The corrected fixtures and related host, modal, sheet-identity, and accounting
coverage now pass 81 cases across six targets and five serial invocations,
with no failures or skips. The two sheet cases are in
`artifacts/goal-fourth-sheet-fixture-correction.log`; the other 79 are in
`artifacts/goal-fourth-fixture-regressions.log`, SHA-256
`2cff869e36bc59c697cc8d081063e4738c8cf183668d4fb7f321858084bff2f6`.
Strict lint passed on both changed test files, and contracts passed. Quick
now selects both sheet dismissal cases and the environment-notification case
explicitly. The compatibility documentation also states that retained async
test results do not establish progress in the native host's current message
loop. No production source changed in this fixture correction.

### Fourth batch: completed local validation at `22eb732`

The complete Full run now passes from the first shard on clean commit
`22eb7326820568f0c4aaadebf0b3e0f84eb30243`, source tree
`3cbdc4b11b9e2d72adba9100f163db0ee2246b49`. All 190 Windows shards covering
304 targets passed, along with the separate portable test invocation, tooling
fixtures, debug and release application builds, five raw retained screenshots,
and the gallery regression gate. A complete Quick run subsequently passed on
the same unchanged clean revision.

| Local validation | XCTest passed | XCTest skipped | Swift Testing passed |
| --- | ---: | ---: | ---: |
| Full | 3,981 | 1 | 134 |
| Quick | 1,641 | 1 | 9 |

Neither successful run contains a failed test. Both skips are the existing
`RenderPassAbstractionTests.testMaterialInsideADrawingGroupBlursNothing`
case; this material limitation is not resolved by the other passing tests.
Strict lint passed on all 45 Swift files changed since the third pushed batch.
The full original goal prefix was verified unchanged before both runs.

The five fresh raw images were opened and inspected: scene and frame dashboard,
dark and light scene gallery, and frame gallery. All 85 reviewed gallery
baselines passed with the existing channel tolerance 8, changed-pixel limit
0.5 percent, and maximum channel delta 64. No baseline, threshold, font
selection, or runner was changed. The frame fallback still visibly omits scene
effects; its usable output is not a claim of visual parity with the scene path.

The first Quick attempt stopped before Swift tests when Windows denied a
directory rename while publishing a synthetic API-audit memory fixture. The
failed staging directory was removed and no ledger was published. An unchanged
focused rerun passed all 19 assertions. Source review found no persistent
owned-stream leak, and the complete unchanged Quick retry also passed. The
cause of the single access denial remains unestablished; no automatic retry or
source workaround was added. This failed run remains separate evidence from
the successful retry, just as the four failed Full attempts and partial tail
diagnostics remain separate from the completed Full run.

The archive at `artifacts/goal-fourth-batch-22eb732/validation.json` lists
201 hashed evidence files totaling 26,013,301 bytes, including successful and
failed logs, source attestations, focused checks, the raw images, gallery
reports, and 85 current gallery renders. Its SHA-256 is
`6d463f1bd555d3f24b4349bbe9a933e5658608a806417d3611bdb63d721643cf`.
The successful Full log SHA-256 is
`6159767774af19286f17133cb17998241346cf15fd1f890b4c17c180815c4b5f`;
the successful Quick log SHA-256 is
`e0f1065acbaa433c8d3f70e53b848a6d500146841371cf316911efac0609e4f8`.
This documentation-only record does not alter the tested production or test
sources. Hosted CI on the next pushed revision, reviewed native SDK/material
captures, actual glyph-face attribution, native scheduling and interactive
flows, hardware timing, complete API conformance, and clean-machine delivery
remain outstanding. All nine original completion gates remain open.

### Native scheduling follow-up: the character relay remains insufficient

A separate optimized message-only-window probe preserved ten authored inputs
across six character-message families through a fixed-ID relay around the
Foundation loop. Task progress, controlled nested Unicode message dispatch,
quit propagation, and owned cleanup also passed their scoped checks. Additional
controls nevertheless reproduced data loss: an owned `WM_IME_COMPOSITION`
character changed from `0x6F22` to `0x003F`, an owned `WM_MENUCHAR` changed its
character while retaining its flags and menu handle, and a foreign Unicode
window still received the wrong character. The GetMessageW baseline preserved
all three. These were synthetic queued messages, not live IME or active-menu
qualification, and standalone assertion counts are not XCTest case counts.

The final source, executable, three result sets, watchdog records, runtime
identity, and saved-evidence verification were imported without modification
to `artifacts/goal-native-mainactor-relay-8304d98/`. The frozen manifest SHA-256
is `de27e7c2f1f866ffe09bfcbaa5a3ddf17495831399d168a77358b5c634a02565`.
No visible window or system preference changed. Neither the plain Foundation
loop nor this six-family relay has been adopted in production. A usable native
scheduler still has to preserve the complete Windows message and text paths;
successful task progress alone does not satisfy that existing requirement.

### Fifth batch: mounted StateObject ownership

`@StateObject` now uses the mounted identity, declaration slot, host, and owner
generation already established for ordinary State. Its initializer stores an
escaping main-actor factory instead of constructing the object immediately.
Installation resolves that factory for a new owner/slot and keeps the accepted
object through fresh view values and keyed reordering. A factory returning a
supplied instance still intentionally shares that reference; a copied source
view does not by itself merge ownership between windows.

Factory execution reserves its slot before calling application code. Recursive
initialization, host closure, superseded builds, and unfinished adoption cannot
publish an invalid candidate. Installation also subscribes to the object when
the body only forwards its projected binding. Escaped mounted member bindings
retain the last readable cell but reject projected writes before accessors run
after that generation retires. Raw object references remain ordinary aliases;
this is not a deep freeze or a revocation of arbitrary external references.

The integrated code passes 220 focused XCTest cases across 23 targets and 14
serial invocations, with no failures or skips: all 36 new installation,
lifetime, and observation cases; 177 existing State, editor-teardown,
transaction, window, demo, and construction regressions; and seven existing
public object/publisher cases. The new-suite log is
`artifacts/goal-fifth-stateobject-new-tests.log`, SHA-256
`06f1e8fc62804aa1254634e9d1dad9fccef082fca0ed015fc795b8b4e50b9116`.
The existing-suite log is `artifacts/goal-fifth-stateobject-regressions.log`,
SHA-256 `1d9348223b02ccd4c65c2932bbd6bd376b7dc768410a42259946ed1279d67814`.
Strict lint passed on all seven changed Swift files, and contracts passed
before and after the architecture change. Quick now includes the three new
StateObject suites; complete fifth-batch Quick/Full validation remains pending.

The mutable whole-object setter, projected-self API, and standalone cache are
explicit Windows compatibility extensions. App/Scene ownership, inactive
opaque content, complete wrapper support, and paired native lifetime and
transaction behavior remain open. [MountedState.md](docs/MountedState.md)
records these boundaries; this slice does not close an original product gate.

### Fifth batch: structural children in the basic stacks

`VStack` and `HStack` now accept the direct children of a pure composition.
A custom view's explicitly annotated builder body can contribute two distinct
stack children, and an empty body contributes no spacing. `Component` carries
an optional package append operation; its public single-node constructor is
unchanged. Keys and node-decorating wrappers keep an aggregate boundary.
`Group`, `ForEach`, arrays, optional/conditional content, and erasure preserve
their selected structural content and captured identity/environment scope.
No body is evaluated merely to discover inactive children.

The integrated change passes 356 focused XCTest cases across 32 targets and
19 serial invocations, with no failures or skips. This includes all 34 new
construction, identity, and mounted-host cases; ten unchanged context and
stack-headroom cases, including the original 60-level construction fixture;
278 existing State, StateObject, identity, list, layout, transaction, and demo
cases; and 34 existing public stack/list/ForEach cases. The successful logs are
`artifacts/goal-fifth-structural-new-tests-v3.log` (SHA-256
`e82dd478dc99365689fb88226fd0f3cef928331741713c2fe7fa1a92226185c0`),
`artifacts/goal-fifth-structural-regressions.log`, and
`artifacts/goal-fifth-structural-public-regressions.log`.

Two unsuccessful fixture attempts are retained. The first did not compile
because 15 new identity-test contexts omitted required initializer arguments;
they now supply an explicit zero-size provider and no-op invalidator. The next
executed 22 cases and failed one because it looked for edit metadata on List's
outer selection wrapper. The corrected fixture keeps selection on that wrapper
and verifies the index/delete action on its sole content child. All original
behavior assertions remain; no production List behavior or recursion depth was
changed to satisfy those assumptions.

Quick includes the three new suites. Contracts and strict Swift lint pass.
This does not flatten every container or modifier, change the public builder's
array representation, complete aggregate layout, establish native SwiftUI
behavior, or qualify the fifth batch's full visual/build gates.
[StructuralComposition.md](docs/StructuralComposition.md) records the precise
producer/consumer boundaries. All nine original completion gates remain open.

### Actual SDK capture and the first complete API review packet

Hosted capture run `33135644721` on pushed commit `0cb9a36` successfully
exported the pinned SDK and published its complete nine-stream audit ledger.
The overall job subsequently failed in material-reference validation: the
material receipt included a `swift-driver version:` prefix while the SDK
receipt's compiler line did not. That later failure does not invalidate the
sealed export, and matching normalized version text alone would not prove
matching executable bytes or native behavior.

The actual candidate records Xcode 26.6 build `17F113`, SDK 26.5 build `25F70`,
and extractor Apple Swift 6.3.3 with complete compiler/clang build suffixes.
The six preserved interfaces independently identify their producer as Apple
Swift 6.3.2 effective-5.10 and interface language mode 5; extraction used
language mode 6. The export host was macOS 26.6.1 build `25G76`, x86_64.
These facts remain distinct and unreviewed. No SDK pin, review status, exception,
or original completion gate was changed.

The 299,473,561-byte artifact ZIP is preserved under
`artifacts/goal-sdk-33135644721/`, SHA-256
`30d576728266c79a81dc7b698f613896bba3413b1f452ecbec4438c1e42f3f44`.
Its capture manifest SHA-256 is
`f900bef9de2e5c37b8145ad6bdae7a3fe1c9b679f15b324175e3f1c89797057d`;
its audit manifest SHA-256 is
`868d79adb9de34ea74f875bb9aaa8a179bf3177e2dfcee16daf6a8b14b34db63`.
Independent streaming hashes and row counts passed, followed by complete
raw-record/ledger reconciliation through the frozen API review selector:
22 graphs, 134,147 precise identifiers, 300,436 declaration occurrences,
309,048 relationships, six interfaces with 137,973 lines, and all nine streams.
Seventy checked input files remained byte-identical before and after selection.
Zero captured overlay files still does not prove overlay completeness.

The first selected unit is the exact exported `StateObject.init(wrappedValue:)`
identifier `s:7SwiftUI11StateObjectV12wrappedValueACyxGxyXA_tcfc`, retaining all
four module/architecture occurrences and four incident relationships. Its
Windows candidates are five explicit Git blobs at `baa2b40`, not the current
working tree. The imported packet is
`artifacts/goal-sdk-33135644721/stateobject-review-unit/review-unit.json`,
SHA-256 `b5d29e592f2b69c15762cbbe44a66c4139e219113f4bf1583891c60613b89105`.
All declaration, source, and behavior claims remain `unverified`. Reading this
unit already identifies a concrete source gap: native construction is
`nonisolated` with a plain escaping autoclosure; Windows currently isolates the
initializer and factory to the main actor. The local ObservableObject protocol
and native Combine constraint also require separate review. Correct lazy
factory ownership does not by itself resolve those API differences.

### Fourth hosted Windows validation stopped before the gallery

Windows run `33135644630`, Full job `98734917190`, failed at shard 95 of 190
in `RenderLifecycleDeliveryTests`. Before stopping, the log records 1,905
passing XCTest cases, one failing case, and 58 passing Swift Testing cases.
The failed case was
`testNodeHookPaintMutationDefersPendingTasksWithoutRepeatingTheHook`: after
64 cooperative yields its task-start values were still empty/zero, while its
later assertion in the same case observed the task start. The log therefore
shows late readiness, not demonstrated task loss. The exact executor timing
cause is not established, and the separate native Windows message-loop
problem remains open.

The failure and parsed counts are retained in
`artifacts/goal-fourth-windows-ci-33135644630-summary.json`. A bounded explicit
task-start acknowledgment is being validated without changing runtime behavior
or removing the lifecycle assertions. This hosted run did not complete the
test ladder or reach the product/gallery gates; the earlier local Full/Quick
passes remain separate evidence, not a replacement for hosted success.

### SDK review tooling integration and validation boundaries

The shared compiler-identity parser now removes only the recognized driver
prefix from its derived Apple Swift compiler line. It retains the compiler
patch version and complete swiftlang/clang build suffixes, rejects ambiguous
compiler or Xcode headers, and preserves original command/manifest receipts.
Synthetic material checks still reject genuinely different compiler identities
and keep inconclusive observations unqualified. The original hosted material
failure is not rewritten into a successful run.

The complete-record API review selector is integrated as a separate tool.
It selects one exact exported identifier, reconciles the entire successful
capture and nine-stream audit, retains all selected occurrences/relationships
and source context, and copies only explicitly pinned regular Git blobs.
Its new immutable output contains separate unverified declaration, source,
and behavior claims. Both validation modes now include its synthetic suite.

The integrated scripts pass 3,174 assertions on each PowerShell runtime:
546 baseline/streaming/memory, 293 material provenance, 391 audit, 19 audit
memory, 350 workflow, and 1,575 review-unit assertions. These were fresh-process
suite checks, not native execution. The successful PS7 sequence is preserved
in `artifacts/goal-fifth-sdk-tooling-fresh-ps7.log`; PS5's first five successful
suites and its separately repeated successful review suite are in
`artifacts/goal-fifth-sdk-tooling-fresh-ps51.log` and
`artifacts/goal-fifth-api-review-unit-ps51-frozen-head.log`.

Failed attempts remain part of the evidence. A root-created aggregate harness
ran unrelated suites in one process before the PS7 memory check, whose measured
peak exceeded its unchanged 768 MiB budget. Fresh memory-only processes passed
at 192.4 MiB on PS5 and 228.8 MiB on PS7. An initial PS5 workflow fixture also
hit the previously observed staging-directory Move access denial; its cause
remains under investigation, with no retry or permissions workaround added to
production. During the first fresh PS5 review run, a documentation commit
changed HEAD and correctly tripped the repository-immutability assertion.
Repeating that suite with files and Git state frozen passed all 1,575 checks.
No failure log, budget, audit record, or native qualification was discarded or
silently relaxed to obtain these results.

### Typed builder candidate: preserved, not delivered

The native-first typed-builder candidate compiled its production sources, but
the repository test module did not compile. Three loop sites containing opaque
view-modifier results exposed Swift's synthesized for-in accumulator inference
limit; a separate minimal module/client probe reproduced it. Four additional
new metadata assertions needed explicit optional map-result types. No new
builder tests executed, so the candidate is not a validated implementation.

Its complete integrated patch, including the small fixture corrections, is
preserved against `50c7ed8` under
`artifacts/goal-fifth-typed-builder-held-50c7ed8/`, SHA-256
`7974804d1c32970d2741a24c00d0b8165a294809beb7a3ba90071b6f4dd224b0`.
The original agent bundles and failed compile log remain unchanged. The
unfinished candidate was removed from the active build inputs so independent
runtime, color, identity, and document work can continue validating. The
delivered public builder still has its existing array representation.

The pinned native ViewBuilder interface has no `buildArray`; for-in support is
a Windows extension. A separate explicit legacy array builder is a possible
migration design, not an implemented fix or permission to hide the failing
cases. Native concrete-body inference, typed tuples, metadata, State identity,
and the existing shared-source goal still require completion and verification.
No original acceptance criterion or failing behavior assertion was removed.

### Fifth color, identity, and lifecycle integration checks

The first focused run of the combined independent fixes now passes 123 XCTest
cases across nine targets and seven serial SwiftPM invocations, with no failure
or skip. Its log is
`artifacts/goal-fifth-color-identity-lifecycle-focused-v3.log`, SHA-256
`7e68e674535e06869d2ddecc7d44c430c009321e18ab1e93f527ffd158f168f9`.
Strict lint passes all nine changed Swift files. Broader state, editor, color,
and lifecycle regressions and the next Full/Quick batch remain pending.

The canonical RGB constructor now converts linear sRGB and Display P3 into
the retained encoded extended-sRGB components, keeping representable negative
and above-one RGB values. Forty-three new tests distinguish transfer/matrix
math, finite storage policy, alpha, and the existing renderer clamp. This does
not establish native color resolution, wider-gamut output, white-initializer
behavior, or renderer working-space parity. The paired native observer is
separate work; no native result is implied by these standards-derived tests.

Item sheets key their presentation content by the selected item's typed ID.
Three new mounted cases retain state for a same-ID payload change, retire it
on accepted identity changes or dismissal/reopening, reject retired binding
writes, and preserve the background editor and its undo/selection. A separate
single-child reconciliation path uses the existing matching rules without
building key lookup tables. Six new cases cover typed/tag/layout precedence,
180 legacy tag/layout pairs, colliding keys, other child counts, focus, and
editor retirement. Hash-call counts are structural evidence, not measured
allocation savings or frame-performance qualification.

The lifecycle change is test-only: positive starts now acknowledge the actual
recorded task start through a bounded expectation. Existing negative deferral,
once-only, and callback-order checks remain. This improves the readiness check
that failed in hosted CI; it does not fix the native Windows MainActor loop.

Two failed compile attempts remain preserved with zero executed cases. The
original item-sheet patch was correct in its frozen source, but its short,
identical context initially matched the Boolean overload in the newer checkout.
Root moved that line explicitly into the item overload; the original patch is
unchanged. The next compiler run rejected seven new singleton-test accesses to
a fileprivate runtime reference. Tests now observe the existing runtime-backed
clock accessor with a temporary counting clock, restored synchronously in
`defer`; production visibility is unchanged. Parent, focus, controller, and
retirement assertions remain. Logs are
`goal-fifth-color-identity-lifecycle-focused.log` (SHA-256
`9ec7e8a1ea0368c2c1ec0e51e8b7eaf714cb3f4e1572c12af309450373f3df35`)
and `goal-fifth-color-identity-lifecycle-focused-v2.log` (SHA-256
`843bfef0f08781a5d06681014b6b87bdb7a19e77bd2fda4f160fc208b96e7c6d`)
under `artifacts/`. A test closure-formatting failure was also corrected without
changing its behavior. No baseline, tolerance, original goal gate, or failing
runtime assertion was removed to obtain the passing run.

The broader follow-up now passes another 360 cases across 28 targets and 18
serial invocations; ten selected public color/sheet/cover cases also pass.
Together these runs cover 493 distinct XCTest cases. Five additional fresh
PowerShell/SwiftPM invocations each pass all 16 lifecycle cases (80 repeated
passes, not 80 additional distinct cases). The completed record is
`artifacts/goal-fifth-color-identity-validation.json`, SHA-256
`fb9c25d3099741c8c9500e02d7aba385fc5f6c2df533c51eabe8067853c5c60d`.
It seals the tested working-source hashes, all eight successful logs, retained
failures, strict lint, and post-edit contracts. These are focused checks;
Full, Quick, visual review, and hosted validation for the fifth batch are still
required before delivery. Quick now explicitly includes both new color-space
and item-sheet suites.

### StateObject isolation experiment rejected

A standalone Swift 6.3 experiment tested the proposed private MainActor
factory/seed carrier behind a nonisolated plain-autoclosure initializer.
The separate-module client emitted SIL for an unsafe mutable deferred capture
without a diagnostic under complete strict concurrency and warnings as errors.
The direct mutable-capture control correctly produced a sending/data-race
diagnostic; immutable and ordinary positive controls compiled. No unsafe
program was linked or executed. Successful code generation is the observation,
not proof that a race occurred at runtime.

That result triggered the experiment's rejection gate. Remaining authored
families were not run, no production isolation change was applied, and no
unchecked Sendable or stronger public-parameter workaround was substituted.
The owned source, flags, logs, and SIL are retained under
`C:/Users/maxw6/AppData/Local/Temp/swift-windowsui-state-object-isolation-probe-1bd182277aa047918327010b93c69a39/`.
The current MainActor initializer restriction and its native declaration gap
remain explicit. A safe replacement still needs design and native comparison.

### Diagnostic integration: font ownership, material hosting, and RGB observers

The bitmap-font attribution, material-hosting experiment, and paired RGB
observer sources are now integrated for validation. The original font patch
and its separate formatting overlay remain unchanged. Strict lint passes all
25 changed Swift files, and the portable material executable compiles and
passes all 170 synthetic checks. On both PS5 and PS7, the font collector passes
174 synthetic assertions and the material collector passes 1,383 assertions
across 369 fixtures. These runs do not execute native macOS rendering.

The first combined Swift test build stopped before executing cases because
the imported `CompareStringOrdinal` function expects a Swift Bool at its final
argument, not WindowsBool. The call now supplies the same true value with the
correct imported type; no comparison rule or path validation was changed.
The failed log remains at `artifacts/goal-fifth-font-attribution-focused.log`,
SHA-256 `b23fd0d6ff3319b7e8c9cac7495d7d87305b105be65d0ae85646ac27b831726d`.
The subsequent Swift test run and actual diagnostic off/on render checks are
still required. No baseline or comparison tolerance has changed.

The material addition preserves the canonical six-fixture/two-repeat capture
first. Its opt-in sidecar adds 24 fresh unattached/attached captures under a
checked process-only activation-policy transition, with separate controls per
arm and checked cleanup/restoration. It never orders or activates a window,
changes OS preferences, or promotes an inconclusive control. The new color
executable records fixed public constructor observations without opening a UI;
its Windows compilation and pinned native comparisons remain pending here.

The SDK follow-up confirms that the six captured interface files comprise
four macOS files and two SwiftUICore Catalyst variants. The exporter searched
only two framework module directories for cross-import definitions and did
not preserve a discovery census. Zero copied definitions therefore remains
unverified overlay completeness. The successful capture and nine audit streams
remain intact; a separately sealed discovery/load-check plan is being prepared.
These checks document how to establish the original full-baseline audit;
its acceptance gate is unchanged.

Two further font-integration compile failures are retained, again with zero
executed test cases. The gallery's exclusive directory-creation check now uses
the Bool returned by `CreateDirectoryW` directly. A test helper's metadata
closure now carries the same MainActor annotation as the existing production
initializer it forwards to. Neither correction changes a runtime assertion,
comparison rule, public API, or the callback ownership contract. The logs
`goal-fifth-font-attribution-focused-v2.log` and
`goal-fifth-font-attribution-focused-v3.log` have SHA-256 values
`ffa679467b527f8210d3eb7fce80a0eaad033a246efc5a4d46c7e3cbaaae1ddf`
and `7f1e3093695096e9c366bcf18205e3c83072bdabecc3b9b7494ee4dbe9ac8d42`.
The second attempt left one compiler process orphaned after its parent exited;
root verified the exact PID, creation time, module, workspace argument, absent
parent, and unchanged CPU observations before terminating only that process.
`artifacts/goal-fifth-font-orphan-compiler.json` records the cleanup. No other
compiler or application was stopped. The RGB observer executable did compile
and link during that attempt, but its observations have not yet been executed.

The corrected focused run now passes 138 distinct XCTest cases across 11
targets and eight serial invocations, including all 79 new attribution cases.
There are no failures or skips. Its log is
`artifacts/goal-fifth-font-attribution-focused-v4.log`, SHA-256
`beb13089c905a66eeed756f5333c550e70331b428b8d2363c34ab2556109dd53`.
Actual off/on retained renders and native face/file observations are the next
checks; passing these tests alone does not establish pixel neutrality or the
cause of the hosted gallery differences.

The RGB collection/comparison scripts are also integrated. Their isolated
synthetic validation passed 125 cases on each shell: 446 assertions on PS5
and 453 on PS7, with separate fallback-specific checks. Root validation is
still pending. Quick and Full now include this synthetic suite. The actual
Windows observer, both pinned native typechecks, native execution, and paired
comparison remain separate evidence; no component tolerance was widened.

The first isolated Foundation build attempt stopped before compilation when
pinned Ninja rejected an unchanged 264-character source path. Its configuration
had succeeded, but no Foundation target object, library, or module-origin
receipt was produced. The immutable failure record is
`C:/Users/maxw6/AppData/Local/Temp/swift-windowsui-foundation-inputs-1787886013247/builds/foundation-build-1787890953218/frozen-build-phase-manifest.json`,
SHA-256 `f0792f095da207cd979c3d17f773bc2bd9123b05829b5969a0f5e519f206e036`.
A new bounded cohort will copy the same four frozen source views into shorter
owned paths, verify every byte, and rebuild the same eleven targets and options.
No installed toolchain, source fix, OS path setting, or native activation was
substituted. The native MainActor/Unicode failure remains open.

Root RGB tooling validation now passes all 125 cases under both PS5 and PS7
(446 and 453 assertions respectively). The two diagnostic gallery fixtures
also pass against the unchanged baselines with zero changed pixels and zero
channel delta, both with attribution disabled and enabled. Their PNG bytes
are identical between modes. The raw retained stepper and symbol-palette
images were opened and inspected; this is a two-fixture diagnostic check, not
the full 85-baseline release gate or GPU visual qualification.

The actual native records identify Segoe Fluent Icons for the nine accepted
bitmap draws and their selected scene references: both stepper chevrons and
seven palette icons. The sparkle selects the existing vector fallback.
Segoe MDL2 Assets appears in candidate/sentinel probes only and is not
misreported as an accepted bitmap. Both approved font-file references were
fingerprinted after rendering through the same checked file handles; embedded
versions were Fluent Icons 1.54 and MDL2 Assets 1.86. These disk hashes are not
hashes of bytes loaded by DirectWrite. Optional axes remain unimplemented,
so the report correctly stays partial and unqualified. Ordinary text and
atlas glyphs are not instrumented, and scene references alone do not prove
visible contribution after clipping. Hosted observations remain required.

`artifacts/goal-fifth-diagnostics-validation.json`, SHA-256
`9377e3162f03196aafc79c3274a17636c468161e19b7473d20558dc4787e8abb`,
seals the focused tests, synthetic tooling checks, two off/on render sets,
actual bounded font observations, preserved failed builds, source hashes,
strict lint, and post-edit contracts. The font, material-hosting, and RGB
collector slices are committed separately as `6dd7dbd`, `c515e19`, and
`c1fc350`. They remain unpushed pending the fifth batch's complete validation.

A source review also found that Quick/Full invokes the bounded-memory audit
fixture in the same PowerShell process as earlier suites, while its Windows
measurement is the process-lifetime peak working set. Earlier allocations can
therefore contaminate that measurement. A fresh same-engine child boundary
for that one fixture is being implemented and tested; the existing 768 MiB
limit, workload, and failure result will remain unchanged.

### Typed ViewBuilder and explicit Windows array migration

The held typed-builder candidate and its separately reviewed Windows array
overlay are integrated for serial validation. Canonical composition preserves
typed blocks, conditionals, optional content, tuple children, and inherited
`View.body` builder syntax. Existing array-returning control closures retain
their contextual compatibility path. `WindowsArrayViewBuilder` explicitly
preserves the old fixed-array rules for Windows opaque `for` expressions;
it is a named Windows extension, not a native SwiftUI API or a repair to the
canonical compiler inference limit. Only the two previously approved fixture
boundaries were migrated; their loop bodies and behavior assertions remain.

The candidate has 55 new canonical/projection cases and 23 new explicit-array
cases, still unexecuted at this point. The canonical opaque-loop source is
retained outside the SwiftPM targets as a negative compilation fixture. Its
expected three diagnostic headers must be observed against the real integrated
module; a nonzero compiler exit alone will not count as passing evidence.

The first clean-commit Windows RGB collection attempt at `bb39831` failed
before any compiler or color observer ran. A safe-relative-name check rejected
the existing committed path `Sources/SwiftWindowsApp/FoundationApp+DefaultRenderer.swift`
because its allowed character set omitted a literal plus. The complete failed
packet remains in `artifacts/goal-fifth-rgb-windows-bb39831/`; `capture.json`
has SHA-256 `92bf7c1c580c4bed4ac6db733c8af4c0d256ffbab61dcb1cf893bc1fb691c7f1`.
The collector will admit this ordinary filename with regression coverage while
keeping traversal and containment checks. The source file will not be omitted
or renamed to make collection succeed.

The typed-builder run now passes all 96 selected XCTest cases: 78 new cases
and the existing 18 structural-identity cases, across nine targets and five
serial invocations, with no failures or skips. The log
`artifacts/goal-fifth-typed-builder-new-tests-v2.log` has SHA-256
`b473026e60d1615048a4c0a28d81a8c5e55e580941773aea7f8c567fb0a70539`.
The actual-module negative fixture also reproduces exactly its three expected
opaque-result inference errors at lines/columns 10:5, 29:9, and 37:9. It has no
unexpected error or warning; all 179 recorded tool/module/source inputs are
unchanged. `artifacts/goal-fifth-typed-negative-bb39831/validation.json`,
SHA-256 `cd3b404c4031c8210db5a4f66ab43f8fd271cf97da44a31f7614ea5b67136f03`,
seals that result. This confirms the documented Windows compiler limitation,
not native SwiftUI conformance or a linked/executed negative program.
Broader state/list/scrolling regressions remain the next check.

The memory-fixture process boundary and RGB literal-plus filename correction
are now integrated for root validation. The memory fixture alone runs in a
fresh copy of the current `$PSHOME` engine and preserves its native exit code;
other validation stages and the 768 MiB limit remain unchanged. Its new tiny
stub-based process tests are included in Quick/Full. The RGB change consists
of three literal-plus grammar additions plus regression coverage through the
actual snapshot helpers and source/evidence validators. It does not skip an
input or weaken traversal/containment checks. Prior failed capture evidence
and the original frozen patches remain intact.

The broader typed-builder validation now also passes 732 state/list/scrolling
cases and 105 mounted-state/structural-component cases. Together with the first
96, the three logs contain 933 distinct passing XCTest identifiers, no overlaps,
failures, or skips, across 41 strictly serial SwiftPM invocations. The first
broader selection used abbreviated class tokens that omitted the mounted suites;
the separate 105-case run explicitly selected all eleven intended classes.
Those omitted classes are not inferred to have run in the earlier invocation.
The existing test bodies remain unchanged. Strict lint passes all 15 changed
Swift files, and the post-integration architecture contracts pass.

The corrected memory-boundary fixtures pass 303 assertions across twelve cases
on each PowerShell version. The first root fixture attempt failed because the
new self-test gate was placed between the audit ledger and its memory stage,
violating the test's exact predecessor assertion for a missing child. Moving
that self-test before the ledger restores the existing sequence; the assertion
was not weakened. Both failed logs are retained. Separate fresh executions of
the actual memory workload pass all 19 assertions at measured process peaks of
193.5 MiB on PS5 and 231.3 MiB on PS7, below the unchanged 768 MiB limit.

The plus-filename regression passes all 126 RGB-tooling cases on each shell,
with 494 assertions on PS5 and 501 on PS7. The workflow integration passes
387 assertions per shell. It checks out the triggering source revision and
adds a native RGB collection step only after a successful pinned SDK export
and complete unreviewed audit. Material failure remains a job failure but
does not suppress independently eligible RGB evidence. A completed Windows
packet from the same final clean source revision and an actual native packet
are still required; no workflow run or paired comparison has occurred here.

The Windows CI font diagnostic is also integrated and passes 102 synthetic
cases on each shell. It preserves the original Full command and result, records
a boundary before Full, and accepts only a fresh successful gallery build
receipt with matching clean source and executable observations. Its separate
two-fixture invocation never rebuilds or substitutes an executable. Bounded
stdout/stderr prefixes, discarded-byte counts, child exits, and independent
pixel/attribution outcomes remain explicit. The advisory diagnostic does not
convert the existing hosted pixel failures into success. Actual hosted face
selection, loaded font bytes, and font-profile qualification remain unobserved.

`artifacts/goal-fifth-builder-workflows-validation.json`, SHA-256
`13ba8f93c2574fc854e472f6ed9707f2eeb65bd38a9556788ccfa19d24b8717e`,
records the 933 test outcomes, actual negative compiler validation, current
working source hashes, both-shell tooling receipts, fresh memory measurements,
lint/contracts, and preserved failures. It is focused working-source evidence,
not a clean-source Full/Quick or native compatibility qualification. The
original goal text and its nine open acceptance gates are verified unchanged.

The isolated Foundation experiment has preserved two additional preparation
failures. A short-source configure attempt used an incorrect rebased ICU path;
it stopped before compilation and is recorded as a driver error. A subsequent
configuration unexpectedly enabled Ninja compile response files because the
owned PowerShell driver had left an empty-but-present environment variable
where it intended absence. A bounded sentinel confirmed that distinction;
no Foundation compiler ran in that attempt. The failed phase is sealed in
`builds/foundation-f5-build/frozen-f5-phase-manifest.json` under the existing
owned Foundation workspace, SHA-256
`7edc033911b0548648c95090d0229ddeed4f9da3da96de7526bf7015254c5647`.

The fresh F6 configuration now uses verified literal environment removal,
the same frozen source bytes, public build options, dependencies, and eleven
targets. Its actual 586 compile edges and eleven link edges match the reviewed
command-length projection, and compilation has started within the existing
time/output/memory limits. No installed SDK, runtime, source semantics, or OS
setting was changed. Compilation, module-origin verification, a complete
runtime/test-library cohort, and native activation remain separate unfinished
steps; the MainActor/Unicode failure is not yet resolved.

### Accepted sheet dismissal activity

The separately reviewed sheet activity change is now integrated after the
typed-builder commit. Its seven-file increment applies without conflict and
preserves the existing typed item identity and stable base-content shell.
Dismissal authority now belongs to an accepted, materialized presentation
generation, separately from State that may remain retained in an inactive tab.
Provisional or discarded candidates cannot borrow a live dismissal, accepted
absence permanently retires the earlier generation, and deferred GeometryReader
adoption updates only its covered scope. Close revokes activity before releasing
application payloads. The raw construction path retains its documented behavior.

Fourteen ledger and twelve host/raw XCTest cases are authored but not yet run
against the root integration. They cover latest accepted configuration, copied
actions, getter/focus reentry, item replacement, tab inactivity, discarded
construction, deferred adoption, and teardown ordering. Quick now selects both
new classes. Custom Binding setters still have their ordinary semantics; this
does not claim an atomic compare-and-set or detect an unobserved coalesced
false/true interval. Full/Quick and native comparisons remain pending.

F6 has now stopped at its first actual Foundation compiler failure. The
installed SDK and candidate source both supply a `_FoundationCShims` module
map, producing a redefinition while compiling FoundationEssentials and
subsequent import errors. Partial build output and the original log are being
sealed; no retry or installed-toolchain replacement was performed. This is a
new observed module-search boundary, not a successful Foundation replacement
or resolution of the native event-loop failure.

The initial sheet test build failed before executing any case: Swift reported
that it could not produce a diagnostic for the nested configuration expression
in the new recursion fixture. The log
`artifacts/goal-fifth-sheet-activity-new-tests.log`, SHA-256
`d27968c95316ecf4768fc6bb0832cf006366c274b823304ae0cacdfeb11946ad`,
and the exact failing fixture are retained. The optional focus rollback now
uses an ordinary guard and closure return rather than a ternary closure.
Independent review also bounded the fixture's deliberately recursive calls,
so a future missing production recursion guard produces assertion failures
instead of a stack overflow. All expected event sequences and production
behavior remain unchanged; the corrected test build must still pass.

That corrected build compiled successfully, then exposed a production Swift
exclusivity trap during close cleanup after seven cases had passed. A released
configuration capture called an escaped dismissal while the same configuration
property was still being assigned nil. Symbolication identifies the write at
`PresentationActivity.swift:198` and the premature read at line 62 in that
candidate. The crash log has SHA-256
`f96290f04a3c05cb6e154da81c860e210fb696293ea9083798c6a43ffdb59f0e`;
`artifacts/goal-fifth-sheet-exclusivity-failure/failure.json` records the exact
source copies, binary digest, and symbolication, SHA-256
`a6c5f7e3e3d5774f6a9019ec697ce20d71a3513ae1e1f28ce094a571625b0161`.
Seven completed cases do not make this interrupted invocation a passing run.

The repair rejects retired sessions before configuration reads and retains an
outgoing configuration until its stored-property write ends. Ledger cleanup
pins both sessions and anchors; build cleanup first detaches all six stored
collections and only then releases their captured payloads. Normal finish uses
the same safe drain without clearing accepted configurations. Two additional
bounded regressions exercise destructor-driven close during provisional,
discarded, and committed-but-unfinished cleanup. The original crashing test
and its expectations remain unchanged. There are now 28 new sheet-activity
cases to validate, and no production acceptance claim precedes that rerun.

The Foundation F6 failure is now sealed at
`builds/foundation-f6-build/frozen-f6-phase-manifest.json` in the existing owned
Foundation workspace, SHA-256
`f0d577d0c40d0b5b64a247ecc02e7df9d4e79e5f831926c8bba7f87ead5e41bb`.
It retains 1,483 files and 307,837,613 bytes. Three of eleven targets completed;
FoundationEssentials, the five Foundation DLLs, and the modified CFRunLoop
object did not. The two conflicting CShims maps contain identical bytes at
different paths. This identifies an SDK search-path collision, not a proven
upstream source or compiler defect. Follow-up is limited to source inspection
and an explicitly reviewed isolated SDK plan; no new build or activation has
been authorized at this point.

The repaired sheet integration now passes 281 distinct XCTest cases with no
failures or skips: 35 focused cases, including all 28 new ledger/host cases,
plus 246 broader mounted-State, StateObject, deferred-build, editor ownership,
and host/lifecycle regressions. The two runs cover 24 classes in seventeen
serial invocations without overlapping test identifiers. Six changed Swift
files pass strict lint, pre/post architecture checks pass, and independent
review confirms the original crashing test and already-safe commit path were
not altered to make the failure disappear.

`artifacts/goal-fifth-sheet-activity-validation.json`, SHA-256
`aeed34ad0e684e18f6f0441bc260508fb7514de176ae4f7c3893b1a06861d32f`,
seals the current working source, passing logs, two preserved failed attempts,
symbolication, and exact failed source snapshots. The earlier seven partial
passes are excluded from the passing totals. This is focused retained-host
evidence, not native SwiftUI, real-window, or hardware-performance qualification.
The fifth batch is ready to be committed and frozen for complete Full/Quick
validation; no accumulated commit has been pushed yet.

The reviewed Foundation SDK-isolation plan is now authorized for one fresh F7
attempt. It copies exactly 274 declared input files (116,215,802 bytes) into an
owned regular-file SDK/Dispatch view, omitting only the listed Foundation-owned
headers, modules, and libraries while retaining the standard Swift/WinSDK shims.
Public `-sdk` selection and matching child `SDKROOT` replace the target SDK path;
new owned Dispatch metadata removes its explicit old SDK include paths. The
installed SDK, pinned sources, host tools/macros, native dependencies, and build
features remain unchanged. Public target-info inspection and an independent
generated-command review gate compilation. The same resource limits and
first-failure stop apply. No installation, candidate activation, real test-library
build, or native application run is included in this authorization.

### Fifth-batch validation restart and Windows RGB capture

The first clean-source Full attempt at `41f8366` stopped before any Swift
test, demo build, screenshot, or gallery gate. The hosted bitmap-font fixture
suite passed only 10 of 102 cases inside the runner: its dynamic-module
callbacks could not resolve script-local assertion helpers through the
runner's function and command-scriptblock scopes. Earlier standalone passes
did not exercise that caller shape. The complete failed log and exact sources
remain in `artifacts/goal-fifth-full-failure-41f8366/failure.json`, SHA-256
`1af6826c4a6f7e05d53fc265e81540454d635985f26b7d909a7bee9553e5bb05`.
The preceding tooling gates passed, including the actual fresh memory workload
at 192.9 MiB against the unchanged 768 MiB limit. All 60 Swift files in this
batch also passed a separate strict-lint invocation with source hashes and an
explicit exit-code receipt. None of these partial results is a passing Full.

The scope failure was independently reproduced under both PowerShell versions
without any preceding suite. The repaired fixtures capture their original
helper ScriptBlocks and the two mutation-loop values explicitly. An intermediate
candidate fixed helper lookup but failed nine mutation cases; that source and
both failed embedded receipts remain preserved in the isolated handoff. The
final change adds a same-process caller-scope harness and one assertion-failure
canary. It preserves all 102 original ordered cases and both assertion helper
bodies, without global helper injection, production changes, or moving the
fixture into a child process to hide the scope problem.

After root integration, four fresh serial invocations pass all 103 cases:
standalone and embedded on Windows PowerShell 5.1.26100.9223 and PowerShell
7.6.4. Both embedded receipts confirm unchanged caller helper bindings; the
assertion canary passes in all four runs. Source hashes and Git state remain
unchanged during the matrix, and post-integration contracts pass. The root
receipt is `artifacts/goal-fifth-ci-font-scope-root-v1-matrix.json`, SHA-256
`b967c8408f89efdc455d2413edfdcd1c3af88465514a4810de13aa7653aa0eba`.
This correction requires a new clean-source Full run from its first step,
followed by Quick and inspection of the raw retained-runtime images.

Separately, the actual Windows RGB collector completed at clean `41f8366`.
It compiled `swiftui-color-rgb-reference` in release mode and recorded three
valid retained-observer reports with 25 cases each. The capture reports healthy
observer controls, no failure codes, and unchanged source, tools, and executable
observations. `artifacts/goal-fifth-rgb-windows-41f8366/capture.json` has SHA-256
`8cb09175f709058e3637125efe6a07ccf3a3bfa9bc208e572f411c16ddca2479`.
Its status remains `captured-candidate`; declaration, source, and behavior review
are unverified and release qualification is false. A new Windows capture at
the eventual pushed revision must pair with the native capture from that same
revision before any cross-platform comparison is claimed. This release build
does not substitute for Full's demo builds or any native SwiftUI evidence.

The isolated Foundation F7 attempt also reached a new, preserved boundary.
Its copied SDK removed the observed F6 duplicate-module collision, and actual
compiler remarks identify candidate FoundationEssentials and Collections
imports with no old-SDK ordinary import path in the observations reached.
The first FoundationEssentials link then failed because the generated command
passed `/machine:x64` and `/INCREMENTAL:NO` as bare Swift-driver arguments.
Those options were outside the response file; the launched command was within
the reviewed length bound. No retry, installation, activation, candidate program,
or real test-framework build followed the failure.

The F7 phase is sealed under the existing owned Foundation workspace at
`builds/foundation-f7-build/frozen-f7-phase-manifest.json`, SHA-256
`eca74ce601a6dc8b49284d2363b9e549133ab0639ceda104e91316a1249b027a`:
2,373 files and 487,119,297 bytes, excluding the manifest itself. Six of eleven
targets have their required library artifacts; the Foundation DLL cohort is
incomplete. The modified CFRunLoop object contains both W import names and
neither corresponding A name, which is static object evidence only. All
observed owned processes exited and pinned inputs rehashed unchanged. Further
work is limited to a separately reviewed link-argument transport plan; the
native MainActor, Unicode, runtime-cohort, and release gates remain open. The
original goal text and all nine acceptance gates remain unchanged.

### Fifth batch: completed local validation at `580718b`

The restarted Full run and the following Quick run both completed at clean
`580718b12378280941174491d3a61b7c1b830ddf`, tree
`4eb9e59ba2e6a35c271f39d5a72bdfe27f74d322`. The checkout, index, and commit
remained frozen throughout each run. Both runner processes returned zero;
the earlier failed Full and sheet attempts remain separate evidence and are
excluded from these passing totals.

- Full: 4,288 XCTest passes, 134 Swift Testing passes, and one documented skip;
  326 selected targets in 208 serial test invocations, with all 26 runner steps
  completed. Debug and release demo builds, all five raw screenshot products,
  and the complete 85-fixture gallery comparison passed.
- Quick: 1,948 XCTest passes, nine Swift Testing passes, and the same documented
  skip; 126 selected-test invocations and all 88 runner steps completed,
  including the debug demo build. This invocation did not request the optional
  gallery comparison and did not generate another screenshot set.
- All 60 changed Swift files passed strict lint at the same clean revision.
  The lint receipt records unchanged input hashes and exit code zero; those
  file hashes were independently checked again when the Quick archive was made.

Full and Quick overlap and are not additive unique-test totals. The remaining
skip is `RenderPassAbstractionTests.testMaterialInsideADrawingGroupBlursNothing`:
an isolated offscreen material still lacks its external backdrop. Keeping this
documented failure mode visible does not satisfy the rendering/effects gate.
The fixed CI-font fixture also passes inside the actual Full and Quick runner,
in addition to its earlier four-mode PowerShell matrix.

The Full archive is
`artifacts/goal-fifth-batch-580718b/validation-full.json`, SHA-256
`e4c6a7bcd4ccb97e6251f251b2b4fcf5aedb96a556561425f0a29d72666470b2`.
Its 196 listed files preserve the original log, start/exit/completion receipts,
runner sources, screenshots, gallery inputs and reports, provenance, independent
pixel checks, and visual-review record. The separate Quick archive is
`artifacts/goal-fifth-quick-580718b/validation-quick.json`, SHA-256
`3344fcda577ca146c7b38951886428688fa3e090471ced3ff018f69d295c4da5`.
Its fourteen listed files preserve the completed Quick log, source/exit/summary
records, lint evidence, and relevant runner/archiver sources. Both archives
verified their listed bytes; Quick did not rewrite the sealed Full archive.

All 85 current gallery images pass the unchanged thresholds: 0.5 percent,
eight-channel-value tolerance, and maximum delta 64. An independent decoder
recomputed all 85 RGBA comparisons against the same reviewed baselines, with
zero pixels beyond the channel tolerance. `state-toggle-hover` has a maximum
channel difference of eight; the other 84 report zero. Therefore the result
is a complete passing comparison, not a claim that every image is byte-identical
or every pixel is identical. Baseline file hashes match the preceding frozen
batch. The recheck receipt is
`artifacts/goal-fifth-full-580718b-pixel-recheck.json`, SHA-256
`34783617923673c9b4a76871542f79c42a925384ecb118799c74856073cab7a9`.

All five fresh 1280-by-720 retained-runtime screenshots were opened and
inspected. They contain the expected application and gallery content, without
an observed blank or displaced-content regression. The diagnostic frame path
still displays its documented square corners and simplified material effects.
Image inspection does not establish native SwiftUI parity, live D3D11 frame
delivery, measured contrast, Narrator behavior, or hardware timing.

The three Windows RGB reports from `41f8366` also passed a separate read-only
packet audit: 240 archived files, 167 source entries, and all 300 measured Float
components agree with the packet hashes and recorded bit patterns. Pairwise
Windows repetitions have no numeric or bit differences. The sealed audit is
`AUDIT.json` under the owned Temp directory
`swift-windowsui-rgb-windows-audit-41f8366-c9179701be0e4309be5b4b80712f46b7`,
SHA-256 `855fbb00801e0451d8ece72401340193c775fb750567c9f1aad102a420e1325b`.
This still provides no native pair and cannot be attributed to a newer commit.
After this ledger-only commit, a fresh Windows packet must be captured at the
final fifth-batch revision and compared with that revision's native CI packet.

### Foundation F8: linker forwarding confirmed, cohort still incomplete

The separately authorized F8 build reused the frozen sources, SDK view, native
dependencies, compiler, and feature selection. Its only new build options were
the public CMP0181 policy and `LINKER:` forms of the two shared-linker flags.
Configuration and independent generated-command review passed: all 586 compile
commands retained their prior semantics, and exactly five Swift DLL links gained
the required `-Xlinker` forwarding. The actual failed launch confirms those
arguments reached the link command, and the earlier flag-as-path failures did
not recur.

The one build then stopped at its first FoundationEssentials DLL link with
`LNK1104: cannot open file 'lib_FoundationCollections.lib'`. Passive object-file
inspection found that exact default-library request in all 209 emitted
FoundationEssentials objects. The produced archive is instead
`_FoundationCollections.lib`, already present explicitly in the link response
file. This records the observed naming mismatch; it does not imply a completed
Foundation runtime or justify copying a file under an alias.

The F8 phase is sealed in the existing owned Foundation workspace at
`builds/foundation-f8-build/frozen-f8-phase-manifest.json`, SHA-256
`495aa44d1c82fabc4e43d3eb413026d24d0070cfbac4fd262a750e4397666bad`:
2,093 listed files and 377,701,624 bytes. The build returned one, with no resource
abort or retry. There are 589 successful primary outputs out of 597, but none
of the five Swift Foundation DLLs. All 279 observed owned process identities
had exited, and the recorded prior manifests, tools, sources, SDK files, and
native inputs rehashed unchanged. No installed toolchain, OS setting, candidate
activation, native application, or real test-framework build was involved.
Follow-up is a separately reviewed naming diagnosis and build-recipe proposal.

The next dialog/native-close increment is still isolated from this tested
checkout. Its source work includes late build-history invalidation, actual
GeometryReader slot settlement, provisional cleanup rendering, and fail-closed
document ownership checks. Its 259 authored tests have not yet been compiled or
executed; source review and lint are not substitutes for that integration work.
This remains part of the original state, presentation, and document requirements.

The fifth-batch delivery commit following `580718b` changes only this ledger.
The code validation above belongs to `580718b`, and hosted CI must run against
the exact delivered commit before any current hosted result is claimed. The
original sections 1–9, their fingerprint, all nine open completion gates, the
pinned API baseline, and the published performance targets remain unchanged.

### Sixth batch: dialog owner lifetime and terminal results

The fifth batch was pushed together as 23 commits at
`9f983e633b80da2591567d78c37913e6632611ca`. Its fresh Windows RGB collection
completed there with three healthy observer reports and unchanged source,
tools, and executable observations. The successful release build reused the
unchanged incremental binary; this was a new collection with new processes,
not a cold recompilation. The final packet has SHA-256
`e349065efdfe1288705f009519ef7cb9e55ae70b2702b3a9331bb3043af87ba5` at
`artifacts/goal-fifth-rgb-windows-9f983e6/capture.json`. A separate read-only audit
verified its 240 referenced files, 167 source entries, 25 commands, and all 300
finite Float observations. Repetitions and the earlier Windows packet agree
exactly by value and bits; no native pairing or qualification follows.

The first sixth-batch slice now binds file dialogs to their retained owner and
presenter lifetime. Hosted requests use that window's handle and do not fall
back to another active window. Internal outcomes distinguish cancellation,
native failure, and a valid selection; existing URL-only providers retain their
documented compatibility behavior. Native extended-error lookup occurs directly
after a false common-dialog result, while its buffers remain alive.

An admitted operation retains its configuration across the modal call, file
access, presentation reset, and captured completion. Owner close, presenter
removal, or removal/reinsertion revokes the old request before later file writes
or callbacks. A normal reset may remove its presenter without discarding an
already-completed result, but a closed owner cannot receive that callback.
Filesystem effects finish before reset/completion; failed or revoked work does
not pretend that bytes were saved. Reentrant empty scans are bounded.

Root replay verified all six prepared native-close patches against `9f983e6`,
with the updated goal as the only difference from their `580718b` source base.
The intake receipt is `artifacts/goal-sixth-native-intake-9f983e6/intake.json`,
SHA-256 `a6cf7b2c36d5e69952376aa0f02274d0e894400290bbbd099f700ad241b594fe`.
Only the first dialog patch is integrated at this point. Its staged tree
`2a2b7e7f55267cdf10820a299cad0348dc62fd92` matches the reviewed replay exactly;
the later close-control, settlement, and host increments are still pending.

The first focused attempt failed in an ignored PowerShell orchestration wrapper:
normal compiler progress on stderr became a terminating NativeCommandError under
its Stop preference. Its partial log and source receipt are preserved, with no
complete child exit receipt and no passing-test credit. The replacement wrapper
captures the actual child's stdout/stderr directly to a file and records its
exit code. No production or test source changed between those two attempts.

The complete rerun passes 109 distinct XCTest cases across eight selected targets
and six serial invocations, with no failures or skips. These include all 42 new
dialog cases and 67 existing file-dialog, export, buffer, and integration cases.
The sharded selector also included the existing `IntegrationTests` class; its
22 executed cases are reported explicitly in that total. The log is
`artifacts/goal-sixth-dialog-tests-v2.log`, SHA-256
`add07abc4a54a24ecef49fa33e7a90fbb7360fb335c6d65e7f3754c968e3f0d2`.
The actual child returned zero; staged tree, index bytes, Git status, and recorded
input hashes remained unchanged during execution. All seven changed Swift files
pass strict lint and contracts. This is focused working-source evidence, not
sixth-batch Full/Quick, an interactive common-dialog smoke test, or a completed
document workflow. The original nine product gates remain open.

### Sixth batch: native close control and captured lifetimes

The dialog slice is committed as `30d68e7`. The next increment introduces
package-owned close outcomes, authority registration, intent tickets, concrete
commit leases, and native window lifetimes. A veto cannot be overwritten by a
later authority, cancelled or consumed tickets cannot be reused, and reuse of
an HWND does not revive the old window lifetime. A prepared lease keeps its
actual owner/session alive through final reservation, destruction, and exactly
one terminal finish. Native destruction is reported successful only when the
captured lifetime acknowledges it; a failed or incomplete destruction is explicit.
This increment does not yet supply the later deferred-delivery or App/document
integration, and it does not activate DocumentGroup.

The first actual build found one unique compiler error in a new fixture,
repeated by the parallel compiler batches: an untyped local closure could not
be converted to the MainActor callback stored by the test lease. No XCTest case
executed. The failed log has SHA-256
`e23b553f7d43492e16dd1c96584159eb732b9a73ae8ab77d58cd6b8e38c62e45`;
`artifacts/goal-sixth-close-control-compile-failure-v1/failure.json`, SHA-256
`2b0d5706e392dff750e36c9d20bae610af3746039e8ddf0add3bfdef31c07700`,
preserves thirteen log, receipt, and exact source files before correction.

The correction explicitly types that one local closure as `@MainActor () -> Void`.
Its body, captures, three invocation phases, and all assertions remain unchanged;
there is no production change, concurrency-flag relaxation, cast, or unchecked
Sendable assertion. Independent review confirms the callback type already has
that actor requirement. The original frozen bundle remains untouched, and
`artifacts/goal-sixth-native-actor-overlay-v1.json` records the exact one-line
root correction for subsequent integration comparisons. The imported test file
is therefore no longer byte-identical to its frozen input; its assertions are.

The complete rerun passes 78 distinct XCTest cases across four serial invocations:
all 37 new `Win32CloseControlTests`, twelve native close-request regressions,
eleven window-coordinator tests, and eighteen dismissal-policy tests. There are
no failures or skips. Its log is
`artifacts/goal-sixth-close-control-tests-v2.log`, SHA-256
`46133c38753da87803f9a09779aa04883e3057bc4b19c97be41411b1400cb800`.
The tested staged tree is `781e8da0d344bb234854dfd27ee5e793ee566c2f` over
`30d68e7`; the child exited zero and all recorded inputs, index bytes, tree, and
Git status stayed unchanged. All three changed Swift files passed strict lint,
with a fresh strict check of the corrected fixture. New state-machine cases use
controlled handles rather than calling native destruction through fake HWNDs.
Full real-machine close, document, and presentation qualification remains open.

The fifth-push hosted results remain distinct. Portable CI and the ordinary
macOS reference workflow passed at `9f983e6`. The latter actually used macOS
15.7.7 arm64, Xcode 26.3, Swift 6.2.4, and SDK 26.2, outside the pinned reference
identity. Its twelve canonical material images and twenty-four attached-hosting
images remain inconclusive with Reduce Transparency enabled in both system and
observed SwiftUI contexts. Every hosting image matches its corresponding
canonical image; the twelve canonical images match the prior fourth candidate.
Unshown window attachment therefore did not distinguish the material controls
under these observed conditions. No setting or qualification was changed.

The separate pinned SDK workflow stopped in the RGB synthetic fixture before
SDK export, audit generation, or native RGB collection. The fixture compared a
physical `/private/var/...` source path with its logical `/var/...` temporary
root. Production collection already resolves its repository root; a narrow
fixture-root correction and separate failure-artifact retention are being
prepared without weakening containment checks. The failed job did not publish a
candidate artifact, so no same-revision native RGB comparison is available yet.

The isolated F9 Foundation build returned zero at 08:08:52 UTC, with no resource
abort. Its exact generated commands passed the reviewed filename correction;
opaque per-configuration target IDs, one dependency enumeration swap, an unused
target-PDB name, and phony-block serialization were retained as explicit metadata
differences without relaxing ordered command/source checks. Complete output,
module-origin, resource, and input verification is still being sealed. No DLL
was installed or activated, and the real XCTest/Swift Testing cohort and native
scheduling/Unicode checks remain separate unfinished work. None of these local
or hosted results closes an original product gate.

### Sixth batch: deferred close delivery and nested native scopes

The close-control slice is committed as `5a09843`. Deferred delivery now uses
an owned window message containing a scalar nonce, with the actual request and
its captures retained by the current close registration. A stale, duplicate,
cancelled, or wrong-lifetime wake cannot become a fresh close approval. Nested
window dispatch, native modal calls, active close attempts, and mailbox cleanup
defer delivery until the owned scopes unwind. Rearming posts a wake rather than
running the application prompt inline; a posting failure is explicit and is
not retried automatically. The real file/color common-dialog calls participate
in these scopes, and failed file-dialog calls still sample their extended error
immediately inside the invocation scope. Third-party modal pumps remain outside
this owned-scope guarantee.

The first actual build stopped before XCTest execution because Foundation and
WinSDK both export a type named UUID. Three new fixture declarations therefore
had ambiguous types, with follow-on inference errors. The complete failed log
has SHA-256 `f64c03857592f7b148a9eb6c133c7f2f6cdf5a82b01654f91a594290f64ebf9e`.
Its sixteen source/log/receipt files were archived before correction in
`artifacts/goal-sixth-deferred-close-compile-failure-v1/failure.json`, SHA-256
`6e2294120cb71b9578f49b2127522685bbfdd79bd0125a7f59b7a7a2eb7a065b`.
No test execution or passing-test credit is attributed to that build.

The correction qualifies two fixture arrays and the ticket helper's argument
and default constructor as Foundation.UUID. Exactly three lines change; all
production code, fixture behavior, and assertions remain unchanged. Independent
source review confirms that these values are the Foundation UUIDs required by
the existing ticket API. The frozen input bundle remains intact. The exact
root-only overlay is recorded in
`artifacts/goal-sixth-native-uuid-overlay-v1.json`, alongside the earlier
MainActor fixture annotation; later integration comparisons must retain both.

The corrected run passes 133 distinct XCTest cases across six targets and eight
serial invocations: 38 deferred-close, 37 close-control, 29 dialog-ownership,
13 dialog-outcome, twelve native close-request, and four color-dialog-provider
cases. There are no failures, skips, or duplicate completed case identifiers.
The actual child exited zero at 08:29:10 UTC. Its staged source tree is
`aca6b3de71828a55dd363c639dd25239cd39e83a` over `5a09843`; the recorded
input hashes, index bytes, Git status, and source tree did not change during
execution. The log is `artifacts/goal-sixth-deferred-close-tests-v2.log`, SHA-256
`e1a36066b09a94ca3c7760cf9b6489f08af8bf817720e055c71fa601e246840b`.
All six changed Swift files pass a fresh strict lint and contract check.
These results include owned hidden-window cases, not visible dialog workflows,
arbitrary third-party message loops, or final App/document close qualification.
The retained-build, layout-receipt, and final host increments remain pending.

The isolated F9 Foundation phase is now sealed. All eleven configured targets
completed, all 597 planned primary outputs have successful build records and
exist, and the declared outputs include six DLLs and eleven static/import
libraries. Passive checks cover actual link/response commands, emitted library
requests, module origins, preserved inputs, and owned-process completion. The
Foundation DLL imports the two wide Win32 message functions in its PE table;
that is linked static evidence, not an executed message-pump result. The phase
manifest is `builds/foundation-f9-build/frozen-f9-phase-manifest.json` under the
owned Foundation input directory, SHA-256
`56e0d623e4d3166819e839c48167c002deea80883fd89d3dc9aaf89718887f66`.
No candidate DLL was loaded, installed, or activated. A separately reviewed
plan for real XCTest and Swift Testing consumers is still being prepared;
runtime ABI, native scheduling, Unicode, distribution, and all nine original
product acceptance gates remain unqualified.

### Sixth batch: retained build settlement notifications

Deferred native delivery is committed as `07db359`. The next increment adds a
stored settlement capability to coordinated retained builds. A build is not
settled while its root or deferred subtree is building, queued rebuilds remain,
the rebuild drain is active, or retained terminal callbacks remain. This does
not claim that geometry is resolved: layout and deferred GeometryReader work
still require their own evidence. Raw hosts without an installed lifecycle do
not expose this capability.

Settlement observers retain a registration token and preserve FIFO slots when
the same owner replaces its pending action. Releasing an old action happens
after its replacement is published and the collection's exclusive access ends.
Notification delivery is bounded to the pass's original slots, so an observer
cannot spin inline by registering itself. A lifecycle removal or replacement
invalidates old host continuations even if that object is later reinstalled.
An idle observer may run synchronously; notification is not final close
authority and must not become a synchronous prompt/retry loop.

The first focused build and run pass 115 distinct XCTest cases across seven
serial invocations, with no failures, skips, or duplicate completed identifiers.
The total includes all 34 new settlement cases and 81 existing component-host,
retained-lifecycle, mounted-state/transaction, sheet, and presentation-activity
cases. The actual child exited zero at 08:36:29 UTC. Its log is
`artifacts/goal-sixth-build-settlement-tests-v1.log`, SHA-256
`781b77ea45750ffd0246ab4e06ed845f29b52af537b8ea0d5d6cbd3158f6774f`.
The tested staged tree is `d9e76c3c69a765ffd0a9ddd815c49b041d755688` over
`07db359`; all recorded source inputs, index bytes, status, and tree remained
unchanged during execution. All four changed Swift files pass strict lint and
contracts. The frozen increment needed no further source correction. Root
comparison also verifies that all 406 preexisting test/resource paths retain
their original Git content; the two explicitly recorded earlier fixture
overlays remain the only imported-source differences apart from this goal.
Layout receipts and final native host integration remain unfinished, and none
of the original nine acceptance gates is closed by this focused result.

### Sixth batch: bounded layout evidence for close finalization

Build settlement is committed as `9bfcae2`. The runtime now records a receipt
only after one bounded layout resolution establishes current geometry. The
receipt carries a runtime-specific identity plus checked geometry and
resolution generations, without retaining the runtime or application payloads.
Later layout/child invalidation, a new resolution, nested resolution, truncated
traversal, unresolved positive-size GeometryReader slots, or pending deferred
layout work cannot reuse an earlier receipt. Generation exhaustion remains
permanently unavailable rather than wrapping into a valid old identity.

Final receipt validation reads stored identity and scalar state; it does not
run layout, application callbacks, reader bodies, lease getters, or key hashing.
Paint-only changes do not manufacture a geometry change. Build settlement is
still a separate condition, and a bounded attempt that cannot establish layout
evidence must not turn into an inline retry loop. Silent arbitrary replacement
of raw layout callback metadata is outside this receipt's stated guarantee.
The final host increment, including its additional build-history and managed
GeometryReader corrections, is still pending.

The first focused run passes 93 distinct XCTest cases over four targets and
six serial invocations: all 34 new layout/finalization cases, 34 settlement
cases, seven GeometryReader slot cases, and eighteen dismissal-policy cases.
There are no failures, skips, or duplicate completed identifiers. The actual
child exited zero at 08:43:44 UTC; its tested staged tree is
`6c7c983ea8e67f3dc5a9032c3caf80b2c9b85596` over `9bfcae2`. Source inputs,
index bytes, status, and tree stayed unchanged throughout execution. The log
is `artifacts/goal-sixth-layout-receipt-tests-v1.log`, SHA-256
`1d353c5cfa1d00adb069b8c27e7fdfa502f62a1e72a449c8c4109e224fe8b002`.
Both changed Swift files pass strict lint and contracts; no new source
correction was needed for this boundary. All 406 preexisting test/resource
paths still match their original Git content. This is focused retained-runtime
evidence, not final native document or complete close qualification.

The fifth-push hosted Windows run `33151787744` at `9f983e6` has now completed
with a failure in Full validation job `98785288310`, at Run full agent checks.
Its contract job passed and the optional Quick job was skipped. Exact logs and
artifacts are being inspected; no cause or passing hosted Full result is
inferred from the earlier local Full/Quick passes. That hosted failure and all
nine original product acceptance gates remain open.

### Sixth batch: final managed native close authority

The final native-host increment joins the earlier owner leases, deferred native
work, retained-build settlement, and bounded layout receipts. A native attempt
keeps its original preflight evidence; a reentrant delegate cannot replace it
after another delegate changes state. Preflight performs at most one observed
reload flush and one existing bounded layout query. Final validation checks
stored ownership, policy, layout history, participant identity, and pending work
without invoking application callbacks, building, rendering, prompting, or IO.
The composite reservation pins its host, participant, and prepared session until
the attempt completes. Missing document participation still rejects before
flush/layout; this does not enable native DocumentGroup or an unsaved-close UI.

Build admission now retires earlier geometry evidence even when the admitted
build later makes no visible change or is abandoned. Reader adoption invalidates
non-nil built-size assignments, including equal values. A nested render denied
by a provisional reader lease preserves the unresolved layout work during an
active coordinated build. The next independent query can resolve the actual
slot; idle denial does not create a retry, frame, timer, or polling loop.

Root integration preserved the frozen input and recorded two real failures.
The first attempt failed compilation before any tests: Swift inferred a
throwing closure for the observed-reload completion fixture. An explicit
`throws(Never)` annotation on that callback fixes inference while leaving its
body and assertions intact. Four additional fixture declarations explicitly
name Foundation.UUID, following the earlier demonstrated namespace ambiguity.
Together with the previously recorded actor and UUID corrections, these are
nine fixture-line corrections, not changes to production close semantics.

The second attempt compiled and completed 255 passing cases, then crashed in
the first reader capture-release regression. It has no passing-run credit.
The exact log, source inputs, receipts, and original 370,859,520-byte executable
were preserved before correction. The executable SHA-256 is
`c03358e7e0738f1b844745fd4ca75b6f7be9e4d7341171506250dd97daa20f6e`.
Static symbols identify the conflict as the lifecycle bag's GeometryReader
key-path write and a reentrant read of the same field during old capture cleanup.
The production fix pins the old lifecycle handler until that assignment ends,
then releases it before the setter returns. The new-storage branch, reader
body-before-size ordering, leases, and complete regression file are unchanged.
The failed evidence and symbols remain under
`artifacts/goal-sixth-native-host-runtime-failure-v2/` and
`artifacts/goal-sixth-native-host-runtime-binary-v2/` respectively.

With that five-line production addition, all 259 close/dialog/settlement cases
pass in fourteen serial invocations. Both exact cleanup phases, including
the 240/360 reader-size assertions and nested public render calls, execute and
pass unchanged. A separate twenty-target preservation run passes 325 existing
window, component, State, GeometryReader, presentation, and text-undo cases in
seventeen serial invocations. Both runs exit zero without failures, skips,
duplicate completed identifiers, timeouts, or changes to recorded inputs,
status, HEAD, staged tree, or index bytes. They tested staged tree
`11e4f763001d486b719ea2a51a638e4ac8ac80db` over `72478f2`.
The focused log SHA-256 is
`8e43c9193188d7818af878c2d212678521cf53ced2f6b0b20dc49cc26b45928e`;
the preservation log SHA-256 is
`c50c4ca173db5182fc411fef5747164850e609c3be0a97380404fd14d01d101d`.
Fresh strict lint covers all seven changed Swift files and contracts pass.
The source comparison preserves all 406 test/resource paths present before
this batch. These results include owned hidden-window fixtures, not visible
dialog flows, arbitrary modal pumps, Narrator, hardware pacing, or complete
native document qualification. All nine original completion gates remain open.

### Fifth hosted result: exact failure and evidence reconciliation

The final audit of Windows run `33151787744` at `9f983e6` identifies the gallery
gate as its first failed Full step: 67 of 85 fixtures differ. All preceding
registered checks, builds, and captures complete. The hosted and local Full
logs contain the same 4,289 distinct XCTest identifiers: hosted has 4,285 passes
and four skips, versus 4,288 passes and one skip locally. The three additional
hosted skips are the variable-font tests on an image without Segoe UI Variable.
All 134 Swift Testing case outcomes match. The previously corrected render
delivery cases pass, but hosted Full still fails its visual gate.

The runner is Windows Server 2022 image `20260818.277.1`. Its two font-diagnostic
PNGs exactly match the corresponding normal captures. Diagnostic exit one means
completed-with-pixel-mismatches and usable partial attribution; the advisory
Actions step's success is not a pixel pass. All 85 current gallery PNGs and
their reported metrics match the verified second hosted run `33110144711`.
The fourth run failed earlier and never reached this gallery gate. This audit
does not establish a new source defect or justify changing fonts, baselines,
tolerances, or reported failures. Loaded font bytes, actual shaped glyph paths,
and a font-qualified replacement runner remain unverified. The sealed audit
manifest is SHA-256
`31e57669d5fa99379d070321b666bd4f5f5ddbbeec6700a88f006af1a2fe4bd0`.
Private raw logs and signed download references are not published as artifacts
of the source package. Hosted release qualification remains open.

### Isolated Foundation framework configuration boundary

The separate real-XCTest configuration generated the expected shared target,
all 32 pinned sources, two target edges, and all 26 approved options. CMake
itself exited zero. The supervising phase nevertheless stopped because an
owned vctip-named descendant remained after configuration; exact pinned process
cleanup succeeded. This is a supervisor completion failure, not a compiler
failure or a clean two-framework pass. Testing was not attempted. Observed
parent/PID/start identity is recorded, but that process's executable path/hash
and reason for persistence were not captured and remain unknown. An installed
sibling's metadata is only a candidate identity, not proof of execution.

The stopped attempt was sealed before its original deadline, with no retries,
target builds, installs, candidate DLL loads, or native consumers. Its manifest
SHA-256 is `e66d40da81d1caf4682151919523fcc59ecdfd3a41d6a72c3715c78e16b213be`.
All predecessor input manifests were rechecked unchanged. Generated explicit
SDK arguments and twelve actual standard-module loading remarks are evidence
about configuration; the separate target-info query does not itself prove
that SDK selection. Testing's actual graph and static-library flags, framework
compilation, ABI, loading, scheduling, and Unicode behavior remain unverified.

### Sixth batch: accessibility adapters do not own a retired runtime

The alert integration exposed a separate existing ownership problem. In its
second attempt, 25 cases passed and one failed: after dropping a host, its alert
node, button, payload, and host released, but the runtime remained alive. The
surviving native-window object retained its accessibility bridge; that bridge
retained its projection source, which strongly retained the runtime. Escaped
alert receipts were not the remaining owner. The failing source and log remain
preserved in `artifacts/goal-sixth-alert-runtime-failure-v2/`; its receipt hash
is `52cb697ff538abdf8d1d00cd988927a4bbc21e38578feccbf78baff95b591f5f`.

The projection source now weakly references the host-owned runtime. Each query
or action pins its entry runtime through the complete operation, including
application bounds mapping and any nested calls. Once that owner is gone,
snapshots are empty, identifier lookup is unavailable, and actions fail without
calling retained controls. The forwarding selection method uses the same
pinned selection operation. No bridge/window ownership, COM provider release,
native disconnect, callback routing, scheduling, or public API is changed.

Four new headless regressions pass: a source and bridge outlive the released
runtime and tree; retained nodes and old identifiers cannot invoke explicit or
fallback actions after release; live ownership preserves stable identifiers,
invocation, and focus; and a bounds mapper can drop the final external owner
while all four mapping callbacks observe the operation's runtime pin, followed
by immediate release and an empty subsequent query. The original alert release
assertion also passes unchanged. The source correction and added test bytes are
bound by `artifacts/goal-sixth-uia-runtime-ownership-overlay-v1.json`, SHA-256
`774e91ac3402c8a558964b07d8c9fe4946b031b87cf5a7d86a9c2ec89c4abc7e`.

These checks executed in the joined alert working tree
`2481a293d5292bc81498ccc7633b13c27d95aefb` over `0ffc5cb`, not as an
independently qualified release commit. The eleven-target run passes 240 cases,
including all four new ownership tests and 32 existing accessibility adapter,
pattern, and bridge cases. Its actual exit is zero, without skips, timeouts,
duplicates, or recorded input/index changes. The log SHA-256 is
`58e7b7b7350049773bb4cdcaba77370a911399243e1c70ed0ab5263924603bb5`.
Both ownership files pass fresh strict lint and contracts. An earlier lint
invocation rejected a comma-joined path argument before linting; separate
documented file invocations supplied the actual passing evidence.

Source review also identified an independent native COM lifetime gap: retained
providers copy an unowned bridge callback context, while native disconnect can
fail or reenter. Merely releasing the bridge earlier would not be a sound fix.
That path is deliberately unchanged here and has a separate repair investigation;
headless ownership tests do not qualify Narrator or native provider teardown.
All nine original product acceptance gates remain open.

### Sixth batch: retained alert generations and settled focus restoration

Boolean, item, builder, and error alerts now share a stable retained shell.
Presenting and dismissing the overlay preserves the background child slot,
editor, and mounted State. Hosted actions require their accepted generation
and individual action receipt; removed, rejected, replaced, or closed content
cannot reuse an escaped action. An admitted operation runs its captured action
before its captured reset, suppresses reentry, and cannot reset a replacement
alert. A binding that refuses dismissal leaves the current alert modal.
Item identity remains typed, and presenting payloads are snapshots for one
accepted hosted generation. Equal-true Boolean bindings do not invent a new
identity or prove that an unobserved false-to-true transition occurred.

Focus restoration waits for an accepted and materialized absent shell, existing
retained-build settlement, fresh layout/prepaint, and the end of keyboard
dispatch. It rechecks ownership and focus intent across application callbacks.
It does not poll, schedule a Task, add a timer, or render continuously. Raw
Component clients require an attached live runtime and have their own receipts;
constructing a detached node does not confer hosted generation or focus rules.
Three existing alert fixtures were explicitly migrated to retain that runtime
and recognize the absent shell, preserving their action, binding, and environment
assertions. All other 405 preexisting test/resource paths remain unchanged.

The first root integration attempt failed compilation before tests because the
new invalidation getter erased MainActor isolation at two callback arguments.
The getter now returns an explicitly MainActor closure around the existing
handler, without capturing the context or coordinator. A stock Swift 6 typecheck
and subsequent real builds validate that correction. Its original source and
failure remain under `artifacts/goal-sixth-alert-compile-failure-v1/`, with
receipt SHA-256
`c87e7947cbb8f9d94f3438fcd07c68f024be38e331d053ac8cf3aeeca8e51590`.
The second attempt's runtime-release failure and separate accessibility-source
ownership repair are recorded immediately above. Neither failed attempt has
passing-run credit; no original alert assertion was weakened to obtain a pass.

The corrected joined source passes 336 distinct XCTest cases in three serial
runs: 240 alert, focus, presentation, close, and accessibility cases; all three
migrated legacy alert cases; and 93 existing mounted-State, component, editor
teardown, and GeometryReader preservation cases. This includes all 50 new alert
and focus cases and all four separately committed ownership regressions.
All runs exit zero without failures, skips, duplicate completed identifiers,
timeouts, or changes to recorded source inputs, HEAD, index, or staged tree.
The tested tree is `2481a293d5292bc81498ccc7633b13c27d95aefb` over `0ffc5cb`;
splitting the ownership repair into its own commit changes history and the goal
ledger, not those tested source bytes. The three log SHA-256 values are:

- `58e7b7b7350049773bb4cdcaba77370a911399243e1c70ed0ab5263924603bb5`
- `68b0678278efb23f858d3079c14e8e38f6a3142abf6ea9a8ebe4873f7d9a4a95`
- `e92838e0fb9f15171cdb67355c9885fdb4085ddabdf4c40834388509f6b09455`

Strict lint covers the ten alert Swift files, with a fresh check of the corrected
getter and the two ownership files; contracts pass. `docs/RetainedAlerts.md`
describes the accepted behavior and limits. These tests do not qualify native
Enter/Space character routing, UI Automation modal isolation, COM provider
teardown, document IO or unsaved-close decisions, native visual equivalence,
Narrator, or a complete template workflow. Those remain separate integrations.
All nine original product acceptance gates remain open.

### Sixth batch: RGB synthetic temp-root identity and retained CI diagnostics

The RGB synthetic suite now canonicalizes its owned UUID temporary root before
creating fixtures. The production capture already canonicalizes its repository;
the suite's mismatched logical/physical paths caused the pinned SDK workflow's
synthetic preflight to fail before any native export. The frozen reproduction
used an actual owned Windows junction and preserved the original 126-case
failure. The patch retains all original 155 RGB assertion commands, case order,
plus-name source selection, cleanup containment, and outside-path rejection.
It adds explicit root/child identity and sibling-prefix rejection checks.
No production capture, path-containment policy, font, baseline, or tolerance is
changed. This fixes tooling preparation, not native RGB or API qualification.

The SDK workflow writes RGB synthetic summaries to a sibling diagnostic folder
and uploads it separately when that step actually ran. The original candidate
directory must still be absent before export. The existing candidate upload,
runner, SDK/toolchain pins, timeout, and failure gates remain unchanged. A
summary written before a later cleanup failure cannot override the actual
step outcome; the new diagnostic upload does not turn that failure into success.
It does not promise raw mutable fixture retention or a summary before the
suite's protected body begins.

Fresh root validation runs the RGB and workflow suites serially on PowerShell
5.1.26100.9223 and 7.6.4. RGB passes all 126 cases with 498 and 505 assertions
respectively; workflow guards pass 408 assertions on each runtime. All four
processes exit zero with no timeout or changes to any recorded tracked regular
file, HEAD, staged tree, index bytes, status, or runtime executable bytes.
The tested joined tree is `62fedf97e2649fe2fa024c8e35a2f178b409a0a8`
over `dbd6b9e`; the still-uncommitted modal accessibility work is not qualified
by these synthetic tooling runs. The result receipt is
`artifacts/goal-sixth-rgb-tooling-v2/result.json`, SHA-256
`c52df914ab15bb00fa37535f54b8386dd7269fdff5b58013d9ebf14f5de2fa1d`.

The first root launcher attempt exited one before cases because its Python
intermediate process passed PowerShell 7 module paths into Windows PowerShell,
preventing Get-FileHash from loading. Its evidence remains unchanged. The new
launcher removes only PSModulePath from the PS5 child environment so that
Windows PowerShell constructs its own standard startup paths; no suite,
production source, or user/machine setting changed. PowerShell 7 is unchanged.
[Microsoft documents the startup path construction](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_psmodulepath?view=powershell-7.6).

All four integrated files match the frozen patch canonically, and its nine
production dependency files remain unchanged. Fresh contracts pass. The
earlier sealed agent evidence additionally passes both standalone and
Actions-shaped callers with aliased TEMP on both runtimes, eight serial runs;
those are local synthetic reproductions, not hosted or macOS execution. The
new workflow still needs an actual hosted run. Same-commit native RGB pairing,
pinned API export, behavioral conformance, and all nine original product gates
remain open.

### Sixth batch: current modal accessibility actions and escaped projections

Retained accessibility default and named actions now qualify the exact live
node, enabled ancestry, current modal scope, settled layout, and accepted
prepaint after one geometry query. Terminal runtimes reject before that query.
An old projection cannot activate a removed or replaced node, reuse a newly
allocated node's UIA identity, or invoke background controls through a modal.
An admitted operation pins its weak runtime through the complete handler;
copied projections and UIA sources do not retain the runtime between calls.

Toggle, Select, AddToSelection, RemoveFromSelection, and Invoke now derive
their role, selection state, no-op decision, and handler from that same current
element. The joined review found that pre-query pattern checks could otherwise
approve a checkbox and invoke a replacement button, or reverse an already
satisfied selection request after layout callbacks changed its state. One
shared invocation guard covers these routes. It does not invoke a handler
twice or add another projection query to repair a stale pre-query decision.

The first root run failed 17 of 45 completed cases because the initial guard
treated `hasPendingLayout` as proof that a geometry query had not settled.
Geometry queries intentionally leave render dirty flags intact. The guard now
uses the existing layout-settlement status, followed by the existing pure
prepaint-freshness check; it does not clear those dirty flags, render, or retry.
The next run passed 50 cases but failed two late-focus fixtures, whose geometry
assertions made the same incorrect dirty-flag assumption. The corrected
fixtures preserve the accepted layout receipt and assert that it remains
current across the callback and action attempt. This proves unchanged geometry
without an intervening resolution. All action rejection, callback count,
prepaint mutation, and subsequent recovery assertions remain intact.

Both failed runs, their original source, and actual nonzero outcomes remain
under `artifacts/goal-sixth-modal-uia-failure-v1/` and `-v2/`; neither has
completed-validation credit. Failure receipt SHA-256 values are
`070f0abe0efb6bfc3d85e38742c0c8785ede8829589eb6dc138fde568524ed29`
and `f9669da427814836dfade86b32f8d538c4dcd4a9d7f7fee569b58a4e5161cdc8`.
The corrected initial implementation then passed 264 distinct XCTest cases.
Subsequent cross-pattern and escaped-projection lifetime changes received a
fresh joined run rather than inheriting that earlier result.

The final joined run passes 293 distinct XCTest cases in 14 targets and 15
serial invocations. It includes all 44 new modal, current-element, and copied
projection cases, 17 new COM lifetime cases recorded separately below, and
the existing accessibility, alert, presentation-focus, build-settlement, and
native-close preservation cases. There are no failures, skips, duplicate
completed identifiers, or timeouts. All recorded source inputs, HEAD, index
bytes, and staged tree remain unchanged during execution. The tested tree is
`03b68c2b2a2bb0243c6fd828332ee3e7de21143f` over `c4124a5`; the run finishes
at 2026-08-28 11:15:38 UTC. Its log SHA-256 is
`3a50f212fa8ebd64fe0cf8ba7cae7a0c8cc6d65bccf08641e2e0510d9428f212`.
Strict lint covers all eight joined Swift files, and contracts pass.

The joined source matches the frozen modal, cross-pattern, projection-pin,
COM, and RGB increments with only the recorded native, actor-isolation,
ownership-test, and late-focus fixture corrections. All 405 preexisting
test/resource paths outside the previously approved legacy alert fixture file
remain unchanged. Splitting the modal and COM changes into separate commits
does not change the tested source bytes; this is still focused joined-source
evidence, not an exact-release Full run or hosted/native conformance.

SetFocus, SetValue, and virtualized realization still require separate
callback-boundary and admission work. This slice does not qualify complete
retained-build reentry readiness, native Enter/Space routing, Narrator, all
UIA patterns, or the full input workflow. All nine original acceptance gates
remain open.

### Sixth batch: revocable COM provider ownership and callback lifetime

Every provider family created by the Swift bridge now shares one native,
reference-counted context containing an immutable callback table and a sticky
availability flag. Its retained Swift box holds the bridge weakly. Escaped
roots, children, selection results, focus results, events, and held pattern
interfaces keep that context alive without retaining the bridge, source,
window host, or runtime. A live callback promotes and pins the bridge on the
main actor for the complete source operation. Temporary provider and bridge
references also survive outbound native calls and reentrant cleanup.

Disconnect revokes locally before attempting native cleanup or creating any
root provider. Failure cannot revive availability or trigger a retry. Deinit
only revokes and releases local ownership; it does not initiate outbound COM.
Operational methods check availability around callbacks and before publishing
results. Reentrant revocation releases partial interface, BSTR, SAFEARRAY, and
VARIANT outputs and returns the unavailable HRESULT. Static QueryInterface,
AddRef, Release, and interface identity remain usable after revocation.
Existing invalid-argument precedence and live unsupported-pattern semantics
remain unchanged. The original 42 C entry points and callback-table ABI remain;
owned-context factories and HRESULT-preserving test peers are additive.

The borrowed provider passed to UiaReturnRawElementProvider receives a balanced
temporary reference. A reentrant disconnect suppresses the outer publication.
An action may run before its owner closes and the final HRESULT becomes
unavailable; clients must not treat that result as proof that no effect ran or
automatically repeat the action. Native availability linearizes at explicit
context revocation, not Swift weak-reference zeroing. Callback-free metadata
may briefly remain available before deferred isolated destruction, but a
missing bridge cannot admit source work or reacquire application ownership.

All 17 new headless COM tests now compile, link, and pass in the 293-case joined
root run recorded above. They exercise actual provider objects with injected
native effects, including escaped interfaces, final release, independent
bridges, callback reentry, actor routing, failure outputs, and weak ownership.
All earlier UIA fixtures remain unchanged. The separately sealed stock
SwiftWindowsPlatform build also exits zero naturally in 35.25 seconds using
the installed Swift 6.3.0+Asserts toolchain and two jobs, with no F9 override,
warning, or error. Its manifest SHA-256 is
`98be50a8b47eaf45d09585024c13cd75772d5bde74730107296aefcfe9c2000d`;
verified copies are under
`artifacts/goal-sixth-late-intake-c4124a5/uia-stock-build/`.
That separate build alone did not compile or execute the tests.

`docs/UIAProviderLifetime.md` records the ownership contract and limits.
Neither run proves native disconnect success, every synchronous COM/main-actor
deadlock scenario, real Narrator behavior, or modal admission for other UIA
operations. The preexisting null-provider shortcut still omits Windows'
documented WM_DESTROY event-map cleanup; that is separate follow-up work.
Windows may retain an inert provider after native cleanup fails, but it must
not retain application state through this provider family. Full, Quick,
visual, hosted, and exact-release validation remain pending for this batch;
all nine original product gates remain open.

### Sixth batch: interrupted test-framework configuration continuations

Two later owned Testing configuration attempts remain failures of supervision,
not completed configurations or product test runs. Neither changes the earlier
successful F9 Foundation build's uninstalled, unexecuted status. Installed SDK,
toolchain, original source, and prior frozen evidence remain unchanged.

The second continuation started at 2026-08-28 10:17:36 UTC with a fixed
45-minute deadline. Its input preflight passed, but its supervisor exited one
at 10:24:21 UTC before worker readiness or a CMake attempt. One selected CIM
record disappeared before a process handle could be opened. Only its PID,
reported parent PID, and creation date were observed; its name, executable,
exact process start, exit code, and descendants are unknown. It must not be
attributed to a guessed executable or treated as a harmless successful helper.
The retained command-shell and console handles were cleaned up without recorded
cleanup errors, but that does not prove absence of all descendants. The zero
working-set sample came from prelaunch observation, not a measured peak.

The phase's 38-file, 233,255-byte seal has SHA-256
`d04862d544d710307023579be07dafc51839ddc0ede47b3c27952a3e077905c7`.
Its outcome SHA-256 is
`deb11f73be747f6ce12888c545f3232eb347d8cc16f09fdbbe9e8252c38b5ead`.
No Testing graph, framework build, install, or runtime load occurred.

The third attempt used a separately reviewed direct PowerShell worker instead
of the command-shell/Visual Studio bootstrap. Its new environment candidate
preserved eight compiler fields from the saved successful XCTest invocation
and explicitly added `EXTERNAL_INCLUDE = INCLUDE`. That ninth value was not
historically recorded. The candidate is not a claim of complete VsDevCmd
equivalence; unspecified inherited fields remain a stated limitation. All
26 CMake options, ten ordered PATH entries, sixteen explicit removals, and seven
phase overrides were preserved except the reviewed new output/cache/temp roots.
The deadline ran from 11:12:26 to 11:57:26 UTC and was not renewed.

This attempt passed its 18-set input preflight and independent execution gate,
established direct worker identity, and launched main CMake. The supervisor
then exited one at 11:21:22 UTC when a selected CIM child named `rc.exe` was
already gone before its handle could be captured. That string is an observation
of a process name, not verified executable identity, hash, exact start, or exit.
The main CMake attempt was interrupted. Some captured compiler probes exited
zero, but their outcomes cannot turn the interrupted configuration into a pass.
Seven exact owned termination requests were recorded, with drained output and
no reported retained-handle survivors or cleanup errors. Two raw ExitTime values
were the invalid 1601 sentinel; derived natural-exit labels for those records
remain untrusted. Selected observations do not establish exhaustive process
coverage or cleanup causality.

The final input verifier and independent evidence reviews passed. The sealed
phase contains 108 files and 4,920,081 bytes, manifest SHA-256
`1359a1c2de30e31ff4d30250abb7800b0df34d1019041105630627222a3e4c9a`;
the outcome SHA-256 is
`637b7d250ab841082eda37cdf5390c5ed6199e2fd9155518c43b62aafa566ce`.
Passive inspection found compiler-identification and scratch outputs, not a
complete top-level Ninja graph, cache, File API reply, or six-target archive/ABI
qualification. No Foundation/Testing installation or runtime load followed.

The next investigation is an isolated prototype using creation and exit debug
events, so a short-lived child cannot disappear before its creation handle is
captured. This changes execution semantics and ownership evidence; it is not a
retry under either expired authority or ordinary-execution qualification.
An owned debug connection and optional dedicated job cannot prove an exhaustive
causal process tree. Source review and controlled tests must cover exception
handling, Unicode command/environment transport, resource/deadline limits,
event cleanup, and failure paths before any new framework configure authority.
Missing identity or exit evidence remains a failure; cleanup never supplies
passing evidence. No original acceptance criterion has changed, and all nine
product gates remain open.

### Sixth batch: shaped editor navigation, selection geometry, and owned reveal

The retained editor now uses one package-internal editing-layout snapshot for
displayed visual fragments, source ranges, legal caret stops, pointer placement,
selection regions, keyboard movement, and native IME caret rectangles. Wrapping
measures complete shaped fragments. Each fragment paints intact; selection
backgrounds, composition underlines, and the caret overlay it without splitting
and reshaping the text. UTF-16 native hit positions map to Swift Character
boundaries, and visually discontinuous bidi selection pieces remain separate.
The layout preserves spaces, tabs, graphemes, line-ending forms, and trailing
empty lines without writing back to the model. Existing paste normalization is
unchanged. Unsupported exact native caret geometry remains explicitly
unavailable rather than receiving invented pixel-font positions.

Up/Down and their Shift variants move between visual lines and preserve the
preferred horizontal position across shorter lines. Soft-wrap affinity survives
compatible rebuilds. Home/End operate on the current visual fragment, while
Ctrl+Home/End operate on the document. Application shortcuts retain precedence;
Ctrl+Up/Down are reserved without moving the editor or an enclosing scroll view.
Paragraph navigation is not implemented. Active IME composition owns its
candidate selection, so these navigation and pointer operations do not move the
model insertion point during composition.

The public editor keeps its retained identity, focus, bindings, and undo owner.
An inset child viewport owns vertical scrolling. There is no hidden source label
used for measurement, accessibility, or caret lookup. Minimal caret reveal
checks the current controller, runtime attachment, focus, viewport ownership,
and settled layout, and changes only that viewport. Unrelated rebuilds and color
changes do not pull a manually scrolled editor back to an unchanged caret.
Geometry invalidation is queued through a package helper with exact node and
controller checks; it does not synchronously evaluate bindings or broaden a
public invalidation API.

Joined tests exposed two production corrections before this slice was committed.
First, the multiline input needed explicit-frame fill on both axes: an editor
framed to width 300 had continued to shape at its unframed ideal width 260.
TextEditor and vertical TextField now honor that explicit frame while retaining
their unframed ideal size, fixed-size behavior, and single-axis constraints.
Ordinary single-line TextField and SecureField sizing remains separate. Second,
reveal now normalizes an out-of-range logical scroll target even when the caret
is already visible or oversized after content shrinks. With an active tween,
normalization preserves the current presented offset rather than jumping to the
old target's clamped endpoint. It cancels only the editor's obsolete motion;
regrowth cannot revive it or alter an outer viewport's animation.

Failures remain recorded as failures, with logs and source copies preserved
before corrections:

- The first editor run completed 98 distinct cases with seven failing cases and
  69 assertion failures. The frame and reveal corrections address the observed
  production behavior; that partial run was not a pass.
- The next attempt failed compilation before any test ran because three new
  frame-fixture API references were wrong. The fixture now supplies the required
  ViewBuildContext invalidation closure and accesses the stack through
  layoutMode. Its four test cases and assertions were retained.
- The next run completed 102 distinct cases with two failing navigation cases.
  Their binding-read hooks had fired during ordinary routing layout, before the
  prepared navigation phase they intended to test. The fixtures now settle the
  bounded pending renders before arming those hooks and explicitly witness the
  intended geometry query. Existing destinations, read counts, callback bodies,
  and rejection assertions remain; the already-correct production guard was not
  replaced by a blanket rejection of legitimate fresh geometry.
- A separate 18-case run had three failing cases: two legacy reconciliation
  assertions still expected split selected-text labels, and a new clamp fixture
  confused child height with the viewport's minimum content extent. The former
  now verify intact text and separate highlight geometry; the latter separately
  verifies child height 40 and viewport extent 80. Selection, animation, owner,
  and regrowth assertions were not removed.
- An earlier preservation run completed 42 passing cases before an old
  multiline-selection fixture asserted the removed child hierarchy and then
  indexed past it. This was a fixture crash, not a passing or completed run. Its
  final method now guards the viewport/content hierarchy and verifies two intact
  lines, separate visible selection backgrounds, full selection range, and the
  unchanged binding. All other methods and bytes in that file remain unchanged.

The fixture migrations test retained construction and geometry, not presented
pixel colors. The new frame and clamp assertions are contract corrections, not
changes to the original acceptance criteria. The staged-source verifier confirms
402 preexisting test/resource paths unchanged relative to the batch base, with
the earlier alert migration and three explicitly recorded editor fixture files
as the only allowed existing-test changes.

Final focused validation uses one unchanged joined tree,
`0d8862faf23303a7f981011b3d8562de7dea3ea9`, over `4ed6011`:

- The editor/accessibility run passes 417 distinct XCTest cases across 23
  selected targets and 22 serial invocations. It includes all 94 new editor
  cases, the reconciliation and text-geometry cases, and all 293 previously
  passing accessibility, modal action, COM ownership, alert, focus, build
  settlement, and close-finalization cases. Eight GeometryTests are also
  selected by the existing shard planner. The run finishes at 2026-08-28
  12:51:15 UTC; log SHA-256 is
  `f58a2cad1b46b4d2aa6e0fb7672126693f7421bc9e69c5063fc2a4873b028698`.
- The separate preservation run passes 169 distinct cases across 11 targets and
  nine serial invocations, covering input construction and ownership, drag
  selection, environment, IME composition, selection indices, undo sessions,
  undo manager behavior, and Win32 text-input routing. It finishes at 12:42:30
  UTC; log SHA-256 is
  `371893556981304aab7b678a5bc51d7056d3e8cbff978342c04e1ab0f90cfb46`.

Those final runs cover 586 distinct cases with no failures, skips, duplicate
completed identifiers, timeouts, or source/index changes during execution.
Their receipts and per-class summaries are under
`artifacts/goal-sixth-editor-uia-joined-tests-v1*` and
`artifacts/goal-sixth-editor-preservation-tests-v2*`. Strict lint passes for all
16 changed Swift files, and contracts pass. An earlier successful editor run
contained seven duplicate completion events from overlapping geometry filters;
its 155 completion events must not be reported as 155 distinct cases.

Geometry and runtime integration are split into coherent commits without
changing the joined source bytes. The tests qualify that combined source, not
an independently tested intermediate commit. `docs/TextEditorNavigation.md`,
the compatibility table, and undo documentation describe the supported behavior
and limitations.

Wheel/drag scrolling qualification, drag autoscroll, Page Up/Down, paragraph
navigation, complete UIA text/selection patterns, arbitrary ancestor transforms,
large-document performance, native IME behavior, and pinned native editing
parity remain open. No visual screenshot or native document workflow is
qualified by these focused tests. Full, Quick, gallery, same-commit reference,
hosted, and release validation are still required for this batch. This slice
does not complete DocumentGroup or any of the nine original product gates.

### Sixth batch: typed document sessions and one model history

DocumentGroup now retains typed factories and content builders without creating
a model, fabricating an empty input file, or invoking application content during
scene collection. Editing and viewing adapters use their required associated
configuration types without forced casts. FileDocumentConfiguration exposes the
document value and its standard projected binding. Viewing permission belongs
to the underlying binding, so changing metadata on a copied configuration cannot
grant write access. Reference documents remain explicitly unsupported by this
value-inverse implementation.

This is an internal headless hosting stage. Each materialized window receives a
separate session, owner lease, undo manager, scene storage, and environment
actions before its first content build. Open/New routing retains the requesting
window's identity and mutation revision across file selection, type callbacks,
decoding, host construction, and startup. Retired requesters cannot admit a new
window or publish an error into a replacement one. Exact standardized file URLs
within one declaration reuse a window; this is not filesystem identity or
external-change coordination.

The shared DemoDocumentScene and DemoDocumentEditor use ordinary SwiftUI-shaped
source and a strict UTF-8 value document. The editor owns selection through
mounted State and receives configuration.$document. Its Windows path now
compiles, but this slice does not enable the scene as the default executable or
claim a new native macOS build. No fake open or save action substitutes for file
operations.

The live regular-file service performs bounded reads in owned operations, with
a 16 MiB input ceiling and one overflow byte to detect excess input. The codec
rejects malformed UTF-8, undeclared types, directories, and unsupported wrappers.
Valid file bytes retain BOMs, decomposed characters, line endings, whitespace,
and embedded NUL content. A NUL in a file path is rejected. Layout and the codec
do not normalize the model; the existing paste policy remains separate. The
shared exporter and document service use the same atomic write helper. Atomic
replacement does not establish power-loss durability, and this input limit does
not bound future edits, output size, or retained history.

Direct model assignments and accepted editor writes now share one document-owned
history. An editor write carries an explicit single-use mutation ticket through
generated Binding projections, receives the exact accepted model-action receipt,
and optionally attaches before/after selection to that receipt. It does not add
a second local text action or infer ownership from equal text or the manager's
top action. Optional and indexed projections retain mutation ownership without
claiming a stable selection projection. Disabled or nil history registration
does not invent fallback history. Managed secure input rejects document editing
instead of storing plaintext model inverses.

Every accepted assignment creates a checkpoint; undo/redo restore checkpoint
identity while mutation revisions continue increasing. Save records the persisted
checkpoint without clearing history. Undoing to that checkpoint becomes clean;
an unrelated history branch at the same depth does not. Losing an optional editor
selection endpoint cannot erase an already accepted model action. Composition
blocks replay, and conservative selection restoration rejects changed explicit
selection, retired owners, stale runtime stamps, and invalidated projections.
It does not claim to detect arbitrary silent side effects in custom getters.

Save tickets bind owner generation, session, operation, and mutation revision
before callbacks. Cancel, dialog failure, serialization failure, write failure,
and superseded ownership remain distinct. A completed write keeps its exact
byte/destination receipt even if a later edit leaves the model dirty or the owner
retires; obsolete work cannot update newer URL/checkpoint metadata. Dirty close
has a separate intent with Save/Discard/Cancel outcomes and a final single-use
reservation. Failed destruction releases the write barrier without reviving the
consumed approval. This protocol is exercised through explicit headless hooks,
not an ordinary second WM_CLOSE or a Boolean save approval.

Native startup continues to reject every unadapted document marker, descriptor,
or context before platform window creation, pending-work flush, or layout. The
document session is not yet connected to the native close participant, owned
retry delivery, real decision presentation, and command routing. The existing
native close primitives are groundwork, not completion of those connections.
Native scheduling, Unicode/IME behavior, actual file panels, Narrator, wheel/UIA
editor scrolling, and the complete open/edit/undo/save/unsaved-close workflow
remain required work.

### Sixth batch: Binding facade and document validation corrections

The shared document source exposed a public Binding visibility problem. The
facade now selectively re-exports the original SwiftWindowsCore.Binding
declaration. A generic typealias was tried and rejected after it caused
ambiguity for clients importing both modules; that failed candidate was not
integrated. The selected export supports facade-only public generic signatures,
property-wrapper initialization/projection, and dual-import clients without
exporting unrelated Core declarations. A separately preserved compiler probe
passes its seven expected positive/negative outcomes; three unrelated-name
sentinels and a public-import-only control remain negative. This is installed
compiler evidence, not a full native SDK compatibility qualification.

Prospective compilation also required an explicit MainActor factory closure and
two throws(Never) test-closure headers. Earlier compiler and wrapper failures
remain archived rather than relabeled as successful attempts. The corrected
prospective build compiled and linked all products and the test runner, then its
first focused run stopped after 67 passing cases at an error-clearing crash.
Root compilation independently succeeded and reproduced the same unfinished
case after 69 passes, including the two facade cases. Neither partial run was
reported as a completed pass.

The crash occurred when DocumentWindowContext cleared routingError: destroying
the displaced application Error wrote through a binding and rebuilt content,
which read routingError while its original stored-property modification was
still active. The three-line production correction retains the displaced value
through that assignment, then releases it outside the exclusive access and
before invalidation/validation. The routing ticket is already installed, so a
nested save remains busy and a newer model revision still supersedes the outer
save without writing bytes. The original failure test and assertions remain.

A separate root run completed 30 cases with one failed caret assertion. The
fixture requested upstream affinity on range 1..<2 but never established an
active caret at its lower endpoint; initial construction placed it at 2, and
undo correctly restored that captured value. The fixture now starts at insertion
2..<2, sends real Shift+Left, and asserts range 1..<2, upstream affinity, and
caret 1 before editing. Every original Unicode, type, undo, and redo assertion
remains unchanged. No production selection behavior was altered for this
correction. Both original failures and their source copies were preserved before
either correction was applied.

The final root run passes all 175 new cases:

| Suite | Distinct passing cases |
| --- | ---: |
| BindingFacadePublicBoundaryTests | 2 |
| DemoDocumentTemplateTests | 12 |
| DocumentFileServiceTests | 27 |
| DocumentGroupHostingTests | 44 |
| DocumentSessionEditorIntegrationTests | 3 |
| DocumentTextUndoTests | 42 |
| FileDocumentSessionTests | 45 |

That run also passes the 395 binding, undo, ownership, settings, window, close,
build-settlement, alert, and focus preservation cases plus 55 other existing
declaration/integration cases. There are 625 distinct passing identifiers, no
failures or skips, and no timeout. The existing broad IntegrationTests filter
runs the three document/editor integration cases a second time: 628 completion
events must not be reported as 628 distinct cases. The run uses 24 selected
targets and 32 serial invocations on unchanged staged tree
`43032b867c8e1e3bbd6d3d41acb9b2ec7a1eb017` over `faeca5e`, finishing at
2026-08-28 13:27:41 UTC. Log SHA-256:
`797e993705276c67298fb2b4c1376b0eeadb6d25b2a7883eaa800d4da863cca6`.
Receipts and per-class summaries are under
`artifacts/goal-sixth-document-joined-tests-v2*`. Recorded source, HEAD, staged
tree, and real index bytes remained unchanged during execution. Strict lint
passes for all 20 changed Swift files, and contracts pass. Compiler warnings
remain visible in the raw log; this is not a warning-free build claim.

The source verifier matches the frozen document and corrective increments while
preserving the earlier native/editor/UIA corrections and all 402 preexisting
test/resource paths outside the four already recorded fixture files. The
document work is split into four coherent commits: facade export, binding/editor
undo ownership, file/model sessions and shared sample, then headless scene
hosting and documentation. Their combined source is tested; intermediate commit
buildability is a source-dependency inference rather than a separate run.

Docs now explain the supported typed/value subset, real IO and history behavior,
and native integration limits. Synchronous main-actor serialization, mutable
reference aliases inside value documents, filesystem races, package documents,
external coordination, and large-document responsiveness remain unqualified.
Full, Quick, raw retained screenshots, gallery/reference checks, and hosted
validation remain pending for this batch. No original scope or acceptance
criterion has changed, and all nine original product gates remain open.

### Sixth batch: public compiler characterization and overlay discovery tools

The compiler-characterization tools now preserve the distinction between a
synthetic protocol check, an observed public SDK declaration, a compiler
invocation, and behavior evidence. The StateObject increment adds 24 public
source fixtures, a 42-cell paired matrix, bounded process/capture helpers, and a
manual workflow with separately reviewed metadata and case phases. It does not
change production StateObject or execute generated SIL. Native compiler cases,
their negative controls, Windows source comparison, and actual SDK/runner
qualification remain outstanding.

Overlay discovery adds bounded source occurrence and filesystem/parser tools.
Every identifier occurrence remains available for audit instead of being
collapsed into an inferred declaration or compatibility claim. Missing,
unsupported, and unreviewed observations remain explicit. The tools do not
establish an atomic observation of a whole installation, a complete Darwin
census, Stage B acquisition, or behavioral equivalence. The recorded SDK source
fixture is read only; no SDK is installed or exported by these tests.

Fresh root validation runs all ten standalone suites serially on unchanged
staged tree `ea5ff4d71633cb02bd518f9b31b07bd762caeddb` over `d0336f9`:

| Synthetic suite | PowerShell 5.1 assertions | PowerShell 7.6.4 assertions |
| --- | ---: | ---: |
| StateObject public fixture integrity | 1,339 | 1,339 |
| StateObject process protocol | 26 unsupported-host checks | 194 |
| StateObject isolation protocol | 412 | 444 |
| StateObject capture protocol | 525 | 614 |
| Overlay discovery | 1,570 | 1,570 |

All ten direct processes and both aggregate launchers return zero, with no
timeout or cleanup intervention. These are assertion counts, not product XCTest
counts. PowerShell 5.1 does not run the PowerShell 7 process cases, and its
isolation suite reports unavailable file-symlink creation explicitly. The
PowerShell 7 capture suite additionally verifies eleven pinned SDK source files;
neither host runs a native SwiftUI compiler or app. Each overlay run covers 139
synthetic fixtures and produces 17 unreviewed sample identifier records.

The StateObject run finishes at 2026-08-28 14:05:26 UTC and the overlay run at
14:06:44 UTC. Results and raw per-suite logs are under
`artifacts/goal-sixth-stateobject-joined-v1` and
`artifacts/goal-sixth-overlay-joined-v1`. Their result JSON SHA-256 values are
`7fbb86c3d8e82cab11c2823ba5d91531a94a7765f19bc311a4177112340367c6`
and `479115f40439b268faa2b55327acfd818b8759130eb088b4e242bdbb956f2821`.
Before/after checks preserve tracked file bytes, HEAD, staged tree, real index,
the selected SDK fixture files, PowerShell executables, and the launcher. Only
the PowerShell 5.1 child's inherited PSModulePath is removed; the user's
environment is unchanged. Contracts and strict lint of all 24 new Swift fixture
files also pass on the joined root source.

The earlier embedded-runner limitations and failed CRLF fixture/proof attempts
remain historical evidence, not converted into successful runs. Standalone
success does not qualify the manual hosted workflow or repair every embedded
caller. The existing 61-record/179-probe API audit, its 67 unrun probes, the
public baseline, and compatibility approval remain unchanged.

Compatibility, mounted-state, and roadmap text now describe the already
implemented alert, inherited body-builder, and lazy StateObject factory
behavior without changing roadmap acceptance or the original goal. The tooling
and documentation are committed separately. Bitmap diagnostics and the full
batch's Full/Quick, raw retained rendering, gallery, reference, and hosted
validation still require their own results. All nine original product gates
remain open.

### Sixth batch: opt-in bitmap glyph and face-file evidence

Version 2 bitmap diagnostics now record copied display DrawGlyphRun indices,
their actual retained faces, callback/result information, and bounded bitmap
receipt associations. Glyph zero, order, multiplicity, distinct face identity,
replay rejection, cache reuse, partial results, and scene-reference limits are
preserved explicitly. Metadata probes cannot supply display-glyph ownership.
The optional native helper reads public Face5 axes and eligible local face-file
streams through checked, retained read handles. Its digest describes a newly
observed face-file stream; loadedBytesDigest remains not-observed and does not
claim to identify the bytes used during an earlier rasterization.

The existing V1 report, strict reader, default CLI behavior, CI selection,
pixel thresholds, font selection, and regression baselines are unchanged. V2
requires the existing diagnostic opt-in plus version 2. Its strict reader keeps
the unchanged attributionV1 payload nested inside the expanded report and
rejects inconsistent graph references, counts, axes, file states, or privacy
markers. Font bytes, private paths, reference keys, ordinary/secure text, atlas
contents, and historical global chronology are not exported by V2.

Bounds remain 128 glyphs per run, 16 callbacks per attempt, 256 runs and 4,096
copied glyphs per session; 64 faces, eight files and 32 axes per face; 16 MiB per
stream, 64 MiB requested stream bytes per session, 64 KiB fragments, and 512 KiB
sidecars. These are requested/returned-byte bounds, not synchronous API deadlines
or physical IO guarantees. Report-local face IDs do not promise complete graph
canonicalization or stable identities between independent reports.

The isolated candidate build and its one focused execution passed before root
intake. Root independently compiles the joined source and passes all 138 distinct
cases, including all 59 new cases, in five targets and nine serial invocations:

| Suite | Existing passing cases | New passing cases |
| --- | ---: | ---: |
| NativeBitmapFontDrawCaptureTests | 11 | 11 |
| NativeBitmapFontAttributionSessionTests | 28 | 20 |
| NativeBitmapFontMetadataTests | 30 | 0 |
| NativeBitmapFontStreamTests | 0 | 28 |
| BitmapFontAttributionViewTests | 10 | 0 |

There are no duplicate completed identifiers, failures, skips, or timeout. The
first root build takes 296.22 seconds; the run finishes at 2026-08-28 14:18:13 UTC
on staged tree `9954c773b376a45cb6eb873a8b301af36b133f31` over `740b761`.
The raw log SHA-256 is
`dbdf0e5a75060bd4d85a984ccc9e32dbb88b9d1f09fc28f792947cbf5f62bb20`;
receipts and the per-class summary are under
`artifacts/goal-sixth-bitmap-joined-tests-v1*`. Actual child exit is zero and
recorded source, HEAD, staged tree, status, and real index bytes are unchanged.
Warnings remain in the raw build log. The two modified existing test files add
825 and 207 lines without deleting any original lines or assertions; the V1
42,436-byte test prefix remains unchanged. The joined-source check preserves
400 other original test/resource paths and the previously documented fixture
corrections.

The root PowerShell 5.1 and 7.6.4 standalone schema suites each pass 411
assertions, with zero native/C# compilation, renderer, or SwiftPM calls. Both
child exits and the aggregate launcher exit are zero, with unchanged tracked
inputs, index, PowerShell and launcher bytes. The result at
`artifacts/goal-sixth-bitmap-protocols-v1/result.json` has SHA-256
`6de353fed8281f48f8e20b55f169fd4fca13014216c6372b07219b3f67da132d`.
Contracts and strict lint of all nine changed Swift files pass. The earlier
isolated PSModulePath startup failure and manifest-packaging failure remain
preserved separately; neither was a successful compiler/test invocation.

This evidence covers headless C/Swift and injected COM/stream fixtures plus
in-memory retained snapshots. It does not yet qualify real positive Face5,
filesystem/ReOpenFile, CNG, fragment-failure cleanup, or off/V1/V2 PNG equality.
Fresh committed-source diagnostic runs remain required for those observations.
No font profile is qualified and the 67/85 hosted gallery mismatch is not fixed
by adding instrumentation. Full/Quick, raw retained/gallery/reference checks,
hosted validation, and all nine original product completion gates remain open.

### Sixth batch: routine regression registration

Quick validation now includes the new document/session/undo, dialog and native
close ownership, retained alert/accessibility lifetime, editor layout/viewport,
Binding facade, and bitmap stream suites. Four new sharded steps and three
extended filters preserve every existing step and filter term. Full and the
shared preamble are unchanged; no assertion, screenshot, baseline, threshold,
capability gate, or shard limit is removed or relaxed.

The reviewed source model adds 28 previously unselected classes and 671 distinct
methods exactly once, predicting 1,963 to 2,634 selected XCTest identifiers and
126 to 166 serial main-Quick test invocations. Those counts exclude the portable
test and material-classifier commands. DocumentSessionEditorIntegrationTests
joins the existing public/input group so its substring match does not repeat
the older IntegrationTests class in a separate group. Existing bitmap and
editor classes already selected by Quick are not duplicated.

The two-file patch has SHA-256
`0fcdab3b8bebed6a3628c0197756debc2d3018704532266388838dcb52bbf10c`;
its source model, exact replay, and independent review are retained under
`artifacts/goal-sixth-quick-registration-intake-v1`. Explicit PowerShell 5.1 and
7.6.4 AST checks pass. This is registration evidence, not execution or a timing
claim. The documented approximately-ten-minute Quick target remains unchanged;
the preceding batch's recorded 13-minute-31-second run does not satisfy it.
The new candidate must be measured before the accumulated push. Full, Quick,
rendering/reference results, and all nine original product gates still require
their own evidence.

### Sixth batch Full attempt: preserved facade regression evidence

The first clean sixth-batch Full run used commit
`26144ba3099447e2bf3bd32f4d2ef23f7c1d2bd8`. Its PowerShell child started at
2026-08-28 14:29:38 UTC and exited naturally with code 1 at 14:45:03 UTC
(925.203 seconds). The capture runner also returned 1. This was a test failure,
not a timeout, cleanup intervention, or source change. All tracked working
bytes, HEAD/tree, status, and raw index observations matched before and after.

The run completed 17 agent-check steps before failing its eighteenth step,
the main sharded XCTest suite, at shard 226 of 249. The observed log contains
4,366 distinct XCTest starts and terminals: 4,362 passed, one known material
test skipped, and three failed. The completed Swift Testing invocations
reported 134 passing tests. Remaining shards, later builds, screenshots, and
the gallery gate were not reached; these partial counts do not establish a
successful Full result.

There were four failed assertions in three existing `WinSwiftUITests` methods:

- `testTextFieldVerticalAxisMapsToMultilineInput` expected the first child
  itself to carry `hi`.
- `testTextEditorSupportsBasicMultilineBindingInput` expected that same direct
  text child both before input and for the rebuilt `hi\nAb` value.
- `testTextInputSingleRangeSelectionReplacesAndDeletes` expected automatic
  retained affinity after the multiline forward deletion; the editor returned
  downstream affinity at the same insertion offset, 2.

The committed editor now uses a clipped vertical viewport, with real shaped
  line fragments in its content and no hidden full-source label. The viewport
  retains the unlimited/wrapping style, while each shaped fragment paints once
  with a single-line clipped style. A faithful fixture correction must check
  the real fragment contents and viewport semantics, not move the old style
  assertions onto the first fragment or inspect only the first line. The
  affinity expectation must follow the editor's explicit post-edit downstream
  policy without changing the single-line field's separate behavior. Source
  review identified these fixture assumptions; a corrected run remains pending
  at this entry.

The complete raw log is 1,480,801 bytes, SHA256
`8661d3070f38cf9748ebb9c914799ddbff25d8004a1447e7370c496f6e1f5fae`.
The immutable failure archive is
`artifacts/goal-sixth-full-26144ba-failure-v1/failure.json`, SHA256
`4079d75989a29a7c809c60e82c96f9821bfee9e455badcff1806bc386a5a4476`.
Its 193 preserved files include run receipts and the shared render files that
were present after failure. Those render files predate this attempt and are
explicitly stale; their existence is not new rendering evidence. Archive
completion means the files were preserved and checked, not that validation
passed. No baseline, tolerance, font, renderer, or test selection was changed.

The follow-up is a minimal fixture correction, focused validation of those
three methods, then fresh clean-commit Full and Quick runs. The failed attempt
and all earlier evidence remain unchanged. The original nine completion gates
remain open, and no interim test result is a substitute for their full scope.

### Sixth batch facade correction: all 575 class cases pass

The follow-up changes only the three fixture method bodies identified above.
The multiline assertions now validate one clipped vertical viewport and its
content, the propagated unlimited/wrap style, and the actual visible shaped
fragments (`hi`, then `hi` and `Ab`). Each fragment must paint as one clipped
line. The complete accessibility value is checked as well; no hidden source
label or first-line-only shortcut replaces the original content check. The
multiline deletion now checks downstream affinity in both retained selection
and the authored selection binding. The two single-line field branches,
original input dispatches, logical caret offsets, and every other method remain
unchanged. This is the existing retained editor policy, not a new native
SwiftUI conformance claim.

The reviewed test-only patch has SHA256
`4644641245ddbb9042be92dc21f2788956f63f22bbe6bfd5aac374b53f765f49`.
Architecture checks and strict formatting of the changed Swift file passed.
Root then ran the complete `WinSwiftUITests` class serially, not just the three
methods: **575 distinct cases passed**, with zero failures, skips, duplicates,
or unmatched generated identifiers, across 20 SwiftPM invocations. All three
corrected cases are included. The unchanged `-Sharded` script selects and
batches a whole discovered class even when a filter names individual methods;
this run deliberately used the class name. Its 20 Swift Testing tails each
reported zero additional tests.

The run used staged tree `69353faea95bc4023fd410be8dc4f5171cbf987e` over
`26144ba`, from 15:15 to 15:19 UTC on 2026-08-28. The first build completed in
207.03 seconds. PowerShell and the capture runner exited naturally with 0;
all 740 tracked input files, HEAD, exact staged tree, status, and raw index
remained unchanged. There was no timeout or cleanup intervention. The 186,205
byte log has SHA256
`563b755a842b733e5662188f2e9bb153f905d4f021719fb4811d49ddb02daec1`;
the exact case audit is
`artifacts/goal-sixth-facade-focused-v1-case-audit.json`.

The prior Full failure remains unchanged. A later source review also identified
a case-sensitive baseline lookup in its artifact archiver: tracked paths use
`Tests/fixtures/...`, while the report uses `tests/fixtures/...`. That adds
lookup errors to the failed archive; it is not evidence of another rendering
failure. A separate archiver correction must reject colliding path aliases and
retain exact file hashes and lengths. It does not change the baseline pixels,
thresholds, renderer, or the original failed validation result.

Full, Quick, new raw renders, and same-commit diagnostic comparisons remain
pending after this focused pass. All original goal requirements and nine open
completion gates remain unchanged.


### Sixth batch second Full failure and diagnostic rerun

The next clean-root Full attempt used commit
`1ce6b9a0fa478fc5e636a146073b58dfd6ad9201`, after the 575-case facade pass.
It stopped before SwiftPM, XCTest, Swift Testing, builds, screenshots, or
gallery comparison. Six preliminary tooling steps passed. The synthetic API
audit ledger fixture then failed while publishing its second output directory:
`System.IO.Directory.Move` reported access denied for the owned staging
directory. The earlier all-queues output existed; image-queue was not
published. Existing failure cleanup removed the staging directory, so its
failure-time attributes, open handles, and inner HRESULT cannot be recovered
from that formatted log.

PowerShell PID 50332 and the runner exited naturally with 1 after 25.547
seconds, with no timeout or termination. HEAD, all recorded source inputs,
status, and the raw index remained unchanged. The 3,010-byte raw log is
`artifacts/goal-sixth-full-v2-caed57ce124b4015849aad22abd78db1/raw.log`, SHA256
`7b0535fd5a4964e710992b8186d72c6c47b01662e566fdf84789bb1a09b47fbc`.
The corrected archive collector preserved the failure and existing outputs in
`artifacts/goal-sixth-full-1ce6b9a-failure-v2/failure.json`, SHA256
`6146a89a55c8cdebc68552bd7e40fac515feeb486934c6f9e3e2703710edab9c`.
Those existing images remain historical artifacts, not new renders from this
failed attempt. The collector's Windows path normalization corrects its own
`Tests`/`tests` source-binding lookup; it changes no baseline, pixel threshold,
or validation outcome.

Static inspection found no deterministic undisposed stream in the successful
audit-writing and merge paths. One separately bounded diagnostic invocation
of the unchanged ledger fixture then passed all 391 assertions in a fresh
owned output directory, with natural PowerShell exit 0 and no retry or cleanup
intervention. It preserved the root inputs and all 40 available original
fixture files. This means **not reproduced; cause unresolved**. It does not
establish that an antivirus, transient lock, or permission policy caused the
earlier failure, and it does not turn that Full attempt into a pass.

The diagnostic receipt is under
`C:/Users/maxw6/AppData/Local/Temp/swift-windowsui-audit-publication-diagnostic-0a1ca23095594a8d8ff2c4f1526cfdd0/`,
with `reproduction.json` SHA256
`542744b71fd8bca6409bc9380a8fe62e78495c29a5cdf0013ca4551df7428157`.
Read it with `correction-index.json`, SHA256
`ec61343ca9090612ad0f497ad4df045fcb0b2b68c70bfa0c4bd7e825de3c61e9`:
the parent's RGB run was planned but had not launched during this diagnostic.
Other concurrent activity was not qualified, so its duration is not an
isolated performance measurement. No move retry, ACL change, alternate
publication path, or production correction was used for this rerun.

### Sixth batch current Windows RGB constructor evidence

The existing Windows RGB collector completed on the same clean `1ce6b9a`
commit and tree `e11c8b3567039e396178faf85b0d4745618a0a89`. It built the
release observer successfully and ran it in three fresh processes, each with
natural exit 0. The 25 distinct constructor cases comprise 23 required finite
cases and two exploratory Display P3 cases. Each process reports one
observation per case: **75 case observations and 300 float components in
total**, not 75 distinct constructor cases. All three complete case payloads
agree exactly, including encoded component bit patterns. The observer controls
are healthy, and the source, tool, and executable integrity checks passed.

Evidence is in `artifacts/goal-sixth-rgb-windows-1ce6b9a/`. The capture manifest
SHA256 is `8752ae2b06bc11fd2afc84cbdd94d86398a00ab774d416696a750c4e1366ccad`;
the independent count/PID/report audit is
`artifacts/goal-sixth-rgb-windows-1ce6b9a-case-audit.json`, SHA256
`69662feb9ed97672e97a528588709d90ca95e042f4c0327911b3c331457bac73`.
The executable is 41,268,736 bytes, SHA256
`916f56ee3389e3501ea129aa78b468da662a36d0170c6f995589c8b9f1f179b8`.
Observer PIDs 39416, 49672, and 43884 match their individual command and report
records. The outer PowerShell process also exited naturally with 0 after
294.985 seconds, including compilation and collection. There was no timeout,
termination, source/index change, visible window, or system-setting change.
The wrapper changed only its child environment: it removed `PSModulePath`
and set `GIT_OPTIONAL_LOCKS=0` to avoid incidental index refreshes.

This is a **captured candidate**, not a pinned macOS comparison or declaration,
source, behavior, GPU, or release qualification. No Apple reference was run,
no compatibility status was promoted, and no tolerance or baseline changed.
The original requirements and all nine open completion gates remain intact.

### Sixth batch clean-root Full and Quick outcomes

The later Full run passed on clean commit
`1ce6b9a0fa478fc5e636a146073b58dfd6ad9201`, tree
`e11c8b3567039e396178faf85b0d4745618a0a89`. Its log records **4,991 distinct
XCTest methods: 4,990 passed and one skipped**, with no failures or duplicate
identifiers. The skip is the existing
`RenderPassAbstractionTests.testMaterialInsideADrawingGroupBlursNothing`
limitation, not a new hardware skip. Swift Testing completion reports total
**134 passing tests** across nine nonzero reports; footer totals do not prove
every individual parameterized argument identity. The direct PowerShell
process, PID 21328, and validation runner both exited naturally with 0.
The recorded child wait and cleanup interval was **996.344 seconds**
(about 16 minutes 36 seconds), with no timeout or termination intervention.

The run produced five fresh 1280-by-720 raw retained captures:
`demo-screenshot.png`, `demo-screenshot-frame.png`,
`demo-screenshot-gallery.png`, `demo-screenshot-gallery-light.png`, and
`demo-screenshot-gallery-frame.png`. The gallery command separately rendered
and compared **85 selected fixtures; all 85 passed**. These are not 144
fresh gallery fixtures. The thresholds remain 0.5 percent changed pixels,
channel tolerance 8, and maximum channel delta 64. The archive also records
an independent RGBA comparison of the copied files. Passing is not blanket
byte identity: `state-toggle-hover` has maximum channel delta 8, with zero
pixels above the channel tolerance. No baseline or tolerance was changed.

The parent inspected all five archived raw images and recorded no new
visible blocker in `artifacts/goal-sixth-full-v3-visual-review.json`, SHA256
`3893131f63c50852d184177936b7979016ad45cd9545cd6b7ade918d09d4d4f6`.
The review retains the frame output's square-corner and simpler-material
fallback limits, and the lack of coverage below the captured 720-pixel
viewport. It is a review of raw retained output, not live GPU presentation,
pinned macOS parity, Narrator, or full interaction coverage.

The complete Full archive lists 193 files at
`artifacts/goal-sixth-full-1ce6b9a-pass-v3/validation-full.json`, SHA256
`f8568b43012b798e89a4382ae1fc841db9fa26cb6d11c922227e0e58ce56176f`.
Its 1,691,293-byte `run/raw.log` has SHA256
`ff5055b9543f79bff959c614b79c809e04ff9e347666d91109d5f7531e3ea3e1`.
The earlier Full failures and their separate diagnostic results remain
preserved; this successful later run does not rewrite those attempts.

Quick then passed on the same unchanged commit. It records **2,651 distinct
XCTest methods: 2,650 passed and the same one known skip**, plus **nine Swift
Testing cases**, each observed starting and passing once. The independent
source/log audit matches all 92 step starts and passes in source order, all
166 emitted filters, and the expected 2,651 method IDs across 185 classes.
The main selection contributes 2,634 XCTest methods and the portable
selection contributes 17. Missing, extra, duplicate, and misordered outcomes
are empty. The 974,722-byte log has SHA256
`38d8353d9ca874ded9831fe15b7f9f44a0cc87da70e3fee174851bd7b22d50a7`.

Direct PowerShell PID 46956 and the Quick runner both exited naturally with
0. The measured interval was **904.469 seconds** (about 15 minutes 4 seconds),
inside that runner's recorded 3,600-second limit. It remains **above the
unchanged approximately-ten-minute Quick target**; a passing validation run
does not satisfy that timing target. This is an observed run duration, not
an isolated performance benchmark. Plain Quick selected no screenshot,
gallery-comparison, or release-build gate.

The first Quick archive invocation supplied an absolute `--full-manifest`
path to a helper that requires a root-relative path. It stopped after copying
12 files and left an incomplete, unverified archive at
`artifacts/goal-sixth-quick-1ce6b9a-pass-v1/failure.json`, SHA256
`ecfd64f8f61a2f075d06c9769e1e06164403bebdf5884e3cbbc395e1f5735937`.
The helper's generic `RuntimeError` record is not a Quick test failure.
A separate invocation of the unchanged helper used the root-relative
argument and a fresh destination. The resulting complete 13-file archive is
`artifacts/goal-sixth-quick-1ce6b9a-pass-v2/validation-quick.json`, SHA256
`5be3f09f1fd8d1619241cb56e7cb1fb44f09ee5b685724143806326bc0666f73`.
All listed member bytes and the Full-manifest digest reference were checked.
The first archive remains unverified and untouched; Quick neither overwrites
nor refreshes the sealed Full image evidence.

Both validation runs preserve the recorded 740 tracked inputs, HEAD, status,
and raw index at their observation endpoints. The independent Quick audit
and original-argument diagnosis are retained at
`C:/Users/maxw6/AppData/Local/Temp/swift-windowsui-quick-archive-independent-audit-1ce6b9a-f176a5dbcf7fe8.json`,
SHA256 `dcbe76b74ea5cc6c3ba93e3c744a4e5036336877dd380ff830d8d3aab79f446b`.
These endpoint checks do not prove continuous immutability, binary source
embedding, or complete process-descendant closure.

### Sixth batch bitmap/font collection failures remain separate

The first native bitmap/font collection request stopped during Git preflight.
`artifacts/goal-sixth-bitmap-preflight-failure-v1.json`, SHA256
`bcd7ecb5ec3ac1cc82f8bd3ccb92e16d118b6377279bf77393482b70739e3ef4`,
records controller/tool exit 1, `git-read-failed`, and a separate read-only
Git reproduction exit 128: global literal pathspec handling was unsupported
by `git check-ignore`. The requested `goal-sixth-bitmap-native-1ce6b9a-v1`
output directory was not created, and no gallery invocation or PowerShell
workload child was dispatched. This receipt preserves transcribed tool
output and source ordering, not retained raw stdout bytes. That first
attempt remains a failure, distinct from the later collection's internal
schema-v1 mode.

The fresh collection at `artifacts/goal-sixth-bitmap-native-1ce6b9a-v2` ran
the two fixed fixtures, `stepper` and `symbol-palette`, in instrumentation-off,
schema-v1, and schema-v2 modes. All three child mode records report one
gallery command and wrapper-reported natural gallery exit 0. The direct
PowerShell exits are separately **0, 0, and 90**. Schema-v2 postprocessing
records `NORMALIZED_WRITE_FAILED`; the collector/controller returns **1**.
The parent tool observation separately records completed session 72413 with
tool exit **1**. It is a decoded tool observation, not a separately retained
Python process handle or raw outer stdout capture. The collector counts only
two validated gallery invocations and leaves
`galleryInvocationCountComplete:false`; three reported renderer exits do not
make the third mode's validation complete.

The six retained PNGs form **two matching triplets**, not six copies of one
image. Each mode's 200-by-200, 160,278-byte `stepper` PNG matches the pinned
Full `stepper` bytes, SHA256
`0abed55cb0c8cc1d66b9475855338ea640874224429e0ee05b1af0adcd5bbc45`.
Each mode's 320-by-240, 307,528-byte `symbol-palette` PNG likewise matches
that Full fixture, SHA256
`6caba719d07b2f307e3635c1d13a979966af7a1849b8c622e8c5659873c206b0`.
This exact file comparison concerns only those two fixtures; the collection
does not supply a new whole-gallery or font-attribution qualification.

Both schema-v2 raw native reports remain `partial`. Each retains a failed
`open-local-file` observation in the `win32` domain with code **87**, with
zero requested/read bytes for that failed observation. Loaded font bytes
and visible-pixel ownership remain `not-observed`; ordinary text and atlas
coverage remain `not-instrumented`. A saved 5,173-byte normalized stepper
file exists, while normalized symbol-palette is absent. Retained partial
files and incomplete processing counters are not completed normalization.

The collection's final authority is `controller-exit.json`, SHA256
`da66806be3c278caec1cf996a85ddf41983be619c6f432fbe5efd83b7b46db82`,
bound to `result.json`, SHA256
`bc9b0b715d4892d171db9472b8f7a99de13ae525608504ae88337831ebbd1eb9`,
and `manifest.json`, SHA256
`0b1e18f97a2e86db6672f5bd931f5bcb9f247e63c7dfe8457e1a1820ca096554`.
The parent observation is
`artifacts/goal-sixth-bitmap-native-1ce6b9a-v2-parent-tool-observation.json`,
SHA256 `5ab62af318876a8f9d76e5dfff1ce913c37829192d9c4449da96426d2d7aa7f1`.
The recorded collection interval through seal verification is 11.843 seconds.
The receipts preserve `integrityComplete:false`, `qualification:unqualified`,
`shareableNativePayloads:false`, `descendantClosureVerified:false`, and
**`requiresOperatorCleanupBeforeAnotherRun:true`**. No automatic retry or
timeout is recorded. Endpoint preservation checks do not clear that cleanup
flag or establish descendant closure.

### Sixth batch offline font-postprocessing reproduction

One separately bounded offline PowerShell 5.1 reproduction used only the
saved reports and parser. The launcher observed PID 34404 exit naturally
with 0, with 0.985 seconds recorded before its exit receipt; the outer tool
also returned 0. Exactly three top-level strict V2 converter calls and one
missing-property getter control ran. There were no native/product, native
helper, or `Add-Type` invocations.

The raw stepper and symbol-palette reports were accepted. Regeneration
produced the same 5,173-byte stepper JSON as the saved failed collection,
SHA256 `f9189f93e8532ece487e9b62b0ddc5ba5cf72fab14d9b3abde5a724e39148ea2`.
Strict reparsing rejected that generated JSON as `invalid-native-schema-v2`.
This reproduces the normalization/serialization boundary defect from saved
inputs; it is not a successful native collection or a production correction.
The six null-identity observations, including the explicit-null control,
all reported both `actualNull` and `automationNull` true. Those observations
do **not** distinguish the underlying sentinel identity.

The parent observation is
`artifacts/goal-sixth-bitmap-offline-v1-parent-observation.json`, SHA256
`ab7eb011b9949616d8bec50f97e58c0b6282b70019a6f2cca6480c2e252fd25b`.
The offline result is under
`C:/Users/maxw6/AppData/Local/Temp/swift-windowsui-bitmap-v2-postprocess-audit-1ce6b9a-c5bfe34ea1d9/offline-repro-output-v1/offline-result.json`,
SHA256 `1fb03ec61c6027e92ca3d5597cca2fe08bd89d5a9c80081f0b7f098eb5cf83d4`;
its `offline-repro-launch-v1/exit.json` has SHA256
`56b267da2479bffed5742cdd56d9c49043e39e15c510f781d53078772f262825`.
The launcher records process completion and input preservation, not semantic
reproduction by exit code alone; the separately inspected child report and
generated bytes support the reproduction finding. A tracked correction and
its validation remain pending. The original native failure and its cleanup
flag are unchanged.

No GPU, pinned macOS, Narrator, original-loaded-font-byte, hosted-gallery, or
complete descendant qualification is promoted by these results. The existing
Full failures, first Quick archive failure, both native collection attempts,
and all earlier evidence remain preserved. No original requirement, timing
target, baseline, tolerance, or one of the nine open product completion gates
has been removed, relaxed, or marked complete.

### Seventh batch publication diagnostics and first root result

The sixth validated batch was pushed together through
`c7e7987b4eb94becabee51b816ef60116069d838`; the local and remote `main`
references matched afterward. That commit changed only this ledger relative
to the previously validated `1ce6b9a` source tree. The following work is a new
batch and does not inherit a claim that its combined tree passed Full or Quick.

The API-audit builder now records bounded diagnostic facts if its single
`System.IO.Directory.Move` fails. It still attempts publication once, preserves
the original failure, and runs the existing staging cleanup. A best-effort,
create-new sibling report contains bounded exception type/HResult facts,
source/destination/parent path observations, the audit manifest hash, and process
version/identity. It does not serialize exception messages, stacks, arbitrary
exception data, or the process environment. No retry, delay, forced collection,
sharing change, ACL exception, alternative publication path, or antivirus
exception was added. Successful publication does not load the new helper.

The three source files came from the frozen publication-diagnostics packet,
patch SHA256 `d3bd77d53a4254c32e48c5830538797fee77a574c2a294afabae8868f27bef8d`.
All 31 manifest members were verified before intake. The isolated candidate
previously passed 241 diagnostic assertions plus the existing 391 ledger
assertions once on each of PowerShell 5.1 and 7. Those isolated results are
separate from the new root execution below.

The root sequence at
`artifacts/goal-seventh-publication-diagnostics-root-v1` invoked the new
standalone fixture serially on PowerShell 5.1 and then PowerShell 7. It did not
run SwiftPM. PowerShell 5.1 PID 55720 exited naturally with **0** after 9.453
seconds: **241 diagnostic assertions and 391 existing ledger assertions
passed**, with the existing ledger invoked exactly once. Its 1,062-byte log
has SHA256
`05265fa4a3da25e3ed5159603fcbe76d737a81795c3665c5f3146176fdb2e41e`;
its test summary has SHA256
`6a7db1caef8c9bfb6c764ab00c6f71bed823830de0b0b2d2b82ded3d4f6bf3a8`.
The synthetic cases cover success, prepublication failure, a move failure,
diagnostic failure, and diagnostic-name collision. The exception object,
HResult, error ID/category, and target remain preserved through rethrow;
the outer PowerShell ErrorRecord wrapper was observed to be a different
object, so wrapper reference identity is not claimed.

PowerShell 7 PID 17020 exited naturally with **1** after 3.703 seconds. The
existing ledger published its first all-queues result, but its second
image-queue publication failed with access denied. No final assertion summary
was produced for this host; neither 241 nor 391 passing root assertions are
claimed for it. Its 840-byte log has SHA256
`5c8a0a03ed51d3541aa278f2eec38b77de52408e61e28e84f929d62c3bab7290`.
The whole sequence ended after 13.406 seconds without timeout, termination,
retry, or source/index changes. All 742 recorded input files and the index
remained unchanged. This is a failed root validation, not a successful rerun
or a correction of the earlier Full publication failure.

The failure-only reporter captured the actual failed move before cleanup in
`ps7/existing-ledger/.swiftui-api-audit-abff17f061454a7b96325c7c73130a97.publication-failure.json`
inside that root output directory. Its 1,665 bytes have SHA256
`99557c84c78abf488be47819ca24981541846a17237c0ad25008f60670c36f77`.
The exception chain is `MethodInvocationException` / `0x80131501` wrapping
`IOException` / `0x80070005`; neither entry supplies a Win32Exception native
error code. Staging and parent attribute reads succeeded with Directory (16).
Destination existence checks returned false, but its attribute read failed.
That path error retained only the outer exception, so destination absence and
its inner failure cause are **not established**. The existing finally cleanup
path remains in place; the diagnostic remains. The saved failure receipts do
not include a post-cleanup staging-path observation.

A bounded source review found explicit stream disposal before publication
and no escaping owned handle or change into the staging directory that
explains the failure. This does not establish that every operating-system
handle was closed, or identify another process, policy, or filesystem cause.
The review is preserved at
`C:/Users/maxw6/AppData/Local/Temp/swift-windowsui-api-publication-diagnosis-c69c812c9fbf496bbf71aca155a9290c/diagnosis.md`,
SHA256 `6f4978152e060615a816357d5107caf09e0471cff19ba18804e2a20ac476a3bf`.
Fresh root `agent-check.ps1 -ContractsOnly` then passed with natural exit **0**
on PowerShell 5.1, PID 50592, in 2.063 seconds, without SwiftPM or input/index
changes. Its receipt is
`artifacts/goal-seventh-publication-intake-contracts-v1/result.json`; the
99-byte log has SHA256
`d3381946a2842a46e7e40917b01bcb3355db0cbf2e6045ec0216e814dbb1641a`.
This contract check does not turn the earlier root PS7 failure into a pass.

An additive bounded projection of path-error inner exceptions is a proposed
follow-up, not a demonstrated publication repair. This standalone fixture is
not yet part of Quick or Full. All prior failures and the original nine open
completion gates remain unchanged.

### Seventh batch mounted change observation integration

`onChange` no longer stores comparison history in a process-wide source-location
dictionary. Its zero-argument, one-value, and old/new-value overloads now stage
typed observation records on the containing host's existing mounted identity.
Separate hosts, sibling occurrences, nested modifiers, keyed rows, and explicit
identities retain distinct histories. Removing an occurrence retires its
history; a later mount begins with a fresh baseline. Optional `nil` is an
observed value, not an uninitialized record.

Only materialized, accepted builds commit observation baselines. Unused
components, abandoned construction, and rejected measured candidates do not
advance history or call actions. The adopted batch commits its proposed values
before application equality and action code. Delivery and displaced-capture
cleanup finish under the existing retained-build guard and captured transaction,
so reentrant reloads queue behind the batch. Explicit nil animation remains
distinct from an absent transaction. Equality reentry rechecks the owner and
delivery token; closing the host revokes later delivery. The existing Windows
equal-value baseline policy is preserved, without claiming native equivalence.

The frozen nine-path implementation patch is
`a84a8b1d9b662a3c1c5b222a86d01cb45f9e384af145a7566961d213303bff18`.
Before root application, all 41 source-packet members and all 12 execution-packet
members were verified and copied into
`artifacts/goal-seventh-mounted-onchange-intake-v1`. The isolated candidate at
`1ce6b9a` with staged tree `14ca024c128a013820cb4f14aae10049049064e3`
passed **691 distinct XCTest methods**, including all 38 new methods, all 575
methods of `WinSwiftUITests`, and 78 preservation methods. Three existing
`onChange` fixture bodies now use a real mounted host; their original value
assertions remain intact. That isolated result is separate from root validation.

Root intake applied the patch without conflicts at commit
`49c50c89a2205cdf208fde9c11d64f7cd6b521ac`, producing staged tree
`cf75aa82b49d64d83cd393a4df685d10313a728e`. All eight changed Swift files
matched the frozen source bytes exactly; the new documentation differed only
in checkout line endings. Root contracts and strict lint of those eight files
passed with natural PowerShell exit **0**, PID 27888, in 18.187 seconds. Its
receipt is under the intake directory's `static-root-v1`; the 70-byte log has
SHA256 `c3f98e398e179674e879dd9b71c4cf9dafbb3d1a307abbaa83221de7ad864175`.

The subsequent root sequence, `goal-seventh-mounted-onchange-root-v1`, passed
**691 distinct XCTest methods with zero failures or skips**. Its selected
registry and observed start/pass IDs match the source-verified isolated
inventory exactly:

| Root coverage | Distinct passing methods |
| --- | ---: |
| Mounted change admission, isolation, lifecycle, and transactions | 38 |
| Existing WinSwiftUI compatibility class, including the three fixture migrations | 575 |
| Mounted State lifecycle/epochs/declarations, Binding transactions, ScrollViewReader, and presentation activity | 78 |

The unmodified stock sharded test script completed 27 serial SwiftPM
invocations. Each performed a build check; these were not `--skip-build`
invocations. The first build reported 310.87 seconds. Each invocation also
reported a separate zero-test Swift Testing tail; these tails are not 27 extra
passing tests. The direct PowerShell child, PID 29212, and the outer runner both
exited naturally with **0**, with no timeout, termination, or retry. The source
and finish receipts span approximately 380 seconds. All 748 recorded input
files, the gitlink, status, staged tree, and real index bytes remained unchanged.
Complete descendant closure is not attested by this direct-child helper.

The root log is 1,366,899 bytes, SHA256
`7c2fe257b7cbbcbfc09736718598ce869bb40bc1a7442ed2f33b53d0ec71be31`.
The exit receipt has SHA256
`766db0906a2f707259860ff03d7aa7a167f9d3aee896bdf375f3a681d47a90e0`.
The generated registry matches the isolated registry bytes, SHA256
`c463693deba5ac802af890e82199030f9d745f2c75e0b579159189816eb28de3`.
The root census is `artifacts/goal-seventh-mounted-onchange-root-v1-audit.json`,
SHA256 `c792fe877fe0e347390057b51d1012eb264c937224dc13a7c4a2ae4ceba93e95`.
All 536 Swift inputs match the prior source-verified staged blobs after CRLF
normalization; 500 also match raw bytes. The first read-only audit stopped on
an overly strict comparison of raw bytes across checkouts. Its script and
failure receipt remain in the intake directory; the corrected audit distinguishes
36 line-ending differences from source changes. No test was rerun or altered
to repair that audit assumption. Compiler warnings remain in the captured log;
no concurrency or warning flags were weakened.

`docs/MountedOnChange.md`, the compatibility status, and the API guide describe
the supported lifetime and remaining limits. Raw components without a mount
coordinator do not acquire global fallback history. The separate
`onPreferenceChange` and `task(id:)` legacy registries are still pending work.
Native macOS scheduling, public actor-isolation equivalence, exact appearance
and task ordering, callback-loop policy, and presented pixels remain
unqualified. List/data-browser integration and a combined root Full/Quick run
are still required. These results do not complete any of the original nine
product gates or change the pinned scope, timing targets, or visual tolerances.

### 2026-08-28: tested deferred-List metadata foundation; public construction remains eager

This implementation advances the unchanged deferred-construction requirements
in sections 3 and 7 without claiming that either requirement is complete.
`RetainedLazyListProvider.swift` and `RetainedLazyListExtentIndex.swift` are
package-only foundations. No public `List`, `ForEach`, `LazyVStack`, retained
runtime, renderer, or demo path is connected to them in this commit.

The provider snapshots collection metadata without invoking row factories.
Opaque source-scoped row tokens preserve surviving typed-key occurrences
through reorder, while replacement, removal/reinsertion, ID drift, or close
invalidates old requests. Materialization consumes an explicit shared budget
and checks the generation across authored collection, hash/equality, factory,
and payload-destruction callbacks. Returned row content is not cached. This
still requires O(data count) model and metadata storage and does not bound
arbitrary application-owned payloads.

The extent index represents unmeasured estimates and measured zero, one, or
multiple leaves without inventing visual wrappers. It validates finite
extents and measurement contexts, rejects overflowing updates atomically,
and supports prefix/window/anchor operations with a segment tree. Queries and
unique-storage point updates are O(log data count); updating a shared value
can incur O(data count) array copy-on-write. Anchors preserve logical tokens
and clamp after size changes; removed tokens have no invented fallback.
`docs/DeferredListConstruction.md` records these contracts and the remaining
runtime, state, focus, accessibility, and viewport integration boundary.

The first isolated compile failed before executing any tests because five new
test closures captured non-Sendable `self`. That failure remains intact in
`artifacts/goal-seventh-lazy-list-stage1-intake-v1/first-failure`, whose manifest
has SHA256
`cad4f8a3173baad4e7426a2f63aa5d3e708d51ebc34f3cdbc4b550647942b7c2`.
The correction changes only those five capture lists; no production behavior,
assertion, concurrency flag, or unchecked-Sendable declaration was changed.
The corrected isolated run passed 55 distinct methods, and its source and
execution packets were copied and verified before root intake. The complete
five-file patch has SHA256
`204431602c22f7eb24a137f4adf957d0d4b85a644331c63bf6f116c5261d415a`.

In the main checkout, the patch applied at commit
`44e8d30cb6d11e4907e9f56d49ad315f64f49a13`, producing staged tree
`6d10c5b7bb39bf08712c7b9a06d7705bff3c94bb`. Contracts and strict formatting
checks on all four added Swift files passed. The root focused run
`artifacts/goal-seventh-lazy-list-stage1-root-v1` then passed **all 55 distinct
XCTest methods: 26 extent-index cases and 29 provider cases, zero failures and
zero skips**. Declared methods, the two generated registration extensions,
and observed start/pass IDs agree exactly with the corrected isolated run.
The complete generated file differs because root also contains the separately
tested mounted-change work; that unrelated difference is not treated as a
test mismatch.

The unmodified stock sharded script performed four serial SwiftPM build/test
invocations, not `--skip-build`. The initial build reported 277.10 seconds;
the remaining build checks reported 0.26-0.27 seconds. Four separate zero-test
Swift Testing tails are not additional passing cases. PowerShell PID 43492
and the runner exited naturally with **0**, with no timeout, termination, or
retry. The recorded interval was 2026-08-28 18:39:43-18:44:33 UTC, approximately
291 seconds. All 753 input files, the gitlink, status, staged tree, and real
index bytes remained unchanged. The helper does not attest complete
descendant closure.

The root log is 1,184,165 bytes, SHA256
`0458e92e2dd6ca1f6176c0b0a02e161903317a748ccb7f4159ed1240daba566f`.
The exit receipt has SHA256
`35fa53c9dfa6392f8aedf954926d9cd1ae034a1103d2d207ddf1c98f4ddd6df8`.
The exact root audit is
`artifacts/goal-seventh-lazy-list-stage1-root-v1-audit.json`, SHA256
`764eeedd9258a522bcd49857550b786271245c7aa3911c537d04ad80de2afbb9`.
Public viewport construction, mounted-state retention across eviction,
programmatic reveal, native keyboard/UIA behavior, large-list frame time and
resource limits, combined Full/Quick validation, and macOS parity remain
required. All nine original gates, performance targets, pinned scope, and
visual tolerances remain unchanged and open.

### 2026-08-28: retain inner errors when publication path inspection fails

The publication diagnostic now preserves a bounded exception chain for each
failed path-attribute lookup, in addition to its existing outer exception
type and HRESULT. This adds three helper lines and 103 test lines. The builder,
its single directory move, cleanup, original-error propagation, and no-retry
behavior remain unchanged. The new data can distinguish more failure facts;
it does not infer absence from `Exists == false`, identify an open-handle owner,
or establish why the earlier root `Directory.Move` returned access denied.

The exact two-file patch has SHA256
`672d68b6632e63acb232901085556524d22f6e29a31a16307ff5ddd1b4e6061e`.
All 772 source-packet members and 153 passing isolated-run members were
verified and copied into
`artifacts/goal-seventh-publication-path-errors-intake-v1`. The isolated run
completed 555 diagnostic assertions and 391 existing ledger assertions once
on each of PowerShell 5 and 7. Synthetic wrapped-native, ordinary-denial, and
truncated-deep-chain cases exercise the actual extracted catch body; they
are not reproductions of the historical directory-move failure.

The patch applied to root commit
`52810b86b9eb4565b4be24c57f02bfb3b6682bed`, producing staged tree
`92c1f544940827ce183e9c28b69f3b67f42ba169` before documentation changes.
The first root invocation is preserved as
`artifacts/goal-seventh-publication-path-errors-root-v1`: PowerShell PID 41016
exited naturally with 1 because `Get-FileHash` could not be loaded. The temporary
Python launcher removed a mixed-case environment key from an ordinary dict,
leaving the inherited uppercase module-path override in place. No final
assertion summary was produced, PowerShell 7 was not started, and all tracked
inputs and the earlier publication-failure sidecar remained unchanged. This
is a launcher failure, not a passing fixture or a newly diagnosed move error.

The original launcher and outputs remain intact. A separate launcher removes
the child-only module-path override case-insensitively; it does not change
machine settings, installed modules, production code, or test expectations.
Its separate run, `artifacts/goal-seventh-publication-path-errors-root-v2`,
passed **555 diagnostic plus 391 existing ledger assertions on each host**.
PowerShell 5.1.26100.9223 PID 54352 exited naturally with 0 in 8.25 seconds;
bundled PowerShell 7.6.4 PID 6752 exited naturally with 0 in 12.375 seconds.
The sequence took approximately 21.2 seconds and completed without timeout,
termination, or automatic retry. Each host ran the unchanged existing ledger
suite exactly once. All 753 tracked file inputs, the gitlink, status, staged
tree, and real index bytes were preserved throughout both host runs.

The passing root result has SHA256
`daeeff8f9b9a2cec35dd79df22c4dca760640cb7eda26c0696bd54e23730f220`.
The PowerShell 5 and 7 raw logs have SHA256
`f0f589846ea30cf3d8fd1e29c63f0bbde28d6ac8dc3e224f85d85c4f050c779a`
and `13e9be9952c73e5660703fe01de1d86c6f3d8b8ab48189d898741d5df0c55382`.
The historical root access-denied sidecar retains SHA256
`99557c84c78abf488be47819ca24981541846a17237c0ad25008f60670c36f77`.
Neither the historical cause nor complete descendant closure is established.
This fixture remains opt-in, with Quick/Full registration and combined
validation still pending. No SwiftPM or native API-export workload ran in
this validation. All original nine product gates and their scope remain open.

### 2026-08-28: optional bitmap evidence fields now survive strict JSON round trips

`Get-GalleryBitmapOptionalProperty` now explicitly returns null when a property
is absent. The one-line production change retains the existing array and
present-value behavior. This corrects the strict V2 serialization/reparse
failure described earlier; it does not change the native collector, its file
access policy, the V1 reader, privacy rules, or CI's diagnostic-version choice.
The complete two-file patch has SHA256
`b4bc2ff12e5942af2907f09a1a981690cd4b44c967441de0fe29ec10c6855c47`.

The 252 added test lines contain 35 cases and 64 assertions: nine getter,
fourteen round-trip, and twelve rejection cases. All 411 existing assertions
remain intact, for **475 assertions per invocation**. The suite forbids
`Add-Type`, the native adapter, rendering, and SwiftPM. Both the isolated
PowerShell 5 and 7 runs passed all 475 assertions. Their source/run manifest
has SHA256
`f0ed9b11775860c5c0630027a9250177390c0ee3a2a1a662b89f86652983ef57`.
The initial hidden `.git` metadata lookup error and its corrected prelaunch
record remain in that packet; they are not fixture executions.

A separate offline replay used the two actual saved raw V2 reports from the
failed native collection. It made four strict V2 reader calls per host, once
on each of PowerShell 5 and 7, without loading the native adapter or rerunning
the collector. Both processes exited naturally with 0. The normalized and
reparsed outputs match byte-for-byte within and across the two hosts. Original
report values are unchanged; only six missing optional properties in the
stepper report and seven in the palette report become explicit nulls.

The normalized stepper report is 5,181 bytes, SHA256
`cebdccccf8c3aec0ae84aa210e40bc6c6ad4378a8635623a9edb6bf99fdd6a21`;
the palette report is 12,600 bytes, SHA256
`c92cc0581ec2f701ef6e78420be363d6a5d49bface62db0f60887ef881113d30`.
The 44-member offline evidence manifest has SHA256
`4e59f15560791f9f2cefed26b1187da5059e0d58993137d3c4b643f58054fe91`;
its independent audit reports no discrepancies. This verifies the observed
round-trip correction, not the earlier experiment's proposed distinction
between null sentinels: that original identity check was nondiscriminating.

Both packets and the hash-verified source files were copied into
`artifacts/goal-seventh-bitmap-null-intake-v1` before root application. The
patch applied at `936266b8f3609e900d29d8dc7999dde3d0d10838`, producing staged
tree `032f65514f2d90cbd131b14ef8a2566968a206ab` before this ledger addition.
The main checkout then passed **475 assertions on PowerShell 5 and 475 on
bundled PowerShell 7**, each in exactly one invocation. PowerShell PIDs 12444
and 36996 exited naturally with 0; the respective recorded intervals were
approximately 12.5 and 30.1 seconds, 42.6 seconds for the sequence. There was
no timeout, termination, retry, native call, or SwiftPM invocation. All 753
tracked file inputs, the gitlink, status, staged tree, and index bytes remained
unchanged throughout both runs. Complete descendant closure is not attested.

The root result, `artifacts/goal-seventh-bitmap-null-root-v1/result.json`, has
SHA256 `fd66c483b2ea5880e2ed89b120ae21b7089df6d1352cb54791b42138b0dc47b1`.
Its two raw logs have SHA256
`eac81b8fff662f005c166838fe96163b174cffb63dcacd8bcf3a17e6a8ef5926`
and `cf93ff6bfd379f8daa5bfe765ee9a466c4771fe869b0c615017aff891ad26b04`.

The historical native result retains SHA256
`bc9b0b715d4892d171db9472b8f7a99de13ae525608504ae88337831ebbd1eb9`,
its stopped status, and `requiresOperatorCleanupBeforeAnotherRun == true`.
The reports still describe partial, unqualified file evidence with
`open-local-file`, Win32 error 87, and zero explicit file-read bytes. The
sparkle remains vector output. No loaded-font-byte identity, successful native
V2 collection, clean native closure, hosted result, macOS parity, or final
visual qualification follows from this parser fix. Combined root Full/Quick
validation and all nine original product gates remain required and unchanged.

### 2026-08-28 seventh batch: composed accessibility source, first root failure, and exact hosted c7 audit

This entry adds evidence to the existing acceptance criteria; it closes none of
the nine original gates. The root accessibility composition is still staged,
not qualified for a passing commit or push. Its failed run is preserved below
and must not be replaced by a later successful correction.

The 29-path accessibility composition applies the previously reviewed cleanup,
focus, Realize, atomic text replacement, value adapter, field-chrome, and caret
corrections. The frozen combined patch has SHA256
`5cd59016b385fbd516eaff042232d5a0d4067926aac9d0b366634bcff363fcaf`;
its source manifest and seal have SHA256
`39cee8b6d477f1e13bdd24e4b441221bff5d8e17e0d4b58c6ffe0d35998588ee`
and `f9d3237a1b0e3974d1c7d6c2f83bfaff4ed1d6592ef04c67db24ad7835041d8e`.
Root verified and copied all 74 manifest members, plus the manifest and seal,
under `artifacts/goal-seventh-uia-intake-v1/final-source-packet`.
The source composition adds 156 test methods; prior 169-case and separate
18-case cleanup results remain results for their older owned trees.

The root at HEAD `11d02b18e587640790f4d8d3ce3273cac6c90d58` applied that
source to staged tree `06accadc1e5f99817109258546403b6082ec14b5`.
Root contracts and strict formatting of all 20 changed Swift files passed with
actual PS5 exit 0, PID 59044, in 12.625 seconds. The raw static log has SHA256
`b67701706142289b5dad6b16e6f76ac6975ed4018da1017f8a741b393edde507`.
These static checks did not establish runtime correctness.

The frozen focused plan has SHA256
`efe57427bf89b77c125c92593fac0a7f5ddfb382a3d6624edb1b2226b6e604a0`.
It selects 1,240 methods through 69 stock shards, including eight explicit
Geometry collateral methods, then three separately anchored legacy methods
without `-Sharded`: 1,243 unique planned methods. Current generated discovery
contains all 1,243 exactly once, within 5,240 XCTest registrations (5,223 Core
and 17 Portable). This is not a claim that all registered tests executed.

The first root run, `artifacts/goal-seventh-uia-root-main-v1`, stopped at shard
43/69 with actual PS5 and wrapper exit 1. PID 59420 was observed launched at
19:54:00.295294Z; its final receipt was written at 20:01:27.980614Z. The first
build completed in 332.35 seconds. All 43 invoked shards retained their normal
SwiftPM build checks. There were 789 distinct starts and terminals: 788 passes,
one failure, zero skips, and no duplicate, extra, or incomplete case events.
The remaining 451 main methods and all three legacy methods were unrun.

The unchanged existing test
`UIAAdvancedPatternTests.testRealTextFieldValuePatternMutatesBindingWithoutExposingSecureField`
failed at line 424: the binding accepted `Grace 東京`, but an immediate real COM
Value-pattern read returned `Ada`. Source tracing confirms that the old adapter
published the retained accessibility value after editing; the new atomic path
omitted that publication. This legitimate no-op-invalidation fixture exposes
stale retained metadata, not an obsolete test expectation or a COM cache that
can be repaired by adding a render to the test. A narrowly scoped production
correction and additional regressions are being prepared; none has run yet.

The failed raw log is 1,524,365 bytes, SHA256
`091bc82806e31497b82fd7eee68114d7d4b04461cf0746e8aa5c734893f10e0c`.
Its exit receipt has SHA256
`510786c608735ee32c879233c0430ca84e60d54732a5ab2264504ab601cf44f8`.
Independent partial audit SHA256
`7cf128f67a07ae0fad07a814ab8152e6da0f5b6f42e8d6c8b879b10ee464e4d8`
reconciles the generated catalog, exact filters and case events. Root reverified
and copied its nine sealed members to
`artifacts/goal-seventh-uia-intake-v1/first-root-failure`.
All 771 tracked regular inputs, gitlink OIDs, status, staged tree and index bytes
were preserved. The process exited naturally without timeout, termination or
capture error; complete descendant closure remains unclaimed. No legacy test
run, automatic retry, assertion weakening, Full/Quick pass, native Narrator
qualification or push follows from this failed attempt.

The completed hosted audit is separately bound to GitHub Actions run
`33195239563`, attempt 1, Full job `98930667586`, at exact pushed commit
`c7e7987b4eb94becabee51b816ef60116069d838`. That run failed. Contracts passed;
the Full step ran 17:36:14Z through 18:41:47Z; Quick was skipped. Successful
artifact and advisory diagnostic steps do not turn the Full result into a pass.

Its gallery report records 85 comparisons: 18 pass and 67 fail, all with numeric
pixel-comparison results rather than missing-image or size-mismatch errors.
All 67 exceed the maximum channel delta; 20 also exceed changed percentage.
Thresholds remain 0.5 percent, channel tolerance 8, and maximum delta 64.
These are verified producer-report counts, not an independent pixel rerender.
The exact 1,084,450-byte artifact has SHA256
`dd3cbd8a36145066184489ff04da84ea99981e65fc4e49e56296690826dd2dce`;
its ordinary report has SHA256
`344b78aaf8ae586eba48721dbbdeb9e2b9e7bf03f8ebae5cc1f14044636c5bae`.

Saved observations establish actual font-environment differences: the hosted
queries lack the three Segoe UI Variable families and Segoe Fluent Icons that
the local Full profile reports present. Selected hosted bitmap symbols use
Segoe MDL2 Assets where local V1 observes Segoe Fluent Icons. Saved disk versions
and hashes of classic Segoe UI and MDL2 also differ. These observations do not
establish the cause of every pixel mismatch, the bytes consumed by rasterization,
general text glyph ownership, or historical baseline font identity. No font was
copied, installed or downloaded, and no baseline or tolerance was changed.

The exact workflow supplied no aggregate XCTest/JUnit summary in the audited
artifacts. Current hosted XCTest counts and skips therefore remain unknown;
earlier runs' counts cannot fill that gap. The audit's digest-verified transfer
completed with HTTPS 200 and zero redirects; its documented blocking-transport
and incomplete archive-payload-verification limits remain explicit.
Root verified and copied all 20 audit members and manifest to
`artifacts/goal-seventh-hosted-c7-audit-intake-v1/packet`; manifest SHA256 is
`86f8185b5dd61eac10fcd52a7ee51ab4eebee8c35c24ce3c0d540a664650c4c7`.
The historical local native font failure and cleanup flag remain unchanged.
Exact release-commit CI, visual, runtime and native acceptance remain required.

### Seventh batch: second UIA failure and qualified isolated Canvas tests

The original sections 1 through 9, their nine unchecked completion gates, and
all prior evidence remain unchanged. This entry records a second failed root
UIA attempt and a successful, separately scoped Canvas attempt. Neither is a
Full, Quick, release-commit, hardware, native-client, or clean-machine pass.

The root first applied the separately reviewed accessibility-value publication
increment, patch SHA256
`2137bc8a989e2e980009f451b1f05a8096b98da20e23b210f72aca9c428aadfb`.
It changes five production lines, adds eight async regression methods, and adds
adapter documentation. The original failing UIAAdvancedPatternTests method is
unchanged. Root verified and copied 30 source-packet members and preserved 769
other previously tracked inputs. With the existing ledger included, the staged
tree became `8d896c668e80dbbf9ef5e08a6b355ad454b133ab` at committed HEAD
`11d02b18e587640790f4d8d3ce3273cac6c90d58`. Before/after contracts and strict lint
on the two changed Swift paths passed; the postcheck used PS5 PID 45572, natural
exit 0, 7.031 seconds, with source/index bytes unchanged. These static checks did
not qualify execution.

The corrected selection retained all previous planned cases and added those
eight methods: 1,248 main cases across 70 stock shards plus three separately
selected, nonsharded legacy methods. The exact plan has SHA256
`94387480d25da3b70bad6b8949a33007ea26883fd606b3ccf66eda52afcf4d95`.
Root invoked the unchanged bounded 885290 runner, with the ordinary stock
incremental build check on each shard, as `goal-seventh-uia-root-main-v2`.
Its retained PS5 child PID 52544 was observed at 20:39:12.543810Z and the failed
exit receipt was completed at 20:45:34.126665Z on 2026-08-28. The actual child,
runner and observed outer tool exited 1 naturally. There was no timeout,
termination, capture error or outstanding operator-cleanup flag. Tracked source,
staged tree, real index bytes, status and gitlink IDs were preserved; descendant
closure remains unverified rather than inferred from that parent exit.

The run stopped at shard 53 of 70. Independent exact-ID accounting found 945
distinct starts and terminals: 944 passed, one failed, none skipped, duplicated,
unexpected or incomplete. Another 303 main cases and all three legacy cases were
unrun. The generated XCTest registry contains 5,231 core and 17 portable cases;
all 1,251 selected methods occur once, with 1,243 async and eight synchronous
entries. Generated registration is not execution of the unrun cases.

The original stale-readback method now passed. Of the eight new publication
methods, seven passed. Only
`UIAValuePublicationTests.testRawControlsPublishUnicodeEqualAndEmptyValuesForImmediateCOMReadback`
failed, producing eleven assertion diagnostics. Its second and fourth SetValue
calls were refused before the expected setter and invalidation, although stored
metadata, actual text and immediate readback assertions passed. The sequence
remains Unicode, equal Unicode, empty, equal empty; all four expected accepted
writes remain unchanged. The existing capability and prior adapter tests require
same-value writes, so refusal is not reclassified as the desired behavior.

Read-only tracing identifies a concrete Field chrome/layout candidate: raw
no-op binding invalidation retains old field chrome; COM value snapshots read
stored projection rather than settling layout. The next checked focus query can
replace field children during its layout pass, leaving no unmutated settlement
proof and refusing the edit. The raw run did not label which control iteration
failed, so this attribution is source inference, not a sampled runtime branch.
A separate current-owner, weak after-layout correction is being prepared. It
must preserve the existing focus/settlement guards, incoming-field one-pass
tests and every accepted-write assertion. No extra test render or synchronous
getter at atomic completion is an acceptable substitute.

The 335,975-byte failed raw log has SHA256
`86354231e91f09c42a418b1aafb29cc82028e21a4b21505079e9f4fd6e00f91b`.
The independent audit has SHA256
`bfd1e7dd6efca0301c3b3a69db3384a824043a2c4737c4ff2bacbd57dcaa9f6a`
and its seal has SHA256
`d52bf193fb538b9ba55ee4569955704811b5342595eabfce29abe4eef44afe3b`.
Root copied the closed audit and raw/generated evidence to
`artifacts/goal-seventh-followup-evidence-intake-v1/uia-failed-root-v2`.
The fresh legacy runner remains blocked and unexecuted; the first root failure,
both source versions and both plans remain available without replacement.

Separately, the frozen Canvas even-odd slice at tree
`bce841e7b9ad8b4765e5af44947ed3c805bad36b`, based on `49c50c8`, completed
its selected isolated execution. Source patch SHA256 is
`3f0f5602f55e75e99eeee62d3bd3e8e515db3c4816a6ebe3f5dcdb85244aabb3`.
Its first attempt still records a successful 569.203-second build followed by
a failed listing with unknown direct native exit, empty output and outer exit
96; no test partitions ran in that attempt. This history was not relabeled.

The approved second phase reused those exact ten built-product pins, without a
standalone rebuild. Its tiny direct-process bootstrap successfully listed the
compiled Swift Testing methods: native PID 50632, actual native exit 0, 3.828
seconds within the 60-second listing envelope. Session 60705 and the controller
exited 0. Admission, thirteen serial nonsharded stock test calls, and final input
preservation took 191.094 seconds within the 900-second workload budget. Final
artifact sealing is separately labeled outside that quiescent workload budget.

Independent raw lifecycle accounting establishes 227 XCTest and 31 Swift Testing
methods, each started and passed exactly once, without skipped, failed, missing,
duplicate or extra cases. All 53 new methods passed. Both WARP comparisons ran
with an asserted software adapter and unchanged pixel tolerance 4, match ratio
greater than 0.995 and alpha accuracy 1. The fourteen required listing/test
stages had natural-zero direct leaf, environment-wrapper and outer exits,
complete captures, empty owned Jobs and no intervention. Sampled descendant
records still include two test-product exits 1168, cmd/reg exits 1 and unknown
images; their exact roles were not captured and no all-descendants-zero or
complete execution-history claim is made.

All 148 result members, 82 proposal payloads, 746 source inputs, 217 tool pins,
five metadata pins, 150 source-freeze pins, 106 historical pins and ten product
pins were independently checked unchanged. The result manifest SHA256 is
`64b5c61112842f5b67f297251786e3ac24bd429f4dc09cf3c8d498d14126dfaa`;
the combined review SHA256 is
`7af13a267eaf7438a796160c1a75c478fcf948e9eaa6d7636fbb86d8ebc1e203`.
Root verified and copied all result members and the review under
`artifacts/goal-seventh-followup-evidence-intake-v1`.
The first passive intake rejected a 65-character transcribed review digest
after copying the two evidence sets. Its script and failure remain preserved;
a fresh completion reverified every source/copy and the actual 64-character
digest. No product workload or source change occurred during that correction.
This is selected offscreen rendering evidence, not the whole 5,044-XCTest
candidate, hardware/performance, screenshots/gallery, or current-root
integration. A separate source-identified floating scanline progress defect is
being corrected in a new checkout; its old hanging counterexample was never
executed. No original rendering requirement, budget or tolerance was reduced.

### Seventh batch: owned execution failures and narrower passing evidence

This additive entry preserves sections 1 through 9, all nine unchecked original completion
gates, and every earlier failed or pending record. These are separate owned-checkout results,
not a current-root Full, Quick, release or native-client pass. Evidence paths below are relative
to `C:/Users/maxw6/AppData/Local/Temp`.

The second 487-case document attempt used source tree
`56df019e592c796e029523e6ecc059f929eb5443`. It stopped in batch 14 of 28: 250 distinct cases
started: 246 passed, four failed, none skipped; 237 remained unrun. The retained driver PID 4388
exited naturally with 1 in 52.403 seconds; the failed stock Swift invocation and its retained
PS5 parent also returned 1. All four NativeDocumentKeyRoutingTests failed shared setup,
producing sixteen assertion diagnostics before Save-key activation or decoded-character
delivery. They therefore establish no Return/Space routing or native document-close result. An
empty-range caret expectation conflicts with the existing insertion-point representation;
missing prompt/close-intent readiness is a separate defect. The frozen result is
`swift-windowsui-native-document-activation-a6b9f66071fe4dee8f485400a61b217c/focused-second-run-failure-v1/FIRST-FAILURE.json`;
its SHA256 is `0ff8c801d4e379e910960bd7f748baf1d57af9f6fce00a1e73c4e1176cb5d491`. The 77-member
failure manifest has SHA256 `8af30eea058b0afe10d14cd7197ea952ee829cfab2c9f4676d8f9ead45ed781c`.
The independent audit checked 75 copied raw members and 44 selected input pins; its SHA256 is
`636c7188f4f5bc9805f91d54ae7c65589cc12aa7ab94a654116a228b0667e4e0`. Closed parent streams and no
timeout do not establish complete descendant closure.

Later document tree `62faf2eb4a3bbb220abc4ee200bed05b2920bdaf` compiled with PS5 PID 31092
naturally returning 0 in 486.290 seconds. The same arena's
`compile-editor-qualification-v1/QUALIFICATION.json`, SHA256
`7e0561ed5075c0c363d509aa803041f3655c86291e2d52bf76c0142820afbaa8`, finds all 571 selected IDs
once in 5,081 generated registrations. That build ran no tests or native document workflow and
does not requalify the failed setup.

The corrected 685-case observer/preference attempt at tree
`d720bcc2f9ecc5b914071dbf73d9e52c2ed5d33a` built, then hit a runtime exclusivity trap. Source
tracing points to an authored anchor hash during a live registry lookup. Ten cases started and
nine passed; one lacked a terminal, and 675 never started. This is a fatal run, not zero
failures inferred from absent assertion diagnostics. Its frozen summary remains in
`swift-windowsui-mounted-preference-44e8d30-5f13ee0cb333/artifacts/mounted-preference-runtime-failure-dcb94d5cdd8b/SUMMARY.json`.
The earlier two-fixture compilation failure is also preserved. The later observer-only
correction snapshots lookup state before authored callbacks and rechecks authority after
cleanup; ordinary State and task(id:) paths are not thereby qualified or migrated. One later
attempt at tree `e3af569e1cf73ebc073d05e5be9937ee7d22da95` completed 689 distinct starts and 689
passes across eleven classes and 26 stock shards, with no failed, skipped, missing, duplicate or
unexpected cases. Retained PS5 PID 48188 ran 21:21:58Z through 21:28:06Z and exited naturally
with 0. The run is `artifacts/mounted-preference-anchored-1a04a3e678c` in that same checkout.
Its raw log SHA256 is `5457325d8c6ab6ffb421a18b68dbb49e6b232312e8ad89c2b960194d1bf6c3bf`; the
corrected counts receipt SHA256 is
`2d460897aeaefbe9426132efd16f7657920402daf366c7abf7b3fc2f9f138965`. All 689 selections occur
once in the 5,088-entry generated registry. Counts V1 remains: V2 adds the stock package path to
reconstructed command arrays, not OS argv captures. Independent pass review is clear;
`artifacts/mounted-preference-pass-1a04a49eee7/SEAL.json` has SHA256
`9e55354cac832e412fbecfbbdc634123e3fbf687652ea04d45e90cf16123747b`. This is focused headless
debug evidence; another 136 State/component cases, Full validation, native macOS scheduling and
presentation remain unqualified.

Dormant lazy-list Stage 2 has two compilation failures, both with zero XCTest starts or
terminals. The first selected 210 methods at tree `18c52d113040ce75bed05e96950f3b28df3b4344`;
PS5 PID 28636 naturally returned 1 after its first of fourteen planned shards. Runtime.swift
lines 16474 and 16477 rejected conversion of two non-Sendable callbacks to main-actor Sendable
closures. The second selected 223 methods at tree `60c05ff43deabee5a8cc0b4ee8b83202da6960b1`;
PS5 PID 46656 naturally returned 1 after its first of fifteen planned shards. The original
callback diagnostics were absent. Two distinct new diagnostics, each repeated eleven times,
identify `RetainedLazyListRuntimeIntegrationTests.swift` at 112:61 and 555:61: optional
`contentSize` must be unwrapped before `.height`. The second result is
`swift-windowsui-lazy-list-corrections-08f2334dc5e94857b22708f8d41ebdd3/worktree/artifacts/lazy-list-stage2-corrected-v1-compile-failure-6e3e7412e8524c56af0fefda3149a911/OUTCOME.json`;
its SHA256 is `e92fdf9d5aefce54d437fb86e7a5db4b3ab4438911508e5e72b16416dad6bf5f`. Its 27-member
manifest SHA256 is `49ff63a8dc30ebcd5b1946b5d0a2351cee13dc5060e9fc7c2bdae518a9bdcc8b`. All 754
source inputs and index/helper pins were preserved during that attempt. A separate two-line
XCTUnwrap correction retains expected heights 50 and 85; no later outcome is assigned here.
Public List construction, state preservation, bounded resource use and performance remain open
requirements.

The OpenFileById substitution compiled two CDirect2DInterop translation units: owned PS5 PID
56952 naturally returned 0 in 11.704 seconds. Source SHA256 is
`daffb9ce34bb4f4164261aad0ef0c07b59cbaa8ed032198ec295bebbe07bffc2`. The target compile packet is
`swift-windowsui-openbyid-cpp-proposal-1787944128324/completed-checks-packet-v2.json`, SHA256
`7cc47ddc602fb51d18e75aee5b2e226ce19369236e201494321c3656a7671122`. A separate single stock
invocation passed exactly six POD-projection cases: two new and four existing. PS5 PID 53828,
stock return and outer tool were all 0; 389.485 seconds included a reported 384.39-second build.
Swift Testing ran zero cases. All six selected methods occur once in the 5,086-registration
generated catalog. The 65-member result packet in the same arena is
`pod-tests-preparation-1/completed-six-method-test-packet.json`, SHA256
`cc04cb65663a6ed7cbfcae872f7932e15394e161bd75487f130e77f3bff44b5a`. All 41 selected inputs, 354
test-source pins and 35 preparation members matched; eight earlier generated files were
preserved before the permitted build reuse. These projection tests do not execute production
LocalFileGuard or native font reads. The old collector's failure and cleanup flag remain; opaque
DirectWrite stream identity, full native ABI/SDK coverage and complete descendant history are
unproven.

DirectRunner Stage A failed before its fixture launched: 61 cases and 3,524 projected assertions
were unrun. A combined PATH/Git admission guard failed, but it recorded no receipt identifying
which environment predicate was false. The before inventory contained 374 fixed pins, 4,453
prior-data files and two junctions. Its write at 197.204 seconds included setup/serialization,
not isolated preservation timing. The helper reached its 287-second cap and terminated its
retained coordinator process; the dispatcher returned 1 and the actual tool completed in 289.719 seconds. No
after inventory, phase result or worker seal completed. A fresh audit verified 374 fixed pins,
not complete preservation of all 4,453 files. Its frozen fifteen-member seal is
`swift-windowsui-stage-a-failure-audit-e882aa11724b4267a6aa1b3d2e6451cb/AUDIT-SEAL.json`, SHA256
`abb5ac162061a18de54255624e9492cfc03a26920d6ed2c4817b1a6873ce03c0`. Earlier pure passes supply
no Stage B/C, real Swift-runner, speed or Quick-budget qualification here; descendant closure is
not inferred.

The six-file CI test-evidence candidate, tree `a7c530b0f7670884b9f1765ffde888968ea37183`, failed
both initial synthetic runs. Each executed 133 PowerShell fixture cases: PS5 passed 113 and
failed 20; PS7 passed 108 and failed 25. Their observed assertion counts were 359 and 349, not
the planned 371 each. PIDs 51076 and 14432 naturally returned 1 in 3.718 and 2.441 seconds; the
outer tool returned 1. The fixture forbidden-operation count was zero, and the frozen
source/index pins remained unchanged. The assessment is
`swift-windowsui-test-evidence-packet-11d02b18-6658394b857e492f9c255be7f1ea407f/first-failure-assessment.json`,
SHA256 `808a6f161a86ba704a3d2a5699b19053c009b7566c34abd1444dee02dafa7649`. The twenty shared
failures and five additional PS7 boundary failures require diagnosis; this candidate supplies no
production observer or hosted test evidence. It does not supply the missing hosted XCTest counts
or prove runtime compiler identity.

The P6 supervisor completed only its fixed two-command compile/link phase in
`swift-windowsui-native-supervisor-prototype-1787947067718/compile-f9-supervisor-1787952052629`.
Retained clang and linker exits, collector exit, outer tool and final seal were all 0 within the
original 600-second envelope, including its 120-second reserve. The 23-member phase manifest has
SHA256 `865b38326c9b8229d6732af03d8857fd38b261cccb88d5fee1cd4b18649e4412`; the final actual seal
receipt has SHA256 `fa8b234d3281632f00a4defa1b5f28919a4752b43f43b41bf61dc44cb72c5974`. Passive
inspection found x64 COFF and PE32+ outputs; 410 include records name 333 unique headers. All
141 selected source files and three tool pins matched. This does not identify every linked
library or establish loaded-module/ABI closure. No compiled output or F9 framework workload ran;
no F9 payload or watchdog was staged in that compile phase. The historical F9
compiler-success/collector-failure audit remains failed; no runtime, performance or
clean-machine gate is closed here.

A later lazy-list attempt at tree `8e22bee0d77ecc217389ebc983f52bc1095d1e26`
compiled and reached 222 of 223 selected methods. It recorded 221 passes and one
failed case, with no skips; the last shard's one case remained unrun. The two
assertions in `testScrollingThroughCleanAncestorsPreservesOverlappingPhysicalRows`
failed its clean-ancestor precondition before the scroll. Its subsequent physical
row identity and bounded factory/consumption checks passed, which does not prove
the intended clean-ancestor path. Both prior compilation failures remain above.
PS5 PID 52144 and the runner exited naturally with 1 at 21:40:11Z; source/index
and helper pins were unchanged and no timeout or cleanup was requested. The raw
log SHA256 is `f485cba08d6e1408a9c3b0c57cb519a88b873574dcf7ddcdd2c2ed9320065437`.
The 51-member failure packet is
`C:/Users/maxw6/AppData/Local/Temp/swift-windowsui-lazy-list-content-size-ac0f7ef5c0d648edae73da0e08b1719c/worktree/artifacts/lazy-list-stage2-content-size-runtime-failure-4fbca2e59a9d43afa6dc77758bf8933c`;
its outcome SHA256 is `be527a4175a1c1e812dc5a7aac4a9ef55477a2587131372d02d833ab96a9ba52`.
Source tracing identifies intentional end-of-render invalidation retention; a
fixed quiet setup frame with additional no-work and identity assertions is a
proposed fixture correction, not a passing rerun or a runtime-policy change.

### Seventh batch: root UIA value and layout corrections pass focused validation

The third root UIA attempt and its separate legacy invocation passed on HEAD
`11d02b18e587640790f4d8d3ce3273cac6c90d58`, staged tree
`914f10292e36dc879db48d639f32fce47ec151a7`. This adds later evidence without
removing the first root failure (788 passes and one failure) or the second
(944 passes and one failure), their unrun cases, or any original completion gate.

The current source includes the reviewed UIA composition, the conditional text
value publication correction, and the separate Field layout correction. A
validated binding result is published to the same current input node before
returning. A Field label or editing-chrome change during layout requests the
existing bounded follow-up pass through a distinct, weakly captured action.
Both queue admission and delivery validate the current attached controller,
exact physical child membership and a cycle-checked path to the intended runtime
root. Unchanged chrome adds no follow-up; a redundant inactive visibility setter
is avoided. The correction adds no binding getter, UIA retry, caret reveal,
scroll operation, or new public API. The separate TextEditor correction is not
included in this tested root tree.

The original failing write assertions remain unchanged. Four messages now name
the control and loop index; two new tests cover authored Unicode selection and
moving a Field to another runtime. The old test comment about a COM read querying
layout remains historical wording: Value-pattern readback actually uses the
stored accessibility projection and does not resolve layout. Both earlier
failing method IDs and all ten publication methods passed in the new main run.

`artifacts/goal-seventh-uia-root-main-v3` recorded 1,250 distinct starts and
1,250 passed terminals across 84 target classes and 70 stock serial invocations.
There were no failures, skips, missing, duplicate or unexpected cases. The
retained PS5 PID was 43760; launch was observed at 21:30:26Z and natural exit 0
at 21:38:59Z on 2026-08-28. Its 1,700,611-byte raw log has SHA256
`1d818ea1a51a0016e2d8f7d62a2e5d0cf91c059698652d7949491d8ed6401496`.
The independent main audit is
`C:/Users/maxw6/AppData/Local/Temp/swift-windowsui-field1253-main-v3-audit-nfjgg5vn/AUDIT.json`,
SHA256 `238251d40342c5a0ee3070e08c0e3617219cc34a8989c8b7b52282f00da7c5ba`.

`artifacts/goal-seventh-uia-root-legacy3-v3` then selected exactly the three
anchored legacy onChange methods without sharding or skip-build. All three
started and passed; PS5 and the runner returned 0 naturally in 6.125 seconds,
within the unchanged 180-second envelope. Its 2,118-byte raw log has SHA256
`fe9630716006619e7176ce273b6d02f29a2bf8d54322945e45fcac34f38bc263`.
Together these runs cover 1,253 unique passing methods. Generated registration
contains 5,250 XCTest IDs, with each selected ID registered once (1,245 async
and eight synchronous). The copied test binary is 425,853,440 bytes, SHA256
`e2d048a99043d1439a9eb1d87f0b7d044be87b5d44e235b330e70c5144a5ccc6`;
it and the generated files remained identical after the legacy invocation.
The final combined audit is
`C:/Users/maxw6/AppData/Local/Temp/swift-windowsui-field1253-joined-v3-audit-ns849w9f/JOINED-AUDIT.json`,
SHA256 `9a24239a1063621010b884d915f456980d16b82fd5f316d05a097aa75c86ef95`,
with seal `8cfa87d2868f7419b695223804a36145b04e592d228da70a0ba5b880dc54e08e`.

Both runs preserved tracked bytes, HEAD, index, status and gitlink IDs; neither
required termination or reported capture/cleanup failure. The stock wrappers
observe their retained PS5 process, not complete compiler/test descendants or
loaded-module identity. Source and plan copies are in
`artifacts/goal-seventh-uia-field-intake-v1`. Contracts and strict lint on all
21 changed Swift files subsequently passed with PS5 PID 57704, exit 0 in
12.938 seconds, without source/index changes; the receipt is
`artifacts/goal-seventh-uia-precommit-static-v1/result.json`.

This closes the two reported root regressions for the selected source and cases.
It does not establish external UIA/Narrator behavior, all SDK APIs, native macOS
parity, root Full/Quick or gallery results on this tree, hardware frame budgets,
hosted release success, or clean-machine qualification. All nine original gates
remain open, and commits containing later additions require fresh validation.

### Seventh batch: document publication failures and native runner evidence

This entry adds evidence without replacing earlier failures, changing sections 1 through 9, or
closing any of their nine original completion gates. These observations are from 2026-08-28. All
paths below are relative to `C:/Users/maxw6/AppData/Local/Temp`. None of these isolated outcomes
is current-root Full, Quick, release-commit, native-client, performance or clean-machine
qualification.

The first execution of the 571-case document selection used source tree
`62faf2eb4a3bbb220abc4ee200bed05b2920bdaf` and stopped at batch 15 of 33. Independent accounting
confirms 273 distinct starts: 270 passed, three failed, none skipped and 298 remained unrun.
Among the 90 new cases, 27 started, 24 passed, three failed and 63 were unrun; 246 of the 481
preservation cases passed and 235 were unrun. All four direct host/decoder key-channel cases now
passed, separately from the earlier four setup failures. They do not qualify native
TranslateMessage or visible keyboard workflows. The failures are new publication fixtures for
independent transaction/legacy slots, ordinary binding animation, and undo/status close setup:
eight assertion diagnostics and one unexpected missing-wake throw. All six new editor/native
regressions and eleven remaining publication cases were unrun. Driver PID 39556 naturally
returned 1 in 62.191 seconds; the failed batch's stock Swift and PS5 exits and the observed
outer tool exit were also 1. Closed parent streams and no timeout/capture failure do not prove
complete descendant closure.

The immutable document result is
`swift-windowsui-native-document-activation-a6b9f66071fe4dee8f485400a61b217c/focused-third-run-failure-v1/FIRST-FAILURE.json`,
SHA256 `1190cf9e7f405fa83306f72274e283bdc2123497d8b4bc5a897eb514455462d4`. Its 87-member
manifest, including 80 unchanged raw copies, has SHA256
`dffd9214f3816b9cc89187e894c51021bb311a7eaafda6130ba4b84852cae18c`. The separate independent
audit has SHA256 `e100cfa0fddeada599da704f5122a571b1eb49046eb83989e16c818977bcbbf5` and confirms
the counts, raw copies and 51 live input pins without identifying the runtime cause.
Owner-reported source tracing separately identifies fixture mismatches involving transaction
precedence and clock advancement; a distinct layout/settlement finding in undo/status setup
remains unresolved. Those explanations are not corrected execution evidence. The earlier parser
failure and 487-case setup failure remain separate records, and no retry or source change
occurred within this failed attempt.

The exploratory P6 F9 attempt failed its controller gate. The controller and actual outer tool
returned 1; the passive validator was never invoked and has no actual exit value. The controller
observed watchdog exit 0, the watchdog recorded supervisor exit 0, and the supervisor recorded
probe and pinned console host exit 0, completed kernel shutdown and empty owned Jobs without
intervention. These retained receipts do not override the failed controller: native acceptance
and cleanup-qualification flags remain false. The probe's self-report claims task completion,
quit code 73 and three module checkpoints, but it was not accepted by the frozen validator. No
ordinary-execution equivalence, continuous module identity, general ABI compatibility or
complete causal process tree is established.

Independent read-only inspection identifies the controller's first stop at line 981:
case-sensitive `-ceq` compared the watchdog's lowercase SHA256 text with the catalog's uppercase
text. Both strict 64-hex strings encode the same 32 digest bytes; the other exit,
executable-path and deadline predicates match. This is a source-and-receipt diagnosis, not a
repaired controller result. The immutable phase is
`swift-windowsui-native-supervisor-prototype-1787947067718/f9-contained-runtime-1787954316329`.
Its `frozen-failed-runtime-phase-manifest.json` has SHA256
`f4ce3ab325ab5ee1512009c23c684744ba4ddd7e57246da0b247b4f8836396b6` and binds 42 members,
including the seventeen staged payloads. The final failure-preservation receipt has SHA256
`5835f5a95b4a400d9adc1ee0ee83794b2f2eb42a912929891f04d89d47def3f6` and records completion within
the original 600-second deadline. Source and input pins remained unchanged; no native retry or
validator run occurred in that attempt. The historical F9 compiler-success/collector-failure
audit also remains failed. A separate failed passive metadata diagnostic was preserved and is
not the cause of this native/controller attempt's failure.

A separate single startup-environment observation completed with actual parent, child and outer
tool exits 0. All twelve named Boolean predicates matched. The child took 0.509 seconds; the
measured tool boundary took 3.013 seconds within the fixed thirty-second envelope. Later copying
and audits are outside that observation interval. Under the pinned child launch, PS7 prepended
exactly one pinned PS7 directory before the supplied PATH; the first two segments were PS7 then
PS5. Get-Command resolved one Application at the pinned PS5 path, without invoking that resolved
application, and the child's GIT_OPTIONAL_LOCKS value was 0. The parent environment stayed
unchanged. Both relevant PATH digests match the historical dispatch receipts, but that
establishes neither a complete historical environment replay nor which predicate the failed old
worker evaluated.

The observation audit is
`swift-windowsui-startup-observation-audit-ec51986bf9784fe1bb15ac7c9e2cff23`; its
`pin-and-evidence-checks.json` has SHA256
`df000b4c9580f7b3feebad9d8aa694a20b4f2f4e42f5110cf710b48cffc987c1`. Its final 35-member audit
seal, `AUDIT-SEAL.json`, has SHA256
`2ce884166ca4545ad14b81f9f28ee1f835422a618823c866523d02f06c7a2227`. All 21 selected before/after
pin rows matched and were rehashed, and all 24 original observation files were copied without
byte changes. This did not repeat the older 374-pin or 4,453-file audits. Original Stage A
remains failed, with all 61 cases unrun and its full 4,453-file after-preservation unknown. At this startup-observation boundary, the
proposed attribute-lookup controls were still unrun; any later control attempt is separate evidence. This observation supplies no DirectRunner,
Stage B/C, Swift-product, speed or Quick qualification and no complete runtime dependency or
descendant-closure proof. The independent audit passed 38 checks after separately preserving a
mistaken expected-digest transcription and a command-length 206 failure during audit writing.
Neither changed evidence or reran the observation; the earlier source-writing OS error 5 remains
preserved as well.

### Seventh batch: Canvas winding, finite scanlines and stored Shape fill rules

The root candidate at HEAD `798cddb80434975acdc9f7761cfc0b6476c66488`, staged tree
`39ebce5b7d9a55cff4d195b5dfcebbaeccd5e914`, now preserves authored non-zero or
even-odd Canvas fill rules through solid and gradient operations, scene replay,
CPU coverage, cached D3D11 paths and legacy frame degradation. Stroke union,
draw order, blending and default non-zero behavior are unchanged. Conservative
topology checks admit supported simple even-odd shapes to existing GPU quad
routes and keep ambiguous, compound or unsupported geometry on the bounded path
route. Cache equality and hashing include the rule. This is not a new whole-window
software renderer, an antialiasing implementation, or complete Shape API parity.

Both scanline loops now have finite iteration counts and verify that advancing a
scanline actually advances its floating-point coordinate. Extreme coordinates
that cannot progress safely reject the entire promotion and use the existing
fallback. The old limits, clip arithmetic and comparison tolerances remain.
Separately, Shape scene and frame producers now carry their own stored
`clipFillStyle.eoFill`; an ancestor's style is not inherited into an unrelated
shape. Producer gaps involving erased/inset/trimmed shapes and Arc geometry
remain separate work. The 19-path candidate contains 81 new methods across five
test files: 53 Canvas/backend cases, 18 scanline cases and ten Shape cases.
All previously existing test files were preserved by the two intake checks.

Contracts passed before intake. Contracts and strict formatting on all sixteen
changed Swift files passed after intake with PS5 PID 16032, natural exit 0,
21.734 seconds. The receipt is
`artifacts/goal-seventh-shape-fillrule-intake-v1/root-static-v1/result.json`.
The exact root selection then ran fifteen stock, serial, nonsharded invocations
without skip-build. It recorded 286 distinct starts and 286 passed terminals:
255 XCTest and 31 Swift Testing methods, including all 81 additions and 205
preservation cases. No cases failed, skipped, duplicated, remained incomplete,
were missing or were unexpected. All fifteen retained PS5 exits were 0, and the
actual supervisor exit was 0 (closed session 98237, tool result `97dfc6`).
Elapsed time was 410.937 seconds, finishing at 22:40:44Z on 2026-08-28, within
the unchanged 1,800-second aggregate acceptance envelope. No finalization-overrun
marker was present. The overall exit receipt has SHA256
`98fd3ed5fecf318be9cc22890f3d8f4308fba9d75b05f3dddf54082d2de7bb8e`.

Independent raw parsing and generated-registration inspection agree with the
result. The compiled XCTest registry contains 5,331 unique methods (5,314 Core
and seventeen Portable); all 255 selected XCTest IDs appear once, with 179 async
wrappers and 76 synchronous references. The 134-method full Swift Testing count
is a source inventory, not a fresh executable listing or full run. The copied
test binary is 429,803,008 bytes, SHA256
`879696739123744443c095cc5fe232132f2ffe2853ededf605737d58d0d01703`.
The independent audit has SHA256
`2c981a6096858531307d00ba988870dc731ff290a7c611590902358db884f74a`;
its seal is `d003578ae25cd3d593b7ba17f274750fc2b88288aee5e7f5f81126cc6ec4f82e`.
The runner preserved all 778 tracked regular inputs, index bytes, HEAD and gitlink.
The auditor separately checked index/source registration and explicitly did not
rehash all 778 working files. Native test-process exits and complete descendant
closure were not independently observed. Metadata-only capture/receipt mistakes
are retained in the audit; none reran or changed the product tests.

A subsequent stock raw scene screenshot on this same source tree completed with
PS5 PID 49352 and actual tool exit 0 in 8.609 seconds. The 1280 by 720 dark
dashboard used 772 scene primitives, 182 frame commands and one layer. The parent
opened and inspected `artifacts/goal-seventh-canvas-demo-v1/demo-screenshot.png`,
SHA256 `b2a4b1a3b26716dfde1771f5845abbe6c7af5908f690dc916336aabdc4196508`.
Navigation, panels, text, gradient and chart remained aligned and legible, with no
obvious new corruption in this viewport. The Activity panel extends below its
bottom edge. This was not a previous-image pixel comparison or interaction test.
The displayed D3D11 badge and frame-time numbers are demo contents, not measured
hardware evidence. The separate visual-inspection record has SHA256
`81e705444918926bbcef25f6d7e53daab3b5edee288ec6bcd4c2eedf785f50d2`;
the historical render receipt's then-pending inspection field was not rewritten.

Root evidence copies and verified external binary references are retained in
`artifacts/goal-seventh-canvas-completion-intake-v1/intake.json`, SHA256
`eff36d0b85ecdf09c72de5706acf9f0829ce89c0e67b387adb77d9f0d121d587`.
The original owned Canvas failures and later owned 258-case pass remain separate
history; this root 286-case result does not retroactively change them. Fresh
root Quick/Full, whole-gallery comparison, native SwiftUI conformance, physical
hardware frame budgets, hosted release success and clean-machine qualification
remain outstanding. All nine original acceptance gates remain open.

### Seventh batch: qualification chronology and mounted observer source

The following owned-result records retain their original phase boundaries. In particular,
the earlier Progress build-only paragraph describes 171 cases as unrun at that build-only
boundary; the subsequent runtime entry records their later owned-tree pass. Neither is
current-root Progress qualification. Original sections 1 through 9 and all nine gates stay unchanged.

The thirteen integrated observer/preference paths give observations mounted owner/cell
identity and checked publication instead of shared callsite identity. Observer admission
uses snapshots and revision checks around authored identity operations and capture release,
so a reentrant callback cannot keep mutating an obsolete proposal or overlap an exclusive
dictionary mutation. Preference observation uses the same mounted lifetime and transaction
delivery. Six new files provide 76 tests; three existing preference facade bodies now use
managed hosts while retaining their behavioral assertions. The root strict lint of all ten
changed Swift files and architecture contracts passed before the focused run.

The legacy task(id:) adapter is still separate in this committed source. Ordinary State
hash reentry, ancestor preference refresh, partial lazy adoption, native scheduling and
complete SwiftUI behavior remain open; the focused result below does not close those gaps.

### Seventh batch: isolated lazy-list pass, Progress build and diagnostic controls

These 2026-08-28 records add detail without changing sections 1 through 9 or closing any
original completion gate. Earlier failures and ledger entries remain intact. Paths below are
relative to `C:/Users/maxw6/AppData/Local/Temp`; each result belongs to its frozen owned source,
not an integrated root, release, Full or Quick qualification.

The fourth dormant lazy-list Stage 2 attempt passed all 223 selected XCTest methods exactly once
across ten suites and fifteen serial stock shards, with no failures, skips, missing or extra
cases. Its tested tree is `7a4f65dfc94eb4c97b55903f457679741a9f9659` at base `1ce6b9a`; retained
PS5 PID 42476, runner and tool naturally returned 0 in 406.390 seconds. The separate eleven-line
fixture setup adds one ordinary frame before the original clean-mask assertions and checks that
factory, epoch, adoption, consumption and initial-row identity do not change. The original mask
and physical-overlap assertions remain. Both the previously failing clean-ancestor case and the
previously unrun final anchor case passed.

The result is
`swift-windowsui-lazy-list-clean-ancestor-1d6a97429bca40678e7f8357201ebc24/worktree/artifacts/lazy-list-stage2-clean-ancestor-outcome-cfbaa040e1334b829ebd3ea232aea1fc/OUTCOME.json`,
SHA256 `e8ca1e7186d75e0a796ce751c564b0644eb335ba7b917ba93cb6f32f93a0e11e`. Its sixty-member
manifest has SHA256 `2b71022f6b422cd2b4663bc43e3cb2732c2933119b170e30f2eded9bc310b96e`; the
final independent audit SHA256 is
`670e82b15914fc20c9ff32430c5fa86392dc5da204f317c53a00a767cfb9dd16`. All 754 source inputs and
index/helper pins were preserved. Endpoint checks do not prove continuous file immutability or
descendant closure. These headless fixtures may use DirectWrite/GDI; public
List/ForEach/LazyVStack construction remains unchanged. No public lazy-resource, performance,
visible-UI, Narrator or root-integration pass follows. The earlier failures are not combined
into this single successful attempt.

The ProgressViewStyle source at tree `0d565d5aa2d4104ec34129a1796fae83224a2313`, based on
`11d02b18`, completed one `swift build --build-tests --jobs 2`. Native Swift, PS5, retained
helper/controller and tool exits were 0. The helper ran for 592.578 seconds; final
preparation/build/evidence sealing totaled 1,382.879 seconds within the 1,800-second acceptance
budget, which is not an independent hard outer timeout. Passive analysis reconciled 5,122 unique
generated XCTest IDs, including all 171 selected methods exactly once: 38 new and 133 unchanged.
No test, registry listing, product, gallery or native UI was executed. All 171 runtime cases
remain unrun.

The build packet is `swift-windowsui-progress-style-plan-11d02b1-pze8l8rb/build-only-v1`. Its
thirty-nine-member `MANIFEST.json` has SHA256
`c7213d345669063dfddb858238f358314bc56063a3a7f8e674ac138b4a1d5b12`; `BUILD-QUALIFICATION.json`
has SHA256 `0c17d1af20d6fe1e650556d25ac6980b659077ff086329301a91b016dcfb308d`. The twelve
approved source paths, 99 source-packet members and protected inputs matched. Compiler/linker
warnings remain, including two new WeakMutability warnings. Build success does not establish
mounted style behavior, appearance, accessibility, native style precedence or API conformance.
Complete descendant retirement is unproven.

Separately, 23 pure SHA comparison controls passed in one pinned PS7 child: all expected typed
results matched, with zero failed controls and child/parent/tool exits 0. The child took 0.531
seconds and final evidence was preserved within the original thirty-second window. The controls
cover equal upper/lower/mixed-case digest text, malformed values and differing digests, plus
rejection when the prior exit, deadline or path condition is wrong. Twenty held pins and
fourteen proposal inputs matched. This is the comparator candidate with SHA256
`fa7101e8fb6ff1824e9ea63dbb9b67bf6ad1325bc0e32bc4ce91f1723736a76a`.

The standalone phase is `swift-windowsui-f9-sha-pure-runner-1787956620838/run-1787956620838`.
Its `actual-execution-receipt.json` has SHA256
`cc85496507f0e11c6ea28ebf0ccd5d1e32a651a3967768a52a8957718cfc43a8`; the six-member
`frozen-pure-phase-manifest.json` has SHA256
`692f57151e0af8bc8b305df023d24d2d86f6a865475f4e0b87a1bb2e17bc07fa`. No controller, supervisor,
watchdog, F9 workload, validator or compiler ran. The old P6 native attempt remains
FAILED_CONTROLLER_GATE, and the historical F9 compile audit still records compiler 0/collector
1. Pure comparison results repair neither record.

The CI evidence investigation completed 21 observations in each of two serial processes: two
AST, three binding and sixteen object-transport observations per engine. PS5 PID 33628 and PS7
PID 37484 naturally returned 0, as did the controller/tool; the observed tool wall time was
3.142 seconds. These are 21 plus 21 collected observations, not behavioral passes. PS5 preserved
identity in all sixteen transport cases; PS7 preserved seven and wrapped scalar values in nine
mock/forwarding routes. The reports also expose the FunctionDefinitionAst/Body guard assumption
and the fixture's Path-switch/name collision. Authored observations are not a replay of the
original failed objects or exceptions, nor execution of the full fixture suite.

The packet is `swift-windowsui-test-evidence-observation-prep-472201f407cc4e59a05932e0c0322c60`.
Its forty-six-member `MANIFEST.json` has SHA256
`53c268fc067cb0535735ea68ec310498eab5acf7642f5d57e5c86a15db1f7451`;
`observation-v1-assessment.json` has SHA256
`8fdb2e05577a8421e3851349094c9fb5b20d615354e0af8c5121facfb3a50336`. This copied snapshot has no
new Git tree: it derives from the unqualified six-file candidate at `a7c530b0`, with only the
separately recorded fixture-classifier increment. Its 134-case full suite remains unrun. All 357
original failed-packet members and selected old/current pins remained unchanged; metadata-only
sealing failures remain separate. No corrected CI behavior, native stdout transport, compiler
identity, process-tree closure, hosted test count or release gate is qualified by these probes.

### Seventh batch: path-guard functional controls

One owned invocation passed ten controls and 204 assertions, with 46 baseline/proposed
guard calls plus two baseline ownership checks, zero failures and no unrun cases.
Parent, child and tool exits were all 0. The child took 1.091 seconds within its
43-second cap; the observed tool boundary was 3.889 seconds within the 60-second phase
with its 15-second reserve. Later audits are outside that interval; no closing QPC tick was saved.

Execution used earlier conditional functional authority, frozen pins and two agent
prelaunch source reviews. A truncated command retrieval was rejected and reread before
binding. The parent's final output-root/template review was POST-execution: later full
file reads recovered its truncated diff and found no blocker. It was not prelaunch review.

The immutable 36-member packet is
`C:/Users/maxw6/AppData/Local/Temp/swift-windowsui-path-guard-audit-c99cd95487e84a8aa09d1f7b5e5e246e/AUDIT-SEAL.json`,
SHA256 `dca1b01a307464f7366cde3fab7e1ee291946a415540a6e1827e89ff90b328ef`.
All 24 before/after pins and sixteen regular-file copies matched; the two original
junctions were retained, with metadata recorded rather than junction copies or traversal.

A later independent read-only audit request hit OS error 5 before its tool host existed;
no audit code or control ran in that failed request. The audit locates the exact request
and full error in the original task transcript; it claims no standalone byte-identical
copy. Subsequent bounded reads used the same ordinary route, without escalation or a control rerun.
This did not exercise guard access-denial behavior. No old 4,453-file walk, Stage A/B/C,
Swift-product, speed or Quick qualification follows. Earlier Stage A remains failed with 61 unrun cases;
the historical after-census stays unproven and all nine original completion gates stay open.

### Seventh batch: later owned Progress runtime qualification

After the earlier build-only phase, one separately approved run passed all 171 selected
XCTest IDs once: 38 new cases and 133 unchanged regressions. Seven serial stock NONSharded
invocations produced 171 starts and 171 passes, no failed, skipped or unrun selected cases,
and seven zero-test Swift Testing trailers. All seven retained direct PS5 exits and the
natural outer tool exit were 0; independent native XCTest OS exits remain unknown.

This qualifies only owned base `11d02b18e587640790f4d8d3ce3273cac6c90d58`,
tree `0d565d5aa2d4104ec34129a1796fae83224a2313`, not the newer root.
The final 50-member packet is
`C:/Users/maxw6/AppData/Local/Temp/swift-windowsui-progress-style-plan-11d02b1-pze8l8rb/runtime-run-v1/MANIFEST.json`,
SHA256 `64978d7daed5c4d39893957bff8fbae846873ffb5d99a843ec2fcb00635268eb`.
The independent audit reconciled all 5,122 source/registry IDs, 28 capture copies and 160
physical pins; those counts are not extra executed cases. Source, index and binary stayed unchanged.

The runner recorded 61.531 seconds before final serialization; the final phase including
preparation, audit and seal took 1,107.543 seconds within the 1,800-second acceptance budget,
without an independent hard outer deadline. Permitted headless font/UIA work does not prove
UIA delivery, descendant closure, native style parity or generic/class/enum/nonfinite conformance.
No full-suite, root or original goal gate is qualified. Prior build-only entries and their
warnings remain historical records; this later selected runtime pass does not rewrite them.

### Seventh batch: observer/preference integration and root run

The integrated observer/preference changes now have a root-specific focused result on
HEAD `228b12b955e6a7d4d34c8503cf71211a17cc609a`, staged tree
`492334b958cb280111ade3fc9802af0e3fad3352`. All 825 selected XCTest IDs started and
passed once across 35 serial stock NONSharded invocations, with no failed, skipped,
duplicate or unrun selected cases. These comprise the earlier 689-ID selection plus
136 additional regressions; the 76 new methods in six observer/preference files are
included within the 825, leaving 749 other cases. They are not an additional population.

All 35 retained direct PS5 exits were 0. The parent separately observed natural outer
closure at exit 0 in completion `0935a5`; the copied capture records that observation,
not an independently retained supervisor handle. The runner's 496.610-second reading
was after preservation checks and before final receipt serialization. The overrun marker
was absent at capture. Native XCTest OS exits and descendant closure remain unproven.

The evidence is frozen under
`C:/Users/maxw6/AppData/Local/Temp/swift-windowsui-observer825-outcome-audit-jfvt5p9g`.
Its final `SEAL.json` is SHA256 `c0c28528227ae1145f28abd2524b48e9b9e2b5c227e0ba94f7898946c6d0c9b8`.
The copied source/exit receipts and physical index agree with the tested identity;
the runner reports all 786 source inputs and ten tool pins unchanged. The independent
audit reconciles 13 capture copies and all 5,407 generated XCTest IDs. Only 825 ran;
134 Swift Testing declarations remain source-only,
with 35 actual zero-test Swift Testing envelopes. The independent raw and compiled
receipts are pinned in the accompanying evidence map; no changing root file was read
to prepare this entry. Earlier failures and owned-tree results retain their identities.
The metadata-only inventory-role refusal is retained; correcting its links changed no tests.

### Seventh batch: P7 native supervisor compile-only success

A separate P7 phase compiled and linked the native supervisor successfully: both retained
direct compiler/linker exits, the collector and the outer tool returned 0. The final
receipt was preserved within the original 600-second phase; no built supervisor was run.
The 344,576-byte executable has SHA256
`83d1005c84de27c01e847317558279f44b5d0cfccad150f152eff9a36a68c3bf`.

The 30-member compile packet is
`C:/Users/maxw6/AppData/Local/Temp/swift-windowsui-native-supervisor-prototype-1787957738753/compile-f9-supervisor-1787960226013/frozen-compile-phase-manifest.json`,
SHA256 `edd90d4b458b9bedd21b236fd82d1c422c1798b905b2057f38b276fb27c33c8c`.
The final tool receipt is separately pinned. Its current 147 source files, nine collector
files, 333 headers and nine possible libraries were preserved; the 410 include records
matched preflight. These boundary checks do not prove selected library origins or ABI.

The optional linker MainModule observation was unavailable for an unknown reason.
No watchdog copy, F9 payload staging, native runtime or candidate DLL load occurred.
The P6 controller/runtime failure and historical F9 compiler-0/collector-1 failure remain
failed; this compile result does not repair them. All nine original gates remain open.
The earlier Progress build-only/171-unrun entry remains correct for its phase; the later
owned 171-pass entry adds runtime evidence without rewriting that historical boundary.

Parent evidence copies are retained under artifacts/goal-seventh-owned-results-ledger-intake-v2,
artifacts/goal-seventh-observer-ledger-primary-intake-v1 and
artifacts/goal-seventh-observer-final-ledger-intake-v1. The closed observer result also has
artifacts/goal-seventh-observer-completion-intake-v1/intake.json, SHA256
669a11603175b3cb53a6ad5d4478f6d7308aa0c009a3c4350a8af5a5666ddffd: 137 mandatory files
were verified and 136 copied; the sealed test PE was verified externally rather than copied again.
All 786 tracked source files and the physical index were freshly verified unchanged before
this ledger addition. This is endpoint preservation, not continuous monitoring or native descendant proof.

### Seventh batch: shape paint producers and 330 root regression cases

Shape paint now reaches TrimmedShape's own leaf and the recognized paint owner behind
erased, inset and transform wrappers. A failed owner lookup does not fall back to painting
the wrapper root. Fill, stroke, fill-rule and gradient descriptors travel together;
rounded inset owners retain their already adjusted absolute radius without a second inset.
Passive delegation and the existing typed component/State installation path remain intact.
Arc keeps its construction paint during layout, and geometry updates target the live
retained node through a sparse package callback. Legacy layout runs first; reconciliation
copies or clears the callback, and replacement uses the existing publish-before-release rule.

The six changed paths are `Sources/WinSwiftUI/Views.swift`,
`Sources/SwiftWindowsUI/Runtime.swift`, `Sources/SwiftWindowsUI/ComponentHost.swift`,
`Tests/SwiftWindowsCoreLogicTests/ShapePaintProducerTests.swift`,
`docs/CompatibilityStatus.md` and `docs/GPURenderingPipeline.md`.
The source packet adds only the 16-method producer test file; all 466 prior Tests files
remain unchanged. Its original source-only/330-unrun wording remains a pre-run record.

The integrated run used root HEAD `a487c70aaa1e0949a98728c74306f2f0f277d299`,
staged tree `e3d48d41b4fac3130927a740d431d65144a56c77`, with index SHA256
`09424da2f599794d436e81a0d3cfbb9170c18872670ec129da58f5b1437cb273`.
The copied static receipt `76fad08a0d33d550cc0741bff4802ee18f1cfddbe4040b758b04b05c818a27b7`
records contracts and strict lint for the four changed Swift files at actual exit 0,
with no SwiftPM invocation and all 787 inputs unchanged.

The later run passed exactly 330 cases once: 299 XCTest and 31 Swift Testing, comprising
the preserved prior 286 cases, 16 new producer cases and 28 existing lifecycle controls.
All 18 serial stock NONSharded calls and retained direct PS5 exits were 0, with no failed,
skipped, missing, duplicate or incomplete selected case. The parent observed natural outer
closure at exit 0 in `55de31`; no finalization-overrun marker was present at capture.
The 440.265-second reading was after preservation checks and before final serialization,
not a separate measurement of the complete process or audit lifetime.

The independent raw and compiled evidence is retained under
`C:/Users/maxw6/AppData/Local/Temp/swift-windowsui-shape330-outcome-audit-8oj7mvl9`.
The final `SEAL.json` is SHA256 `dc18776c51bc7974aa7e3ef9f6cc1cb2edacb562ecc1684e57f9092c64facaef`.
It reconciles all 5,423 generated XCTest IDs with source: 5,071 async and 352 sync.
The selected 299 XCTest cases comprise 223 async and 76 sync; the other 31 actual passes
are Swift Testing. The full 134 Swift Testing source declarations do not have a full
compiled listing or full-run qualification. The runner records all 787 source inputs,
ten tools and index preserved; the auditor independently checks the 13 closed copies.
Native test OS exits and descendant closure remain unknown.

Partial trims and trim.inset geometry, repeated InsetShape.inset paint loss, Arc bounds
double-scaling, first-stop shape gradients and omitted legacy dash/phase remain unresolved.
The result does not resolve antialiasing, general clipShape/fill rules, custom multi-node
ownership, transformed path(in:), exact strokeBorder layering or native shape parity.
The later stock raw retained-runtime demo snapshot also completed: PS5 PID 44132 and
outer tool `0922b6` returned 0, with all 787 source inputs and index preserved. Its
8.797-second observation includes preflight and precedes final serialization.
The 1,280-by-720 dark dashboard PNG and 32-bit BMP match the prior Canvas image bytes
exactly according to the separate parent inspection. Header, navigation, cards and chart
remain intact; lower Activity content continues below the fixed viewport as before.
The result and inspection are retained in `artifacts/goal-seventh-shape-producers-demo-v1`.
This single retained CPU scene is not Shape-specific pixel, gallery, hardware or native
parity evidence; its D3D11 badge does not prove the rendering backend. Older Full/Quick
results remain historical and do not qualify this tree.
All nine original completion gates remain unchanged and open.

The parent completion intake, `artifacts/goal-seventh-shape330-completion-intake-v1/intake.json`,
verified 107 mandatory files and copied 106; the separately sealed test image was
verified in place. All 787 source files and the physical index remained unchanged.
Its SHA256 is `10a57d3acbe7c6e0fe87c0938d91bad784a32456e125d7b13d6accf9000c5dd0`.
The earlier parent intake SHA transcription refusal and two audit inventory-reader
refusals remain recorded as metadata preparation failures. Their corrections did
not change product source or consume another test attempt.

### Seventh batch: P7 watchdog/catalog preparation only

P7 copied the existing 114,176-byte watchdog unchanged and created the 692-byte observer
catalog with the three approved substitutions. The copy, seal and final receipt-write
tool exits were 0. The owner's final tool observation reports 1.991 seconds within the
original 60-second phase; the sealed receipt's earlier checkpoint is 1.454 seconds.
These are distinct observations. The final 1.991-second report is retained in the tool
transcript, not a second post-write value inside the earlier sealed receipt.

The eight-member preparation manifest is
`C:/Users/maxw6/AppData/Local/Temp/swift-windowsui-native-supervisor-prototype-1787957738753/copy-watchdog-catalog-1787963533571/frozen-copy-catalog-preparation-manifest.json`,
SHA256 `8fa2d250bcf1029ca078d1c727cd39c34ab3ca9df67fa5a00825412a2500f612`.
Preservation records account for 741 prior inputs plus the two outputs. No F9 payload
staging, native executable, DLL load, validator invocation or runtime authority follows.
Earlier P6/F9 failures remain unchanged.

### Seventh batch: custom ProgressViewStyle and 171 root cases

ProgressViewStyle is now a main-actor protocol with a typed ViewBuilder body and
configuration labels. Supported struct styles use the normal mounted dynamic-property
and view-body path. Each consuming control keeps its own state ownership; replacing
its style type, removing it, or closing its host retires that ownership. Configuration
delegates preserve the original value/total and distinct label/current-value identities.
Consuming one style installation exposes the remaining inherited chain, without
sharing mounted state between sibling controls or implicitly calling itself again.

The former concrete profile is named ProgressViewStyleProfile. Its built-in values
and Windows environment compatibility surface remain available; an explicit profile
assignment clears inherited custom installations even when the profile value is the
same. The original built-in rendering path is preserved. Explicit annotations of the
old concrete ProgressViewStyle type require the documented migration.

The source intake applied exactly twelve paths: three production files, three new
test files and six documentation files. All 467 prior Tests files stayed unchanged;
the new suites contain 38 methods. The integrated test source was HEAD
`d5ef2f7352a1d1ff68a1458ab6fa11fbebb110ea`, staged tree
`05759e76c9b0f2bb3c0675efc6a690ba04a9dece`, with physical index SHA256
`a3282e42fa5c3daf0fcebfb5209a1f54b6a4562f3ab5a0e2970846c71aa8912b`.
Fresh ContractsOnly checks before and after intake and strict lint for all six changed
Swift files returned zero. No earlier owned-tree pass was substituted for this run.

One integrated run passed exactly 171 XCTest cases once: 38 new and 133 preserved,
168 async and three sync. All seven serial stock NONSharded calls returned direct PS5
exit zero, with seven successful zero-test Swift Testing envelopes. There were no
failed, skipped, extra, duplicate, missing or unfinished selected cases. The parent
observed actual supervisor closure at exit zero in session 45834/tool `f088d7`, and
the one approved closed capture found no finalization-overrun marker. The recorded
365.984 seconds precedes final receipt serialization; it is not a performance gate.

Independent copied discovery reconciles all 5,461 generated XCTest IDs and expected
async flags: 5,444 CoreLogic plus 17 Portable, across 385 class tables, with 5,109 async
and 352 sync methods. All seven filters select exactly their frozen IDs. The other
5,290 XCTest cases and all 134 authored Swift Testing methods did not run in this
selection. Generated discovery is not evidence that those unselected tests passed.

The final audit seal is SHA256
`d8efbdd79ceb6fe6f81c8465acce34972858087543274fe32555dcbf249cc92e`.
The parent copied 79 of 80 verified evidence files into
`artifacts/goal-seventh-progress171-completion-intake-v1`; the separately sealed test
image was verified in place. Its intake receipt is SHA256
`e0109c647bfb200cfcc995385d1a52b8093e68f8cb2240e3a9d2f4207b0e63f7`.
Fresh parent sweeps verified all 792 regular source files and the physical index
unchanged before and after the intake. Native test OS exits, descendant closure,
continuous source monitoring and a complete loaded-tool identity remain unproved.

A later stock raw retained-runtime dashboard snapshot also passed: direct PS5 PID
46892 and outer tool `b64aa3` returned zero, with all 792 source files and index
preserved. Its 8.844-second observation includes preflight and precedes serialization.
The dark 1280-by-720 PNG and raw BMP are byte-identical to the preceding Shape capture;
parent inspection found the header, navigation, cards and chart intact, with the same
lower Activity clipping at the fixed viewport. Evidence and inspection are retained
in `artifacts/goal-seventh-progress-style-demo-v1`. This single CPU scene is not a
dedicated custom-style pixel, whole-gallery, D3D11, hardware or native-parity result.

Class/enum style installation, native generic ProgressView syntax, constructor and
isolation parity, nonfinite primitive inputs, native chained-style behavior, timer
ticking and full animation remain open. This focused result does not qualify the
current tree for Full, Quick, hosted CI or release, and does not close any original gate.

After that validation, only four Progress documentation status passages were
refreshed to report the observed run and retain the native/Full limitations.
The resulting documentation tree is `ab8f41e8f408a1a0e32914139bff62c5b924fd44`;
all 788 other regular files, including every production and test file, remain
identical to the tested tree. The documentation intake is retained under
`artifacts/goal-seventh-progress-doc-status-intake-v1`, with receipt SHA256
`1d178975b03e519331145e99e5573845db80d8d0c8d76a541f6f386fc95981bb`.

### Seventh batch: owned Task95 failure, correction and focused pass

The first Task95 attempt stopped on two helper compiler diagnostics after a reported
168.937 seconds, with zero test starts and all 95 cases unrun. That failure and its
partial build remain preserved. A separate candidate changed only two private helpers
to snapshot `self` in `let probe`, retaining the outer weak capture and synchronous
actor check. All 51 new test bodies and the same 95 selected IDs remained unchanged.
The failed build was not reused.

Fresh owned tree `7d34203e62d412af7d1ef803f949412c2de19b63` then passed all 95 cases
once across six stock calls, with six direct PS5 zeros and six zero-test Swift Testing
envelopes. Actual closure was `0fc320`, session 33520, exit 0; the reported interval was
435.609 seconds. Independent review reconciled all 5,458 source/compiled XCTest IDs,
but only 95 ran. The 40-member pass packet is not root integration or Full/native parity.
Unmounted ID tasks, lazy-row activity and native scheduling remain limited; native test
OS exits and descendant closure remain unknown.

### Seventh batch: document1287 failure and source-only fixture alignment

The one owned `e2c47c747a207dc6907d80eaefc9dfafb61e2968` attempt failed at call 45:
771 starts, 768 passes, three failed cases and 516 unrun. Calls 1-44 passed; calls 46-63
did not run. All 94 new cases and the prior 571-case selection passed within that prefix;
these overlapping populations do not make the complete 1,287-case attempt pass.
Four assertion diagnostics came from three older text-input fixtures. The supervisor
closed at exit 1 in session 96306/`29c5d2`; the independent audit confirms the failure.

The 96-member alignment packet freezes `c6151ed3d3c14a6a4ea4013a00ddc66da03c2178`.
It changes exactly those three fixture bodies to versions already present on root since
`1ce6b9a0fa478fc5e636a146073b58dfd6ad9201`; it changes no production behavior or
selected IDs. Contracts and strict lint passed; the source-only freeze adds no compiled
or runtime qualification. Neither source diagnosis nor the passing prefix qualifies a complete native
document workflow or replaces any earlier failed run.

### Seventh batch: one exploratory debugged P7 F9 pass

One controlled P7 F9 experiment passed its fixed WM_CHAR sequence, task-thread checks,
quit code 73 and 17 application-local module origins at three checkpoints. Recorded
native, controller, validator and outer-tool exits were 0. Final receipt preservation
was reported at 91.6861809 seconds within the original 600-second phase. That final tool
observation is separate from the 91.1517672-second checkpoint retained with the 48-member packet.

This was a debugger-attached experiment, not an ordinary launch or a native product,
general ABI, physical-key translation or general scheduling qualification. Independent
review was reported clear in a message; no separate durable review receipt is claimed.
The older P6 runtime failure and historical F9 compiler/collector failure remain failed.

### Seventh batch: preservation-only timing observation

One preservation-only attempt completed naturally with child, parent and tool exits 0.
The outside interval was 33.746 seconds; the single preservation call itself took
27.9070594 seconds. Its snapshot covered 374 fixed rows, seven roots, 4,453 regular
files, two junctions and 2,408 directories; the before/after 41 input pins matched.
The current snapshot matched its saved reference, without another census attempt.

Only this subset fit its separate 60-second experiment. Original Stage A's 300-second
total and 60-second finalization reserve remain unchanged and unqualified as a whole.
The failed Stage A still has 61 unrun cases and an unresolved historical 4,453-file
after-checkpoint gap. No real DirectRunner, Swift product, complete Stage A or Quick
speed claim follows. The three later metadata-audit incidents remain preserved.
These entries leave original sections 1-9 and all nine completion gates unchanged and open.

The four owned follow-up records above are backed by 27 verified metadata
references copied into `artifacts/goal-seventh-progress-followup-ledger-intake-v1`.
Its intake receipt is SHA256
`1a511b9f469539d7e2c83544945d5f58c2dc77770bc1cce0ff3d393fbcaf4cae`.
That intake verifies the named metadata, not a new transitive replay of old
source, raw logs or binaries, and it does not transfer owned results to root.


### 2026-08-29: Owned validation evidence frozen at 04:24 UTC

All nine original completion gates remain open. These records add evidence to the
existing ledger without replacing failures, treating source edits as execution,
or applying historical Full/Quick results to a different source composition.

**Grid170: the first compile failure remains separate from the corrected pass.**
The first attempt on owned commit fbe62c83/tree e0ad5596 closed at tool 730da8
(session 25145), exit 1. Its first PS5 child exited 1 before any test started;
all 170 selections were unrun and the remaining twelve filters never launched.
The compiler resolved `gridColumnAlignment` as an instance property instead of
the private global helper. Its 50.109 seconds is runner aggregate before final
receipt serialization, not an independently timed PS5 or native-test duration.

A fresh owned commit 73c23ad5/tree f1bf6590 changed only the helper name and sole
call to `gridTrackCrossAlignment` beyond the reviewed Grid source. One corrected
run closed at 9bb323/session 90968, exit 0: thirteen PS5 exits 0, 170 distinct
starts and passes, no failures or skips. The 36 new cases and 134 preservation
cases include two explicit migrations; the 134 are not all untouched fixtures.
The independent final audit reconciles 5,459 generated XCTest IDs and every flag,
but only the selected 170 async cases ran; all thirteen Swift Testing runs were empty.

The sealed 155-member result and 59-member independent audit retain the old
failure and metadata incidents. The passing runner aggregate was 445.359 seconds
before final serialization, with no timeout or overrun. Recorded source/index,
tools and effects pins were preserved. Grid remains partial for spacing, spans,
compression/priority, RTL and guides; future Stage2 composition and native parity
are not qualified. Primary records: `grid-pass-result`, `grid-independent-reconciliation`.

**Document1287: the corrected owned run now has a sealed independent audit.**
One run against HEAD 26144ba3/tree c6151ed3 closed at 7d8e78/session 60884,
exit 0. All 63 stock calls had PS5 exit 0 and explicit empty Swift Testing runs.
The audit confirms 1,287 distinct starts and passes: 94 new plus 1,193 preservation
cases across 37 complete classes, with no failed, skipped, duplicate, unexpected,
unclosed or unrun cases. The earlier raw-capture pending label is preserved as
a historical boundary; the later sealed audit supplies the focused qualification.

The outer observation was 377.303 seconds; the runner receipt was 364.610 seconds.
These are different observation points. Complete child logs total 573,717 bytes;
the truncated supervisor progress display is not a complete console archive.
Captured source/tool/index associations remained unchanged. The two build graphs
differed only in the verified 40/20 quoted jobs tokens, not an agent jobs override.
The generated census is 5,085 XCTest IDs; it is not a full-suite execution.

The old e2c47 attempt remains 771 starts, 768 passes, three failures and 516 unrun.
The c615 pass does not qualify a root overlay, a complete visible document workflow,
native TranslateMessage behavior, loaded-image origin or descendant closure.
Primary records: `doc-owner-outcome`, `doc-final-audit`, and `doc-final-audit-seal`.

**Arc342: all cases completed, but three methods failed exact pixel assertions.**
Owned HEAD 7478b0c7/tree ce7cf23a closed at e20d02/session 56462, exit 1.
All 342 selected IDs started and terminated once: 339 passed (308 XCTest and
31 Swift Testing), three XCTest methods failed, and none were skipped or unrun.
Calls 1–18 passed the prior 330 cases; call 19 passed nine of twelve Arc methods.
The three failed methods produced nine assertions of BGRA [255,0,0,247] rather
than [255,0,0,255]. There was no tolerance or oracle change. The independent
audit retains this failed result and the complete 5,435-ID generated census.
The runner aggregate was 483.875 seconds, without timeout or finalization overrun.

The separate source successor ce866d8a/tree 4a4ed0d1 adds the missing bevel
connector between CPU stroke segment bodies; the existing 0.1 threshold still
governs only additional exterior round/miter geometry. The gap attribution is
source analysis and arithmetic, not instrumented evidence of which raster failed.
Four paths changed, including eight new tests; all twelve Arc method bodies and
the prior test files remain unchanged. The 51-member source packet is sealed,
but its prospective 350-case selection has not compiled or run. General native,
antialiasing, trim, gradient, clipping and unjoined Stage2 oracle limits remain.
Primary records: `arc-failure-reconciliation`, `arc-failure-independent-review`,
and `arc-successor-handoff`; the successor does not replace the failed run.

**Date161: compilation failed; the later one-assertion correction is source-only.**
HEAD 2be4dc20/tree 9464f7ca closed at 096403/session 93561, exit 1 after
163.25 seconds. The first PS5 child exited naturally with code 1; partitions
2–16 never launched. One private-member diagnostic for `hoveredNode` at
GraphicalDatePickerControlTests.swift:461:42 appeared in twelve compiler jobs.
There were zero case, suite or Swift Testing events: all 161 cases, including
35 new and 126 preserved, were unrun. No generated registry file was present.
The failure, raw outputs and partial build remain preserved, without a retry.

Fresh commit 001f3b5b/tree 4d64fcb8 changes only that assertion to the existing
`button.isHovered` getter. No production API or helper visibility was widened.
The sealed 112-member source packet and independent source review preserve the
other 791 source files, all 160 other selected method bodies and all 161 IDs.
Contracts and strict formatting passed, but this successor has not compiled or run.
Its 18 fresh hosts and 528 day-center checks are authored counts, not observed
calls; the assertion is justified only for this fixture without hover callbacks.
Clock, native-pixel, roving-focus and generic API parity remain unqualified.
Primary records: `date-failure`, `date-successor-final`, `date-successor-review-manifest`.

**CI235 synthetic pair: actual failure despite PS7's structured case results.**
The pinned eleven-file source is a snapshot, not a new Git checkout; its historic
HEAD/index copies do not establish a current checkout identity. Tool 65c31d
completed with exit 1 and no yielded session in 7.1988969 seconds; the outer
controller returned 1 at 7,020 ms, separately from its 6,455 ms launcher receipt.
PS5 PID 54300 exited naturally with 1 during setup: zero cases and assertions;
none of its 235 expected bodies executed. PS7 PID 35720 exited naturally with 0,
and its structured result reports 235 cases and 720 assertions passed.

The launcher nevertheless records PS7 stdout as null with
`stdout-file-pin-unavailable`. A later file hash does not repair that original
capture failure or establish EOF. The pair remains failed and unqualified.
At this addition's freeze, the whole-packet handoff/final audit is still pending;
the pinned raw snapshot and actual closure records support only the stated facts.
No retry, source successor execution, Swift/native test or hosted CI run is implied.
Primary records: `ci-raw-snapshot`, `ci-tool-observation`, `ci-launcher-receipt`
and the separate `ci-ps5-result` / `ci-ps7-result` records.

**Shared message-loop probe: direct compile/link success only.**
Tool 75d385, the collector and direct compiler DWORD all returned 0 with normal
EOF and no intervention; the sealed manifest has 60 members. The saved seal
checkpoint is 254.0632182 seconds. The owner's later tool-message observation
at 04:11:16.9185780Z is a separate 285.4001384-second point from the original
04:06:31.5184396Z authority, within its unchanged 600 seconds and 120-second reserve.
The primary metadata records complete before/after input checks. No probe,
mock test, validator or native runtime ran; passive origin review remains pending.
Ordinary App behavior, ABI, IME, host DLL origins and descendants are not qualified.
Older F9/P6 failures and the separate P7 debugged experiment remain unchanged.
Primary records: `loop-compile-summary`, `loop-compile-outcome`, `loop-compile-final-tool`.

The companion map pins metadata paths, bytes and hashes. This drafting pass read
and hashed metadata only: no source/binary/transitive replay, workloads or root edits.
These owned results do not qualify a later root composition or close any of the nine gates.

Local evidence map: [snapshot 0424](artifacts/goal-seventh-owned-ledger-intake-v1/0424/primary-evidence.json). The intake retains the referenced metadata as data; it does not repeat the underlying workloads.


### 2026-08-29: Owned validation evidence frozen at 04:57 UTC

This addition follows the 04:24 ledger freeze; it does not rewrite that record.
All nine original completion gates remain open with unchanged requirements.
Each result below belongs to its stated owned source and validation scope.

**CI235: the final packet is sealed, and the original pair is still failed.**
The 385-file packet now preserves 2,554,400 bytes, the rechecked 339 raw files,
and the completed independent-audit copies. This resolves the earlier pending
packet boundary, not the failed result. Tool 65c31d still exited 1; PS5 executed
zero cases during its setup failure, while PS7 reported 235 cases and 720 assertions.
PS7's null stdout pin and `stdout-file-pin-unavailable` remain disqualifying.
The later stdout hash neither repairs that capture nor proves EOF. No pair retry,
source repair, root intake or hosted CI success follows from the final seal.
Primary records: `ci235-final-manifest` and `ci235-final-handoff`.

**AST-only pair: the proposed newline mismatch was not observed.**
The separate probe closed at a9f9ee with exit 0 and no yielded session.
Tool time was 1.4925128 seconds; the collector recorded 1,390 ms.
PS5 PID 14296 and PS7 PID 58604 both exited naturally with 0.
In both engines, the expected literal and actual writer extent were ordinally
equal: each operand was 151 UTF-8 bytes with four CRLF pairs and no lone CR/LF.
Both input parses were clean; no fixture, helper or project definition was invoked.

The conditional 239-case/728-assertion newline correction was withdrawn without
implementation or execution. The original PS5 setup exception remains unknown;
this observation is not a trace of that historical exception or a CI235 pass.
The 33-file probe packet preserves the separate metadata timestamp-review stop
and its later completion; neither was an observer rerun. Subsequent probe plans
are outside this addition. Primary records: `ast-pair-handoff`, `ast-pair-tool`,
`ast-pair-ps5`, `ast-pair-ps7`, and `ast-pair-post-audit`.

**Joined Task95: one focused pass on the held 56706 composition.**
Owned HEAD d5ef2f73/tree 56706c93 closed at 2c275e/session 62789 with exit 0.
All six stock calls had PS5 exit 0; the independent raw audit confirms exactly
95 starts and passing terminals, with no failed, skipped, missing, extra or
duplicate IDs. The cases are 51 new task cases and 44 preservation cases.
The runner aggregate was 418.859 seconds, with no overrun or retry.
All six Swift Testing runs were empty; omitted printed suite-count fields were
kept distinct from the independently checked absence of named suite events.

The sealed 78-member capsule also contains independent reconciliation of all
5,512 generated XCTest IDs and the selected 95 async adapters. The 5,417 other
registrations and 134 authored Swift Testing methods were not run.
Recorded preservation covers 797 source bindings, 806 physical pins and the
private index. The first zero-test compiler failure and separate 7d34203 pass
remain unchanged. This does not qualify the larger preservation union, unmanaged
task ownership, native scheduling equivalence, lazy rows, or a root integration.
Primary records: `task95-joined-final-result`, `task95-joined-raw-audit`,
`task95-joined-registry-audit`, and `task95-joined-seal`.

**Lazy1968: one existing preservation case failed after the first 235 passed.**
On owned HEAD 87d88f57/tree 4964de1a, the parent observed 6761f3/session 37826
close with exit 1. The sealed independent audit verifies 260 distinct starts
and terminals: 259 passes, one failed case and two assertion headers, with no skips.
The first sixteen calls passed all 235 Stage2 cases; call 17 ran all 25 cases
and failed `ComponentHostTests.testReloadReusesNodeWithFreshStateAndHandlers`.
Caret 1 remained instead of 4, and insertion-point/upstream selection remained
instead of range 1..<3/downstream. The remaining 83 calls were not invoked:
1,708 cases are unrun, comprising 1,677 XCTest and all 31 selected Swift Testing cases.

The recorded runner aggregate was 553.547 seconds before final serialization.
Direct-child receipts show no timeout or termination. The generated audit matches
5,603 IDs and the 1,937 selected XCTest references; it is not a 1,968-case pass.
Source actor attributes and generated array attributes remain separate evidence.
The audit records the tool closure as owner-reported; it did not independently
read the actual tool object. The full historical owner archive is still pending,
so the stable run prefix is not described here as a finalized archive.

Source comparison found the fixture byte-identical to root comparison commit
46d22ff, while the extracted Host path omitted the raw caret/selection copies
for an incoming node without a controller. The sealed 58e994 restoration proposal
adds that fallback after the existing validity checks, without changing assertions.
It remains a source-only proposal, not an implemented or tested repair.
Public lazy construction, native parity and the full preservation union remain open.
Primary records: `lazy1968-independent-review`, `lazy1968-independent-seal`,
`lazy1968-proposal-note`, and `lazy1968-proposal-source-pins`.

**FilePreview392: one accepted build, with all runtime cases still unrun.**
Owned HEAD 11d02b18/tree 22857650 closed at 90cfe6/session 89825 with exit 0.
The single stock `build --build-tests --package-path` used default jobs.
The retained PS5 exit and fresh propagated Swift exit were 0; an independently
retained native Swift OS exit is unknown. The owner reports the build-log time
as 414.60 seconds, distinct from 420.4023417 seconds for PS5 and the supervisor's
421.0004914 seconds before its outcome write. No timeout, cap or overrun occurred.

The build verification records all 790 source files, the index and eleven tool
pins unchanged. Its preparation seals are not runtime or discovery seals.
All 392 runtime cases remain unrun. Passive registration/image qualification
is still pending; no final registry audit, capture seal or PE hash is claimed.
No test listing, test product, native fixture or visible-preview workflow ran.
Primary records: `filepreview-build-verification`, `filepreview-tool-closed`,
and `filepreview-build-exit`.

**Arc350: the later CPU connector run is now independently sealed as passing.**
Owned commit ce866d8a/tree 4a4ed0d1 closed at a6dd56/session 83135 with exit 0.
All twenty stock PS5 calls returned 0. The audit confirms 350 unique starts and
passing terminals, or 700 events: 319 XCTest plus 31 Swift Testing cases.
All twelve unchanged Arc cases passed, including the three prior failures;
all eight new connector cases also passed without changing thresholds or samples.
The runner recorded 489.359 seconds, with no timeout, overrun, skip or retry.

The 107-member result reconciles all 5,443 generated XCTest IDs and records
789 source files, the index and ten tool pins preserved. Registration is not
full-suite execution. The old 342-case result remains 339 passes, three failures
and nine alpha-247 assertions; its source-only preparation records are not rewritten.
This pass does not prove software-only rendering, native/full-image parity,
promoted fractional-opacity behavior or the unjoined Stage2 stored-Arc oracles.
Primary records: `arc350-outcome`, `arc350-independent-completion`, `arc350-seal`.

The companion map pins metadata paths, sizes and hashes. This drafting pass made
no root/goal/index edits, source or binary replay, workloads, or memory changes.
Owned evidence here does not establish root Quick/Full, hosted CI or broader native parity.

Local evidence map: [snapshot 0457](artifacts/goal-seventh-owned-ledger-intake-v1/0457/primary-evidence.json). The intake retains the referenced metadata as data; it does not repeat the underlying workloads.

### 2026-08-29: further owned validation evidence after the 04:57 ledger

Evidence addition after the 04:57 ledger freeze, as of 2026-08-29T05:53:34.8212739Z.
This addition records later archive closure, passive verification, observed attempts and held source compositions.
It preserves the earlier ledger and every failed attempt. All nine original completion gates remain open.
Metadata hashes below identify evidence; they do not extend any result to root Quick/Full, hosted CI or native parity.

The Lazy1968 failure now has a completed archive and an independent archive closure.
On owned HEAD87d88f57/tree4964de1a, session37826 closed at actual tool6761f3 with exit1.
The run still has 260 starts and terminals: 259 passes, one failed case and two assertion diagnostics.
The first16 calls passed all235 Stage2 cases; call17 ran all25 cases and failed
`ComponentHostTests.testReloadReusesNodeWithFreshStateAndHandlers` on caret and selection preservation.
The remaining1708 cases and83 partitions did not run. The 553.547s runner value precedes final serialization.
The finalized archive contains927 payloads/929 readonly files, including the54 runtime payloads;
the independent closure checked archive integrity and agrees with the already sealed failed-run accounting.
It does not turn this attempt into a1968-case pass or prove native XCTest exits or descendant closure.
[Lazy final outcome](C:/Users/maxw6/AppData/Local/Temp/swift-windowsui-owned1968-failure-freeze-6_d_ktls/OUTCOME.json)
and [archive closure](C:/Users/maxw6/AppData/Local/Temp/swift-windowsui-owned1968-failed-archive-closure-174b27da99944c0e91c20a10a9eef6e9/CLOSURE.json)
bind manifest421b8dc6/seal829ecd4f; earlier archive-reader failures remain metadata incidents, not additional test attempts.

A separate Lazy source correction is now frozen at staged tree79fbc275, derived from the failed owned tree.
It adds13 Host lines to retain incoming-controller ownership and restore scalar caret/selection only when no
incoming controller owns them, plus five new private-fixture tests; the prior test bodies remain unchanged.
Contracts, strict lint and independent source/integrity reviews passed, but no build or test ran for this correction.
The source census is5608 XCTest declarations plus134 Swift Testing declarations.
The unchanged100-filter/1968-case plan excludes the five new methods; neither that plan nor a larger run has passed.
[Source handoff](C:/Users/maxw6/AppData/Local/Temp/swift-windowsui-lazy-list-controller-restoration-w2o3lf83/artifacts/controller-restoration-source-freeze-v1/HANDOFF.md)
and [source closure](C:/Users/maxw6/AppData/Local/Temp/swift-windowsui-controller-freeze-closure-1nkxiv6_/REVIEW.json)
bind the842-payload source packet. Public lazy construction and the earlier runtime failure remain unresolved.

FilePreview392 now has final passive verification after its previously recorded successful build.
The build remains the one session89825/actual90cfe6 exit0: 414.60s in the compiler log,
421.0004914s in the supervisor receipt; these are different timing boundaries.
On owned tree22857650, capture7939cc/0 and copied-data reconciliation8e591a/0 were followed by seal254c03/0.
The sealed25-payload/27-file packet and independent review reconcile5414 generated XCTest identifiers
to source:5397 CoreLogic plus17 Portable, with392 selected async methods across30 classes and23 filters.
The separate134 Swift Testing declarations have no compiled-listing or execution qualification here.
One filter's generated source order differs from the planned order; actual test-listing order was not observed.
The executable was hashed and its bounded header read, but was neither copied nor executed.
All392 runtime cases remain unrun, including the two earlier UIA failure witnesses; neither failure is cleared.
[Passive handoff](C:/Users/maxw6/AppData/Local/Temp/swift-windowsui-file-preview392-discovery-zt8a6isd/checkout/artifacts/file-preview392-passive-admission-v1/HANDOFF.md)
binds manifestbed7bdb7/seal80abad6d. This adds metadata evidence, not a FilePreview, UIA or full-suite pass.

Disclosure18 now has a sealed independent outcome audit for owned HEAD3e30a746/treea66fee16.
All18 selected async tests passed once:12 new and6 existing cases, with no failures, skips, duplicates or unrun cases.
Session7758 closed at actual34f8ad/0; retained PS5 PID29664 exited0.
The383.890s supervisor value precedes final serialization; the build log separately records374.34s.
Passive capturef43b02/0 copied eight text artifacts and read executable hash/header metadata without executing the PE.
The final independent audit reconciles all5473 generated XCTest identifiers and async flags against source
(5456 CoreLogic+17 Portable;5121 async/352 synchronous), but qualifies execution only for the18 selected cases.
The remaining5455 XCTest registrations and134 source Swift Testing declarations did not run.
[Independent outcome review](C:/Users/maxw6/AppData/Local/Temp/progress-style-production-review-1f15e13bee9d440886b2292b6f5bd0a4/disclosure-lifetime-owned-outcome-audit-v1/compiled-capture-audit-v1/REVIEW.md)
binds AUDIT8be98a81 and seal308866fb. The owner's additional aggregate wrapper is pending at this freeze;
the earlier capture's pending label remains historical. Native exits, descendants, image identity and root Quick/Full remain unproved.

The corrected Date161 source001f3b5/tree4d64fcb was attempted once and failed at runtime.
Session35776 closed at actuale28f02/1 after two direct PS5 partitions exited0 then1.
The owner reconciliation records27 starts,26 passes and one failed test with six assertion diagnostics;
134 cases remain unrun, comprising8 new mounted cases and126 existing cases.
The failing width comparison recorded280 against220.51. Its cause is not established by this ledger.
Runner elapsed389.079s precedes final serialization; no timeout, termination or retry was reported.
The original zero-case compiler failure and the earlier metadata admission refusal remain separate historical events.
[Actual closure](C:/Users/maxw6/AppData/Local/Temp/swift-windowsui-date-picker-calendar-hover-9464-hzk375ok/repo/artifacts/date-picker-calendar161-run-v2-failure-v1/TOOL-CLOSED.json)
and [owner reconciliation](C:/Users/maxw6/AppData/Local/Temp/swift-windowsui-date-picker-calendar-hover-9464-hzk375ok/repo/artifacts/date-picker-calendar161-run-v2-failure-v1/RAW-RECONCILIATION.json)
are verified standalone receipts, not a final aggregate failure seal. Independent closure and final capture remain pending.
No correction or successful retry, native XCTest exit, descendant retirement or observed528-hit claim follows.

The CI fixture successor e97ef4f7 was initially source-only: strict UTF8 decoding supplies the copied source
to the filename-preserving ParseInput overload, without EOL normalization or weakening the old235 case bodies.
Its two added cases contain seven assertions, giving237 cases/727 assertions; the source packet records
the inverse proof and independent source review. The original235 failed pair and the AST observations remain intact.
A later single pair actually ran: initiald93c43/session12496 closed at actual0d47f9/0.
The outer native receipt reports10542ms; the launcher reports9972ms; the outside request-to-observation
interval is23.008s. PS5 andPS7 exited naturally0 in5857ms and3916ms respectively.
Each structured report records237 passes, zero failures and727 observed assertions with no setup failure.
These are observed report counts; independent case/capture audits and the final whole-packet seal are still pending.
All four redirected streams opened on the first attempt, so the sharing-retry branch was not exercised.
[Actual pair closure](C:/Users/maxw6/AppData/Local/Temp/ste-237-launch-70620cbd50c14c329fbc779ceea3e4ae/ACTUAL-PAIR-TOOL.json)
and [local audit](C:/Users/maxw6/AppData/Local/Temp/ste-237-launch-70620cbd50c14c329fbc779ceea3e4ae/POSTRUN-LOCAL-AUDIT.json)
preserve that pending qualification. No real Swift workload, hosted CI, LF-checkout, EOF or descendant proof is claimed.

Four separately frozen source compositions start from committed root46d22ff; none has a joined runtime result.
The table records owned source identities and authored selections, not new passes or current root integration.

| Composition | Owned commit / tree | Authored selection | Full source XCTest census |
| --- | --- | --- | --- |
| Grid | 69c321df / b1dc4d98 | 170 async;13 filters | 5497 |
| Label | 3d4c387a / a1364970 | 141;6 filters | 5486 =5469 CoreLogic+17 Portable |
| Document | 716bc41f / b0fe6777 | 1287 async;63 filters | 5555 |
| Hover | 850fb5bd /92ba9e6d | 55 async;4 filters | 5499 =5482 CoreLogic+17 Portable |

Grid retains the36 new cases and two fixture migrations from its earlier isolated170 pass, plus a provenance note.
Label keeps the same141 identifiers and case bodies; its17 Portable methods are XCTest, not Swift Testing.
Document keeps all94 additions and the63-filter selection, but its inherited mounted observer/UIA behavior differs
from the isolated c615 tree; the prior1287 pass cannot establish equivalence of this combination.
Hover preserves the root baseline and adds38 cases; its packet corrects the older Core-only5482 count.
These packets record static/source reviews, not emitted registrations, new builds, native effects or runtime cleanup.
[Grid source seal](C:/Users/maxw6/AppData/Local/Temp/swift-windowsui-grid-join-46d22ff-s4hfb8n0/repo/artifacts/grid-join-source-freeze-v1/SEAL.json),
[Label handoff](C:/Users/maxw6/AppData/Local/Temp/swift-windowsui-label141-rebind-3d4c387-2c1f7a6190ec/candidate-v2/HANDOFF.md),
[Document handoff](C:/Users/maxw6/AppData/Local/Temp/swift-windowsui-document-root46-join-imlwz_ye/source-composition-v1/HANDOFF.md),
and [Hover handoff](C:/Users/maxw6/AppData/Local/Temp/swift-windowsui-hover-reentry-46d22ff-c3aac2c943bd/artifacts/hover-reentry-runner-proposal-v1/HANDOFF.md)
bind their separate held source states. Lazy's restoration above belongs to its failed owned base, not this shared root46 census.

No earlier failure, pending-at-the-time entry or validation boundary is rewritten by this addition.
Original goal sections1-9 and all nine unchecked completion gates are unchanged.

The 51 primary metadata references and the exact frozen draft are copied in
[the local evidence archive](artifacts/goal-seventh-ci237-evidence-v1/COPY-MANIFEST.json).
This copy preserves their original timing and qualification boundaries.

### 2026-08-29: accepted CI evidence correction and combined validation intake

The CI237 results described as pending at the preceding 05:53 freeze now have
completed independent case and capture audits. The single serial pair passed
237 distinct cases and 727 assertions on each of Windows PowerShell 5.1.26100.9223
and installed PowerShell 7.6.5. The original 235 cases and 720 assertions were
preserved; two strict UTF8 source-decoding regressions add seven assertions.
Actual session12496 closed at tool0d47f9/0. The outside interval was23.008s,
with outer10542ms and controller9972ms recorded at their separate boundaries.
The 237 PASSED records and seven intentional negative-control diagnostics in
each stdout were reconciled with the structured results. PS5 LF and PS7 CRLF
stdout remain distinct raw files. All four stream snapshots qualified on their
first open; no sharing-retry branch, EOF or descendant closure was proved.

The complete new692-member pair and36-member source packet are copied locally
under [CI237 evidence](artifacts/goal-seventh-ci237-evidence-v1/COPY-MANIFEST.json).
The [accepted handoff](artifacts/goal-seventh-ci237-evidence-v1/pair/HANDOFF.md)
and [final audit](artifacts/goal-seventh-ci237-evidence-v1/pair/FINAL-AUDIT.json)
bind pair manifestdead00c4, case auditfac09de5 and capture auditb463308a.
The original failed235 generation and both AST diagnostic packets remain
unchanged. These results qualify the frozen CRLF synthetic inputs, not an LF
checkout, a real Swift workload, hosted CI or a release gate.

Six CI files were applied over rootc0e901b using the reviewed source composition:
the Windows workflow, agent-check/test wrappers, evidence helper, synthetic
fixture and Testing documentation. Opted-in Full now retains a caller-held
request identity, preserves the original test invocation and exit policy, checks
evidence separately after successful tests, and withholds stale case records
during sanitized publication. Current-invocation matching is not authenticated
freshness. The source
fixture reads UTF8 explicitly without relaxing its existing hash guards.
All five code files match the tested raw bytes. The documentation adds exactly
147 CI lines while preserving every existing byte, including the23 Progress
lines. Intake ffcfc3/session51049 closed at77b9ea/0; its
[receipt](artifacts/goal-seventh-ci-root6-intake-v3/INTAKE.json) records794 regular
source files after the two additions and unchanged unrelated source/index/goal
bytes. The unexecuted v2 intake control's incomplete failure-path accounting
was corrected in v3 before this sole application.

Root contract checks passed immediately before and after intake at44383e/0
and ae9b3b/0. Strict lint covered all59 Swift files changed sincec7e7987,
closing session94170 atb81abc/0; all59 hashes were unchanged. These checks do
not substitute for fresh combined Quick/Full validation, which remains pending
at this checkpoint. No push or hosted qualification is claimed here.

Separately, the [Pure207 outcome](artifacts/goal-seventh-ci237-evidence-v1/pure207/OUTCOME.json)
is now sealed and independently accepted:207 cases,635 assertions and zero
failures, comprising169 clock,24 envelope and14 preservation controls.
Actual tool1fd79e and its child returned0. The original outside interval5.395s
and complete outside tail0.424067s fit this phase's60/15-second bounds; capture
return3.65645s fits45 seconds. This did not run StageA61, its old374/4453
preservation census, Swift or a native UI fixture. The historical A61 failure,
missing4453-after evidence, StageA300/60 budget and Quick performance target
remain unresolved; a pure-controller pass cannot repair or qualify them.

Disclosure18's owner aggregate subsequently closed too. Its
[qualification](artifacts/goal-seventh-ci237-evidence-v1/disclosure18/QUALIFICATION.json)
and manifest47b8eb9a/sealcf714822 preserve the independently accepted18-case
pass and5473-entry registration audit already described above. Only18 tests
executed;5455 other XCTest registrations and134 Swift Testing declarations
remain unrun in that owned attempt. Root integration remains a later slice.

These additions preserve original sections1-9, all nine unchecked completion
gates, earlier failed attempts and every earlier evidence boundary.

### 2026-08-29: first combined Quick failure and scoped memory-fixture correction

The CI evidence integration and preceding ledger were committed together as
dd2e37111081aca029c60c4d608728f213c5fb3f, tree886728dbcb5ad5db01219721185912c9d915085c.
The first fresh combined Quick attempt then failed before any Swift command.
Actual launch1f2b99/session39591 closed at33932e/1. Its direct PowerShell child
6304 returned1 naturally after19.281s; no timeout or forced termination occurred.
Contracts, checkout metadata, explicit lint-path fixtures, baseline fixtures
and API audit capture fixtures had passed. The next memory-isolation fixture
stopped at assertion98 while inspecting its copied agent-check source, before
launching any of its12 stub scenarios. The new evidence resolver was outside
the old fixture's command whitelist. This was not a Swift test failure, a
memory-workload result or a successful combined Quick run.

[The failed Quick archive](artifacts/goal-seventh-root-quick-failed-v1/failure.json)
preserves the raw2543-byte output, SHAa00094573255dadea4c1367342864b8c66a3ced1a482bc7b8fcf0b0f97e048dc,
the nonzero runner result and all12 fixed archival payloads. Archiver9e1cd1/1
means that a failed validation was completely archived, not that validation
passed. The parent closure and copied612-byte fixture report retain the actual
tool boundary and zero launched cases. All794 tracked regular source files
and the index were preserved. No build artifact was copied or invoked for
this failure, and the successful-run supplemental collector was not used.

The correction changes only scripts/test-agent-check-memory-isolation.ps1.
It admits four specific AST command objects inside the reviewed evidence
prefix, while retaining the general command and variable whitelists and
computed-stage rule. The resolver, empty default evidence directory and six
ordered Full statements remain pinned. Seven source extents normalize only
CRLF to LF before hashing; other whitespace, tokens and node identity remain
significant. Pure negative controls reject a changed resolver, changed Check
site and an unrelated PowerShell call. Child process dictionaries exclude
exactly the four evidence/Actions control variables; the parent environment
and unrelated child variables remain unchanged. The original12 scenario
bodies are byte-identical, including Full's ordinary single -Sharded argument.
The five production CI files are unchanged from the accepted CI237 inputs.

The exact26608-byte corrected fixture has
SHAef9e2dd39e6fb781d942c5e8ffb943c2219b6e4763f0f8500780e78d611e6ddc.
One targeted serial pair passed333 assertions and all12 scenarios on each of
Windows PowerShell5.1.26100.9223 and installed PowerShell7.6.5. PS5 toola36b35/0
recorded child49124, natural0 and9114ms. PS7 launch122a80/session54198 closed
at6cac77/0, recording child58252, natural0 and13862ms. The12 scenarios include
expected failures: the missing-script exit is-196608 on PS5 and64 on PS7;
both satisfy the unchanged nonzero-and-stop requirement. Neither result was
standardized or retried. Independent review reconciled all24 call ledgers,
344 stub calls and48 saved case-stream hashes, with zero real evidence-helper
calls. These are fixture results, not actual Swift, Quick or Full execution.
Saved case-stream hashes describe decoded-and-saved UTF8 output rather than
original native pipe bytes; no descendant-closure claim is made.

The final17-pin preservation check78c13c/0 released the root source/index
at06:54:43.5435477Z before intake. The evidence copy and source intake are
recorded under [the fixture evidence archive](artifacts/goal-seventh-memory-fixture-evidence-v1/COPY-MANIFEST.json).
Actual intake10f071/0 verified all717 original payloads and copied719 files
including their manifest and external seal. Its
[receipt](artifacts/goal-seventh-memory-fixture-evidence-v1/INTAKE.json) records
the sole changed source path, unchanged index and793 other regular source
files. Post-intake ContractsOnly passed at e5b881/0; the
[contract log](artifacts/goal-seventh-memory-fixture-evidence-v1/contracts-after.log)
retains that output. No Swift source changed after the prior59-file strict lint.
The original failed Quick attempt, superseded unrun source candidate,
metadata-only failures and reviewer-only read/comparison failures remain
separate and unchanged. No failure has been converted into a passing result.

The current source census remains5461 XCTest declarations:5444 CoreLogic and
17 Portable, with5109 async and352 synchronous methods. An independent lexical
review corrected one historical per-method async flag whose declaration wraps
onto the next line; the previously stated aggregate5109/352 was already right.
The134 Swift Testing declarations are a separate source count. The static
Quick plan expects2651 XCTest identifiers and9 Swift Testing declarations
across167 test invocations, including31 methods selected by the existing
substring rules. These are source expectations, not observed execution counts.

A new combined Quick run and then Full, preserved compiled-registration
evidence, gallery comparison, grouped push and exact-commit hosted validation
remain pending at this checkpoint. This correction does not add feature scope
or relax any acceptance requirement. Original sections1-9, all nine unchecked
completion gates and all earlier evidence boundaries remain unchanged.

### Seventh validation batch: Quick reaches a deferred-List focus failure

The next serial root Quick run used commit
`91df15c6959b13f0b48cd3529bacb943d05c394b`, tree
`6f86f0624a603200d0664883e8aad85031610195`. Unlike the earlier
memory-isolation fixture failure, this run passed that fixture's 333 assertions
and reached XCTest execution. It did not pass Quick, and Full and the grouped
push remain pending.

- The reviewed runner was invoked once as `-Quick`. Its direct PowerShell 5
  child, PID 24112, exited naturally with code 1. Actual tool launch `6dbf07`,
  session 8151, closed as `a2911f` with code 1. The recorded child-wait and
  cleanup interval was 841.844 seconds. There was no timeout or termination
  attempt; source and index endpoint preservation passed. These facts do not
  prove descendant-process or native-resource closure.
- The failure is
  `ListVirtualizationTests.testKeyboardSelectionCanRevealADeferredFarAwayRow`,
  at the existing assertion that runtime focus is the target row. Selection
  reached 900 and the scroll offset exceeded 20,000, but focus was not on row
  900 before the next render. The later explicit render realized that row,
  and the subsequent Up selection/focus checks passed. No test assertion was
  removed, weakened, or converted to a skip.
- Source inspection explains the ordering: List requests focus while its
  target is still deferred; ordinary focus admission rejects that target;
  the subsequent scroll changes the offset without synchronously realizing
  the row. A fix is being developed around List-owned reveal, bounded layout
  settlement, and the existing focus admission. Global focus and UI Automation
  availability checks must remain intact. This is a diagnosis and source-work
  direction, not a tested fix.
- The failed run is retained at
  `artifacts/goal-seventh-root-quick-v2-e52f0fac232e41608df78a800e08f475`.
  Its 862,076-byte raw log has SHA256
  `5ec361d4b618a42f58a4457891948ceff2fc31216966de1c5a4974823e52ee04`.
  The failure archive completed with its expected nonzero result, actual
  `efdb7a/1`; its 12-payload manifest is
  `artifacts/goal-seventh-root-quick-failed-v2/failure.json`, SHA256
  `707c14b2250c7ffb6cec2f522cd4a15297ae51fb3a644b3357fd0548578ca668`.
  A complete failure archive does not make the validation successful.
- Before another SwiftPM invocation, one passive capture copied the exact
  test PE, eight fixed generated/build text files, and three supporting source
  files. Reviewed control v3, SHA256
  `7d637436100b74521219753458407b09a3255b9a16bedd0b8783bb48d15d942b`,
  ran with isolated, unoptimized Python and closed as actual `8e83b1/0`.
  Its manifest is
  `artifacts/goal-seventh-root-quick-failed-v2/compiled-failure/manifest.json`,
  SHA256 `50c2bcbac0b22be8c541e9a89fa24e2fd9521e35867e652917375b50c0f3a3cf`.
  The copied PE is 440,354,816 bytes, SHA256
  `046831875d0ac941ede14c6337ab295570045cbf24682a10b61952582d21c143`.
  Nothing in that capture invoked the PE, a fixture, a build, or a test listing.
  Its source/index checks establish endpoint preservation, not continuous
  immutability or complete compiler provenance.
- Capture controls v1 and v2 remain preserved and uninvoked. Review corrected
  archive-sidecar binding, child Git environment/timeouts, and bounded
  same-buffer reads before the single v3 capture. These preparation findings
  are distinct from the actual List test failure. Subsequent source/generated
  registry and raw-case reconciliation will use the preserved copies; that
  independent reconciliation is still pending at this entry.

The earlier failed run and the later successful fixture-only checks retain
their separate outcomes. No current-root Full, hosted exact-commit CI,
macOS reference, native interaction, or hardware timing qualification follows
from this failed Quick. All nine original completion gates remain open.


### Seventh batch: preserved focus failures and metadata follow-up (2026-08-29)

This is an additive record of separate checkpoints. Historical source-only
statements below describe their stated checkpoint; the later entries record
the subsequent intake and failed compilation. No original scope, acceptance
target, exception policy, or completion gate changes.

#### Completed metadata work recorded before the corrected focus run

Additive metadata follow-up, using the fixed receipts reviewed on 2026-08-29.
This entry adds no test execution and leaves all earlier outcomes and original completion criteria unchanged.

The completed passive audit concerns the failed Quick source commit
`91df15c6959b13f0b48cd3529bacb943d05c394b`, tree `6f86f0624a603200d0664883e8aad85031610195`.
Its generated XCTest identities, reachability and adapter flags reconcile with the 5,461-declaration source census
(5,109 async and 352 synchronous). Execution covered 2,323 XCTest start/terminal pairs:
2,322 passed and the one deferred-List keyboard-focus case failed. Of 167 planned invocations, 143 were observed;
24 invocations and 328 planned XCTest identifiers remain unobserved. Material observation remains unavailable.
The parent-observed metadata tool `ca65cf` closed with exit 0 in 1.0397222s, separately from the audit's
0.906s internal elapsed value. Neither metadata exit changes the original Quick outcome of exit 1.

The nine Swift Testing start/pass event pairs are present, but canonical Swift Testing reconciliation is not clear.
The 38 new issues comprise 18 per-invocation unknown-label diagnostics, the same 18 global diagnostics,
and two identifier checks: the fixed parser accepts `method()` aliases, not the observed quoted `@Test` labels.
A separate metadata review uniquely associates each label with one of the 134 frozen source declaration records.
Its SceneRasterizer source pin is `45e1b627bf9764231968fb1dc5503c0d7698a6f1f32b2857ad682fc2d3adfc9b`;
the review did not reopen the Swift file. This association does not replace the original unresolved canonical
identity flags or establish compiled Swift Testing registration identity. No parser, audit or test was retried.
The six original parser issues remain in order and the complete eight-field parser observation matches the archive.
The archive's eight issue entries are those six plus its nonzero-exit and aggregate-test-failure entries;
they are not eight failed cases. The sole List failure and the unobserved suffix remain unchanged.

P9's separate post-run capsule confirms 279 pure report-predicate controls: six expected accepts and
273 expected rejects, with zero failed expectations. The pinned source manifest is
`64e8971059f1a33a3adf605cae851151eeef9a9b334fd66a476cac4567e82858`.
Original caller791c9d, author053714, sealer12a332, publisher968695 and terminal sample6672b3 all returned 0;
the retained child43080 exited 0 with both streams at EOF and no timeout or intervention.
The original integer-QPC interval is 6.9228365s within the original 60s budget, including its 15s reserve;
the separate UTC subtraction is 6.9188393s. Later preservation does not renew that clock.
The post-run audit checked the nine named original files and 51 selected pins, with independent review clear.
Original self-referential publisher/whole-qualification fields remain null; external terminal receipts carry the exits.
This proves pure controls only: no full validator, native probe, candidate DLL, compiler or repository test ran.
Historical F9/P6 failures, relative-path rejections and the denied/unsealed binary audit remain unchanged.

The bounded SDK review uses immutable source context `292eb3c439c5f5ff5284f4cff621d57e6ed55a0a`
and historical capture run33135644721/attempt1 at `0cb9a361130c92dfba4bc6c65ab4fd0a306f11dd`.
It checked 18 metadata files, not the large identity, graph, relationship or interface streams.
The saved receipts record Xcode26.6/17F113, macOS SDK26.5/25F70 and Apple Swift6.3.3;
SDKSettings independently reports macOS26.5. All 14 saved command receipts report exit0 without timeout.
These commands were inspected, not rerun; their recorded tool hashes are not independently verified executables.
The 134,147 precise-identifier total remains a manifest/inventory-fact claim, not a newly computed full count.
All 182 inspected queue entries remain lexical candidates and unreviewed, with no Windows symbol mapping.
Windows matching, Swift source parsing, identity review and behavior-conformance authority fields are all false.
No overlay-completeness, macOS reference behavior, Windows parity or baseline promotion follows.

The following small evidence files were read and their byte lengths and SHA256 pins verified; no transitive payload replay was performed.

| Evidence | Bytes | SHA256 |
| --- | ---: | --- |
| [Quick summary](C:/Users/maxw6/Projects/swift-windowsui/artifacts/goal-seventh-root-quick-failed-v2-audit-v1/summary.json) | 1404 | bce01b985defd3e9a1f62efac03517435d0a552a50e675d98eaea18f81c05ccb |
| [Quick output manifest](C:/Users/maxw6/Projects/swift-windowsui/artifacts/goal-seventh-root-quick-failed-v2-audit-v1/OUTPUT-MANIFEST.json) | 569 | 542bbee26aaa634d5640b297567b0cc38d3f1e8d06ac94d27f90dc3b04e600bf |
| [Parent audit closure](C:/Users/maxw6/Projects/swift-windowsui/artifacts/goal-seventh-root-quick-failed-v2-audit-parent-closure-v1.json) | 803 | a6fc4bad41db77f2d88d8c756800b77490efbba76e29070a31774e10bb61053d |
| [Quoted-label and archive classification](C:/Users/maxw6/AppData/Local/Temp/quick-failed-output-classification-91df-9e39f292cb15/REPORT.md) | 5264 | af04784eeabec4bbd03a17770846e7b4bf88cca6a7c1b020c99683de3748aa7a |
| [P9 post-run handoff](C:/Users/maxw6/AppData/Local/Temp/swift-windowsui-p9-pure-postrun-audit-1787990560567/POSTRUN-HANDOFF.json) | 7448 | c73a3622e385b626c23d57d825e53488500ecfe1de368e2ef5c3accc83be28bd |
| [P9 capsule manifest](C:/Users/maxw6/AppData/Local/Temp/swift-windowsui-p9-pure-postrun-audit-1787990560567/frozen-postrun-capsule-manifest.json) | 1710 | 24f0bac670f668ca8e83fc16d6178c2201ae7f5b90300656f84fec98707efc11 |
| [P9 freeze receipt](C:/Users/maxw6/AppData/Local/Temp/swift-windowsui-p9-pure-postrun-audit-1787990560567/postrun-freeze-receipt.json) | 1632 | 717960ec196b0873f6b048b213ab1e4ec3863327e48001cb72c8bf8ace94efa5 |
| [P9 independent review](C:/Users/maxw6/AppData/Local/Temp/swift-windowsui-p9-pure-postrun-audit-1787990560567/reviews/independent-postrun-review.json) | 14892 | 09b214005281e4acaa3dfbbb53c1e5974cb1bd063c6f6301b879db5126559b66 |
| [SDK metadata review](C:/Users/maxw6/AppData/Local/Temp/codex-baseline-metadata-review-40969f20378245e78632b6f21bce7c65/report.md) | 8190 | 1fd69c88e2c75f6197ba9311ada8471922ca00f2c12ce0648e341453a7bb9904 |

The separately launched root93 attempt is outside this entry; no outcome is inferred from its launch or source state.
Original sections1-9, all nine open completion gates, the preserved38e855d prefix and all earlier evidence remain unchanged.


#### Historical checkpoint before the first corrected95 launch
The failed root93 attempt tested HEAD `292eb3c439c5f5ff5284f4cff621d57e6ed55a0a`, tree `36a4a7a599ab56b4f39460c6df31bd598c9b5401`.
Launch `0e9dfc`, session56787, closed naturally as `642a4f/1`; retained direct PS5 child51948 exited1.
The copied exit receipt records no timeout, termination attempt, capture error or source-observation error.
Parent raw observation records18 start/terminal pairs:17 passes, one failure and75 cases unrun;
independent reconciliation from the preserved copies is still pending at this entry.
The new failure is `ListDeferredKeyboardFocusTests.testSynchronousRebuildFocusesTheRetainedRowAndRetiresTheOldHandler`:
the immediate `scrollOffset > 0` assertion at line250. No passing93-case result follows from its completed capture.

Parent-observed passive capture `ae0edb/0` took4.4341007s and produced17 payloads.
These include nine compiled artifacts (one PE and eight text files), four run inputs, three supporting source files and an index copy.
The manifest records endpoint checks for798 tracked files and the index; only the three supporting source files were copied.
Compiled-source census and raw-case verification are explicitly false/pending in that capture manifest.
Only the capture manifest, parent closure and copied source/process/exit JSON were read here; no PE, raw log or live `.build` was reopened.

The proposed successor remains source-only:18 new tests plus77 existing tests form a95-case plan, not an executed result.
Parent source analysis distinguishes the already-realized row's queued normal-render timing from the separate production Host gap
when revealing a deferred far target. The original strict settlement proof remains required; this distinction does not prove a fix.
The corrected proof and95-case plan have neither run nor been taken into root at this checkpoint.

| Verified metadata | Bytes | SHA256 |
| --- | ---: | --- |
| [Parent capture closure](C:/Users/maxw6/Projects/swift-windowsui/artifacts/goal-seventh-root-list-focus93-capture-parent-closure-v1.json) | 1403 | 5ffaf0327651b7f36b35a057bda814aa1d291b878f488230ac099fd119c353f1 |
| [Capture manifest](C:/Users/maxw6/Projects/swift-windowsui/artifacts/goal-seventh-root-list-focus93-postrun-v1/manifest.json) | 7754 | fbd75368aa40cfa0a95b56f072415a393bdc8279d2b8c4ca145f906433ef6f85 |
| [Copied source receipt](C:/Users/maxw6/Projects/swift-windowsui/artifacts/goal-seventh-root-list-focus93-postrun-v1/run/goal-seventh-root-list-focus93-v1-source.json) | 226856 | ff8dc945b2b20fc34f5a10a3e04a72408e97933927bb19c32ff5ae970d8921dd |
| [Copied process receipt](C:/Users/maxw6/Projects/swift-windowsui/artifacts/goal-seventh-root-list-focus93-postrun-v1/run/goal-seventh-root-list-focus93-v1-process.json) | 600 | 0126da769c01bcb86a34c00ca14cd73e2a4b0701d15a19fb2cd24d77603de193 |
| [Copied exit receipt](C:/Users/maxw6/Projects/swift-windowsui/artifacts/goal-seventh-root-list-focus93-postrun-v1/run/goal-seventh-root-list-focus93-v1-exit.json) | 1109 | 2eacdb186384d34931ac9c21191228fcd79a8123e4a419f33a59dc432c91cc10 |

Original sections1-9, all nine open gates, the38e855d prefix and prior failures remain unchanged.
Native test exits, descendant closure, Quick/Full and the separate Material214 attempt receive no qualification here.


#### Corrected95 intake, failed compilation, and exact fixture repair

The four-path production/test correction was applied to root by a5f6e6/0.
At HEAD292eb3c439c5f5ff5284f4cff621d57e6ed55a0a, the staged tree became
a476d4782aab52d2329b98c9a813ff594d376e42 and the index SHA256 became
ad4dd149021732a09d7506677c69aadf571e7673fcb9d6cdd19938dbe71571d3.
All470 pre-existing root test files retained both their physical bytes and
indexed blobs. Other tracked entries, the gitlink and goal.md were preserved.
Root contracts passed before intake (7c5c1f/0), and contracts plus strict lint
passed on all six changed Swift files (adcaee/session9581 -> 7511ba/0).
These static checks did not prove that the new tests compiled.

The source plan contains95 async XCTest methods,65 throwing, all MainActor,
with no selected Swift Testing declarations. The six unchanged stock filters
select19/8/20/15/20/13 methods. The full source expectation is5479 XCTest
declarations:5462 Core plus17 Portable,5127 async and352 synchronous.
The23-payload source packet was verified by a24783/0; its manifest SHA256 is
12763a92e15f26a44636eb67844637d6e36dcea5a82822bf2d567b9b59ce95b1.
These are source expectations, not a compiled registration result.

The first corrected95 invocation was ab0fa0/session35734 -> 7a12f5/1.
Its retained PS5 child52684 exited1 naturally, without timeout, intervention,
capture error or source-observation error. The first of six SwiftPM calls
failed during compilation; there were zero test lifecycles and all95 cases
remain unrun for this attempt. Runtime/helper compilation proceeded, but the
new test attempted to access fileprivate ViewNode.runtime at source line211;
the same invalid expression also appeared at225. The complete8586-byte log,
read in27ad25/0, has SHA256
315d0857b2314238c10e6d651ceccdb1378b065910c821d4930c376aafdde261.
No runtime focus or scroll outcome follows from this failed compile.

The separately approved passive capture completed as915f42/0 in4.5169016s.
It preserved17 payloads and checked all798 tracked source files and the index.
Its manifest SHA256 is
ea3f82dcf17694bbfebc8c74129bb46443b7fa371ce284a78bd00a44dab96334.
The copied PE and all four generated Swift files are byte-identical to the
earlier93 capture, as compared in771721/0. Their bytes do not establish
current5479-test registration or new binary provenance. No PE or generated
test listing was invoked. The parent closure is stored at
[focused95 capture closure](C:/Users/maxw6/Projects/swift-windowsui/artifacts/goal-seventh-root-list-focus95-capture-parent-closure-v1.json).
The original93 runtime failure and both earlier Quick failures remain intact.

The repair replaces only the two inaccessible test expressions with the
existing internal hasListNavigationRuntime(runtime) helper. That helper
already evaluates exactly runtime === expected; the test already imports
SwiftWindowsUI with @testable. The identity assertions are retained without
changing production access control, adding a test API, altering any test ID,
or changing the selected effects. The1286-byte patch SHA256 is
48f50cc1232a62b90c3f8f6022268d3886f3df52df727673ddd7cf3aa22bf3ae.
Root intake324cb0/0 verified the new19885-byte file SHA256
d8fbeaec0bb9abeba276689ee3ca84882d274138456507239e44964a7c4e53b0,
all798 other tracked entries, all470 old test files, production source and goal
preservation. Its staged tree is68394f9cc00bec8df642643b68b649363805221c.
This repair has not run at this checkpoint. A fresh95 attempt, copied
registration/case reconciliation, Quick and Full remain required.

#### Other isolated work remains separate from root validation

The first owned Material214 run stopped during compilation:
cb3887/session32213 -> 29675d/1. Only the first of11 stock calls launched;
all214 case lifecycles were unstarted, including the known residual skip.
The copied log identifies two distinct invalid accesses to Rect.x/y in the
new test fixture's shared quad helper. They are not rendering-test failures.
The separate capture completed as368910/0; its sealed35-payload outcome
manifest is5b3482782f2dbd9ed6016c387d683709cd0b4e2d4ed11c68b7105588f2766bbc.
All four generated Swift registry files and the test PE were absent in that
owned build. A fixture-only successor uses Rect.origin.x/y; its commit
2e4e6aedb2d50b26eabf0f5ba3479715c276020c and one-line patch
6275189431892a271a7c028ca3654590dee719185a04740ca5deda65866b8f6a
do not yet carry a new runtime result or root intake.

The first Date175 metadata admission also failed before any compiler or test
launch:9ee649/1, with failure receipt SHA256
16b03907d07aef5c15e183c3cdc52bc0ef6def595d5ed5fda289fd2846ea5d4b.
Its error was the path-stat/handle-fstat identity comparison, after129983734
input bytes. The original receipt did not record the offending path or fields.
A deterministic frozen read-order projection places Python.exe next; that is
an inference, not a recovered observation of the original mismatch.
A separate approved seven-file, one-byte-per-file Temp experiment
(20cb1c/0) reproduced only the Windows executable permission-bit distinction
for .exe/.com/.bat/.cmd; device/inode/type/size/mtime and endpoint records stayed
equal. The proposed successor admits only that exact directional0o111
difference, retaining every other identity/hash/reparse/read-budget check and
adding bounded mismatch details. A metadata success, if later obtained, is
not authorization or evidence that the175 runtime tests passed.

Image sampling and the lazy-state bridge remain isolated implementation work.
Their source checks, prospective build plans and unsupported cases do not
establish compiled, runtime or native SwiftUI conformance. Public List
construction remains eager; animated deferred-focus completion and the
remaining lifecycle/state work remain open. P9's new adapters and245 authored
controls likewise do not inherit qualification from the earlier279 pure checks.

All original sections1-9, all nine open completion gates and the exact
38e855d goal prefix are preserved. No failed, unrun, unsupported or
source-only result is promoted to completion by this entry.

### 2026-08-29: corrected List keyboard focus passes the focused runtime suite

The seven-path List change is committed as `ed07d34ef5eb851dacae3fc2f34c7d6c570dc013`.
Its tree is exactly `600b31ffc36f21d525a02171f2f7387ac8ce7a98`, the staged tree
tested against parent commit `d8bfc27631d29f1e67e97c7f7786d505796fb897`.
The change keeps the original keyboard handler's physical attachment and runtime
authority through a synchronous rebuild, then uses a single prepared layout
receipt to reveal and focus a retained deferred row. Reentrant changes to that
receipt, focus, attachment, or geometry reject stale follow-up work. Ordinary
focus and UI Automation keep their existing admission rules.

The corrected focused run `goal-seventh-root-list-focus95-v2` closed naturally
with exit zero (`3aed29`, session `49992`, completion `6fa361/0`). All six stock
serial invocations passed. A separate raw-log check found 95 unique starts and
95 matching terminals in the same order, all PASS, with no skipped or failed
case. This includes the original far-row keyboard selection regression, the
synchronous host rebuild, stale-handler rejection, and same-geometry layout
receipt supersession. The run preserved all 798 tracked regular source files,
the staged tree, and the physical index; it needed no timeout or intervention.
Contracts and strict formatting checks had passed before this run. The two-line
test repair uses the existing internal runtime identity accessor and changes
neither the assertion's meaning nor production access control.

Before another root SwiftPM command, a separate copy-only capture preserved the
four run files, index, three source inputs, test executable, four generated Swift
files, and four build metadata files: 17 payloads, with nine compiled artifacts.
It closed as `5d8c30/0`; the manifest is
`artifacts/goal-seventh-root-list-focus95-postrun-v2/manifest.json`
(7,790 bytes, SHA256 `10b56697c065ebb813332bd11b4faaad075609653685e9e5838089cae4a855b2`).
The compiled CoreLogic registry changed to the corrected build. Full comparison
against the 5,479 source XCTest declarations and exact stock selection remains
a separate copied-input audit at this checkpoint. The executable was copied,
not invoked by the capture. Endpoint hashes and a retained direct-child exit do
not establish continuous immutability or complete descendant/build provenance.

The earlier focused93 failure has now been independently reconciled without
rerunning tests (`4145a3/0`). Its 5,477 generated XCTest identities and adapter
flags match that earlier source. Exactly 18 cases started and terminated:
17 PASS and the one recorded synchronous-rebuild assertion FAIL. The remaining
75 cases in five invocations were unrun. There were no framing or lifecycle
ambiguities, and the failed stop boundary matched the preserved closure.
The metadata audit's exit zero does not replace the original test exit one.
The failed95 compile attempt likewise remains a distinct zero-test failure;
neither failure packet is overwritten or counted as passing coverage.

The DatePicker successor's corrected metadata admission also closed successfully
(`92f717`, session `59694`, `b48824/0`). All 64 recorded Git calls exited zero;
the source/index, 96 fixed input pins, 72 reserved output names, and the planned
175-case selection matched. This follows the separately preserved admission
failure and the narrow, tested Windows executable-mode comparison correction.
It is metadata evidence only: all 175 runtime cases remain unrun.

This checkpoint does not close any of the original nine completion gates.
Public List construction is still eager; the separate lazy state/activity bridge
and animated deferred-focus completion are unfinished. Root Quick and Full
validation, fresh gallery/backend evidence, and the grouped push remain pending.
The original scope, acceptance targets, and earlier failed evidence are unchanged.

### Follow-up: completed List evidence, fresh Quick/Full, and bounded CI image findings

This adds evidence to the existing destination and checkpoints. It does not
change sections 1–9, remove a gap, relax a comparison threshold, or close any of
the nine original completion gates. Source-only proposals and owned-checkout
results below remain distinct from integrated root validation.

The corrected List keyboard-navigation slice was committed as
`ed07d34ef5eb851dacae3fc2f34c7d6c570dc013`; its tree
`600b31ffc36f21d525a02171f2f7387ac8ce7a98` is the staged tree exercised by the
previously recorded successful focused95-v2 run. Commit `5ba24a2` recorded that
run and its preserved failures, and `060f5c3c689980c5b2156c12d81a571c094a0d89`
linked the behavior document from the README and compatibility table. The latter
tree is `e89279c044a43ea84de63997375ef3165a697a3a`; only the three documentation
paths differ from the tested List tree. These later commit IDs do not replace
the focused run's original `d8bfc276` HEAD and staged-tree identity.

- The focused95-v2 passive reconciliation subsequently ran once and closed
  naturally with actual tool `b9a551/0`. It matched all 5,479 XCTest declarations
  to generated registrations and async adapters: 5,462 Core and 17 Portable,
  with 5,127 async and 352 synchronous declarations. The six exact focused
  scopes contained 95 starts and 95 passing terminals, zero framing/lifecycle
  issues, no failures/skips/unrun suffix, and six valid zero-Swift-Testing
  envelopes. This is stronger than inferring success from exit 0 or a count.
  The result is
  `artifacts/goal-seventh-root-list-focus95-v2-audit-v1/audit-result.json`
  (6,352,016 bytes, SHA-256
  `2c37a7c70d6ac76c67ae3d8eae7d9d00bb3cfab1ef45fba5750ecf3f2076a3c8`);
  its summary hash is
  `607f261bef76541b233e1862a990a6516c9b038844f234cef9d9869581c85e0c`.
  Parent closure `40590e/0` binds the actual closed audit. No PE, current index,
  live build directory, or active broad-validation output was read by it.
  The original93 failure and first95 compile failure remain unchanged.
- Root Quick-v3 ran on the unchanged, clean `060f5c3c` source/index and closed
  `ab012d/session88919 -> 58c8ee/0`, with retained PS5 PID 32544 and 954.078
  seconds elapsed. The observed stream has 2,651 complete XCTest pairs:
  2,650 passing and the existing
  `RenderPassAbstractionTests.testMaterialInsideADrawingGroupBlursNothing`
  skip. It has nine passing Swift Testing pairs across 167 invocation
  envelopes; all archived invocation multiplicities match and no duplicate
  XCTest pair was observed. The known skip remains a gap, not a pass.
  The successful archive was created by `7fa281/0` at
  `artifacts/goal-seventh-root-quick-v3-archive/validation-quick.json`
  (1,216,326 bytes, SHA-256
  `3d861039e92e98b8e865c27be0833e47f481c0634b425dcbcde60a272efc2e9f`).
  Parent closure and all 12 supplemental compiled/source copies were preserved
  before starting another SwiftPM command. The supplemental manifest hash is
  `6762c13c461576d3516849f7d7974ae64f3c9e5f0b0c88338b4fc90a39db9ec5`.
  Its PE and four generated Swift files match the focused95-v2 copies byte for
  byte; that identity alone is not complete build or loaded-image provenance.
  Complete current-Quick source membership and quoted Swift Testing alias
  reconciliation are separate work, not implied by the archive's pass flag.
- Root Full-v3 then ran once on the same clean `060f5c3c` source and index,
  closing `0820d3/session74926 -> 8db70a/0`, retained PS5 PID 21576, after
  1,354.375 seconds. No timeout, termination, cleanup requirement, source/index
  change, or metadata error was reported. Its archived stream contains 5,479
  complete, distinct XCTest pairs: 5,478 passing and the same known material
  skip. The common portable step accounts for 17 cases; the 277 CoreLogic
  shards account for 5,462. All 278 invocation multiplicities match, and the
  stream contains 134 Swift Testing starts and passing terminals with footer
  total 134. The source-bound full case/alias audit remains separate; neither
  aggregate totals nor generated registration counts substitute for it.
  Full also passed its CoreLogic evidence-completeness step, debug and release
  builds, five retained screenshots, and the gallery gate. Archive `4e3ec5/0`
  produced 193 files with no missing inputs or issues, at
  `artifacts/goal-seventh-root-full-v3-archive/validation-full.json`
  (2,506,246 bytes, SHA-256
  `ec2a2c3d96985a033dcfbf90aa07f52dbfb720f49e95fd6c4a78b427d0447ade`).
  Read-only pixel recomputation found all 85 comparisons within the unchanged
  limits: 84 have identical RGBA pixels; `state-toggle-hover` has maximum
  channel delta 8 and no pixels exceeding the channel tolerance. This is not
  85 exact matches. The five 1280-by-720 retained images were opened and
  reviewed: outputs are nonblank and readable, with lower content clipped at
  the viewport edge. Frame/debug output visibly differs in rounded corners and
  material rendering; reviewing it does not establish equivalence with scenes,
  native presentation, interaction, Narrator, or hardware pacing.
  Supplemental copy `e8319e/0` preserved 568 files before another SwiftPM run:
  nine compiled artifacts, three source files, and 556 journal JSON files.
  Its manifest SHA-256 is
  `9f15eb8d4ab0030b172235699e1ec3630bee7d2dbbd2bfc1db3eb967af97df03`.
  The journal stores 5,462 distinct CoreLogic rows (5,461 pass, one skip, no
  failed/unfinished/repeated rows); copied arithmetic is not independent proof
  of the expected session or raw case identity. Parent review is recorded in
  `artifacts/goal-seventh-root-full-v3-parent-review-v1.json`, SHA-256
  `1faf19cb1c5daea7f55fda1d58a69a90daa1b74d2e0235b90753485ed3ee727a`.
  The first supplemental admission (`a8b0e6/1`) rejected a parent-authored
  multi-token tool-receipt field before copying anything. That input and refusal
  are preserved; only that field was corrected to actual tool ID `8db70a`.
  A later report-only assertion (`29f798/1`) incorrectly expected all 85 pixel
  pairs to be exact and stopped before writing. The corrected report retains
  the observed 84-exact/one-delta-8 distinction. Neither event reran validation,
  changed an image/threshold, nor rewrote a failed workload outcome.
- The proposed quoted Swift Testing name resolver passed 87 finite pure
  fixtures once (`912495/0`), including all 240 expected-field comparisons,
  complete legacy alias maps, ambiguous/unsupported names, and full lifecycle
  records. Failed and skipped synthetic outcomes cannot acquire a passing
  decision. The helper joins all 134 bound declarations before adding exact
  quoted names; an unknown, escaped, interpolated, or inconsistent label in
  any peer withholds all added quoted aliases. It does not infer names from
  observed logs or normalize their spelling. Candidate hash
  `f9171ef8d4b5f66c335107ae959fbfcad4ef88d8a7bce1195058e870fe090e02`
  and all five fixture inputs were unchanged after actual closure. The result
  hash is `3b523e95ffc5ed87d6f5cea65c819acbcad6f78eeadd3c9f8d07c2921b8f499e`;
  parent receipt is
  `artifacts/goal-seventh-quoted-label-fixtures87-parent-closure-v1.json`.
  These are pure checker controls, not a historical audit rerun, Swift Testing
  macro-registration proof, native behavior result, or current-Quick verdict.
- A passive follow-up on hosted C7 run `33195239563`, attempt 1, independently
  reproduced ten selected image comparisons from existing PNG bytes. The
  archived result is still 18 passing and 67 failing of 85 at the original
  thresholds. For those ten pairs, HTML baseline pixels match immutable C7 Git
  baselines and HTML current pixels match the archived current PNGs. This is
  neither an 85-pair recomputation nor a new render or complete test census.
  The proven two-fixture identity is hosted normal C7 output equals hosted C7
  V1 diagnostic output for `stepper` and `symbol-palette`. It is not a local
  MDL2 reproduction. The older local `1ce6b9a` V1 records identify Fluent Icons;
  hosted V1 associates MDL2 with particular bitmap/scene references, without
  proving final visible-pixel ownership or ordinary-text faces.
  Stepper's maximum delta 242 is in its label; 48 label and 31 chevron pixels
  exceed tolerance. Symbol-palette has 1,429 text and 494 icon-cell pixels over
  tolerance; its sparkle and globe cells are identical. Sparkline differences
  are confined to its header, while its chart, the gradient-path fixture,
  slider, divider strip, and disabled-toggle switch regions are unchanged.
  The donut is explicitly not glyph-only: its ring mask has 983 differing
  pixels, 874 over tolerance. A one-pixel horizontal comparison leaves 185
  differences, including 26 over tolerance; this is not exact translation or
  evidence that fonts caused the displacement. Earlier classic-override and
  local diagnostic cohorts remain separate and cannot supply C7 causality.
  The frozen 66-payload report packet is
  `swau-c7-font-region-analysis-x5blpk9l` under the OS temporary directory;
  its manifest SHA-256 is
  `404202d916e0ac17745a3df4c48070e60a41daaad9642eeab4dcd370ebd9283f`.
  Fresh exact-HEAD comparisons are required before any further diagnostic.
  No baseline, font installation, threshold, or workflow was changed.

The separate image cap/stretch/tile proposal completed one owned product-only
debug build (`1444a3/session37792 -> 392ccf/0`, retained PS5 PID 52784). Its
production tree is `70377826efa25a8c1ad9ac35a50cacd0468a4456`, with all 170
source files and the private index preserved; the compiler reported 148.86
seconds and the enclosing caller 152.234 seconds. This build did not type or
run tests, compile HLSL, launch the app, or verify GPU pixels. The proposed next
selection is 71 methods: 61 CPU, two non-skipping checks compiling the exact
production SM5/SM4 strings, and eight GPU methods which must not skip. It covers
50 added and three changed test methods plus 18 unchanged guards/regressions.
The existing WARP helper can convert attachment or shader failures into skips;
those cannot count as GPU/shader coverage. Legacy shader compilation and pure
route checks would still not prove legacy attachment, presentation, or pixels.
The 128-byte image primitive and admitted integer-cap subset remain owned source,
not integrated root support or native SwiftUI conformance.

Independent source review also read all 18 proposed dashboard loader tests and
their helpers. It found no additional confirmed API, ownership, preservation,
or vacuous-hover defect, but retained an important native boundary: the current
blocking Win32 message loop does not service arbitrary Swift MainActor tasks,
and the candidate starts its loader in a MainActor Task. The nil-HWND test
fallback therefore cannot establish native load/retry/cancel usability. This
is a source-inferred limitation, not a reproduced native failure or a test run.
Existing observed-model repaint and close-specific posted-message paths do not
supply a general async service delivery bridge. That gap stays open under the
state/task and working-template requirements; no Windows-only demo workaround
or private executor hook has been introduced.

The separate pure245 preservation controls ran once and failed naturally:
caller `3561f0/1`, child PID 56492, child exit 1 after 2.838275 seconds, complete
stdout/stderr closure, and no timeout or termination request. The observed
result is 244 passing controls and one failed postcondition,
`sample-qpc-6999999999-just-below-cutoff`: acceptance was true as expected, but
`remainingSeconds` did not match its expected value. The failure is not replaced
by the earlier accepted pure279 cohort. No DATA writer, preserver, final writer,
native collector, compiler, or previously denied sealer was invoked afterward.
The original 60-second clock expired; subsequent authorized preservation is
passive, explicitly late, and cannot qualify that original phase. The exact
numeric cause still requires review before any source or fixture correction.

These completed local gates do not qualify the unrun owned-source proposals,
native service delivery, macOS conformance, timing targets, or the remaining
baseline API surface. The grouped push and fresh exact-commit hosted CI result
are still pending at this checkpoint. All nine original completion gates remain
open; later evidence must be appended without replacing these historical facts.
