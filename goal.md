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
