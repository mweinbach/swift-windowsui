# Testing And Visual Checks

This repo uses first-class PowerShell scripts under `scripts/` for local Windows validation.
`scripts/with-swift.ps1` prepares the Swift for Windows environment by locating
Visual Studio through the active environment, `vswhere`, or installed Visual
Studio 18/2022 instances before adding the Swift toolchain, runtime, and SDK
paths. The Visual Studio installer directory is also added to `PATH` before
`VsDevCmd.bat` runs so its own `vswhere.exe` lookup works in hardened shells;
developer-environment startup failures are reported immediately.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/with-swift.ps1 -CheckOnly
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/agent-check.ps1 -ContractsOnly
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/lint.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/agent-check.ps1 -Quick
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/build.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/build.ps1 -Configuration release
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/demo-probe.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/demo-screenshot.ps1
```

## Agent Guardrails

Use these checks when making agent-driven changes:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/check-contracts.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/lint.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/lint.ps1 -AllSwift
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/agent-check.ps1 -Quick
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/agent-check.ps1 -Quick -Format
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/agent-check.ps1 -Full
```

- `check-contracts.ps1` fails fast on architecture regressions that generic lint cannot see. Besides the target dependency direction and the presentation-order rules, it pins the two single-implementation invariants a test cannot: `SceneRasterizer.swift` takes its coverage from `GPUIQuadCoverage`, declares no rounded-rect distance or smoothstep of its own, calls neither unqualified, and never answers coverage with a containment test against a sample point (WS-08); and `Runtime.swift` / `ScenePainter.swift` narrow clips only through `RuntimeClipShape.narrowed(to:)`, never with a bare `Rect.intersected(with:)` in any binding form — `guard let` and `if let` included (WS-16). A second copy of either rule is invisible to every pixel gate until it has already drifted. When editing these two rules, prove the edited pattern still fires: break the guarded file with a synthetic violation, run `check-contracts.ps1`, then `git checkout` the file and confirm the check is clean again. A rule that matches nothing passes silently forever.
- `lint.ps1` runs `check-contracts.ps1` and then toolchain `swift-format lint --strict` against changed Swift files. Use `-Path <file>` when the checkout already has unrelated dirty Swift files, and use `-AllSwift` before broad cleanup branches or CI-style validation.
  Every explicit `-Path` entry must name an existing file; missing, blank, or
  directory entries fail before the formatter runs, including mixed valid and
  invalid lists. Paths are literal, so comma-containing filenames are not split.
  For multiple files, invoke the script from PowerShell with an array, for example
  `& ./scripts/lint.ps1 -Path @("Sources/WinSwiftUI/Core.swift", "Sources/WinSwiftUI/Views.swift")`;
  a comma-separated argument passed through native `powershell -File` is one path.
  Omitting `-Path` still succeeds when there are no changed Swift files, and
  `-ContractsOnly` still bypasses file selection.
  `scripts/test-lint-paths.ps1` checks selection and failure propagation using
  owned synthetic files and fake tooling; it never runs a formatter or compiler.
