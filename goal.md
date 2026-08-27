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

- [ ] Host `Settings` alongside ordinary scenes through public scene composition;
      route `openSettings` to one reusable settings window and preserve normal
      window lifecycle, renderer injection, and focus requests.
- [x] Carry binding transactions through writes, projected bindings, state
      observation, and retained animation; restore ambient context after nested
      writes and explicit animation suppression.
      `BindingTransactionTests` passed 14 focused tests, including a real
      state-driven intermediate opacity frame, alongside the existing
      `SwitchKnobMotionTests`. This verifies synchronous retained propagation;
      conflicting ambient/binding precedence and deferred-update behavior
      remain native-reference qualification gaps under gates 1–3.
- [ ] Dispatch scroll geometry, phase, and visibility callbacks from retained
      presentation, preserving observer history across rebuilds and respecting
      scroll ownership, clipping, and animation.
- [ ] Persist the settings template through an injectable local store; restore
      it on launch, validate saved data, preserve unsaved edits on write failure,
      and keep snapshots/tests isolated from user settings.
- [ ] Correct authored color-effect parameters and preserve sequential effects
      across relevant primitive and compositing paths, with CPU/D3D11 execution
      tests and explicitly recorded remaining limitations.
