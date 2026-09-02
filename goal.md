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


### 2026-08-29: pushed 3fcdf14, complete Quick reconciliation, and preserved compile failures

The previously pending grouped push completed: `c7e7987..3fcdf14` contains 19
commits, pushed together by `ad579c/0`. The subsequent checkout was clean and
synchronized with `origin/main`. The pushed commit is
`3fcdf14a4ef83ac94e3decc437030cd99402b358`, tree
`18d151a2f8ffd5f4a40e27de129d1c2a620c924b`. Local Quick and Full still belong to
`060f5c3c689980c5b2156c12d81a571c094a0d89`, not the later commit. The only
intervening tracked change is the appended goal ledger; source, tests, package,
scripts, and reviewed gallery baselines are unchanged.

Fresh hosted runs are associated with that exact pushed commit and attempt 1:

| Workflow | Run | Observed result at this checkpoint |
| --- | --- | --- |
| Portable core CI | [33250300359](https://github.com/mweinbach/swift-windowsui/actions/runs/33250300359) | Passed on macOS 15 and Ubuntu 24.04; isolated public products, portable tests, and the same-source macOS demo build passed |
| SwiftUI baseline candidate capture | [33250300319](https://github.com/mweinbach/swift-windowsui/actions/runs/33250300319) | Job succeeded, but the artifacts remain candidates, not conformance acceptance |
| Windows CI | [33250300330](https://github.com/mweinbach/swift-windowsui/actions/runs/33250300330) | Architecture checks passed; Full remains in progress; the separate Quick job was skipped |

The successful macOS capture explicitly reports the material candidate as
inconclusive. Its API ledger remains unreviewed, and the captured/compiled RGB
candidate does not establish declaration, source, behavior, or release review.
The SDK export reports 134,147 identifiers and macOS 26.5 target triples. The
log names Xcode_26.6, host macOS 26.6.1/25G76, and runner image
20260824.0517.1, but this check did not recover exact SDK, Xcode, or compiler
build IDs. It does not silently replace the previously pinned reference.
The separate small RGB synthetic artifact reports 126 cases and 495 assertions
under PowerShell 7.6.4; it does not execute native Swift Color. The roughly
300 MB candidate ZIP was not downloaded merely to infer SDK identity.
Windows gallery artifacts and a fresh hosted/local comparison remain pending.

The new passive Quick-v3 audit ran once and completed naturally:
`bd404b/0`, 1.1004687 seconds. All 13 explicit evidence checks passed, including
the complete 5,479 generated XCTest identities and async adapters, the exact
167 ordered invocation scopes, and all 92 ordered agent steps. The raw case
results reconcile to 2,650 XCTest passes and the one specific material skip,
plus nine Swift Testing passes. There are no missing cases, failed cases,
duplicate/unclosed lifecycle issues, unresolved quoted labels, or legacy
parser issues in this run. The material method has both its start and skip
terminal; its reason text was not independently parsed. All 18 newly added
List methods remain outside Quick's selection and rely on their separate
focused and Full coverage.

The audit uses the complete 134-declaration Swift Testing source table for
quoted aliases and keeps 391 relevant raw/index source associations. It does
not infer macro registration, loaded-image origin, native Swift process exits,
or descendant closure. The previous failed Quick audit and its 38 quoted-label
issues are unchanged. An initial parent intake check, `944cbf/1`, incorrectly
listed `write_failure` among ten unchanged helpers; it stopped before creating
the capsule or invoking an audit. Read-only diagnosis `bfd92d/0` established
the correct ten helpers, including `pin_matches`, and the exact reviewed
metadata-only change to `write_failure`. Corrected intake `6c215d/0` changed no
candidate source, input, or parser. This intake refusal remains preserved.

The resulting audit is
`artifacts/goal-seventh-root-quick-v3-audit-v1/audit-result.json`, 14,629,290 bytes,
SHA-256 `8bcdc0674b6ce38e99030b9f70a5d37cc7da957e5277de394645da5018b06431`.
Parent check `528ce9/0` rehashed its output manifest and all 37 non-PE inputs;
the final manifest exists and no failure record exists. The parent closure is
`artifacts/goal-seventh-root-quick-v3-audit-parent-closure-v1.json`, SHA-256
`84abe23a30b1c6c99ab6d1bd72714e503e8a9302f5bb08a124bbde08f358ad56`.
The separate Full case/journal audit remains source preparation, not execution.

Two isolated proposals reached test compilation failures. Neither changes the
passing root Quick/Full results or qualifies the proposed functionality:

- **Calendar/layout175:** `e6ca45/session68987 -> 6e2cc1/1`, retained PS5 PID
  33828, stopped during the first partition after 170.063 seconds. The new
  assertion in `AbsoluteLayoutSizingTests.swift:268` passes `Bool?` directly
  to `XCTAssertTrue`. There were zero case starts or terminals; all 175 selected
  methods and the remaining 16 partitions are unrun. This is a compile failure,
  not a failed assertion. Fixed capture `1c9635/0`, raw capture `42a8d3/0`, and
  end preservation `e5b223/0` retain 793 source files, the private index, 96
  named tool files, six raw outputs, and 66 unused output paths. Only three of
  eight fixed build-text files exist; the four generated Swift files, link
  list, and test PE are absent. The 5,472-method source expectation is not
  generated-registration evidence. Independent lean reconciliation `15781a/0`
  confirms the zero-event/175-unrun result. The 43-payload failure seal is
  `swift-windowsui-date-picker-calendar-sizing-001f-11orizwq/repo/artifacts/date-picker-calendar175-compile-failure-v1/MANIFEST.json`
  under the OS temporary directory, SHA-256
  `d1918948c936502c26ef4f12b8a6b8d44c4caa238f0bf5bcd066cd0389b98a27`.
  A separate source successor may compare the optional value with `true`,
  preserving failure for both nil and false; no repaired runtime is claimed.

- **Image cap/stretch/tile test typing:**
  `171a83/session88144 -> 962a6f/1`, retained PS5 PID 20220, completed after
  247.75 seconds. Two new fixture expressions exceed Swift's type-checking
  limit: `ImageSamplingPlanTests.swift:334` and
  `WinSwiftUIBitmapResizingTests.swift:42`. Each diagnostic appears in 24
  compiler jobs; those are two source issues, not 48 separate failed tests.
  No tests, test listing, application/test executable, HLSL compiler, or GPU
  assertions ran. All 740 guarded inputs and the private index are unchanged;
  all 19 retained calls closed naturally, with 18 Git exits of zero and the
  PS5 compile exit of one, without timeout, intervention, or overrun. The prior
  product-only build and its evidence remain unchanged. The 71-method runtime
  selection remains unrun. Parent passive capture `fe1696/0` preserves 25
  files/6,226,681 bytes and again finds only three build metadata files, five
  missing generated/link files, and no test PE. Its manifest is
  `codex-image-resizing-impl-69edab8884264c04b3c36c91eea64b45/early-test-typing-v1/passive-capture-v1/CAPTURE.json`
  under the OS temporary directory, SHA-256
  `22e817a905b80b1528eea01991100a39906092e3dff5ef7635c8773417fedf78`.
  Follow-up source work must simplify the two fixture expressions while
  preserving their data, colors, expected pixels, production code, and tolerances.

The material214 fixture successor has begun one separately bounded attempt,
`a7a079/session31979`, after fresh source/tool checks and preservation of the
preexisting generated material PNG. It has no outcome at this checkpoint.
Other prepared source work includes 14 animated List completion tests, a
seven-path Arc/CPU connector join with its 12 Arc prerequisites and eight new
connector tests, and a standalone public-API native scheduling probe. None of
those preparations constitutes a current-root runtime pass. The probe does not
implement the proposed host ownership change or resolve UIA, modal, renderer,
or shutdown requirements.

The pure245 failure also remains failed: its historical projected floating
value was not logged and is still unknown. Reviewed source now proposes
subtracting integer QPC ticks before division, retaining the original `1e-7`
oracle, all cutoff/reserve guards, and exact comparisons. Optional diagnostic
text records finite numeric values and types on a future mismatch. No corrected
control run, renewed old clock, native collector, or previously denied sealer
is implied by that source proposal.

No baseline, font, visual threshold, original requirement, or completion gate
was changed. All nine original gates remain open. Later results must add to
this checkpoint rather than replace its recorded failures or qualifications.


### 2026-08-29: current geometry validation, completed CI findings, and isolated corrections

Root commit `3fb9e55abe65a2d1dd615b7d360374dc384deb25`, tree
`8bca33938ec9fd7ece8fd3bd2191d38b65caa205`, integrates the seven-path Arc and
shallow stroke-join change. Arc stores normalized geometry in the live node's
positive border-inset paint rectangle, rather than applying placement and
scale twice. Collapsed inner dimensions produce an empty path. The CPU stroker
keeps the triangle joining adjacent segment bodies even when the additional
round or miter exterior falls below the existing 0.1-pixel threshold. Paint,
callback ownership, public `Arc.path(in:)`, promotion policy, and coverage
tolerances are unchanged. Twelve Arc tests and eight connector tests were added;
all 472 previous test files and unrelated source were preserved at intake.

Architecture checks passed before and after intake, and strict formatting passed
for all five changed Swift files. Commit `3fb9e55` follows the goal-only
`33a9b21`; neither was part of the earlier push to `3fcdf14`. The current source
inventory has 5,499 XCTest methods, with 5,147 async registrations and 352 direct
registrations, plus a separate 134-declaration Swift Testing inventory. These
source counts are not themselves executed-test counts.

Fresh root Quick completed naturally:
`bfc6c1/session28545 -> e63270/0`, retained PS5 PID 25096. Source preservation
passed and no operator cleanup was needed. Archive `d2d94b/0` preserves 12 files;
the validation manifest is
`artifacts/goal-eighth-root-quick-v1-archive/validation-quick.json`, SHA-256
`58ffe18f1271a94c74d715bff9dbe3eefd2c0e038fbeb4b2ed7051617a0fd301`.
Supplement `b8ed22/0` copied the nine compiled outputs and three stock source
files before another root SwiftPM workload. The separate passive case and
registration audit remains pending at this checkpoint. Source rematching shows
that the 20 new methods do not enter Quick's unchanged selection; their focused
runtime result follows below.

The focused geometry run then completed naturally:
`0e25f4/session12302 -> ddf8ee/0`, 118.641 seconds, with all 20 retained PS5
children exiting zero. The runner reports exactly 350 passing cases: 319 XCTest
and 31 Swift Testing, including all 12 new Arc and eight new connector methods.
There were no failed, skipped, missing, duplicated, or unrun selected cases in
its recorded result; source preservation passed and stopReason is null.
The calls use the original exact non-sharded filters. A separate source-only
check showed that substituting the generic sharded path would broaden this
selection to 610 distinct cases in 29 calls, including 18 duplicate occurrences;
that broader workload was not executed.

Fresh admission `c615e8/0` checked all 800 source files, the index, ten tool/helper
pins, the 48-member runner packet, and all 84 unused output paths. After actual
closure, fixed capture `e88231/0` saved 89 stable files, including all 63 raw
run files and four generated Swift registration files. Source, index, tools,
and output-presence observations remained unchanged before and after capture.
All required live build reads are complete; no test PE was read or copied by
that capture. The capture manifest is
`swift-windowsui-root-arc350-capture-3fb9-v1-dbc5a4f1ce864b0d8b6567b67e2dbb5a/outcome/CAPTURE.json`
under the OS temporary directory, SHA-256
`06cbcc3881e3deaa2b7701cfa7a11445b4bfa8c365736ffd764f8f8fb345dcf7`.
Independent reconciliation of the copied 5,499 registrations and 350 outcomes
is still pending. Neither the historical 342-case failure nor the earlier
owned 350-case pass has been relabeled as this current-root result. This focused
pass does not establish native SwiftUI Arc API parity, general transforms,
antialiasing parity, full-image equality, or hardware pacing.

The older local Full-v3 passive audit is now complete on its own `060f5c3c`
source: `fc790f/0`, 2.546 seconds, with all 14 acceptance checks true. It joins
all 5,479 generated XCTest identities and wrapper flags, 278 ordered invocation
scopes, 5,478 passes and one named material skip, 134 Swift Testing passes,
27 ordered agent steps, and the 277-shard Core journal. No new or legacy parser
issues remain. Parent acceptance is recorded in
`artifacts/goal-seventh-root-full-v3-parent-audit-acceptance-v1.json`, SHA-256
`a48df6c5ffa4d23785633b10b0db3102d243a20d61882066bba5c783599efc48`.
This is a completed audit of preserved evidence, not a rerun or qualification
of later Arc source. Native process exits, loaded-image provenance, and
independent authentication of the supplied session nonce remain outside it.

Hosted Windows CI for the pushed `3fcdf14` has also finished. Run
[33250300330](https://github.com/mweinbach/swift-windowsui/actions/runs/33250300330),
attempt 1, failed the gallery gate: 18 of 85 entries passed and 67 failed.
Twenty failures exceed both unchanged thresholds, and 47 exceed only the
maximum-channel threshold. Fresh comparison of the retrieved artifact confirms
the result. All 85 new hosted PNGs are byte-identical to the separately preserved
C7 hosted PNGs; this establishes persistence, not the cause of the differences.
The source/decoded-log join observes 5,475 XCTest passes, four skips, zero
failures, and 134 Swift Testing passes. The four skips are the known material
residual and three unavailable Segoe UI Variable cases. The Core artifact covers
5,462 cases; the other 17 Portable outcomes come from the completed job log.
This must not be reported as the local Full run's single-skip environment.

The hosted pixel differences include text, icons, and a nonglyph donut region.
The donut's best tested integer shift still leaves differences. Font availability
and versions differ between the recorded hosted and local environments, but
the baseline's original font profile and per-glyph loaded font bytes remain
unreviewed. No blanket font cause, complete observer/wrapper provenance,
compiled-registration attestation, or D3D11 presentation result is inferred.
The same-push Portable workflow passed, including the macOS same-source demo
build. The macOS baseline workflow succeeded as a candidate capture only:
materials remain inconclusive, the 134,147-identifier API ledger is unreviewed,
and exact SDK/compiler/Xcode build IDs were not recovered from the inspected log.
No newer reference was silently substituted. Parent `05cd2e/0` rehashed all
133 files in the sealed CI packet; its final manifest SHA-256 is
`1d3a2716d00926c079b7cffcb6300ac1ae4f2f774c147717ab9e8b498b8b35af`.

The isolated material214 attempt recorded as in progress in the previous entry
has failed: `a7a079/session31979 -> a2fbf6/1`, 432.484 seconds. Copied evidence
reconciles 198 XCTest passes, one known skip, one failure, and 14 Swift Testing
cases unrun after the ninth call stopped the run. The failed method is
`D3D11MaterialDrawingGroupBackdropTests/testReplayedBackdropSourcesRejectCapacityAndRecover`.
Its partial-prefix comparison obtained match ratio `0.9992897727272727` instead
of 1 at tolerance 2: three of 4,224 pixels exceeded tolerance. The failed GPU
pixel coordinates and channel bytes were not captured and remain unknown.
Later assertions in that method passed, but the complete method remains failed.

Source inspection found that this reference compared 1,024 separate 2x2 quads
against one 64x64 CPU quad. Their derivative coverage at the boundary differs,
so that reference is not equivalent to the admitted prefix. A distinct successor
`7359e4630aec4c63a816c98260f9877cdbfdb58d` changes only that test reference to
the matching 32x32 grid and independently checks all 16,896 expected BGRA bytes.
The existing tolerance, exact match ratio, capacity/recovery/resource assertions,
all production source, and the other 5,485 test bodies are unchanged. Contracts
and strict formatting passed. Its 214-case runtime selection is still unrun;
the earlier failure is preserved, not retrospectively accepted.

Other isolated source corrections also remain separate from root validation:

- Calendar/layout175 now compares the optional Boolean with `true`, preserving
  failure for nil and false. Only eight bytes changed in the previously
  uncompilable assertion. The private successor preserves all other source,
  all 175 selected identities, and its 5,472-method source inventory. Contracts
  and formatting passed; the new 175-case run remains pending.
- Image cap/stretch/tile fixtures replace two costly type-checking expressions
  with explicitly typed construction while retaining data, expected pixels,
  production code, and tolerances. Source census `ee2aec/0` derives 5,507 XCTest
  methods and 138 Swift Testing declarations for that private source. The four
  additional Swift Testing declarations are explicit GPUISceneBridge additions;
  the historical 134-declaration reference remains intact. All 474 source/package
  pins and the original 71-method selection are preserved. This is source
  inventory evidence only; corrected test compilation and runtime remain pending.
- Animated List focus has 14 new tests and a 125-case focused plan. Its private
  source has 5,493 XCTest methods. Compilation and runtime are unrun; it does
  not make the public List lazy or complete the separate state/task bridge.

The standalone native scheduling probe's first compiler attempt stopped before
any C, Swift, or link step: `946878/1`, 1.6675392 seconds, retained PS5 PID 15572,
natural exit 1 without timeout or intervention. The diagnostic is Visual Studio
developer-environment initialization failure. Fixed capture `55c36f/0` preserves
the four emitted evidence files, explicitly records the absent compiler outputs,
and verifies all 27 inputs and two anchors unchanged. No native probe ran.
Source diagnosis found that the launcher supplies `VSINSTALLDIR` without the
terminal separator expected by installed Visual Studio extension scripts.
This is a source-supported explanation, not a recorded per-extension trace.
A separate reviewed successor adds that separator and updates the matching
child guard; probe sources, compiler arguments, and limits are unchanged.
Its corrected compiler attempt completed naturally:
`0ff680/session58703 -> b0de89/0`, retained PS5 PID 39948, with no timeout,
intervention, or capture/cleanup errors. Fixed capture `1b2570/0` verifies all
three exact compiler/link steps and all four output pins, with all 27 inputs
and two anchors unchanged. Its capture SHA-256 is
`766fe9d6b8df7a48b395919a8099390af9184c8dadd13a841dbb7dab8fd3319f`.
The standalone C/Swift program therefore compiles and links; its native run
is still unperformed. Even a successful standalone probe would not implement
the production host's UIA, modal, renderer, input, or shutdown boundaries.

The corrected pure245 control flow has now passed: 245 of 245 fixed synthetic
fixtures, comprising 30 accepted and 215 expected-rejected cases over 30 selected
definitions. The retained child and all ten tools exited zero. Completion was
8.2837628 seconds on its original 60-second clock. The correction subtracts
integer QPC ticks before division, retaining the original `1e-7` comparison and
all cutoff/reserve guards. Independent review and parent `05cd2e/0` preserve
all nine output copies and the 13-member postrun manifest. The mismatch-only
numeric diagnostic branch was not exercised. The original 244-pass/one-failure
attempt and its unknown floating value remain unchanged; no denied sealer,
native performance collector, or product qualification follows from this pass.

No baseline, font, visual threshold, API baseline, original requirement, or
completion gate changed. All nine original gates remain open. Each later
integration and result must add its own source and validation evidence.

### 2026-08-29: completed geometry audits and a successful native scheduling probe

This checkpoint adds evidence to the preceding checkpoint; it does not replace
the original requirements, erase failed attempts, or close any completion gate.
The root is `9984a1022306b78cd1637584981fa3ff02e4d46f`, with documentation
following the tested geometry implementation at `3fb9e55abe65a2d1dd615b7d360374dc384deb25`.

#### Current Quick and geometry evidence is now fully reconciled

- The one current Quick audit closed successfully at `a609c7/0`. Its saved
  evidence contains 2,650 passed XCTest cases, the one known material skip,
  and nine passed Swift Testing cases. All 5,499 generated XCTest registrations
  match the frozen source, including 5,147 async and 352 direct registrations.
  All 92 ordered script steps and 167 evidence scopes reconcile. The 20 newly
  added Arc/stroke tests were outside Quick's selection and are covered by the
  separate run below; unselected cases are not counted as runtime passes.
- The independent copy-only geometry audit closed at `e5d3bf/0`: all 350
  selected cases passed exactly once, comprising 319 XCTest and 31 Swift
  Testing cases across 20 successful serial script calls. There were no
  failed, skipped, missing, duplicate, or unrun cases in that selection. The
  full generated registration also matches all 5,499 frozen XCTest identities
  and their async/direct flags. Capture postchecks preserved all 97 captured
  members and all 92 files bound to the audit. Sealing closed at `be5933/0`.
- These results remain attributed to source `3fb9e55` and tree `8bca339`.
  Subsequent documentation does not retag them as tests of a different code
  revision. They do not establish full-suite execution, image parity, native
  interaction, hardware frame pacing, or the identity of a loaded binary.
  The earlier 342-case failure remains a failure of its own source/attempt.
- Durable local references include
  `artifacts/goal-eighth-root-quick-v1-audit-parent-acceptance-v1.json`,
  `artifacts/goal-eighth-root-quick-v1-audit-v1/summary.json`, and the sealed
  `audit-results-v1` directory beside the previously recorded Arc350 capture.

#### Public dispatchMain can service MainActor work beside a native window loop

- The corrected standalone compiler attempt, already described above, was
  followed by exactly one native execution: `b23104/0`, with direct native
  process 28568 exiting naturally with zero. Its complete fixed capture closed
  at `fafeed/0`; parent verification of the capture and four saved outputs
  closed at `46a650/0`. No timeout, termination, cleanup error, or finalization
  overrun occurred, and all 19 fixed inputs plus two controller anchors stayed
  unchanged.
- The 20-row trace satisfies all 14 required causal markers: creation of a
  hidden native window, two native-message/continuation round trips, resumption
  after `Task.sleep`, resumption after an external worker completion, window
  destruction, checked native-thread join, and the final success marker.
  The existing first compiler failure remains separately preserved.
- In this run the entry thread was 55816, the native HWND owner was 22796,
  the MainActor markers used thread 31292, and the external worker was 44408.
  Every MainActor marker reported `Thread.isMainThread == false`. Therefore
  checking the process's main-thread identity cannot substitute for checking
  Swift actor isolation. The observed single actor thread is not a promise
  that all future actor work uses that same OS thread.
- This proves the scheduling premise for the standalone probe only. The
  application host has not adopted this loop arrangement. Input delivery,
  synchronous UI Automation results, IME caret queries, modal operations,
  renderer ownership, and close/destroy acknowledgements still need an
  integrated design and validation. The trace's unchanged echo count across
  awaits does not prove complete message-loop or CPU idleness.
- The capture is under
  `Temp/native-mainactor-run-capture-v1-3fcdf14-20260829-84c12e`;
  `artifacts/goal-eighth-native-probe-parent-acceptance-v1.json` records the
  parent's copied-output verification. Native `.task`, AsyncImage phase
  publication, and live model-loading behavior remain unqualified until the
  real App path is fixed and exercised.

#### The corrected image source reached linking but did not produce a test executable

- The image test-typing successor closed at `dc9a12/1` after 605.109 seconds,
  following launch `ace7f0/session70641`. The stock PowerShell child exited
  naturally with one. The copied log reports `lld-link` failing to open the
  generated `swift_windowsuiPackageDiscoveredTests.swiftmodule.o` with
  `invalid argument`, followed by the linker command failing. This is a new
  link-stage failure, distinct from the earlier two fixture type-check errors.
- All 740 frozen source files remained unchanged. The raw Git index changed
  from its recorded initial hash, so the controller's strict after-check also
  failed. The original raw index bytes were not saved; only the initial hash
  and the actual after-index are available. Its changed field and cause are
  therefore unknown. Neither a source mutation nor a harmless metadata-only
  change is inferred from the hash mismatch.
- Fixed capture `2e918a/0` preserved all eight requested generated/metadata
  texts, 52 text/control copies, and the actual index. The test executable was
  absent. All 71 selected runtime cases remain unrun. The capture and subsequent
  preservation check are complete; no further reads of that live build are
  needed.
- The next proposed experiment changes only the private checkout prefix to a
  shorter path while retaining the `repo` leaf, all source bytes, test selection,
  flags, and rejection policy. Path measurements come from saved copies; path
  length is a hypothesis to test, not a proven sole cause. The next admission
  must save the actual before-index bytes as well as its hash. No OS long-path
  setting, tolerance, baseline, or source behavior is changed to accept this
  failed attempt.

The next runtime work remains the corrected material oracle, date-picker
fixture, and animated-list compilation, followed by source integration and
combined validation. A private captured-pointer input slice has also passed
contracts and formatting but has not been compiled or executed. None of these
prepared changes is represented as shipped or as satisfying a release gate.

### 2026-08-29: pointer scale and lifetime capture integrated, runtime checks pending

The root now includes the reviewed four-file captured-pointer slice from private
commit `f4ab758b37cbc914c51be80629b32cdb5409fdc6`, applied on `a722d66`.
It changes `Win32Host.swift`, `App.swift`, and `PlatformArchitecture.md`, and
adds `Win32CapturedPointerInputTests.swift`. All existing test files and the
previous goal text are preserved.

Native pointer move and left-button callbacks carry the coordinates and display
scale captured at their existing delivery boundary. A per-window identity,
close-lifetime identity, and sequence bind that value to one synchronous
delivery. The retained host consumes it before callbacks can replay it; nested
callbacks save and restore the enclosing frame, including its consumed state.
Legacy and neutral delegates retain their synchronous physical-coordinate API.
This does not move HWND ownership or change the application message loop.

The 12 new async XCTest methods cover captured versus current DPI, press/release,
fractional and invalid scale rules, nested callbacks before and after
consumption, replay, stale or inactive contexts, wrong-window/host delivery,
closed hosts, and legacy/neutral forwarding order. These tests are authored
but remain unrun at this checkpoint. Real create/destroy, pre-capture native
focus/capture reentry, cross-thread delivery, UIA, and IME remain separate work.

Root contracts passed before intake (`171263/0`) and after intake together with
strict formatting of all three Swift files (`1075a1/0`). Parent verification
`76c24b/0` confirms byte-identical Swift source and identical canonical document
content. Its receipt preserves the earlier data-check failure caused by the
frozen document's mixed line endings; no implementation or test was changed to
resolve that bookkeeping mismatch. The source receipt is
`artifacts/goal-eighth-captured-pointer-intake-after-v2.json`.

Compilation, focused pointer/host regressions, and combined validation are still
required before pushing this source. No existing gate is marked complete.

### 2026-08-29: UI Automation queue recognition and immutable queries

Two independently reviewed source slices are joined on `4fdfa2d`; this is
implementation progress, not native scheduling qualification. The first comes
from private `e390a030` (patch SHA-256
`63033234bbd64a9b052704f8f07b87373eaede1761b330b836b0f68ec3ddd5eb`).
The second comes from private `e1fd44e8` (patch SHA-256
`37bef0755f2ea0ef0cf11ef3124a1d784bb55fcab353b22b9ebf72702ad95bae`).
Both apply as context changes; the captured-pointer implementation remains intact.

- UIA callbacks already executing in the main dispatch queue's target hierarchy
  can now take the inline route instead of synchronously dispatching to that
  same queue. One private, immutable process-lifetime owner installs the queue
  key once. It carries no provider, window, registry, or other UI state. The
  existing thread shortcut remains, and **both routes retain
  `MainActor.assumeIsolated`**. Queue recognition does not replace actor checks.
- Queries now compute through a checked-Sendable `UIAQuerySnapshot` containing
  copied value elements. The twelve existing query callbacks still obtain a
  fresh projection at their original call sites; the separate SetValue guard
  remains the thirteenth projection call. Runtime-ID lookup remains projection
  free. First-match order, selection ancestry, hit-test depth ties, missing
  values and C sentinels are preserved. This introduces no shared query cache.
- Four new async lifetime tests author six queued COM scenarios: main and
  main-targeted name queries, worker success and revocation, and successful and
  failed Value actions. Twelve further async tests cover immutable transfer,
  query ordering and defaults, fresh bridge values, and selection count/fill
  shrink, growth and empty results. The existing lifetime tests are retained.
- Parent contracts before and after the joined change, strict lint of all four
  Swift files, and source comparison passed. The intake receipt is
  `artifacts/goal-eighth-uia-combined-intake-v1.json`. **Compilation and all
  sixteen new tests are still unrun at this checkpoint.** A successful test
  must actually observe main-queue context with `Thread.isMainThread == false`
  before the newly needed inline branch can be qualified.
- Actions remain synchronous with their existing results, callback pinning,
  native/provider lifetime and C ABI. No application entrypoint, HWND owner,
  message pump, modal behavior, renderer ownership or teardown policy changes.
  Production task progress, blocked native-to-actor callbacks, Narrator and
  native presentation still require their separate implementation and evidence.

The local `origin/main` tracking ref was observed at `4fdfa2d` during this
intake, with an update-by-push reflog entry. This observation is not a fresh
hosted-CI result or a test result for the pointer or UIA additions. All nine
original completion gates remain open.

### 2026-08-29: enclosing-backdrop groups joined after focused execution

The fourteen-path material implementation is integrated as a context patch
from `46d22ff` to private `7359e463`, on top of root `add2485`. Patch SHA-256:
`7e671b8214b9224a3aea445e5f12dc356bc6f167aea97b826d2926543fdbebc6`.
Separate Graphics/runtime and D3D11/test source reviews were clear. The root's
newer List, Arc, captured-pointer and UIA changes remain intact; Runtime gains
only the four-line optional `surfaceSize` cache-key addition. Ten other changed
production/test files match the qualified private endpoint's Git blobs exactly.

Eligible plain drawing/compositing groups now retain a scene with explicit
`currentTarget` input. Each image occurrence reads its immediate parent's
already-painted prefix in `GPUIScene.presentationOrder()`, including replay
after an outside-only change. CPU copies the bounded parent region; D3D11
copies between GPU textures without rasterizing or reading back the window.
Opacity and clip coverage replace the seeded destination as
`k * child + (1 - k) * destination`, including alpha, rather than blending the
same translucent backdrop twice. Final-attempt glyph atlases and target-size
and snapshot-identity guards preserve deferred replay and resize behavior.

Admission remains explicit: transparent clear, no post-filter, full UVs,
identity 1:1 placement, a nonnegative even device-pixel origin and containment
inside the immediate target. Odd extents are supported. Existing source-count,
pixel and depth budgets remain unchanged; every actual occurrence is charged
before allocation. These limits do not bound all process or driver memory.
Independent content-blur, color-effect and Canvas captures, unsupported
mapping/rotation cases, arbitrary blend modes and native SwiftUI parity remain
open. This capability does not close the full composition or renderer gates.

The isolated material run on `7359e463` completed **199 XCTest passes,
14 Swift Testing passes and one existing named skip**, with all eleven stock
PowerShell calls returning zero. Its independent copy-only audit reconciled
all 214 selected start/terminal lifecycles and the complete 5,486-method
generated XCTest registry (5,134 async and 352 direct methods). All 25 new
material tests passed. The capacity case now constructs the same 1,024 small
quads independently for its CPU oracle and first asserts their expected pixels;
the GPU tolerance and required match ratio were not loosened. Earlier failed
compile and capacity runs remain separate evidence. The remaining
`RenderPassAbstractionTests.testMaterialInsideADrawingGroupBlursNothing` skip
still records the unresolved content-blur arm; it is not counted as a pass.

The audit's final manifest SHA-256 is
`f5dfdb22dc1d8f8f169197f0760e2851bf188e616fc65675572fabdb82320e8f`.
Root intake evidence is `artifacts/goal-eighth-material-intake-after-v1.json`.
Joined-root contracts, strict lint of eleven Swift files and whitespace checks
passed. **Joined-root compilation, focused execution, Full, retained visual
inspection and hosted CI are still pending.** The private WARP-first harness
can fall back to hardware and does not qualify a hardware configuration,
performance, native test-process exit or descendant-process closure. All nine
original completion gates remain open.

### 2026-08-29: bounded first-scene diagnostics for gallery investigation

The reviewed geometry diagnostic from private `722668460` is integrated on
`f374636`, preserving the material target-size cache key and existing List/Arc
changes. Its five-path context patch has SHA-256
`e90c448422f6787fc6867251ea448fb919f88ec4d1667d4262e69819dfd9ec19`.
This adds investigation tools; it does not fix or excuse the 67 gallery
failures observed in the earlier `3fcdf14` hosted run.

The runtime can accept one explicit package-owned capture request. It copies
stored node-local frames, ancestor paths, constrained measurement-cache values
and requested text styles immediately after the first scene paint, before
end-of-pass callbacks. Snapshotter retains that value before its existing
auxiliary frame render. The default path does not traverse for diagnostics;
the source introduces no extra layout, measurement, paint, user callback or
font probe. Overlap, nested/frame-only renders, cached/paced early returns,
pending layout, invalid data and exceeded bounds produce explicit unavailable
results rather than forcing another pass or borrowing later geometry.

The gallery opt-in requires paired directory/invocation flags, a 32-character
lowercase hexadecimal invocation ID, and exactly the existing
`typography-scale` and `canvas-donut` fixtures. It rejects unknown or swallowed
diagnostic flags and bitmap-attribution combinations, keeps the existing
320x240/scale-1/dark/timestamp-zero settings, and refuses output replacement.
Limits are 128 nodes, depth 32, 256 paths, 4,096 path elements and 256 KiB of
encoded sidecar output. The byte cap is not a streaming memory limit. Standard
SecureField display data stays masked; ordinary custom node text is not a
general-purpose secret-redaction boundary.

Scene paths follow `presentationOrder()` and carry scene-local references,
not invented cross-variant identities. Child-pass and gradient-coordinate
coverage remain explicitly unavailable. The donut selector requires unique
center/legend roles and distinguishes the authored Canvas from icon fallback
canvases. Neither that role nor primitive indexes prove pixel ownership.

Contracts before/after integration, strict lint of four Swift files and
independent source reviews passed. The intake receipt is
`artifacts/goal-eighth-geometry-diagnostic-intake-v1.json`. All **22 new async
tests are still uncompiled and unexecuted** at this checkpoint. The planned
causal experiment uses the same built gallery in two fresh children, varying
only the child-local classic-font override while preserving baseline pixels
and comparison thresholds. A font cause, runtime noninterference, native
parity and the hosted gallery gate remain unqualified. All original goal
requirements and nine open completion gates are unchanged.

### Eighth implementation pass: shared Grid tracks joined to the main checkout

The shared-track Grid implementation is now integrated on top of `ebaa8e2`.
Grid and GridRow have distinct retained layout modes. Direct rows share column
measurements, spans consume contiguous logical tracks, and non-row children
occupy a full-width row. Structural Group and ForEach expansion uses the existing
ComponentHost and State installation path. Reconciliation preserves mounted
cell state while updating spacing, direction, and alignment configuration.

Sparse track boundaries avoid allocating an entry for every empty logical
column in a huge span. Width-dependent remeasurement, flexible and unsized
demand, standard alignment, RTL ordering, and bounded after-layout settlement
are implemented. `gridCellColumns` now stores span metadata without changing
authored layout priority. The two former facade tests for stack mapping and
span-as-growth-priority intentionally migrate to these real contracts.

This intake adds 22 retained-layout and 14 facade XCTest methods. The previous
170-method pass belongs to independent commit `73c23ad`; the composed private
commit `69c321d` and this newer root combination are runtime **UNRUN**. A prior
pass is not transferred across those joins. Current root contracts and strict
lint of all seven changed Swift files passed. The ten-path staged delta was
checked against the complete sealed feature patch, preserving newer List,
Arc, material, UIA, pointer, and geometry-diagnostic work. The receipt is
`artifacts/goal-eighth-grid-joined-intake-v1.json`.

[GridLayout.md](docs/GridLayout.md) records the solver's current policies and
remaining differences: equal span-deficit distribution, preserved but unused
layout priority in track negotiation, zero default spacing, the standalone
GridRow HStack fallback, and unresolved merged/custom alignment behavior.
Nested minimum-size propagation and callback-driven reparenting still need
characterization. Literal geometry tests do not establish native layout or
pixel parity. Full generic API compatibility and every original completion
gate remain open; fresh combined execution and retained rendering are next.

### Eighth implementation pass: graphical calendar and shared sizing joined

The graphical DatePicker now builds real retained month navigation and day
buttons, replacing its decorative calendar hint. Its ordinary mounted State
keeps each occurrence's browsed month independent through unrelated rebuilds,
keyed moves, and separate hosts. Accepted selection/calendar/time-zone changes
recenter it; rejected, hidden, superseded, removed, or closed occurrences cannot
authorize escaped button actions. Binding callbacks are revalidated before
writing. Month browsing alone never writes the selected date.

The calendar honors inherited first weekday, calendar, time zone, and locale,
and handles partial-day ranges, exclusive endpoints, leap and short calendar
months, and explicit DST matching policies. It retains pointer/Tab/Enter/Space
button behavior and selected/disabled accessibility metadata. The shared
absolute-layout correction distinguishes positive finite fixed frame dimensions
from ideal preferences, so narrow proposals can size the calendar without
discarding authored fixed dimensions or animated intermediate widths.

The thirteen-path feature intake adds 49 XCTest methods: 35 calendar/control/
mounted-state cases and 14 generic sizing cases. Only two existing DatePicker
assertions migrate from the placeholder size and decorative-square count.
All 175 selected methods passed at private `9f56ad9`, with 17 direct PowerShell
zero exits, no selected skips/failures, and a reconciled 5,472-method registry.
That focused result is not a full suite result or a pass for the new root join.
The parent checked all 146 qualification payload hashes, read the production
delta and all 49 new tests, and verified the staged thirteen-path change against
the sealed cohesive patch. Current contracts and strict lint of ten Swift files
passed. Intake receipts are under `artifacts/goal-eighth-date175-*-intake-v1.json`.

The source is joined after Grid commit `40ec9cf`, preserving its shared tracks
and all earlier root work. Combined execution and retained screenshots remain
pending. [GraphicalDatePicker.md](docs/GraphicalDatePicker.md) records current
Windows selection policies and the still-open graphical clock, grid-arrow
roving focus, localization of navigation action names, full generic API/style
surface, native accessibility, and native pixel comparisons. This slice does
not close any original completion gate or exempt these remaining behaviors.

### Eighth validation pass: pointer UUID collision found and corrected

The first combined Full run on `30737f4` failed during portable-stage package
compilation after 16 preceding validation stages passed. Both the direct
PowerShell process and outer runner returned 1 naturally after 475.047 seconds;
tracked source and index bytes were preserved, with no timeout or cleanup
intervention. No XCTest cases ran. The failed receipts, raw log, and affected
source/tests are retained in `artifacts/goal-eighth-full-30737f4-failure-v1`.

`Win32Host.swift` imports both Foundation and WinSDK. Four unqualified UUID
references in the pointer slice selected WinSDK's GUID alias, conflicting with
the Foundation UUID used by close lifetimes. The window identity initializer
also constructed a zero GUID instead of a fresh Foundation identity. All four
references are now explicitly `Foundation.UUID`, preserving the intended
per-window and per-lifetime identity checks. No test oracle, filter, skip, or
acceptance threshold changed. Contracts and strict lint passed after this fix;
the corrected combined source still requires fresh compiler/test/render
validation. The failed run is not counted as a partial release pass, and every
original completion gate remains open.

### Eighth validation pass: explicit import and a separate publication failure

The next Full attempt, on `f20b4bf`, stopped after six preliminary tooling
stages: the synthetic audit's second directory publication returned access
denied (`IOException`, `0x80070005`). Its failure-only diagnostic recorded a
real directory at staging and parent, and a destination attribute read with
`FileNotFoundException`, `0x80070002`. The diagnostic does not establish an
open-handle owner, antivirus interference, or another cause. Both processes
returned 1 naturally after 26.453 seconds; no SwiftPM or XCTest work began.
The six-payload failure capsule is
`artifacts/goal-eighth-full-f20b4bf-publication-failure-v1`. Existing single
publication, cleanup, error propagation, and test criteria were not changed.

A separate focused pointer run then found the missing Foundation import in
the preceding correction. The earlier ledger sentence saying Win32Host already
imported both modules was incorrect: that file imported WinSDK but not
Foundation. It now explicitly imports Foundation as well as qualifying all
four UUID references. This focused attempt returned 1 after 6.078 seconds,
before any XCTest case, with source/index preserved; its original records and
failure receipt remain in
`artifacts/goal-eighth-pointer-f20b4bf-d52a5681ea4e444fbcf17f4122eae120`.
Fresh focused execution and the full release checks are still required.

### Eighth validation checkpoint: pointer identity and all CoreLogic shards

The explicit Foundation import and UUID qualifications compiled on `b660e9e`.
The focused pointer run closed naturally with zero exits after 333.859 seconds
including compilation; all twelve selected pointer methods passed with no
failures or skips. A copied-evidence audit also matched all 5,659 generated
XCTest identifiers and every 5,307 async / 352 direct adapter against source.
That registration check is not runtime coverage for the unselected methods.

The same clean source then ran stock `scripts/test.ps1 -Sharded` from its first
shard. All 285 serial invocations reported success across 404 CoreLogic targets;
the direct PS5 process and runner closed naturally with zero exits after
912.391 seconds, preserving tracked source and index bytes. The exact source
plan selects 5,642 CoreLogic XCTest methods and 134 Swift Testing declarations
once each; the 17 Portable methods are compiled but not selected. Per-case
outcome and skip reconciliation is a separate copied-evidence check still
pending at this checkpoint. The capture is
`artifacts/goal-eighth-sharded-b660e9e-capture-v1/CAPTURE.json`.

The capture preserves eight generated/build text files, five closed run
records, and five source inputs. Its streamed test executable hash matches the
earlier pointer executable; the capture neither copied nor executed that PE.
This standalone CoreLogic run does not include the agent-check tooling stages,
Portable execution, retained screenshots, gallery comparison, or the Full gate.
The two earlier Full failures and the missing-import failure remain preserved.

### Eighth implementation pass: capped and tiled bitmap sampling integrated

Resizable bitmap leaves now resolve admitted cap insets and tile repetition
into one constant-size sampling descriptor. The original source bitmap and
content identity remain unchanged, independent of destination size or tile
count. CPU, batch D3D11, and legacy D3D11 paths select matching source bands,
clamp fixed-band taps, wrap repeating center taps, and interpolate premultiplied
texels. Ordinary zero-cap stretch retains its prior sampler and admission.

The image primitive keeps its original 80-byte field prefix and appends 48
sampling bytes for a 128-byte stride. Sampling propagates through retained
reconciliation and scene/frame output. The legacy frame renderer chooses its
D3D11 path before drawing when Direct2D cannot honor the descriptor, without
permanently changing later frame selection. Current-target material replacement
requires canonical legacy sampling because it copies child pixels back to the
same parent positions; unsupported remapping is rejected before replacement.

The reviewed 28-path join adds 48 XCTest and four Swift Testing methods. Two
new regressions cover the material interaction. Twenty-one newly authored
MainActor test signatures were made async to avoid the documented Windows
discovery cast failure, without changing their assertions. Independent review
also corrected one new fixture that converted shader/pipeline attachment
errors into availability skips after a successful device probe: those errors
now fail the test, with cleanup retained. Other original test bodies and all
existing pixel tolerances remain unchanged; four existing assertions migrate
only image stride/offset or default-sampling contracts.

Before the documentation additions, the entire staged root tree exactly
matched reviewed private tree `6ee0ad05531d99c21a2b7de7859c02f03ac0e622`.
All image handoff payload hashes and 28 source endpoints were checked. The
README and compatibility matrix now describe the implemented subset; the
README also corrects its stale statement that retained Canvas symbols were
not wired. Current root contracts and strict formatting passed. The image
join itself still requires fresh compilation, runtime tests, and rendering;
the preceding `b660e9e` shard result is not transferred to it.

Fractional/oversized caps, nonpositive centers, partial UVs, excessive tile
phase, asset density/orientation, RTL mirroring, full aspect negotiation and
native pixels remain required future work, documented in `BitmapImageSizing.md`.
Typed refusal of those inputs does not exempt them from the full Image goal.
All original requirements and all nine completion gates remain unchanged.

### Eighth validation checkpoint: CoreLogic outcomes reconciled

The copied evidence for the clean `b660e9e` stock sharded run has now been
reconciled against its exact source plan and generated registration. Across
285 invocations, all 5,642 selected XCTest methods have paired starts and
outcomes: 5,641 passed and one existing material-content case skipped. All
134 selected Swift Testing declarations passed. There were no failures,
missing, extra, duplicated, or unmatched cases. The 17 Portable methods were
registered but not selected by this CoreLogic command.

The skip is
`RenderPassAbstractionTests.testMaterialInsideADrawingGroupBlursNothing`;
the test reaches its existing skip after its preceding assertions. The stale
broad skip message does not establish that every material capability is
missing, and the content-isolation requirement remains open. The sealed
57-payload reconciliation is retained in
`artifacts/goal-eighth-sharded-b660e9e-reconciled-v1`. This completes the
previous checkpoint's pending per-case audit, not the Full gate, and does
not transfer the older execution result to the subsequent image changes.

### Eighth implementation pass: bounded audit publication recovery

Audit publication retains its original directory move, with at most two
additional attempts after fixed 25 and 100 millisecond delays. Recovery is
eligible only for the exact access-denied or sharing-violation leaf error
through the admitted PowerShell invocation wrappers. Each additional attempt
requires the original staging and parent identities, canonical paths without
reparse ancestors, the original manifest digest and seal, and a destination
confirmed missing by its attributes. Windows identities include the full
128-bit file identifier and volume; unavailable identity information leaves
the original single-attempt behavior intact.

Every failed move writes a new diagnostic receipt before any retry. Receipt
failure stops recovery. Success reports the recovery; persistent failure
retains the original error, and cleanup failures are aggregated. Cleanup
refuses a substituted staging directory. There is no copy fallback, overwrite,
ACL change, reset retry budget, or suppression of a persistent failure.
This bounded response to observed failures does not identify the cause of
the earlier synthetic access-denied result. Filesystem calls are not hard
time-bounded; path observations are not an atomic defense against an
adversarial replacement race, and other sealed payloads are not rehashed on
each retry.

The final private Windows PowerShell 5 fixtures passed 301 recovery,
558 diagnostic, and 393 ledger assertions, preserving the 99 bound script
and baseline files in each run. Recovery includes 16 real filesystem cases,
11 error-classification cases, and missing-ownership controls. Independent
review found and corrected a post-publication warning that could throw under
`WarningAction Stop`: reporting now explicitly continues, and the regression
exercises both inherited and explicit Stop behavior through the actual
post-finally return. The failing negative control remains retained.

The eight-path join into root exactly matches the reviewed source endpoints;
root contract checks passed. Quick and Full now run both publication suites,
in addition to the existing audit suites. The pinned macOS capture workflow
still does not invoke those two additional suites; its documentation now
states that distinction. The direct private fixture runs are not a Quick or
Full pass. Intake is recorded in
`artifacts/goal-eighth-publication-root-intake-v4.json`; the combined root
compiler, Full tooling, runtime, and retained-render checks remain pending.

### Eighth API inventory checkpoint: raw structural reconciliation passed

The retained macOS capture from run `33250300319`, attempt 1, artifact
`9714411359` has completed structural validation. The successful process and
controller exited naturally with zero codes, in 98.233 and 102.813 seconds
respectively. It reconciled 22 symbol graphs, 134,147 precise identifiers,
300,436 declaration occurrences, 309,048 relationship occurrences, and six
public interfaces containing 137,973 lines. All 39 retained raw and metadata
inputs, eight frozen source/document files, and 21 ledger payloads were
hashed by that run. Its small reports and bindings are copied under
`artifacts/goal-eighth-api-structural-v2-intake`; the large payloads remain
at their original bound paths.

The preceding attempt failed naturally when inherited `PSModulePath` made
`Get-FileHash` unavailable to the PowerShell 5 child. The second attempt
removed that key only from the private child launch environment, without
recording its values or changing the frozen generator, capture, parser,
baseline, scope, budgets, or prerequisite. The first failure is preserved.
Sampled resource bounds remained untriggered; sampling is not proof of hard
OS caps or that every short-lived descendant was observed.

The ledger remains unreviewed and identity pins remain held. Zero captured
overlay definitions is an empty set, not evidence that no applicable overlay
exists. Discovery roots, exported modules beyond the extractor allowlist,
Cxx conditions, the loaded interface variants, and extension/overlay linkage
still require review. Structural reconciliation is not API matching, source
compatibility, native behavior, or release qualification. No original
requirement or completion gate has been removed or closed by these updates.

### Eighth Full restart: synthetic stage-order expectation corrected

The combined Full attempt on `6e0101c` stopped in the memory-isolation fixture
after five top-level stages passed. The direct process and runner exited
naturally with 1 after 23.297 seconds, preserving source and index. No SwiftPM
or XCTest execution began. The eleven-payload failure capsule is retained in
`artifacts/goal-eighth-full-6e0101c-tooling-failure-v1`.

The synthetic Quick runner had correctly stopped at its deliberately missing
memory child. Both newly inserted publication stages were already stubbed and
had run in the original parent process. The failing assertion still named the
ledger stage as the immediate predecessor; diagnostics now occupies that
position. The fixture now expects that actual predecessor and checks that
ledger, recovery, diagnostics, and memory run in order, with each publication
stage exactly once. The original failure-stop and child-status assertions are
retained; production validation behavior is unchanged by this correction.

The corrected root fixture then passed all 345 assertions in a direct Windows
PowerShell 5 run, exiting naturally with 0 in 8.563 seconds and preserving all
tracked source and index bytes. Its records are under
`artifacts/goal-eighth-memory-order-focused-0d37afad6dbf4795a8e99aaa5efd1d4b`.
Those Quick/Full cases use synthetic stage stubs; they are not real Quick/Full,
compiler, memory-workload, or rendering passes. Combined Full is restarted
from its first stage after committing this correction. All original gates
remain open.

### Eighth implementation pass: observed bitmap fixture failures and narrower corrections (2026-08-29)

The clean `0966b48ccc2bd54b8e9803c2debd4c364820e032` Full attempt
(`goal-eighth-full-0966b48-433d11038828448bbae9e2f2c498f6e0`)
stopped naturally with exit 1 after 1403.844 seconds. Its runner recorded
unchanged tracked source and index endpoints, no timeout, and no termination.
The log reports all 19 preceding top-level stages passing, followed by 245
passing CoreLogic shards and a failure in shard 246 of 286. That shard ran 25
XCTest methods: two new bitmap-resizing methods failed with five assertions
each; the other 23 methods passed. The remaining 40 CoreLogic shards and later
Full product, screenshot, and gallery stages were not run. This is failed
partial validation, not a Full pass. Independent per-case reconciliation of
the copied failed prefix is still pending at this entry.

Before another compiler invocation, the closed failure was retained in
`artifacts/goal-eighth-full-0966b48-failure-capture-v1`: its manifest records
520 payloads totaling 9,802,869 bytes, including raw output, source pins,
compiled discovery text, and the partial journal. `CAPTURE.json` SHA-256 is
`46cb2c788aef594c23e13a004b501c9993d9419644e968023f74375c89686816`.
The executable was streamed for identity only, not copied or executed by this
capture. This evidence remains bound to the failing source, even after fixes.

The two corrections change only existing methods in
`WinSwiftUIBitmapResizingTests.swift`. The invalid-cap test previously required
full alpha at the bottom-right corner of a separately antialiased rectangle;
the renderer's quad coverage gives fractional coverage there. The replacement
oracle compares every output pixel with an independently rendered sibling-only
scene and retains opaque-color checks at two interior pixels. It does not
adopt the observed corner alpha as an expected value or change the 1/255 color
tolerance. The tile-phase boundary test previously used a helper whose 24-point
frame clamped both nominal 4096- and 4097-point images. It now supplies a real
4097-by-4-point snapshot viewport, verifies actual retained dimensions, and
checks acceptance at 4096 and rejection at 4097, along with the unchanged
4-byte source bitmap, resource/command records, and legacy stretch behavior.
No destination rasterization is requested by that boundary test.

The reviewed fixture patch SHA-256 is
`e62ac633272933a64ed9adc9377dd5ef9caad5b3428f9d5f2067d61a3097c1fb`.
Root contracts before and after applying it and strict formatting of the one
changed Swift file passed. The corrected fixture methods have not yet been
executed at this entry; focused bitmap tests and a new Full attempt are next.
No production sampler, layout implementation, phase limit, ABI, baseline,
existing test identity, or original acceptance gate changed. Fixed-frame
overflow, broader aspect-ratio proposals, and native pixel parity remain
separate open work. All nine original completion gates remain open.

### Eighth implementation pass: corrected bitmap tests and complete local Full validation (2026-08-29)

The two fixture corrections were committed as
`a2cad235a57d403bb19c4418df36d8cfb9604184`, tree
`f1a42a88d36bda6dcc2d1e26696175abf1e43cff`. A fresh serial focused run
executed all 20 existing bitmap resizing and stretch XCTest methods: 20 passed,
none failed or skipped. Both GPU comparison methods executed successfully.
The run exited naturally with 0 after 196.469 seconds, without a timeout,
termination, or tracked-source/index endpoint changes. Its result is retained
under `artifacts/goal-eighth-bitmap-a2cad23-b222a5f427e84a5b95152957ba35d87a`;
it does not retroactively turn the earlier failed Full attempt into a pass.

A new stock `agent-check.ps1 -Full` run on that exact clean commit then passed
all 29 top-level stages, including all 286 CoreLogic shards, the separate
portable tests, evidence-completeness checks, debug and release builds,
retained screenshots, and gallery comparison. It exited naturally with 0 in
1491.047 seconds without timeout or termination; tracked-source and index
endpoints remained unchanged. This is a local Windows run, not hosted CI,
a native-machine smoke test, or qualification of unmerged source candidates.
The existing `RenderPassAbstractionTests.testMaterialInsideADrawingGroupBlursNothing`
skip remains an open rendering gap rather than an accepted completion exception.

The closed run is
`artifacts/goal-eighth-full-a2cad23-21ee25cbf0b14066a9615edc05c8bd50`.
Before another build, its raw output, source pins, discovery text, all journal
members and visual outputs were retained in
`artifacts/goal-eighth-full-a2cad23-archive-v1`. The archive manifest SHA-256 is
`51baa98e2208e1793e2c5a48c8518a44b2e2b4f792992821f83516693dcae2bd`;
the supplemental manifest is
`ef9aa17d3ace44409d30517627118c1ca32a263febf9f3a56aef4a2c47e49707`.
A separate copied-input audit then reconciled all 5,707 generated XCTest
identities and adapter flags against source, all 287 invocation scopes and
all 29 ordered stages: 5,706 XCTest passes, the one named material skip, and
138 individually identified Swift Testing passes. Every one of its 14 evidence
checks and all per-scope checks passed. The 5,690 Core journal rows agree with
the raw events; no expected case was unobserved. The separate metadata process
exited naturally with 0 in 2.995 seconds; it did not execute a test or binary.
Its result SHA-256 is
`e5cc16ff52af3b772d3b7055d66800fd312f51ee2cd0a6a9f6e43488b638d56e`.
The audited result, source expectations, parser capsule and closure receipts
are retained in `artifacts/goal-eighth-full-a2cad23-reconciled-v1`, alongside
the already retained raw Full archive.
This does not attest loaded binary origins, independent journal session
identity, descendant-process closure, native behavior, or hardware timing.

All 85 reviewed gallery comparisons passed their unchanged limits: 0.5 percent
of pixels above channel tolerance 8, and maximum channel delta 64. Of these,
83 were pixel-exact. `canvas-path-gradient` had 70 pixels above tolerance
(0.175 percent), maximum delta 20; `state-toggle-hover` had no pixels above
tolerance and maximum delta 8. The baseline/current pairs were visually
inspected and left unchanged. The five retained demo screenshots were also
inspected. The legacy frame images still visibly differ from retained scene
images in corners and material appearance, including backdrop blur; a passing
screenshot stage does not establish backend parity. The separate parent review
is `artifacts/goal-eighth-full-a2cad23-parent-visual-review-v1.json`, SHA-256
`71cc7da4976b4784db7355466b1cd01e1b3e8e50eec7227739ac6e34f5e2d80c`.

All nine original completion gates remain open. Native owner scheduling and
shutdown, deferred List construction, broader image proposals and frame
placement, full template workflows, the pinned API audit, macOS conformance,
accessibility, hardware timing, and deployment still require their own
implementation and direct evidence. Their private source reviews are not
substitutes for compiled or executed integration results.

### Eighth implementation pass: observed font-policy layout sensitivity (2026-08-29)

A separate controlled experiment ran exactly two fresh headless gallery
processes on the unchanged `a2cad23` build, producing four PNGs for
`typography-scale` and `canvas-donut`. The only changed child environment value
was `SWIFT_WINDOWSUI_CLASSIC_UI_FONT`: absent versus `1`. Both children exited
naturally with 0, without timeout; no fonts, global environment values,
settings, source files, baselines, or thresholds changed. The closed records
are under
`artifacts/goal-eighth-font-policy-a2cad23-e7e5fad3042341538c8a8f5a671cfde4`.

All ten selected text roles actually changed their requested family from the
appropriate Segoe UI Variable cut to Segoe UI at the same point sizes. Both
default PNGs matched the existing baseline pixels and were byte-identical to
the archived normal Full PNGs. Classic typography differed at 2,052 pixels
above tolerance (2.6719 percent), maximum delta 242; the classic donut differed
at 2,129 (2.7721 percent), maximum delta 255. Those raw comparisons fail both
unchanged limits; diagnostic alignment does not replace or relax them.

Stored constrained legend width changed from 69.6 to 67.6, shrinking the outer
composition and moving its centered origin one pixel right. The Canvas itself
kept its local 138-by-138 frame. Derived nontext ring bounds and pixels agree
with that displacement. After diagnostic one-pixel alignment, 218 ring-edge
pixels still differ, including 26 above tolerance, maximum delta 50. Shared
solid colors agree. This supports a current font-policy-sensitive layout
mechanism, not an exact translation or a complete explanation of the residual.

The sidecars contain zero path records because the four paths were promoted;
that counter is not proof of GPU execution. Captured path geometry, direct
Canvas-to-primitive ownership, and actual loaded font files remain unavailable.
The PNGs use the retained CPU reference renderer. The older hosted `3fcdf14a`
run remains 18 passing and 67 failing comparisons; this later two-fixture
experiment does not establish that run's font identity or explain all its
failures. Hosted visual qualification and all original goal gates remain open.
The passive comparison, geometry review and unchanged-input checks are saved in
`artifacts/goal-eighth-font-policy-a2cad23-analysis-v1`; they required no
additional app process or font probe.

### Ninth implementation pass: finite image fit and fallback preservation (2026-08-29)

The next integration branch starts from the validated and pushed `3d716d1`
checkpoint. It now contains the reviewed finite-fit implementation from private
`923be4ae0bb47b1cc026e2fd5c71703ac1e17567`; all five Swift postimages match
that candidate exactly. The original source patch SHA-256 is
`a9bf57eb98b4eb4095578e0367a3822d9e14a324e09b8870a105ea1e1bde62a5`.
The documentation join preserves the preceding a2 validation rather than
relabeling it as execution of these new cases.

Resizable bitmap Image and generic View fit methods now share a retained
proposal modifier. Positive finite width and height maxima with zero minima
produce a coupled aspect-fit proposal; a nil ratio comes from the child's
current ideal size. The wrapper reports the child's accepted size, and the
outer frame keeps responsibility for alignment. A 4-by-2 image inside a
centered 12-by-12 frame therefore fits to 12-by-6 at (0, 3).

Declined proposals retain the original centered stack's measurement and clamp.
This incorporates a source-review correction: an earlier, unrun absolute
wrapper let an inner fixed 12-by-8 frame regain its width inside the old 8-by-8
fit ideal. The accepted implementation preserves the old 8-by-8 result at
(6, 6) under fixedSize and a centered 20-by-20 outer frame. Accepted size,
placement admission, fit configuration and inherited fill state travel together
under the same measurement cache/memo key; construction nodes do not replace
the installed node's private cache.

Nineteen new MainActor async XCTest methods cover independent geometry and
solid coverage, typed and generic lowering, frame order, reconciliation,
caps and repeats, four display scales, clipping, fallback preservation,
source identity and the unchanged tile-phase limit. The original sixteen
candidate tests and helpers remain unchanged; three cover the corrected
fallback and finite/fallback reconciliation. Source bytes, sampling, the
128-byte image ABI, all existing test bodies, baselines and tolerances remain
unchanged by this slice. Root contracts and strict formatting of all five
changed Swift files passed. Compilation and execution of the nineteen new
cases are still unrun at this entry; the earlier a2 Full did not include them.

Fill/overflow, unspecified/infinite/single-axis/invalid proposals, minimum and
fixed-size conflicts, complete modifier order, symbols, density, orientation,
RTL, interpolation and native pixel/filtering conformance remain original
requirements. Preserving older Windows fallback behavior does not establish
native conformance. Legacy frame bitmap placement and the separate resource
samples still need their own integration. All nine original gates remain open.

### Ninth implementation pass: bundled bitmap examples and resource copying (2026-08-29)

Two small owned PNG resources and a shared-source bitmap sample now demonstrate
capped stretch, partial tile repeats, and capped aspect fit through ordinary
Image APIs. Both Windows and macOS SwiftWindowsDemo targets declare the
resource directory. The gallery adds a bitmap card and three deterministic
128-by-128 fixtures. The catalog now contains 147 entries: 104 base examples,
16 interaction states and 27 light variants. The reviewed baseline set remains
85; these three new examples have not silently become accepted baselines.

The source patch from private `ff2c0bcbbea987d7e0c9a67c575fed5e4dee4177`
has SHA-256
`50dc1dfbcfa19f5a79b6274c93d06083604d44309f50501b9caf7d425f03e940`.
All seventeen staged postimages match that reviewed patch. Its eight new
MainActor async XCTest methods cover actual generated bundle resources,
named-image decoding, source/cap/repeat preservation, finite aspect fit,
accessible names, gallery search, and an explicitly copied bundle. The
aspect sample depends on the preceding retained fit implementation; it does
not add a demo-specific sizing API or substitute a rendered expected bitmap.

The resource-copy helper takes an explicit generated bundle path and preserves
its whole basename, files and empty directories. It rejects replacement,
redirection and source changes rather than guessing a SwiftPM output location.
The Quick/Full ladder now includes its synthetic checks after checkout metadata
and before lint. The separate memory-isolation harness retains its prior
failure/timeout cases and verifies that this new stage executes once, in order.

On the integrated root, all 28 synthetic resource-copy assertions and all 360
memory-isolation assertions passed; the latter use stub stages, not real
Quick/Full or memory workloads. Logs and retained fixtures are under
`artifacts/goal-ninth-resource-source-checks-v1`. Root contracts and strict
formatting of all seven changed Swift files also passed. The eight new XCTest
methods, actual bundle relocation, new retained PNGs, macOS execution and
joined Quick/Full remain unrun at this entry. Copying a resource bundle alone
is not a complete executable package or clean-machine deployment proof.
All original completion gates remain open.

### Ninth implementation pass: text editor content layout settlement (2026-08-29)

TextEditor now requests a targeted follow-up layout when its content is
replaced or its chrome is cleared during layout. The request uses the
runtime's existing bounded after-layout queue and checks attachment and
controller/content ownership both when queued and when delivered. Weak
captures and a guarded parent-chain walk keep a retired, replaced, moved or
closed editor from invalidating its former runtime. This path does not
reveal the caret or reset the user's scroll position or selection.

The separate reviewed editor patch has SHA-256
`bafffe92749bb880bc551f77692db370b96b0800e9dbfe842620d9c7ed7b0008`.
It contains three Views.swift hunks and five MainActor async XCTest methods.
The tests cover first-layout settlement without an extra paint, retained
selection/scroll and an ancestor animation, unfocused and empty content,
stale ownership, and refusal to report settlement for continuously changing
geometry. The existing TextField changes are preserved. The separate file
preview template has not been imported with this patch.

On the integrated root, contracts passed before and after application, both
changed Swift files passed strict formatting, and the staged diff passed
whitespace checks. The five new methods are still unrun at this entry. The
next focused selection contains 64 async XCTest methods across finite bitmap
fit, bitmap resources, editor settlement, the two existing bitmap sizing
suites and responsive gallery coverage; 32 of these methods are new in this
integration branch. Compilation, runtime outcomes and retained visual review
will be recorded separately after they occur. All original gates remain open.

### Ninth implementation pass: first combined test run and directory URL fixture (2026-08-29)

The first combined focused run compiled the root at
`f029fff1387139653fc8c44baf60b094885d0df4` and executed all 64 selected async
XCTest methods. Sixty-three passed, one failed, none skipped, and Swift Testing
executed zero tests. Both existing bitmap GPU comparison methods, all nineteen
finite-fit methods and all five editor-settlement methods passed. This was a
failed run, not a successful focused or Full result.

The sole failure was the copied-bundle test's exact URL equality: Bundle
returned the owned directory with a trailing slash while the expected URL was
constructed without a directory hint. Its following resource-containment and
decoded-image equality assertions reported no failures. The fixture now marks
that expected path as a directory when constructing it. It retains the exact
standardized URL equality and both image-loading assertions; no production
code, rendering tolerance, expected pixels or suite selection changed.

The child exited naturally with code 1 after 336.579 seconds. Source and index
endpoint checks passed, with no timeout or operator cleanup required. The raw
log is retained under
`artifacts/goal-ninth-image-editor-f029fff-550ff6582d0a407b895e833df7de63fe`;
its SHA-256 is
`d6af7b12112db1a2586cd0af2cbaa64802ae5ca3a6ae308cefd175dc652b46b7`.
The separate failure reconciliation matches all 64 started/completed IDs to
the selected source methods. A fresh run of the unchanged 64-case selection
is required after this fixture correction. All original gates remain open.

### Ninth implementation pass: combined focused tests and retained bitmap review (2026-08-29)

The unchanged six-class selection passed at
`138d49b684a9c7082432a17cdbb0a200e03bbafb`: 64 XCTest methods, zero failures,
zero skips and zero Swift Testing methods. All nineteen finite-fit, eight
resource, five editor-settlement, twelve responsive-gallery, ten resizing and
ten stretch methods completed, including both existing D3D11 comparison
methods. The corrected copied-bundle test retains exact URL equality,
containment and decoded-image equality. The earlier 63-pass/one-failure run
remains a separate failed result rather than being overwritten.

The fresh run exited naturally with code 0 after 201.657 seconds, without a
timeout, termination or required operator cleanup. Source and index endpoint
checks passed. Its raw log is retained in
`artifacts/goal-ninth-image-editor-138d49b-bc5e0a2e0f684bee90c13ff3caa72d0e`
and has SHA-256
`fc8a41d66710cde2496927593c6da8b607cffbecc5828006cedc34ccd8cba991`.
The separate reconciliation binds every started and completed method to the
current source. These are focused results, not a joined Full result.

The just-built gallery then rendered `bitmap-cap-insets`, `bitmap-tile` and
`bitmap-aspect-fit` through the retained snapshot path. All three original
128-by-128 PNGs were opened and inspected: the colored caps remain visible,
tiling fills its square with cropped final repeats, and the 96-by-64 fitted
image is centered between equal 16-point horizontal bands. The catalog is
still 147 entries and the reviewed baseline set is still 85. No new baseline
was accepted and no threshold changed.

The gallery executable was 73,847,808 bytes with SHA-256
`de969b45a8c19fe92641554abe23261c56653698e00215c553628dd07adbc5c6`.
Its render child exited naturally with code 0. A separate successful child
used `copy-demo-resources.ps1` on the actual generated
`swift-windowsui_SwiftWindowsDemo.resources` bundle: both files, 285 bytes in
total, matched their source and copied hashes. The generated accessor was
inspected and retained by hash; it prefers the main bundle location but can
fall back to the original build tree. Neither a relocated executable nor a
missing-build-tree or clean-machine installation was tested.

The PNGs, resource copy, child exit records and parent visual review are under
`artifacts/goal-ninth-bitmap-gallery-d2a1cf75653947d4915ffdff05da47ba`.
The executable, accessor, source resources, tracked source and index were
unchanged at the recorded endpoints. This retained CPU review and the focused
GPU cases do not qualify native SwiftUI behavior, legacy frame presentation,
the forthcoming native/List join, hosted CI or deployment. All nine original
completion gates remain open.

### Ninth implementation pass: bounded native owner and MainActor transport (2026-08-29)

The reviewed native host source is now integrated over the tested image,
resource and editor foundation. UI construction, state and callbacks remain
on MainActor; a dedicated STA owns the HWND, native message pump and renderer
kernel. Copied Sendable commands and typed actual replies cross that boundary.
The renderer facade preserves captured display scale and submitted frame
identity instead of consulting live HWND state from the UI actor.

Native input admission is bounded to 1,024 records and 16 MiB of accounted
payload, with 32 events per automatic actor turn and one outstanding drain
token. Manual flushing has a finite captured tail. The native command mailbox
has 128 ordinary slots and explicit bounded close/wake/stop reservations;
these remain in FIFO order rather than bypassing older admitted work. Timer
changes retain one command in flight and the latest desired state, applying
state only after the matching actual reply. Essential overflow is an explicit
owner failure, not a claim that normal-load performance is qualified.

Commands expose the real one-shot reply capability. Terminal replies are
claimed under the queue mutex before arbitrary callbacks, with delivery after
release; no arbitrary getter, rejection callback or final object destruction
is introduced under that lock. Close admission, native destruction, reply
delivery, actor consumption and the OS-thread join remain distinct milestones.
UIA retains complete C-call lifetimes across dispatch and output marshalling.
Authored synchronous native services and the guarded document-startup paths
remain documented qualification gaps.

This is the native portion of the sealed source join from
`e1c9945faf08f9659fbc29e0ace96d4f65df99e4`, applied as its separate
`a837b74a1164e4e9d4be55166126b0dbdc66a0cb` source commit. Its patch SHA-256 is
`fbedfd870b70ab0101595bd70aa4360da32aa90d2c32548d33f1a8dc28b50fb2`.
All 68 changed production/test postimages match that immutable source; root
documentation and goal history are preserved. Contracts passed before and
after integration. The native source adds 269 test methods, including 95
bounded-transport cases, but no compilation, discovery, native execution or
live timing result has yet been obtained for this root composition. The
following List join must preserve these ownership and transport contracts.
All original completion requirements remain unchanged and open.

### Ninth implementation pass: deferred public Lists joined to native ownership (2026-08-29)

The public List construction path now defers supported flat and ForEach rows,
including transparent groups and bound collections, instead of constructing
every retained row before layout. Logical identity and visited State ownership
remain separate from the bounded physical row nodes. Eviction retires row
tasks, observations and presentation activity; checked adoption, keyboard
focus, programmatic scrolling and logical UIA realization share that ownership.
This does not make model IDs or scalar metadata viewport-sized: those remain
O(data), and arbitrary explicit ID discovery can still require O(data) total
authored factory work across bounded probes.

The join keeps native dialog hooks in all 26 explicit ViewBuildContext
constructors. Shared native invocation storage clears both List construction
attributions and installed owner/epoch values; this does not renew old row
action authority. Component adoption checks finite-fit configuration without
copying private measurement caches. A changing scalar List extent is measured
before either cache probe and records its current inherited fill axes without
inserting a stale memo or using an uninitialized placement plan.

Logical UIA state and property-zero ItemContainer enumeration now use typed
native requests, actor-captured capabilities and fresh copied geometry. The
full C-call lease covers dispatch, foreign identity/Release, related-provider
allocation and final output marshalling. A transport HRESULT takes precedence
over payload booleans. Actor handling never waits for native-owner progress;
logical enumeration must not construct rows. Nonzero property searches and a
custom legacy-only mapper without copied geometry still fail explicitly.

The source patch is the separate private commit
`5e54123311ef5fd094b7ff92bb2d7a773729dea5`, SHA-256
`adbe0faf730788b2e42a697ab66d596075dde9c2a191b5049cbf4aae8eac9cf0`.
All changed production/test postimages match it on the root; contract and
whitespace checks passed. The 478 List methods, 269 native methods and all
19 held lifecycle test originals retain their source oracles. Sixteen
additional async integration methods cover native invocation contexts and
logical UIA/call lifetimes. Compilation and execution are still pending for
this larger root composition; the preceding 64-case result is not transferred.

Nonidentity removal transitions remain refused before mutation. Completing
them still requires passive captured paint with original geometry and retired
activity, replayed without builders, Canvas callbacks, actions or observations.
Tree/opaque projection, spacing and unknown-prefix limits, nested unbuilt
targets, unobserved external binding removal intervals, per-leaf logical
enumeration and arbitrary work inside a row factory remain tracked gaps.
These are unfinished requirements, not new compatibility exceptions. All
original completion gates remain open.

### Ninth implementation pass: selected List rows preserve authored labels (2026-08-29)

The joined List selection owner now forwards the exact optional accessibility
label from its identified content root, including nil and an explicitly empty
label. It retains the existing identity, selection, focus and action owner.
It does not scrape descendant text, add a wrapper Button or expand logical
enumeration or row decorations. This supplies the ordinary authored-label
behavior needed by the separate file-preview template without a demo-specific
accessibility workaround.

The source is the separate `e1c9945faf08f9659fbc29e0ace96d4f65df99e4`
join commit, with patch SHA-256
`228edc0be20c40449419dc46f74cf0424200fe9531a062cba66ebb41f70fe54e`.
It adds six production lines and eight MainActor async regression methods.
Contracts and whitespace checks passed on the root; compilation and execution
remain pending. Together the native, List, label and integration source cohorts
contain 771 new methods (765 async and six nonisolated synchronous methods).
Their source preservation is not a runtime pass. The original nine gates stay
open, including real UIA/Narrator and complete lazy-collection behavior.

### Ninth implementation pass: explicit overlay census workflow and stable template bytes (2026-08-29)

The existing Stage A filesystem census can now be requested through a separate
manual baseline-workflow option. Push runs and ordinary manual runs retain
their previous behavior. An opted-in request requires the reviewed template's
exact SHA-256 and an explicit optional-root choice. The caller binds only the
fresh successful capture/audit and named anchor hashes into the fixed plan;
it does not substitute discovered root paths, broaden traversal or approve
baseline identity. The generated plan hash records integrity, not a second
independent review.

The new preflight has a two-minute limit. A requested census follows successful
export and complete audit with a separate twenty-minute limit inside the
existing ninety-minute job. Independent material/RGB failures are preserved;
they do not silently suppress this separate requested stage. Cancellation or
failed export/audit does suppress it. Existing uploads and their retention
remain unchanged. No workflow was dispatched by this implementation step.

The source packet's six-file patch has SHA-256
`f5010220e99fe3d1a50e115459a4eab5367a1262e40ecb1f43a1002569dd2019`.
On Windows integration, the exact-hash preflight correctly refused Git's CRLF
checkout of the template. The root now pins only this authorization template
to LF in .gitattributes and retains its already reviewed bytes and SHA-256
`51090bf9a96a781dde9a65433d19ad6cd6fa3ddafbb02c3efcf3640481aa9766`.
The caller's hash guard was not relaxed or replaced. Two additional synthetic
assertions check the Git rule and actual line endings.

All 236 focused source/synthetic assertions, the corrected ValidateOnly call,
root contracts and whitespace checks passed. ValidateOnly explicitly reports
no root-plan validation, SDK observation or native census. The original failed
preflight remains a separate diagnostic. The complete workflow, managed-reader
fixtures and live macOS census have not run for this change.

The plan acknowledges the existing BCL adapter's possible incidental link-target
metadata queries outside a reviewed boundary before controller checks. Those
individual queries are not fully observed; this is not permission for outward
content reads, listings or traversal. Stage A still cannot prove compiler
module loads, overlay activation, declaration ownership, API completeness or
behavior. Stage B and the original identity/raw-payload review requirements
remain open. The separate native/List integration also passed strict lint of
all 144 changed Swift files; its runtime tests remain pending. No original
completion gate is changed or closed.

### Ninth implementation pass: explicit frame bitmap placement (2026-08-29)

Frame bitmap commands now distinguish an authored logical destination from an
already completed device-pixel raster. Ordinary Image, Canvas and cached
axis-aligned symbol producers use the destination; text, path and affine
raster producers mark their physical pixels explicitly. Existing initializer
function values remain supported. The native plans preserve the positive
29-by-15 raster at scale 1.5 and keep zero or negative logical extents empty
before considering source dimensions.

Shared admission records typed placement failures with original command
indices before resource registration or native branch selection. Rejected
bitmaps do not remove valid siblings or alter clip order; a supplied observer
or stderr receives the refusal. A successful accepted partial frame is not a
claim that rejected commands painted. Source images, sampling policy, the
128-byte ImagePrimitive ABI and tile-phase limits remain unchanged. Legacy
POINT/nearest filtering still differs from the linear CPU/batch-scene path.

The reviewed native/List-relative patch is from
`af26a7ea89b8e964f08f56efc22ad3bacf5e191d`, SHA-256
`4bb3753403d659524ed9300b7b45d3f34fcf019f106e3689f07dd5ebf2757a5f`.
All fifteen changed production/test postimages match that source on the root.
The native kernel/facade split, captured scale, complete frame transport,
submission/device identities and teardown remain preserved. The independent
native-boundary source review found no blocker; root contracts, strict lint
of all fifteen Swift paths and whitespace checks passed.

The three new test files contain 31 async methods, including the two empty-
extent regressions; their full source remains unchanged from the reviewed
candidate. Compilation and execution, actual native frame rendering and
fractional filtering remain pending. This source integration does not inherit
the earlier foundation's CPU gallery or focused-test result. All original
completion gates remain open.

### Ninth validation pass: native compiler blockers and exact shard selection (2026-08-29)

The first native/List/bitmap compilation at root
`6b4379024cf48c34b3ebd6fca928dece72c3eaf0` stopped in
SwiftWindowsPlatform before any test started. The requested ten portable
NativeWindowOwnerValueTests did not execute. The direct PowerShell child
exited naturally with code 1 after 30.140 seconds; it did not time out or
require termination. Tracked-source and index endpoint observations were
unchanged. Its 8,424-byte combined log has SHA-256
`2942f9e3086bedb4d107c54652e6b0223ff2d44262e64e6f7213aeff68e34610`.
This is a compiler failure, not ten failed tests or a runtime qualification.

The diagnostics identify the WinSDK WindowsBool conversion in native file
recycling, opaque C provider/call pointers crossing Swift Mutex sending
boundaries, and an EnableMenuItem result imported as Bool where the source
expected integer flags. Repairs must preserve native error reporting, all
provider and call retain/release ownership, and release outside the Swift
mutex. Later modules and the new native/List/bitmap tests remain unqualified;
the earlier foundation's 64-test pass does not transfer to this integration.

Preparing the bounded Core run also exposed an independent test-runner bug:
an exact class filter could select a shorter suffix class. Sharded selection
now first uses case-insensitive exact class/suite names and preserves their
order and object identity. Only a filter with no exact match uses the existing
bidirectional substring/wildcard behavior. Empty filters, joined-name fallback,
non-sharded regular expressions, shard planning, evidence capture, and exit
handling retain their previous behavior. Joined names can still select suffix
matches; focused native validation will request one exact class at a time.

The three-file selector patch has SHA-256
`3d1dbbc44073c42c836903a4135b8ade16fa6d8238302d3508ba9456f4e6470d`.
All root postimages match the reviewed packet. Thirty pure PowerShell 5
fixture cases with 94 assertions passed against the actual helper extracted
through the production script's AST. These fixtures also verify the actual
sharded call site; they do not execute test.ps1 or SwiftPM. Contracts before
and after the change and whitespace checks passed. The private negative
control using the old selector failed as expected on the first collision.
Compiler repairs and fresh test execution remain pending. All nine original
completion gates remain open and unchanged.

### Ninth implementation pass: native lifetime capabilities and close-menu state (2026-08-29)

The three diagnosed native compiler boundaries now have narrow source repairs.
File recycling reads WindowsBool.boolValue while retaining the existing shell
operation error and cancellation results. Close-menu updates use the real
Boolean success results of GetMenuItemInfoW and SetMenuItemInfoW with MIIM_STATE,
instead of treating EnableMenuItem's imported Bool as integer flags. Only the
disabled/grayed bits change; checks, highlighting, default status and unrelated
state bits remain. Native close policy, absent-menu handling and DrawMenuBar
error reporting are unchanged.

UIA session and call-lease mutexes now contain private, type-specific Sendable
capabilities with immutable integer identities. These values do not own or
release C references when copied. The existing session and full-call lease
remain the owners: admission retains before locking, expected identities are
checked under the lock, temporary pins are acquired before unlocking, and
revocation/final release remain outside the Swift mutex. C atomics, complete
native method lifetime, drain wake, marshalling and callback release hooks are
unchanged. No unchecked Sendable conformance, isolation bypass or new C target
was introduced.

The reviewed five-file patch has SHA-256
`30dbed1c28bba682d780d96695439e5f4d5d9d809f9da70d2a9ab69fa066bbef`.
Root contracts before and after integration, strict lint of all five Swift
files and whitespace checks passed. Every postimage matches the source packet;
all existing test files are unchanged. Three additional MainActor async menu
state tests cover preserving unrelated bits, all prior disabled states and
idempotent updates. They are a separate, still unexecuted cohort.

The initial failed compile remains recorded above. This repair still requires
fresh compilation, all affected tests, and actual native menu/UIA behavior;
source review alone closes none of those requirements. The original nine
completion gates and the original compatibility destination remain unchanged.

### Ninth validation pass: preserve the lazy probe ownership check (2026-08-29)

The next compile at `ab7844d151d2b2823a3053eb8759483dcfa54e02`
compiled SwiftWindowsPlatform and SwiftWindowsRendererD3D11, then stopped
before tests on two accesses to ViewNode's fileprivate runtime from the lazy
List adapter. Its direct child exited naturally with code 1 after 36.609
seconds, without timeout or termination; tracked-source and index endpoints
were unchanged. The 9,666-byte log has SHA-256
`a66b40236cbccb183022ff5b5369a64dc78d1700a4a4a1dbd590b00603270ddf`.
No XCTest or Swift Testing case began in this attempt.

Both checks now use the already-existing internal read-only
retainedLazyListRuntime getter. Its body returns the same private runtime
value. The checks still require nil parent and nil runtime both before and
after the opaque scroll matcher; authority, identity and record validation
remain in the same order. Only these two member names changed. No access
level was broadened, no new API was added and no test source changed.
Contracts before and after the change, strict formatting, exact two-edit
preservation and whitespace checks passed. Compilation and execution still
need a fresh attempt; all original goal gates remain open.

### Ninth validation pass: explicit facade imports, actor closures and List scopes (2026-08-29)

The compile at `8a17ce9c846d2b490cab4ff499440767922024b5`
advanced through SwiftWindowsUI and stopped in WinSwiftUI before tests. The
direct child exited naturally with code 1 after 30.828 seconds, without timeout
or termination, with unchanged tracked-source and index endpoints. The
59,318-byte log has SHA-256
`26c9f3cea6e3e6722145c09ab9f0261b5eaafdf11af93875d4f331008ccdcf2e`.
Thirteen distinct source diagnostic locations reduce to missing dialog type
imports, actor closure annotations, List scope/access mismatches and an explicit
self capture. None is an executed test failure.

Core now explicitly imports its already-declared SwiftWindowsPlatform
dependency for NativeDialogSession. The local scroll-request predicate, the
List binding predicate and Group's deferred materializer explicitly carry
MainActor/Sendable function types for their actor-owned work. Their bodies, capture values,
predicate ordering and invocation sites remain unchanged. UIA's lazy node
lookup makes its existing self capture explicit; the chain is only rewrapped
to retain the formatter's 120-character limit. The initial strict-format
refusal for that longer line is retained separately from the corrected pass.

Managed List predecessor replacement now unwraps the actual descriptor scope
before staging. Predecessor lookup accepts an optional scope but only returns
an attached adapter with a current managed logical binding. Ordinary standalone
adapters have no such binding and still take the existing new-source path.
A scope-free attempt to reuse managed state is refused without inventing a
scope or silently starting a replacement source. The standalone lease reads
the existing traversal cap through a package read-only getter; the internal
mutable policy, bound and ancestry walk remain unchanged.

The separate four-file List repair patch has SHA-256
`d612e6245b66860df1e45d3fe9d1935a4a1d71f25e1969d2d73dcf1aaebf5887`.
The combined six-file correction preserves all existing test files and their
oracles. Source review, contracts and strict formatting passed. Compilation,
the requested portable cases and the larger native/List cohort still require
a fresh run. No original completion gate or compatibility requirement changes.

### Ninth validation pass: explicit closure values for host construction (2026-08-29)

The compile at `481448d37aa0fcbe417bb02641e4141ca008f182`
reached two remaining WinSwiftUI diagnostics before any test started. Swift
rejected the explicit Sendable attribute on the synchronous MainActor local
function, and reported that it could not produce a diagnostic for the host's
ViewBuildContext initializer expression. Its direct child exited naturally
with code 1 after 52.734 seconds, without timeout or termination. Source and
index endpoints were unchanged. The 5,902-byte log has SHA-256
`59e36d53742991d58dc1691def534927c3086bfc70837911251fa3eaff2871ae`.
The preceding formatting/source review was not compiler qualification.

The scroll-current predicate is now an explicitly typed MainActor/Sendable
closure value rather than an attributed local function. Its Boolean expression
is unchanged, and an explicit self capture retains the original strong capture.
The host constructs the optional native-dialog owner callback in a separately
typed local value, then passes it to the same context initializer. The existing
native-presentation condition, weak host capture, pending-owner callback and
all other context arguments remain. Standalone contexts still receive nil.
Neither correction adds an actor hop, fallback, global state or mutable native
handle access.

The host patch has SHA-256
`ff5df6f2bdf646925d5f8e1fe2fdc21701ff4d97a2c84712867700462ff500b2`.
The selector only reads the immutable native-presentation factory. The existing
lazy coordinator initialization constructs framework state and stores callbacks
without invoking them; extracting this callback does not run authored work.

Contracts, strict formatting and narrow-diff checks passed for these source
corrections. All test source remains unchanged. The opaque host expression
diagnostic and the local-function rejection are retained; fresh compilation
and test execution remain required. No original completion gate is changed.

### Ninth validation pass: production compilation and preserved fixture assertions (2026-08-29)

The compile at `b58aee5b7089540b1248a6f295d05d1c2893871b`
compiled the production targets and linked the app, gallery and snapshot
executables. It then stopped in test compilation, with 26 distinct diagnostic
locations in nine test files. No XCTest or Swift Testing case began. The
direct child exited naturally with code 1 after 121.187 seconds, without
timeout or termination; tracked-source and index endpoints were unchanged.
The 2,845,477-byte log has SHA-256
`1aca5574e6f8cc689d89580ce67698ea621537635d214c4355448e09653651aa`.
Linking these executables does not qualify their native behavior.

The nine fixture corrections preserve all 125 existing test method names and
headers. They add the missing Graphics import, use Int32 for the existing
bounded IntSize fixture, read the existing accessibility-hidden property and
read-only List runtime getter, and explicitly isolate the UIA fixture's base
initializer to MainActor. Two required window environments are unwrapped
rather than accessed through an optional. The cancellation probe strengthens
its weak self reference before its existing synchronous MainActor assertion;
it does not add a task hop or change the cancellation expectations.

Four reentrant ingress callbacks now check their Result with a nonthrowing
assertion helper. Each enqueue still occurs exactly once at its original
callback position, and every failure remains an XCTest failure with the
caller's source location. No event is moved out of a reentrant callback and
no admission failure is discarded. The dialog fixture captures a throwing
driver operation in Result while the temporary build context is active, then
rethrows after that context is restored and before awaiting delivery. Both
context assertions remain inside the scoped operation.

The modal fixture sets the existing modal accessibility trait, uses a checked
public root-layout query instead of the private layout helper, and makes three
existing presenter self captures explicit. The public query requires an
attached root and its normal query guard; it performs the existing layout work
and subsequent focus/retained-callback/reveal settlement. That wrapper is part
of the fixture behavior and is not claimed to be a byte-identical helper call.
The root stays attached at both calls, including after removing its container.

Source review, exact postimage checks, strict formatting, contracts and
whitespace checks passed. The dialog postimage matches its separately reviewed
source packet exactly; the parent's earlier equivalent Result variable name
and both patch histories are retained. No production implementation, existing
test identity, baseline or comparison tolerance changes in this correction.
The selected native test runner must bind the four changed selected fixtures
before execution. Fresh compilation and test results are still required;
all original completion gates remain open.

### Ninth qualification pass: fresh hosted gallery failure and bounded font evidence (2026-08-29)

Hosted Windows run 33270528843, attempt 1, for
`3d716d15f4c0a5942e610bb2444cb8f96ced5c02` completed with failure.
Its Full log and retained artifacts report 18 passing and 67 failing gallery
comparisons. Independent decoding against all 85 immutable baseline blobs from
that same commit reproduces every reported metric: 20 images fail both limits
and 47 fail maximum channel difference only. There are no missing images or
dimension mismatches. Twelve images are exactly equal as decoded RGBA; none
has identical encoded PNG bytes. The existing greater-than-0.5-percent changed
pixel limit, noise threshold 8 and maximum-channel limit 64 are unchanged.

The runner reports Segoe UI Variable's three cuts absent and Segoe UI present,
so the existing default policy projects classic UI without a forced override.
Segoe Fluent Icons is separately absent and Segoe MDL2 Assets present. Narrow
V1 diagnostics reference nine MDL2 icon roles for stepper and symbol-palette;
they do not expose general text glyph ownership or Canvas/quad placement.
The diagnostic's nonzero, unqualified pixel outcome is retained even though
its workflow step uses continue-on-error and reports success.

Fresh hosted typography-scale is byte-identical to the already closed local
classic-UI capture, SHA-256
`575d6f2b06348fc92eb01280bcce0714155bfba68665a3616798a3e1c26306a7`.
The hosted donut and that same closed classic treatment have identical ring
and text pixels; 216 differing pixels remain in the three legend icons, with
maximum channel difference 237. The donut still fails the unchanged maximum
rule against the classic image. These passive comparisons support these two
fixtures only. They do not explain all 67 failures, prove loaded font files,
reconstruct hosted Canvas geometry or authorize replacement baselines.
The parent inspected the four relevant retained PNGs at original resolution.

The Core publication is consistent with its own 5,690 unique case identities:
5,686 pass and four skip across 286 declared completed shards. One is the
existing material test; three SystemUIFontFaceTests explicitly report that
Segoe UI Variable is not installed. This differs from the previously recorded
local Full's one skip. The publication check does not independently join the
complete source inventory, Portable or Swift Testing, and is not a Full pass.

The separate macOS baseline run 33270528823, attempt 1, also reports failure.
Its material-provenance step still has stale in-progress metadata, its log
request returns 404 BlobNotFound and its artifact list is empty. The cause is
unknown; no current native SDK/material/RGB/API export is available from it.
No timeout, deadlock, assertion cause or SDK identity is inferred from labels.

All three downloaded ZIPs and the selected members were checked within the
fixed extraction bounds; artifact code was never executed. The sealed packet
contains 245 payloads, 33,445,236 bytes, with manifest SHA-256
`2d4fd9a71f089a1e62d3efbf63b3739768fcfe460b64679a47777fce9404fb5e`.
The parent verified and retained every payload. No fonts, baseline images,
tolerances, environment settings or workflows were changed by this diagnosis.
These are results for the earlier pushed commit, not qualification of the
new native/List integration. All original completion gates remain open.

### Ninth validation pass: retained UIA test capability (2026-08-29)

The compile at `be76daa842f3b41caa319f0d27a22272773d49f0`
stopped before tests on the UIANativeRequestTests helper passing its optional
opaque provider pointer into Mutex's sending initializer. The direct child
exited naturally with code 1 after 50.203 seconds; there was no timeout or
termination, and source/index endpoints were unchanged. The 979,476-byte raw
log has SHA-256
`637a45709e7f8e2eba343b848d16bd14cc48d6648ee6f7e071e3ee729324607f`.
The earlier attempt's partial compile output did not qualify this helper.

The previously reviewed, unapplied fixture patch now addresses that observed
diagnostic. It stores a private Sendable integer capability for the retained
C provider, rather than sending an opaque pointer through Mutex. The capability
is non-owning: copying it does not AddRef. The existing handle still explicitly
owns one permanent reference, acquires each query reference under the lock,
and releases references outside the lock. Native name queries and all mutable
C output remain outside the lock. Null query/release behavior is unchanged;
this does not make arbitrary native pointers safe to share.

The exact patch has SHA-256
`52b2ed78bc099ea83535ce09bf33b977b5b8ed684b8fb47c76a36bbaf33668ad`.
All 16 complete test bodies and headers remain byte-identical after newline
normalization. Only their private provider holder changes. Contracts, strict
formatting, exact postimage and whitespace checks passed. No production source,
test selection, timeout, baseline or tolerance changes. The focused runner must
now bind five changed selected fixtures, 86 existing methods, while preserving
the other 17 selected files and 234 methods. Fresh compilation and execution
remain required; all nine original completion gates remain open.

### Ninth validation pass: compiled registrations and first executed cohorts (2026-08-29)

At `cdd5fd2c80bffc2b0ca0db7ddd064d5b022a9e04`, production and test
compilation succeeded. The portable window-owner run exited naturally with
code 0 after 235.203 seconds, including compilation. All ten expected XCTest
identities started and passed once, with no failure or skip; the separate
Swift Testing run explicitly reported zero tests. Source/index endpoints
were unchanged. Its 5,059-byte log has SHA-256
`715ff4e30cbf85171b5c44bb28c341458029ef3b8b0472b398037399aabf2e95`.

Before another build, the generated discovery files and current source were
captured and joined against the immutable 771-case native/List inventory.
All 765 expected asyncTest wrappers and six direct registrations are present
exactly once. The six direct entries all belong to the non-MainActor
NativeHostPresentationQueueTests class. The separate 31 bitmap and three menu
methods also have their expected async wrappers: 805 registrations in total.
All 59 current source files match their committed text and expected method
headers. This is registration evidence, not execution of the other cases.

The retained capture is
`artifacts/goal-ninth-cdd5-test-registration-capture-v1`; its 66-payload
manifest has SHA-256
`a17cd4e46d8e5e439a06c7e27b29e9188ee4f057ac55a975a2f2d63b564351bb`.
The observed linked test output is 540,614,656 bytes with SHA-256
`11bcf57d42b8ba38e51f9e2b05cec4db7cde584d50dd24f2da6a4c336e7358d7`.
That association does not supply an embedded revision or independent evidence
of the loaded image. An unrelated old debug executable was not substituted.

Two further serial focused runs at the same clean commit passed. The new
bitmap-placement/menu cohort passed all 34 identities with no skip or failure
in 4.968 seconds. It covers admission, CPU placement, actual text services and
menu state bits; it does not execute a native window, real menu or GPU draw.
The image/editor/responsive-layout cohort passed all 64 identities without skip
or failure in 13.828 seconds, including its two actual offscreen D3D11
comparison methods. Both runs preserved source/index endpoints and explicitly
reported zero Swift Testing cases. Their raw logs are 11,711 and 19,040 bytes,
with SHA-256 `23bb444b8032c4c6fca063371c0b96f797023e504f038d63dee2406b1eaa67c2`
and `dbf0d36792b3fdfa6da7973d0d6e5b084f0dd8e50490ae20e7ebcfb58d71c242`.

The three retained bitmap gallery fixtures were rendered again and inspected
at original resolution. Cap insets, tiling and aspect fit retain exactly the
same encoded PNG bytes as their earlier reviewed captures. The actual generated
resource bundle was copied and both PNG asset hashes remained exact. This run
is retained at `artifacts/goal-ninth-bitmap-gallery-cabcf97cec0d4f7fae525842c00a30cf`.
Neither the 85 reviewed baselines nor tolerances changed. These three CPU
fixtures and copied resources do not establish native presentation, a relocated
executable, macOS parity or clean-machine deployment.

These 108 executed cases and the larger registration inventory do not replace
the remaining native/List tests, combined Full validation, actual native-window
checks or any other original completion gate.

### Ninth validation pass: retain UIA discovery failures and improve diagnostics (2026-08-29)

The first 320-case native/runtime selection at the same `cdd5fd2` commit
stopped at its eighth class. Seven preceding classes passed all 136 cases.
UIANativeItemContainerIntegrationTests then ran ten cases: seven passed and
three failed while unwrapping the initially discovered ItemContainer provider.
Its runtime-backed geometry, pending-replacement and deleted-token cases did
not reach their later behavior assertions. In total, 146 cases ran, 143 passed,
three failed and none skipped; 174 selected cases in 14 classes remain unrun.

The runner returned 1 naturally after 70.969 seconds. All observed direct
children exited, with no timeout or termination; source/index and required
input endpoints were unchanged. All ten executed SwiftPM invocations have
explicit Swift Testing start/zero-footer observations. The failed class's
5,251-byte log has SHA-256
`d004541c2db20ad4bf5560da9cbf45c3c4cda138ed5bb99ca1b071447ed31a17`.
The partial run and per-class records remain under
`artifacts/goal-ninth-native-core-0142f0cbf24c`; this is not a complete Core pass
or independent full-journal audit.

A separate 402-case List invocation compiled but did not start any XCTest.
Windows process launch reported NSCocoaErrorDomain 258 with underlying error
206; the script returned 1 naturally after 4.750 seconds. The small authored
regex did not bound SwiftPM's expanded XCTest identifiers. Its 3,414-byte log
has SHA-256 `909e8d7c30fc9acbf12b15c391b9bf2380da358528733ac57525879bf347645c`.
The observed zero-case Swift Testing run is recorded separately and cannot
turn this launch failure into a test pass. The existing exact-class/method
sharding must be used for this larger selection.

The UIA fixture now records the HRESULTs already produced by its existing
pattern and navigation calls. Its recursive order, pointer branches and
release positions are unchanged. A failed unwrap reports the first native
failure, bridge failure, retained List and row-factory counts, and passive
logical/managed currency flags. The failure message does not run on success,
project snapshots, settle layout or invoke authored callbacks. All ten complete
test bodies and their assertions remain unchanged. Contracts, strict formatting
and exact postimage checks passed. This diagnostic addition does not claim a
product fix; the three provider-discovery failures still require investigation.

### Ninth validation pass: deterministic dialog fixture endpoints (2026-08-29)

Source review of the held dialog cohort found one fixture that installed the
public default Win32 file-dialog provider from a binding getter. Its intended
route uses an injected native session, but an incorrect fallback could reach
real common-dialog endpoints. That instance now retains the concrete Win32
provider and its native-owner capability while injecting four endpoints that
fail the test and refuse the operation. Open/save return false, the error
query returns a nonzero error, and the active-window query returns nil.

The existing internal injected initializer accepts an explicit capability
argument defaulting to false. All four existing injected callers retain their
previous behavior, and the public no-argument initializer is unchanged. An
explicit assertion reads the public default's native-owner capability before
installing the guarded instance. This preserves the original fixture's
production-default contract instead of merely forcing true in its replacement.
Constructing that temporary default object only stores its native closures;
the assertion does not invoke them.

All 20 method headers and 363 existing XCTest calls remain, with the four
refusal guards and the one capability assertion added. Getter context,
session execution, callback order, continuations and cleanup are unchanged.
The exact two-file patch has SHA-256
`8e847ce0eb1c1b89d9adaf43e8f8096d2d5e46e858dc8226b535292293285751`.
Source review, exact postimage checks, strict formatting and contracts passed.
The earlier proposal without the explicit public-default assertion remains
unadopted. This is a deterministic fixture guard, not an OS sandbox or proof
of native-dialog behavior. The existing asynchronous waits still need bounded
execution, and this held cohort remains unrun at this checkpoint.

### Ninth validation pass: managed List build admission (2026-08-29)

The diagnostic rerun at `2ce2a2e` executed all ten UIA ItemContainer cases:
seven passed and the same three runtime-backed cases failed. Every failed
fixture retained one List and a current managed descriptor, but had no current
logical snapshot and zero row-factory calls. Neither the first native HRESULT
diagnostic nor the bridge's native-failure diagnostic reported a failure.
The runner returned 1 naturally; source/index endpoints were preserved.
The 12,260-byte log has SHA-256
`d10885010fecd7d38cb07e581f8539e1decfe70806a6c8c7806e190253d91263`.

A separate unchanged eight-case MountedLazyListStateTests run at that same
commit also returned 1 naturally. All eight cases failed, with 15 assertion
failures and no skipped cases. Initial row captures were absent on both layout
and render routes. Its 7,581-byte log has SHA-256
`f7b628de25835564aa401e52a2cdfda1a8a5c1027c087159e05550bf7863cc77`.
Both focused runs have exact once-only XCTest identifiers and explicit
zero-case Swift Testing observations. These are reproduced failures, not
completion evidence; the raw logs and reconciliation remain under `artifacts/`.

Source tracing found that managed List admission rejected its own build-start
invalidation. A layout visit captured revision R; the runtime-owned callback
inside `beginBuild` retired settlement evidence by incrementing R once. The
immediate managed-only guard then required the old R, stopping before the
managed epoch and row preparation. The runtime now accepts only that exact
checked increment at this one guard. The original pass, viewport, attachment,
identity, lease, scroll offset and scroll-epoch checks remain. Other callers
continue to require the original revision. Overflow and any additional
invalidation still reject admission; the global settlement clock is unchanged.

Four additional async regression cases cover first layout constructing bounded
visible rows without appearance callbacks, geometry changed and restored during
the lease getter, an already busy build coordinator, and generation exhaustion
before any row factory. All 550 existing test paths remain unchanged, including
the original State/StateObject and UIA assertions. Exact patch replay, strict
formatting and architecture contracts passed. The two-file source patch has
SHA-256 `9e5d318b61b1dfa0cd1b4ec2e1d7b5697b1f20ebfdf382b70431e348ea28cfd5`.
Compilation and execution of this repair remain pending at this checkpoint.

The state run also exposed a distinct pre-layout metadata problem: its first
case expects the already-declared 32 logical records before asking for layout,
but the adapter reports zero until preparation. Equivalent public List tests
require this metadata contract too. The admission repair does not address that
separate failure, and the existing assertions are retained. No original goal
gate is closed by either the diagnostic evidence or this source repair.

### Ninth validation pass: accepted logical counts and subsequent failures (2026-08-29)

The admission repair at `9ea5289` compiled and passed all four new regression
cases. The unchanged eight state cases then passed three and failed five;
the unchanged ten UIA ItemContainer cases passed nine and failed one. All
three original provider-discovery failures were resolved, allowing the tests
to reach their later assertions. The remaining failures concern the declared
count, surviving state owners across rebuilds, and later item realization.
The complete focused result is 22 starts, 16 passes, six failed cases and
26 assertion failures, with no skips. The runner returned 1 naturally after
301.672 seconds including compilation. Its 1,309,641-byte log has SHA-256
`ff052c455db9b64f212e5a1e565a4513fe7dbfc1b305d78bff32a798c74182bc`.

The logical-count repair now carries the already-captured metadata's generation
and scalar row count in the native managed descriptor binding. The adapter
exposes that count only while the binding is current and the same descriptor
remains accepted. Provisional, stale, replaced, revoked or closed managed
bindings return zero; they cannot borrow old prepared tokens. Unmanaged
adapters retain their previous token-count behavior. The getter calls no
provider, builds no rows and grants no physical snapshot, layout, scrolling or
accessibility authority. The facade retains the same immutable metadata it
already owned; the native binding does not acquire its keys or row payloads.

Four additional async cases cover that separation, replacement and closure,
provisional/revoked bindings with a provider-call counter, and key-payload
release while a native count binding remains retained. Two existing fixture
helpers pass their original captured metadata into the explicit initializer;
all 50 test bodies in those files remain unchanged. Exact postimages, strict
formatting, contracts and source review passed. The six-file patch has SHA-256
`01418d7a3b362215d37d150dcc1961cec49841f038f9314474271696a623df09`.
Execution of this count repair remains pending at this checkpoint.

Two further closed runs at `9ea5289` retain additional failures. The new
exact-class sharded 402-case runner entered its first class, passed seven
DeferredConsumerLabelTests cases and failed one with 32 assertions; 394 cases
in the remaining 28 classes were not entered. The 13,375-byte log has SHA-256
`d546857eaa602d3fd081f109de8f9b93076791eb0471868f7d49208ad53a51b6`.
The separate public accessibility/projection run executed 24 cases: 15 passed,
nine failed and none skipped. Its 40 XCTest failures include five unexpected
unwrap errors; all nine projection-admission cases passed. XCTest execution
took 447.511 seconds, and the runner returned 1 naturally after 452.453 seconds.
Its 19,837-byte log has SHA-256
`12a8fa8aa04872cd4c5ec0d1f97b6edc1e6ff302285312bb4602254be0ee449a`.
These runs had explicit zero-case Swift Testing observations, preserved
source/index endpoints, and no timeout or termination. They are not complete
cohort passes. Label identity, realization, prefetch behavior and the observed
large-list construction cost remain assigned investigations; no original
completion gate is closed.

### Ninth validation pass: retain managed row ownership during replacement (2026-08-29)

The four remaining state-identity failures after initial row admission use the
internal ManagedLazyListContent primitive. It created a fresh source and empty
adapter on every descriptor rebuild, unlike public List's existing checked
predecessor continuation. Reconciliation therefore removed the old physical
cohort as an accepted replacement. That removal retired owned permissions and
cells even when their logical keys survived. Viewport eviction uses a separate
path that preserves cold state, explaining why eviction passed while rebuilds
reset state and created replacement StateObject instances.

The internal primitive now uses the same checked predecessor, staged typed
source and adapter continuation as public List. The row-construction callback
and its checks are unchanged. Source creation and installation failures still
close the uninstalled source. Logical deletion remains authoritative and revokes
removed membership before cleanup; transferring a cohort cannot restore a
deleted row's write permission. No retirement guard or resource limit changes.

Four new async cases cover the descriptor-to-viewport gap, actual synchronous
State invalidation, deletion, and accepted absence followed by reinsertion.
They use the real retained host and coordinator, preserve surviving owners and
objects, and require obsolete bindings to remain unwritable. Existing state
and other test files are unchanged by this two-file patch. Exact application,
strict formatting, contracts and independent source review passed. The patch
has SHA-256 `66b040032d73b65dbdda3bc93d510b68720d779be515dbe74a4dfcfa9126f86b`.
The separate count repair remains intact. Compilation and execution of the
combined repairs are still pending, so the previously recorded failures remain
open evidence until their unchanged assertions pass.

### Ninth validation pass: independent control-label identities (2026-08-29)

The failing nonempty deferred-label case exposed shared retained identities
between a control's independent label builders. Picker, Slider, ordinary
ProgressView and Gauge reused the same identity context for their main,
current-value or bound labels. Matching local occurrence paths then selected
the same State owner under different descriptor attributions. The existing
ownership guard correctly rejected that candidate, leaving the initial root
empty. Static and deferred trees could therefore compare equal while the
separate positive root/text assertions failed. Single-label DatePicker and
ColorPicker cases did not have this collision.

Each affected consumer now uses stable distinct role contexts consistently for
both materialization and component construction. Picker options also use their
content role. ProgressView's configuration-label paths are unchanged, and the
ordinary primitive uses those same main/current roles. Three explicit Core
identity roles distinguish minimum, maximum and marked-value label builders.
Clients that exhaustively switch over the public Core Role enum may need to
handle the added cases; retained identities are not a persisted file format.

Global composition timing, descriptor rejection and lazy structural expansion
are unchanged. Four new async tests place the same stateful custom view type
in each label slot and require visible text, independent State owners/values,
the same owners after reload, and rejected writes after host closure. All
existing deferred-label and structural-composition tests are preserved.
Strict formatting, contracts, exact postimages and independent source review
passed. The three-file source patch has SHA-256
`ab14afd97e8036781f89501a7c67946376fab16864388e2e6589ea6c866fe57f`.
Runtime results for this repair are pending; it does not qualify complete
control behavior, appearance or native SwiftUI parity.

### Ninth validation pass: avoid copying the whole checked key map per write (2026-08-29)

The closed public accessibility run exposed expensive large-list construction:
single 50,000-record fixture cases took approximately 43.380 to 45.086 seconds,
the two-fixture closure case took 87.221 seconds, and the three-generation
replacement case took 128.159 seconds. Source tracing found that checked-map
insertion retained an entire prior dictionary through every write. Swift's
copy-on-write behavior therefore copied all existing buckets on each insertion
even when no caller needed a separate map snapshot. Metadata collection and
scroll-source installation both use this helper.

ManagedKeyedMap now pins only the affected collision bucket through its final
admission check. Untouched buckets remain owned by the current map; snapshots
actually held by callers still have normal independent value semantics.
Departing keys and values stay alive through publication, and their later
cleanup can still revoke the caller's permission before its required recheck.
The change does not bypass authored hashing/equality or source-validity checks.
Deliberately colliding keys still require searches within their bucket; this
is not a claim that arbitrary application key operations have constant cost.

Four new async tests cover replacement and removal cleanup ordering, deliberate
collisions, independently retained map copies, and 4,096 distinct-key inserts
without rehashing stored authored keys. These preservation tests can also pass
on the old implementation and are not themselves a measured speed result.
All existing tests are unchanged. The narrow helper patch was composed with
the separate metadata-count change without replacing that file wholesale.
Strict formatting, contracts, exact composition and independent source review
passed. The patch has SHA-256
`75ecae54caf2d99fdbb3ceec743f0bdf846e86112e5272fb5bff7f76174e39a0`.
The unchanged large-list cases must still be rerun to measure the combined
repairs. No fixture size, deadline or acceptance threshold was relaxed, and
the original hardware performance gate remains open.

### Ninth validation pass: keep checked prefetch output beside its candidate predecessor (2026-08-29)

Two public accessibility cases reached their layout setup but could not find
prefetched row 3, despite its factory having run. Another case reconstructed
optional rows after an empty result. Preparation checked only previously
accepted predecessor summaries, so it discarded optional rows whose immediate
predecessor was already present in the same new candidate. Missing optional
prefetch did not itself request another resolution pass.

Preparation now tracks current candidate records by native source ordinal
after they pass capacity and duplicate-node checks. An optional row can remain
when its preceding boundary is supplied by those earlier checked records,
including a contiguous empty candidate chain. The check revalidates the prior
record and reads its current node summary; it does not reuse a summary across
later application callbacks. Carried records and discarded predecessors do not
gain this authority. The scan advances through distinct earlier candidate
entries and is bounded by the physical record allowance.

This changes candidate retention only. Accepted boundary publication, measured
extents, adoption, generation checks and settlement remain on their existing
paths. Four new async cases cover ordinary and empty-chain prefetch, an
oversized discarded predecessor, and source revocation during construction.
The two raw-adapter cases establish candidate selection, not native adoption.
All existing tests are unchanged. Exact composition with the count repair,
strict formatting, contracts and source review passed. The patch has SHA-256
`7df9b57bfd48ee8818172b11bf0eedbfe8428527255d1fedb3dcfa4e1f67a0f6`.
Runtime validation remains pending, including the separate default-budget
Realize failures. No work budget or original completion requirement changes.

### Ninth validation pass: diagnose complete logical realization budgets (2026-08-29)

Four additional async source-route tests now exercise the pending-replacement
realization flow with the unchanged default four rounds, explicit eight and
sixteen rounds, and an explicitly exhausted one-round/one-element budget.
The positive cases retain completion, ordinary projected-item state, stable
identity count and bounded row-construction assertions. The exhausted case
requires refusal without renewing its shared budget. Their passive diagnostics
report the completed call's counters, stored settlement state and retained
adapter state without an extra layout or snapshot query.

These tests do not change production defaults or existing oracles. They are
intended to distinguish missing settlement work from budget exhaustion after
the separately repaired admission, ownership and prefetch paths. They exercise
the shared realization source route without COM or an HWND and do not replace
the existing native HRESULT, property, action and focus tests. Exact application,
strict formatting and source review passed; the diagnostic patch has SHA-256
`8441e358dee14ce74330d5e5178cec6f54ce1ebd126461d7386be7a2deadb59d`.
All four require execution before drawing a conclusion about the remaining
Realize failures. No completion gate or work limit changes here.

### Ninth integration: combined List regressions and native service tests, 2026-08-29

- The clean execution commit was `f7d055f614ecee0f4c4a034a580e0a5db4663428`,
  tree `96b02077b60fde83ac4ef796edb35b2bd55b38cd`. The fixed 88-method run
  compiled successfully in 346.33 seconds and then reported 70 passes,
  18 failed methods, zero skips, and 77 XCTest failures (8 unexpected).
  XCTest took 116.475 seconds; the direct-child wait took 467.610 seconds.
  Tool closure was `c2f659` / session `45374` -> `f3a807/1`, not a pass.
- All four control-label identity, eight deferred consumer-label, four
  candidate-prefetch, four map-storage, four build-admission, four logical-count,
  nine projection-admission, and three public binding tests passed. Internal
  replacement state was 2/4, mounted state 5/8, public lifetime 6/7, public
  accessibility 6/15, native ItemContainer integration 9/10, and the four
  realization-budget diagnostics 2/4. These are separate method outcomes,
  not a claim that any original product completion gate has closed.
- The realization diagnostics distinguish the remaining convergence problem:
  the default four rounds exhausted after seven elements, while eight rounds
  exhausted after eight elements. Both left the target as a placeholder and
  layout unsettled. Sixteen explicitly configured rounds passed. The separate
  one-element/one-round exhaustion test also passed. Production limits and
  existing assertions were not increased or weakened to obtain those results.
- The missing initial prefetch-row assertions now pass, but later replacement,
  precise reveal, scroll-intent, and inactive-owner cases still fail. In the
  two new replacement tests, the pre-layout checks that deleted owners are
  revoked and old bindings refuse writes passed; stale captures after failed
  rematerialization must not be mislabeled as proven owner resurrection.
- The unchanged public accessibility class took 50.941 seconds, compared with
  446.878 seconds in the earlier `9ea5289` run. Its unchanged logical-enumeration
  method took 3.755 seconds versus 43.380 seconds. This supports the usefulness
  of removing the forced dictionary copy, but is an uncontrolled debug-test
  comparison across the other reviewed fixes, not hardware timing acceptance.
  A bounded source follow-up found no second whole-metadata copy per row on
  this one-segment path. Mixed projection-segment and many-List-declaration
  costs remain separate, unqualified workloads.
- The 88-method raw log is retained at
  `artifacts/goal-ninth-list-repair-cohort-f7d055f-2640fcc687fb43bc98211d99e0a99b74/raw.log`
  (1,013,833 bytes; SHA-256
  `035dfeebb44fe6b84d231e3f989af09e45ac19629d7366940caa11f12bffa01c`).
  Parent reconciliation `0f9438/0` independently matched all 88 expected starts
  and terminal IDs, no duplicates/skips, the zero-test Swift Testing footer,
  and the complete source/index endpoints. The runner was a byte-preserving
  derivative of the reviewed 900-second runner, changing only its two filter
  literals (20,118 bytes; SHA-256
  `d39123e358d26fa8f8f82c7d47a9b6aa8ae7b17aaad86b60a0fe1d6daaab2eb6`).
- The fixed 402-method serial List run now passes its first three classes:
  deferred consumer labels 8, deferred List projection 14, and checked keys 19.
  It stops at all four declared-owner continuation methods, with 102 assertion
  failures. Thus 45 cases ran: 41 passed, 4 failed, 0 skipped; 357 cases in
  25 classes remain unrun in this attempt. Tool `3f1763` / session `26102` ->
  `81a857/1` closed naturally after 57.047 seconds. The failed class log is
  `artifacts/goal-ninth-list-f7-4312747b8192/c04/raw.log` (33,876 bytes; SHA-256
  `a6538b2d40a6b2076e5e477c8e130b8cb228653220df03cf057969f4d96e0521`).
  Parent reconciliation `6045a1/0` matches the exact IDs, source/index endpoints,
  and producer summary counts/sessions. It is not an independent full journal
  audit, and earlier passes are not combined with unrun cases into a suite pass.
- All 39 formerly held dialog/URL service methods passed on this same commit:
  native dialog ownership 20, startup deferral 5, and URL routing 14. Tool
  `2bdec0/0` observed natural child and runner zero; wait was 5.187 seconds.
  Parent reconciliation `4c49ae/0` confirms 39 distinct starts/passes, no skips
  or failures, the zero-test Swift Testing footer, and unchanged source/index.
  The raw log is
  `artifacts/goal-ninth-native-services-f7d055f-cb812b66a7e243d896ca83b6d115f5a4/raw.log`
  (11,936 bytes; SHA-256
  `9d3c4ae1087954dfc818a0a7d26c8b7eadec9efa1771b8d6acfbfc90609ba33e`).
  These use injected command, dialog, and shell services; they prove no actual
  HWND, common-dialog, ShellExecute, file-write, or native pump flow. The
  earlier deterministic legacy-endpoint refusal guard remains in effect.
- Every attempt above closed without timeout or termination and required no
  operator cleanup. These observations do not prove descendant closure,
  continuous source immutability, a full-suite pass, visual parity, or a release
  qualification. No font, baseline, tolerance, or environment policy changed.
- A follow-up diagnostics-only change adds passive failure messages to the two
  new replacement cases. It retains all four method IDs and 67 assertion calls;
  removing only the two messages and helper reconstructs the exact previous
  source. It adds no layout, provider, callback, or budget action. The patch is
  2,522 bytes, SHA-256
  `acf4a9ff50a31cb4ddca0d41ac7c18a27d117b89fcb96e43a9a5b95b6d78c7b0`;
  source postimage is 11,245 bytes, SHA-256
  `ecda90fb378698ebf6e4e6e462878e80c4af0f8832c2ae040be51c408c27a586`.
  Parent application `d6f2ad/0`, strict lint and contracts `303cbd/0` passed.
  These added messages have not yet been compiled or executed. All nine
  original completion gates remain open, with the original goal unchanged.

### Ninth integration: material inside content blur, 2026-08-29

- The reviewed material feature now joins the compiler-corrected native/List
  foundation after `6a74ab564862774db34fd25171647e3b58f4b103`. It preserves the
  original goal, all previous execution records, and all nine open gates.
  Source origin is `d295472355928e72fb87381c5a3acea2efcf1578`, based on `cdd5fd2`;
  the actual integrated commit and future execution must be recorded separately.
- Material-dependent content blur now carries an explicit isolated backdrop
  input through retained painting, scene replay, the CPU rasterizer, and D3D11.
  It filters premultiplied foreground and replacement coverage separately, then
  composites them against the live destination at each image occurrence.
  Transparent padding and empty groups therefore do not import an entire
  backdrop rectangle, and translucent material alpha is not mistaken for
  replacement coverage. Nested namespaces and presentation order remain explicit.
- The D3D11 path uses real texture copies and shader passes, with per-occurrence
  scratch targets and explicit cleanup. Material-free content retains its
  independent cached bitmap route. These are implementation facts pending
  execution; no GPU pass, live-window result, or native SwiftUI parity is
  inferred from CPU code or source inspection.
- Admission retains the existing 1,024-source, depth-32, 4,194,304-pixel
  per-source and 16,777,216 cumulative ceilings. Each dependent occurrence
  reserves eight times its area, so an isolated source is limited to 2,097,152
  pixels by that cumulative allowance. The GPU uses at most six full-size local
  planes per active isolation. These structural limits are not a bound on all
  process allocations, GPU work, or qualified frame time.
- The feature adds 52 async methods: 15 scene/admission contracts, 21 retained
  and CPU cases, and 16 D3D11 cases. The existing historical stripe fixture keeps
  its exact identity, 100-by-100 input and inline/group smoothing bounds. Its
  known-bug content-blur assertion becomes the same positive smoothing bound,
  and the unconditional skip is removed. No other existing assertion, visual
  baseline, pixel tolerance, or font selection changes.
- Parent intake preserves the reviewed 350,974-byte patch, SHA-256
  `a635193574f03690974c1e071f74bd406ea314e2daee5e343bc07e359bbb4bd6`, under
  `artifacts/goal-ninth-material-cdd-source-intake-v1`. Parent application
  `4fcf74/0` passed without conflicts and matched all fourteen reviewed Swift
  postimages exactly. The delta is nineteen feature paths: ten production,
  four test, and five documentation files. Runtime, List/state, native host,
  Package and existing label fixes are outside that delta.
- Strict lint on all fourteen Swift files and architecture contracts passed
  (`a7bf77/0`). Independent composition review also found no production/test
  overlap with FilePreview or NativeSmoke; their only shared path contains
  disjoint Testing documentation hunks. This commit is still uncompiled and
  unrun. The upcoming serial run must verify the 52 new cases and the existing
  render-pass regression class. Native modifier-edge semantics, general clip/
  blend/color composition, Canvas integration, hardware timing, recovery and
  reference comparisons remain open to their original acceptance requirements.

### Ninth integration: bounded asynchronous file-preview template, 2026-08-29

- The reviewed FilePreview feature joins the material/native/List foundation
  after `0a0299fd2990993208a73ae6948aca4ace8cf406`. Its source origin remains
  `ebff7a7e7e8677ca51ad33ba38d684d661202018` on `ab63afc`; that historical source
  identity is not the forthcoming compiled or executed root identity.
- A reusable window-owned model, preview service and shared SwiftUI-shaped
  template provide selection, text decoding, loading/failure/cancellation,
  retry, typed file-URL drop and explicit import actions. The Gallery exposes
  the template using the ordinary List, task, observation, focus and native
  service routes. No framework bypass or Windows-only drawing API is added.
- The default demo still selects Dashboard. Its FilePreview model begins
  suspended; selecting Gallery mounts the template and admits deterministic
  sample preview work. Real file reads require imported or dropped URLs, and
  opening the importer requires its explicit action. This is a source trace,
  not an observed default-startup, idle, native dialog, or teardown result.
- The service limits admission to 64 records and the first 64 supplied URLs,
  32,768 UTF-8 bytes per URL spelling, 65,536 preview bytes, and 8,192-byte read
  chunks plus one overflow probe. It allows one physical read with only the
  latest request pending. Cancellation cannot preempt a blocking OS read;
  metadata checks and opening are separate operations and do not prove
  race-free no-follow behavior or physical file locality.
- The feature adds 85 async cases: 48 model, 23 service and 14 interaction
  methods. All four test/support files and their original assertions remain
  intact. Service cases use owned temporary files; the symbolic-link case may
  explicitly skip if Windows denies link creation. Such a skip must be counted
  and disclosed, not removed, retried with elevation, or promoted to a pass.
- The exact 210,461-byte patch, SHA-256
  `ba01c19c0bbebcc87eb8f07b6852cfd34b3a0b6ff13a1f8279fe6e9eee58e129`, is retained
  under `artifacts/goal-ninth-file-preview-native-list-intake-v1`. Parent
  application `de50fb/0` applied the ten-file delta without conflicts and
  matched all nine Swift postimages to the independently reviewed composition.
  Strict lint and architecture contracts passed (`ce0376/0`). The earlier
  Editor and List-label fixes are preserved rather than imported twice.
- This commit has not yet been compiled or run. Real import/drop/select/cancel/
  error flows, native owner/renderer teardown, settled idle, macOS, Narrator,
  DPI, retained pixel review and performance still require evidence. Full
  media grid/list behavior, asynchronous thumbnails, image preview and outgoing
  drag remain original requirements; this text-preview slice does not replace
  them. The unchanged original goal and all nine completion gates remain open.

### Ninth integration: distinguish measured metadata from changed geometry, 2026-08-29

- The List adapter now distinguishes `extentChanged` bookkeeping from a
  `requiresLayout` signal. Publishing the first actual leaf-count/vector no
  longer invalidates geometry when that record's exact measured total equals
  its estimate and the runtime has already placed its actual leaves. This
  removes a redundant layout round without refunding any work already spent.
- The exception is per record and uses exact equality. A one-ULP size change,
  redistribution of already-known leaf heights, or opposing changes in two
  records still requires layout. Unknown leading gaps still withhold measurement
  and settlement. Existing metadata updates, anchors for changed geometry,
  attachment/visit/generation checks and callback ordering remain intact.
  Production element/round limits and existing test assertions are unchanged.
- Eight new async `LazyListMeasurementLayoutTests` cover five raw signal
  boundaries and three actual managed-runtime cases: exact two-round settlement,
  one-round exhaustion, and shorter rows that expose more work after two rounds.
  These are additional tests, not a replacement for the failed UIA realization
  cases or their four/eight/sixteen-round diagnostics.
- Source origin is `e15af9729e6dd327a6fb8c1ce92812627e8acb31` on exact `f7d055f`.
  The 14,632-byte patch has SHA-256
  `5c8dd4e3ac68450fee6ff2d579703977ca0bc4cbaeda887dc039d01580884e36`.
  Parent intake `e55a7f/0` verified twelve passive payloads totaling 2,265,608
  bytes. Its manifest uses the explicit `payloadFiles` list; the first helper
  call rejected that schema before copying or changing source. The preserved
  original manifest was then read with that explicitly selected list key.
- Parent application `feea27/0` matched all three postimages exactly on the
  material/FilePreview composition. Strict lint and contracts passed
  (`362f3a/0`); source review found no blocker. The new tests and implementation
  remain uncompiled/unrun at this commit. Default-four-round `Realize` is not
  claimed fixed: its existing preparation, target, gap and reveal phases still
  need a separately checked continuation design. Fractional-spacing/large-prefix
  cases and complete original goal qualification remain open. All prior goal
  text and all nine completion gates are preserved.

### Ninth integration: repair two test compiler witnesses, 2026-08-29

- The first combined material/FilePreview/List attempt on `ed01e0a` failed
  during compilation. The direct child exited naturally with code 1 after
  135.937 seconds (`a8165b/session21690 -> 7b7a16/1`). None of its 179 planned
  XCTest methods started, and Swift Testing did not start. This is not a test
  result or a successful build.
- The two distinct compiler errors were test references: a removed bitmap-cache
  member and the runtime's fileprivate attachment property. The material test
  now checks the actual `cachedCompositingGroupBitmap` cache. The List test uses
  the existing callback-free `accessibilityTarget(for:)` attachment query while
  retaining its direct-parent identity assertion. That query checks every
  ancestor's exact runtime and physical child membership through the root.
- These are the only two expression corrections. All 24 affected test methods
  and all 190 XCTest assertion calls remain. No production API, expectation,
  tolerance, budget, skip, or test selection changed. Strict lint and contracts
  passed (`e882d2/0`); the corrected tests still need a fresh execution.
- The closed failure, exact old/new test hashes, and source/index preservation
  are recorded in `artifacts/goal-ninth-ed01-compiler-corrections.json`. Its raw
  log is 2,761,222 bytes with SHA-256
  `68acff03a0d6d362b4d1806902ec801831970c7c2554eb62416cf4daf7df14cd`.
  All prior goal text and the nine original completion gates remain unchanged.

### Ninth integration: preserve accepted managed rows across width changes, 2026-08-29

- A width-only layout change previously refreshed the complete managed List
  snapshot, invalidating its row configurations and rebuilding the row factories.
  This explains the unchanged width/count assertions in one of the four failed
  declared-owner continuation cases; it is separate from the three TabView
  removal-transition failures.
- For an accepted, complete managed snapshot with the same current generation,
  the adapter now retains only records whose original freshness and exact
  physical attachment proofs remain current. It preserves their nodes, activity,
  identity witnesses and declaration, but clears their leaf measurements. A new
  configuration and attempt still revoke all old layout proofs, including when
  width changes from A to B and back to A.
- Raw providers and changes to scale, content revision, environment revision,
  source generation or incomplete snapshots keep the existing refresh path.
  Provider currentness/prefix callbacks remain checked. Work budgets, mounted
  caps, transition eligibility and all prior test assertions are unchanged.
- Five added async tests cover physical row/State retention, a writable escaped
  binding with exactly one invalidation, stale proof rejection, and the existing
  rebuild requirements for scale/content/environment changes. The four original
  declaration tests remain byte-identical. The earlier measurement/layout
  distinction is preserved by applying the two narrow patches, not replacing
  the adapter with an older whole-file postimage.
- Source origin is `b46e88a43a382c3bee511ab3ed51130f2d45cc34` on `f7d055f`.
  Parent intake `24f41c/0` verified eight passive payloads totaling 20,414 bytes
  under `artifacts/goal-ninth-list-width-context-intake-v1`. Its manifest SHA-256
  is `4f27fa153c2e55709ee5e97cd67cca5282f2f726035f88025e25bce6faf0e23a`.
  Parent application, strict lint and contracts passed (`4e8737/0`). These
  changes still need compilation and execution on the composed source.
- This does not qualify TabView retirement or default-budget UIA realization.
  Their remaining failures and every original completion gate stay open.

### Ninth integration: measured failures and managed replacement finalization

At source `6a55df0f617cb44faa70377dea4c490b10a30553`, six naturally closed
focused runs covered 158 distinct methods from the previously selected 188:
145 passed, 13 failed, and none skipped. The classes were List25 (17/8),
MaterialContract15 (15/0), MaterialCPU21 (18/3), RenderPass26 (26/0),
FileModel48 (48/0), and FileService23 (21/2). The 114 List and 39 material CPU
assertion messages are not counts of failed tests. The new Measurement8 and
Width5 classes passed. The unchanged four-round and eight-round realization
cases, two managed replacement cases, and all four declared-owner continuation
cases still failed; sixteen-round and one-element/one-round controls passed.
The individual run directories, raw hashes, exact selected method reconciliation,
and independently compared source/index endpoints are retained in
`artifacts/goal-ninth-*-6a55df0-reconciled.json`.

The original combined 188-method attempt completed compilation in 266.89s but
timed out at its unchanged 900-second limit. A separate FileInteraction14
attempt built in 0.37s and also timed out. Neither produced observed XCTest
start or terminal lines, so individual execution and outcomes remain unknown.
Both controllers recorded exit 124 and closed their direct PowerShell child;
the parent then verified creation identities and retained process handles,
terminated only each owned XCTest process, and observed the Swift/PowerShell
parents exit naturally. Subsequent ancestry checks found no recorded child
remaining. The FileInteraction attempt includes two noninvasive, nonsuspending
local stack samples, which observed retained attachment validation; it is not
a timing qualification. Its abnormal receipt is
`artifacts/goal-ninth-file14-6a55df0-timeout.json`. GPU16 has not yet been run
independently, and the original 188-method obligation remains open.

The replacement source repair moves an existing source-group closure check
from inert handoff reservation to the all-handoffs activation preflight.
Implicit StateObject dependency groups and deferred-reader groups intentionally
remain open while they collect descendant outputs; journal preparation closes
them before physical activation. Requiring closure before preparation rejected
valid replacements and repeatedly rebuilt survivors without accepting a new
mounted snapshot. Reservation still grants no mutation or physical lifetime;
generation, logical membership, attachment, duplicate, and rejection checks
remain in force. All pending handoffs are checked before any one activates.

Six additive tests cover both mounted replacement paths, inherited source
outputs, inert reservation, accepted attachment gaps, and stale source,
membership, or attachment authority. All previously tracked tests and work
budgets are unchanged. Parent contracts and strict lint passed after the
three-file patch. Compilation and runtime results for this repair are still
pending; it does not close the separate realization or transition work.
The original goal text and all nine completion gates remain unchanged and open.

### Ninth integration: avoid an empty List convergence round using current layout evidence

The retained convergence loop can now stop after an already charged changed
iteration completes its ordinary layout pass, when a read-only comparison
proves that every registered List has current accepted measurements and needs
no additional work. This avoids charging a new round solely to discover that
the previous pass finished. It does not run another layout, invoke a provider
or readiness callback, change a limit, refund work, or publish settlement.
The ordinary query epilogue still performs callback draining, final checks,
and prepaint work.

The comparison requires the same budget and resolution sequence, an unmutated
pass, current owner/scroll/leaf attachment proofs, exact viewport and actual
leaf order, and accepted content extent. It rejects first or missing
measurements, stale generations, unresolved gaps, changed gap summaries or
heights, unpublished chrome, incomplete selection, and queued or active
callback, reader, teardown, anchor, focus, or navigation work. Shared viewport
arithmetic has a read-only entry that does not stamp the ancestor cache. The
coordinator exposes only a stored pending-work refusal hint, not a replacement
for settlement authority.

The six-file patch adds 24 tests: 12 adapter comparisons, seven retained-runtime
cases, and five coordinator cases. The positive correction test keeps four
rounds available and expects two consumed, so exhaustion cannot disguise an
unnecessary third scan. Negative cases retain actual round and geometry
assertions. The original Measurement8, Width5, realization budgets, generic
prepare/no-far-row tests, and all previously tracked tests are unchanged.
Parent contracts and strict lint passed; execution is pending. This change
alone does not claim successful four-round UI Automation realization or close
the combined 188-method validation obligation. All original gates remain open.

### Ninth integration: correct transparent material and nested content-blur recording

The three observed MaterialCPU21 failures led to two ScenePainter corrections.
A transparent material still changes the backdrop when its sanitized Float
blur radius executes; emission now uses the same radius as dependency
selection instead of rejecting the quad solely because its tint is clear.
When recording an isolated content-blur source, both finish paths now retain
the suppression flag. They cannot emit an extra fallback Gaussian inside the
source before the consuming blur pass, including around deferred children.
The deferred queue, clip reconstruction, and normal oversized-buffer fallback
remain unchanged.

Three additive material tests cover the Float execution boundary with an
independent kernel expectation, suppression through both finish paths, and
the existing unsized-buffer fallback without allocating a large raster.
Removing only the additive test block recovers the complete previous
MaterialContentBlurTests file, including all 21 original methods and assertions.
Documentation records the corrected pass ownership. Parent strict lint and
contracts passed after applying the three-file patch. These are source repairs;
the original three failed cases and all 24 material CPU methods still require
a fresh execution result, and GPU16 remains separately unqualified.
No baseline, tolerance, budget, or original completion gate changed.

### Ninth integration: preserve test callbacks through Swift actor conversion

The fresh 136-method List/rendering attempt on `4f27e78` closed naturally with
exit 1 after 133.5 seconds. Compilation rejected two method-reference arguments
in the new terminal-checkpoint adapter tests when converting them to an
actor-isolated Sendable callback. Four generic-inference errors followed from
those two expressions. No XCTest start or terminal was observed, so none of
the selected tests, including GPU16, gains an execution result from this run.
Source and index endpoints were independently identical; the closed evidence
is `artifacts/goal-ninth-repaired136-4f27e78-compiler-failure.json`.

Both call sites now pass explicit actor-context closures invoking the same
helper with the same integer. No test ID, assertion, fixture value, helper
behavior, or production code changed. Strict lint and contracts passed; the
136-method selection remains due for a fresh run. Original goals and limits
are unchanged.

### Ninth integration: owned bounded image decoding

The image stack now has an in-memory WIC decoder with an owned renderer-neutral
bitmap result and an ordinary public Image facade. The media policy accepts
single-frame PNG, JPEG, and BMP, checks encoded input at 8 MiB and source pixels
at 16 million, and produces thumbnails with an edge of at most 1024 pixels.
Checked arithmetic precedes output allocation and narrowing. Reported JPEG
orientation is applied, reported color profiles are converted to sRGB, and
premultiplication precedes downsampling so transparent source colors cannot
bleed into visible edges. Swift copies the native result before freeing it;
COM objects close before balancing the decoder's apartment initialization.

A separate compatibility entry decodes frame zero of any installed WIC format
at its full admitted size, retaining raw orientation/color and straight BGRA.
It has the same input and source limits and a 64-million-byte decoded limit.
The media policy never silently falls back to this entry. These resource and
format policies are explicit adaptations, not complete SwiftUI image support.
Neither synchronous API dispatches work or owns a cache, and cancellation
cannot interrupt a codec call already running.

Fourteen additive decoder tests contain real PNG/BMP/JPEG pixel oracles,
transparent-edge and EXIF cases, both policy boundaries, malformed data,
native output reset, cancellation, and public retained Image composition.
The corrected 43-byte GIF fixture contains complete clear/pixel/end codes;
APNG/MPO marker witnesses are not full animated-container conformance tests.
Parent contracts and strict Swift lint passed. Native compilation, decoding,
color/profile qualification, and runtime test outcomes remain pending.
Absent or unsupported WIC color metadata is assumed sRGB; absent or unsupported
JPEG orientation metadata means orientation 1. These limits remain documented.
The original goal and all nine gates remain unchanged and open.

### Ninth integration: browser-owned image workers and bounded thumbnail cache

DemoMediaImageService owns at most two active physical workers, with no
implicit waiting queue; a further load reports busy. Cancellation, invalidation,
revision changes, reload, and close revoke publication without freeing a slot
before the worker returns. File reads use bounded chunks plus one overflow
probe and balance their owned handle. Construction starts no I/O. A caller
owns the service lifetime and each load task; there is no global image cache.

The cache retains at most 32 decoded images and 16 MiB of owned pixels. File
identity includes the admitted lexical URL, caller-owned content revision,
and requested edge. External edits require reload, invalidation, or a new
revision. Eviction does not invalidate image values already held by a view.
Data sources are decoded without entering the file cache. Publication authority
is committed under a lock, then cache/result work and captured-payload release
occur after unlocking, with no actor suspension between commit and publication.

The shared value provides an ordinary public Image. The macOS ImageIO adapter
is confined to the service value, with one explicit immutable CFData raster
shared by its CGImage provider and counted once in cache ownership. Its actual
compilation, pixels, color metadata, and resource behavior remain unverified.
The Foundation metadata/open sequence is not a race-free no-follow open, a
path sandbox, physical-locality proof, or OS-read preemption.

Twenty-one additive service tests cover actual encoded bytes/files, retry,
freshness, cache accounting, eviction, independent instances, draining
cancellation, busy admission, stale completion, and terminal close. Four new
actor-isolated test declarations were made async before integration to obey
the repository's documented Windows discovery requirement; their bodies,
assertions, throws behavior, and all 35 decoder/service method IDs are unchanged.
Parent strict lint and contracts passed, but execution is still pending.

This supplies the image service for the original media-browser requirement;
it does not itself implement thumbnail grid/list interactions or repair the
existing AsyncImage and named-image loaders. Those remain separate tracked
work. No original feature, limit, test assertion, or completion gate was removed.

### Ninth integration: file URL admission and the Foundation constructor boundary

The two failing service tests were investigated with a standalone diagnostic
that copied the exact old validator and input arrays. After an unsuccessful
Swift interpreter attempt and a PowerShell argument-binding error, the parent
compiled it with swiftc and ran it normally. The 35-row successor confirmed
that `file://localhost:/...` retains its empty-port colon in absoluteString
while URLComponents reports no port range. Admission now examines retained
spelling before components, requiring empty authority or literal ASCII
localhost, rejecting query/fragment delimiters, and checking the Windows raw
drive prefix. Existing percent decoding, traversal, device, stream, size, and
cancellation checks remain.

The diagnostic also proved that Windows Foundation converts the literal
backslash input `file:///C:/bad\name` into the same URL value and public
spellings as `file:///C:/bad/name`. Equality, data representation, path,
directory/base fields, and every reported component field matched the ordinary
control. A URL-taking validator cannot recover discarded constructor text and
must not blacklist that ordinary path. The old rejection fixture therefore
changes exactly one input to `%5C`, which retains the prohibited backslash
through construction for the existing single-decode rejection. Its rejection
and zero-reader assertions are unchanged; all other old fixtures and assertions
remain intact. One additive async test covers both constructor equivalence and
encoded-backslash refusal without opening a file.

The parent diagnostic is retained at
`artifacts/goal-ninth-file-url-diagnostic-v2-6a55df0.json`, with SHA-256
`d090539a1979077fc1440b1606d122a1d00cfe875cad938b3467b0867fb37b88`.
It establishes Foundation behavior, not passing repaired service tests.
Parent contracts and strict lint passed after the four-path patch; all 23
service methods plus the new construction case still need execution. This
clarifies an unobservable input distinction without weakening accepted file
URL safety, read limits, the original feature requirement, or any goal gate.

### Ninth integration: deterministic retained file-preview samples, 2026-08-29

- The retained gallery adds loaded, empty, and invalid-UTF-8 file-preview
  samples at 800 by 480 in dark appearance at scale 1. Each uses the shared
  `DemoFileBrowserTemplate` and a fresh production model. Its reader accepts
  only built-in bytes, while the production preview service performs decoding
  and its ordinary size/cancellation checks. No fixture opens a user file.
- A package-only hook captures and awaits the current physical preview task
  once. It does not start/cancel work, wait for future selections, poll, or
  preempt an OS read. The gallery entry point is now async; only selected sample
  fixtures prepare asynchronously. Each checks its exact expected model state
  before rendering and closes its model on normal or error exit.
- Four additive semantic tests cover the idle wait and the three decoder
  outcomes. This gallery patch changes none of the original 85 FilePreview
  methods or their support; the separately recorded URL repair changes one
  fixture spelling and adds its own constructor case. The previous 147 fixture
  definitions, render body, and 85 baseline
  blobs are preserved. The registered catalog is now 150 entries: 107 base,
  16 interaction, and 27 light; the reviewed comparison gate remains 85.
- Source origin is `a700bb01f286c8c17bc03e87413455aa2709a23c` on `ed01e0a`.
  Parent passive intake `bf5905/0` verified five payloads totaling 76,041 bytes
  under `artifacts/goal-ninth-file-preview-gallery-intake-v1`. The original
  3,355-byte provenance file has SHA-256
  `317bc15dfc4d0b3f77bf73fd6f0669ae4df2c8ef0b5e2dc9b6161acd6c83712d`;
  the six-path source patch has SHA-256
  `a8a5f3d59caa8b42526f3f67d84014513ce39462cbfce39f4a0ab5e0e3bee1d0`.
- These samples require fresh compilation, their four semantic outcomes, and
  inspection of every actual retained PNG. Source registration is not visual
  evidence. Native import/drop/dialogs, interaction, narrow layouts, DPI,
  macOS pixels, thumbnails and the full media-browser workflow remain separate
  requirements. No baseline, tolerance, font, or original goal gate is changed.

### Ninth integration: reuse native ancestry checks within one descriptor query

The attachment-validation path observed in the FileInteraction timeout now
shares positive ancestor distances and checked child identities within one
synchronous descriptor validity query. A later ordinary contribution or
enclosing scope in that same native call can reuse structural work. Every
production entry creates a fresh query and discards it before returning; it
cannot cross an authored hash, getter, builder, observer, or mutation.

Cache keys include exact runtime and root identity. Cached suffixes still
require prefix depth plus distance to root to remain below the original
traversal limit. Attachment target IDs, attachment IDs, local identity proofs,
retirement, lifetimes, phase, and supersession checks are not cached. Entries
hold native identities and counters, not nodes or application payloads.
Standalone attachment checks retain their original walk.

Ten additive tests check deterministic structural visit counts, enclosing
scope reuse, wrong targets, changed identities, detach/move/reinsert, alternate
runtime, depth limits, retirement before unlinking, and fresh checks after an
authored hash callback. The independent review traced the selected-row chain
without finding an authored callout in the shared query. All old tests remain
unchanged. The parent applied narrow hunks, preserving the separate handoff
finalization and terminal-checkpoint repairs; strict lint and contracts passed.
Compilation, test results, and improvement of the 900-second timeout remain
unverified. This structural optimization is not a latency or UIA performance
qualification and changes no original work limit or completion requirement.

### Ninth batch: closed repair checks and the file preview visual failure

The following three attempts and gallery generation are bound to the unchanged,
clean `ccff4145767c363010c59210fa77305c4f9301d9`, tree
`b2a03b9eb070d2cb8c4d4101938fd2e7b23e1429`. Each source/index comparison belongs
to its own recorded attempt. These are focused checks, not a Full result or
completion of any original gate.

The repaired 146-case cohort compiled in 347.48 seconds and ended naturally
with **141 passes, five failed cases, and no skips**. All 146 expected method
identifiers have exactly one start and terminal result; the 66 assertion
messages belong to those five failed cases, not 66 distinct cases. The direct
child returned 1 after 452.938 seconds. The separate Swift Testing footer
reports zero tests. The independent receipt is
`artifacts/goal-ninth-repaired146-ccff414-reconciled.json`; the raw log is in
`artifacts/goal-ninth-repaired146-ccff414-6b9da243a53743639fd07297bfcf6a3c`,
SHA256 `adcd7e9deb8276d8ff35a7a91360cc1ccda40fedd84fd5d3a23634cb4f781ae5`.

- All 16 D3D11 material cases, 15 material contract cases, and 26 render-pass
  cases passed. CPU material tests had 23 passes and one failure; all 21
  original cases, including the three earlier failing oracles, passed.
- All four replacement-state, eight measurement, five width, six handoff,
  24 terminal-checkpoint/pending-work, and ten descriptor-query cases passed.
- The default-four-round UIA replacement still failed, although the other
  three realization-budget cases passed. The original budget and ordinary
  element requirement are unchanged.
- One of the four declared-owner continuation cases passed; the conditional,
  explicit-identity, and zero-slot inactive cases still failed. Source tracing
  ties these three failures to the not-yet-integrated managed removal bridge;
  that diagnosis is not a passing execution result for that bridge.

The remaining CPU material failure was the newly authored
`testUnsizedContentBlurStillEmitsItsExistingFallback`, which spent 60.419
seconds in an admitted 4096-square bitmap operation. Source inspection and
independent review established a fixture error: the root surface clip removes
the radius outset before the inclusive 16,777,216-pixel admission check.
4096 squared is exactly that limit, so the observed 67,108,864-byte bitmap was
correct. The fixture-only repair from private `bf8238a692234cba3d4b6f2d90efc5bf6d7fba94`
uses a 4097-square clipped surface (16,785,409 pixels), retains every existing
result assertion and all 24 case IDs, and fails and returns before painting
if the fixture is accidentally reduced to an admitted size. Production and
the 21 original material test bodies remain unchanged. The bounded intake is
`artifacts/goal-ninth-material-fallback-fixture-intake-v1`; its source patch is
1,286 bytes, SHA256 `55935ceef7361ae3b75dc5bf2ec0ef7fd3e324826ece39e6ad1ed064302dd7e6`.
The corrected fixture still requires a fresh execution; the closed failure
above remains recorded as a failure.

The separate file interaction cohort again reached its unchanged 900-second
deadline after a 0.32-second incremental build. Its buffered log exposes no
XCTest starts or terminal results, so all 14 individual outcomes remain
unknown. The controller recorded exit 124 and closed its direct PowerShell
child with exit 1. Cleanup verified all five recorded creation identities,
terminated only the exact owned XCTest handle with code 143, and let its
wrappers close naturally. A subsequent CIM check found none of those processes,
their children, or the recorded console host. The complete abnormal receipt is
`artifacts/goal-ninth-file14-ccff414-timeout.json`; the raw log has 227 bytes and
SHA256 `996bc09f6320559b24086b6f23b3f039cfea5b4d92eb951ffbcd084b17b9341a`.
One local, noninvasive, nonsuspending debugger sample detached normally while
the exact test process remained running. Its incomplete unwind and raw stack
words do not identify an active case or establish a full call chain. This
instrumented attempt is not timing qualification. Source review identified
overlapping subtree completion validation as a separate cost issue still
requiring repair and execution; the successful descriptor-query unit tests
do not establish that this browser timeout is fixed.

After that process closure, the independent file/media cohort ended naturally
with **111 passes, no failures, and no skips**: 48 file model, 23 file service,
one URL-construction, four gallery-preparation, 14 bounded decoder, and 21
media-service cases. All exact method starts and terminal results reconcile
in `artifacts/goal-ninth-file-media111-ccff414-reconciled.json`. The raw log is
in `artifacts/goal-ninth-file-media111-ccff414-ba2e44aed41a42379564cce9a19a945e`,
SHA256 `8579eafffd7820a5bdd7c2dfde65059f042c5c3ccbdde67f4006c07dde00e7f7`.
The reviewed focused-runner derivation now separately records 110 async
methods and the decoder's one nonisolated synchronous method; it preserves
the same bounded runner, exact total selection, and 900-second deadline.
Accepting that signature did not skip or convert any test. These results
qualify this Windows cohort only, not the macOS adapter or complete media UI.

The retained six-entry gallery driver and resource-copy child both returned
0 with source, executable, generated accessor, and asset endpoints preserved.
All six PNGs were opened and inspected. The three 128-square bitmap controls
match every PNG byte of the prior retained control output. The three new
800-by-480 file preview images show their loaded text, empty-file message, and
invalid-UTF-8 failure, but their Files pane is blank despite four model records.
This is an unresolved visual failure, not approved output. Generation success
does not qualify the workflow. The images are in
`artifacts/goal-ninth-file-preview-gallery-72170ad7bced4b4e9802caefbdd5103e/renders`;
the independent comparison and explicit visual findings are in
`artifacts/goal-ninth-file-preview-gallery-ccff414-review.json`. No gallery
baseline, tolerance, or acceptance criterion changed. The catalog remains 150
fixtures with 85 reviewed baselines; those counts describe different sets.

The original 188-method obligation, the new regressions, full validation,
native and macOS checks, and all nine original completion gates remain open.

### Ninth batch: managed List departure without retained executable activity

The managed removal bridge is integrated from the independently reviewed
`9a06fa70ba90f70af7a90bd5974a4137d3881e42`, tree
`3dd535d5a43dddb24127cda5a05662b2c19078cd`, composed over exact `ccff414`.
`artifacts/goal-ninth-managed-removal-ccff-intake-v1` is an alternative context
join of the original removal106 packet, not a second implementation layered
over it. Its manifest SHA256 is
`6ef150327f0a26d987a7ea2ea7ce398b4620cdb2763ca767a9cf972c54760ef8`;
all 42 payloads and 4,434,653 bytes were independently checked at intake.
The source patch is 131,165 bytes, SHA256
`9f67162c54748410186179b4518f99ddfad0dc2f3d836145a55ce2c91fae2513`.
The tests and documentation patches are byte-identical to the original sealed
packet. Reversing that packet from the private composed tree recovers exact
ccff; no conflict workaround or whole-file replacement was used.

This addresses the previously unconditional rejection of a structurally
departing, nonidentity-transition root inside an accepted managed List.
Ordinary removal retains its existing lifecycle rules through a shared
transition resolver. Raw providers retain their existing refusal and cannot
borrow transport authority from a managed ancestor. The bridge neither clears
TabView transitions nor retires all logical State on a descriptor replacement.
The three failing cold/inactive declared-owner cases need this bridge before
their original declaration-retirement behavior can proceed; their original
assertions and the separate default-four-round UIA requirement remain intact.

Normal retained painting records the exact attachment, identity, pose, paint
ranges, and admitted deferred draws before departure. Original native
observations precede Canvas callbacks; an old callback cannot certify a new
attachment or callback assignment. Frozen scenes own their bitmap and glyph
bytes and follow `GPUIScene.presentationOrder()`. Capturing or replaying the
departure never calls the old Canvas, application builder, layout closure,
State owner, task, or cleanup callback. A never-painted attachment has no
outgoing pixels, but still follows the same transaction eligibility rule.

The accepted retirement drain revokes physical, task, input, focus, and UIA
authority and completes cleanup before publishing the visual tail. Logical
State still follows the accepted declaration: an inactive, still-declared Tab
page preserves State; removing its exact identity retires that generation.
Viewport eviction does not create a removal tail. All authored removal
modifiers and clock reads are guarded by the original departing and incoming
native witnesses, including a check after temporary callback payloads unwind.

The tail owns renderer values and native animation values only. It can project
supported inherited opacity at the original primitive boundaries rather than
fading overlapping children as one accidental group. Explicit child effects
keep their separate boundaries; dependent material output keeps its backdrop
domain. Original authored alpha is checked before saturation, including Canvas
operation alpha during the ordinary draw. Existing unrelated root timelines
keep their easing phase; fresh removal properties start from the last painted
pose. Completion and shutdown release visual resources without replaying
application cleanup. The normal GPU scene path submits image render passes;
only the explicitly documented legacy frame fallback can rasterize a complete
already-issued frame while a visual tail exists.

The capture limits are 65,536 primitive records, 1,024 spans, 262,144 inspected
entries, and 64 MiB of retained storage. One normal paint records at most 256
transition roots sharing a frozen snapshot. A runtime keeps at most 32 tails
and 128 MiB of their storage. The live render graph reserves capacity first;
older tails finish when remaining pass/pixel or retention capacity is exhausted.
Executable retirement has already completed at that point. These are concrete
resource policies, not measured hardware performance qualification.

Changing scale/rotation, moving clipped or dependent-backdrop output, changing
a dependent source's target size/DPI, unfinished descendant animations, and
root effects without sufficient opacity provenance remain implementation gaps.
Fractional translation of frozen pixels is not native glyph/hairline parity.
Those gaps still require work under the original goal; refusing them does not
satisfy their completion requirements.

The 20-path source change adds 106 async tests in eight new files and preserves
all 576 existing test files from its ccff base. The parent separately retains
the explicitly documented allocation-fixture correction above. Registry,
Activity, adapter, and TabView source are unchanged by this bridge. Contracts,
strict formatting of its 18 Swift files, source composition, and independent
review are source evidence only. Fresh combined compilation, the original
declared-owner cases, all 106 new cases, retained visual review, native D3D11/UIA,
and full validation remain required. No original completion gate is closed.

### Ninth batch: owned AsyncImage loading and source image density

The image-loading slice is integrated by narrow context patches from
`4f765417f4ea358c5d4911fb6a87b7ff3fbe7fae`, tree
`4699fdc070b6ff4c9ccfb7e34421aa96d517a5a7`, against its recorded `6a55df0`
base. The complete intake is `artifacts/goal-ninth-async-image-intake-v1`:
29 payloads / 3,100,838 bytes, manifest SHA256
`e7c0403f17675e5612e8e30c77f2347d0e058f1c36ba98b3ebab1087f8891920`.
Its 224,078-byte patch has SHA256
`5ce6e3578fc2130bf619ad5aabb32656bd43ae1557a4ad6b518f56b201200ba2`.
It preserves the recent List, material, file, gallery, and removal changes;
newer shared files were not replaced with private postimages.

AsyncImage phases and request lifetime now use the existing mounted
StateObject and task machinery, including a stable container for an empty
placeholder. A per-host service admits at most two active source/decode
operations and 64 queued owners. Cancellation reaches the owned worker and
URLSession data task, removes queued owners before I/O, and retains an active
slot until the actual operation returns. Host shutdown closes admission
before state teardown and drains cancellation after ownership revocation.
The previous global URL-to-phase cache and temporary-file decoder route are
removed. These bounds count source/decode operations, not every Swift Task
object or the native codec's private scratch memory.

Only accepted source adoption can retarget a loader. Completion checks the
original invocation, source, and cancellation before publishing, with native
metadata settled before synchronous phase observers can reenter. Adopted
A-to-B/nil-to-A changes retire the earlier terminal result even if an
intermediate task never starts. A continuously matching URL does not restart
for scale or transaction changes; the latest accepted presentation values
apply to publication. Cancellation is installed before the initial phase
callback so a reentrant successor cannot inherit a stale invocation.

Image density is now distinct from bitmap texel dimensions. Retained
reconciliation copies density, intrinsic point size divides by it, and
cap-inset and tile placement retain the correct source-texel sampling domain.
Changing density preserves bitmap bytes and content tokens. The uncapped
stretch route still admits valid output at extreme finite density without
requiring representable intrinsic point dimensions.

The synchronous named-image cache retains at most 64 entries / 32 MiB of
pixel Data. Hits validate an opened file's identity, byte count, creation and
modification times, and available change time. NTFS stream identity also uses
the opened final stream's exact UTF-16 spelling. Reads use bounded chunks and
an overflow byte. A failed refresh cannot return an earlier cached version.
Filesystem revalidation is an ordinary freshness observation, not atomic
publication, content attestation, or a no-follow filesystem guarantee.

Both paths use the distinct bounded legacy in-memory WIC decoder already
integrated and exercised in the 111-case Windows cohort above: 8 MiB encoded
input, 16 million source pixels, and 64,000,000 tight decoded bytes. Legacy
installed-format/first-frame, full admitted dimensions, raw orientation/color,
and straight BGRA behavior remain separate from the strict thumbnail policy.
The AsyncImage patch does not replace that decoder with the thumbnail service's
format/normalization/1024-edge rules. Synchronous file and codec operations
remain cooperative rather than preemptible; caller-retained images, renderer
resources, and allocator overhead are separate budgets.

The public AsyncImage initializers and phase/error/loader surfaces are retained.
Four new test classes add 124 async MainActor methods: 25 loading, 17 density,
54 cache, and 28 lifecycle cases. No pre-existing test file is changed by this
patch. Exact-source independent review covered actor/lifetime/cancellation,
file identity, bounded resources, sampling units, and API construction.
Contracts and strict formatting of the 11 changed Swift files passed in the
parent checkout. Those are source checks; this combined image/removal source
still requires compilation and execution of the new and original tests.
Actual host/HTTP/file behavior, retained rendering, macOS conformance, resource
qualification, and Full validation remain under the original goal. No baseline,
tolerance, or original completion gate changed.

### Ninth batch: removal path compilation correction

The first combined image/removal run at
`648ddb20db28abac808ef02d47097120f03ba441` stopped during compilation.
`RetainedLazyListPaintSource.isClipped` omitted the required `toLayer`
argument when placing a path in its temporary, single-layer bounds scene.
The call now explicitly selects layer zero, consistent with the temporary
scene used for the other primitive families. No public API, resource limit,
draw-order rule, or test expectation changed.

The retained run is
`artifacts/goal-ninth-async159-648ddb2-d5df8caa54704064a6d11c86fe02b122`.
Its controller recorded natural exit 1, no timeout or termination, and unchanged
tracked source and index endpoints. The 4,484-byte raw log has SHA256
`7bfd6d24ebf250524167f976263e27ffb1188b7d68222f2068445a16caf48bef`.
There are no observed test starts or results, so none of the 159 selected
methods passed or failed as tests. A subsequent process inspection found no
remaining build/test executable in this checkout and no recorded direct child
or immediate descendant. The same cohort must be rerun after this correction.
Architecture checks passed before and after the edit, and strict formatting
passed for the one changed Swift file. The change still needs compilation and
execution. All original completion gates remain open.

### Ninth batch: removal fixture compilation corrections

The next run at `4b628f6d7f89b160c8fd93973be4961e5204133c` compiled the
production image/removal source but stopped while compiling the tests. Two
new removal fixtures needed source corrections: the path-rounding scene now
passes layer zero to `addPath`, and the release hook explicitly captures its
MainActor closure rather than sending non-Sendable `self` into
`MainActor.assumeIsolated`. The latter uses the same capture-list pattern as
existing checked-key ownership tests. The release still happens synchronously
at the same point. No assertions, case identifiers, or production behavior
changed in this correction.

The run is retained at
`artifacts/goal-ninth-async159-4b628f6-f968fc40b2dd49728136a0a1cefa5ca6`.
Its controller and child exited naturally with code 1 after 188.75 seconds
of child wait, without timeout or termination. Tracked files and index
endpoints were preserved. Its 2,951,623-byte log has SHA256
`990efd5b094fcde37911fdb4fab367558a293c528779c014a849873f0a2d370c`.
No selected test began, so the 159 individual outcomes remain unverified.
The two unique compiler errors are corrected here; fresh compilation and
execution remain required. Contracts and strict formatting passed for the
two changed Swift test files. No original completion gate is closed.

### Ninth batch: direct native completion predicates

The first performance-repair slice replaces three native `allSatisfy`
key-path predicates with equivalent closures. It retains the same currentness
getters, order, short-circuit behavior, and validation frequency. This is the
1,571-byte patch from private commit
`002a130e41dcb507af785405e614cae80f214413`, SHA256
`0c2e201a19e3069c9eb7a3a10c5d17f1ae5f37402c781807cf24a997679ce7f0`.

The complete two-slice source packet is retained at
`artifacts/goal-ninth-completion-compaction-intake-v1`: 30 payloads,
3,847,801 bytes, manifest SHA256
`f589567ffcb641ce4bb3964fd89772527af6bc823526667c18a85f3fee30cd27`.
Parent intake checked every payload against its recorded size and hash.
Independent review found no changed admission obligation. Contracts and
strict formatting passed for these two Swift files. No tests changed in this
slice, and no elapsed-time improvement is claimed. The retained File Browser
timeouts still require execution of the full repair and unchanged tests.

### Ninth batch: exact completion snapshot compaction

Nested checked reconciliation previously retained full-subtree completion
snapshots after each child reconciliation. A chain could keep snapshots of
sizes 1 through N and repeatedly validate all of them, causing quadratic
admission storage and cubic cumulative completion-validation work.

The second source slice now removes a snapshot only when another immutable
snapshot contains every exact captured native obligation. The original
admission and incoming snapshot must both be current before compaction, and
the original final admission check remains. Comparisons include attachment
and view-identity tokens, parent/runtime presence and referents, optional
controller/observer/adapter presence and referents, and ordered child IDs.
No proof is refreshed, no application callback is added, and no currentness
result becomes permission for a later operation. External old receipts remain
unchanged and continue to reject stale ownership.

This uses private commit `2fd3f0badf6d870a486777896da5be5177da7e88`, tree
`b72c6a3fc1f26a8309b513a8589a52fd4ac4b234`, from the intake recorded above.
Its 42,202-byte second patch has SHA256
`f5c2df5bafd4d6637e9c2ef8fc32ab5a7d5ea65c766804334450acfefe8bfbbc`.
The parent applied narrow context patches to current shared files. All 576
pre-existing test files are unchanged by that private patch; it adds 15 async
methods in `RetainedLazyListCompletionForestTests`. Existing root compiler
fixture corrections are retained. Independent reviews checked stale-prior
rejection, exact coverage, callback boundaries, and the tests. Contracts and
strict formatting passed for the three changed Swift files in the parent.

For the nested-chain source pattern, admission-held witnesses are now linear
and cumulative completion-validation work is quadratic. Full subtree capture,
independent branches, ancestry/layout work, and externally retained receipts
remain. The tests count explicit fresh validation walks, not every operation
in reconciliation. These are structural source bounds, not elapsed-time or
memory measurements. Fresh compilation, the 15 methods, unchanged File Browser
interaction cases, and actual timeout resolution remain unverified. This
repair does not close any original completion gate.

### Ninth batch: standalone List attachment after GeometryReader adoption

The blank Files panes in the retained gallery were caused by a standalone
build lease tied to a temporary List construction node. GeometryReader
reconciliation kept the previous List node and adopted a new adapter onto it,
but the copied lease still checked the discarded source node. This prevented
the accepted List from constructing its rows.

The adapter now owns a concrete native standalone lease that captures its
first actual runtime attachment. Construction nodes cannot arm it. Builds
require that original attachment and identity proof, expected runtime, exact
adapter ownership, and installed lease. A temporary mismatch while the
accepted adapter and lease are copied does not revoke the incoming lease.
Actual release or lease replacement permanently revokes the outgoing lease;
detach/reinstall and identity reassignment cannot refresh it. A discarded
source cannot revoke the accepted target, and a foreign protocol lease cannot
reopen the opted-in adapter. Managed Lists and raw adapters without this
standalone opt-in retain their existing routes.

The source packet is `artifacts/goal-ninth-standalone-list-lease-intake-v1`,
25 payloads / 2,765,920 bytes, manifest SHA256
`4703904d76914d23829e1dfe3487fdbcb74799f5e88c6b8cc2f54090fb78e399`.
Its private composition is `f4f1f7608be75f3944151e161709095d437ec60f`, tree
`40ded6d0a15ed1fa07fb0147a59cfc2d55bbd6ee`. The 36,052-byte patch has SHA256
`374a7c979b33e558c972b2b35bb38217a77f6def957dd0c398425567452422d3`.
The parent applied the eight narrow file changes without replacing shared
files. All 588 prior test files in that composition remain unchanged by the
patch. Ten new standalone ownership/render cases and three production file
browser cases require visible labels in the first retained scene; they do
not retry rendering until blank output disappears.

Parent contracts and strict formatting passed for six Swift files.
Independent review checked claim ordering, lease copy, permanent revocation,
and unchanged surrounding attachment callers. Compilation, the 13 cases,
existing managed/raw regressions, and renewed inspection of the gallery PNGs
remain required. The separate File Browser interaction timeouts are not
claimed resolved. No baseline or original completion gate changed.

### Ninth batch: completion fixture actor capture correction

The combined 187-case image/List run at
`0912dcb024ebcd9432d8dbbe9b541f6049d3345a` compiled the production changes
but stopped in the new completion-forest test fixture. Its non-Sendable
payload deinitializer implicitly captured `self` in `MainActor.assumeIsolated`.
An explicit `[probe]` capture now transfers only the MainActor probe, retaining
the same synchronous deinitialization counter and all 15 test assertions and
method identifiers. This is a test-source correction, not a behavior change.

The retained run is
`artifacts/goal-ninth-image-list187-0912dcb-318e69b0bcff496ba85a040bf1997fa8`.
The child and controller exited naturally with code 1, with no timeout or
termination and unchanged tracked source/index endpoints. Child wait took
275.907 seconds. The 2,969,216-byte log has SHA256
`7905a76667300510a6faae093ba59b07d395ab924a764ff2acf4f6f520f135a7`.
The repeated diagnostics identify this single remaining compiler error;
there are no observed test starts or terminal test outcomes. Contracts and
strict formatting passed for the corrected file. The same 159 image cases
plus 28 completion/standalone/render cases still require execution, followed
by the prepared removal/blur cohort and original File Browser interaction
regressions. No original goal requirement is reduced or marked complete.

### Ninth batch: executed repair cohorts and fixed-size image placement

The image/List cohort at `02edb4cb233f5684c5efbbc7881843506702a779`
compiled and completed all 187 XCTest methods: 185 passed, two failed, and
none skipped. The 15 completion-forest methods, all three first-scene File
Browser render methods, and nine of ten standalone attachment methods passed.
The failures were the existing unconstrained resizable-image density case and
the standalone first actual attachment after a foreign-runtime render. The
runner exited naturally with code 1 after 341.25 seconds; the 2,060,177-byte
raw log has SHA256
`2fb67b6b47196cca923ce744f45066316c0e0002117bbbd46ad80897f2f6916f`.
Exact method reconciliation and unchanged source/index endpoints are recorded
in `artifacts/goal-ninth-image-list187-02edb4c-reconciled.json`. Swift Testing
reported zero tests; this is not a full-suite result.

The separate removal/blur cohort at the same commit completed 150 XCTest
methods: 145 passed, five failed, none skipped, and zero Swift Testing tests.
All four declared-owner continuation cases and all 24 CPU material cases now
passed, including the previously failing blur boundary fixture. Five managed
removal cases failed: three compared the dark background against a grayscale
contrast value of zero, while two found no insertion animation state. The
latter two remain production behavior gaps. The run exited naturally with
code 1 after 70.766 seconds; its 49,549-byte raw log has SHA256
`3d72f0698ce4424f85a22a6fb226fe0e162e37e1d49ca3ea7c17655196160be4`.
`artifacts/goal-ninth-removal-blur150-02edb4c-reconciled.json` retains the exact
150 starts and terminal outcomes, eight failed assertions, and preservation
checks. The five failed methods are not counted as passes.

The unchanged 14-method File Browser interaction attempt at that commit again
reached its 900-second limit. Build completed in 0.32 seconds, but the retained
227-byte log contains no observed test starts or outcomes. SwiftPM buffers
child output, so this does not prove that no test executed. The controller
recorded timeout 124 and direct child exit 1. Only the recorded test process,
verified through its retained process handle and exact creation identity, was
terminated with code 143; the remaining recorded parents exited naturally.
A subsequent CIM check found none of the recorded processes or their children,
including the associated console host. All tracked source/index endpoints
were unchanged. The timeout receipt is
`artifacts/goal-ninth-file14-02edb4c-timeout.json`; its raw log SHA256 is
`996bc09f6320559b24086b6f23b3f039cfea5b4d92eb951ffbcd084b17b9341a`.
A single noninvasive, nonsuspending local stack sample pointed to repeated
native identity searches in owned-component ledger freezing. The incomplete
unwind is diagnostic evidence, not a complete call chain, identified test,
timing qualification, or proof of the sole cause. No timeout was increased.

For the image failure, measurement produced the correct density-adjusted size,
but stack allocation still treated the fixed axis as greedy and enlarged it.
`fillsMainAxis` now excludes only axes protected by `fixedSize`, including
inherited fill intent through wrappers. The other axis remains flexible.
Intrinsic measurement, source density, bitmap identity, explicit equal-share
distribution, and priority/flex rules are unchanged. This also changes the
existing greedy shrink classification on protected axes; complete compression
and native proposal parity remain unqualified.

The source packet `artifacts/goal-ninth-fixed-image-axis-intake-v1` contains
private commit `a8534967d58f3d0ddf098a1406515fe666989f51`, tree
`5dee6ee622f2ac60ae1bd22ee170793cb06df425`. Its 8,119-byte patch has SHA256
`75736ec14ab087c77148b2538791dae555e1fb9f5c0004e8e492978e5dd52928`.
It preserves the existing 17 image-density methods and adds six cases for
single-axis behavior, nested stacks, wrapper fill, a flexible sibling, modifier
order, and reconciliation of the same bitmap leaf. Parent contracts and strict
formatting passed for both changed Swift files. Compilation and execution of
this correction and the unchanged layout regressions remain required. The
failed standalone case, two insertion cases, File Browser timeout, renewed
gallery inspection, full validation, and all nine original gates remain open.

### Ninth batch: first accepted List attachment invalidates cached layout

The remaining standalone failure in the 187-method run accepted the correct
adapter and lease after a foreign runtime attempt, but the first scene still
contained no rows. The foreign render had cleared dirty flags on the outer
frame wrappers. The later accepted attachment dirtied the root but not that
cached wrapper path, so layout pruned the List before preparing its viewport.

Registration now records whether this adapter already owns the attachment.
Only a successful new claim marks the List and its ancestors dirty for layout.
Rejected claims and repeated registration keep their previous behavior.
The normal layout pass still supplies geometry and build authority; the change
does not rearm a lease, add a provider pass, relax ownership, or change a budget.

`artifacts/goal-ninth-standalone-cached-layout-intake-v1` retains private commit
`4003bf990f0816b18f8fc293fb9161dacdd7eba2`, tree
`30f629604611832deddc6a2bed566298a232cd59`. The 4,520-byte source patch has
SHA256 `60d7f7815d8f31efac9ee3a6d6f523bd3a6badd958aadf9e488856b9762f03c2`.
It changes one runtime registration site and two documentation files. All
591 existing test files, including the original 13 standalone/first-scene
render cases, are unchanged by this patch. Parent contracts and strict
formatting passed for the runtime file. Execution and all six retained gallery
renders remain required; the prior 12 passing scene cases are not evidence
that this new correction has run. Standalone navigation lifetime and insertion
animation repairs remain separate work. No original completion gate changed.

### Ninth batch: exact background pixels in removal fixtures

Three managed-removal cases used a grayscale contrast assertion for pixels
that should equal the application's dark background. That background is
`surface0.dark`, RGB `0x17171C`, so its channels differ by five even when no
removed row is present. The offset case already reported this difference in
its initial empty control, before any removal. That evidence and the palette
definition distinguish the fixture error from a residual painted row.

Five assertion locations in three method bodies now compare complete BGRA
pixels against the independent expected background `(28, 23, 23, 255)`.
The offset control is first checked against that palette before supplying
later comparisons. No tolerance is widened, method dropped, or intermediate
ownership, State, lifecycle, or task assertion removed. Both tests requiring
the currently missing insertion animation state remain unchanged and failing
at the previous commit; this fixture repair does not address them.

The packet is `artifacts/goal-ninth-removal-background-fixture-intake-v1`,
private commit `e7146ab3d0a5e336fae5415d25e499f99794ccf1`, tree
`e713da9a6ec6175a5f070d38946dd116a5594f24`. Its 6,397-byte patch has SHA256
`8565c79be2c2a423768e4ca4c99f410823499b9dbe10f82c534f2bfcf6d035d7`.
All nine method identifiers and the other 590 test files remain unchanged.
Only this fixture and its documentation change; production code does not.
Independent source review, parent contracts, and strict formatting passed.
The revised assertions still require execution and do not count as passing
evidence yet. All original completion gates remain open.

### Ninth batch: checked identity preserves erased-key equivalence

Conditional casts in checked identity hashing/equality could unwrap
`Optional.some` and treat an erased optional framework value as its nonoptional
counterpart. Ordinary `AnyHashable` equality distinguishes those shapes, so the
checked path could disagree with the original identity equivalence relation.

Recursive checked dispatch now requires the exact erased dynamic type of a
framework Identity, Key, or Segment. Equality checks both operands before
recursing. The original declared-type discriminator, ordinary erased fallback,
numeric canonicalization, and post-callout currentness check remain. Optional
and arbitrary composite payloads are one entered erased operation; this adds
no recursive introspection or promise to interrupt application code inside it.

The independent prerequisite is private commit
`92b747e60dae901ae71b53f84efc0a6eeb3962ec`, preserved in
`artifacts/goal-ninth-core-erasure-intake-v1`. Its 17,044-byte source patch has
SHA256 `6103d2cc0f26ff6ed01773d98d5af03569d37b059c48289f57c195b6698f5f0a`.
The parent applied only the Core change and a new seven-method test file; no
existing test source or assertion changed. Tests compare ordinary equality
against checked results for erased/reboxed framework values, optional/nil
shapes, equivalence laws, equal checked hashes, typed numeric controls, and
revocation at exact framework versus opaque callback boundaries. Source review,
parent contracts, and strict formatting passed. Compilation and serial
execution remain required. The separate UIA reader/phase changes are not part
of this commit, and no accessibility or original completion gate is closed.

### Ninth batch: native source indexing during owned declaration freezing

The File Browser timeout sample led to a second independent cost in ownership
preparation. For each registered component, freezing scanned all sources and
their ancestry, then repeatedly searched growing payload/facet arrays by
identity. Common ancestors and nested owners repeated this work without
adding a new ownership check.

One freeze-local index now maps each tagged native component identity to its
original source positions. Repeated ancestry entries count a source once;
ordinary and lazy component identities stay distinct. Per-component native
identity sets replace the growing result-array searches while the retained
payload/facet arrays preserve exact first-encounter order. Duplicate payloads
can still add distinct required facets, and expired weak source nodes do not
erase their recorded metadata. Empty or entirely rejected registrations do
not build the index.

The index contains native identity keys and integer positions, not nodes,
application identities, callbacks, cached currentness, or publication permits.
It is built from the same immutable source parameter used for roster reads.
Region preparation still precedes it; registration order, rejected keys,
source-free plans, slot continuation, plan construction, and every later
ownership/publication check remain unchanged. It does not persist on the
ledger or grant permission after a callback.

Private production commit `11631790ebefe63968dc499e10f56879be4b7c35` and the
test-only count refinement `29932139a5692b76e15737f1052152fa38d0a621` have
combined tree `d92ee4c41db208e5557a87d573e574605344b36e`. Their 36,070-byte
patch has SHA256
`db2f854d7f4204d5de64bde9111c83fc7aec0011809726453836641c693095c2`.
The packet is retained in `artifacts/goal-ninth-owned-freeze-intake-v1`.
All 591 prior test files remain unchanged by this patch. Eight new methods in
`RetainedOwnedComponentFreezeTests` compare exact ordered results with the
original independent algorithm, count both old identity comparisons and new
membership attempts, cover weak expiry/nonretention, and prepare ordinary and
lazy owned declarations. Preparation fixtures do not claim actual adoption.

Index construction visits every recorded ancestry association once. Each
roster visits its matched sources and facets once, with expected native hash
membership cost. Nested ownership still has a triangular output footprint;
slot/region processing, hash implementation work, and other reconciliation
costs remain. These are structural bounds, not measured latency, memory, or
proof that the interaction timeout is resolved. Independent source review,
parent contracts, and strict formatting passed. Compilation, all eight new
methods, unchanged ownership regressions, and the original 14 interaction
methods still require execution with unchanged limits. All nine gates remain
open.

### 2026-09-01: Image, layout, removal and file-preview evidence at 04568c8

This entry records new execution evidence for source commit
`04568c87b5992c2199a35276f107289c51603529`, tree
`5657f3a29dea5c8308620abb266f7950e8dc0f11`. It adds detail to the original
acceptance criteria; all nine original completion gates remain open. The native
source-ownership index is not a demonstrated solution to the remaining file
browser interaction timeout.

Three serial, fixed-roster XCTest runs completed with 476 starts and 476
terminals: 474 passed, two failed, and none skipped. Each run's source and index
endpoints were independently compared, and each emitted the explicit Swift
Testing zero-test footer. These counts cover only the selected classes, not a
Full run or the separate timed-out interaction cohort.

| Fixed cohort | Observed result | Raw log bytes and SHA-256 |
| --- | --- | --- |
| Image/List ownership, 208 methods | 208 passed; natural exit 0; 356.171 seconds including 346.83-second build | 3,032,707; `aaf8097797347c5230296c3c48eccdeb01467505df4f5010e75fd2b8370a09b8` |
| Layout/sizing, 118 methods | 118 passed; natural exit 0; 8.047 seconds | 32,183; `dc076dcb033c7f2c10d71052d4ec2a56937cfaa71f75b32353b3a01b7bd943f0` |
| Removal/blur, 150 methods | 148 passed, two failed; natural exit 1; 70.954 seconds | 47,681; `45c1ee59a4de3a2899f6c12c661992a367a22c3764adb60eec07b4f2aa628c36` |

The 208-method run passes both previously failing image-density and
foreign-then-original standalone List cases. It includes all 23 image-scale,
ten standalone snapshot, three file-browser render, eight native ownership
freeze and seven erased-key identity cases. The freeze tests qualify their
native roster/order/lifetime assertions, not end-to-end interaction speed.

The layout cohort includes all 16 existing `WinSwiftUICompositeTests` methods.
A rejected preliminary 116-method specification had missed two existing
`nonisolated` GroupBox methods. A separately reviewed artifact-only parser
successor accepts that exact optional declaration modifier; it preserves the
same masking, structural, count and identifier-size checks, filter derivation,
timeout and process handling. No test was removed or edited to obtain 118.

The three corrected removal background comparisons now pass with exact dark
BGRA `[28, 23, 23, 255]`. The two unchanged positive assertions still fail:
`testManagedTabCrossfadeKeepsDeclaredStateAndDoesNotRestartOnRebuild` at line
172 and `testRemovalDuringInsertionUsesPresentedOpacityAndCannotCancelReinsertedRow`
at line 225 both require a non-nil `AnimationState`. These remain production
insertion-animation defects, not tolerance or fixture problems. All four
declared-owner continuation, 24 CPU material blur and 16 D3D11 material blur
cases in this cohort pass; that is not a claim of complete backend equivalence.

Reconciled receipts are retained as
`artifacts/goal-ninth-image-list208-04568c8-reconciled.json`,
`artifacts/goal-ninth-layout118-04568c8-reconciled.json`, and
`artifacts/goal-ninth-removal-blur150-04568c8-reconciled.json`. Their recorded
run directories contain the raw logs, exact roster derivations and source
snapshots. The layout and removal process censuses found no surviving original
direct child, child process or Swift test process before the next workload.

The unchanged 14-method `DemoFileBrowserInteractionTests` run again reached its
900-second limit: controller exit 124, direct PowerShell exit 1, with unchanged
source/index endpoints. The 227-byte raw log, SHA-256
`f1aab64c1cae1d1d10adb5d55cb3dffc3afc8c3a87e1b5e786618337598f2696`, records
a 0.35-second successful build but no observable XCTest start or terminal.
Buffered output does not establish which individual cases executed or passed.
One local, noninvasive, nonsuspending CDB sample completed and detached; its
incomplete unwind and candidate raw stack words do not establish a complete
active call chain. They motivate source investigation of repeated ownership
checks, not a timing qualification or permission-cache change.

After the timeout, retained handles verified every recorded process creation
identity before cleanup. Only the owned XCTest process was terminated; its
Swift/PowerShell parents consumed that exit naturally. A subsequent CIM census
found none of the seven recorded controller/process/console IDs or their
children. The exact attempt and cleanup are retained in
`artifacts/goal-ninth-file14-04568c8-timeout.json`; the original workload and
deadline were not reduced or extended.

Six retained gallery renders then completed at the same source commit using
the executable linked by the successful 208-method build. Both renderer and
resource-copy children exited naturally with code 0; source, executable,
generated accessor and the two image resources stayed unchanged. The six new
images and all three old file previews were visually inspected. All four file
rows and the appropriate selected-row background now appear in the loaded,
empty-file and invalid-UTF-8 previews; their corresponding preview bodies
remain unchanged. Differences are confined to the Files area: 12,967, 23,135
and 18,936 pixels respectively. The cap-inset, tiled and aspect-fit bitmap
controls are byte-identical to their retained comparison images.

Gallery output is retained under
`artifacts/goal-ninth-file-preview-gallery-797bda7174b54bf1a57dc07a1b3e07af/`,
with pixel/hash comparison in
`artifacts/goal-ninth-file-preview-gallery-04568c8-comparison.json`. This is six
specific retained fixtures, not the full gallery gate, a native input workflow,
macOS comparison or a baseline refresh. No reviewed baseline was changed.
ContractsOnly passed again after these runs. Full validation, the two remaining
animation repairs, the interaction timeout, hosted CI and all other original
completion requirements remain outstanding.

### 2026-09-01: Integrate the bounded native-host smoke workload

The reviewed native smoke source is now integrated as a separate capability
slice. `swift-windowsui-native-smoke` exercises an owned Win32 window through
the existing host and main-actor application path. It observes native command
delivery, real UIA publication-gate entry, task suspension/resumption, an
unforced three-second idle interval, and close/unwind/join ordering. Optional
observation records do not grant admission, reorder the ordinary mailbox, or
turn normal application execution into the smoke workload.

The fixed workload includes 64 commands and 64 probes, with the real C UIA
query at ordinal 31, two mounted task awaits, and a publication gate retained
across close. Its finite records distinguish successful natural process exit
from an intended exit/result file. Failure, timeout, and insufficient fairness
evidence cannot become a pass. The internal workload deadline is 42 seconds,
the self-watchdog is 45 seconds, and the separately reviewed root controller
uses a 55-second external retained-process bound. A watchdog does not replace
verification that the owned child actually closed.

The source packet's four private commits end at
`11956185b38492f44279ff9551f293a1b5e6727e` on its documented `cdd5fd2` foundation.
The packet was applied to root `9f689ddcf2e7b86ee2496e438d87d136008c918d` without
changing any added or removed source line: 23 paths, 19 Swift files, two C/C++
files, and two documentation files. Root integration proof is retained at
`artifacts/goal-ninth-native-smoke-root-integration-proof-v1.json`; its packet
SHA-256 is `de9b254011a7e1c0bd48dc1b27c450910cbde1cd27458170aad2ab6a1acdb57f`.
All prior test files are unchanged. The three new files contain the reviewed
45 async test methods: eight gate, 15 observation and 22 result-validation
cases. Strict formatting of all 19 Swift files and ContractsOnly passed at
root (`0f6dfd/0`). Compilation, these tests and the actual native workload
have not yet run on this integrated source.

`Package.swift` is now the reviewed 7,331-byte variant, SHA-256
`4643f0f470cb5cf373928bf91e58cd38883f1d98210503e4f03a07647be12b69`. The separately
reviewed Core320/List402 validation-controller successors bind that exact
package change while preserving their original test source and workload
checks. Later test-resource changes require separate handling; they must not
be silently accepted by these fixed controllers.

Before the native run, bind the actual same-commit build, executable, tools,
source record and required DLL identities. The source-foundation label inside
the workload is not a substitute for this release-source binding. The workload
does not use desktop captures, global input, dialogs, clipboard, network or
settings changes. It does not qualify general COM routing, Narrator, modal
interaction, multiple windows, display timing, GPU recovery, long-session
resource behavior, or clean-machine deployment. See
[NativeOwnedSmoke.md](docs/NativeOwnedSmoke.md) for the concrete workload and
remaining scope. All original goal gates remain open.

### 2026-09-01: Integrate typed keyframe timelines and managed playback

`KeyframeAnimator` no longer discards its authored tracks. The integrated
implementation builds typed linear, cubic/Hermite, spring and move timelines,
supports the documented scalar and geometry adapters, preserves declaration
order, and samples the maximum track duration. Root values need not themselves
conform to `Animatable`. Per-track velocity and truncated spring endpoints are
retained for interruption; this is a concrete local implementation, not a
claim that its numerical curves match the pinned native SwiftUI baseline.

Managed occurrences stage one synthetic state cell, commit the exact adopted
proposal, and start factories under their captured transaction and ownership
checks. Equal triggers and ordinary rebuilds do not restart a run. An
interruption begins from the current sampled value and velocity. Frame delivery
uses the existing runtime queue with its actual tick timestamp, disables an
extra implicit tween for each published value, and preserves other transaction
fields. Final retirement/close cancels before captured payloads are released;
reversible retirement does not manufacture a replacement run or new authority.

Repeating playback anchors ordinary overshoot to the previous cycle end. At
most eight factory boundaries may run in one frame before the documented
long-gap policy resets the remaining current cycle at that frame. Zero-duration
repetition cannot create an infinite loop. These policies, first-mount trigger
seeding and Reduce Motion still require native comparison. An unmanaged raw
Component only samples a beginning value; durable unmanaged/snapshot playback
remains an open requirement, not a platform exception or a completed feature.

The reviewed private source ends at
`a1a10d2911e9903d28507441aeb5b193da54a606`, tree
`4200deab95edd4ec96fbaa46a0187336ff19494e`. Its 206,411-byte patch, SHA-256
`0c31db7933d57768eb6b5efd6d5915af5098c306eda0a656fac320930bfb7986`, was applied
to root `7b3970211c8e457fe3504eae86b29751c6fcdee0` with every added/removed
packet line preserved. The 12 packet paths comprise eight production Swift
files, three new test files and one document. Root also replaced the obsolete
shim description in `CompatibilityStatus.md` and documented the supported
partial behavior in `WinSwiftUI.md`; the original goal was not revised.

All prior test files and the 7,331-byte native-smoke package variant remain
unchanged. The new source roster is 25 timeline, 15 playback and 22 mounted
tests, all async. Strict formatting of all 11 changed Swift files and
ContractsOnly passed (`ea0ece/session61637` through `e69a04/0`); the exact
packet/context preservation proof is
`artifacts/goal-ninth-keyframes-root-integration-proof-v1.json`. These 62 tests
and the newly integrated source have not yet been compiled or executed at this
point in the ledger. Generated registration, real test terminals, wider
preservation checks, rendered motion and hardware pacing still need evidence.
See [KeyframeAnimations.md](docs/KeyframeAnimations.md) for the supported API,
local policies and limits. All nine original completion gates remain open.

### 2026-09-01: Preserve standalone List navigation ownership

Standalone List navigation now distinguishes a rejected foreign runtime attempt
from its first accepted attachment. Both public List construction paths select
this mode only without a State coordinator. The owner retains a weak original
runtime and a scalar close witness; native membership/owner publication captures
the actual attachment once. Getters cannot arm or refresh it. A failed foreign
attempt may cancel a prepared construction action but cannot consume the
never-accepted owner's future original attachment, and foreign close cannot
revoke another origin.

Explicit close, real departure, owner/adapter/lease replacement and identity ABA
remain terminal. Ordinary weak runtime expiry preserves existing returned-tree
navigation without retaining the outer logical-host lifetime or granting new
row construction. The additional physical-proof predicate is navigation-only;
ordinary attachment/build/descriptor authority is unchanged. Compatible
same-node declaration transport can retain an already valid original physical
attachment but cannot revive an old proof after identity or ownership changes.

Raw owner/adapter replacement captures the affected original runtimes before
revocation, defers navigation cancellation until the property is published,
and then drains it. A cancellation callback may install a newer declaration
without the older setter subsequently overwriting it. This follows the original
runtime even when checked retirement has already cleared the node's runtime;
that fallback is source-reviewed but has no direct new executable oracle yet.

The exact source delta from private `4003bf99` to
`b782b3a1afc66b449f058126efca8a94fbd6bf81`, tree
`61daf1549624351f90ff6f7c80b6505278fa468c`, was applied to root
`90eea0e6f7304f7dfda1adc03c65d81cc40454a2`. The 53,487-byte patch has SHA-256
`a23e701659edbf665823f0810578e0850dc1c893f2f8640f57a616574b466107`. All
added/removed packet lines and all pre-existing test files remain unchanged;
the separate cached-layout prerequisite was not reapplied. Root integration
proof is `artifacts/goal-ninth-standalone-navigation-root-integration-proof-v1.json`.

Fourteen new async tests cover foreign attempts and close, prepared actions,
actual attachment revocation before first observation, cancellation publication,
same-node transport, weak expiry and native identity/adapter/lease ABA. Strict
formatting of eight Swift files and ContractsOnly passed at root
(`06bd61/session77370` through `012454/0`). The new tests have not yet been
compiled or run. This slice does not fix or qualify the separately identified
deferred keyboard controller retaining a discarded construction container after
GeometryReader adoption; that requires its own repair and fresh-action tests.
No original completion criterion or gate changed.

### Direct native adoption predicates integrated; FileBrowser timeout remains open (2026-09-01)

The source candidate from private commit
`12cb845c518345bf070d5c6bfad08691673b875a` is now integrated on root parent
`3b202273d63e206cf06c23e398670066e3488338`. Ten native `allSatisfy` key-path
predicates in ComponentHost now use direct typed closures. Arrays, guard order,
fresh witness reads, scope and journal checks, payload lifetime pins, and
postchecks are preserved. No permission is memoized or deduplicated, and no
witness is recaptured to revive an old operation. General Boolean caching was
rejected because weak-owner promotion and release can reach authored cleanup.
The syntax change alone does not establish compiled ARC timing equivalence or
a measured performance improvement.

Six new async `RetainedAdoptionProofPredicateTests` cases cover actual attachment
and identity ABA, completion snapshots and short-circuit ordering, authored hash
reentry, outgoing payload cleanup, and prepared insertion invalidation by a
later sibling callback. Root audit
`artifacts/goal-ninth-adoption-predicate-root-integration-proof-v1.json` confirms
that every added and removed source line matches the sealed packet, all existing
test files are unchanged, and the 7,331-byte Package.swift is unchanged. Root
strict formatting and ContractsOnly both passed (`93abc3`, exit 0). Compilation
and execution of the six tests remain pending.

The separate source cost model still gives two admission visits for a checked
node and its journal, three top-scope visits in the nested publication prefix,
and `(h + 1) * (h + 2) / 2` staging visits for a fully declared chain with `h`
parent rows. These counts are not reduced by this change. The actual depth,
compiled cost, and active case of the buffered File14 workload remain unknown.
Its previous 900.016-second timeout and unknown individual outcomes remain
failures to obtain evidence; neither the timeout nor workload has been relaxed.
All nine original completion gates remain open.

### Fresh deferred List keyboard controllers use the accepted retained container (2026-09-01)

The separately documented deferred-controller transport defect is now repaired
in root source. GeometryReader or component adoption could move the incoming
adapter and row declarations onto a retained List while the new keyboard
controller still held its discarded construction node weakly. Finishing an old
prepared selection action did not demonstrate that the next action could work.

Each fresh adapter now installs a native navigation container binding. It
captures only its first actual attachment to the original runtime at accepted
claim publication; a provisional claim can finish that first capture once
membership exists. An accepted release is terminal. Getters never capture,
retarget, search for another owner, or invoke a provider. Existing declaration,
selection, focus, identity, lease, and close checks still apply. Already realized
direct-data rows keep their navigation path after ordinary weak runtime expiry;
explicit close, foreign attachment, departure, identity ABA, and adapter or
lease replacement still reject the old controller. No factory pass was added.

Root parent `4883b8f6471a292ca248f3ceb9cd1b7089ecc5ac` integrates the reviewed
private `b1d661c10b2ae0e990f592a6049c550db9e13608` packet. The source audit in
`artifacts/goal-ninth-deferred-navigation-transport-root-integration-proof-v1.json`
confirms exact added and removed packet content across five production files,
two new test files, and two documentation files. Existing tests and Package.swift
are unchanged. Strict formatting for seven Swift files and ContractsOnly passed
at root (`1eb864`, exit 0).

The seventeen new async tests include the actual padded GeometryReader rebuild
with both held and released construction candidates, a fresh runtime keyboard
event after adoption, a managed prepared action followed by a separate new
action, original claim publication, release, and lifetime refusal cases. They
have not yet compiled or executed on root. No new keyboard, UIA, visual, or
release qualification is claimed. All nine original completion gates remain open.

### Managed List insertion events and deferred transaction delivery integrated (2026-09-01)

Root source now includes the reviewed insertion repair from private commit
`8aeb2e8e77338456797be2c7d61a37006a8681c2`. This addresses the mechanism behind
the two remaining missing-animation failures recorded at `04568c8`; those
failures are not considered resolved until their unchanged tests pass again.

Provider continuations distinguish newly introduced logical row tokens from
initial, cold, and remounted viewport rows. A pending introduction survives an
accepted descriptor continuation without carrying an obsolete transaction.
Insertion uses the latest accepted declaration's effective transaction, captured
inside its existing modifier scope and bound to its actual accepted attachment.
An absent transaction preserves the existing 0.35-second default; explicit nil
animation or disabled animations suppress it. Logical reinsertion may reuse a
physical node while taking its new State identity and authored destination pose.
It does not reset physical appearance or replay an already accepted arrival.

The first actual accepted native property, attachment, structural declaration,
inserted-node, or empty-row-table publication claims the event. A later failure
does not return that claim for replay. Generic insertion is consumed before
attachment controllers can call out. Only a completed original candidate may
deliver the prepared animation; the injected clock and its captured payloads
unwind before original attachment, configuration, completion, and presentation
checks admit scalar writes. One finite clock sample covers the accepted forest,
and unrelated animation channels are preserved.

Integration on root parent `9224738abd82afc20973e46dcfccce1e464b09ac` required two
explicit hunk joins. Successful List claims activate the insertion context while
the earlier cached-layout fix still marks layout dirty only for a newly owned
attachment. Release preserves navigation revocation, then expires insertion
context before the unchanged standalone lease and candidate teardown. The
derivation in `artifacts/goal-ninth-managed-insertion-root922-merge-derivation.json`
proves that inverting these two adaptations restores the original normalized
packet. Independent join review found no blocker (`a8e7c2`, exit 0).

Root audit `artifacts/goal-ninth-managed-insertion-root-integration-proof-v1.json`
records exact applied adapted content, all other packet file edits unchanged,
and preservation of existing tests and Package.swift. Strict formatting of nine
Swift files and ContractsOnly passed (`9b18ed`, session 8879, terminal `e95c55`,
exit 0). Twenty-one new async tests cover event semantics and callback boundaries.
They and the unchanged removal tests still require compilation and execution on
the combined root source. No factory budget, cleanup obligation, timeout,
workload, or original completion criterion was reduced; all nine gates remain open.

### First combined compile found insertion recipe actor isolation (2026-09-01)

The first fresh 165-method cohort on root `7f178d81a34cd058d4c2847da78b8ee1a3121778`
stopped during compilation. It exited naturally with child/controller codes 1/1
after 40.25 seconds (`deec2a`, session 29124, terminal `3f9fd8`); it did not time
out. Four distinct diagnostics, repeated during module emission and compilation,
identified the private nested insertion Recipe initializer reading main-actor
ViewNode transition, opacity, transform, and implicit animation from a
nonisolated context. No XCTest start was observed, so none of the 165 intended
test outcomes is qualified by this run.

The original 15,696-byte log is preserved under
`artifacts/goal-ninth-new165-7f178d8-3bab96a6bb8745ad8ec995c0da1bfe7c/` with SHA256
`1fc732ce28e74c7136d064115137eb7015fc659aeba845e146c2dcda2af3f3b0`.
Tracked source and index endpoint checks passed. A separate process observation
confirmed that direct child 16124, its remaining children, and Swift processes
were absent (`534c31`, exit 0). The compile-failure receipt is
`artifacts/goal-ninth-new165-7f178d8-compile-failure.json`.

The repair adds only `@MainActor` to the private Recipe structure. Its callers
already execute on the main actor; no dispatch, weakened isolation, transaction
recapture, test change, or extra runtime work was introduced. Strict formatting
and ContractsOnly passed (`8ea9ac`, exit 0). A fresh compile and the same 165
methods remain required. The separate unchanged 150-method removal/blur cohort
also remains pending at this source. These two serial cohorts retain all 315
planned methods while each stays below the fixed Windows command-length bound;
their 900-second per-run limits are unchanged. All nine original gates remain open.

### Keyframe factory generic inference corrected after fresh compilation (2026-09-01)

The unchanged 165-method cohort on `27f43662a49fcf384e40073c0556f12fb0c294de`
compiled past the insertion recipe but stopped in WinSwiftUI: the keyframe
configuration factory's multi-statement closure did not infer its `Value`
parameter. Child/controller exit codes were naturally 1/1 after 56.813 seconds
(`e79712`, session 57318, terminal `00982e`), without timeout or observed XCTest
starts. No method in that cohort is qualified by this attempt.

The 9,752-byte raw log, source/index preservation, two distinct diagnostics, and
process closure are retained in
`artifacts/goal-ninth-new165-27f4366-compile-failure.json` and its referenced run
directory. The raw log SHA256 is
`75822bc88d553b7ad928ef228a17343ef6f4d3c0a76571bdc246282f03850744`.
Direct child 31936, its remaining children, and Swift processes were observed
absent (`5b4b60`, exit 0).

The only production change explicitly constructs `KeyframeConfiguration<Value>`
using the animator's existing generic parameter. No behavior, callback, test, or
acceptance condition changed. Strict formatting and ContractsOnly passed
(`159c38`, exit 0); recompilation and both planned focused cohorts remain pending.
All nine original completion gates remain open.

### Keyframe test fixture compilation repair after the third integrated 165-method attempt (2026-09-01)

The unchanged 165-method roster was attempted at `62a76fa72941d09143f9d99bde35d1519ecf9afc`.
The retained controller and its direct PowerShell child both returned 1 naturally after
124.797 seconds; there was no timeout. Compilation reached the new test sources,
then reported two distinct diagnostics: the unmanaged keyframe fixture omitted
`ViewBuildContext`'s required canvas and invalidation closures, and the independent
spring terminal oracle left `exp(-1)` ambiguous between numeric overloads.
The 3,242,701-byte combined log has SHA-256
`d8bc741bd76f41e1ac0efffdb519419e5ac9acdd1d92c62425e2e1444a7a39a7`.
No XCTest method start was observed, so this attempt qualifies none of the 165
methods. Tracked source and index endpoint observations were unchanged; a fresh
post-exit process census found the direct child, its still-parented descendants,
and Swift build/test processes absent.

The repair changes only these two new test fixtures: it supplies a 100 by 100
canvas and an empty invalidation closure without adding a managed state owner,
and explicitly declares the existing terminal expression as `Double`. The
closed-form expression, every assertion, and every test identifier are unchanged.
An exact inverse replacement check accounts for both complete source deltas.
The detailed receipt is `artifacts/goal-ninth-new165-62a76fa-compile-failure.json`;
`artifacts/goal-ninth-new165-62a76fa-post-closure.json` records the process census.
A fresh compile and the same 165-method roster are still required, followed by
the unchanged 150-method removal/effect roster. This is compilation repair, not
functional, native-host, visual, performance, or macOS qualification. All nine
original completion gates remain open and unchanged.

### First functional execution of the combined List, insertion, and keyframe work (2026-09-01)

The compile repairs allowed the complete new 165-method roster to execute on
`26390ef2f30b4aeb8cf022ab998eb5a14e7fbfd7`, tree
`4c1be84b7278f28c1d140a1d0bff1367586a58fa`. The direct child and controller both
returned 1 naturally after 309.235 seconds, without timeout: 156 methods passed,
nine failed, and none skipped. The 2,170,085-byte raw log has SHA-256
`9b1e33ece8c44d706ea4db3244849fb731e5b80c03024100debf2abf864792ce`.
The independent case-ID, terminal-result, source/index endpoint, and process
closure records are `artifacts/goal-ninth-new165-26390ef-reconciled.json` and
`artifacts/goal-ninth-new165-26390ef-post-closure.json`. These results replace the
earlier compile-only unknown outcomes for this roster at this source, not for
subsequent changes or the entire package.

The timeline's 25 methods, playback's 15 methods, all 45 native-smoke validation
methods, six adoption-predicate methods, eight navigation-container methods, and
14 standalone navigation-lifetime methods passed. The nine failed methods are
now specific remaining work:

- Deferred navigation: the managed prepared continuation did not allow the
  separate next keyboard action after rebuild; eight other transport methods
  passed.
- Insertion boundaries: the two callback-count fixtures observed four fresh
  attempts under the existing default four-round budget, not the single attempt
  assumed by those fixtures. Any fixture correction must explicitly select the
  existing one-round policy and preserve the assertions; a separate default-budget
  regression must retain and distinguish the four original attempts.
- Insertion events: an accepted initially empty row did not retain the physical
  cohort needed for its first later child, and a nested initial List could not
  attach its expected row. The nine other event methods passed.
- Mounted keyframes: keyed reordering lost the surviving run's physical sample;
  explicit-identity replacement, factory-capture cleanup, and a factory closing
  its host did not reach their expected original factory or cleanup behavior.
  Eighteen other mounted methods passed. Passing timeline and playback tests
  therefore does not establish mounted keyframe correctness.

The unchanged 150-method removal/effect roster then executed on the same source.
It returned 1 naturally after 77.843 seconds: 149 passed, one failed, none skipped.
Its 48,181-byte log has SHA-256
`67c2987fa0dc43133a2c5c4a32953c24f4f136888cda1197dd56ee87e76980d4`.
The two earlier missing-insertion-animation observations no longer occur in
their unchanged tests. In particular, removal during insertion now observes its
presented opacity and retained reinsertion behavior. However,
`testManagedTabCrossfadeKeepsDeclaredStateAndDoesNotRestartOnRebuild` fails later,
when returning to the original page: the owner and model identities change,
the owner generation is 38 instead of 10, and state is 100 instead of 41. The
incoming page and unchanged midpoint rebuild assertions pass. This is not a
pass for Tab state preservation. The owner generation is not a factory count.
Receipts are `artifacts/goal-ninth-removal150-26390ef-reconciled.json` and
`artifacts/goal-ninth-removal150-26390ef-post-closure.json`.

### Fixed Core and List regression runs stopped at their first failing classes (2026-09-01)

The reviewed Core320 and List402 controllers retained their original selections,
180-second class limits, 1,800-second total limits, and stop-on-first-failing-class
policy. Neither was a complete suite pass. Both ran serially on the same
unchanged `26390ef2` source and index after the functional runs above.

Core320 completed eight classes and 146 methods in 77.547 seconds: 145 passed,
one failed, none skipped, and 174 methods in 14 classes were not run. The
remaining failure is the unchanged
`UIANativeItemContainerIntegrationTests.testNativeRuntimeIDAndRealizeRespectPendingAcceptedReplacement`:
the requested row 300 remains a placeholder with an unavailable result. The
earlier runtime-geometry and deleted-token cases now pass, but the deferred UIA
realization repair and the four separate shared-budget tests still require
execution. Those four tests are outside the fixed Core/List selections.

List402 completed nine classes and 107 methods in 114.485 seconds: 105 passed,
two failed, none skipped, and 295 methods in 20 classes were not run. Both
failures are in the unchanged `MountedLazyListStateTests`. Cold deletion and
reinsertion cannot recover the expected collection binding. Keyed reordering
and insertion lose the physical row for key 1 and the installed owner for key
99. The later public navigation classes were never entered, so this run gives
no new result for their opaque-builder navigation cases.

`artifacts/goal-ninth-core320-26390ef-partial-reconciled.json` and
`artifacts/goal-ninth-list402-26390ef-partial-reconciled.json` independently
reconcile the exact ordered executed prefixes, every observed start and terminal
case ID, per-class raw hashes, and source/index endpoints against the original
fixed selections. Their corresponding `post-closure.json` receipts found all
retained controller/direct-child PIDs, still-parented children, and observed
Swift processes absent after natural controller exit 1. No process was killed.
These are endpoint process observations, not continuous descendant attestation.
Unrun methods are not skips or successes. Package.swift and the original test
workloads remain unchanged; the localization resource change is still deferred.

### First owned native-window smoke failed during UIA shutdown (2026-09-01)

A separate fixed three-class, 45-method smoke-validation run passed all methods
on `26390ef2`, with child/controller exit 0/0 and no timeout or skip. Its original
start and exit records, not a rewritten Core per-class record or a failed compile,
bound the subsequent native execution. The only runner changes were the two
class-filter literals; the 900-second limit and all source/process guards were
preserved. `artifacts/goal-ninth-native45-26390ef-reconciled.json` records the
13,576-byte raw log, SHA-256
`6ac8d206990abfc4c80781a4c0520ddd14dcd7d431a96af46475d664b2217db6`.
These 45 methods overlap the new 165-method roster; they are not 45 additional
distinct tests of the product.

The actual native fixture then used binding
`artifacts/goal-ninth-native-smoke-26390ef-binding-v1.json`, SHA-256
`7bed7ffa1a1f779ea0d6f7c206c501735d055817783e1836b04f3c777ef40c33`.
It pins the 93,270,528-byte executable, SHA-256
`f74f6681ec5adb818c7037ed6fb75d58b4a216983be93dfa325fec4a940f4a79`,
the reviewed controller and output schema, the actual successful compilation
records, Python/Git, and 135 immediate DLL inputs from the two fixed Swift 6.3
directories. The source and index were not changed between compilation and
native execution. The preserved SwiftPM build graph includes the native-smoke
product in its test target. This is incremental build validation: the native
product was linked during the earlier `62a76fa` attempt, and only the two test
compile fixes and this goal's earlier ledger changed before the successful
`26390ef2` build. A fresh link at `26390ef2` and actual loaded-DLL selection are
not claimed. The build association is retained separately under
`artifacts/goal-ninth-native-smoke-26390ef-build-association-v1/`.

The native child, PID 64832, returned 1 naturally; its retained wait and cleanup
interval was 11.063 seconds, and the controller also returned 1. Neither timed
out or required termination. It created one owned window,
delivered the 64 queued probe/command replies, recorded the three retained update
phases and two mounted task awaits, and reached the three-second unforced idle
observation. Shutdown then reported `UiaDisconnectProvider` failure with native
code -2147220991. The fixture records two failure notifications for that native
error, no nonclient window destruction, and no actual native-thread join.
Its unfinished native operation remains explicitly unknown. The fixed validator
reports 16 true and 11 false predicates out of 27; the result is failed, not a
partial native qualification or a fairness pass.

The 2,717-record trace is 633,329 bytes, SHA-256
`9c20fbf629cd719b364e48c274ad2f64514423fbc2b2111951d77c4f20a31705`.
`artifacts/goal-ninth-native-smoke-26390ef-failed-reconciled.json` independently
checks the actual exit, hashes, contiguous trace identities, event counts, and
source/index/input preservation; it does not reimplement the native semantic
validator. The post-exit census found the child, still-parented children, and
observed Swift/native-smoke processes absent. The original controller's
conservative cleanup-required flag remains unchanged in its sealed record;
the later census is separate evidence, not a replacement receipt. No automatic
retry occurred. The shutdown failure and independent fairness/thread-observation
failures require diagnosis and a fresh bounded native run after repair.

These focused results and failed native execution do not qualify Narrator or
COM routing, visual parity, full-suite validation, frame pacing, resource bounds,
macOS, hosted CI, deployment, or any release gate. No original workload, timeout,
cleanup obligation, or completion criterion was reduced. All nine original
completion gates remain open and unchanged.

### Ordinary reconciliation keeps original source completion through reordering (2026-09-01)

Root source now contains the narrow repair from private commit
`abfa80ff68a33528ecc32541210f4e98eb925d81`. A retained target had already completed
against its fresh candidate, but a later changed-child-list walk completed that
same target against itself. The target did not carry the candidate's source
stamps, so that second completion could revoke the newly accepted descriptor
and stop a surviving keyframe run. This mechanism differs from the remaining
old-footprint/new-footprint retirement gap during physical root replacement.

ComponentHost now captures the original prepared source forest once at the
outer adoption or reconciliation boundary, before authored matching and property
callbacks. Descendants share that immutable weak membership record. The ordinary
setter uses it only to filter its later self-completion replay; candidate-to-target
completion and the entire accepted insertion/arrival walk stay in their original
positions. Direct/raw setters retain their existing default behavior, including
explicit same-object sources. Checked List adoption is unchanged.

Membership holds native object identifiers and weak original nodes, and requires
the surviving original referent to match. It grants no attachment or publication
permission and cannot retarget after callbacks or address reuse. The existing
bounded traversal rejects malformed source forests before mutation. This adds
one O(N) native traversal and weak dictionary per outer operation; those costs,
physical storage, and end-to-end performance remain unmeasured. The historical
File14 timeout is not considered resolved.

The exact three-file postimages were checked against the sealed packet on parent
`6063d2dbfa8dd66709ae76a9fa21bbc808af13f5`; all 605 preexisting test files are
unchanged. Nine separate tests cover real-journal reorder and mixed insertion,
direct and reconciled same-object sources, direct adoption, callback replacement,
weak payload release, stale attachment separation, and malformed forests.
The root proof is
`artifacts/goal-ninth-ordinary-source-completion-root-proof-v1.json`.
Strict formatting for three Swift files and ContractsOnly passed (`5a20a1`,
session 56581, terminal `b885f7`, exit 0). Compilation and the unchanged 62
keyframe tests plus these nine new tests still remain required. No other mounted
keyframe failure, native failure, or original completion gate is marked resolved.

### Managed deferred-navigation failure now has an unchanged-budget trajectory test (2026-09-01)

The separately committed diagnostic from private `f2a310a4093fbdc28c8a3e5f2d754d6fe0f48965`
adds one new `ManagedDeferredNavigationTrajectoryTests` method. It repeats the
existing managed keyboard-continuation oracle with the same eight-element,
eight-round, and 24-pass limits, and records native settlement, mounted ordinals,
focus, ownership identities, and the test probe's existing counters at the
original action/render boundaries. It does not add layout, realization, binding
reads, action preparation, or production instrumentation.

The original transport test and all its assertions remain unchanged. The new
diagnostic also retains the original behavior assertions; it is not a reduced
workload or a replacement test. Its exact staged patch matches the sealed
`artifacts/goal-ninth-managed-navigation-7ca0e67-intake-v1/diagnostic.patch`.
Strict formatting and ContractsOnly passed (`16caf1`, exit 0). This commit changes
no production behavior; compilation and execution remain pending. The separate
managed attachment-publication repair follows as its own source change. All
nine original completion gates remain open.

### Checked cold attachment publishes managed navigation ownership (2026-09-01)

The checked attachment path assigns the accepted node's runtime directly instead
of going through the ordinary runtime setter. It previously notified only
standalone navigation owners. A managed scope created while its node had no
runtime could therefore be physically attached yet still lack its original
navigation runtime, causing its first prepared action to be refused.

The repair from private `7ca0e67e6defdbacdf6617a25b40e01dc5849da5` changes that
one accepted-publication notification to the existing `didAttach` method for
each navigation owner. The original declaration/revocation guards still decide
whether an owner may record its first actual attachment; getters do not capture
or refresh authority. The call stays after successful native attachment
publication and before controller callbacks. Standalone behavior is equivalent
to the previous delegating call.

Root proof `artifacts/goal-ninth-managed-navigation-publication-root-proof-v1.json`
verifies the exact one-call substitution, the unchanged ordinary completion
repair, and the new one-method fixture's exact postimage. Existing tests are
unchanged. The fixture checks the actual managed adapter claim, attached scope
and row, and preparation of the original action without a selection-binding
read or write. Strict formatting and ContractsOnly passed (`f619bb`, exit 0).
The original managed navigation regression, separate bounded trajectory
diagnostic, and new fixture still require root compilation and execution.
This source repair does not resolve the separately diagnosed zero-offset anchor
policy or qualify any original completion gate.

### Insertion boundary fixtures distinguish one attempt from the default four rounds (2026-09-01)

The two insertion boundary failures at `26390ef2` came from fixtures whose
attachment callback invalidates every fresh candidate while their callback-count
oracle describes one attempt. Both now explicitly select the existing
128-element, one-round policy before starting that operation. All their original
assertions remain unchanged; production behavior and the default four-round
policy are unchanged.

A separate new test retains the default policy and requires four distinct native
journal and descriptor-attempt identities, four consumed elements, and only the
first controller of each rejected attempt. It then checks a separately requested
fifth attempt, shared by both completed controllers, while the original physical
first node and consumed insertion event remain unchanged. No clock or insertion
animation may replay. Diagnostic controller storage holds only the native attempt
IDs and its existing weak test probe, not an owner, epoch, lease, or authored
payload that could change retirement timing.

The root patch matches private `1010f70187621fae491926d60bb6bb953a331ec1`, apart
from Git's index-hash display width; the ten existing method identities remain
and the class now has eleven methods. The proof is
`artifacts/goal-ninth-insertion-fixture-root-proof-v1.json`. Strict formatting and
ContractsOnly passed (`352053`, exit 0). The corrected fixtures and new default
policy regression still require execution; the earlier failures remain recorded.
No original goal criterion was changed or marked complete.


### 2026-09-01: preserve accepted empty rows and distinguish List lease provenance

The original goal and all nine original unchecked gates remain unchanged. This
entry records two narrow source repairs for the failed insertion-event methods
at `26390ef`; no compiler, XCTest, rendering, or performance pass is claimed.

The reviewed `f863275e4ac1d35fbaf4f406153cc57a9a25d17c` packet is now applied
as eight Swift files: five production files and three new test files containing
eleven methods. The root packet is
`artifacts/goal-ninth-empty-nested-f863275-intake-v1/payload/SOURCE.patch`
(28,381 bytes; SHA256
`7da157bfaa6807d4328555540acc2c021665551bd044c263234fed2d734b4597`).
Its original nonstandard manifest was retained unchanged in a separate passive
wrapper; the fixed intake helper and its validation rules were not weakened.

An already accepted managed row with zero physical descendants now remains
eligible in the bounded mounted window when its original carried-record proof,
identity, source configuration, generation, position, and zero prefix extent
still match the viewport. Selection considers only the existing mounted table,
after positive/protected rows and before optional prefetch. It does not scan
zero-height indices, invoke a provider, reconstruct a cold row, enlarge the
window, or change the default four-round budget. The extra native sorting work
is bounded by mounted capacity; its actual time and allocation cost is unmeasured.
This permits a later accepted update to insert the first descendant of that
same still-mounted empty row.

List subtree leases now declare the native `.lazyList` contribution purpose.
Both managed and deferred List constructors use it; the attributed lease API
continues to default to GeometryReader for existing callers. A List therefore
no longer falsely declares a deferred reader region with no reader source.
Actual GeometryReader missing/duplicate-source rejection, reader anchors,
owned registration, group cleanup, and checked publication remain unchanged.
No Runtime.swift or ComponentHost.swift changes are part of this packet.

New source regressions comprise five `ManagedLazyListEmptyRowWindowTests`,
two `NestedLazyListLeaseProvenanceTests`, and four
`RetainedDeferredLeaseSourceTests`. They cover half-open viewport boundaries,
positive-row capacity and prefetch priority, cold/deleted empty records, public
nested List state, a real nested reader, and missing/duplicate/single-reader
admission with zero owned slots. Every pre-existing test file is unchanged.
The original two failed `ManagedLazyListInsertionEventTests` remain in the
required execution cohort; these eleven tests do not replace them.

Pre-edit architecture contracts passed (`e12336/0`). Root strict formatting on
all eight changed Swift files and post-edit contracts passed (`c5621b/0`).
`artifacts/goal-ninth-empty-nested-f863275-root-proof-v1.json` verifies the
reviewed patch body/hunks, all original test blobs, and the eleven-method roster.
Compilation, the original failing tests, the combined focused cohorts, broader
List validation, and release-quality visual checks are still pending.


### 2026-09-01: keep the absolute leading edge fixed during keyed List updates

All nine original completion gates remain open. This is a source repair for
the two `MountedLazyListStateTests` failures in the partial 26390ef List run,
not a claim that those tests or the full 402-method cohort now pass.

The reviewed `0ecccf420c8b4cb80b0718dfbd86afef3df9ae40` packet adds one
native policy condition and two explanatory comments in Runtime.swift,
four new `LazyListLeadingEdgeAnchorTests`, and ten documentation lines in
`docs/DeferredListConstruction.md`. Root intake is
`artifacts/goal-ninth-leading-edge-0ecccf4-intake-v1/source.patch`
(23,246 bytes; SHA256
`acd0156979fedb210a2bf409ac9adb0b55d65db4d9538aac3744162c505786be`).

Automatic keyed preservation now requires a positive enclosing scroll offset.
At absolute zero, accepted metadata reordering or prefix insertion keeps the
leading edge at zero instead of shifting the future mounted window to follow
the formerly first key. This also covers an explicit return to zero before
successor metadata preparation. The shared guard applies to future-window
selection, correction application, and pending normalization. A List below a
header at local offset zero still preserves its key when the enclosing scroll
offset is positive. Every prior reveal, motion, indicator, authored-anchor,
epoch, and equal-value authored-intent guard remains unchanged. There is no
new build pass, provider call, authority, owner policy, or round-budget change.

The new tests mirror every existing cold-binding and keyed-owner assertion,
with the same layout and reload counts, and add cached geometry checks. Two
controls retain positive-offset keyed preservation and local-zero preservation
below a positive header. The original eight MountedLazyListStateTests and all
other prior test files are unchanged. Required execution also includes the
existing runtime anchor, terminal-checkpoint, public accessibility, and
programmatic-scroll controls listed in the packet's execution roster. The
historical File14 timeout remains unresolved and is not covered by this fix.

Root strict formatting on both changed Swift files and architecture contracts
passed (`c49f9c/0`). The root proof
`artifacts/goal-ninth-leading-edge-0ecccf4-root-proof-v1.json` checks the
reviewed patch with only index hashes and hunk start offsets adjusted, and
verifies that removing exactly the three added Runtime lines restores its
entire preceding source. Compilation and runtime validation remain pending.


### 2026-09-01: preserve the original Tab owner across dormant-marker removal

All nine original goal gates remain open. The reviewed Tab handoff source is
integrated without changing the old transition test, identity matching,
State registry, provider, animation, or default resolution-budget policy.
The 26390ef removal result remains 149 passing methods and one failing method
until fresh execution establishes otherwise.

The accepted return build already named the original inactive page owner,
but publishing its replacement children declaration removed the last dormant
marker before its normal physical source could attach. Immediate native
retirement then invalidated that original plan. The failed return assertions
reported a different owner, generation 38 instead of 10, a different model,
and value 100 instead of 41; 38 was an owner generation, not a factory count.

The source now admits a retirement ticket only at the original accepted
marker-removal operation for an exact old native permission or presence with
no remaining attached footprint. It must be named by an already frozen,
selected, registered normal plan with a nonempty original source roster,
valid native lifetime, and no revoked slots. Omitted slots and rejected,
unselected, declaration-only, empty, or later unrelated sources cannot
manufacture a handoff. The ticket immediately suspends old writes through
the existing mechanism and never grants write permission.

Only a matching original accepted normal publication can consume that ticket:
its exact plan and source payload must match, its native structural member
must actually be stored, and its current actual attachment, target, storage,
and attachment identity must still agree. Neither a prepared source nor an
arbitrary later facet is sufficient. Spent entries remain recorded until
finish so callback-produced work cannot rearm the old member's ticket.
Direct revocation and retirement of omitted slots remain immediate.

Seal and abandonment drain original pending physical departures first,
then unresolved declared-marker tickets. Retirement consumes a ticket before
checking its old native member and releases only its own write suspension.
This ordering is preserved for the separate ordinary-physical handoff repair;
no physical-map-clear continuation or legacy root-guard exception is added.

The exact `d64eead6144017c780655156c5c465ea79b4819b` source delta is
`artifacts/goal-ninth-tab-handoff-d64eead-intake-v1/payload/SOURCE.patch`
(42,895 bytes; SHA256
`ad13c5dd5ea3d7f4420625f6e20da06f72a01a8c7257ed59ac5ba40d54158cdf`).
It adds 170 Activity lines and two separate test files: eleven
`RetainedDeclaredMarkerHandoffTests` and three `ManagedTabDeclaredHandoffTests`.
The native controls cover same-attachment and inserted acceptance, original
source/attempt isolation, spent tickets, immediate omission, zero slots,
invalidated preflights, revocation, and terminal cleanup. The mounted controls
cover two return cycles with the same owner/model/value, an actual build-time
binding write and invalidation, and closing before the second controller.
Every prior test file is unchanged. Ticket scanning, temporary metadata,
and native facet checks have not been benchmarked.

Root strict formatting on all three changed Swift files and architecture
contracts passed (`262cba/0`). The root proof
`artifacts/goal-ninth-tab-handoff-d64eead-root-proof-v1.json` verifies the
byte-identical patch, fourteen new methods, unchanged prior tests, and cleanup
order. Compilation, execution of the original failing Tab regression and new
controls, the full removal cohort, and broader release checks remain pending.


### 2026-09-01: retain the failed compilation evidence and correct one new fixture

All nine original completion gates remain open. The first combined-source
execution attempt at `9bd22bddf7e874afcf788706a6b15d0413e4451c` selected the
original 165 methods plus the new default-budget insertion-boundary method.
It did not reach XCTest: compilation failed on two inaccessible `fileprivate`
revision reads in the new ManagedLazyListEmptyRowWindowTests fixture. The
prepared separate 122-method repair/anchor batch was not launched because
it would have encountered the same compilation failure.

The original failed run remains
`artifacts/goal-ninth-new166-9bd22bd-844de6606e38455a8a3d879b2e45d2a5`.
Its retained child PID was 41476, launch `dd8c61/session86819`, final closure
`64e5c6/1`, with natural child/runner exit 1/1 after 119.281 seconds. There
was no timeout or process termination. Raw output is 3,356,763 bytes, SHA256
`e4546f0ec345a1c6722845598fd220f617ac1b132bf9f14e3e0d960a32451d6a`.
The independent reconciliation (`b01b3b/0`) verifies identical source/index
endpoints, exactly those two unique compiler errors, and zero started XCTest
cases. The subsequent census (`68ee5f/0`) found the retained PID, its listed
children, and Swift test/build processes absent. That is not a continuous
proof of every descendant's lifetime. No selected test is relabeled a pass
or assertion failure; all 166 were not run because compilation failed.

The reviewed corrective packet `29389ee4419f5fb209952f3fdc17ce4930f1f4da`
changes only that new fixture. It declares the already-existing zero content
and environment revision tags and uses the existing package setter, whose
equality guard returns before invalidation, allocation, or pending-candidate
revocation. The original first layout still precedes this setup. The same
zero tags now form the six cached viewport queries, avoiding inaccessible
storage reads without broadening production access or changing cache matching.
The complete current source writer census contains only the default-zero
storage and its existing source-copy setter. This fixture performs no revision
update, so the added setter is a no-op rather than a settling pass.

The original five methods, 52 assertion lines, six manual viewport queries,
and four first-method layouts remain unchanged. The other four method bodies
are byte-identical. The root proof
`artifacts/goal-ninth-empty-window-29389ee-root-proof-v1.json` verifies that
removing the four setup lines and restoring the two argument expressions
recreates the entire preceding test source. The exact source patch is
`artifacts/goal-ninth-empty-window-29389ee-intake-v1/SOURCE.patch`
(1,814 bytes; SHA256
`423ef0d837b381943f7b8fb8e2ca92777b961dc41885ca545bab4a1a802fbb48`).
Root strict formatting and contracts passed (`eac543/0`). Fresh compilation
and both serial execution batches are still required.

A separate proposed ordinary ownership handoff remains unintegrated: source
review identified that delayed old cleanup can remove a later accepted
publication of the same permission/component at the same native facet. The
counterexample is currently established at the native API level, not as an
executed public callback reproduction. Its original sealed source packet is
retained; a corrective successor and additional regressions are being reviewed.
This does not excuse the remaining keyframe failures or close a goal gate.


### 2026-09-01: fresh List, navigation, ownership, and keyframe regression results

All nine original completion gates remain open. Two serial fixed selections
ran on `10188a1dd1142482a70fd3f35b46726dc82dd353`, tree
`901ad2ae13c1cc68fd69a755bc964ebd8efe9f6d`, without source or index changes
between them. Compilation succeeded. Together they started 288 distinct
XCTest methods: 275 passed, 13 failed, and none were skipped. Both invocations
also emitted the separate zero-test Swift Testing footer. These are focused
regression results, not a full-suite or native-window qualification.

| Fixed selection | Passed methods | Failed methods | Retained child / runner exit | Retained wait and cleanup |
| --- | ---: | ---: | --- | ---: |
| Original new165 plus the added default-budget insertion boundary | 162 | 4 | 46652 / 1 / 1 | 281.984 seconds |
| New repair controls and original anchor/removal/accessibility controls | 113 | 9 | 54052 / 1 / 1 | 149.781 seconds |

The first run is
`artifacts/goal-ninth-new166-10188a1-aed3743f3442436ea9885c2210b3fbfb`.
Its combined log is 86,452 bytes, SHA256
`9995be5163a24c723150c8aa3003f4bbe845bc0eef2afeade45197595d10bf36`.
Launch `b0339e/session58168` closed naturally at `c8d5c0/1`.
Independent reconciliation `2700d4/0` recorded one start and one terminal
outcome for every selected method; the nine assertion errors belong to four
failed methods, not nine failed methods.

Navigation transport passed all nine methods, insertion boundaries all eleven,
and the original nested-List insertion regression now passed. The four failed
methods are the original accepted-zero-root insertion at its missing ViewNode
unwrap, plus the three mounted keyframe factory/identity ownership regressions
listed in `artifacts/goal-ninth-new166-10188a1-reconciled.json`. The original
keyframe reordering regression passed. The separate delayed ordinary cleanup
repair remains held for its same-permission facet successor review; this run
does not qualify that unintegrated proposal.

The second run is
`artifacts/goal-ninth-repairs122-10188a1-58a54e506385449588763f93ff351471`.
Its log is 54,375 bytes, SHA256
`05bf788740b4a7c40472b2b1af59e1c1b61636e4b697363e3578d078998f1ec2`.
Launch `89308c/session28695` closed naturally at `5c8ef0/1`.
Independent reconciliation `eeac0b/0` retained all 122 method outcomes. The
45 assertion errors, including eight reported unexpected unwrap errors,
belong to nine failed methods in PublicLazyListAccessibilityTests. That class
passed six of fifteen methods. Its realization, logical-ID, replacement,
anchor-preparation, and zero/multiple-leaf failures remain open; the pending
UIA proposal has not yet been integrated or tested against them.

Every other class in that second run passed: four leading-edge anchor tests,
seven terminal-checkpoint controls, one deferred-navigation trajectory, five
accepted-empty-row window tests, nine original managed removal transitions,
one managed navigation publication test, three mounted Tab handoff tests,
eight original mounted List state tests, two nested lease provenance tests,
nine ordinary source completion tests, eleven native declared-marker handoff
tests, four deferred lease source tests, twenty-three retained List runtime
integration tests, and twenty programmatic-scroll controls. In particular,
the original Tab return and both original keyed List state failures passed.
Passing the five new empty-window controls does not excuse the remaining
original zero-root descendant insertion failure.

Neither run timed out or terminated a process. Both retained original
source/index endpoints. The post-closure CIM records
`artifacts/goal-ninth-new166-10188a1-post-closure.json` (`ac174e/0`) and
`artifacts/goal-ninth-repairs122-10188a1-post-closure.json` (`65a5d7/0`)
observed the recorded PIDs and Swift/native processes absent. They are
point-in-time observations, not continuous descendant attestations.
Architecture contracts passed again after both runs (`65a5d7/0`).

The original test selections, assertions, four-round production defaults,
900-second execution budgets, earlier failed compilation evidence, and all
prior goal text are retained. The remaining failed methods require correction
and fresh execution; the full Core/List cohorts, native workload, visual
comparisons, complete release gate, and original product criteria remain due.


### 2026-09-01: preserve revoked UIA roots while disconnecting their original HWND

All nine original completion gates remain open. The earlier actual native
run failed at UiaDisconnectProvider after the public provider had correctly
become unavailable. Its failed trace and required-cleanup flag remain
unchanged. The reviewed shutdown repair now gives the explicit owned-root
factory an HWND identity and performs disconnect through a private native
identity object for that same original HWND.

The public provider remains revoked throughout shutdown. The owner pins the
original provider, revokes its family, waits for the existing full-method call
leases to drain, and then makes exactly one real UiaDisconnectProvider call
with the private identity. That object implements only the necessary native
simple-provider identity, owns no Swift callback context, tree, attachment,
or authored payload, and releases its local reference afterward. Allocation,
host lookup, and native HRESULT failures propagate; there is no reopen,
retry, public-provider exception, or fallback to a guessed HWND. Child and
generic roots retain their existing behavior.

The exact reviewed source delta is
`artifacts/goal-ninth-owned-root-ff98379-intake-v1/payload/owned-root-shutdown.diff`,
38,164 bytes, SHA256
`d0f2d56464582c295f171b34145434bc9a777830c10bfbf7e34941110f656ed8`.
The root staged diff is byte-identical to the six-path source packet from
`ff983797758543899836eecd080967f95839adb8`. The source proof
`artifacts/goal-ninth-owned-root-ff98379-root-proof-v1.json` (`15fd04/0`)
also verifies all 614 prior test files unchanged, no Package.swift change,
and ten new headless shutdown methods. Their native per-invocation probes
cover HWND identity, revocation, balanced references, quiescence, failures,
and the child/unmarked-root exclusions without opening a real window.

Independent source review found no remaining blocker. Root strict formatting
on both changed Swift files and architecture contracts passed (`134a69/0`).
Compilation, the ten new tests, original lifetime regressions, and a fresh
actual native shutdown are still required. A separate actor-dispatch repair
must also be integrated before the unchanged native workload is retried.
This source change does not qualify actual OS disconnect success, actor
separation, fairness, Narrator, performance, or release completion.


### 2026-09-01: queue owned UIA requests on the actor and preserve synchronous nesting

All nine original completion gates remain open. The second reviewed native
repair replaces borrowed-main-queue execution in the owned-provider dispatch
path with an ordinary MainActor Task. A foreign query keeps its original
copied envelope, callback context, and full call lease while waiting for one
actor result. It does not refresh source geometry, pump the native owner,
or execute an authored source callback on the waiting thread.

A private lexical native entry scope marks only an already-established,
synchronous actor stack. Its RAII object restores the exact predecessor
before returning. The synchronous nonescaping Swift wrapper owns its temporary
invocation box through that call. Only the queued production receive creates
this scope; no thread-ID observation, queue label, worker wrapper, TaskLocal,
or cached availability grants it. An already-scoped nested query runs the
existing receive immediately, preserving the original global nested-request
failure guard for both the same and a different provider family.

The reply cell distinguishes pending from completed nil. It claims its first
result under a short mutex and signals only after unlocking and after receive
and scope unwinding. No timeout or cancellation path can release the call
lease while the queued body can still execute. The original C method lease
continues through output publication and provider release; revocation does
not reopen availability. Legacy provider dispatch remains unchanged.

The source packet
`artifacts/goal-ninth-native-actor-aafecd8-intake-v1/payload/owned-actor-dispatch.diff`
is 54,385 bytes, SHA256
`f88cdbe0cd0570fad294aa78335966d27c0794000f7140807e72378b62102bc9`.
It includes the separate one-line correction in the new tests at
`aafecd82f502c6d8a4ad4c534176c0565131c0be`; the inaccessible redundant
observation was removed without changing the following real C success check.
The root proof `artifacts/goal-ninth-native-actor-aafecd8-root-proof-v1.json`
(`5b23e3/0`) verifies the complete staged diff equals the nine-path packet,
ten new methods, and 613 other existing test files unchanged. The only two
modified old test files are the existing owned request and item-container
fixtures, whose direct actor calls now enter explicit synchronous scopes.

The independent review packet is retained at
`artifacts/goal-ninth-native-actor-aafecd8-peer-intake-v1`. It reconstructed
the two original fixture token sequences after only those approved wrappers
and helper annotations, preserving all 63 C calls, 210 assertions/unwraps,
eight loops, 26 methods, and all raw-worker blocks. Its eight original critical
lifetime, admission, nested-request, and legacy bodies are byte-identical.
This is a source preservation proof, not compilation or execution. The
PublicLazyListAccessibility fixture uses the unchanged legacy provider factory,
so it does not require a new owned-entry scope for its existing raw calls.

Root strict formatting on all five changed Swift files and contracts passed
(`fa63d7/0`). The original 45 native-smoke regressions, 27 actual-native
predicates, workload, timeouts, and earlier failed native trace are unchanged.
Next qualification requires fresh compilation, the original 45 plus twenty
new native repair tests, original owned lifetime fixtures, a new immutable
binary binding, and the unchanged actual-native workload. Arbitrary raw-C
actor interop still needs a genuine explicit scope; direct-vtable tests do
not establish cross-apartment COM behavior. Actor separation, shutdown,
fairness, routed accessibility, and release completion remain unqualified.


### 2026-09-01: retain the native compile failure and make the HRESULT conversion explicit

All nine original completion gates remain open. The first 65-method native
repair attempt at `bb9337db43bd996831efd24e28e437f1ab09c517` failed during
C++ compilation before XCTest started. One aggregate initializer used the
unsigned UIA_E_INVALIDOPERATION constant where HRESULT is a signed Windows
long. C++ list initialization rejects that implicit narrowing. The same
location produced three diagnostics through the two template instantiations;
these are not three distinct defects or failed test methods.

The immutable attempt is
`artifacts/goal-ninth-native65-bb9337d-df3faf5bfbe9488a82b556e83710125b`.
Launch `548527/session2924` closed at `13b907/1`; retained child 40252 and
runner both exited naturally with 1 after 7.531 seconds, without timeout or
termination. The log is 5,951 bytes, SHA256
`96fcaa5d80c2715f0a024231a45c1d2f4e0cb0f434e0c4540d572ded14de87dc`.
The independent compile-failure reconciliation verifies unchanged source and
index endpoints and all 65 methods not run. It is not a successful compile
receipt and cannot bind an actual native run.

The correction adds only `static_cast<HRESULT>` around that existing error
constant. The branch, signed HRESULT value, quiescence requirement, all tests,
and all other source bytes are unchanged. The inverse source proof is
`artifacts/goal-ninth-native-hresult-cast-root-proof-v1.json` (`660d4f/0`).
Architecture contracts passed before and after this one-line C++ edit. The
same five classes, 65 methods, and 900-second budget will be rerun.

Two initial process censuses conservatively matched unrelated swift-format
processes and remain recorded as unsuccessful absence observations. The
separately derived census excludes only unrelated formatter name matches,
still includes any descendant of the retained PID, and reports formatters
separately. Its fresh third observation found no relevant process or formatter
(`3678ab/0`); no process was killed and no earlier receipt was rewritten.
This is a point-in-time closure observation, not continuous descendant proof.
Actual native execution and all broader qualifications remain pending.


### 2026-09-01: native repair tests pass; actual shutdown succeeds with three checks still open

All nine original completion gates remain open. Fresh compilation and the
fixed 65-method native repair selection passed on
`66e9a7dba78f0190cf8f6c2a39deee819a78b234`, tree
`c43571d9f68f4f7fc90045d71a1af961539ea96f`. The original 45 methods and
twenty new shutdown/actor-dispatch methods all started and passed, with zero
failures or skips and one separate zero-test Swift Testing footer.

The run is
`artifacts/goal-ninth-native65-66e9a7d-88890848b80c4bb7894b14d15927d62a`.
Launch `b439ab/session45777` closed naturally at `1192b8/0`; retained child
16924 and runner exited 0/0 after 364.719 seconds including compilation.
Its log is 3,348,863 bytes, SHA256
`7f2f17a505666f907af7cdc3e7f80cf4d8190475b2b676c9eaf72f10ca0516ee`.
Independent reconciliation and the post-closure census passed (`0cdd59/0`).
The separately observed formatter was not a SwiftPM/test process; the retained
child and relevant build/test processes were absent.

The actual native attempt used a fresh binding
`artifacts/goal-ninth-native-smoke-66e9a7d-binding-v1.json`, 35,057 bytes,
SHA256 `31e88bdbfc1d9df0a37f4ab9512cc303649255c916178caf3cf688e57172d1c3`.
The 93,475,840-byte executable has SHA256
`916c49316a96f6f6e4a1933b004b8908cc90da275a73fbea8ddb816b1b60fc7c`.
One native-executable link was observed in the successful build, and its
modification time falls within that retained attempt. The build-association
directory retains debug.yaml and the native link input list. All 135 immediate
DLL inputs from the two fixed Swift 6.3 directories were freshly pinned,
817,850,784 bytes total. These are input pins, not proof of loader selection.
An initial controller argument preflight refused a relative binding path
before creating an attempt directory or child (`5c4e06/1`); the same unused
binding was then supplied with its required absolute path.

The actual attempt is
`artifacts/goal-ninth-native-owned-smoke-f5d4b9307e054654a5063f09e375d3d6`.
Launch `82a496/session7073` closed at `797b48/1`: native child 34356 and
controller both exited naturally with 1 after 11.094 seconds. There was no
timeout, process termination, fixture failure, or native-owner failure.
The result remains failed: 24 of the original 27 predicates passed, while
actor-and-native-owner-thread-separation, actor-progress-between-backlogged-turns,
and backlogged-32-record-turn-and-continuation remain false. The result explicitly
records insufficient fairness exercise. The predicate set, 64-probe workload,
32-record bounds, timeouts, and original failed attempts are unchanged.

This run observed the previously missing shutdown chain: both native
attachments detached after the held full C call drained, renderer detachment
preceded NCDESTROY, the native close unwound before actor close consumption,
the native thread was joined, actor stop was consumed, and a closed-owner
command was rejected once. All 64 accepted probes were delivered in FIFO
order with 64 actual replies. All three frame phases, two mounted-task awaits,
and the three-second unforced settled-idle checks also passed. These observations
do not turn the three false predicates into passes.

The trace contains 2,776 contiguous records, 643,576 bytes, SHA256
`a39e8a39f3d155728d6206f6ef907bdc884098ae1d5a418e1a9b99df68315852`.
The 6,097-byte result has SHA256
`78964763f74cce1d90cd2d27354d9e0a75307d11c3c06ebd060c23ff8207dad4`;
raw stdout/stderr is empty. Independent reconciliation (`871984/0`) verifies
source/index and bound-input endpoints, file hashes, trace sequence/counts,
and agreement with all recorded predicates. It does not replace the semantic
validator. The process census (`b35488/0`) observed relevant processes absent.
The producer's requiresOperatorCleanupBeforeAnotherNativeRun flag remains true
and immutable; no automatic retry is authorized by this result.

Targeted trace inspection found all twelve actor-query callbacks on thread
56880 and the native query on owner thread 6352. The termination and join
observations occur on joiner thread 31624, naming 6352 in their auxiliary field.
That distinction is being reviewed against the separation predicate; no thread
ID has been rewritten and no classification change is yet qualified. The
backlog/fairness failure is being investigated separately. Original owned
fixtures, Core/List cohorts, full visual/release validation and product gates
remain required despite the narrower shutdown progress.


### 2026-09-01: ordinary owned handoffs retain only their accepted successor facets

All nine original completion gates remain open. The reviewed ordinary handoff
series and its facet-republication correction are now integrated as one source
unit. The original `614d0d4` series alone remains superseded for integration;
the accepted combination is the sealed `b1a5c9a` packet, whose 70,218-byte patch
has SHA256 `aa7b2209904878e516baa5fdd4ad111733866ae3da10ead00e07dd1c35192fa8`.
This repair targets the three surviving mounted-keyframe regressions from the
fresh 166-method run; source review does not establish that they now pass.

An ordinary replacement captures the original physical departure once, suspends
only continuing owned members, retires departing members before their callbacks,
and drains its original pending ticket at completion or abandonment. Continuing
members cannot write while their original declaration is suspended. Declaration
only, zero-source, region, and unrelated-attempt cases retain their established
retirement paths. Pending physical departures still drain before pending declared
marker retirements in both journal seal and abandonment.

The correction handles a later accepted publication of the same permission or
component on the original node. A native one-shot performs the original fourteen
physical-map removals in their original order and acknowledges success only when
the original storage, target, and attachment still match and all maps are empty.
Only a pending partition with that proven successful clear can preserve a later
facet. Each original member is checked again after preceding retirement callouts;
payload fields and structural membership must match their own later publication.
An expired or replaced storage, a changed attachment, a refused clear, an absent
publication, or a different member cannot acquire this exception. The one-shot
retains no physical node, authored payload, or replacement storage, and creates
no write permission. The existing retirement calls and region tail remain intact.

The source change touches RetainedLazyListActivity and Runtime and adds two new
test files: fifteen ordinary-handoff methods and eleven facet-republication
methods. All 616 existing test files are byte-identical to the preceding root
commit. Package.swift is unchanged. The complete root diff matches the sealed
patch except for Git blob IDs and hunk starting offsets; every context, added,
and deleted line and every hunk count is preserved. Reverse application checks
also passed. The root proof is
`artifacts/goal-ninth-ordinary-b1a5c9a-root-proof-v1.json`; the staged source tree
before this append is `d4e129191a980bb55c8af0abfcc8d3cc3b85d408`.

Pre-edit contracts passed. Strict formatting of all four changed Swift files and
post-edit contracts passed at `29fae1/0`. Root review verified the physical-before-
declared drain order separately (`02cc8a/0`). The proof helper completed before an
unrelated search in its command returned no match; its retained receipt and
full staged diff contain the successful comparison. No compiler or XCTest was
run for this source change yet. The original keyframe, Tab, removal, and empty-row
assertions remain required, alongside all twenty-six new methods. This does not
qualify the unresolved File14 run, broad Core/List cohorts, native fairness,
visual parity, performance, or any release gate.


### 2026-09-01: observe the accepted empty-row boundary before changing membership publication

All nine original completion gates remain open. A separate diagnostic XCTest is
added beside, without changing, the failing original accepted-zero-root-row
insertion test. It uses the same two layouts, one reload, one List query, one
row lookup, and the original animated-node and descriptor assertions with the
existing default budgets. Its test-local factory/body counters and four printed
boundary snapshots do not add a layout, query, journal, completion, lease, or
build permission. Native identities are retained to prevent address reuse from
confusing the diagnostic; physical nodes and original activity receipts remain
weak. The test closes the host and releases its captured binding afterward.

Source inspection suggests that a genuinely empty accepted row reaches the
native completed-row table without an owned component or effect group, but its
membership is omitted from the facade disposition. This is a hypothesis until
the diagnostic executes. The proposed production repair remains separate and
unapplied so the original failure and new observation can first run against the
same source. No synthetic owner, effect, task, or extra retry is introduced.

The diagnostic packet is `d62bc148302efd2f4b17d5b39e3e3a2b2c9e241e`;
its exact 9,881-byte source patch has SHA256
`5525870155f47641d7772538ef43953d2a93dc6836492f0c93238a5c0a38eac3`.
Root comparison verifies the complete staged diff is byte-identical to that
patch and all 618 preceding test files remain unchanged. The root proof is
`artifacts/goal-ninth-empty-arrival-d62bc14-root-proof-v1.json`. Strict formatting
of the single new Swift file and contracts passed (`2c0a8d/0`). No production
source, Package.swift, old fixture, timeout, or predicate changed. The new method
has not executed yet and provides no compatibility or release qualification.


### 2026-09-01: keyframe regressions pass; empty membership loss and three new handoff failures remain

All nine original completion gates remain open. The fresh fixed 132-method run
on `ea725523c6c04aceb6790a5fd9ecfff17fd0a2aa`, tree
`bfbfdab03156c5d28fe1fe7c53ea026dad557918`, started every selected method:
127 passed, five failed, and none skipped. All twenty-two mounted-keyframe
methods passed, including the three failures from the preceding 166-method run.
Playback fifteen, timeline twenty-five, original ordinary completion nine,
declared-marker eleven, Tab three, and removal-transition nine also all passed.
The new ordinary-handoff file passed fourteen of fifteen methods and the new
facet-republication file passed nine of eleven. These new failures still need
resolution before the handoff repair can be considered fully validated.

The three newly exposed failures are the later-declared-marker fixture's missing
owned receipt, the exact-republished-field test's retained permission/component,
and the closing-departure test's missing dismantle callback. The original
accepted-zero-root insertion and its separate diagnostic both still fail because
the physical descendant is absent. Existing assertions, budgets, and tests were
not changed to obtain this result.

The diagnostic now supplies an observed boundary: before reload the accepted
empty row has one mounted record, zero leaves, a declared logical membership,
and an active attached physical receipt. Immediately after reload the same
logical receipt is no longer declared, while its physical receipt and original
actual attachment remain active. The replacement layout never calls another
factory or body and never samples the insertion clock. The adapter remains
unresolved with no current accepted snapshot. This confirms that logical
membership is lost before replacement construction, consistent with the native
completed-row membership missing from the facade's accepted disposition. The
separate proposed membership repair was not applied during this observation.

The retained run is
`artifacts/goal-ninth-ordinary132-ea72552-ba2f48e0557e4083bd223fa419880e19`.
Launch `dac4f8/session4545` closed at `e24b3c/1`; child 38404 and runner
exited naturally with 1/1 after 385.375 seconds, with no timeout or termination.
The log is 3,431,265 bytes, SHA256
`54d65e6dcc5b7c7af09a391ee83d99993476a0423115f1ba87609aebf1defab4`.
Independent reconciliation and the post-closure process census passed
(`47e5ad/0`): source/index endpoints match, all 132 starts and terminals reconcile,
and the retained child and relevant build/test processes were absent. One
separate zero-test Swift Testing footer is not counted as additional coverage.
The diagnostic observations are retained in the same raw log (`9eb9b2/0`).

The native fairness diagnosis also remains an unqualified result. Its actor
ingress never consumed a full 32-record turn; native mailbox backlog and all
64 successful probe deliveries do not establish actor fairness. A proposed
initial scheduler hold was rejected because the existing fixture explicitly
forbids forcing backlog through scheduling changes. No hold, delay, larger
workload, predicate relaxation, or repeat attempt was introduced. The original
native 24/27 failed result remains unchanged. Full Core/List, native, visual,
performance, shared-platform, and release evidence remain required.


### 2026-09-01: integrate Button action ownership without discarding ordinary cleanup

All nine original completion gates remain open. The reviewed Button action
ownership series is integrated after the ordinary handoff repair. Pending
construction cannot expose an executable Button action before its declaration
is accepted. Rejected construction, physical departure, replacement, and close
retire the original action; a later physical attachment cannot revive a saved
old handler. Reentrant activation remains closed through the original action's
completion and payload release. Already claimed task, controller, disappearance,
and source cleanup still drains when forward Button admission expires.

Insertion completion now also remembers the original Button owner's presence,
weak identity, and retirement state. A clock or callback that clears, replaces,
or retires that owner cannot reuse the earlier completion to present an
insertion. No action payload is retained as a completion witness. The original
completion and admission are rechecked at their existing presentation boundary;
the renderer-neutral draw-order contract is unchanged.

The adapted Button-only patch is 372,876 bytes, SHA256
`9eacfb8c6d0e707b1d300d81fc35ac4ab4ddc692160970a74106eca75243c628`,
in `artifacts/goal-ninth-button-ordinary66-intake-v1`. It preserves every added
and deleted line of the earlier Button input. The sole composition resolution
keeps both original local declarations: owned departure tickets and Button
retirement. Their original finishing paths remain in the same defer, and
physical departures still drain before declared-marker retirements. Sixteen
of seventeen complete Button files match the original input; Runtime additionally
retains the three already-integrated ordinary handoff hunks.

Root independently verified the complete staged diff is byte-identical to this
adapted patch and all 619 preceding test files remain unchanged (`9e5421/0`).
The source adds six test files with 108 methods and two ownership documents.
Its staged tree before this append is
`d559f66e4a48abcc52e78186d51483e808a39789`; the proof is
`artifacts/goal-ninth-button-ordinary66-root-proof-v1.json`. Pre-edit contracts,
strict formatting of all fifteen changed Swift files, and post-edit contracts
passed (`0dce0b`, closed at `69539c/0`). Compilation and the Button tests have
not run on this root source. The separate reviewed fixture amendment must still
follow; its two additional methods are not included in the 108 count.

Correction to the preceding 132-method result description: the closing-departure
test's dismantle callback DID run exactly once, and its assertion at line 261
passed. The failure at line 266 is the missing final retired-slot record, zero
instead of one, after that callback revoked the host lifetime. The source review
is investigating publication bookkeeping after close, not missing callback
delivery. The retained raw result, five failed method IDs, and all assertions
are unchanged. The prior wording remains only as historical ledger text; this
line-specific clarification supersedes it. The two other new handoff failures
also remain under review, independently of this Button integration.

This source step does not establish a Button test pass, a File14 recovery,
Table/UIA qualification, native fairness, visual parity, or release completion.


### 2026-09-01: preserve the original Button insertion attempt in the fixture checks

All nine original completion gates remain open. The separately reviewed Button
fixture amendment now follows the unchanged adapted production series. Seven
setup lines in the existing insertion composition file defer the two negative
clock interventions until the initial descriptor exists. Their original
assertions and explicit 128-element/one-round bounds remain unchanged. The
ordinary positive case keeps the default four-round budget.

A separate two-method retry class captures the actual native attempt and
descriptor identities before the first successor copy. It checks that the
original refusal consumes its stale proof and leaves the old action inert,
while any successor uses its own source attempt. These checks do not claim
eventual descriptor commitment or a successfully executable fresh action.
All 108 earlier Button method IDs and assertions are preserved; the complete
Button selection now contains 110 methods. None has executed on this root yet.

The exact patch is 15,989 bytes, SHA256
`f1e76f634a84f147749895fb0fbae64c8950a6b16ffe3f17428284c6a9c9466d`.
Root comparison confirms complete staged-diff equality, one deliberately
modified existing fixture, one new test file, and byte preservation of the
other 624 existing test files. No production source, Package.swift, timeout,
or test assertion changed. The proof is
`artifacts/goal-ninth-button-ae49000-root-proof-v1.json`, with staged tree
`f5df0fbdd3a63d64e08182466b58d81f8515e9d2` before this append. Strict formatting
of both changed Swift files and contracts passed (`0376f7/0`). Compilation,
all 110 Button methods, the original UIA budget cases, and broader validation
remain pending; source review and fixture correction are not test passes.


### 2026-09-01: retain accepted empty rows through their native membership IDs

All nine original completion gates remain open. The production repair for the
observed empty-row membership loss is now integrated. Native row completion
already accepted an empty table anchored to its List container, but the facade
retained sparse rows only through accepted effect groups or owned components.
A genuinely empty builder branch has neither, so the next descriptor could
revoke its logical row before any replacement factory ran.

The journal now records the original membership ID at the same successful
completed-row boundary and carries those IDs in its immutable disposition.
Storage remains bounded to one ID per component, without retaining physical
nodes, providers, factories, State cells, or effect payloads. The facade unions
these native IDs into its existing accepted-membership selection. Sparse commit
also explicitly requires the original reservation's attempt to match that
selection. All existing completion, liveness, descriptor, revision, original-row,
and post-callback publication checks remain in place. This grants no synthetic
owner, group, task, or build permission and adds no query or retry.

The reviewed source is `a51a8ec5c099558cbcc8200c7e5dd57397fce84f` on its private
base. Its complete 45,967-byte patch has SHA256
`5e18bbc8e7c269ceb2ad6974307b75348470ea119e7929cda57a8c04a0eab09d`.
The production delta is twelve added and four removed lines across Activity
and StateMountRegistry. Two new files contain twenty methods: nine native table
cases, eight registry acceptance/refusal cases, and three complete bare-empty
facade cases. They include same-ID stale reservation rejection, partial and
uncompleted rows, revoked or competing descriptors, immutable repeated seal,
first physical insertion, empty reload, and deletion/reinsertion.

Root read every new method and the minimal production delta, then verified all
626 preceding test files remain byte-identical. The original failing test and
diagnostic are unchanged. The complete root diff differs from the sealed patch
only in Git blob IDs and hunk starting offsets; every other line and hunk count
matches, and reverse application checks pass (`929de1/0`). The proof is
`artifacts/goal-ninth-empty-membership-a51a8ec-root-proof-v1.json`; the staged
source tree before this append is `3208c21da7cf21accbe634bce1f6ac47d0b3059f`.
Pre/post contracts and strict formatting of all four Swift files passed
(`cbe929/0`). Package.swift is unchanged. None of these twenty methods, nor the
original failure, has run against this repair yet. Runtime, broader List/UIA,
visual, performance, and release qualification remain pending.


### 2026-09-01 root integration 87: Table construction and owned sort headers

The reviewed Table source is now composed after the accepted empty-row membership
repair at `ea323dbf6429dd22e309148fbd756ddaa0a6b20a`. This records a source
integration, not executed Table, Button, UIA, visual, or release qualification.
All nine original completion gates remain open and unchanged.

The nine-path patch is the original 129,363-byte Table patch, SHA-256
`d291eba7797b9d1bd9fa1750ceb6730bc815f04b4911078a85fceaf4d88dee11`.
The independently reviewed private composition was `754ba96626900bd92763273a965c91baac706fbe`,
tree `808bd7c5e5c6dbac9613e3b199f70bfa2193e68f`. Root read the complete independent
review and all three production diffs. A first source-only output attempt hit the
Windows stdout encoding for a sort glyph; the corrected UTF-8 read completed at
`24437d/0`. No source adaptation or fixture change was needed on root.

Table keeps its original construction attribution across authored collection, ID,
header, and cell callbacks. Both row-ID erasures share one original lookup receipt.
Single-selection reads use the caller's original continuation, read the binding
once, and check before and after erasure; an optional nil value remains distinct
from rejected admission. Typed child installation remains outside the pure lookup
receipt, so legitimate child State publication is not itself rejected. Sortable
headers with a callback use the normal typed Button and its accepted action owner.
The author still owns the declared sort state and data order.

Root pre-edit contracts passed in `6d12f2`; strict formatting of all eight changed
Swift files and post-edit contracts completed with `3f47d2/0`. Source proof
`dcc100/0`, retained in `artifacts/goal-ninth-table-ea725-root-proof-v1.json`,
binds the staged source tree `57517068a255aad0dd28cf08dabb3b083b409dbe`.
Its entire staged patch is byte-identical to the sealed original, the reverse
patch check passes, and all 628 pre-existing Tests files remain byte-identical.
The five added test files declare exactly 56 new async methods: 12 identity and
selection admission, 14 construction admission, 16 sort interaction, and 14 sort
ownership. These methods have not yet run on root. The earlier 110 Button methods
and the newly integrated 20 empty-membership methods are preserved, also awaiting
fresh combined-source execution. Package.swift is unchanged.

The documented Table remains eager. This slice does not establish the complete
SwiftUI sortOrder/comparator API, multi-column sorting, table virtualization,
macOS behavior, visual parity, template completion, or native accessibility
qualification. Default list budgets and the original Row300 test are unchanged
and still require execution after the pending accessibility composition.


### 2026-09-01 root integration 88: original UIA continuations after Table

The reviewed accessibility continuation patch is now composed on root after Table
commit `9f3ff4a90e49ed54844e014801c6904ad16ecf6d`, preserving the accepted empty-row
membership repair. This is source integration only. All nine original completion
gates remain open; the earlier failed PublicLazyListAccessibility and native
Row300 results are not converted into passes by this change.

The immutable input is the UIA-only private `754ba966` to `b920cb98` composition,
not replacement snapshots of root files. Intake `ec7586/0` verified all 99 payloads
(12,668,115 bytes), manifest SHA-256
`cfd331e43d145d33496f27dd78da21bc3107b2bd426969adcc7593732d38005d`,
and seal SHA-256 `4414e048e2060be41c4f3503a8936ae72389ed6731cec11581ee9c633f058357`.
The incoming 680,852-byte patch has SHA-256
`5be38d5c01e14607e106e5678483260b74be8ef1810da7a65acb9cbca0171e78`.
Its previously approved seven literal unions retain the original ordinary
completion source membership alongside the separate original UIA authority.
The independent review, read in full at `2591fe/0`, found no bounded composition
blocker and verified 39 phase/query/counter/cleanup bodies against the incoming
source. These are preservation comparisons, not runtime results.

The UIA path carries its original construction/query continuation through bounded
provider preparation, target construction, reconciliation, scroll geometry, and
publication. An unused provider phase is consumed or drained using its original
authority; the patch does not turn ordinary source membership into UIA permission.
Insertion-origin capture uses the original bounded native predecessor cohort.
The ten added insertion cases are separate from the prior 112 cases; their
explicit-sixteen positive fixture is not evidence for the default-four budget.

Root pre-edit contracts passed in `bd5aa6`; strict formatting of all fourteen
changed Swift files and post-edit contracts completed with `c1ba4d/0`. Root proof
`b338d2/0`, `artifacts/goal-ninth-uia-aftertable-b920-root-proof-v1.json`, binds
staged source tree `7c835b4ec236cea3558b8f7a624fe576e556d78f`. The complete root diff
differs from the sealed patch only in Git blob IDs and hunk starting offsets;
every context, added, and deleted line and every hunk count is unchanged. The
reverse patch check passes. The actual staged patch is 680,852 bytes, SHA-256
`766ddeafadd5a7bb2b6fed4567efd20f5b82a2b662179f58b6e9ce97a244c704`.
All 633 existing Tests files remain exact, including Button110, Table56, and the
20 membership regressions. The seven new test files contain 122 methods with
class counts 30, 40, 10, 3, 22, 13, and 4. None has yet run on this root source.
Package.swift is unchanged.

Fresh combined-source validation must still exercise the original default-four,
explicit-eight/sixteen, exhausted 1x1, generic no-far-row300, and native Row300
contracts. The fixed Core320 and List402 selections remain required, not replaced
by this new cohort. PublicLazyListAccessibility uses its existing legacy bridge;
passing it would not by itself qualify the separate owned native actor hop.
No native, visual, macOS, full-suite, or release claim is made by this integration.


### 2026-09-01 root integration 89: refuse retired ownership after publication

The fourteen-line, two-site Activity repair is composed after UIA commit
`46d487ac16162a5ec8fbeda3caf73afba7e2b649`. It addresses the precise failed final
retirement count in `testAClosingDepartureCallbackCannotPublishThePreparedContinuation`;
the callback itself ran in the earlier failed execution. The complete original
closing-callback test remains unchanged. No fresh behavioral pass is claimed.

The approved guards run immediately after publish's weak-source scan and before
the first prepared payload/structural membership map write, both for inserted
nodes and completed nodes. They inspect only each original declaration's owner,
native lifetime, and slot generations. They do not require an accepted owned
write: an ordinary suspended continuation can still be valid. They capture no
new receipt, rescan no returned tree, and skip no runtime cleanup. Refused native
activation therefore cannot leave a new physical footprint that masks retirement.

Root intake `8cabc6/0` verified the sealed 13-payload ordinary repair packet,
409,835 bytes, manifest SHA-256
`6ad78935e5ba549a49b601d25b6b31247137d0b13e8d3d8b498d3784632000df`.
The complete production and fixture diffs and independent review were read at
`28cf1a`; only the production patch is applied in this commit. Its 2,133 bytes
have SHA-256 `c7489bbccedd5391b6275916a4a6a4af5e3a0378c9837c46b38fac7e4254e363`.
The private production commit is `6296dc83b9e1e41a3a45e0cec35365bcb5a06d8c`.

Pre/post architecture checks and strict formatting of the one changed Swift
file passed in `4b925d/0`. Source proof `3450c8/0`, retained in
`artifacts/goal-ninth-ordinary-production6296-root-proof-v1.json`, binds source
tree `2159eaab6218239324bfc0eefff511f9c1b05d7b`: the entire patch is unchanged
except Git blob IDs and hunk starting offsets, its reverse check passes, and all
640 existing Tests files are exact. The actual staged patch SHA-256 is
`33c9a90b1e83fbd34b0dcf23bf91fa4d3114d65487853f73c28478004fcae708`.
The earlier accepted-empty membership and UIA changes remain intact; Package.swift
is unchanged. The separately reviewed fixture corrections will follow before
the combined regression run. Analogous property/declared-path observations are
a separate source audit, not part of this bounded correction or a claimed pass.
All nine original completion gates remain open and unchanged.


### 2026-09-01 root integration 90: preserve the ordinary fixture premises

The separately reviewed ordinary fixture patch follows production repair
`524172375cb9cc0208318a3144f3a3599139ea5a`. It changes only the original fixture
setup, not any assertion, method identifier, budget, or expected result. The
three previously failed ordinary cases still require fresh execution.

The declared-marker case now registers and prepares its original declaration-only
continuation before capturing the departure that suspends its slot. Acceptance
still occurs after that departure, and the suspended-write assertion is unchanged.
The exact-payload case removes an unintended identity payload before its first
publication, using an opt-out whose default remains true for all other fixtures.
It does not clear identity mid-test, which would revoke a different proof and
obscure the intended onAppear/onDisappear distinction.

The 2,559-byte sealed fixture patch, SHA-256
`d6e697af0da792e667bedc75bdc6be13c1ca94833b642d48d669c0d6aede3fc4`,
is composed byte-identically on root. Strict formatting, contracts, and root
source proof completed in `226114/0`. The proof is retained in
`artifacts/goal-ninth-ordinary-fixture-e1e753f-root-proof-v1.json`, binding staged
tree `7cb25468f3f9628c61a72e136b14569097e34c21`. Of 640 existing test files,
639 are unchanged and the sole amended file has exactly the three approved hunks.
The independent whole-file inverse and assertion proof preserves all 26 original
methods and all 249 complete XCTest calls across the two ordinary test files.
OrdinaryOwnedHandoffTests, including the entire closing-callback test and final
retirement assertion, remains byte-identical. Package.swift is unchanged.

No compiler or XCTest run has qualified these amendments yet. The next combined
selection retains all original 132 identifiers and appends the 20 empty-membership
regressions. All nine original completion gates remain open and unchanged.


### 2026-09-01 root integration 91: observe actual native-thread termination

The reviewed native termination-observer correction is integrated after
`5723c3d55b1691fc7c7d54c5608c4ced23f0c5d8`. The old native attempt remains failed
at 24/27, with its original result, trace, exit statuses, and cleanup-required
flag unchanged. This source change does not reclassify that old trace or create
a native pass. All nine original completion gates remain open and unchanged.

Win32NativePump still observes the original thread handle on its existing join
worker after successful WaitForSingleObject. The observation now includes that
actual wait result; it still records GetCurrentThreadId for the real observer and
the original native owner's ID as auxiliary data. There is no fabricated thread
ID, early termination marker, extra scheduling hop, or changed shutdown order.

The validator distinguishes that post-wait observation from work produced by the
window thread. Unique owner-entry, close-return, termination, and join receipts
must name the same original owner and satisfy owner < close < termination < join.
Termination and join share the actual nonzero observer and require successful
wait/exit values. All remaining native records precede termination and join on
the original owner. All receipt rows count before success is checked. Actor
separation still covers the complete original owner-entry-through-join interval,
including the termination-to-join gap. Missing termination retains only the old
partial separation possibility; it cannot establish the complete join predicate.

Root intake `eb5589/0` verified the passive wrapper: 53 payloads, 648,008 bytes,
manifest SHA-256 `e39ec16b502bac65e385b4cf9300b900626ee9b56bb6de042a062f57699b7bfa`.
The mapping-shaped original manifest, original seal, and all 51 original payloads
are preserved under original/. Root read both production diffs and the complete
independent review at `fad0dd/0`. The private source is `555bf18e176a874151d01213466658d8bf2fab89`.
Its exact 27,706-byte patch has SHA-256
`82b133c146d09856ad8dc032673f6d8cdb5775a567ffe0e7eeb0e44a3ed59cb1`.

Root pre/post contracts, strict formatting of all four Swift files, and exact
staged-source proof passed in `2c8ce3/0`. The proof is retained in
`artifacts/goal-ninth-native-termination555-root-proof-v1.json`, binding source
tree `31dd4e0182920d16d307d791d358798333974cd7`. The entire root diff is byte-identical
to the sealed patch. Of 640 old test files, 639 are exact and the sole changed
file contains only the two approved trace scaffolds. Independent inverse proof
restores its complete old blob and preserves all 22 methods and 58 assertions.
The 29 new async regressions have not run. Package.swift is unchanged.

The future focused native prerequisite keeps the original 65 identifiers and
adds these 29, for 94. Only a fresh same-HEAD successful compile, exact test
reconciliation, and closure evidence may produce a new binding. The 27 predicate
names, 64-command workload, ordinal-31 query, 16/32 bounds, idle interval, trace
caps, fixture/watchdog deadlines, and 55+5 outer budget are unchanged. No forced
backlog, scheduler hold, workload increase, or retry to search for a fairness
pass is authorized. The two independent fairness predicates remain unqualified.


### 2026-09-01 root validation: combined source does not yet compile

The first fresh combined-source attempt at `229122b535d5e6e6b8b1d79a27128a775a55cfa3`,
tree `65b140f375f36e8fc6183cfba175a8a3cd9d1586`, failed during compilation.
All 166 selected Button/Table methods are NOT RUN, not failed XCTest methods and
not passes. The source-only integration checks above did not establish compilation.
All nine original completion gates remain open and unchanged.

The original planned ordinary152 selection first stopped before launch at
`d8fbcc`: the unchanged derivation helper requires one XCTestCase per file, while
the accepted-membership file intentionally contains two classes (nine and eight
methods). Its new spec is preserved unchanged. No SwiftPM command or test ran
from that failed derivation. A separate strict inventory extension is being
reviewed; it must retain all original 132 identifiers and all 20 appended methods,
validate every declaration, and preserve the 900-second execution bound.

The existing helper successfully derived Button110 plus Table56 at `6be088/0`: eleven
classes, 166 unique async methods, and 21,363 identifier characters. The 19,992-byte
runner differs from its fixed donor only in the two class-filter literals, SHA-256
`22742b1407e221ba14b74770f88249779ce38affd8b280327dc9f1b011d3d027`.
Run `artifacts/button-table166-229122b-8836b1aeb8ac451fb3269cde3441d867` launched
with `914dfd`/session 54864 and closed naturally with `6a8fa6/1`: actual child 1,
runner 1, PID 21344, 39.469 seconds, no timeout or termination attempt. Source and
index endpoints match. The 19,468-byte raw log has SHA-256
`28eff95e1371f59dc551ff2f19d6393429f07583a8cd578ba811c2fb4b65dea4`.

There are exactly sixteen unique source diagnostics: one non-Sendable Button
action conversion at RetainedButtonActionOwner.swift:78; thirteen main-actor
isolation diagnostics in the new Runtime geometry snapshot at 13874-13889; and
two references to nonexistent PrepaintInteractionState.visibleFrame at 24651.
There is no completed build, started XCTest method, or successful test terminal.
Root is preparing narrow production fixes without changing assertions, actor
safety, UIA permissions, or construction/turn budgets.

Independent reconciliation and post-closure CIM passed in `f9198a/0`, retained as
`artifacts/goal-ninth-button-table166-229122b-compile-failure-reconciled-v2.json`
and `artifacts/goal-ninth-button-table166-229122b-post-closure-v1.json`. CIM found
no matching process or separate formatter; this is a point-in-time observation,
not continuous descendant attestation. The earlier `ad680c` reconciliation call
misused a single-valued substring option as three repeated options and stopped
before writing a receipt; the successful successor preserves and lists all
sixteen original diagnostics. No old execution artifact was rewritten.


### 2026-09-01 root integration 93: sealed overlay probe input planning

The four-file Stage B intake slice is composed after the recorded combined-build
failure at `2e623e8bdd019975dcbcf58789c08a57eb401d1d`. It is tooling groundwork,
not a repair to that Swift compilation and not Apple SDK or API conformance
evidence. All nine original completion gates remain open and unchanged.

The input reader reuses the strict capture/census readers and joins complete
Stage A discovery records to the original definition occurrences, aliases,
ordered overlay names, module contexts, and source seals. The public path
rejects synthetic/incomplete input. Explicit plans bind their source hashes,
native profile, both original macOS 26.5 targets, language mode, and bounded
selected definition pairs; they cannot inject source/search-path arguments.
Unselected or unresolved occurrences remain explicit rather than becoming API
absence or a scope exception. All nine original audit streams remain required.

The sealed private source patch from `941c4485e51ffbb80612a42b8fa3724da5106a50`
is 144,358 bytes, SHA-256
`1c538afb33b66af04985bf2d1ececc9028d082f0cfa623fcbdd658f77ac4a381`.
Root `ab00b3/0` passed pre/post contracts under PowerShell 7 and proved the
complete staged diff byte-identical. Proof
`artifacts/goal-ninth-stageb1-941c-root-proof-v1.json` binds staged source tree
`aa868b156c6368340349d129910c898d4a235b40`; all 641 existing Tests files and
Package.swift are unchanged. No Swift file changed. The 72-case/427-assertion
synthetic intake selection has not run on root yet; its private result is not
presented as a fresh root result.

After the collection slice, root will run each of the four complete synthetic
suites in a separate PowerShell 7 process with a fresh output root and no case
filter. Existing managed streaming support may compile C# in-process through
Add-Type; these tests do not launch an external compiler, SwiftPM, native Apple
collector, or SDK workload. They cannot close SDK identity review, full overlay
coverage, declaration review, or behavioral conformance.


### 2026-09-01 root integration 94: bounded overlay collection evidence

The reviewed Stage B collection slice follows input planning commit
`3fbd8885ad4e7e385d3c59d08d1ccdbb9d348abd`. It adds separate native observation,
supplemental graph, and final collector paths with explicit source/profile
bindings and qualification fields. It does not establish that any Apple SDK
workload has run, that an unselected overlay is absent, or that API compatibility
is complete. The original scope, targets, nine streams, and gates are unchanged.

The original private collection patch is 441,776 bytes, SHA-256
`baa39abafc44728fb8c8f4ed9f07c266533f03db422794768a4a43a5eb3e13eb`.
Root `a6c8ce/0` passed PowerShell 7 contracts before and after application and
proved its complete staged diff byte-identical. Source proof
`artifacts/goal-ninth-stageb2-92e23-root-proof-v1.json` binds staged tree
`5496e5f25c212743f6b9bd5763a5bb4eb8ecf19c`. The patch adds sixteen new paths and
appends to the existing probe documentation; all 641 existing Tests files and
Package.swift remain exact. Together the two Stage B slices add twenty paths.
No Swift source, XCTest assertion, compiler setting, or runtime budget changed.

Root synthetic validation is still pending: intake72/427, native28/286,
graphs71/304, collector45/501, totaling 216 cases and 1,518 assertions. These are
the required full selections, not root pass counts. Each suite must run in its
own fresh PowerShell 7 process with no case filter. Evidence must retain exact
case identities, loaded dependency hashes, zero adapter/process invocation
counters, collector fullSuite, unchanged source endpoints, false qualification
flags, and graph nativeExecution=false. The existing nine-stream capture remains
untouched. In-process Add-Type may compile the managed helper; no external
compiler, SwiftPM, native SDK collector, network, or macOS workload is authorized
by this synthetic check.

The combined Swift build still requires its separately reviewed Button/Runtime
compile corrections and a fresh run. No tests or native qualification are
inferred from these tooling integrations. All nine original gates remain open.


### 2026-09-01 fresh Stage B synthetic validation: 216 cases, 1518 assertions

All four complete synthetic suites passed on root `1bebfb61d88b1a3e6d4605c8241b39ca18a9d1c0`,
tree `268ef5316f333e1b017067ee0897d00d564c2e86`, in separate PowerShell 7.6.4
processes without case filters. These are fresh tooling results, not copied
private receipts or Swift XCTest/native SDK results. All nine original completion
gates remain open and unchanged.

The new output root is
`artifacts/goal-ninth-stageb-root-1bebfb6-ddba14e8a14547e1a2e67edbc917122d`.
The start binding is `d8746c/0`. Observed exits and complete selections are:

| Suite | Cases | Assertions | Root execution evidence |
| --- | ---: | ---: | --- |
| Intake | 72 | 427 | ef80d5/session24822 to d0347a/0 |
| Native-record parser, synthetic only | 28 | 286 | e8a08a/0 |
| Supplemental graphs, synthetic only | 71 | 304 | 2fdb72/0 |
| Collector, synthetic only | 45 | 501 | edbe16/session24920 to c6e302/0 |

Post-run contracts passed in `246f8d/0`. Reconciliation `131edf/0`, retained in
`artifacts/goal-ninth-stageb-root-1bebfb6-reconciled-v2.json`, verifies all four
ordered case lists against their sealed rosters, all 216 case outcomes, no
failures/skips, and all 1,518 reported successful assertions. The unchanged
source/index endpoints include 126 script/baseline/goal/package files. The
collector's sixteen actually loaded source hashes match before/after and disk;
its fullSuite flag is true, both adapter/process counters are zero, and all four
qualification flags remain false. Graph nativeExecution remains false. Intake
verifies the original source capture, all nine audit streams, and positive
census fixtures unchanged. Add-Type initialized the existing managed helper
in-process; no external compiler, SwiftPM, SDK collector, or native SDK ran.

The first reconciliation helper stopped at `7b85a6` because it incorrectly
assumed every intake assertion belonged to a named case. Source inspection at
`d838ee/0` confirms the unchanged global counter also includes initial checks
and census-fixture setup outside those case windows. The successful immutable
successor records 310 named-case assertions plus 117 outside them, retaining
the exact original total 427; native and collector per-case totals match their
global counters. Neither tests nor receipts were altered to resolve this
accounting error. The graph schema does not report per-case assertion counts.

Report SHA-256 values, in suite order, are
`c7dec6c3ecf6698b3c002517f1a7a93e7c4dc16129a0aa98330a496e8bc44603`,
`465c7c47ca81d176b5e39f71b58afe40e634db70019a048071b676e34547e66b`,
`2f431e4b72f64045c12a13d024fecd44ec04cb508a5f67217d428967a5fdd5e7`,
and `0cc48cc26ec137520f77b4e295b123b5c2fd7b867ed0faeb6dcd25d27a79cb90`.
Actual SDK identity, overlay/declaration completeness, behavior conformance,
macOS execution, and release qualification remain separate unfinished work.


### 2026-09-01 Button callback isolation compile correction

The combined Button/Table166 attempt recorded above stopped at compilation;
none of its 166 selected XCTest methods executed. Its Button diagnostic came
from passing the existing optional, plain callback directly into the new
main-actor payload closure. The reviewed `bc480060` correction now wraps a
non-nil callback in an explicitly `@MainActor` forwarding closure. A nil
callback still produces the same payload object with a nil action.

The forwarding closure captures only the original action. This change adds no
task, actor hop, unsafe isolation assertion, initialization callback, or strong
node/runtime capture. The public Button and control callback signatures remain
unchanged. Payload identity, completion, retirement, and lifetime logic are
unchanged. A non-nil action gains one forwarding closure; its cost has not been
measured.

Root validation before this ledger append:

- Source parent `1e895d7d0c2aa2ef6e93ecbad550edc20a73bf8b`;
  staged source tree `1e9b19174ae728cb848b6ec045cbf3ddaec427b2`.
- The complete staged diff equals the sealed 880-byte source patch, SHA256
  `31efa0de193903cb1c4df1d14b3cafb225231372d30df1c2e3d44b73afc9c5b0`.
- Pre/post architecture checks and strict formatting of the one Swift file
  passed. All 641 existing test files, including the seven Button classes and
  all 110 Button methods, remain byte-identical. Package.swift is unchanged.
- Proof: `artifacts/goal-ninth-button-sendability-bc480-root-proof-v1.json`.

These are source and formatting checks, not a successful compiler or XCTest
result. The separate Runtime compile correction and fresh preserved cohorts
remain required. No original completion gate is closed by this change.


### 2026-09-01 UIA phase reader and prepaint compile corrections

The reviewed `652f61e4` correction addresses the remaining Runtime diagnostics
from the failed Button/Table166 compilation without changing the selected
tests, continuation budgets, or cleanup rules. The nested UIA phase `Reader`
is now explicitly `@MainActor`, matching its retained-node reads and the
existing main-actor construction and currentness call sites. Its weak storage
and reader body are unchanged.

The resolved-target test now reads the existing prepaint interaction `frame`
instead of the nonexistent `visibleFrame` property. That frame is the raw
absolute layout rectangle, not an exact clipped pixel-visibility rectangle.
The interaction entry has already passed the existing transformed-paint and
clip culling; presence plus positive raw extent remains a conservative
condition. This correction introduces no new coordinate-space intersection,
transform exclusion, fallback, or visibility guarantee.

Root validation before this ledger append:

- Source parent `77067bdff6ad04a7d82465cbc1729cae651a4eb1`;
  staged source tree `a42252c4ea78b22a6d2bc913e24ebe25e5a91289`.
- The complete staged diff equals the sealed 1,055-byte source patch, SHA256
  `860709d65d4d7d6f2b145b633508c2026eb74b0266a4f4722fd005d1cacddaf6`.
- Pre/post architecture checks and strict formatting of Runtime.swift passed.
  All 641 existing test files and Package.swift remain byte-identical.
- Proof: `artifacts/goal-ninth-uia-compile652-root-proof-v1.json`.

The preceding Button fix and this Runtime fix have not yet been compiled
together. Fresh Button/Table166, ordinary152, UIA continuation/budget/public
accessibility, and original Core/List validation remain necessary. The
previous compile failure remains failed evidence. All original goal gates
remain open.


### 2026-09-01 preserved ordinary152 selection reaches two further compile errors

The source selector now handles the two XCTestCase classes in
RetainedLazyListAcceptedMembershipTests.swift. The reviewed derivative keeps
the existing lexer, declaration checks, donor pin, roster limits, and timeout;
it validates the entire masked file before selecting a named top-level class.
Malformed or duplicate unselected siblings do not disappear from validation.
The spec's explicit sourceFile entry selects the eight-method sibling from
that same file without splitting, renaming, or dropping either test class.

The root packet is `artifacts/goal-ninth-multiclass-focused-parser-intake-v1`.
Its preparing reviewer recorded 135 parser-only checks, and the independent
reviewer recorded 111 overlapping parser/filename checks. Those are not
XCTest results. Root read the derivative, exact patch, notes and review, then
verified all 13 selected source files equal their committed 229122b versions.
The fresh spec changes only its HEAD to `78b890b6`. Its derived runner changes
only the donor's two class-selector literals. Root independently verified all
132 original identifiers plus exactly 20 additions: 152 unique async methods,
14 classes, and the unchanged 900-second budget.

The actual attempt at `78b890b6aecd7c41fbfccb7fcf53be43da7162c6`, tree
`85a278a267c5f27a0aa2bfe1f9c29d91a7d95370`, is retained at
`artifacts/ordinary152-78b890b-bace012664724a99800896c3196fcd4a`.
Runner and retained child 16196 exited naturally with 1 after 69.641 seconds;
there was no timeout or termination, and source/index endpoints matched.
The raw log is 12,779 bytes, SHA256
`265ee95a75aac7e713b81b10d678657f99e8710b1c0165f6c2be0e3c7d3f9212`.

The build advanced past the previous Button and Runtime errors, then failed
on two unique diagnostics. TableConstructionAdmission.withValueLookup passes
the nonescaping isCurrent parameter into another nonescaping parameter in a
way Swift rejects for possible reentrant modification. StateMountRegistry's
empty-membership check directly reads the preparation's fileprivate attempt
field. That second error appears twice in the build log. The original attempt
identity check and Table callback/admission semantics must survive their fixes.

Independent reconciliation is
`artifacts/goal-ninth-ordinary152-78b890b-compile-failure-reconciled-v1.json`;
the following point-in-time CIM census is
`artifacts/goal-ninth-ordinary152-78b890b-post-closure-v1.json` and found no
matching process or formatter. There were zero XCTest starts: all 152 methods
remain NOT RUN for this attempt. No original goal gate is closed, and the
separate mixed-roster ownership gap remains open even after compilation.


### 2026-09-01 Table value lookup avoids invalid nonescaping forwarding

The Table compile correction removes the unused currentness parameter from
withValueLookup's callback and from its six call sites. Those callbacks read
the collection's start/end indices, compare indices, fetch an element and its
ID, or advance the index. None used the supplied predicate. withLookup itself
is unchanged: the original lookup receipt, pre-call/final checks, refusal
short-circuit, callback ordering, and cleanup scope remain in place.

The wrapper still explicitly returns Optional<Value>.some(body()). An authored
Optional.none therefore remains a successfully obtained value; it is not
confused with failed admission. No callback becomes escaping, and no unsafe
exclusivity or isolation override, new ownership token, or fresh receipt is
introduced. The two typed ID erasures keep their existing withLookup scopes.

Root extracted the exact frozen `6c9f1f608cd2851d223cd9f3087a877aba9feee8`
diff, independently read all eight substitutions, and applied that 3,078-byte
patch without adaptation. Its SHA256 is
`a0a533a2ec7c11ad7fea714d5f000e4c1a3a14b9bd360df69644164024fce0b6`.
The staged source tree is `eecb840213d1e710ffe5825eab679cce1903ad28` on
parent `4d39f404e25c4f1ffc3939d18ff11a0ef8bc105b`.

Root pre/post contracts, strict formatting of both Swift files, and the exact
staged-diff proof passed. All 641 prior test files, including Table56 and
Button110, and Package.swift are unchanged. Proof:
`artifacts/goal-ninth-table-value-6c9f1f-root-proof-v1.json`.
This is not compiler or XCTest qualification. The separate immutable-attempt
access correction and a fresh combined build remain required; all original
completion gates remain open.


### 2026-09-01 expose the original selected-row attempt within the package

RetainedLazyListSelectedRowPreparation.attempt now has package read access
instead of fileprivate access. It remains an immutable let of the existing
package-scoped native ID type. Its initializer and sole journal construction
site are unchanged. This allows WinSwiftUI's sparse empty-membership guard,
and the existing stale-reservation regression, to compare the exact original
selected-row attempt without changing either consumer.

The selected-row attempt is not the descriptor-build attempt. Replacing that
comparison with descriptorBuildAttemptID or with a live construction query
would change its authority and is not part of this fix. No public API, setter,
constructor, receipt refresh, acceptance rule, or lifecycle behavior changes.
StateMountRegistry.swift remains byte-identical.

Root applied the exact sealed 897-byte `22b392bd` patch, SHA256
`cd120befa62d95819780246d85fa9afd62ec8abe823264e93a7523f183032e9c`.
On parent `a69b9f00a63f860b2248769715a7771f44054c5b`, the staged source tree
is `5c29ba7f60cff22135a00147a977f6b7f05fd997`. Independent source review,
root pre/post contracts, one-file strict formatting, and the complete staged
diff proof passed. All 641 existing test files and Package.swift are unchanged.
The retained packet and proof are
`artifacts/goal-ninth-attempt-access-22b392-intake-v1` and
`artifacts/goal-ninth-attempt-access-22b392-root-proof-v1.json`.

Both newly diagnosed compile fixes are now present in source, but the failed
ordinary152 attempt remains failed and all its selected methods remain NOT
RUN. Fresh compilation and execution are the next evidence requirement. All
nine original completion gates remain open.


### 2026-09-01 production compilation advances to six fixture compile failures

The next ordinary152 attempt used clean commit
`16a0b546d2ef764dc6b9bac9ef284444b88ff578`, tree
`64a27a73afa5c450dc7767a8f7e5984949ee03e7`, with the same 152 selected
identifiers, 13 source files, and 900-second limit. Its retained directory is
`artifacts/ordinary152-16a0b54-c8e324a4ea724ad3abd247358bce761b`.
The runner and retained direct child 42376 exited naturally with 1 after
129.078 seconds. There was no timeout or forced termination, and source/index
endpoints matched. The raw log is 3,812,265 bytes, SHA256
`6dfbfe02f6400d66a4e4660600cf3bb8bc401cf3bd62e5b56da4889e921461be`.

Production compilation advanced past the earlier Button, Runtime, Table and
selected-row attempt access errors. Test compilation then reported 427
diagnostic headers containing 25 unique errors across six fixture files:
two Button files, two Table files, and two UIA files. The errors concern
explicit self captures, actor-isolated function conversions, generic and
key-path type inference, two lease fixtures missing protocol requirements,
and three test references to the nonexistent prepaint visibleFrame field.
The UIA enum inference errors may be secondary diagnostics; that remains to
be established by correction and compilation, not assumed to be a test pass.

The repair scope is the affected fixtures. Existing identifiers, assertions,
expected values, callback order and ownership/visibility oracles must survive.
In particular, PrepaintInteractionState.frame is a raw absolute layout frame,
not exact clipped visible pixels; replacing the missing name must preserve
the partially visible target tests' meaning. Lease conformance must retain
real fixture revocation behavior rather than substitute unconditional success.

Independent reconciliation is
`artifacts/goal-ninth-ordinary152-16a0b54-compile-failure-reconciled-v1.json`.
The following point-in-time CIM census,
`artifacts/goal-ninth-ordinary152-16a0b54-post-closure-v1.json`, found no
matching process or formatter. There were zero XCTest starts or terminals:
all 152 selected methods remain NOT RUN for this attempt. The separately
prepared Button/Table166, UIA122, public-budget19 and native94 runners were
not executed. All nine original goal gates remain open.


### 2026-09-01 make Button fixture captures explicit without changing teardown

Two nested construction calls now spell self.button explicitly, preserving
their existing outer self captures and their original execution positions.
Two teardown fixtures store explicit main-actor forwarding closures. Each
capture initializer reads and unwraps the original onActivate callback at the
original append statement; its body later calls that saved callback once.
The wrapper does not reread the Button, capture the Button or event table,
add a task or actor hop, or extend the callback into a new test-scope local.

The exact `8584f080` patch is 2,853 bytes, SHA256
`940e3d49ea755911e5282725263f627b4d070a375838d9bd6f25693dce52362b`.
It contains four single-line substitutions across two test files. All 46
Construction and seven Teardown methods, XCTest expressions, callback order,
render/removal operations and cleanup statements remain in place. Complete
file reconstruction and inverse checks, independent source review, root
strict formatting, contracts and the staged-diff proof cover this source
correction. The other 639 existing test files, production code and Package.swift
are unchanged by the patch. The retained packet and root proof are
`artifacts/goal-ninth-button-fixtures858-intake-v1` and
`artifacts/goal-ninth-button-fixtures858-root-proof-v1.json`.

These source checks do not establish compiler acceptance or passing tests.
The preceding ordinary152 attempt still has zero executed cases; the separate
Table/UIA corrections and fresh combined test execution remain necessary.
No original completion gate is closed by this fixture repair.


### 2026-09-01 preserve clipped visibility and actor callbacks in UIA fixtures

The two UIA fixture files now use contextually actor-isolated forwarding
closures for the same three gapRows calls, instead of converting bound method
values. The five readiness enum assertions remain unchanged; their previous
inference diagnostics are not independently treated as resolved without a
fresh compiler run.

The continuation fixture derives a visible rectangle from its existing
prepaint frame intersected with the existing clip rectangle. These fixtures
use identity transforms and rectangular clipping, so both captured bounds
share coordinates. An absent clip leaves the original frame; an empty
intersection produces zero and fails the original positive-visibility checks.
This is fixture geometry, not a general claim about transformed or curved
visible-pixel bounds and not a new production visibility API.

The oversized row still must measure 180 pixels while exposing 60 pixels,
with the same tolerance, ordering and factory count. All four original
visibility assertions remain. The preceding failure entry described three
references from the three unique compiler locations; the source actually had
four references, including the adjacent less-than assertion at old line 94.
Both local calculations use the already unwrapped prepaint entry and do not
add a query, build, callback, unwrap, or assertion.

The exact frozen `715bab15` patch is 4,644 bytes, SHA256
`14115235fd15b6ffa45ddead07a17f98d4c4c12a9ab0b09e989af38b54bef820`.
It preserves the ordered 70 methods and 628 XCTest expressions across the
two files, apart from the four documented assertion receiver substitutions.
The other 639 existing test files, production sources and Package.swift are
unchanged by this patch. Independent source review, root strict formatting,
contracts and the complete staged-diff proof are retained separately from
execution evidence. The packet and root proof are
`artifacts/goal-ninth-uia-fixtures715-intake-v1` and
`artifacts/goal-ninth-uia-fixtures715-root-proof-v1.json`.
This correction has not yet established a test pass;
fresh combined compilation and the original UIA/public-budget cohorts remain
required, and all nine original goal gates remain open.


### 2026-09-01 bind Table fixture types and leases to their original builds

Three AnyTableColumn expressions now specify the row types already supplied
by their collections, and one TableColumn key path names its existing root
type. Builder bodies, capture lists, identity values, selection bindings and
statement order are unchanged. The four following inference diagnostics do
not justify edits to their unwraps or keyed-identity assertion; those remain
unchanged pending an actual compiler result.

Both fixture leases now implement the required beginBuild method. Each keeps
a weak reference to the real epoch that the fixture already owns and installs.
Its canBuild result follows that original epoch's canAdopt value; it cannot
find a replacement epoch or keep the original alive. beginBuild returns nil
because the manual fixture cannot supply a second build. It neither hands
out the already installed epoch twice nor constructs a synthetic success.
The existing coordinator, adapter, admission, journal and close/abandon/finish
sequence still provide the fixture's real construction and revocation.

The exact `513c38ab` patch changes only two test files, with 26 additions and
eight deletions. It is 5,476 bytes, SHA256
`ebba86a032663d98ea4c3b90fb94cc4ee61cf11d80b3f21f0872c4fe86712abb`.
All 26 methods and 175 complete XCTest expressions in those files remain;
the complete 56-method Table roster also remains unchanged. Independent
source review, complete-file/tree inverses, root strict formatting, contracts
and the staged-diff proof cover the correction. The other 639 existing test
files, production code and Package.swift are unchanged by this patch. Root
extracted the frozen Git diff directly and verified its exact staged bytes;
the proof is `artifacts/goal-ninth-table-fixtures513-root-proof-v1.json`.

This completes the planned six-file fixture repair in source. It does not
convert the previous failed compilation into passing tests. Fresh combined
compilation and the ordinary, Button/Table, UIA and original Core/List
qualification remain required. All nine original completion gates stay open.


### Continuation: preserve the six fixture captures exposed by the next compilation

The same ordinary 152-case selection was attempted at
`084356c15f3cd30177efb06abcfa402a03b633dd`, tree
`0e1f6a08d273c115248916fc19ef308f02e8accc`. The direct child closed naturally
with child/runner exits 1/1 after 89.281 seconds. Compilation reported six
unique actor-capture errors across seven diagnostic headers: five in the
generic Table erasure helper and one in the UIA continuation cancellation
helper. The earlier 25 compiler diagnostics were absent. No XCTest case
started or finished; all 152 selected cases remain unrun at that revision.
This is compiler progress, not passing test evidence.

The retained raw log is 2,423,581 bytes, SHA-256
`f21b1425e2f8c665cad89c03f9d2fb5563c1c2452473264abf33aece7b13543f`, under
`artifacts/ordinary152-084356c-8e326b44ba6b41cc91b75a9f8e8b75b9`.
`goal-ninth-ordinary152-084356c-compile-failure-reconciled-v1.json` records
the diagnostics, zero case outcomes, natural closure and unchanged source/index
endpoints. The separate post-closure census found no matching process or
formatter. That census is a point-in-time observation, not continuous proof
of descendant lifetime.

The follow-up source repair consists of six changed lines in two test files.
Table's synchronous actor closures capture the existing actor-isolated probe
and, where needed, its String label; they no longer capture the generic row or
collection. Generic IDs remain Hashable without a new Sendable constraint.
Recorded events, return values and their order remain identical. The UIA
cancellation closure retains its outer weak capture and adds an explicit inner
weak capture. Its existing actor precondition and immediate cancel, onCancel,
release, clear-before-resume sequence are unchanged. Neither repair adds a
task, actor hop, unsafe conformance, asynchronous cleanup or persistent owner.

Independent source review found no blocker. Exact whole-file forward/inverse
checks preserve the 52 ordered methods and 474 XCTest call sites in these two
files; the other 639 test files, production, Package.swift and all original
budgets remain unchanged. Strict formatting and contracts passed. The combined
canonical patch is 2,617 bytes, SHA-256
`66f9757f46ea4c337fb483d84095cdbb3846d02d7fdd1f680b93f2a4f30febbf`;
`artifacts/goal-ninth-capture-fixtures084-root-proof-v1.json` records its exact
staged source tree. The sealed UIA source packet is retained in
`artifacts/goal-ninth-uia-cancel-b622-intake-v1`.

Compiler acceptance and runtime behavior of these captures still require the
next serial run. This entry changes no completion criterion: all nine original
gates remain open, and the other prepared focused cohorts remain unrun.


### 2026-09-01: Fresh selected cohorts and one native attempt at 525c6e7

All five selected XCTest cohorts below used the same clean commit
`525c6e72148e1cc5fd56fa2f3ab38d911d0ed5f0`, tree
`737feefa5a4685c042ce1fffb19a51ad8d259944`. Each selected method had an
independently reconciled start and terminal result. None skipped a case; each
also recorded the separate zero-test Swift Testing footer. Source and index
endpoints matched. These are focused results, not a full-suite pass.

| Fixed cohort | Passed | Failed | Direct-child result and elapsed time |
| --- | ---: | ---: | --- |
| Ordinary ownership/membership, 152 cases | 135 | 17 | Natural exit 1; 399.719 s |
| Button/Table, 166 cases | 162 | 4 | Natural exit 1; 12.735 s |
| UIA continuation/readers/origins, 122 cases | 104 | 18 | Natural exit 1; 266.234 s |
| Public UIA and realization budgets, 19 cases | 7 | 12 | Natural exit 1; 204.062 s |
| Native dispatch/shutdown/smoke validation, 94 cases | 94 | 0 | Natural exit 0; 6.875 s |

The previous compiler failures remain in this ledger. The 525c6e7 capture
corrections were accepted by this build. All original 132 ordinary cases and
the three bare-empty diagnostics passed. The remaining 17 ordinary failures
throw `candidate` during the shared fixture's unsupported plain-adapter setup;
the reviewed two-line identified-source fixture correction is not yet applied
or executed. All 56 Table cases passed. The four Button failures comprise
three unsupported managed-admission fixture setups and one removal assertion
that conflates the rejected attempt with a later default-budget attempt.
Separate fixture repairs, including a new default-budget removal regression,
remain unexecuted at this checkpoint.

The UIA failures still prevent qualification. Static review correlates several
positive failures with an unchanged provider build invalidating an otherwise
current actual layout pass. Reader construction, original slot resolution,
mounted State, and binding assertions pass in the reader cohort; synchronous
request settlement does not. The reader fixture performs 301 fresh projection
queries when finding row 300; no per-Realize latency was measured. The public
budget diagnostics remain distinct: the default allowance uses four rounds
and reports budget exhaustion; both explicit six- and sixteen-round allowances
use six rounds and complete construction but remain unsettled. No allowance,
assertion, settlement guard, or acceptance criterion was relaxed.

The 94 passing tests permitted a separate, single bounded native attempt on
the same source and index. Its pinned executable was 95,502,848 bytes,
SHA256 `84cfa98e6c757193baa4f8ad1e22e5f6dda7acbeb12584f216fc94a7aab17ed5`.
The incremental focused invocation did not relink that executable; the binding
retains the observed successful build inputs and existing PE bytes without
claiming a new link or loaded-DLL attestation. All 135 explicit DLL input pins
were preserved during the attempt.

The actual native attempt failed: 24 of 27 predicates passed. Thread separation
now passes. `actor-progress-between-backlogged-turns`,
`backlogged-32-record-turn-and-continuation`, and
`three-second-unforced-settled-idle` failed. The validator reports insufficient
fairness exercise; the idle failure requires separate trace diagnosis. The
native child and controller exited 1 naturally after 11.25 seconds, with no
timeout, termination attempt, fixture failure, or source/input change. The
original controller's cleanup-required flag remains recorded, not rewritten.
A later CIM observation found no matching child/toolchain process or formatter;
this is a point observation, not continuous descendant attestation. No retry,
larger workload, added delay, or predicate relaxation is authorized by this
failed result.

Evidence is retained under `artifacts/`: the five
`goal-ninth-*-525c6e7-reconciled-v1.json` records and corresponding closure
records; `goal-ninth-native94-525c6e7-binding-v1.json` and build association;
and `goal-ninth-native-smoke-525c6e7-failed-reconciled-v1.json`. The native
attempt directory is
`goal-ninth-native-owned-smoke-11744293cdab4997ad57001b701add15`; its 2,812-record,
652,011-byte trace has SHA256
`44f6c44f4a5777034b49de91e01af6b44e5a0917c980ee461c7ec61bff14a680`.
The independent native reconciliation is 3,813 bytes, SHA256
`aaed50755070370d3dc61a9a935919a3b42cc89c2490761ffe9047b13d883aac`.

All nine original completion gates remain open. No current full validation,
visual parity, complete API census, native fairness, hardware, hosted CI,
packaging, or clean-machine release qualification is inferred from these runs.


### 2026-09-01: Authentic Button admission and separate removal retry fixtures

Three test files now carry the reviewed Button fixture repairs from private
sources `063d1ea60eddccc6d26b6e91d7a345c7d0494b97` and
`bea342546a7327c5960d84a4977198cea4ab82c7`. The admission fixture supplies the
real managed descriptor, selected-row build activity, and checked publication
that its existing reconciliation path requires. Its three test bodies,
17 assertions, original Button callbacks, and destructor probe are unchanged.
No authority is replaced after the destructor callout.

The owner-clearing removal fixture now isolates its original rejected attempt
with one round; its other branch retains the default. All 69 original XCTest
calls remain. A separate new regression retains the default 128-element,
four-round allowance and requires a strictly later provider round and layout
pass before the later modifier or retirement can occur. The original physical
attachments must survive the rejection, followed by exactly one valid
disappearance and retired paint in the successor attempt. The next fixed
Button/Table selection is the original 166 methods plus this new method, not
a replacement or reduced selection.

Root formatting and contracts passed. The complete staged source diff matches
the reviewed 19,394-byte patch, SHA256
`ff366eb0fe37c81da17d6b7c705389e23bea243612dc6c6e3b9942a14eefb5b2`;
the staged source tree is `353f09c64ebb5b44b8203b93ab5a1c99cc3875ac`.
The remaining 639 original test files, production, and Package.swift are
unchanged. Source proof and the two imported packets are retained under
`artifacts/goal-ninth-button-fixtures4ae-staged-proof-v1.json`,
`goal-ninth-button-admission063d-intake-v1`, and
`goal-ninth-button-removalbea3-intake-v1`. These repairs have not yet been
compiled or run; the earlier four failures remain the actual result.

Correction to the preceding 525c6e7 budget description: the explicit allowances
are EIGHT and sixteen rounds, as fixed in
`ManagedListUIARealizationBudgetTests.swift:17` and `:21`. Both runs consumed
six rounds. Six was the observed consumption, not the first configured
allowance. This clarification changes neither source nor test expectations.
All nine original completion gates remain open.


### 2026-09-01: Original lazy-list identities before row construction

The reviewed empty-membership fixture correction now supplies the identified
source prefix already used by its managed descriptor. The original empty-row
factory callback is unchanged. This addresses the shared setup failure before
the 17 membership tests reached their assertions; all 17 methods, 128 assertions,
and 20 unwrap calls remain intact.

Two insertion-origin fixtures now obtain their original source tokens after
descriptor introduction and before the first factory. Lookup inside a running
factory is correctly unavailable. Only native token values cross that boundary;
the insertion event lookup, capture, claim/expiry, and all assertions still run
inside the original row-zero callback. The other eight insertion-origin methods
and existing adapter-token helper are unchanged. This does not repair the
separate request-settlement or cancelled-source failures.

Root strict formatting and contracts passed for both files. The complete
4,889-byte staged diff has SHA256
`31a3ea88ed470357b284415cca67ddc10c487bf93f911fc5fe4c3373f63a61ed`,
and source tree `1e166fea8a24b6b667bdbf869631a987c695208b`. All other
640 current test files, production, and Package.swift are unchanged. Root proof
is `artifacts/goal-ninth-list-fixtures1a96-staged-proof-v1.json`; source packets
are `goal-ninth-empty-membership7989-intake-v1` and
`goal-ninth-uia-insertion4dd1-intake-v1`. No compiler or XCTest has yet validated
these changes. The original selected methods remain required, and all nine
completion gates remain open.


### 2026-09-01: Preserve an actual UIA target pass and stop known-empty work

Runtime now tries its existing strict target-pass certificate after the normal
measurement and reader phases, before entering another provider build, only
for an unchanged target query. This prevents a redundant unchanged build from
invalidating an already usable actual pass. The same round remains charged;
all currentness, reader, callback, probe-retirement, other-list, and measured
geometry checks still govern capture. A refused certificate falls through to
the original provider path. Final queries and ordinary phase ordering are
unchanged.

A separate loop-top check stops an exact current target query when that same
adapter/token has accepted a native zero-leaf result. It marks only the original
preparation inactive. It does not manufacture visible roots or settlement, and
it leaves the ordinary query epilogues and request cleanup in place. Keeping
the typed preparation installed prevents an epilogue from rebuilding the
failed demand through an ordinary path. Unknown or stale targets do not match.

The source change is exactly 18 added Runtime lines, matching the reviewed
2,007-byte patch, SHA256
`1eba47ad70224f35cb1995eeab6409b35d307ecbff7a6191504c3d9908f4b944`.
Root strict formatting and contracts passed; source tree is
`7b9c150c55bf8cf475f8b09631df74ed16035dd1`. All 642 current test files and
Package.swift are unchanged. The packet and root proof are
`artifacts/goal-ninth-uia-target9f0-intake-v1` and
`goal-ninth-uia-target65eb-staged-proof-v1.json`. No compiler or XCTest has
validated these changes yet. The separate initial-query measurement correction
and unused-phase proposal is not included or implicitly approved. Existing
four/eight/sixteen-round expectations remain required. All nine completion
gates remain open.


### 2026-09-01: Keep only accepted original ordinary ownership plans

Ordinary descriptor-owned publication now retains the exact original plans
that were actually accepted. A rejected sibling cannot erase an accepted
component or leave rejected ownership attached. This path is restricted to a
successfully prepared ordinary adoption whose frozen and current owned metadata
contain no managed or lazy regions. The original source roster is materialized
and that domain is checked before the first accepted fact. If the domain no
longer qualifies, the original strict route remains available only before any
new accepted fact; there is no fallback after partial publication.

Property, insertion, completion, and declared-structure consumers filter their
original permission and presence arrays by those successful plan identities,
preserving original order and duplicates. Empty successful results still run
the existing outgoing retirement and revision work. The three original
preparation checks, managed/lazy-region routines, queued-region behavior, and
original native owner/slot identities remain unchanged. This is a correction
to bounded ordinary metadata publication, not a claim about every visual
subtree under a managed ancestor or arbitrary later ARC reentry.

Eight new regression methods cover 20 designed scenario iterations, including
nil-controller host closure, accepted-field retirement, suspended continuation,
original native-lifetime closure, stale declared revisions, and mixed accepted
and rejected siblings. The original 152-case ordinary cohort remains required
alongside these eight additions. All 642 previously tracked test files remain
unchanged by this source correction.

Root contracts and strict formatting passed. The complete staged diff matches
the reviewed 73,169-byte patch, SHA256
`0cd7e2a9414a8237c847a707183150e2d00d4b33f49b22280cd8fb6874b6fd93`;
source tree is `3e34e7dfc267fed586c7cd9c14178adefb23dd7a`.
`artifacts/goal-ninth-ordinary-regionless3472-intake-v1` preserves the projected
packet and original reviews; `goal-ninth-ordinary-regionlessc812-staged-proof-v1.json`
records exact staged reproduction. The projection preserves the existing
package-visible immutable attempt identity. No compiler, runtime test, public
facade, performance, or native result is claimed here. All nine original
completion gates remain open.


### 2026-09-01: Execute the ordinary, Button, and UIA corrections together

Four serial focused runs completed on clean commit
`c3407897d2fc56ff556fb5a376c059b27aa947ba`, tree
`422d421d1f971aa0b82b9bdba24dbcf621b22e72`. Every selected XCTest started;
there were no skips. Each run ended naturally with child/controller exit 1/1,
without a timeout or termination. Independent source/index endpoint comparisons
passed. Separate post-closure CIM snapshots found no matching child processes;
these are point observations, not continuous descendant attestation.

| Selected cohort | Passed | Failed | Result and remaining boundary |
| --- | ---: | ---: | --- |
| Ordinary ownership and membership, 160 cases | 159 | 1 | All eight new ownership methods passed. One stale-reservation fixture still throws `candidate` before its assertions. |
| Button and Table, 167 cases | 164 | 3 | All 56 Table cases and all seven removal cases passed. The three final-admission fixtures now stop at an ambiguous `noAdmission` setup guard. |
| Internal UIA, 122 cases | 115 | 7 | All 40 continuation, 30 construction-hint, three reader/Button, and 22 scroll-geometry cases passed. Two insertion-origin, two unused-provider, and three managed-reader cases still fail. |
| Public UIA and shared budget, 19 cases | 7 | 12 | The same three managed-budget and nine public-accessibility cases still fail. |

The two original-token fixture corrections now pass. The target-pass and
known-empty changes are exercised by the complete continuation cohort, not
just source review. This does not establish managed-row settlement. The public
default four-round case still consumes ten elements and all four rounds while
unsettled. Explicit allowances of eight and sixteen both consume six rounds
and sixteen elements and report complete work but unsettled presentation.
The separate original one-element/one-round rejection case still passes.
Existing budget limits, test expectations, and public completion requirements
remain unchanged.

The four retained runs are `artifacts/ordinary160-c340789-65449a3cab294994b1a36a07230c3e72`,
`button-table167-c340789-45d1390311c148398a4f3d7e6c15eecb`,
`uia122-c340789-fdd4b01e94634c8fb6776f2a9932310d`, and
`uia-public19-c340789-98d6791687864c23ab373de471a3dde0`.
Their complete case identities, failures, durations, raw-log hashes, and source
comparisons are in `artifacts/goal-ninth-ordinary160-c340789-reconciled-v1.json`,
`goal-ninth-button-table167-c340789-reconciled-v1.json`,
`goal-ninth-uia122-c340789-reconciled-v1.json`, and
`goal-ninth-uia-public19-c340789-reconciled-v1.json`, with matching
`post-closure-v1.json` receipts. These are focused results only. No new Full,
native-window, visual, hardware, macOS, CI, or release qualification is claimed.
All nine original completion gates remain open.


### 2026-09-01: Distinguish Button setup refusal and rebuild empty-row reservations

The final-admission Button fixture now reports a different error for each of
its 11 existing setup conditions. Split guards retain the same once-only,
left-to-right evaluation and first-failure exit. No authority read, callback,
proof, candidate, destructor probe, or production code changes. All three test
bodies and their 17 assertions remain identical. The actual failing guard is
still unknown; this is diagnostic preparation, not a claimed behavior fix.

The empty-membership fixture now assigns each explicit attempt a fresh content
revision before build/admission capture, using the same revision in its viewport
context. This requests an actual second content build instead of reusing an
unchanged accepted record. It intentionally invalidates the prior layout stamp
but keeps the logical membership, original provider generation, physical empty
receipt, descriptor binding, and attachment. No cache clear, record release, or
weaker stale-reservation check was added. All 17 methods, 128 assertions, and
20 test unwrap calls remain unchanged.

Root strict formatting and contracts passed. The two-file staged patch is
8,325 bytes, SHA256 `38d12a78b39e68ce82d60eec98fe434e917a132f54cfb05d43a8fa221a2345bb`;
source tree is `32363b99c310852ffc4ced03c0acfd113252fe23`.
`artifacts/goal-ninth-fixtures8273-staged-proof-v1.json` records exact reproduction
and preservation of the other 641 existing test files, all production, and
Package.swift. The reviewed packets are `goal-ninth-button-admission3521-diagnostic-intake-v1`
and `goal-ninth-empty-membership3575-intake-v1`. Execution of the original
20 affected cases is still required. All nine completion gates remain open.


### 2026-09-01: Execute fresh reservations and locate the Button setup failure

On clean `496428cb7b248a00a640dfe7500e46e8af18b3f0`, all 17 membership
cases passed, including the original stale-reservation case. The three Button
cases all failed with the new specific `descriptorCopyPreparation` error before
their assertions. The focused 20-case run had 17 passes, three failures, no
skips, and natural child/controller exit 1/1 after 236.922 seconds. Source/index
endpoints matched; post-closure CIM found no matching process at that instant.
The descriptor-copy setup still needs a causal repair, not a weaker admission.

Evidence is `artifacts/fixture20-496428c-38b29c5b318149bd848321762ae098ef`,
`goal-ninth-fixture20-496428c-reconciled-v1.json`, and the matching closure
receipt. Supplementary source-span checks initially used incorrect annotation
and newline boundaries. The corrected independent comparison matches every
original byte through both test-class prefixes and all 20 original identifiers
and async classifications. It completed during the frozen-source run, not
before launch; `goal-ninth-fixture20-496428c-derivation-proof-v4.json` retains
that timing and the failed checks. No source, selection, or runner changed.


### 2026-09-01: Preserve accepted list sources when row construction is cancelled

Deferred list projection now distinguishes an interrupted finite construction
attempt from proven source invalidity. A cancelled factory, collection access,
or aggregate validation rejects its output without revoking an unchanged
accepted source generation. Genuine count, index, ordinal, key, or validator
failure is latched at the original proof point while current, before temporary
cleanup can cancel the surrounding attempt. No partial eager cache is published.

Binding-backed validation follows the same distinction. It keeps its original
getter and currentness checks; only a complete current scan proving a captured
key/occurrence absent revokes its generation. Unequal keys remain normal search
results, and ambiguous cancellation does not become source invalidity. Escaped
binding getter/setter and lifetime semantics remain unchanged. There is no new
authority capture, callback, retry, source-close policy, or Runtime/UIA guard.

Four new methods cover eight direct-List/builder cases: cancellation in a row
factory, collection access, or binding getter preserves the original accepted
source; genuine missing binding keys stay invalid even after restoration.
They use actual entered admissions and one explicit layout per case. Key-getter
and proof-followed-by-cleanup cancellation remain source-reviewed boundaries
without dedicated new execution fixtures; no universal coverage is claimed.

Root strict formatting and contracts passed. The three-file patch is 35,159
bytes, SHA256 `4a3ed434d4af66a41bda938716b686e2ad0f33014fa60f2235369a2ad1a16f45`,
with source tree `ef2962b1314f7bb2d2f0ba3571f5b2865a9bb1c0`.
`artifacts/goal-ninth-projection-binding496-staged-proof-v1.json` verifies exact
reproduction and preservation of all 643 existing test files and Package.swift.
The generic and binding packets remain separate in
`goal-ninth-projection-cancellation85bae-intake-v1` and
`goal-ninth-projection-binding-d857-intake-v1`. The four new methods and existing
projection/binding/UIA regressions still require root execution. All nine
original completion gates remain open.


### 2026-09-01: Add bounded construction diagnostics for the unresolved FileBrowser run

The retained runtime and component host now have an opt-in construction trace.
With its environment variable absent or empty, no writer or XCTest observer
is created. An explicitly configured writer opens only an existing empty local
file without creating, truncating, or replacing it. The diagnostic controller
must supply an exclusively created file inside its fresh attempt directory.
The trace holds native scalar IDs and runtime birth tokens, not view payloads,
current-case ownership, admission, or a new source of authority.

Complete newline records are written synchronously under a lock. The 64 MiB
cap reserves space for an explicit PARTIAL terminal record; an actual write
error is sticky and does not invent completion or retry. Readers must tolerate
an incomplete final write. This is not an atomic-write, durable-flush, timing,
or hardware-performance guarantee. Default-off tracing does not excuse later
behavior or performance validation.

The FileBrowser observer records actual XCTest start/finish callbacks and
explicit fixture associations. Runtime layout, reader and component boundaries
can identify where a stopped run was active. A callback-finish event is not an
XCTest pass. All 14 original method bodies, assertions, order, and the original
900-second attempt limit remain unchanged. The earlier timed-out attempt still
has 14 unknown individual outcomes and is not retrospectively reclassified.

Eleven writer regressions cover configuration, visible writes before close,
rejected files, bounded-cap and rejected-record behavior, a closed-handle write
failure, escaped case metadata, and distinct runtime births. Small-cap and
closed-handle tests do not claim actual 64 MiB saturation or every OS IO fault.
Root must execute these and a small visibility smoke before deciding on one
instrumented FileBrowser attempt. No retry or new timeout is approved here.

Root contracts and strict formatting passed. The five-file patch is 40,943
bytes, SHA256 `0b4a6c2ddcf603a516af52049db4e9421ac1baa9a669432bb795d4ace2cf07ba`;
source tree is `438632ca89fb24b7ee0a9965ca34b05df6d18752`.
`artifacts/goal-ninth-file14-bf7-source-composition-proof-v1.json` independently
confirms that only five Git/index or hunk-start metadata lines differ from the
previously reviewed patch and all five approved postimages match. The staged
proof `goal-ninth-file14-bf7-staged-proof-v1.json` preserves 644 of the 645
existing test files, with only the approved FileBrowser instrumentation in the
remaining file. The 18 earlier Runtime corrections remain intact. Compiler,
writer, visibility, FileBrowser, and release qualification are still pending.
All nine original completion gates remain open.


### 2026-09-01: Reuse the original descriptor binding in Button admission setup

The observed `descriptorCopyPreparation` failure has a concrete source cause:
`proposal.nativeBinding` constructs a new object on each access. The fixture
installed one object in the adapter and registered a different object in the
journal. Their equal descriptor IDs did not satisfy the required binding
identity check. The fixture now captures the binding at its original first
access and reuses it for both operations, matching the production list path.

Only three lines were added and two removed. All three test bodies, 17
assertions, destructor probes, callbacks, and production admission rules remain
unchanged. No authority is refreshed or replaced. Root strict formatting and
contracts passed; the 1,564-byte patch has SHA256
`6d3843a5ecb828e7a9c3a56d6ca184fa6af4d29797b43ae3ef0bce7d8cc44357`.
Source tree `05dddc9db945ef0f9dd8bb50d0308819d13957a5` and preservation of
the other 645 existing test files are recorded in
`artifacts/goal-ninth-button-bindingc6d-staged-proof-v1.json`. The original
three cases still require execution. All nine completion gates remain open.


### Original completion gates after the 2026-09-01 focused runs

All nine original completion gates remain open. This map adds no requirement,
exception, or substitute for their existing acceptance criteria.

The four focused runs on clean `c340789` on 2026-09-01 passed 159 of 160
ordinary ownership cases, 164 of 167 Button/Table cases, 115 of 122 internal
UIA cases, and seven of 19 public UIA/budget cases. The remaining failures
number one, three, seven, and twelve respectively; none of these selections
skipped a test. These results qualify only their recorded source and methods.
Later fixture or production changes require their own execution evidence.

The later `496428c` focused run passed all 17 membership cases and located
three Button setup failures at descriptor-copy preparation. The subsequent
binding-identity fixture repair, source-cancellation changes and construction
diagnostics still await execution. These newer changes do not inherit a Full
or release qualification from the dated cohort results above.

| Original gate | Remaining implementation and evidence |
| --- | --- |
| 1. Full pinned desktop API and behavior | Complete public declaration, extension and overlay review, Windows implementation mapping, and behavioral conformance for the fixed baseline. The captured inventory and passing synthetic audit tools are inputs, not a completed census. In-scope partial implementations, shims and placeholders remain gaps; no implicit platform exception is permitted. |
| 2. Relevant semantic, interaction, accessibility and visual coverage | Correct the remaining ownership, construction and UIA failures; complete the FileBrowser interaction diagnosis and fixed Core/List regressions. Map every in-scope feature and applicable state to coverage, then validate the integrated source. A pass across existing tests alone cannot establish coverage of missing features. |
| 3. Shared Windows/macOS reference apps | Build and exercise the same reference sources at the candidate revision on both platforms, with reviewed behavior and render comparisons that state font, theme and platform differences. Earlier macOS build or SDK-export success does not qualify current behavior. |
| 4. CPU/D3D11 scene agreement | Verify current effects, groups, mixed order, transparency, clipping and fractional DPI through CPU rendering and actual D3D11 execution/readback. Historical passes and a material skip do not qualify changed source or excuse an in-scope gap. Keep fallback limitations and measured tolerances explicit. |
| 5. Motion targets and bounded resources | Finish interruption, scrolling, long-session collection/navigation/window lifetime and idle-work checks. Publish rendered motion and controlled hardware evidence against the unchanged section 4 targets, including native input-to-present latency and all required workload and percentile fields. Unit-test timing and virtual-display diagnostics do not qualify hardware pacing. |
| 6. All eight template workflows | Complete the advertised model, persistence, loading/failure/retry/cancellation and interaction paths for every template. Native document activation/close decisions, the complete media/file workflow, and the remaining chart, navigation and animation-lab behavior still need integration and proof. Exercise keyboard, pointer and assistive technology; static previews are not complete workflows. |
| 7. Real-machine native smoke | Resolve the failed fairness/idle predicates from the 24-of-27 native attempt at `525c6e7`. Separately record GPU recovery, software fallback, monitor/DPI changes, IME, native dialogs and Narrator flows. The hidden-window workload and normal renderer health do not establish those results. |
| 8. Exact release commit in hosted CI | Pass contracts, lint, serial tests/builds and reviewed visual gates on the candidate commit, then retain successful hosted results for that exact revision. The older local Full and earlier hosted failures remain historical evidence; focused runs do not replace this gate. Keep manual and timing qualification separate. |
| 9. Clean-machine delivery | Complete the versioned sample package, runtime/resource dependencies, installation/build/deployment instructions and compatibility notes. Record a clean Windows machine or VM installing, building and deploying the sample without the original development tree. A fresh checkout alone is insufficient. |

Local implementation, failure diagnosis and coverage work can proceed while
preparing the separate pinned-macOS, controlled-hardware, native, hosted-CI
and clean-machine evidence. A versioned subset release does not close the
full goal, and no gate is marked complete by this status map.

The release checklist now distinguishes development checks from full goal
qualification: a fresh checkout does not replace clean-machine installation,
and normal renderer health does not replace required recovery evidence. The
original goal is unchanged; these wording fixes remove possible weaker
interpretations rather than adding a new requirement. The reviewed packet is
`artifacts/goal-ninth-release-checklist496-intake-v1`. No runtime or release
result is claimed for these documentation changes.


### Ninth integration: executed cancellation, membership, Button and trace-writer checks

The combined fixed 61-case cohort ran on `1c28ccfa91b2862418398107e2a778aea6cda3c1`
(tree `1abd13ef9a5cb1cd7f07a4189397eed60bd8c9a9`). It compiled and executed all
61 selected XCTest methods: **60 passed, one failed, zero skipped**. This is
focused evidence only; none of the nine original completion gates is closed.

- Both new ordinary-projection cancellation methods and both new binding-backed
  cancellation methods passed. All 26 original projection, binding and admission
  methods in their three existing files also passed. The accepted source now
  survives the tested finite-construction cancellation cases, while the separate
  missing-source tests still require rejection.
- All nine accepted-membership and eight mounted-empty-row publication methods
  passed again. Their previous fresh-reservation fixture repair is exercised here
  with the cancellation and diagnostic changes integrated.
- The shared descriptor-binding fixture repair allowed all three Button admission
  methods to reach their assertions. Two passed. The remaining method,
  `testRejectedSourceDestructorSealsJournalBeforeNewButtonAcceptance`, failed its
  existing `XCTAssertTrue` at line 34. This is no longer the earlier descriptor-copy
  setup exception. Its destructor-cleanup ordering still needs diagnosis; the
  assertion and production identity guards have not been weakened.
- All eleven new trace-writer methods passed, including visibility of complete
  records before writer close, bounded output, rejection and failure handling.
  This does not establish the separate small visibility smoke or execute any of
  the fourteen FileBrowser interaction methods. Their prior timeout remains
  unresolved until the bounded diagnostic attempt has actual evidence.

The root runner and its original child both exited naturally with code 1 after
465.985 seconds, without timeout or termination. Source/index endpoints were
independently compared. The post-closure CIM snapshot found no matching workload
or formatter processes; it is a point-in-time observation, not continuous
descendant attestation. The raw log contains 3,611,404 bytes, SHA-256
`a6b1a5514b0489c130aa9b29c3162a2113a07fa05102ffa6c20cd5070252f1b0`.
The reconciliation is
`artifacts/goal-ninth-projection-writer61-1c28ccf-reconciled-v1.json`; the separate
closure receipt has the corresponding `-post-closure-v1.json` name.

The earlier derivation proof's field
`original26ProjectionBindingTestFilesByteIdentical` names its unit incorrectly:
the check compared **26 methods in three files**, not 26 files. The actual file
roster and byte comparisons are unchanged; this clarification does not rewrite
that frozen receipt. No full-suite, native-window, gallery, hardware, hosted-CI,
clean-machine delivery or complete SwiftUI compatibility pass is inferred.


### Ninth integration: initial measurement correction and bounded FileBrowser diagnosis

The reviewed initial accessibility measurement correction is integrated on top
of `3a704bf518cb37220865c761d69bee95d289e437`. It moves one already-owed layout
pass before an unentered reader/provider phase within the same paid preparation
round. It does not add a round, retry, measurement, debit refund or larger budget.
The original preparation, sequence, actual-tree completion and weak native input
witnesses must still be current; stale evidence cannot authorize the remaining
phase. Ineligible preparations keep their existing path, and an unsaved fallback
may still require its ordinary later pass.

Fourteen new methods cover quiet/default-four correction, restored inputs,
late reader bodies, expired leases, paint changes, checked work exhaustion,
queued work, changed output slots, multiple lists and necessary fallback passes.
All 646 existing test files, Package.swift and the prior goal text were preserved.
The staged three-file source proof is
`artifacts/goal-ninth-uia-measurement-root-staged-proof-v1.json`. Strict lint on
both changed Swift files and architecture contracts passed. These are source
checks, not an executed correction result: the original accessibility failures,
the new fourteen methods and the wider Core/List cohorts still need fresh runs.

Before this source change, a separate unchanged eleven-method trace-writer smoke
ran on `3a704bf` and passed all eleven cases, with zero failures or skips, in a
natural 5.610-second process run. It exercises independent-handle visibility
before writer close, not cross-process durability. Its reconciliation is
`artifacts/goal-ninth-writer11-smoke-3a704bf-reconciled-v1.json`.

The subsequent original fourteen-method FileBrowser diagnostic on that same
commit reached its unchanged 900-second deadline. The runner reported timeout
124; its outer command and terminated direct wrapper reported 1. The raw XCTest
log remained 249 bytes and reported no individual outcomes, so all fourteen
outcomes remain unknown. Trace callbacks show progress but are not XCTest passes
or proof of a deadlock. The run is
`artifacts/file14-diagnostic-3a704bf-6618adc990174956a03de16200cc0e3b`.
Root then verified all six recorded process creation identities, terminated only
the retained test-process handle, and observed all six closed. A later CIM census
found none of those PIDs or observed descendants; it is a point-in-time check.
The cleanup and census receipts are
`artifacts/goal-ninth-file14-3a704bf-owned-process-closure-v1.json` and
`artifacts/goal-ninth-file14-3a704bf-post-closure-all-recorded-v1.json`.
No longer timeout, smaller fixture, retry or passing FileBrowser result is
introduced. All nine original completion gates remain open.


### Ninth integration: observe both sides of rejected Button cleanup

The remaining Button admission fixture failure is corrected at its actual
observation boundary. Sealing the journal inside the original destructor callback
does not itself retire the incoming Button owner, so the fixture now records and
asserts current admission immediately after that seal. Rejected final acceptance
then retires the owner; a new assertion requires admission to be false afterward.
The previous post-cleanup true expectation contradicted the same test's existing
retired-owner expectation. No production guard, authority, callback or retry was
changed. All seventeen existing assertions remain, with the true assertion moved
to its intended boundary, and the final false assertion is additional.

The one-file patch is recorded in
`artifacts/goal-ninth-button-boundary-root-staged-proof-v1.json`. Both other
methods and all 646 other existing test files remain byte-identical. Strict lint
and architecture contracts passed; the repaired test and full 167-case Button
selection have not yet executed on the integrated source. The earlier failure
remains a recorded result, not a retroactive pass. All nine goal gates stay open.


### Ninth integration: classify native dispatch targets without exemptions

Native smoke dispatch and return records now carry the same pre-dispatch scalar
classification when observation is enabled: nil/thread target, control window,
registered recorded window, or unmatched non-null handle. The classification
uses only recorded handles and is captured before native dispatch; no owner is
retained across dispatch and no native ownership query is added. It identifies
a target category, not a sender, caret/timer cause or ownership authority.
Existing message, flags and their original evaluation positions are preserved.
The extra window scan and record bytes are not claimed to be timing-neutral.

Seven new tests cover all classifier inputs and categories, both dispatch wire
shapes, omitted metadata and unchanged predicate results with each category.
The original 94 selected native methods remain selected, giving 101 for the next
portable run. The existing validation file's entire 29,241-byte committed prefix
is unchanged; three methods are appended and four are in a new file. Root strict
lint on all four Swift files and architecture contracts passed. Source and prefix
proofs are `artifacts/goal-ninth-native-message-target-root-staged-proof-v1.json`
and its corresponding `-test-prefix-proof-v1.json` receipt.

The prior real native result remains 24 of 27 predicates passed, with fairness
and settled-idle failures unresolved. No predicate, schema vocabulary, workload,
query position, budget, timeout, record cap or idle exemption changes here.
A fresh exact-source 101-case run and its closure/provenance checks are required
before a new native binding; the old 94-case receipt cannot be reused. This source
change is diagnostic, not a native fairness fix or a qualifying native pass.
All nine original completion gates remain open.


### Ninth integration: fresh focused and native evidence on 922ff21

The integrated source at `922ff21` completed the original 167-case Button/Table
selection with **167 passed, zero failed and zero skipped**. The three admission
checks now observe both sides of cleanup correctly; the original removal cases
and the separate later-round retry regression also pass. This is fresh execution
evidence, not a reinterpretation of earlier failing runs. The natural process
run lasted 15.219 seconds, with unchanged source/index endpoints; reconciliation
is `artifacts/goal-ninth-button167-922ff21-reconciled-v1.json`.

The same source completed all 155 accessibility cases: **135 passed, 20 failed,
zero skipped**, in a natural 543.984-second run. Of the original 141 methods,
124 now pass and 17 fail, improving two previous failures. The fourteen added
measurement checks contribute eleven passes and three failures. Their phase
observations confirm the intended saved/resumed second round in the two positive
cases, but final realization and settlement still fail. The third new failure
shows that the intended unchanged-provider setup actually admits optional
prefetch; that premise needs correction without suppressing legitimate provider
work or weakening its pass/debit assertions. Managed final settlement, public
anchor correction, successor ownership and actual visible-row receipts remain
unresolved. No allowance, retry or guard is relaxed by this result. The receipt
is `artifacts/goal-ninth-uia155-922ff21-reconciled-v1.json`.

The existing eight builder classes completed **72 passed, six failed and zero
skipped**, with all 78 methods executed in a natural 9.547-second run. The fourteen
public builder methods pass; failures concern mounted optional/conditional/
iteration updates, a re-erased inactive array, and projected List tags/state.
`View.body` already inherits `@ViewBuilder`, so the compatibility table's claim
that it does not is corrected while these behavioral failures and Foundation
geometry limits remain explicit. The source-method lexer had refused nested
quoted interpolation before any test launch. It was not loosened: a separate
runner derivative used the exact generated registration roster, corroborated
against eight current source hashes and declarations, and changed only the two
original filter literals. Its 900-second deadline and other wrapper bytes were
preserved. The observed incremental-build association is not a sealed compiler
input or loader attestation. Actual outcomes are recorded in
`artifacts/goal-ninth-builder78-922ff21-reconciled-v1.json`.

All **101 native unit cases passed**, including the unchanged original 94 and
seven new message-target cases, with zero failures or skips in a natural
394.281-second process run. Exact case IDs, compile association and source
preservation were checked before creating one fresh native binding. The real
64-probe/query-31 smoke then again passed **24 of the unchanged 27 predicates**.
Its natural 11.25-second run still fails the backlogged 32-record turn, progress
between backlogged turns, and three-second unforced settled-idle checks. The new
scalar associates all six idle dispatch/return pairs with a registered recorded
window; it identifies neither sender nor timer/caret cause. The 64 probes were
automatic FIFO deliveries, with no synchronous probe flush this time, yet the
maximum beginning actor queue was seven and maximum consumed turn was seven.
Thus removing query-flush consumption as an explanation does not supply the
missing backlog evidence. No message exemption or workload/predicate change is
introduced. Receipts are `artifacts/goal-ninth-native101-922ff21-reconciled-v1.json`
and `artifacts/goal-ninth-native-owned-e6726ed-reconciled-v1.json`; the bounded
comparison is `artifacts/goal-ninth-native922-vs525-readonly-review-intake-v1/REPORT.md`.

After the earlier FileBrowser timeout and verified cleanup on `3a704bf`, the
final trace contains 648 complete records in 71,353 bytes. Its 34 records beyond
the timeout snapshot include the previously outstanding content return. All
seventeen content spans are paired; the last adoption entry is unmatched. Four
test callbacks have entry/exit observations, one has only entry, and nine have
none, but **all fourteen XCTest outcomes remain unknown**. There are no marker
timestamps or internal adoption boundaries to establish cost, deadlock or a
source fault. Final parsing and source/closure reconciliation are retained in
`artifacts/goal-ninth-file14-3a704bf-timeout-reconciled-v1.json`.

Each completed run had a separate subsequent CIM absence observation before the
next workload or source edit; these are point-in-time checks, not continuous
descendant attestations. The native failure receipt's original cleanup-required
flag remains unchanged alongside the later closure evidence. There is no fresh
Full/gallery, hardware-motion, native-workflow, hosted-CI or clean-machine
qualification in these focused results. All nine original completion gates stay
open, and the original product scope and numerical targets remain unchanged.


### Ninth integration: compare Button child order without temporary ID arrays

Each existing Button adoption witness now compares child counts and ordered
object identities directly instead of allocating a mapped identity array for
every validation. The same attachment, identity, owner, retirement and phase
checks remain at their original boundaries; no result is cached or reused, and
no validation or cohort member is removed. Authorized child-table writes still
advance only their named original obligation, and rejection remains permanent.

Three new tests compare the actual witness against the previous array-equality
oracle for unchanged, reordered, inserted, removed and replaced children; check
a legitimate recorded child write; and reject an unrelated ancestor-table
mutation. All 648 existing test files and Package.swift remain unchanged. The
complete staged diff matches the reviewed two-file patch in
`artifacts/goal-ninth-button-child-order-root-staged-proof-v1.json`; strict lint
on both Swift files and architecture contracts passed.

This is an allocation reduction established from source, not a measured speedup
or an attribution of the FileBrowser timeout. The wider repeated-cohort scans
still exist. The prior 167 Button/Table passes were on `922ff21`, before this
change. Fresh execution of those cases plus the three new methods, broader
validation and the unresolved FileBrowser workflow remain required. All nine
original completion gates remain open.


### Ninth integration: Button validation result and bounded UIA rejection evidence

The exact `ff823af279bcf83a104e69aab63624704c257dfe` Button/Table attempt
`button170-ff823af-a8f76ba207c446999e3af08e55c5bc30` completed naturally with
**170 passed, zero failed, zero skipped** across all thirteen selected classes.
The original 167 test identities and the three new child-order regressions all
executed. Both wrapper and child exited zero after 307.750 seconds; this includes
build time and is not a measured performance comparison. No timeout or process
termination occurred. The reconciled raw log has 56,303 bytes and SHA256
`fb30ac50bfebf813141dcaa0f8918b3aec95c850356034eb41a3320fd939ee16`.
Source/index endpoints were compared, and a separate post-closure census found
no recorded process remaining. This qualifies that focused cohort only; it does
not resolve the earlier File14 timeout or establish the cause of its cost.

The unchanged-provider UIA fixture previously warmed an 80-point viewport that
still admitted optional rows 3, 4, and 5 during the observed preparation. It
therefore did not establish its stated unchanged-provider premise. Its isolated
warm viewport is now 160 points, followed by explicit checks that six already
measured mounted rows cover the ordinary 80-point prefetch interval, that the
next row begins beyond that interval, and that target 30 remains cold with its
31-point estimate. These checks happen before preparation and tracing; the
observed viewport remains 80 points. All original assertions remain, and the
other thirteen original method bodies are byte-identical. A separate fifteenth
method retains the original setup and requires the additional paid measurement
when optional provider expansion actually occurs. No production prefetch rule,
request allowance, or retry was changed by this fixture correction.

A separate opt-in diagnostic records the existing UIA rejection sites using
fixed site/phase enums and native scalar counters. The environment flag
`SWIFT_WINDOWSUI_DIAGNOSTIC_UIA_REJECTIONS=1` is sampled once. Recording is silent
and disabled by default, bounded to 64 accepted entries per operation, and reset
only after accepted typed preparation. It stores no nodes, callbacks, leases, or
continuation authority and schedules no work. Each accepted entry can emit one
scalar stdout line; output does not influence request results. Forty-one existing
failure branches gained recording calls. The remaining compound leaf predicate
is evaluated once into a Boolean before optional recording, retaining its order
and short-circuit behavior. The original guards and budget rules are unchanged.
Three new pure tests cover disabled behavior, the cap/reset, and transport text.

Root verified the entire diagnostic Runtime inverse after removing only the
recording additions and the single-evaluation Boolean normalization. It also
proved the four integrated files match private `9146bcab` apart from one
format-only line wrap. The complete staged source patch is 36,690 bytes, SHA256
`8752f465559a0342d2d7933b5940285e27581353772c857e47d69a8e7285d185`;
`goal-ninth-uia-diagnostic-root-staged-proof-v1.json` records the exact tree and
649 original test files, of which only the approved fixture file changed.
Strict lint and architecture contracts pass after that wrap. This entry records
source review, not a compiled or passing UIA result. The focused diagnostic
attempt, final-query optional-prefetch policy, anchor correction, and larger-
allowance settlement diagnosis remain outstanding. All nine original goal gates
remain open and unchanged.


### Ninth integration: typed List tags and the observed UIA final visibility boundary

The focused diagnostic attempt at `2c711625f3c43d47af20c49d3f5114bc8324cbdc`
completed naturally: **22 started, 17 passed, five failed, zero skipped**.
The unchanged-provider fixture with its established warm premise and the new
optional-expansion regression both passed, as did all three passive diagnostic
controls. MeasurementCorrection finished 13/15; ManagedListUIARealizationBudget
finished 1/4. All selected identities have individual XCTest outcomes. The
wrapper and child both exited one after 602.875 seconds, including a 436.51-second
build and 160.148 seconds reported by XCTest. There was no timeout or termination.
Source/index endpoints match; the separate point-in-time post-closure census
found no recorded process remaining. The raw log has 3,657,039 bytes, SHA256
`6566ac274110cea267a4a88b12e56aab0c2f05f0b81aeb318f6cd4bd9cec34a1`.
`goal-ninth-uia22-2c71162-reconciled-v1.json` records the exact roster/results.

The default-four quiet/nested/managed failures stop at final-query accepted
measurement capture, with six newly constructed optional rows and no remaining
round. The explicit-eight and sixteen-round failures differ: they finish
measurement in round five, report complete provider work with no unresolved
rows, and reach the final visibility/correction rejection. Their pass 10,
sequence 4, geometry 60, last-unmutated geometry 60, and mutation 42 survive;
no pass-counter or final-query-result rejection is recorded. The strict final
query/currentness/settlement/prepaint/root-membership guard therefore passed in
those cases, but a positive target interaction and another useful correction did
not. This does not establish the target geometry's cause. It rules out treating
the previously hypothesized stale geometry-counter branch as observed evidence.
The diagnostic flag was enabled only for this bounded attempt. No production
prefetch, visibility, budget, or retry change is justified merely by this ledger.

The separate List tag repair carries a declared ID type token from the six
existing data-and-selection initializer routes into deferred materialization.
Each real content leaf receives its element's typed tag before selection chrome;
this includes an explicitly nil selection binding. An already-erased
`AnyHashable` payload is stored under the declared type rather than guessing from
its underlying value. Optional nil IDs remain distinguishable from absent tags.
Unrelated typed tags, data-without-selection forms, builder-authored tags,
factory ordering, and identities keep their existing behavior. Temporary old tag
aliases are released in a separate non-inlined helper before source/admission
validation, so reentrant cleanup cannot authorize stale construction.

Nine new asynchronous tests cover declared AnyHashable/optional IDs, nil
selection, all data-and-selection routes, no-selection/builder controls, and
outgoing tag cleanup before source rejection. The cleanup fixture tests source
invalidation, not a real managed-admission revocation, and external owners can
retain an authored payload beyond this helper. All 650 existing test files are
unchanged. Root's complete staged patch equals the reviewed 21,721-byte patch,
SHA256 `a630134a0df78b53e7df9ba2b0564e4c040699b138990ee2d67bc35cdccabc2a`;
strict lint and contracts pass without a formatting delta. The exact proof is
`goal-ninth-list-typed-tag-root-staged-proof-v1.json`. Compatibility/List docs now
distinguish earlier focused compilation from still-failing runtime behavior.
The nine new tests and the original 78 builder tests must run on this follow-up;
no tag result, other builder-state repair, native conformance, or goal completion
is claimed. All nine original gates remain open.


### Ninth integration: distance-based partial trimming source checkpoint

This checkpoint adds implementations for portable partial path trimming and the
ordinary retained partial-shape route. It preserves every preceding goal byte
and leaves all nine original acceptance gates open. The implementation is a
bounded advance toward the existing shape requirement, not a reduced completion
criterion. Compilation, the new tests, retained visual inspection and native
parity are still pending at this checkpoint.

Portable trimming measures total drawn length across lines, quadratic/cubic
curves, circular arcs and closing edges. Moves do not contribute length or join
separate contours. Partial contours remain open, selected whole closed contours
retain their close command, exact `[0,1]` preserves the original raw elements,
and equal valid fractions are empty. Other selections require ordered finite
fractions in `0...1`. Malformed geometry, lost/nonfinite arithmetic or finite
work exhaustion rejects the entire selection through a typed internal failure;
the public nonthrowing operation returns an empty path, never the original or a
partial accepted prefix. Adaptive subdivision and prefix-length inversion handle
nonuniform-speed collinear curves. Path-length and local endpoint tolerances are
separate and are approximation policies, not universal accuracy guarantees.
The implementation admits at most 65,536 input elements, 131,072 derived
segments, 1,048,576 work steps, depth24 and 56 inverse iterations; arc angles and
sweeps are bounded by `8192*pi`.

The separately reviewed arc boundary correction retains one requested-direction
turn when a nonzero opposed sweep has an exact whole-turn remainder. Equal
original angles remain zero and aligned multiple turns retain their admitted
length. Apple's single clockwise full-turn example supports that one case;
symmetric/multiple-turn policies are not native execution evidence. Existing
raw drawing/containment consumers still disagree on some arc boundaries, and
full-range identity deliberately does not rewrite them. An arc following close
starts a new contour; general line/curve continuation after close remains outside
partial admission.

Retained partial shapes capture only value geometry/fractions, scale the original
unit path to the live border-inset paint size before measuring, and normalize the
trimmed result for a single final placement. Authored path construction does not
run again during layout. Paint metadata/passive erasure remain intact and a
collapsed or rejected selection stores an explicit empty RenderPath to prevent
rectangle fallback. This does not qualify bounds-dependent custom shapes,
literal/nested/inset composition, exact strokeBorder, hit/clip behavior, animated
fractions, arbitrary transforms, gradient/dash/antialiasing fidelity or native
parity. [PathTrimming.md](docs/PathTrimming.md) records these contracts and limits.

Root composed the previously reviewed trim and arc packets, then checked the
entire source diff against their combined private tree. The first strict lint
reported formatting issues; the toolchain formatter subsequently changed only
outside-literal whitespace, one import ordering and eleven optional collection
trailing commas. The independent formatting proof also verifies that Views
outside TrimmedShape, including the earlier List tag repair, is unchanged.
Strict lint on all five changed Swift files and architecture contracts then
passed. `artifacts/goal-ninth-trim3f48-root-format-proof-v2/proof.json` and
`artifacts/goal-ninth-trim3f48-root-formatted-staged-proof-v1.json` bind the
reviewed source, formatting delta, staged tree and unchanged 651 old test files.
The complete formatted source patch is 77,372 bytes, SHA256
`c10b7e3ef632f45d0888993e96a11bc4b75916419061ecf15f251b4c2e55a1b5`.

There are 38 new methods: 26 portable analytic controls and 12 retained
geometry/pixel controls. All require fresh execution. The planned focused shape
selection also preserves the 16 ShapePaintProducer, 10 ShapeFillRule and seven
RetainedLazyListShapeCallback cases: 71 shape cases total. The nine new List tag
cases are an additional separate selection, not shape coverage. No fresh full
suite, gallery, hardware presentation or native-platform result is claimed.


### Ninth integration: first shape and List-tag build failure and fixture repair

The 80-case attempt on `e261998c5997ce6dff6361c70df07ff2447263e8`
closed naturally with child/runner exit1 after 162.563 seconds. Compilation
failed before XCTest began: the new ListImplicitSelectionTagTests omitted the
required ViewBuildContext.invalidateHandler argument at two call sites. All80
selected methods remain not run; no shape or tag test pass/fail is inferred.
The 36 emitted diagnostics repeat those same two source errors. The raw log is
3,739,949 bytes, SHA256
`dd360e92463327811e59c7f9e9294679888a5cf7b0e28573fadf8f8fb4719e0b`.
`artifacts/goal-ninth-shape-tag80-e261998-compile-failure-v1.json` independently
compares the source/index endpoints, exact filter, selected source pins and raw
bytes. The subsequent CIM snapshot found no remaining matching process; it is
a point-in-time check, not continuous descendant attestation. There was no
timeout, process termination or source mutation during the attempt.

The repair adds the required empty invalidation callbacks only to those two
static test contexts, matching the surrounding shape-test fixture convention.
It changes no production code, test method, assertion or selected count. Removing
those two arguments reproduces the entire original test blob exactly; the proof
is `artifacts/goal-ninth-list-tag-context-repair-v1/proof.json`. All other653-era
test paths remain unchanged. Strict lint and architecture contracts pass for the
one changed Swift file. The identical 71 shape plus nine tag selection must run
again on the repaired commit. All nine original goal gates remain open, and no
full-suite, gallery, native or performance qualification is added here.


### Ninth integration: fresh shape and builder outcomes at 7db6b98 (2026-09-02)

The two focused runs below used source commit `7db6b98095209e8fce07490277bfa556e9e6bcbd`, tree `6fe2b126bfa37c9cbd6619e086ef9084e0929709`. They finished naturally with unchanged source/index endpoints. Neither is a whole-suite pass. The original nine acceptance gates remain open, with no weakened requirement, removed case, increased execution budget or baseline replacement.

- **Shape and List-tag cohort: 78 passed, two failed, zero skipped; all 80 methods started.** `shape-tag80-7db6b98-8d3a44e3f4d1469e998b8c0c29bf657f` closed with child/runner exits `1/1` after 328.547 seconds, including a fresh 321.60-second build. The raw log is 2,936,307 bytes, SHA-256 `be1d2c19cdfaf9f79c5e9530a7518ba7fc8df3edb3d9d548451fe1706091e443`. All nine `ListImplicitSelectionTagTests` and all twelve `TrimmedShapeGeometryTests` passed. Portable trimming passed 25/26, shape paint producers 16/16, fill-rule tests 10/10, and retained lazy-list shape callbacks 6/7. The XCTest footer counts four assertion failures in two failed methods, including one unexpected thrown error; it is not four failed methods.
- The retraced quadratic throws `workLimit`. Independent source review and a separately labelled arithmetic model point to fixed halving of subdivision error allowances during prefix inversion: exact monotone sibling subcurves strand unused allowance while a non-dyadic reversal reaches the unchanged depth bound. No Swift repair has yet been applied or executed at this checkpoint. The older Arc adoption test compares a normalized retained path against literal pixel coordinates and initially also ignores the border inset. Its Arc implementation predates those assertions and is unchanged by trimming. A correction requires independent analytic geometry and pixel checks while preserving the existing paint, settlement and attachment assertions; it is not permission to accept current output as the oracle.
- The earlier reconciliation helper refused the portable module's 26 method identifiers because it assumed the CoreLogic module prefix. That refusal was a tooling limitation, not another workload attempt or test failure. The separate `goal-ninth-multimodule-cohort-reconciler-v1/reconcile.py` retains the original source/index/log/closure/order checks and changes only qualified-identifier construction. Its six pure mapping controls passed; duplicate, unknown, missing and wrong-count cases still reject. Its 6,122-byte source hashes to `8ba340edbdeb87e46f0207c10872d0c30a8fb392aa14605ec7b08b3cd8a044d9`. `goal-ninth-shape-tag80-7db6b98-multimodule-reconciled-v1.json` records the actual 80 outcomes. The post-closure census observed no matching processes; it is a point-in-time observation, not continuous descendant attestation.
- **Unchanged builder cohort: 73 passed, five failed, zero skipped; all 78 methods started.** `builder78-7db6b98-ab2426845b5d4a818ba19bac6d75860e` closed with exits `1/1` after 9.968 seconds. Its raw log is 33,579 bytes, SHA-256 `b0e8b6a526562984ee4ee1ffa0e30aef7615bcba45fe44977bedc915d5f684af`. All eight source files remain byte-identical to the earlier fixed 78-case roster. The fresh compiler-discovery copy supplies exactly those async method names; this is observed incremental-build association, not a sealed compiler-input or loader attestation. The runner's only difference from its original donor remains two class-filter literals, with the same 900-second bound. `goal-ninth-builder78-7db6b98-reconciled-v1.json` records outcomes and unchanged source/index endpoints; the separate census observed no matching processes after direct-child closure.
- The previously failing `testDataDrivenListTaggedRowsProjectsTupleBeforeApplyingElementSelectionTags` now passes. Four inactive declaration/state cases still fail in the canonical and legacy-array mounted builders. Separately, `testPrebuiltRawArrayInListTaggedRowsKeepsFollowingMountedStateWhenOptionalDisappears` still displays `41` instead of `42` and leaves six mounted states instead of five. A stale adapter-map explanation remains unproved; bounded diagnostics must identify the failed stage before a behavioral repair. These five failures remain in the original tests and in the completion ledger.

Current compatibility and path-trimming documentation now distinguish these executed outcomes from the earlier source-only checkpoint. Retraced-curve repair, corrected Arc assertions, the remaining builder failures, broader UIA suites, retained gallery inspection, native qualification, the full validation gate and batch push are still outstanding.


### Ninth integration: bounded original measured support for keyed anchors (2026-09-02)

The reviewed `941e0ba0e7ad4a74a6e8285138dfe0b359550cf1` source packet is integrated over `728f75697af460b759bd2714a6064e985f19eb84`. This is an implementation checkpoint, not a new UIA pass. Its purpose is to let an existing managed scroll anchor account for newly measured heights of original mounted predecessors after metadata changes, while retaining the original attempt's authority and finite work limits.

Before the one existing metadata call, the adapter captures weak eligible original row witnesses, bounded by its current mounted-record and mounted-leaf limits. It maps the surviving anchor into the new native token order and selects extra support only if the complete prefix from ordinal zero through the anchor fits within the original witness count and every predecessor belongs to that original set. Missing initial support declines the entire extra prefix, rather than constructing missing rows or accepting a partial predecessor chain. Once selected, an expired witness makes the attempt obsolete; it is never refreshed from successor state. Unselected stale/deleted rows do not poison a complete surviving prefix. The returned metadata generation must still equal the original managed descriptor's source generation when original anchor support was captured.

The selected tokens join the existing transition requirements and measurement path. The same original proofs enter both the carried and actual-row proof maps; no old measured height is reused as fresh geometry. Selecting this support invokes no authored key/hash or row factory. Subsequent row work still uses the existing admission, callback-order checks, cleanup, work debits and limits. Width-cache reuse, nil-anchor handling and the raw adapter path are unchanged. This source does not fix final-query optional prefetch or framed-row visibility, and it does not establish a default four-round success.

`LazyListAnchorSupportTests` adds thirteen async cases for real generic preparation, accepted reorder, native new-order selection, missing/count-bounded support, initial invalidity, selected identity ABA, unselected deletion, weak lifetime, first-factory revocation and cleanup, one-element/one-round exhaustion, nil anchors and raw preparation. The valid-but-mismatched metadata-generation branch is currently source-reviewed, not separately exercised by a runtime test. The helper ABA case is not a claimed metadata-callback integration test.

One existing `PublicLazyListAccessibilityTests` method corrects the successor fixture's timing premise. It retains all seventeen original assertions and first checks the failed query's original callback, current successor, unchanged offset, placeholder, absence of target 300 and action, no successor factories, and the original height 30. Only then does a new ordinary host layout perform the separate successor work, after which the pre-existing successor/height assertions and explicit settled/+40 checks apply. The other fourteen methods in that file are unchanged; all other 652 pre-existing test files are unchanged. No prior failing outcome has been relabelled as passing.

The initial strict formatter check reported one guard-layout issue in the new file. Root formatting changed only that guard's line break and indentation; exact inversion restores every original file byte. The final three-file strict lint and architecture contracts passed. The complete staged source diff is 31,388 bytes, SHA-256 `b3e73ba0bd10d643dbf26707f9be8908a470908b516468ddf6d8c6d6532a5898`, recorded in `goal-ninth-anchor941-root-staged-proof-v1.json`; the original packet and formatting proof remain separate. None of these thirteen new cases has yet compiled or executed on the root source. Fresh focused and broader UIA execution is still required. All original nine goal gates remain open and unchanged.


### Ninth integration: final UIA visibility for framed noninteractive row roots (2026-09-02)

The reviewed `fafd965a288c6ecc27f435c0c009c1f207afdec0` visibility change is integrated over `d844494db75c0c446a031cec9d241b62496ec462`. It replaces only the final row-visibility predicate: the exact original target must occur in current prepaint dispatch nodes and have a strictly positive result from the existing `scrollVisibilityFraction(of:)` helper. A framing root is not required to own a pointer interaction. All preceding original request/currentness, pass, settlement, target and root checks, and all subsequent query accounting remain unchanged.

This addresses the source-supported reason that explicitly funded, settled framed Button rows failed the earlier `.resolveVisibility` check. Dispatch membership alone is insufficient: the existing helper also checks finite positive geometry, physical-surface intersection and ancestor clipping. It does not add general occlusion or improve the helper's rounded-clip semantics. No failure or diagnostic bound was dropped, and no target, source generation or proof is borrowed from a successor.

The new `LazyListUIAFramedRowVisibilityTests` has six async cases: a public framed Button, the exact retained typed request, hidden-target rejection before owned scrolling, a target inside the surface but outside its List clip, a dispatch-present target outside the physical surface, and positive layout dimensions with zero transformed paint area. The latter three negatives establish the original target/mutation/roots, current pass, settled receipt and current prepaint before the rejection; they require one owned scroll and `.resolveVisibility` with remaining rounds/elements. The hidden case deliberately checks the earlier `.resolveTarget` rejection and does not claim final settlement. No extra query after a failure or target action is used to manufacture success.

These fixtures use target 30 of 64 with an explicit 128-element, sixteen-round allowance to isolate geometric visibility. The original default sixteen-element/four-round cases and all other 654 existing test files remain byte-identical. Therefore these new tests, even if they pass, cannot establish the unresolved default-budget behavior. Final-query optional prefetch remains a separate investigation.

Root strict formatting initially identified four assertion line-wrap issues in the new file; formatting changed only their newlines and indentation. A complete byte comparison after those four exact transformations proves all tokens, strings and comments unchanged. Final strict lint of both changed Swift files and architecture checks passed. The formatted staged diff is 20,343 bytes, SHA-256 `11d92b945c226311cc5a42d18c51ecfe1f590997de49e66d8c1ca60255af2254`, in `goal-ninth-uia-visibility-fafd-root-staged-proof-v1.json`. The production Runtime is 1,193,575 bytes, SHA-256 `2b641958f64fc1cf3ddfed32f57b1629c4bc1e09a838064b09de2e9949985336`; the only production delta is the reviewed three-line predicate replacement. Compiler and XCTest execution of this composition have not yet occurred. All nine original goal gates remain open without changed requirements.


### Ninth integration: qualified passive native GUI-thread snapshots (2026-09-02)

The reviewed `8fc20506dc8a1d7d5d712f8043d7c835749a546d` source change is integrated over `5364515200c9efbeac2810d3260a2a1461adc304`. The earlier actual native attempt remains **24 of 27 predicates passed**, with actor-ingress backlog, progress-between-turns and strict idle quietness unqualified. Its observed `0x118` messages target a registered window, but neither that receiver category nor this new source identifies a producer or permits an idle exception.

The existing timer-state observer retains its original publication guard, cached state assignment, flags and record. Only an existing zero-state publication for a created, live, nonquiescing window with the original recorded handle qualifies for one `GetGUIThreadInfo` call on the explicit nonzero current native-thread ID. The record's optional auxiliary field is absent when unsampled and zero on API failure. Success is `0x80 | (caretAssociation << 5) | (guiFlags & 0x1f)`, where association 0/1/2 means no caret, a caret matching this recorded window, or another caret. No handle, caret rectangle or additional thread identifier is output or retained. The low caret flag describes current visibility; it is not evidence of a running timer.

This is an instantaneous diagnostic at a qualified publication, not a continuous idle or endpoint trace. It creates no additional native action, record, window, hook, timer, callback, message filtering or exception. The source leaves the exact smoke workload of 64 commands and ordinal-31 query, native/actor turn limits 16/32, all 27 predicates, schema 3, record/byte bounds and all existing attempt/watchdog/cleanup deadlines unchanged. The original Main, Validation and Observation output-contract source pins are untouched. It does not make an old executable binding current.

Seven new async `Win32NativeSmokeGUIThreadStateTests` cover API failure, successful absence, same-window caret with and without visibility, different-window association, documented versus unknown flag bits and absent-caret precedence. All 655 existing test files are unchanged. Root strict formatting of the three Swift files and architecture contracts passed without a formatting delta. The root staged diff is byte-identical to the reviewed 6,962-byte patch, SHA-256 `8ecb555d2b05477f33d9ae2296173bc08f647f15997fa88dedda55fee96b4df1`, recorded in `goal-ninth-native-gui8fc-root-staged-proof-v1.json`.

The resulting fixed native source cohort is the original 101 methods plus these seven; none of those 108 has yet run on this integrated source. Fresh compilation, focused execution and, separately, a newly bound actual native attempt remain required. Native fairness and idle criteria and all nine original completion gates remain open without moved goalposts.


### Ninth integration: independently corrected retained Arc test coordinates (2026-09-02)

The three incorrect coordinate comparisons in `testCheckedArcAdoptionUpdatesRetainedGeometryWithoutRestoringOldPaint` are replaced with analytic stored/presented geometry and interior pixel checks. This changes no production source or original acceptance criterion. Commit `3fb9e55a` had already normalized Arc's retained geometry before `41c9e82f` introduced these comparisons. The 3,291-byte Arc implementation block is unchanged through `7db6b98`, SHA-256 `b161709694fbd782402fd47134b2d3a77a95adb3dae8100a2a8aba679495c377`; the trim implementation did not change it.

The initial 120-by-40 row has a three-unit border, so its inner paint rectangle is `(3,3,114,34)`, center `(60,20)`, radius 17 and starting point `(77,20)`. Its stored normalized radius is `17/114`. After outer fill resets the border, the paint rectangle is `(0,0,120,40)`, center `(60,20)`, radius 20, stored radius `1/6`. Resizing to 160-by-40 moves the center to `(80,20)` while keeping radius 20, stored radius `1/8`. The new 35-degree start and 215-degree end use independent trigonometric constants. Expected geometry does not call `Arc.path(in:)` or `RenderPath.scaled`; actual emitted fill-command geometry is checked separately from the stored path, with a two-element open-arc structure and `1e-9` coordinate/angle accuracy.

The same three existing `renderFrame()` calls retain their order; only their returned frames are captured. Independent CPU probes require initial red coverage and black absence at fixed interior points, then blue coverage and opposite-side absence after the angle/paint change, then the correct shifted coverage with the old location empty after resizing. They cannot pass for a blank or stale frame. The fixture's existing black clear color is retained. These probes do not qualify gradient interpolation, stroke-dash fidelity, full-image baselines or native Arc parity.

The private assertion audit lists 35 original assertions, unwraps and assertion-helper calls: 32 remain byte-exact and in relative order, and only the three approved wrong-coordinate assertions are replaced. All seven original methods remain; all bytes outside this method are unchanged. Every other 655 existing test file is unchanged. The original failing outcome remains recorded as a failure of its original source, not rewritten as a success.

Root formatting changed only two line wraps inside new local helpers; exact byte transformations preserve their tokens and all existing assertions. Final strict lint and architecture checks passed. `goal-ninth-arc37de-root-staged-proof-v1.json` records the complete 8,339-byte staged patch, SHA-256 `7c09846ec1be919a7d8e31e4cc80e965ebb1c460d15c1316da5c26a739f67007`. Compiler, XCTest and raster execution of this correction remain pending. The next shape validation must include the existing twelve `ArcCoordinateTests` as independent controls, along with the original shape cohort and the separate retraced-curve repair. All nine original goal gates remain open.


### Ninth integration: reuse curve error allowance without increasing limits (2026-09-02)

The reviewed `d64e24eb29abf40234d3b656173ff69b3f26e7b3` source repair is integrated over `ed7e6084b63bdcbbcf745524921ec37ee69b0104`. It changes only `PathTrimming.Worker.measure` and adds a separate six-case portable test file. The preceding measured failure remains recorded: the original retraced quadratic threw `workLimit` at `7db6b98`. No new Swift success is claimed at this source checkpoint.

After the unchanged depth, midpoint split and exact-stagnation guards, measurement pays for the right child's chord/polygon bounds once. It reserves `min(T/2, rightRawError)`, measures the left child with the balance, and passes the left child's unused allowance to the right child together with those already paid bounds. This prevents exact monotone siblings from stranding half the allowance at each subdivision of a reversal. Every computed allowance must be finite and nonnegative; the combined reported error must be finite and no greater than the invocation's original tolerance. Rounded subtraction or addition that cannot satisfy these checks rejects with `numericalLimit`; there is no clamp, added epsilon, larger tolerance, retry or fallback geometry.

All five original limits remain unchanged: 65,536 input elements, 131,072 derived segments, 1,048,576 work steps, depth 24 and 56 inversion iterations. Path error shares remain `1e-7/count + 1e-8*originalControlPolygonLength`; prefix measurement still receives one quarter of the existing local endpoint allowance. Endpoint acceptance, path admission, finite arithmetic, exact full-range identity copying, equal-fraction handling and all-or-empty public rejection are unchanged. Each bound calculation consumes exactly one work debit, including the lookahead. A later left failure does not refund the already performed right calculation, and a right-bound failure may now precede a competing left-subtree failure. Those are explicit ordering effects, not a promise of identical failure precedence. No local bound tuple escapes its actual sibling or the depth-bounded recursion.

Six new `PathTrimmingReversalTests` independently cover left and right non-dyadic quadratic reversals, rotated/translated retracing, a cubic with two reversals and rationally selected parameters, unchanged low depth/work/inversion rejection, and exact binary64 midpoint stagnation with empty public output. Their positive coordinates use the existing `1e-5` comparison policy; all original 26 portable trimming cases and every other one of the 656 existing test files are unchanged. No production source outside this one measurement function changes.

The packet separately retains 33 pure arithmetic-model records and an independent source review. Those sampled models explain the failure and check debit/rounding boundaries; they are not Swift tests, runtime timings or renderer evidence. In particular, both modeled versions reject a 256-smooth-quadratic workload at the same 1,048,576-work cap. Floating rounding and different admitted prefix estimates prevent a universal work-reduction or finite-input-admission claim.

Root strict formatting and architecture checks passed for both Swift files without a formatting delta. The complete staged diff is byte-identical to the reviewed 9,493-byte patch, SHA-256 `2f255b1e124cc84a396f98926e27397d6f41f0e9279e73dbfa5e03c6e8a12919`, recorded in `goal-ninth-trim-reversal-d64e-root-staged-proof-v1.json`. Current documentation records the algorithm and pending execution. Fresh validation must retain the original 80 shape/selection cases, the twelve existing Arc coordinate controls and these six reversal cases; broader suites, retained gallery pixels and native parity remain separate. All original nine completion gates remain open with their original requirements.


### Ninth integration: a retained gallery fixture for partial trimming (2026-09-02)

The reviewed `7935f4b121054d4ed13cd0e586ab6194b156fdb8` fixture source is integrated over `c99942baec76070e0f558ec3a8f3f705b74ef6d4`. The new `DemoPartialTrimSample` uses shared SwiftUI-shaped source and ordinary `trim`, fill and stroke APIs; no platform-specific rendering workaround is added. Four registration lines add the single dark, scale-one, 600-by-400 `shape-trim-static` gallery entry. Every old catalog definition, baseline and comparison roster remains unchanged.

The scene pairs gray full outlines with colored wide/tall quarter outlines, shows a partial quadratic against its full curve, and compares full, half and empty fills. The six-unit stroke inset gives a wide 160-by-56 outline a quarter path from `(6,6)` to `(102,6)`, while the tall 56-by-160 outline runs from `(6,6)` through `(50,6)` to `(50,58)`; both selected distances are 96. The 160-by-96 quadratic's selected half has move `(6,90)`, control `(43,48)` and endpoint `(80,48)`. These are intended analytic review expectations, not an observed image result.

Root strict lint and architecture checks passed without a formatter delta. `goal-ninth-trim-gallery7935-root-staged-proof-v1.json` records the exact reviewed 4,069-byte source diff, SHA-256 `b7383b6372211531b0db8d7702ff342905db9c60bbd0ebaeb015b3eea9792d1f`; all 657 existing test files are unchanged. The fixture has not yet compiled, rendered or been visually inspected on root. Fresh execution must use the retained gallery executable built from the recorded source and a new artifacts directory, never a desktop/window capture or a stale executable. No baseline will be accepted without inspecting the actual result. The original shape, rendering and all other nine completion gates remain open.


### Ninth integration: omit optional work only in the original final UIA query (2026-09-02)

First, a correction to the preceding framed-visibility entry: its phrase "original default sixteen-element/four-round cases" was inaccurate. The configured default is **128 elements and four rounds**, unchanged in `922ff21`, `2c71162`, `7db6b98` and `12daf29`. The failed default test's diagnostic reported **16 consumed elements**, four consumed rounds and `budgetExhausted`; 16 was not its configured element limit. The explicit eight- and sixteen-round cases also use 128 elements, and the exhausted negative uses one element/one round. `goal-ninth-uia-default-budget-wording-correction-v1.json` records the actual source blobs/constants and original failure line. This corrects the ledger, not the implementation or an acceptance requirement. All original bytes and tests remain preserved.

The reviewed `2037f07cb4891623bfa7e1825090e77a41b13bbf` incremental source packet is integrated over `12daf2949e1d967ac692c33477a3fb7b6c372b60`, keeping the earlier anchor and visibility changes. After the existing preparation-currentness guard and before lease callbacks, Runtime captures one Boolean requiring the original preparation/current request, `.finalQuery`, no hint, an unsealed query, the original current query sequence, exact content and adapter, and the same shared work budget. It deliberately does not require remaining rounds to be positive: an already paid last round may have zero remaining. No extra phase, budget recharge or later retry is introduced.

Only this Boolean travels through the existing preparation helpers. The adapter omits only the no-hint optional token append. Full window selection, required/protected/target rows, transition requirements, original measured anchor support, gap probes, hinted rows, all mounted measurements, caps, admission, journals, departure cleanup and completion checks remain intact. The flag is not stored on the request, adapter, candidate or runtime and is not an authority certificate. Existing guards still reject a finished request, stale attachment or obsolete epoch after callbacks. A genuine typed request using a raw adapter is eligible; ordinary raw planning and unrelated adapters retain the default false behavior.

Omitting optional rows can retire previously mounted optional resources; the existing cleanup still must complete. Ordinary prefetch resumes on the next actual ordinary build, not merely because an idle query observes missing optional rows. The restoration fixture therefore moves the viewport by 20 to introduce genuinely required row 301. The quiet final query builds no new row, so callback-expiry controls use real `canBuild` and `canAdopt` boundaries with exactly one intervention rather than a vacuous final-factory hook.

Thirteen new async cases cover default-budget raw/public requests, ordinary preparation and generic realization, an unrelated sibling adapter, focus-protected rows, a required gap probe, the complete measurement oracle, request expiry before and after epoch creation, attachment removal/restoration, weak request/optional-row lifetime and actual paid convergence events. The measurement-negative case changes local copies passed to the existing oracle; it does not claim that Runtime rejected an already accepted receipt. The payload-release case covers raw rows, not all managed Button/task/State cleanup. The public pending-Button case requires the separately integrated visibility fix. All 657 prior test files and original default/explicit/exhausted controls remain unchanged.

Root verified all eight exact source transformations forward and backward against the current complete Runtime and Adapter files. This preserves the earlier visibility predicate, anchor prerequisite and passive diagnostics, not just the old private base. The initial patch differs from the reviewed packet only in Git blob IDs; every hunk count, context, addition and deletion is identical. Formatting changed two statement wraps in the new test file only. Final three-file strict lint and architecture checks passed. `goal-ninth-uia-final-prefetch2037-root-staged-proof-v1.json` records the 42,122-byte formatted diff, SHA-256 `0ad0bd27c1fc8150d6f3e25d69a4a490df9e6a0e0fb58739bf9158ba88db1622`; separate source-join, formatting and packet proofs retain their scopes.

This source composition has not yet compiled or executed. The original failed UIA outcomes, first-query behavior, one-element/one-round refusal, default four-round success requirement, managed cleanup, readers and overflow cases still require fresh validation. All nine original completion gates remain open without changed budgets or moved goalposts.


### Ninth integration: consume owned observed-object batches independently of frame submission (2026-09-02)

The reviewed async-v2 native reload source is integrated over `0516a16767659a9e4f0d98606df26920e8b4bf6d`. Previously, the scheduler used the presence of any HWND to suppress its main-actor task, although owned presentation has a separate cooperative actor. Frame submission can return before the batch consumer for transition, readiness, surface, resize or pacing reasons. A live owned window with unavailable presentation could therefore retain a pending observation batch despite an available actor. This is an ordinary reload-liveness defect, not evidence that it caused the earlier native smoke failures.

The actual scheduler now uses the immutable `usesNativePresentation` choice made at host construction. Owned presentation schedules the existing weak-self task with `requestsFrame: false`, both before and after native handle creation. A legacy live HWND retains the no-task blocking-loop policy; a headless legacy host still schedules with `requestsFrame: true`. The original animation-driver synchronization, native invalidation and teardown guards remain in order. The helper expresses that four-row policy; it does not fabricate a native owner or an acknowledgment.

The complete 108,131-byte App suffix beginning at `flushObservedObjectReload` remains unchanged. The consumer still clears an accepted batch before callbacks, selects the latest relevant transaction, preserves explicit nil animation and other transaction fields, keeps reentrant mutations in their own batch, skips irrelevant objects, and refuses work after teardown. Disabling this task's direct frame request does not eliminate adoption's lifecycle, accessibility, close-affordance or dialog obligations. Separately serviced actor-turn batches may legitimately do more such work than a batch delayed until a later frame. The native message cap, query limit, N/A scheduling constants, 27 smoke predicates, trace limits and timeouts are not changed.

Eight new async tests cover all four policy inputs, same-turn coalescing without available frames, relevant versus unrelated transactions, explicit nil animation, reentrancy, unrelated-object handling, same-turn teardown and the legacy headless follow-up frame. They use a real native-selected factory without starting a native owner or HWND. The teardown fixture follows the existing no-owner cleanup and false waiter completion; it does not manufacture a successful native teardown. A completed-scene counter is not a count of every cached scene read. Live HWND behavior, fairness and long-running observation remain outside this fixture's proof.

Root reviewed the original source and verified that async v2 adds only `async` to the first new test relative to the first reviewed packet, aside from Git metadata. The complete staged source diff is byte-identical to the reviewed 19,506-byte patch, SHA-256 `f925f19af3f692c628809df437e7e650ba1e5542ea66c99e6f809b3ed45e52e5`. `goal-ninth-native-owned-reload-root-staged-proof-v1.json` records all 658 prior test files unchanged, and `goal-ninth-native-owned-reload-root-consumer-proof-v1.json` records the untouched consumer suffix and all eight async methods. Both Swift files passed strict lint and architecture checks without a formatter delta.

These source checks are not compilation or execution evidence. The next native focused cohort must retain the original 101 cases, the seven GUI-state cases and these eight cases on one recorded HEAD. A new actual native run still needs a fresh executable binding and all unchanged predicates; the earlier 24-of-27 result remains a failure. All nine original completion gates and their requirements remain open.


### Ninth integration: bounded observations for the remaining raw-array List shrink failure (2026-09-02)

One diagnostic companion is added over `0ef291daae52941e9b4c8fda8456356e9b2f6639`; it repairs no production behavior and does not replace the original failing test. The actual Builder78 run at `7db6b98` reported attached tail text 41 instead of 42 and six row factories instead of five metadata samples. That evidence did not establish whether the body had read 42, identify the first rejecting guard, or prove the earlier stale-map hypothesis. The separate four inactive-container failures remain separate work.

`DeferredListProjectionShrinkDiagnosticTests` copies the original data-driven List route into one new async test. All 22 original assertions remain verbatim and in order. Selection, initial values, binding captures, mutations and the five two-frame flushes remain unchanged. Its separate diagnostic root/tail concrete types mean reproduction itself still needs execution. No old test or production file is modified; all 659 prior test files retain their exact Git objects.

The companion records root entry/return, row factories and the value already read by each body, plus snapshots after the original creation, mutations and frames. Snapshot work reads existing native fields and cached adapter counts without provider calls, guard reevaluation, additional authored State/Binding reads or extra rendering. Storage is capped at 128 scalar events, traversal at 128 nodes per snapshot, four List records and sixteen child addresses per List; truncation/drop flags remain explicit. Only value records and UInt addresses escape the non-inlined snapshot boundary. The separate report recorder retains no capture, binding, view, node, adapter or callback and emits JSON after the existing fixture close.

The existing host counter counts noninitial reload attempts, not accepted root reloads. `lazyListResolveCount` counts accepted List row resolutions after payload cleanup, not a root-completion acknowledgment. A body value of 42 with attached text 41 would narrow the failure to later construction/adoption; absent body42 would identify a different boundary. A cached mapped-leaf/actual-child count mismatch would be an observed inconsistency, not proof of the first cause or of identity equality when counts match. Recorded addresses can be reused and are not lifetime certificates.

Root read the complete patch and passivity report, independently compared the 22 assertions, and verified the byte-identical 17,335-byte staged patch, SHA-256 `98008296e3bd7ff0bc30b98ea6a056511b94903f8b6df0b7203a202993e17d99`. `goal-ninth-list-shrink-diagnostic-root-staged-proof-v1.json` and `goal-ninth-list-shrink-diagnostic-root-assertion-proof-v1.json` record the source checks. Strict formatting and architecture checks passed without a formatter change. Compilation and the diagnostic result remain unverified.

The next source freeze is intended to run the complete 98-case shape cohort first, then the 116 native, 79 builder and 191 UIA cases serially at the same compiled HEAD, preserving the existing 900-second per-cohort budget. The compiler-first order keeps compilation time out of the large UIA run; it does not alter an acceptance requirement. Source changes require a new freeze and fresh binding. Neither this diagnostic nor the proposed cohort rosters closes any of the original nine gates.


### Ninth integration: fresh four-cohort, native and retained-gallery outcomes at a3dfc5f (2026-09-02)

All execution in this checkpoint used source commit `a3dfc5f20f191c173aa23c4569734bfb5cb41455`, tree `662a847b10e2bfbba8b69653a128e491276f6ff0`. The four focused selections retained every one of the 414 original seed method identifiers and added 70 explicitly inventoried methods. All 484 selected cases started: **469 passed, 15 failed, zero skipped**. Every run closed naturally with unchanged source/index endpoints, and each subsequent point-in-time CIM census found no matching process. The per-cohort 900-second limit, original assertions and test budgets were not increased or removed. These are four focused runs, not a full-suite pass.

| Cohort | Passed | Failed | Skipped | Child/runner exit | Seconds including build |
| --- | ---: | ---: | ---: | --- | ---: |
| Shape and List tags, 98 cases | 98 | 0 | 0 | 0/0 | 399.015 |
| Native components, 116 cases | 116 | 0 | 0 | 0/0 | 9.047 |
| Builder and shrink diagnostic, 79 cases | 73 | 6 | 0 | 1/1 | 10.875 |
| UIA and anchor support, 191 cases | 182 | 9 | 0 | 1/1 | 500.094 |

The Shape98 run `shape-tag98-a3dfc5f-dc1ae38c3450418eaba00453b404063d` includes the fresh 391.98-second compile. Its 3,739,422-byte raw log hashes to `b210aac219b4243d74dea5908722445d4f01a2c2a21592c104190e807c753b93`. All 26 original portable trimming cases, six reversal controls, twelve retained trimming cases, twelve Arc coordinate controls, sixteen shape-paint cases, ten fill-rule cases, seven retained shape-callback cases and nine List-tag cases passed. Both previously failing methods now pass with the separately reviewed repair/oracles. `goal-ninth-shape-tag98-a3dfc5f-reconciled-v1.json` records the exact outcomes. This establishes neither arbitrary shape composition nor native/macOS fidelity.

The Native116 run `native116-a3dfc5f-4cd71ace227d4db7849f8ac3edc4498a` passed the original 101 methods, seven GUI-state encoding controls and eight owned observation-batch controls. Its raw log is 35,258 bytes, SHA-256 `3d2c948a260c34c99c5c3611d0ea99fa7fb163615bef9168bd8d386c24a01d31`. `goal-ninth-native116-a3dfc5f-reconciled-v1.json` preserves the method-level result. These component tests do not themselves exercise a live HWND, establish actor fairness or prove strict idle behavior; the separate actual native run below remains unsuccessful.

The Builder79 run `builder79-a3dfc5f-f85ddd470c2d4a83b99de46d7b4c2f0a` has the same five original failures plus the new diagnostic companion's two failing assertions in one method. Four original inactive-container/state cases remain in the canonical and legacy-array mounted builders. The original raw-array optional-removal case and its diagnostic still show tail text 41 instead of 42 and six factories instead of five metadata samples. The original eight test files are unchanged. All 79 async identifiers match the fresh observed compiler-discovery copy and their exact source declarations; this is compiler-output association, not sealed compiler-input attestation. The raw log is 50,500 bytes, SHA-256 `b87d16240ec3b2bd639dd36a22eeeabfb9697926c25cdcced30cef63ee3761c1`; `goal-ninth-builder79-a3dfc5f-reconciled-v1.json` records the results.

The shrink companion emitted 39 bounded events with no drops or truncation. After optional removal, actual children and mapped leaves both equal two, and accepted List resolutions equal three. Later body events 30, 32 and 35 read 42, while snapshots 33, 36 and 39 retain attached text 41 and the same completion count. Thus the earlier count-mismatch explanation was not observed; the failure occurs after the body reads its updated value. `goal-ninth-builder79-a3dfc5f-shrink-diagnostic-v1.json` is 15,477 bytes, SHA-256 `cd1a831b155b7b6c883759d5ee9159bd8c975dc50328883ce10cb845185c4cbc`. Addresses remain scalar observations, not lifetime/identity proof. Independent source review found that accepted synthetic gaps enter the complete physical attachment receipt despite having no authored contribution, while both physical-departure paths discover receipts only through contributions. This can strand a departed gap and reject the next complete handoff. The exact first failed guard was not observed; a private original-attachment retirement correction is pending, with every handoff guard and existing test retained.

The UIA191 run `uia191-a3dfc5f-f7a112b3827146b8a2011c915bf5aa2e` has this complete class-level result:

| Test class | Passed | Failed |
| --- | ---: | ---: |
| LazyListAnchorSupportTests | 9 | 4 |
| LazyListUIAConstructionHintTests | 30 | 0 |
| LazyListUIAContinuationTests | 40 | 0 |
| LazyListUIAFinalPrefetchTests | 13 | 0 |
| LazyListUIAFramedRowVisibilityTests | 5 | 1 |
| LazyListUIAInsertionOriginTests | 10 | 0 |
| LazyListUIAMeasurementCorrectionTests | 15 | 0 |
| LazyListUIAReaderButtonConstructionTests | 3 | 0 |
| LazyListUIARejectionDiagnosticsTests | 3 | 0 |
| LazyListUIAScrollGeometryTests | 22 | 0 |
| LazyListUIAUnusedProviderPhaseTests | 13 | 0 |
| ManagedListUIAReaderAuthorityTests | 4 | 0 |
| ManagedListUIARealizationBudgetTests | 4 | 0 |
| PublicLazyListAccessibilityTests | 11 | 4 |

The raw UIA log is 66,722 bytes, SHA-256 `1db074d862931655f5105a3997ef128c42d046a938dc60546d48c45ad5aa6dc4`; `goal-ninth-uia191-a3dfc5f-reconciled-v1.json` records every outcome. The original default **128-element/four-round** pending-update cases, explicit allowances and one-element/one-round rejection control all pass. This is not blanket public-List realization success: the already-warm public `testRealizeAdoptsAndLaysOutTheActualActionTarget`, `testLogicalIDsSurviveReceiptEvictionWithoutRetainingRows` and `testZeroAndMultipleLeavesKeepLogicalEnumerationHonest` still return failure and leave unavailable action/name targets. Their unchanged assertions remain open. Their shared 50,000-row fixture also exposes a source-level mismatch between the full logical extent and the one-million-unit paint-coordinate cap applied to resolved content size. The existing exact terminal equality cannot hold for that warm List. A bounded separation of logical scroll extent from paint sanitation is under review; no equality guard, row count or budget has been weakened, and the first failed guard was not recorded by this run.

The four failing new anchor methods are `testAcceptedReorderMeasuresNewPredecessorOrderWithoutBorrowingOldHeights`, `testCapturedProofsDoNotRetainClosedPhysicalRows`, `testGenericPreparationMeasuresOriginalMountedPrefixBeforeCorrectingAnchor` and `testOneElementOneRoundCannotBorrowOldPredecessorMeasurements`. The fourth failed public method is `testSuccessorDuringPreparationCannotCorrectTheSameScrollOwnersAnchor`. Source review distinguishes layout-only render dirtiness from actual settlement and the live fixture's prepaint ownership from weak support witnesses. Numeric anchor failures require separate treatment: a legitimately accepted partial candidate can resolve its original anchor against estimates, whereas overwriting accepted scalar coordinates during an aborted preparation can lose the successor's prior within-row offset. Merely accepting a newly captured post-loss anchor would conceal that latter defect. No failing method has yet been altered or relabelled.

The one framed-visibility failure is the exact transform assertion in `testFramedRowWithPositiveLayoutButZeroPaintAreaIsNotRevealed`; its other rejection and settlement assertions pass. The authored `scaleEffect(x: 0, y: 1)` becomes scale zero on both axes because existing matrix decomposition discards the surviving second column when the first column is zero. This is a separate geometry defect, not justification to weaken the UIA fixture. A bounded geometry repair is pending, keeping the original x-zero/y-one setup and assertion unchanged. Broader rank-one transform limitations remain open.

Actual native execution used a newly bound executable, not the older 922ff21 binary. `goal-ninth-a3dfc5f-native-gallery-compile-association-v1.json` records the Shape98 link lines, timestamps within that fresh compile, current PE hashes and matching source/index endpoints across all four runs. Native116 itself was incremental and contained no new native link; its launch-association record preserves that fact. The native executable is 96,303,616 bytes, SHA-256 `900c8acbe55db1adcd07f688819d130d59a987626e7afd4afb220d58b0b2a9d0`. The new launch binding records 135 runtime DLL files totaling 817,850,784 bytes, but is not an attestation of which DLLs the loader executed.

The actual run `goal-ninth-native-owned-smoke-0ed910840edd48d1b60ef4c5173edb70`, fixture run ID `DBDB6D40-79C5-45C7-88FF-F74CE5726CD0`, closed naturally with child/runner exits 1/1 after 11.359 seconds. **24 of the original 27 predicates passed.** The same two backlog/fairness predicates and `three-second-unforced-settled-idle` fail. The result explicitly reports insufficient fairness exercise; it does not demonstrate starvation or permit a fairness claim. All 64 probes/replies, the three retained update phases, owner teardown/join, actual timer absence and the other passing predicates remain recorded independently. No workload, event cap, native/actor turn constant, query limit, timeout or predicate was changed.

That native trace has 2,721 records, 641,883 bytes, SHA-256 `43b9e4c4eb1927996b7ca031d3816408413b59a3d327d1542ad74be3c2348b16`. Root independently checked contiguous ordinals, run ID, event counts, exact output hashes and source/input endpoints in `goal-ninth-native-owned-0ed9108-reconciled-v1.json`. The controller reports structurally valid output despite unsuccessful qualification. The original exit's operator-cleanup flag remains true and unchanged; the subsequent separate CIM observation found no matching process after natural direct-child closure. Neither observation proves continuous descendant, loader, COM-routing or display-completion behavior. The seven sampled zero-timer GUI publications encode 0x80: successful query, no reported caret and zero low GUI flags. The last is 0.3969 milliseconds before the idle interval. That 3.0095306-second interval still contains six 0x118 dispatch/return pairs to the registered receiver. Those observations do not identify their sender or cause. The maximum observed actor turn starts with and consumes 23 records, below the required 32-record backlogged exercise; a 24-record queue observation is not a qualifying turn. The native query spans actor consumption of probes 9 through 30 without native work/dispatch. These findings do not justify changing the fairness or idle predicates.

The freshly linked gallery executable is 100,334,080 bytes, SHA-256 `ea53701b156753a1bbd6d418639a763bb0d825094080a60d08405e7453a1b0dd`. It rendered only `shape-trim-static` into the new `artifacts/goal-ninth-trim-gallery-a3dfc5f-v1/gallery` directory and closed naturally with exit zero. The wrapper verified all 1,115 tracked regular files and the index against the frozen source record before and after execution, and retained the same PE bytes. Its elapsed render/verification interval was 1.375 seconds, not a frame-time benchmark. The PNG is 600 by 400, 960,538 bytes, SHA-256 `8d96c9c1c6db18d9d8f7960440555644dbf52589148ef1311e3cc69dd5ae6d9e`; the raw log confirms exactly one entry.

Root opened and inspected that actual retained-snapshot/CPU-raster PNG. All six panels are visible: the wide cyan quarter ends along its upper edge, the tall quarter continues down the right edge, the orange quadratic ends at the center apex, and full/half/empty mint selections appear over gray references without a colored fallback in the empty panel. The gray complete-curve reference shows segment faceting, so antialiasing/stroke fidelity remains unqualified. `goal-ninth-trim-gallery-a3dfc5f-visual-review-v1.json` separates visual observations from header/count checks. No desktop or window capture, new baseline, baseline replacement, D3D11 presentation proof or macOS reference comparison is involved.

Current compatibility and path-trimming documentation now reflect the executed Shape98 and one-image results instead of the earlier source-only checkpoint. The remaining 15 focused failures, unsuccessful actual native qualification, broader Core/List suites, File14, templates, full release-quality validation, hardware/performance/manual/clean-environment requirements and final batch push remain outstanding. All original nine completion gates remain open with their original requirements; this entry only adds evidence and detail.


### Ninth integration: preserve a surviving matrix column for a collapsed X axis (2026-09-02)

The reviewed `fe323604cd40b2a0d4df01f4b9c5a18eca7d0401` geometry source is integrated over `8f561c4c53094b87d7364d0de80cebdcdd2a5133`. The actual UIA191 run showed that the original public `.scaleEffect(x: 0, y: 1)` fixture became `(0, 0)` during composition. Its exact `(0, 1)` assertion correctly exposed loss of the surviving matrix column. The existing fixture, visibility predicates, settlement assertions and all other 660 pre-existing test files remain unchanged; the repair belongs in geometry, not a replacement test expectation.

The production change inserts only recovery of the finite second column `(c,d)` inside the existing zero-norm branch, additionally requiring that the first column `(a,b)` is exactly zero. Signed Y scale and an atan2 rotation reconstruct `(c,d) = scaleY * (-sin(rotation), cos(rotation))` with zero skews. Choosing the scale sign from d preserves a pure negative Y scale without introducing a half turn. A rescaled norm avoids unnecessary squaring overflow/underflow; only a representable resulting norm is accepted. Translation and the old true-zero/fallback initialization remain unchanged. Small coefficients and angles are not snapped away. The entire normal decomposition branch and every other original Geometry byte are preserved.

Thirteen new `TransformZeroColumnTests` use literal matrices and independently calculated point mappings for positive/negative Y axes, all rotated quadrants, both quarter turns, a zero linear map, identity/centered composition, tiny and large finite columns, a small nonzero angle, and full-rank/reflection/shear/first-column-only controls. Exact axis cases require exact values; rotated cases use explicit floating-point tolerances. Tiny tolerances and the separately tested small coefficient prevent an all-zero result from passing. These are portable Core value sources housed in the existing CoreLogic test target, not Windows/macOS execution evidence.

Root read the complete source/test diff and independent source report. The initial strict formatter check required one line break after the new rotation assignment. Formatting changed only that break and indentation; the complete inverse is recorded in `goal-ninth-zero-column-root-format-proof-v1.json`. The formatted source diff is 11,894 bytes, SHA-256 `266267c5d8957d847ffa61ce85b7427e3f47fc0497a344bcc9ea72a74c8040b8`. `goal-ninth-zero-column-root-staged-proof-v1.json` records the exact two changed source paths, all 660 old tests unchanged and the thirteen added methods. Final strict lint and architecture contracts pass. No compiler or test execution of this correction has yet occurred.

Other transform defects remain open: nonzero first columns whose squared norm underflows, surviving columns whose norm exceeds the representable range, and rank-one matrices with parallel nonzero columns. The representation can express the last case with both skews, so it is not dismissed as mathematically impossible. This narrow correction establishes no complete singular-transform, rendering, hit-testing or native parity claim. Fresh execution must retain the original failing UIA fixture and prior shape/geometry controls.

A clarification to the preceding native observation entry: "the last" GUI sample before idle refers to the last of the five pre-idle samples, not the last sample in the complete run. Two more samples occur after idle; none occurs within the 3.0095306-second interval. All seven encode 0x80. The source/trace review establishes neither continuous caret absence nor the producer of the six 0x118 message pairs. The 24-of-27 native result remains unsuccessful, with every original predicate unchanged.

All nine original goal gates and their acceptance requirements remain open. Current compatibility documentation records this geometry correction as source-reviewed and unexecuted; the original ledger bytes, old failed outcomes and unresolved work remain preserved.