- `agent-check.ps1 -Quick` runs contract checks, focused scene/renderer/runtime tests (including the two WARP suites, `D3D11BatchRendererRenderTests` and `CrossBackendPixelParityTests`, the pixel-format contract `PixelFormatContractTests`, and the device-loss suites `DeviceLostPolicyTests` / `DeviceLossRecoveryTests` / `PresentationFailurePolicyTests`), and the demo executable build serially. Add `-GalleryCompare` to also run the gallery regression gate.
- Four P1 invariant suites gate Quick as well: `ScenePresentationOrderTests` (the single draw-order authority), `SharedCoverageKernelTests` (the CPU/GPU coverage kernel), `CPUGPUBlendModeContractTests` (source-over on both paths) and `ClipAbstractionTests` (one clip value, one space). All four are cheap — 0.02 s to 0.4 s of test time each, ~2.5 s of wall clock apiece once the build is warm, since a `swift test` invocation dominates. The remaining P1 suites (`CPURasterizerGPUModelTests`, `PathRasterizationQualityTests`, `BorderCornerArcGeometryTests`, `TextShapingPipelineTests`) stay Full-only. Keep the Quick gate under ~10 minutes: measure a candidate before promoting it.
- Three P2 invariant suites joined them in P2F-GATES: `RenderPassAbstractionTests` (0.71 s — the render-pass vocabulary both backends speak; the contract check can only see that each side *mentions* the shared derivations, this checks they agree on the answers), `StrokeStyleContractTests` (0.03 s — caps, joins and the bounds outset that has to cover them, on both stroke routes), and `GlyphAtlasExhaustionSafetyTests` (0.06 s — never ship a glyph quad addressing someone else's atlas cell). All three are invisible to the screenshot gates: a stale UV renders as a plausible wrong character, and a blur schedule mismatch only shows on the GPU, which no screenshot goes through. The heavier P2 suites (`D3D11PathCacheTests`, `PathDashingTests`, `CacheComplexityAndReclamationTests`, `LazyStackVirtualizationTests`) stay Full-only.
- Product/runtime behavior also gates Quick: `GradientRenderingFidelityTests`, `PathGradientRenderingTests`, and `CanvasPathGradientIntegrationTests` check directional GPU-quad promotion, CPU/D3D11 gradient parity, authored stops/endpoints, retained lowering, and frame degradation; `ViewNodeSparseStorageTests` pins genuinely lazy optional capabilities and IME/caret callback reconciliation; `ListVirtualizationTests` pins viewport-bounded large-list layout, exact pixels, far-row keyboard navigation, programmatic scrolling, and accessibility placeholders; `UIAAdvancedPatternTests` drives secure Value, Toggle, Selection/SelectionItem, and VirtualizedItem patterns through real COM vtables; `HighContrastSystemPaletteTests` pins exact native contrast-theme role propagation; `TextInputSelectionTests` covers Unicode/grapheme-aware word navigation and bound selection; `DemoCommandPaletteAndTableWorkflowTests` covers global command shortcuts, responsive product chrome, sorting, pagination, and validated settings; `RuntimeProgrammaticScrollTests` plus `WinSwiftUIScrollViewReaderTests` pin anchored scrolling, first-render replay, deferred lazy rows, and reader ownership; and `ClipboardFileFormatTests` plus `DropFilesPayloadHardeningTests` keep typed paste and hostile cross-process file-list validation fail-closed.
- Quick also registers the document file/session/undo and template-hosting
  suites, dialog/close ownership and build settlement, editor layout and
  viewport navigation, retained alerts, and accessibility action/provider
  lifetime through bounded serial shards. Hidden-window and COM fixtures
  do not establish interactive document workflows or native SwiftUI parity.
- `agent-check.ps1 -Full` runs full tests, builds the demo in debug and release configurations, regenerates scene plus frame fallback screenshots, and runs the gallery regression gate. The release build catches optimized-compilation diagnostics that debug tests can miss; it is not a hardware timing qualification or a release-mode test run. Small XCTest classes share bounded alternation-filter shards (up to eight targets and 3,000 estimated expanded identifier characters by default), substantially reducing repeated SwiftPM startup while keeping all `.build` access strictly serial; oversized classes retain their existing method-level safety sharding.
- Do not run multiple SwiftPM test/build commands against this checkout in parallel; they share `.build/build.db`.
- Both validation modes run the API review-unit fixture suite after the audit
  intake/ledger/workflow checks. Its exact-identifier packets reconcile all
  captured raw records and retain explicit committed Windows source blobs;
  passing these tooling tests does not approve an API mapping or behavior.
- Both modes also run `test-swiftui-color-rgb-reference.ps1`. Its synthetic
  fixtures cover strict report parsing, fixed component bounds, source and
  compiler provenance, process failures, and separate primary/AppKit outcomes.
  These checks compile only a managed JSON helper, not Swift or a native color
  observer. Actual collection requires the separate clean-source workflow in
  [ColorRGBReference.md](ColorRGBReference.md).
- Keep tracked files and Git state unchanged while validation is active. The
  review suite checks repository immutability, and the bounded-memory fixture
  measures the whole test process. Quick and Full launch only that fixture in
  a fresh process using the current PowerShell installation under `$PSHOME`;
  its arguments and 768 MiB budget are unchanged. Standalone runs also need a
  fresh process so earlier suites' allocation peaks do not affect the result.
  Both modes also run `scripts/test-agent-check-memory-isolation.ps1`, which
  checks this boundary under PS5.1 and PS7 using a copied runner and tiny stage
  stubs. It checks engine, process identity, arguments, failures, and the
  ContractsOnly bypass without running the real memory workload, SwiftPM, or
  the Quick/Full validation work.
- Use `async` test methods in `@MainActor` XCTest classes. With the current Windows toolchain, synchronous actor-isolated methods can compile but crash SwiftPM's test discovery when it casts them to nonisolated callbacks, before a filter executes. A standalone XCTest entrypoint does not validate that discovery path.
- Quick includes `RetainedViewIdentityTests`, `WinSwiftUIStructuralIdentityTests`, and `ViewIdentityRoleTests` for typed keys, structural branches and slots, erased fragments, and auxiliary builder roles. These check retained-node identity, not mounted `State` or `StateObject` storage.
  The identity suite also covers singleton tag/layout precedence, retained focus
  and callbacks, recursive editor departure ordering, and child-count boundaries.
  Local `Hashable` counters check omitted singleton key hashing without production
  instrumentation; they do not measure allocations, elapsed time, or frame pacing.
- Quick also runs the canonical ViewBuilder public, mounted, metadata, and
  array-compatibility suites, `ViewListProjectionTests`, and the three explicit
  `WindowsArrayViewBuilder` suites. They preserve inherited body syntax,
  current tuple children, structural ownership, metadata, and Windows array
  migration behavior. The separate expected-failure fixture under
  `Tests/CompileFixtures/ViewBuilder` is outside SwiftPM test discovery; its
  real-module invocation and strict diagnostic comparison are documented there.
- Quick includes `WinSwiftUIColorInitializerTests` and
  `WinSwiftUIColorSpaceConversionTests` for the canonical RGB constructor's
  signed transfer curves, P3 primaries, finite storage policy, alpha handling,
  and distinction between extended stored values and clamped renderer output.
  These mathematical and retained-output checks do not establish native
  color resolution, wide-gamut output, or white-initializer conformance.
- Quick also includes `StructuralComponentTests`,
  `StructuralCompositionIdentityTests`, and `StructuralComponentMountedTests`.
  They check direct stack children, empty compositions, opaque decorated
  boundaries, captured context, raw and mounted identity, and retained row
  metadata. The unchanged construction/headroom suites remain a separate gate.
  See [StructuralComposition.md](StructuralComposition.md) for the deliberately
  limited consumers and the remaining native compatibility boundaries.
- Quick separately includes `DynamicPropertyInstallationTests`,
  `StateMountRegistryTests`, `RetainedBuildLifecycleTests`, the seven
  `MountedState`/`MountedOutlineGroup` suites, and
  `EditorStateOwnershipTeardownTests`. They cover ordinary mounted State,
  candidate adoption, deferred GeometryReader scope, retired binding guards,
  queued transactions, and accounting. They do not establish general native
  SwiftUI lifetime. See [MountedState.md](MountedState.md).
- Quick also runs `MountedStateObjectInstallationTests`,
  `MountedStateObjectLifecycleTests`, and `MountedStateObjectObservationTests`.
  These exercise lazy factories, mounted owner/slot identity, discarded and
  reentrant candidates, multi-window isolation, retired projections, and
  projection-only observation. Supplied object aliases and the standalone
  cache retain their documented behavior; native SwiftUI lifetime comparison
  and App/Scene ownership remain separate qualification work.
- Sharded `-Filter` target selection uses class-name substring/wildcard
  matching before it builds XCTest filters. Pass explicit class names joined
  by `|`; do not assume a regular expression such as `MountedState.*Tests`
  selects every intended source class. Check the reported targets and case
  counts, including accidental suffix matches such as `GeometryTests`.
- `UndoManagerTests`, `TextInputUndoTests`, `TextInputUndoSessionTests`,
  `TextInputConstructionLifetimeTests`, `TextSelectionIndexSafetyTests`, and
  `SheetContentIdentityTests` and `ItemSheetStateIdentityTests` gate Quick, covering target/replay lifetime,
  automatic editor history, and background editor identity through Boolean and
  item sheet presentation, fresh versus retired editor adoption, and safe
  selection handling after the bound text changes. Item-sheet cases also check
  same-ID state retention, changed-ID and dismissal/reopening retirement, and
  escaped bindings without conflating presentation identity with description tags.
  `PresentationActivityTests` and `SheetDismissActivityTests` separately gate
  accepted dismissal authority, inactive and provisional presentations, deferred
  GeometryReader adoption, reentrant getters/focus, and close-time revocation.
  These headless checks distinguish retained State from active presentation
  authority; they do not establish native window or SwiftUI lifetime parity.
  `WinSwiftUIBitmapStretchTests` covers ordinary bitmap
  stretch through layout, CPU scene/frame output, and D3D11. Full includes them all.
- Quick and Full run the material diagnostic classifier's synthetic self-tests through `macos-reference-renderer`. These do not render native material on Windows or replace macOS capture, reviewed comparisons, or the unresolved material-backdrop regression.
  The self-tests also cover the optional fixed unattached/attached hosting
  experiment, per-arm controls, checkpoint failures, and policy restoration.
  The original canonical capture matrix and classifier remain separate.
- Quick and Full run the bitmap font attribution collector's synthetic suite;
  Quick additionally includes the five bitmap attribution XCTest suites for
  context propagation, callback ownership, cache receipts, bounded metadata, and
  font-stream ownership and read limits.
  These do not fingerprint loaded glyph bytes or qualify a font profile. Actual
  off/on retained renders and selected DirectWrite face observations remain
  separate checks; see [BitmapFontAttribution.md](BitmapFontAttribution.md).
- Both modes also run `test-ci-bitmap-font-attribution.ps1`. Its synthetic
  process and filesystem fixtures check the advisory hosted handoff, bounded
  log capture, executable and source matching, and separate pixel/attribution
  outcomes. They do not run native rendering or hosted CI. The Windows workflow
  preserves its original Full result and never rebuilds a stale or missing
  gallery executable to manufacture diagnostic evidence.
- Quick and Full also run the API audit intake, ledger, default bounded
  memory, and workflow handoff fixtures. The pinned macOS capture workflow runs the same four
  scripts before export. These synthetic tests preserve full record scope,
  hashes, rejected inputs, and publication boundaries; they do not establish
  a successful native capture or any API conformance. The opt-in large fixture
  remains separate. See [SwiftUIAPIAudit.md](SwiftUIAPIAudit.md).
- Quick and Full also run `test-swiftui-material-reference.ps1` for bounded
  metadata, source/tool identity, artifact hashes, and consistent control
  classifications. These synthetic fixtures do not decode native material
  pixels; the separate pinned macOS job builds and captures the public fixtures
  with the exact compiler and SDK used for its completed inventory export.
- Quick and Full run `test-swiftui-baseline.ps1` against synthetic exporter
  fixtures. These checks protect pinned-version rejection, inventory parsing,
  and provenance handling; they are not a native SDK capture or API conformance
  result. See [SwiftUIBaseline.md](SwiftUIBaseline.md) for the actual Mac audit.
- Full-repository formatting automatically batches normalized Swift paths to
  stay below Windows command-line limits. The shared Swift/Visual Studio
  bootstrap initializes once per PowerShell process, preventing repeated test
  or lint shards from growing `PATH` until tool startup fails.
- Interrupted sharded debugging can resume with
  `scripts/test.ps1 -Sharded -StartShard <number>`; release validation always
  starts at shard one and executes every discovered target.
- `scripts/test-portable.ps1 -BuildProducts` verifies all four public portable
  package products, builds their isolated Core/Graphics/Layout/Scene targets,
  and executes the independent headless CPU/geometry/layout XCTest target.
  Both Quick and Full run its portable test target separately because the
  Windows-only sharded runner intentionally scans a different test directory.
- `PlatformHostContractTests`, `RenderSurfaceTargetTests`, and
  `BackendInterchangeabilityConformanceTests` verify alternate host lifecycle,
  genuine handle-free surfaces, truthful backend capabilities, safe software
  fallback, and equivalent scene/frame output without importing a concrete GPU
  backend.
- `RenderLifecycleDeliveryTests` and `SceneLifecycleHostTests` exercise scene-only
  appearance, removal and task cancellation, raw snapshots, shared frame/scene
  lifetimes, visibility and deferred paint, callback-driven rebuilds, retained
  dirty flags, active-build deferral, close before backend submission, and active
  task cancellation after State/editor revocation during close and host release.
  Task cases cover latest deferred declarations, duplicate-key suppression,
  ordinary node reinsertion, and rejected launches from close cancellation.
  Positive starts acknowledge the actual probe record with a bounded XCTest
  expectation; a fixed number of cooperative yields is not a readiness barrier.
  Negative deferral and exactly-once assertions remain separate.
  They execute under a cooperative test executor. They do not qualify task
  progress inside the native Win32 message loop, which currently leaves the
  installed Swift 6.3 MainActor queue unserviced. The separate native loop
  experiments and Unicode failure are recorded in `goal.md`.
  The batch host cases do not prime lifecycle by rendering a fallback frame first.
  Quick also runs `RuntimeDirtyFlagIntegrityTests`: a Canvas callback changes
  an already-painted sibling, while a separate appearance callback changes it
  before paint. Both paths must preserve invalidation and then settle.
- `TransitionConstructionOwnershipTests` and `TabViewLifecycleTransitionTests`
  keep construction-time transfers out of the outgoing-overlay lifecycle.
  Both render paths must deliver incoming descendant appearances while real
  outgoing pages fade and disappear. Repeated tab switches and rebuilds during
  a fade must preserve that ownership without restarting the transition. Quick
  includes both suites; the existing demo remount assertion remains unchanged.
- Quick also runs the existing boolean/item sheet dismissal and host environment
  notification fixtures. Dismissal checks descendant content, since the stable
  sheet shell remains to preserve background identity. Notification counters
  use a post-startup baseline and require exact increments and duplicate
  suppression; presenter attachment already performs a counted rebuild.
- `ViewSnapshotTaskLifetimeTests` checks cooperative cancellation and payload
  release for the two bitmap-only snapshot helpers, including actual renderer
  failures. Borrowed runtimes and the runtime returned by the SwiftUI snapshotter
  stay caller-owned and active until caller cleanup. It runs in Quick with the
  lifecycle suites and existing `ViewSnapshotTests`.
- `BackendCompositionContractTests`, `WindowCoordinatorTests`,
  `RenderBackendAvailabilityTests`, and `SoftwarePresentationTests` verify that
  real app composition uses independently injectable platform and renderer
  factories, offscreen-only backends cannot masquerade as window presenters,
  and software fallback actually blits its offscreen CPU output.
- `BindingTransactionTests` covers binding write scopes, projection propagation,
  explicit animation suppression, and state-driven intermediate animation.
  `BindingHostTransactionTests` checks that real controls preserve captured
  transactions through immediate host invalidation and coalesced observation.
  `SettingsSceneHostingTests` covers static/availability scene composition,
  environment propagation, singleton Settings lifecycle, and startup rollback.
  `WindowGroupContentIdentityTests` checks fresh roots per managed/direct window,
  same-window rebuild continuity, inherited environments, Settings reuse, and
  explicit configuration-content replacement.
  `DemoSettingsPersistenceTests` exercises file/memory stores, restart, dirty
  state, malformed data, validation, keyboard save, failed writes, and retry.
  These suites also gate Quick.
- `DemoObservationShowcaseTests` drives the live gallery's observer readouts,
  reset action, and animated binding through the retained host. Two-host tests
  also verify independent derived readouts, late window creation, same-window
  rebuilds, and tab remounts while authored preferences stay shared. Its shared
  view source remains ordinary SwiftUI-shaped application code.
- `ScrollObservationTests` and `WinSwiftUIScrollObservationTests` cover actual
  geometry, phase, and visibility callbacks, presented offsets, reconciliation,
  nested ownership, bounded delivery, clipping, and lifecycle safety. They gate
  Quick; native SwiftUI timing and threshold qualification remains separate.
- `RuntimeProgrammaticScrollAnimationTests` and
  `WinSwiftUIProgrammaticScrollAnimationTests` check captured scroll transactions,
  authored timing, continuous retargeting, input interruption, disabled input,
  range changes, and precise alignment after lazy realization.
  `WinSwiftUIKeyboardProgrammaticScrollTests` verifies that activating a button
  or pressing an unrelated key does not cancel its programmatic scroll.
  `PrepaintSnapshotReplayTests`
  protects cached interaction and paint ranges when clipped subtrees return.
  These suites also gate Quick; synthetic clocks do not qualify native pacing.
- `NativeTextConversionSafetyTests` checks color and geometry sanitation before
  native integer conversion, unchanged normal pixels, and real GDI rasterization.
  DirectWrite text bitmaps use the same corrected tint helper. It gates Quick
  alongside `SceneColorEffectPassTests` and `D3D11ImageRenderPassTests`, which
  cover ordered subtree effects, fractional-DPI coverage, real WARP execution,
  replay/resource isolation, bounded malformed passes, and resource reuse.
- `SceneAtlasLifetimeTests` and `D3D11SharedSceneAtlasTests` also gate Quick.
  They check one completed atlas buffer shared by nested color-effect sources,
  immutable previously returned scenes, nested replay after atlas recycling,
  safe observer reentry, CPU isolation cache retries, and actual WARP upload
  sharing and restoration when a child has a different atlas.
- `RetainedLongPressGestureTests` checks timed recognition, logical movement,
  cancellation, reconciliation, modal scope, and callback reentry using an
  injected clock. `DemoLongPressWindowStateTests` exercises independent window
  attempts and tab remounts, plus a button alternative through keyboard and
  retained accessibility invocation. These do not replace native gesture or
  Narrator qualification.
- `TextEditorReconciliationTests` exercises live hosted rebuilds during editing:
  mid-string insertion, selection replacement, Unicode graphemes, external
  shrinkage, explicit selection overrides, new bindings, IME caret geometry,
  drag anchors, callback-triggered rebuild/removal, and release on host close.
  Related selection, IME, drag, native-input, and sparse-storage suites must
  also pass; these tests do not establish undo or vertical caret behavior.
- `TextInputUndoTests` covers public hosted nonsecure editor history, exact
  undo/redo shortcuts, selection and Unicode, IME commit versus composition,
  disabled/modal scope, shared managers, external replacement, setter reentry,
  removal, and accepted/refused host close. `TextInputUndoSessionTests` covers
  delta payloads, preflight, reciprocal registration, and cleanup races; run
  `UndoManagerTests` alongside both. See [TextInputUndo.md](TextInputUndo.md)
  for the one-edit policy and identity/native-parity limits. These suites do
  not establish typing groups or a document save/dirty workflow.
- `EditorStateOwnershipTeardownTests` combines mounted State with plain and
  mounted editor bindings. It checks ownership revocation before State/undo
  payload release, departure callbacks, and host deinitialization while handles
  survive, plus Unicode/IME replay, keyed editor membership, and current bindings
  after queued rebuilds. Run it with the mounted-State and text-input suites.
- `Win32WindowCloseRequestTests`, `WindowDismissBehaviorTests`, and
  `PlatformHostContractTests` cover close preflight, concrete and neutral vetoes,
  the current retained policy, reentrant decisions, handle lifetime, and
  idempotent teardown. Native cases create owned hidden windows and drain only
  bounded close messages. Failed startup uses an unconditional cleanup hook;
  ordinary dismissal still follows policy. Document save decisions and native
  conflicting-modifier precedence remain separate requirements.
- `AffineImagePlacementTests`, `CanvasSymbolRuntimeTests`,
  `CanvasSymbolSceneTests`, `WinSwiftUICanvasSymbolTests`,
  `CanvasSymbolAtlasLifetimeTests`, and `CanvasPixelFontScaleTests` cover
  resolved symbols, copied graphics state and order, logical coordinates,
  CPU/WARP affine placement, failure markers, atlas ownership, and PixelFont
  spacing. Primitive layout and renderer buffer tests enforce the 80-byte image
  ABI. These tests do not establish native SwiftUI symbol or full layer parity.
- `LiveDiagnosticsAccountingTests` and `LiveDiagnosticsReportTests` cover
  rebuild intervals before/inside a frame, nested reloads, carryover, monotonic
  warmup, phase populations, and schema-2 nulls for missing evidence. Their
  injected clocks prove accounting, not hardware timing. Report tests replace
  window closure with a test callback and never post a process quit message.
- `D3D11GPUFrameTimingCollectorTests`, `D3D11GPUFrameTimingNativeTests`,
  `LiveGPUFrameTimingHostTests`, and `LiveGPUFrameTimingReportTests` also gate
  Quick. They cover bounded nonblocking query polling, issuing-frame identity,
  warmup and eligibility, missing results, device recovery, and tracked COM
  ownership. Native tests use an owned offscreen WARP-first device and a
  readback to complete test work before one bounded drain; production polling
  never waits or flushes. A clock-cost regression keeps metadata lookup and
  polling outside CPU frame timing with collection enabled or disabled.
  These tests do not qualify hardware performance, input-to-present latency,
  display deadlines, or driver-level leak freedom.
- `test-checkout-metadata.ps1` gates Quick, Full, and pinned SDK capture. It
  reproduces unmapped-gitlink checkout cleanup in an owned temporary repository,
  verifies `.gitmodules`, and leaves the reference uninitialized and unfetched.
  Repository-redirection environment variables are rejected before Git runs.
- `ModalPresentationIsolationTests` and `DemoRendererIdentityTests` cover
  topmost modal focus/accessibility/shortcut isolation and renderer identities
  that remain accurate when the app switches between D3D11 and software.
- Existing `ListFormQualityTests`, `DemoProductPolishTests`,
  `DemoInteractivePolishTests`, `DemoResponsiveLayoutTests`, and
  `DemoResponsiveProductPolishTests` also gate Quick so small-list keyboard
  scrolling, minimum-width settings, inherited appearance, unclipped labels,
  responsive breakpoints, and legacy dashboard workflows cannot regress behind
  newer virtualization or product features.
- `DemoShowcaseNavigationTests`, `DemoGalleryResponsiveTests`, and
  `DemoGalleryStatePersistenceTests` gate the shared-source interactive
  Gallery destination, global gallery shortcuts, searchable categories,
  responsive 640-point layouts, accessible controls, adaptive light/dark
  presentation, and model-owned state that survives real retained-host
  rebuilds. `ScenePrimitiveScaleInvarianceTests` and
  `FramePathDegradationTests` also cover every demo destination so the gallery
  remains usable at multiple display scales and on the frame fallback.
- Do not leave root-level logs or screenshots behind. Generated screenshots belong under `artifacts/`, and temporary logs should be deleted before handoff.

Focused test runs:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Filter RetainedViewRuntimeTests
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Filter WinSwiftUIWindowHostTests
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Filter GPUISceneTests
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Filter TraversalStackHeadroomTests
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Filter Win32TextInputTests
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Filter WinSwiftUIEnvironmentConsistencyTests
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Filter DraggableFocusRoutingTests
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Filter GradientRenderingFidelityTests
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Filter PathGradientRenderingTests
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Filter CanvasPathGradientIntegrationTests
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Filter RuntimeProgrammaticScrollTests
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Filter WinSwiftUIScrollViewReaderTests
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Filter ClipboardFileFormatTests
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Filter DropFilesPayloadHardeningTests
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Filter DemoProductPolishTests
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Filter DemoResponsiveProductPolishTests
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Filter SceneBoundaryResilienceTests
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Filter D3D11TransparentCompositingTests
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Filter D3D11ImageBindingLifetimeTests
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Filter WinSwiftUIBitmapStretchTests
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Filter Win32PointerMessageRoutingTests
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Filter Win32NativeFileDialogSafetyTests
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Filter FileDocumentExportTests
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Filter FileDialogIntegrationTests
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Filter WinSwiftUITouchInputRoutingTests
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Filter RetainedInteractionLifecyclePolishTests
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Filter AccessibilityProjectionRuntimePolishTests
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Filter WinSwiftUIDisabledAccessibilityInvokeTests
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Filter ModalAccessibilityActionTests
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Filter UIACurrentElementMutationTests
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Filter AccessibilityProjectedActionLifetimeTests
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Filter WinSwiftUIDynamicTypeRangeTests
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Filter WinSwiftUIControlUsabilityTests
```

`ModalAccessibilityActionTests` contains 32 headless async cases for copied
actions and the live UIA source. The late focus notification and focus-request
completion/cleanup fixtures witness paint-only modal reordering, rejection of
the stale explicit or fallback route, and recovery after an independent layout
query. These cases do not create HWNDs or qualify disconnected COM delivery,
Narrator, or native activation-character routing.

`UIACurrentElementMutationTests` adds 10 headless async cases for Invoke,
Toggle, Select, AddToSelection, and RemoveFromSelection. The cases change
roles and selection during layout, exercise current-state no-ops, reject
modal/terminal/removal/disabled targets, and check shared reentry protection
and the absence of a second action query. They preserve the existing 32
modal-action cases and do not exercise native COM delivery.

`AccessibilityProjectedActionLifetimeTests` adds two headless async cases for
copied named/default actions whose last external runtime owner disappears
during layout or the admitted handler. They check temporary retention through
the handler, terminal rejection through another projection scope, release
after return, and inert stale repeats. They do not create a UIA source or
qualify native provider disconnection.

`FileDocumentExportTests` performs real filesystem writes in unique test-owned
temporary directories. It checks document round trips, atomic replacement,
preservation on encoding and write failures, cancellation without completion,
latest-document reconciliation, reentrant/chained presentation, and explicit
unsupported-representation errors. The read-only destination fixture restores
its original attributes before cleanup. Exporter mocks must never return
hardcoded user or example save destinations; migrate them before enabling a
new write path. See [FileDocument export](FileDocumentExport.md) for the
implemented boundary and remaining parity work.

`TraversalStackHeadroomTests` covers construction and retained traversal: it
builds a 60-level public VStack/padding hierarchy and renders a retained tree
at `ViewNode.maximumTraversalDepth` (256). If a frame grows past the native
stack budget, the test process can exit with code 1 after a case starts,
without reporting an assertion failure. Windows Error Reporting or a crash
dump can confirm exception `0xc00000fd` (stack overflow). Run this suite after
changes to component construction, context scopes, `layoutSubtree`,
`sizeThatFits`, `appendPrepaintState`, or `appendCommands`; a silent abort is
not a passing or flaky test. Do not reduce the depth or enlarge the executable
stack to hide a regression.

`ViewBuildContextScopeTests` checks synchronous nested/reentrant restoration,
value-copy isolation, and provider-payload release. Context scopes retain
private immutable boxes so nested construction saves references instead of
complete context values. The API remains main-actor, synchronous, and
nonthrowing; this storage choice adds an allocation per scope and is not a
performance qualification. Quick runs both suites together.

On Swift for Windows, filtering the very large `WinSwiftUITests` XCTest class can fail in the runner with Windows error 206 (`NSCocoaErrorDomain Code=258`). Use full `swift test` for that coverage, or filter narrower XCTest classes such as `WindowGroupInitTests`, `CommandsAndSceneTests`, or `ClipboardButtonTests`.

Place new text, geometry, composite-control and animation regressions in the
existing `WinSwiftUITextTests`, `WinSwiftUIGeometryAndFocusTests`,
`WinSwiftUICompositeTests` and `WinSwiftUIVisualModifierTests` suites. Adding
more methods to `WinSwiftUITests` can also exceed the Swift compiler's type
checking budget for its generated test-discovery array.

## GPU Tests (WARP)

Every test that touches real D3D11 goes through the one harness in
`Tests/SwiftWindowsCoreLogicTests/WARPRenderHarness.swift`. It creates the
device WARP-first (the software rasterizer ships with every Windows install
and rasterizes deterministically across machines) and falls back to
hardware; when neither exists the helpers throw `XCTSkip`, so a machine
without D3D11 reports skipped GPU tests rather than failures.

Two levels:

- `makeWARPDevice()` plus `makeWARPOffscreenTarget(...)` / `readWARPPixels(...)`
  drive a single component against a bare `ID3D11Device` —
  `D3D11BackdropBlurTests`, `D3D11GlyphShaderPixelTests`.
- `WARPBatchRenderer.render(_:size:)` drives the real `D3D11BatchRenderer`
  frame path with no HWND, via `attachOffscreen(size:driver:)`, and reads
  the frame back. It caches one attached renderer for the whole test process
  (attaching compiles a dozen shaders), so scenes that bind images must use
  distinct texture IDs.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Filter "CrossBackendPixelParityTests|D3D11BatchRendererRenderTests"
```

- `D3D11BatchRendererRenderTests` — execution coverage for attach / resize /
  render / present: a 64→1920→1→4096 resize storm, zero-size and negative
  frames, repeated-frame stability, clear colour, and the typed error a
  glyph scene with no atlas must produce. Also the image-texture cache's
  live-set bound: content that changes every frame under one texture ID
  (an animating `.drawingGroup()`) keeps exactly one live texture, while a
  frame that renumbers its texture IDs keeps both and re-uploads neither.
- `CrossBackendPixelParityTests` — canonical scenes rendered through both
  the D3D11 batch backend and `GPUIRawSceneRasterizer`, asserting at most 4
  per channel over at least 99.5 % of pixels. Scenes the backends genuinely
  disagree on are present and asserted against a **measured match-ratio
  floor** rather than skipped: they fail if they drift below the recorded
  ratio, and they also fail with "promote me" if they reach the required
  ratio and should be gating like the rest. Re-measure a floor only when a
  deliberate change moves it, and record the new value with the reason; see
  `docs/GPURenderingPipeline.md` § 7 for the current divergence list — which
  is **empty**: every scene gates at the standard ratio since WS-18 gave the
  CPU rasterizer the shaders' bilinear sampler. Fixtures for the sampler
  families are deliberately hostile: a uniform opaque atlas cell or a gentle
  image gradient cannot observe a filtering difference at all, so the suite
  keeps an 8× magnified alpha ramp and an 8× magnified checkerboard whose
  only signal *is* the filter. WS-08b added eight stroke scenes — a thick
  open polyline with each of the three caps, a sharp corner with each of
  the three joins, the same corner with a miter past its limit, and a
  round-capped polyline taken through the tessellator so the cap is a
  `cornerRadius` rather than a coverage polygon. All eight gate at the
  standard ratio.
- `PixelFormatContractTests` — the `BitmapSurface` format contract: the
  named default (BGRA, straight), the straight ↔ premultiplied conversions
  and their opaque fast path, the validation that rejects a truncated or
  under-strided surface before it reaches `CreateTexture2D`, and WARP
  readbacks proving red stays red, a half-transparent image composites to
  mid-gray, and an already-premultiplied surface is not multiplied twice —
  each cross-checked against `GPUIRawSceneRasterizer`.
- `AtlasUploadProtocolTests` — the atlas and texture upload protocol: the
  pure decision table (`skip` / `region` / `full`, including a fresh
  texture always taking `full` and a region only applying to the version
  it was computed against), the producers' content versioning, and the
  real upload counts on WARP — frame 1 fresh = one full upload, frame 2
  unchanged = zero, frame 3 with a small region = one boxed upload. Also
  pins image texture/SRV pointer identity across rebinds and across a
  frame that renumbers the texture IDs.
- `SceneAtlasLifetimeTests` and `D3D11SharedSceneAtlasTests` extend that protocol
  across nested scene namespaces. Image-only ancestors bind the completed
  atlas so descendants can borrow the same GPU texture. Retained replay copies
  release atlas pixels recursively and track descendant native glyph usage
  when invalidating stale UVs. Keeping old returned frames can still retain
  one atlas buffer per frame; these tests do not establish a total RAM bound.
- `GlyphAtlasExhaustionSafetyTests` — an atlas rect handed out before a
  recovery addresses a different glyph after it, so no holder of one may
  outlive the recycle: the generation token only moves when shelves are
  recycled, a pass that recycles mid-flight re-emits its UVs, a working set
  larger than the atlas degrades to the pixel font instead of shipping UVs it
  cannot vouch for, the suspension does not outlive the degraded frame, and a
  runtime's *cached scene* is dropped when another window recovers the shared
  atlas under it (a clean window never repaints on its own, so the token is
  the only thing that can force it). Since P2F-GATES it also pins the *cost*
  of the narrower invalidation: reusing a cell eviction returned is not a
  recycle, so a full atlas taking one new glyph per frame costs zero
  discarded passes (it was one per frame), the frame after a reclaim runs
  with replay disabled from the start, and the one intra-pass aliasing case —
  freeing a cell this pass already drew from — still discards the pass.
  Gates Quick.
- `RenderBackendLifetimeTests` — GPU resource lifetime: `detach()` empties
  every stored COM pointer, the image map and the path cache; attach →
  detach → attach round-trips draw the identical frame on a fresh device;
  repeated cycles do not accumulate; and the host calls `detach()` on
  window close and on both directions of a presenter switch, always before
  the incoming backend claims the HWND. Attaches its own WARP renderer
  rather than the shared `WARPBatchRenderer`, since it destroys the device.
- `DeviceLostPolicyTests` — the HRESULT classifier and retry schedule, with
  no GPU involved: device-lost codes, `DXGI_STATUS_OCCLUDED` as throttle
  rather than clean present, permanent vs transient, bounded monotonic
  backoff, and each backend error type classifying itself for the host.
- `DeviceLossRecoveryTests` — the rebuild itself, driven through
  `simulateDeviceLossForTesting()` on an offscreen WARP renderer: a new
  device generation, the target rebuilt at the same size with matching
  pixels, a bounded budget that surfaces a typed `.deviceLost` failure, a
  clean present refunding it, and the backdrop-blur engine keyed on
  generation rather than device address. Attaches its own renderer and stubs
  the recovery wait, so the suite does not sleep.
- `PresentationFailurePolicyTests` — the host half: the failure kind reaches
  `RendererHealthSnapshot`, a `.permanent` failure schedules no recovery, an
  unclassified error keeps the historical transient behaviour, and a backend
  reporting `needsImmediateRepaint` keeps the frame loop alive.
- `SoftwarePresentationTests` — the GPU-less startup path end to end through
  the host seams: the substituted software backend actually blits a frame
  (right size, right clear-colour bytes, right client size) instead of
  rasterizing into memory, `render` never returns without presenting, a failed
  blit reaches the fallback policy and health rather than reading as a healthy
  scene session, and `RendererHealthSnapshot.backendResolution` separates
  healthy hardware from WARP from a substituted factory. Includes one real-HWND
  `StretchDIBits` blit, skipped where a top-level window cannot be created.
- `FrameClockPacingTests` — the frame clock and the pacing floor: the clock is
  monotonic and resolves inside a system tick, the floor sits strictly below
  the vsync period, a 15.625 ms-quantized tick sequence renders ≥ 55 frames per
  simulated second at 60 Hz, two rebuilds cannot share one vsync interval, and
  `WM_PAINT`-driven frames carry the host clock rather than `0`.
- `BatchRecoveryBackoffTests` — the recovery ladder: 5 → 10 → 20 → 40 → 60 s
  carried across downgrades instead of resetting, retired only by a sustained
  run of presented scene frames, with a `.sceneContent` failure never retried
  against an unchanged tree and `.permanent` scheduling nothing.
- `WindowConfigurationDPITests` — window creation and configuration: creation
  geometry linear in DPI and independent of the frame inset, the logical root
  equal to the requested size at 2×, one clamped effective scale for every
  consumer (hit testing round-trips at 0.75), track sizes / fixed size /
  placement / level translation, a 100-message drag costing ≤ 1 display-mode
  query, and an unchanged appearance snapshot triggering no reload.
- `ClipAbstractionTests` — the one clip value and the one space it lives in:
  the narrowing rule (anchored rounding, cut corners squared, an empty clip
  distinct from an absent one, per-corner radii floored like the uniform
  scalar), both halves of the in-band encoding (`encode` emits `emptyExtent`
  for a collapsed rect instead of the all-zero *absent* sentinel), rounded
  clips reaching the glyph / image /
  shadow / path families, and clip-space coherence under a transform — the
  interactive region of a rotated clip pixel-for-pixel equals its painted
  region, a deferred subtree under a translating clip paints where its clip
  moved, the frame path's border gate is the frame it paints, every clip
  prepaint records is `.painted`, and a rotation nested inside a translated
  and scaled ancestor survives on the frame path — the case a single
  transform hides, because only there do "the node's own transform" and "the
  accumulated transform" differ.
- `TransformLoweringTests` — the transform algebra, from both ends. Rotation
  lowering: a rotated card emits its *unrotated* rect plus
  `rotationRadians`, a uniform scale rides along, and shears / mirrors /
  non-uniform scales fall back to the bounding box (rotation exactly `0`, so
  the historic bytes are unchanged); the border ring turns with the node it
  surrounds; a rotated quad is accepted by the scene contract on its rotated
  footprint, where the unrotated one is rejected. Composition order:
  hand-computed absolute placements for nested translate+scale and
  translate+rotate on the scene path *and* the frame path, plus the pointer
  landing where the content is painted — agreement alone would have kept both
  paths wrong together. Plus the replay key (a half-turn of a square ancestor
  leaves every bounding box unchanged and still has to repaint) and the two
  places the frame path resumed in the wrong state: a canvas drawn from its
  painted origin, a deferred subtree resumed with its inherited blend mode.
- `TransformReflectionTests` — a reflection stays one. `Transform2D`'s
  decomposition is an exact round trip (mirrors carried as a negative scale,
  shears no longer growing by `sec(skewX)` per composition), so a mirrored
  container places its child *across* it rather than upside down on both
  paint paths, the pointer finds that child where it is painted, an
  interpolation to a mirror flips rather than tumbles, and `PaintPlacement`
  still degrades the reflection it now actually receives to its bounding box.
- `ScrollIndicatorTransformSpaceTests` — the two spaces a scroll indicator
  lives in: thumb length is the layout-space visible fraction, thumb position
  and drag rate are painted space, and the untransformed geometry every other
  indicator test pins is unchanged.
- `ScenePresentationOrderTests` — the single draw-order authority, plus
  replay integrity at the painter: a range rejected rather than trapped, a
  rejection answered by repainting instead of caching the emptiness, a
  subtree wrapped and then unwrapped from a `drawingGroup` replaying its own
  primitives rather than whatever moved into its old indices, and a fully
  replayed text frame CPU-rasterizing to the same pixels as the frame it
  replays (it has to ship the atlas its glyph quads address, even though it
  rasterized no glyph). Also the cost of the ordering machinery: a paint
  record stays a reference rather than a second copy of the primitive, and
  sealing plus planning a 5,000-quad / 10,000-glyph scene stays under an
  eighth of what inserting the same primitives cost — a *relative* budget,
  so a slow runner moves both sides together instead of flaking. It rejects
  even one heap allocation per primitive in the sealed phase, so the retired
  per-primitive sort in `finish()` cannot come back unnoticed.
- `TextMeasurePaintFidelityTests` — measured width == painted width for
  native text at fractional scales, and the same equality for *tracked*
  text, where measurement and painting have to count the same inter-glyph
  gaps. Its combining-mark fixture asserts that it still shapes into a
  different glyph count than character count, so it fails loudly rather
  than passing for the wrong reason. It also counts DirectWrite shaping
  probes: a second pass over the same tracked paragraph must shape nothing,
  because the gap-count memo outlives one `layout` call — and measure ==
  paint is re-asserted with the memo warm, since a mis-keyed memo shows up
  as a width off by whole tracking steps.
- `TextShapingPipelineTests` — WS-17's pipeline end to end: shaped glyph
  identity (a real `DWRITE_GLYPH_RUN`, not a per-character hit-test walk),
  the two glyph coordinate frames and the raster declaring which one it
  measured ink from, the `Double → Int32` conversions that return `nil`
  instead of trapping on a non-finite frame, `FontFaceRegistry` handing out
  stable monotonic identifiers and reporting when its retained set stops
  being bounded, tracking moving measurement and paint together, and the
  galloping wrap probe staying linear on a 20,000-character space-less
  paragraph. It also pins the shaping capture's pixel-snapping contract —
  snapping disabled, exactly one DIP per pixel — and that a shaped glyph's
  `origin.y` is the line's baseline, not its top. Those two were the
  intermittent, process-dependent text failures: the capture renderer used
  to answer DirectWrite's `GetPixelsPerDip` out of the wrong client context
  struct, so DirectWrite snapped whole lines against uninitialized memory.
  A text failure that reproduces in some processes and not others, or only
  when other suites run first, is that shape of bug — suspect the seam, not
  the harness. Needs a real DirectWrite; the cases that would silently pass
  without one assert the layout came back first.
- `SharedCoverageKernelTests` — `GPUIQuadCoverage`, the one Swift
  transcription of the quad shader's coverage math, compared on a dense
  sample grid against a *third* copy transcribed line-by-line from the HLSL
  in the test itself. Uniform and per-corner radii, the box-SDF ramp a
  square quad must get (there is deliberately no `radius == 0` short
  circuit), the rasterizer's own centre-coverage rule, and a rounded clip
  producing fractional alpha where an exact rect rejection would not.
  Editing one side of the pair without the other fails here; that the pair
  matches the *running* shader is pinned by `CrossBackendPixelParityTests`.
- `CPURasterizerGPUModelTests` — what the reference renderer models: the
  shadow envelope and falloff, the material composite and its shared blur
  cap, `luminanceToAlpha` ordering, the glyph sampler's alpha convention
  (coverage is `.a`, exactly as the shader reads it), and texture filtering
  — a magnified glyph must ramp rather than staircase, a 1:1 glyph must be
  bit-for-bit what nearest sampling produced, and image filtering must
  interpolate *premultiplied* texels so a transparent neighbour cannot
  darken an opaque one.
- `CacheComplexityAndReclamationTests` — the render path's caches as
  *caches*: warm lookup work that does not scale with cache size — 3,000
  lookups against a full 4,096-entry cache visiting zero entries linearly,
  the same at 64 entries, counted through
  `GlyphAtlasCache.scannedEntriesForTesting` rather than timed (see the rule
  at the top of `docs/PerformanceBudgets.md`; a third case pins that the
  counter can still see the one legitimate scan, eviction's) — eviction
  returning atlas space to a per-shelf free list instead of marching the
  frontier into a full `clear()`, free-span coalescing and double-free
  rejection, the generation bump that must accompany reclaimed-space reuse
  and *only* that (and that it is **not** a `recycleGeneration` bump), the
  rewritten region still reaching the upload protocol, intra-frame recency
  ordering, and the two caches that were dead or unbounded —
  `TextRasterCache` (now what `Controls.icon` *and* the frame path's
  whole-string rasterization go through, keyed apart by device scale on both
  routes) and `NativeFontAvailability`'s probe cache.
- `PathRasterizationQualityTests` — path fill and stroke quality, which is
  not a fallback-only concern: the D3D11 path texture cache calls
  `GPUIRawSceneRasterizer.rasterizePath` and uploads the result, so this is
  the shipping appearance of `Canvas`, `Shape` strokes, chart lines and the
  SF-symbol vector fallback. Implicit per-subpath closure (SwiftUI's fill
  semantics), non-zero winding on a self-overlapping shape, fractional
  coverage on a diagonal edge, a translucent polyline never exceeding its
  single-segment alpha, no gap at a thick join, a stroke *not* closing an
  open subpath, and the path clip rejecting per pixel centre. Since WS-08b
  it also pins cap and join *geometry*: a butt cap stopping at the
  endpoint, a round cap reaching half a line width as an arc, a square cap
  reaching the same distance squarely, the miter spike, the round join's
  radius, the bevel's chord, a miter past its limit being pixel-for-pixel a
  bevel, and a closed subpath ignoring its cap entirely.
- `StrokeStyleContractTests` — `StrokeStyle` as a contract rather than a
  suggestion: the primitive's defaults, the scale invariance of
  `miterLimit`, the sanitizer's bounds on it, the shared
  `StrokeOutlineGeometry` rules (miter ratio, limit resolution, join
  visibility, bounds outset), each lowering that used to keep `lineWidth`
  and drop the rest (`Canvas` stroke, shape outline, frame
  `StrokePathCommand`, scene bridge), and the agreement between the
  promoted-to-quads and CPU-rasterized routes for the styles both can draw.
  Since P2F-PATH it also pins `effectiveMiterLimit`: a corner sharper than
  the bounds ratio bevels rather than drawing a spike past the `bounds`
  that sized its own raster.
- `PathDashingTests` — dashes as geometry, resolved before the path
  contract. The walk itself (even spans, phase offset, an odd pattern
  doubling, a dash keeping the corner it spans, a fine pattern on a curve
  staying bounded) and the three lowerings that used to drop
  `dashPattern` outright: a `Shape` outline arriving as a
  `backgroundPath`, a `Canvas` `strokePath`, and the frame-path bridge.
  `BorderSegments` still owns the rect and rounded-rect case.
- `D3D11PathCacheTests` — the path raster cache. Translation invariance
  and the digest key that replaced a per-frame translated copy, that two
  shapes with the same extent stay two entries, that a huge path inside a
  small clip rasterizes bounded (and still hits while scrolling inside one
  tile), and that a raster too large for the byte budget is denied a slot
  rather than flushing every other entry. Needs a D3D11 device; the
  device-backed cases `XCTSkip` without one.
- `RenderPassAbstractionTests` — the render-pass vocabulary
  (`RenderTargetDescriptor`, `RenderPassDescriptor`, `SubTextureRegion`,
  `BlurPassPlan`) and the two things it exists to prevent: a sub-texture
  tap that reaches outside its region (the grow-only ping-pong pair's
  stale texels), and a blur schedule the two backends compute differently.
  Also covers the **halving rule** — that the span a 2× reduction reads is
  exactly twice the output extent, so every tap lands on a texel boundary
  at odd extents too; that the CPU drops the same trailing column the
  GPU's UVs never reach; and that the blur shader still maps viewport to
  UV the way the tap model assumes. Plus the downsample chain — invisible
  across its threshold, still honouring the radius, and agreeing across
  backends at the suite parity floor both at quarter resolution and over
  an odd (5 device pixel) region. Carries two recorded residuals as
  `XCTSkip`s: rotated clipping, and a Material inside a `drawingGroup`
  having no backdrop to blur.
- `ContentBlurRenderPassTests` — `.blur()` as an **isolated** content
  blur: one pass over 50 backgrounded rows rather than 50 backdrop blurs,
  a Material background that does not frost the cards inside it, nested
  blurs as independent passes, the device-scale radius sizing the pass,
  the regression that matters (a blurred label whose glyphs actually
  change), and the two isolation properties — blurring a view that paints
  nothing leaves every pixel of the render identical, and the wallpaper
  around a blurred badge stays sharp. Also pins that a pinned section
  header inside a blurred subtree is drawn *inside* the pass rather than
  sharp on top of it by the deferred phase, and that an unchanged blurred
  subtree reuses its bitmap instead of re-blurring per frame.
- `LazyStackVirtualizationTests` — `.lazyStack`: rows the viewport plus
  overscan cannot reach skip their recursive layout, an eager `VStack`
  and a lazy stack with nothing scrollable above it skip nothing, the
  virtualization window follows the resolved scroll offset, and the
  virtualized list is **pixel-identical** to the eager one both before
  and after scrolling — including with a plain panel between the scroll
  view and the stack, the shape a scroll dirties *around* and where a
  stack that is never reached leaves rows painting at stale geometry.
  Also pins the integrity properties: layout **visits** (not just skips)
  stay proportional to the viewport at 5,000 rows, a deferred row projects
  to accessibility as one flagged placeholder with its real bounds rather
  than a subtree of zero-size rectangles, reconciling a lazy stack into an
  eager one stops charging every later scroll a layout pass, and `onLayout`
  is published only for rows within range — the semantic that keeps `List`
  out of virtualization.
- `PerformanceBudgetGateTests` — since WS-20 it bounds *work*, not only
  scene size: render-plan draw-step counts for the demo screens (with a
  minimum primitives-per-step ratio, so a batch that breaks shows up), a
  second identical render uploading no atlas bytes, blur passes for a
  blurred 50-row subtree, layout work for a 500-row lazy list, layout
  **visits** for a 5,000-row one (a skip counter cannot tell "skipped the
  descent" from "still walked every row"; a visit counter can), and the
  node count for a 500-row list, which pins the O(rows) construction cost
  virtualization does *not* remove. Structural counts only — the suite
  still asserts no wall-clock time.
- `BorderCornerArcGeometryTests` — the corner-arc geometry `BorderSegments`
  emits for a rounded border, measured in all four quadrants rather than
  the one whose maths was right. The annular-sector bounding box used to be
  computed as if the ring's outer edge always lay at `+x`/`-y`, so three
  corners came out narrower than the ring by the border width and the
  sub-boxes nearest the straight edges inverted and were dropped: a rounded
  border on a container with children rendered thin or gapped. Asserts ring
  coverage at each 45° midpoint, the arc union spanning the whole corner
  square, areas and counts agreeing across quadrants, no sub-arc inverting,
  and full-width and dashed borders still emitting every corner.
- `CPUGPUBlendModeContractTests` — source-over, and only source-over, on
  **both** paths: every mode rasterizes as `.normal` on the scene path and
  on the frame path, a `.multiply` overlay matches on WARP, and the mode
  still survives onto `QuadPrimitive.blendMode` — through the painter and
  through `GPUISceneBridge` — so the decision stays reversible. Landing the
  opposite decision means implementing the modes on the GPU and deleting
  this suite.
- `SystemAppearanceTests` — sampling, the mapping tables, and the
  settings-change routing: the generic high-frequency broadcasts
  (environment, policy) are filtered when the four-field snapshot did not
  move, while metrics/font/theme/locale broadcasts and `WM_SYSCOLORCHANGE`
  reach the delegate unconditionally — they change what the app draws from
  and the snapshot does not carry them. Every route re-samples, filtered or
  not, so a filtered broadcast never leaves a stale snapshot cached. It also
  covers the hostile side of `WM_SETTINGCHANGE`: `lParam` is a pointer only
  by convention and is marshalled only for the `SendMessage` family, so any
  process can `PostMessage(HWND_BROADCAST, …)` an arbitrary value into it.
  `Win32Window.settingChangeSection` validates the address with
  `VirtualQuery` before reading it — null, misaligned, reserved-but-
  uncommitted, `PAGE_NOACCESS` and a name running off the end of a committed
  page all classify as "no section" rather than faulting the UI thread — and
  the tests drive each of those through `VirtualAlloc`. A `wParam` allow-list
  is deliberately *not* the gate: `ImmersiveColorSet` arrives with
  `wParam == 0`, so allow-listing would drop the dark-mode switch while
  leaving the forgeable case dereferencing a raw address.
- `IconDisplayScaleTests` — icon rasterization at a requested scale, scale-1
  byte-identity, and who may write the process-global
  `NativeTextRenderer.defaultIconDisplayScale`: the sole live host writes it
  on activation and on every resize, a second live host cannot stomp it, and
  claims are weak so a closed window releases it.
- `FocusRingAndDensityTests` — three claims the pixel gates could not see.
  A focus ring is an **annulus**: both the 2pt focus effect and the wider
  chrome outline used to fill their whole outset rect and rely on the control's
  border and fill to cover all but the margin, which holds only while those are
  opaque — the macOS palettes are translucent, so the accent showed through the
  body and a focused bordered button rendered accent-blue (in macOS terms, a
  different control). A rotated node's shadow is **culled where it actually
  falls**: the cull footprint has to turn the shadow offset the same way the
  emission does. And the snapshotter's `size` is **points**, so a HiDPI render
  needs a `size × scale` surface — see the HiDPI section below.

Test runs never write images into the source tree: `check-contracts.ps1`
fails if a `ReferenceImages` directory appears under `Tests/`. Reviewed
baselines live in the gallery gate and the golden-hash suites.

Visual checks:

- `scripts/demo-probe.ps1` launches the demo long enough to record presenter selection, then exits.
- `scripts/demo-screenshot.ps1` builds the shared demo view through `WinSwiftUIRendererSnapshotter`, pulls the raw retained runtime scene, rasterizes it offscreen, and writes `artifacts/demo-screenshot.png`.
- Add `-Screen dashboard`, `-Screen settings`, `-Screen data`, or
  `-Screen gallery` to capture one specific demo destination without rendering
  the other screens. `-Screen` and `-AllScreens` are mutually exclusive.
- Add `-AllScreens` to `demo-screenshot.ps1` to capture all four demo tabs in
  one run: `artifacts/demo-screenshot-dashboard.png`,
  `artifacts/demo-screenshot-settings.png`,
  `artifacts/demo-screenshot-data.png`, and
  `artifacts/demo-screenshot-gallery.png`. Default behavior (a single dashboard
  shot) is unchanged.
- The underlying `swift-windowsui-snapshot` executable also accepts
  `--screen <dashboard|settings|data|gallery>` to render any destination
  directly; the default is `dashboard`.
- `--appearance <light|dark>` (and `-Appearance` on `demo-screenshot.ps1`) wraps the demo in `.preferredColorScheme(...)`. Light-mode runs write `artifacts/demo-screenshot-<screen>-light.png` so both appearances can be captured side by side; the default is `dark`. Before this flag existed there was no way to render light mode at all, which is why control chrome could silently ignore `colorScheme`.
- Add `-FrameDebug` to either command to force the `RenderFrame` fallback path.
- `demo-screenshot.ps1` does not depend on desktop window visibility, monitor placement, or foreground focus. It also leaves the raw BMP source next to the PNG as `*.raw.bmp` for inspection.

#### HiDPI (true 2x) snapshots

`swift-windowsui-snapshot` keeps two sizes, related the way the host relates
them (`WinSwiftUIWindowHost.logicalSize(for:scaleFactor:)`): **pixel = logical
× scale**.

- `--width` / `--height` are the surface in **device pixels**; the window is derived as `pixels / scale`.
- `--logical-size <WxH>` is the window in **points**; the surface is derived as `logical × scale`. Mutually exclusive with `--width`/`--height`.
- `demo-screenshot.ps1` exposes the same pair as `-LogicalWidth`/`-LogicalHeight`. A non-1 `-Scale` suffixes the output (`…-2x.png`) so the HiDPI and 1x renders sit side by side instead of overwriting each other.

```powershell
# A true 2x render of the same 1280x720-point layout the 1x shots use.
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/demo-screenshot.ps1 `
    -AllScreens -LogicalWidth 1280 -LogicalHeight 720 -Scale 2
```

Before this split, `--width`/`--height` fed *both* the runtime root size and
the surface, so `--scale 2` laid the app out at 1280×720 points and then
rasterized it into a 1280×720 **pixel** bitmap — a 2x magnification of the
top-left quadrant, not a HiDPI layout. Nothing about layout at density was
verifiable. `FocusRingAndDensityTests` pins the underlying contract:
`WinSwiftUIRendererSnapshotter.snapshot(size:)` is points, device geometry
scales by the display scale, and a scale-2 scene therefore does not fit in a
`size`-sized surface. It also pins the macOS hairline rule — a `Divider` stays
**one device pixel** at every scale, while a 1pt border scales with it.

Note that the frame path (`--mode frame`) is point-space: `appendCommands`
takes `displayScale` only to pick a text raster scale and both frame renderers
blit its commands 1:1, so a HiDPI frame snapshot fills only the top-left
`logical` region of the surface. The tool warns when `--mode frame` is combined
with a non-1 scale; use the scene path for density renders.

## Responsive Layout Gate

`DemoResponsiveLayoutTests` sweeps the dashboard shell across every window
width and height the app can be dragged to. The demo's three columns used to
be laid out at fixed widths whose sum never consulted the window: at 640 pt of
window they asked for 964, the layout engine answered by driving all three past
their shrink floors, and the window filled with ellipses beside a hero card
whose action pills had been squeezed from 38 pt tall to 0.9. What the suite
pins:

- **`occupiedWidth <= size.width` at every swept size**, and the centre column
  never under its 420 pt floor. This is the invariant that was violated.
- **Columns are given up in order.** The detail rail folds first (below
  ~964 pt), the sidebar second (below ~690 pt); a window can never carry a rail
  without a sidebar. The toolbar gives up its search field, then its two status
  badges, before it truncates anything.
- **A fold re-flows, it does not drop.** Every section heading the 1280 pt
  window shows is still somewhere in the 640 pt window's tree — the rail's two
  panels and the sidebar's session rows move into the centre column, and the
  module list becomes a horizontal strip above it.
- **No label is crushed.** No text node ends up under 8 pt tall at any swept
  size. (Truncation itself is resolved inside the painter from a
  `maxContentWidth` and is not recorded on the node, so the tree cannot be
  asked about the ellipsis directly; height is the axis it does carry, and it
  fires on the same cause.)
- **The declared window minimum is a size the shell survives.**
  `DemoWindowMetrics.minimumSize` (640x480 logical client) is the number
  `AppEntry` hands to `.windowMinSize`, so what `WM_GETMINMAXINFO` stops the
  user's drag at and what the layout is tested at cannot drift apart. The suite
  also checks it reaches the physical track size correctly at 96/120/144/192
  DPI — 640x480 logical is 800x600 device at 125 %, not 640x480.

Render the ladder by hand with
`swift-windowsui-snapshot --logical-size 640x720 --screen dashboard` (and
900x600, 1000x700, 1280x720, 1720x980) when changing the shell; 1280x720 and
1720x980 should stay byte-identical unless the wide layout is what changed.

`StackTextShrinkFloorTests` also checks wrapped paragraph heights after explicit
widths, padding and horizontal stack allocation, including CJK and Thai text
without spaces. `DemoGalleryResponsiveTests`
checks visible native glyph bounds after scrolling to typography and validation
examples with enlarged type at fractional display scales. These tests catch
adjacent labels painting over one another even when their layout frames pass
the minimum-height checks. `RetainedViewRuntimeTests` checks rendered scroll
positions during keyboard glides and edge bounce, rather than only inspecting
the animation's numeric offsets.
`RuntimeDirtyFlagIntegrityTests` and `RuntimeProgrammaticScrollTests` verify
that repeated control layout with unchanged frames and borders settles, so
current scroll geometry remains usable without another layout pass.

## Gallery Regression Gate

`scripts/gallery-compare.ps1` turns the `swift-windowsui-gallery` tool into a visual regression gate for Supported-tier controls.

- The full gallery contains **144** rendered examples; the gate covers a fixed
  subset of **85** reviewed entries across three tiers. The roster lives at the
  top of `scripts/gallery-compare.ps1`.
  Time-dependent entries (e.g. indeterminate progress) are deliberately
  excluded because their renders are not frame-stable.

| Tier | Entries | What it pins |
| --- | --- | --- |
| Control and drawing | 42 | Buttons, toggles, sliders, steppers, pickers, progress, typography, semantic labels, grouped/disclosure content, empty states, dashboard/grid compositions, and Canvas gradient/sparkline/donut examples |
| Interaction state | 16 | `state-<control>-<state>` for button, toggle, text field, segmented picker: the idle → hover → pressed → focused → disabled ramps, driven through the runtime's own input |
| Light appearance | 27 | `light-<id>`: control, typography, grouped/disclosure, empty-state, dashboard, and Canvas entries rendered from their same dark twin |

### Interaction-state tier

The hover / pressed / focus / disabled ramps used to be pinned only by unit
tests reading colour fields, so a ramp could go visually wrong with every
assertion still green — which is exactly how a focused bordered button came to
render accent-blue (the focus ring was emitted as a filled slab under a
translucent control fill instead of as a ring).

- Entries are `state-<control>-<state>` for button, toggle, text field and segmented picker. The tool drives the runtime's **own** input entry points — `pointerMoved`, `pointerDown`, and `keyDown(.tab)` — rather than reaching into node state, so what the gate sees is what a user's input produces.
- They are deterministic despite the control animations: after the input, every tween is settled to its end value with `tickAnimations(at:)` at a timestamp far past any start time (both the colour and property tweens clamp progress to 1), and the scene is captured at the same instant. No wall clock enters the render.
- The tool refuses to write a state entry whose render is pixel-identical to its own idle render, and fails the build instead. A driving point that drifts off its control would otherwise baseline an idle render under a state name and certify a ramp it never exercised.
- There is deliberately **no** `state-field-hover`: a text field's bezel does not respond to the pointer on macOS, and this stack matches it (only `Controls.button` installs a hover ramp), so such an entry would re-certify the idle render forever.

### Light appearance tier

Every entry above renders dark. That left the whole light half of
`ControlPalette` — the derived `controlTrack` / `segmentedTrackFill` grooves,
the container surfaces, the hover/pressed/focus ramps on white — pinned only
by unit tests reading colour fields. It is how a light-mode `Form` came to
draw a charcoal groove across a white settings pane and survive to final
verification: nothing rendered it.

- Entries are `light-<dark id>`. The tool **derives** them from the dark specs rather than re-declaring the views, so a light entry is the same view in the other appearance by construction and cannot drift into testing a different control. A roster id that names no dark entry fails the render instead of silently dropping an appearance from the gate.
- The roster is a subset chosen so each id covers a light-mode role no other entry covers: the recessed grooves (`toggle-off`, `slider`, `progress-view`, `progress-labeled`), the container surfaces (`form-settings`, `list-data`), the control bezels on white (`button`, `button-styles`, `text-field`, `stepper`, `picker`), the hairlines (`divider`), and the ramps (`state-button-hover` / `-pressed` / `-focused`, `state-toggle-pressed`, `state-field-focused`, `state-picker-hover`).
- The backdrop is the appearance's own `windowBackground`, not white. Most light-mode control surfaces *are* white, so on a white page a text field's bezel, a grouped `Form`'s raised surface and a list body would all be invisible and the tier would certify nothing. Dark keeps the pure black it has always used, which is why adding the tier moved no dark baseline.

### Baselines and thresholds

- Checked-in baselines live in `tests/fixtures/gallery-baselines/` as compact PNGs. The rest of `artifacts/gallery/` stays generated-only.
- A compare run re-renders the subset into `artifacts/gallery-compare/current/` and computes bounded per-entry diffs. A pixel counts as changed when any B/G/R/A channel differs by more than `-ChannelTolerance` (default 8). An entry fails when changed pixels exceed `-MaxChangedPercent` (default 0.5%) or any single channel delta exceeds `-MaxChannelDelta` (default 64). Missing baselines and canvas-size changes always fail. The raw-scene CPU rasterizer is deterministic, so unchanged code should produce 0% diffs.
- Native icon glyphs still depend on the installed Segoe Fluent Icons face. A Windows font update can therefore change only a few DirectWrite antialiasing pixels; verify the changed-pixel bounds and refresh the corresponding dark/light control baselines together after confirming no layout, bezel, or text pixels moved.
- Runs write a readable summary to `artifacts/gallery-compare/report.txt`, a
  machine-readable `report.json`, and a self-contained visual `report.html`.
  Failures additionally write red-overlay diff images to
  `artifacts/gallery-compare/diffs/`; the script exits non-zero.
- `report.json` schema 2 adds `fontProvenance` without changing pixel statuses
  or thresholds. The same diagnostic is written to `provenance.json`, with an
  initial `provenance-initial.json` retained before build/render setup. It
  records six allowlisted DirectWrite family probes, resolvable relevant font
  file versions/hashes, the classic-font override, OS/DirectWrite and runner
  image identifiers, executable hashes, and checkout revision/dirty paths.
  Checkout metadata does **not** attest an executable's build revision. Failed
  builds label any executable preexisting or partial; `-SkipRender` cannot
  attribute existing images to the environment being probed now.
- This is diagnostic evidence, **not an accepted font profile**. Unknown
  probes and actual glyph-face ownership remain explicit. No family mismatch
  relaxes the comparison gate or selects a different baseline set. Windows CI
  captures `provenance-ci-initial.json` before toolchain setup and always uploads
  `provenance*.json`, even if a later build, test, or gallery step fails. No font
  binary is copied or uploaded. Quick/Full run the bounded synthetic fixtures in
  `scripts/test-gallery-font-provenance.ps1`; these do not qualify native glyph
  appearance or replace the Variable-font raster tests.
- The gate runs as part of `agent-check.ps1 -Full` (and therefore in the Full stage of Windows CI, with the compare output uploaded as the `windows-gallery-compare` artifact). It is opt-in for Quick runs via `agent-check.ps1 -Quick -GalleryCompare`.

```powershell
# Compare against baselines (fails on meaningful regression)
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gallery-compare.ps1

# Discover the reviewed catalog without building, then inspect one appearance
# or a bounded family of examples.
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gallery-compare.ps1 -List
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gallery-compare.ps1 -Appearance light
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gallery-compare.ps1 -Pattern "canvas-*"

# Regenerate baselines after an intentional visual change; review the PNGs before committing
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gallery-compare.ps1 -UpdateBaselines
```

The gallery executable also accepts `--entries <csv>` and `--output-dir <path>`
for ad-hoc filtered renders. With no arguments it renders the full gallery to
`artifacts/gallery/`, where the self-contained `index.html` provides searchable,
appearance-aware fixture cards, responsive filters, category counts, and
copyable fixture identifiers without external assets or network access.

`-UpdateBaselines` is not a way to make the gate green — it records what the
renderer now produces. **Open every regenerated PNG before committing it**, and
say in the commit which entries moved and why. A baseline accepted unseen turns
the gate from a check on the renderer into a record of whatever it last did.

## Native close acceptance

The close foundation has four focused suites:

- `Win32CloseControlTests` checks delegate vetoes, final leases, ticket/owner
  lifetime, reservation rollback, and actual destruction outcomes using
  per-instance native-call adapters and simulated lifetime notifications.
- `Win32DeferredCloseTests` checks scalar wake ownership, nested scope deferral,
  coalescing, cancellation, post failures, cleanup reentry, and exact retry
  authorization. A build-busy retry can earn one fresh continuation only for its
  exact still-current evaluation; duplicates, terminal outcomes, second inline
  attempts, and capture cleanup cannot borrow it. Its hidden-HWND cases separately
  use real `PeekMessageW` and `DispatchMessageW`; simulated scope tests do not prove
  those native paths.
- `RetainedBuildSettlementTests` checks root/subtree completion, retained callback
  drain, queued work, transaction order, weak observer ownership, and bounded
  self-registration. Admitted builds retire old layout evidence even when their
  exact retained geometry remains unchanged; skipped, rejected, abandoned, and
  overflow cases preserve that boundary. Reader metadata and denied-lease tests
  distinguish active-render invalidation staging from ordinary idle denial.
  Readiness does not imply resolved geometry.
- `WindowCloseFinalizationTests` checks layout receipts and managed-host final
  acceptance, including stale policy/geometry, unavailable evidence, first-attempt
  preservation, participant reservations, and host-only pending work with an idle
  component coordinator. Nested observed flushes must complete before a waiting
  continuation posts. Unadapted document configurations reject both native and
  direct Boolean close routes before flushing. Public State/GeometryReader cases
  cover stale receipt rejection and a fresh constrained-slot policy query,
  including capture cleanup renders during adoption. Runtime receipts are not
  native document workflow qualification.

The clean-tree State fixtures establish their baseline with ordinary layout and
rendering before the tested mutation. Initial reader adoption may stage a normal
follow-up layout invalidation; the setup consumes it while retaining the clean
assertion. No extra query is inserted between the later mutation and the native
preflight being checked.

Run them serially through the existing sharder; do not start another SwiftPM
command against the same build directory:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Filter "Win32CloseControlTests|Win32DeferredCloseTests|RetainedBuildSettlementTests|WindowCloseFinalizationTests"
```

Also retain the existing close-policy, window-coordinator, dialog-lifetime,
mounted-state, and editor-undo regressions when integrating this capability.
Check the selected test names and report which native cases actually ran versus
skipped. Hidden-window fixtures do not show a UI or consume another test's quit
message. They are distinct from an interactive Save/Discard/Cancel sequence,
native dialog ownership, or a complete document/editor product.

The initial implementation handoff recorded formatting, contracts, patch checks,
and source review only. Authored tests and simulated destruction are not execution
evidence. Preserve that distinction in subsequent validation records; default
document-scene activation and the remaining native workflows stay governed by
[goal.md](../goal.md). The detailed callback, receipt, and unsupported raw-mutation
contracts are in [WindowClose.md](WindowClose.md).

## Live Motion Capture

Every animation assertion in the suite is about counters and about values
sampled out of the runtime, and none of those can fail the way an animation
actually fails. A fade that advances perfectly in the runtime while the screen
shows the start, one middle frame and the end satisfies a timeline-sampling
test completely and reads as a step to the person watching. Only the presented
pixels can tell the two apart.

```powershell
.build\x86_64-unknown-windows-msvc\release\swift-windowsui.exe `
  --diagnostics --diagnostics-capture-motion `
  --diagnostics-seconds 40 `
  --diagnostics-motion-frames 60 `
  --diagnostics-motion-output artifacts/motion `
  --diagnostics-output artifacts/perf/motion.json
```

This is **self-readback of the app's own swap chain**, taken between the last
draw and the present — not a desktop or window capture, so the screenshot
contract holds. The readback runs in `D3D11BatchRenderer` behind
`BatchRenderBackend.setCapturesPresentedFrames(_:)`, which is off in every
shipping run. It has to be taken *before* `Present`: the chain is
`FLIP_DISCARD`, where the back buffer is undefined the instant the present is
queued, and a capture taken afterwards often reads the previous frame — the
exact failure that would make a stuttering animation look smooth.

The run writes `artifacts/motion/frame-NNN.png` plus a `manifest.json` giving,
for every consecutive pair: the wall-clock gap, how many pixels changed, the
mean and maximum channel delta over the changed pixels, and the bounding box of
the change. Frames are held in memory and encoded when the run ends — encoding
between two presents would stretch the timeline being measured.

The scripted sequence is indexed on captured frames, not seconds, so the phase
boundaries are checkable against the images: frames 0-1 settled, frame 2 a
pointer arrives on a control (`hover-fade`), frame 20 that control is pressed
(`screen-switch`), frame 40 a control on the new screen is pressed
(`control-activate`). Targets come from
`RetainedViewRuntime.activatableControlCenters()` — the hit-test's own frames —
rather than fractions of the window, which miss the moment the layout re-flows.

What to read the manifest for:

- **`longestIdenticalRunWhileAnimating`** — the number that says slideshow.
  Read this one, not `longestIdenticalRun`: an idle window repeating itself is
  correct behaviour and dominates the unrestricted count. A run of identical
  frames while the runtime says something is animating is either a wasted
  present or a dropped step.
- **A single frame with a large `changedFraction` and nothing on either side**
  is a cut, not a transition. That is how the missing tab cross-fade was found:
  one frame changed 92 % of the window with 20 identical frames after it.
- **`meanAbsoluteDeltaOverChangedPixels` per frame** across a fade is the
  step size. Many small steps is smooth; one big step is not.
- **`medianFrameGapMs`** — read this first. Nine steps of one colour level is
  a smooth fade at 16 ms a frame and a quarter-second freeze at 250, and the
  images look identical either way. On a display whose compositor stalls
  `Present`, give the run enough `--diagnostics-seconds` for the pacing
  watchdog to engage before the capture starts (40 s is comfortable); the
  manifest's gap will read ~16 ms once it has.

A capture run's frame times are not comparable with a normal run's: the
readback is a full-surface GPU stall on every frame. Use it for pixels and
`--diagnostics-no-vsync` for timings.
