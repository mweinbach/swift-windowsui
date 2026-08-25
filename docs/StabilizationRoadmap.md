# Stabilization Roadmap

This document is a concrete, phased plan to move `swift-windowsui` from a
working prototype toward a release-ready custom-rendered Windows UI toolkit.
It is derived from the current repository layout, docs, scripts, and known
limits in `README.md`, `docs/WinSwiftUI.md`, `docs/Testing.md`,
`docs/GPURenderingPipeline.md`, and the package targets.

**Honest baseline (do not overclaim):**

- The stack is a custom-rendered retained UI toolkit with a SwiftUI-shaped
  `WinSwiftUI` compatibility layer. It is **not** full SwiftUI parity and
  **not** a wrapper around native Win32 widgets.
- Default presentation is `GPUIScene` → `D3D11BatchRenderer`. The
  `RenderFrame` → `D3D11Renderer` path is a same-session fallback and
  explicit debug override (`SWIFT_WINDOWSUI_FRAME_DEBUG=1` / `-FrameDebug`).
- `D3D11Renderer` still executes only `fillRect` and `drawBitmap`. Scene
  coverage is richer (shadows, quads, paths, atlas-backed glyphs) but still
  incomplete relative to GPUI-style text/sprite systems.
- Accessibility metadata is projected to native UI Automation (fragment tree,
  properties, Invoke/Value/Toggle/Selection/SelectionItem/VirtualizedItem
  patterns, focus/structure events, and explicit live-region announcements via
  `CUIAInterop` + `UIAProviderBridge`). Rich TextPattern, automatic live-region
  observation, and fine-grained structure notifications remain unsupported.
- Windows light/dark preference, high contrast, text scale, reduced motion,
  and active contrast-theme semantic colors are sampled through
  `SystemAppearanceSnapshot`; settings broadcasts refresh the inherited
  retained environment. Native window/text/control/selection/disabled colors
  drive control chrome and semantic text; live-theme manual verification
  remains pending.
- `WinSwiftUIWindowCoordinator` hosts multiple windows (own host/runtime/
  renderer each); default `openWindow` / `dismissWindow` routing is live and
  `supportsMultipleWindows` is true for coordinator-managed hosts.
  `openSettings` / `Settings` scenes remain **unsupported**.
- Local validation scripts are strong. `.github/workflows/windows-ci.yml` now
  runs contracts on every change, Quick on pull requests / branch pushes, and
  Full plus screenshot upload on main, schedule, and manual dispatch. Hosted
  runner results still need to be monitored for toolchain drift.
- Public Core/Graphics/Layout/Scene package products and the genuine offscreen
  CPU renderer are portable to Linux/macOS. The same demo source builds against
  native Apple SwiftUI on macOS, while the complete retained `WinSwiftUI`
  runtime, Win32 accessibility/text/image integration, and native Windows
  presentation remain **Windows-only**. Neutral platform-host contracts are a
  foundation for another host, not a claim that one already exists.

Architecture invariants that every phase must preserve:

- App path: `WinSwiftUI.App` / `WindowGroup` → `WinSwiftUIWindowHost` →
  `Win32Window` → `RetainedViewRuntime` → `GPUIScene` → `D3D11BatchRenderer`
- `GPUIScene.paintOperations` is presentation-order source of truth
- Screenshots stay raw retained-runtime rasterization (no `CopyFromScreen`)
- Same-source demo contract (`import WinSwiftUI` / `import SwiftUI`)
- Main-actor UI surface; `Runtime.swift` remains layout/focus/animation truth

---

## Immediate next wave — Product UI polish

The stabilization ladder covers retained-runtime and renderer tests, demo
builds, scene/frame screenshots, and a reviewed multi-tier gallery gate. The
next work should deepen visible quality instead of adding more source-only API
surface.

### Priority order

1. **Gallery regression gate:** retain per-entry canvas sizes, add reviewed
   baselines for Supported controls, and report bounded image diffs in CI.
2. **Responsive control geometry:** audit every control at compact, regular,
   and expanded widths; keep labels intrinsic and make tracks/content consume
   remaining space. Labeled `Slider` is the first corrected case.
3. **Text input quality:** selection painting, caret movement, clipboard
   commands, horizontal scrolling, IME composition, and disabled/focus states.
4. **List and form quality:** row metrics, separators, selection/hover chrome,
   section spacing, keyboard navigation, and scroll behavior under real data.
5. **Presentation quality:** menu, picker, alert, sheet, and popover placement,
   clipping, shadows, dismissal, and keyboard/focus restoration.
6. **Real sample screens:** evolve the shared demo into dashboard, settings,
   and data-list screens that exercise Supported APIs at multiple window sizes.

### Exit criteria

- [x] Reviewed gallery baselines fail CI on meaningful visual regressions
      (`scripts/gallery-compare.ps1`, 61 Supported-tier, interaction-state,
      light-appearance, and Canvas-path-gradient baselines under
      `Tests/fixtures/gallery-baselines/`, runs in `-Full` and Windows CI)
- [x] Supported controls render without clipping at documented minimum widths
      (track controls re-resolve geometry in `onLayout`: slider, progress bar,
      circular progress, toggle thumb; pinned by `ControlGeometryTests` at
      gallery canvas sizes)
- [x] Text fields support selection, clipboard, caret, and IME smoke flows
      (selection/clipboard/caret/drag landed earlier; IME composition now
      flows WM_IME_* → marked underlined text → commit, candidate window
      positioned at the caret — `TextInputIMECompositionTests`; live-IME
      desktop smoke pending)
- [x] Lists/forms support mouse and keyboard navigation with stable row chrome
      (arrow-key selection with focus + scroll-into-view, constant row
      metrics, hover highlight, form section clipping)
- [x] Demo includes at least three product-style screens and resize snapshots
      (dashboard/settings/data tabs; snapshot smoke at 1280x720 and 800x600)
- [ ] Full validation remains green after each vertical slice

---

## Phase 0 — Green tests and CI foundation

**Goal:** Make the existing validation ladder the release gate: green on a
clean machine, serializable for agents, and runnable in CI without inventing
a second architecture.

### Current state

| Asset | Status |
| --- | --- |
| `scripts/check-contracts.ps1` | Present; encodes architecture invariants |
| `scripts/agent-check.ps1` (`-ContractsOnly` / `-Quick` / `-Full`) | Present; serial steps, no parallel `.build` use |
| `scripts/test.ps1`, `scripts/build.ps1`, `scripts/lint.ps1` | Present |
| `scripts/demo-screenshot.ps1` (+ `-FrameDebug`) | Present; raw scene/frame rasterizer path |
| `scripts/demo-probe.ps1` | Present; short presenter-selection probe |
| Test target `SwiftWindowsCoreLogicTests` | Large local suite (runtime, scene, D3D11 plan, WinSwiftUI, stress) |
| GitHub Actions | Windows validation plus hardened macOS reference rendering |
| Windows GHA build+test | `.github/workflows/windows-ci.yml` uses hosted `windows-2022` runners |

Known friction:

- Very large XCTest filters can hit Windows command-length limits. The test
  harness now expands matching methods into serial bounded shards.
- Do not run multiple SwiftPM commands against the same `.build` in parallel.

### Work items

1. Document and enforce the serial validation ladder as the only supported
   agent/CI entrypoints (`agent-check.ps1`, not ad-hoc parallel `swift test`).
2. Split or reorganize oversized XCTest classes so focused filters stay under
   Windows command-length limits without dropping coverage.
3. Add a **Windows** CI workflow (self-hosted or cloud runner with Swift for
   Windows + VS toolchain) that runs:
   - contracts
   - lint (or changed-file lint + scheduled `-AllSwift`)
   - `agent-check.ps1 -Quick` on PR
   - `agent-check.ps1 -Full` on main / nightly
4. Upload screenshot artifacts (`artifacts/demo-screenshot.png`,
   `artifacts/demo-screenshot-frame.png`) from Full runs.
5. Fail CI on contract regressions and flaky screenshot path breakage; keep
   golden pixel diffs opt-in until baselines are stable (see Phase 6).
6. Keep macOS reference-render workflow as a **parity input**, not a
   substitute for Windows correctness.

### Exit criteria

- [x] Local checkout: `agent-check.ps1 -ContractsOnly` passes
- [x] Local checkout: `agent-check.ps1 -Quick` passes
- [x] Local checkout: `agent-check.ps1 -Full` passes (tests, demo build,
      scene + frame screenshots written under `artifacts/`)
- [ ] Hosted Windows CI run confirms the ladder on PR/main without manual
      `.build` cleanup
- [x] No reliance on desktop capture or foreground windows for validation
- [x] Documented procedure for toolchains (Swift for Windows + VS) in
      `docs/Testing.md` remains accurate

### Validation commands

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/with-swift.ps1 -CheckOnly
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/agent-check.ps1 -ContractsOnly
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/lint.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/agent-check.ps1 -Quick
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/agent-check.ps1 -Full
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/build.ps1 -Product swift-windowsui
```

Focused (local iteration only; still serial against `.build`):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Filter RetainedViewRuntimeTests
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Filter GPUISceneTests
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Filter SceneRasterizerTests
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Filter D3D11BatchRendererTests
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Filter WinSwiftUIWindowHostTests
```

---

## Phase 1 — Supported API contract (honesty + freeze surface)

**Goal:** Publish a machine-checkable **supported** surface for app authors
and stop implying full SwiftUI parity. Prefer real demo/app needs over
speculative API cloning.

### Current state

- Large SwiftUI-shaped surface in `Sources/WinSwiftUI/` (`App`,
  `WindowGroup`, stacks, lists, navigation, sheets, many modifiers).
- Many APIs are **source-compatible shims** (metadata only, no-op, or
  partial retained behavior). Examples already documented in
  `docs/WinSwiftUI.md`: scroll observation callbacks, SF Symbol effects,
  `matchedGeometryEffect` interpolation, Settings scene, full grid semantics,
  native menus, asset catalogs, Canvas symbols / `withCGContext`.
- Shared-demo subset in `Sources/SwiftWindowsDemo/` is the practical
  compatibility bar for same-source macOS builds.
- Contracts script encodes architecture goals, not a full API tier matrix.

### Work items

1. Define three tiers and label APIs in docs (and, where cheap, tests):
   - **Supported** — behavior covered by tests/screenshots; safe for apps
   - **Accepted (shim)** — compiles and maps to retained metadata / partial UI
   - **Placeholder** — intentional stub panels (Map, WebView, Chart chrome,
     AVPlayer, etc. in `Views.swift`)
2. Freeze the **Supported** tier for a release train: changes require tests
   and doc updates; no silent behavior drop.
3. Keep expanding Supported from demo/gallery needs
   (`swift-windowsui`, `swift-windowsui-gallery`), not wholesale SwiftUI
   cloning.
4. Add contract checks that:
   - shared demo stays free of Windows-only APIs
   - placeholder product surfaces remain explicitly named / documented
5. Maintain `docs/WinSwiftUI.md` as the living inventory; link tiers from
   README without restating the full list.

### Exit criteria

- [x] Published Supported / Accepted / Placeholder matrix for app-facing APIs
      (`docs/CompatibilityStatus.md` separates Implemented, Partial,
      Shim / no-op, Placeholder panel, and Unsupported surfaces)
- [ ] Every Supported control/modifier has at least one automated test or
      screenshot-backed demo usage
- [x] Placeholder panels remain clearly non-functional (no accidental
      “works” claims; the compatibility matrix lists them separately and
      explicitly excludes them from real product flows)
- [ ] Same-source demo still builds against the documented subset
- [x] Contract script still passes; no second parallel UI abstraction
      (`scripts/agent-check.ps1 -ContractsOnly`)

### Validation commands

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/agent-check.ps1 -ContractsOnly
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/build.ps1 -Product swift-windowsui
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/build.ps1 -Product swift-windowsui-gallery
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/demo-screenshot.ps1
```

---

## Phase 2 — UI Automation (accessibility projection)

**Goal:** Expose retained accessibility metadata to Windows assistive
technologies through UI Automation, without replacing the custom renderer
with native widgets.

### Current state

- `ViewNode` already stores accessibility **metadata**: label, value, hint,
  identifier, hidden, traits, child behavior, sort priority, actions
  (`accessibilityLabel`, traits add/remove, `accessibilityAction`, `help`,
  etc.).
- A native Win32 UI Automation fragment tree is derived from the retained
  accessibility projection through `CUIAInterop`, `UIAProviderBridge`, and
  `RuntimeUIAElementTreeSource`; default actions expose InvokePattern, text
  fields expose secure-aware ValuePattern, switches expose TogglePattern, and
  List/Table rows expose SelectionPattern + SelectionItemPattern.
- Retained focus, transform-aware/offscreen bounds, hit testing, enabled
  state, focus/structure events, and VirtualizedItemPattern realization are
  projected live; the bridge can explicitly raise live-region change events.
  Rich TextPattern, automatic live-region observation, and fine-grained
  structure notifications remain unsupported.

### Work items

1. Design a read-only UIA provider tree projected from the retained tree
   (bounds, name, control type from traits, enabled/focused/selected).
2. Map common traits → UIA control types/patterns (button, text, edit,
   checkbox/toggle, header, link, list/list-item as feasible).
3. Invoke stored `accessibilityActions` via UIA invoke/default action where
   patterns allow.
4. Keep projection **derived** from retained state; do not maintain a second
   app-visible tree API.
5. Cover with unit tests for mapping tables; add a small automation smoke
   path if a headless UIA client is practical on the CI host.
6. Document remaining gaps (automatic live regions, full text patterns,
   multi-selection metadata, and lazy construction) honestly.

### Exit criteria

- [x] Narrator (or equivalent UIA client) can read labels for primary demo
      controls and activate default button actions
      (`.NET UIAutomationClient` probe: control types/names/bounds enumerate,
      InvokePattern activates retained buttons; `scripts/demo-uia-probe.ps1`)
- [x] Focus changes update UIA focus; bounds track layout after resize
      (focus-changed events via runtime hook; bounds re-projected live with
      DPI + ClientToScreen on every query)
- [x] Hidden / `accessibilityHidden` nodes omitted or marked correctly
- [x] Mapping unit tests green; contracts still pass
      (`AccessibilityProjection` — derived tree, trait→control-type table,
      action invocation; `UIAProviderBridge` + `RuntimeUIAElementTreeSource`
      headless tests through the real COM vtables)
- [x] Docs state remaining UIA pattern gaps
      (see `docs/CompatibilityStatus.md`: no rich TextPattern/text ranges,
      automatic live-region observation, fine-grained structure notifications,
      or advertised multi-selection container metadata)

### Validation commands

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/agent-check.ps1 -Quick
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Filter RetainedViewRuntimeTests
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Filter ComponentHostTests
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/demo-screenshot.ps1
# Manual: Narrator smoke on swift-windowsui demo (not scripted yet)
```

---

## Phase 3 — System settings and high contrast

**Goal:** Derive environment appearance from Windows settings and honor
high-contrast / accessibility display preferences in retained chrome.

### Current state

- `EnvironmentValues.colorScheme`, `colorSchemeContrast`,
  `preferredColorScheme`, dynamic type, legibility weight, and related
  accessibility preference shims exist.
- High contrast samples the selected native window, text, control, highlight,
  disabled, and link colors. The inherited palette drives retained control
  surfaces, semantic foreground/backgrounds, selection, default accents, and
  borders; dark/light identity follows the theme's actual window background.
- `Win32Host` samples light/dark preference, high contrast, text scale, and
  reduced motion at startup and refreshes appearance on `WM_SETTINGCHANGE` /
  `WM_SYSCOLORCHANGE`; luminance and capture remain overrideable defaults.

### Work items

1. On host startup and `WM_SETTINGCHANGE` / related display messages, sample:
   - light/dark (or app preference override)
   - high contrast on/off and system high-contrast colors when available
   - text scale / DPI (already partially present via display scale paths)
   - reduce motion / related flags where Win32 exposes them
2. Map high contrast into `colorSchemeContrast` and a small semantic palette
   for backgrounds, text, borders, focus rings, and selection.
3. Ensure focus rings and text remain visible under high contrast on both
   scene and frame fallback paints for Supported controls.
4. Keep app overrides (`preferredColorScheme`, explicit environment sets)
   above system defaults with documented precedence.
5. Add tests with injected system snapshots (do not require live OS theme
   flips in unit tests).

### Exit criteria

- [ ] System high-contrast toggle is observed without app restart (or
      documented if restart is required for specific settings)
      (wired: `SystemAppearanceSnapshot` re-sampled on
      WM_SETTINGCHANGE/WM_SYSCOLORCHANGE → environment → reload; manual HC
      theme smoke still pending)
- [ ] Supported demo controls remain legible in high contrast
- [x] Semantic colors do not hard-code low-contrast greys when HC is on
      (`GetSysColor` roles propagate through `HighContrastSystemColors`,
      `EnvironmentValues`, `ControlPalette`, and semantic text/backgrounds)
- [x] Unit tests cover mapping tables; screenshot optional HC fixture
      (`SystemAppearanceTests` and `HighContrastSystemPaletteTests` — injected
      snapshots, exact role mapping, COLORREF decoding, theme luminance,
      override precedence, and contrast-on/off environment clearing)
- [x] Docs describe precedence: app override > system > toolkit default
      (`README.md` and `docs/CompatibilityStatus.md`, System appearance)

### Validation commands

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Filter WinSwiftUIVisualModifierTests
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Filter WinSwiftUIWindowHostTests
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/agent-check.ps1 -Quick
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/demo-screenshot.ps1
# Manual: Windows high-contrast theme smoke on demo
```

---

## Phase 4 — Text, localization, and selection

**Goal:** Make text input and display good enough for real forms and
localized dashboard apps, without claiming full font shaping parity.

### Current state

- Scene path: runtime-owned logical text layout cache, DirectWrite glyph-run
  capture / native glyph atlas; still short of GPUI-style shaped runs and
  text-system-owned line layout.
- Frame path: native bitmap draws; `PixelText` remains uppercase bitmap with
  `?` fallback for legacy paths.
- Inputs: `TextField` / `SecureField` / `TextEditor` accept native `WM_CHAR`
  Unicode characters, active-keyboard-layout punctuation, and UTF-16 surrogate
  pairs; support IME composition, selection-aware insertion, delete, clipboard
  shortcuts, and caret left/right/home/end. Selection UX is still incomplete
  relative to full desktop editors.
- Localization: `LocalizedStringKey`, tables, `LocalizedStringResource`,
  locale/calendar/timeZone environment values partially used (e.g.
  `DatePicker`); not a complete resource catalog / pluralization story.
- Clipboard: `ClipboardManager` supports Unicode text and Explorer-compatible
  file-list (`CF_HDROP`) copy/paste, including type-aware `PasteButton`
  delivery; malformed cross-process file lists, unsupported content types,
  and relative text masquerading as URLs fail closed. Richer transferable
  formats remain unsupported.
- RTL: `layoutDirection` flips many stack/alignment paths; arbitrary custom
  drawing is not auto-mirrored.

### Work items

1. **Selection & editing (Supported inputs):**
   - mouse drag / shift-extend selection
   - clipboard shortcuts (Ctrl+C/X/V/A) wired through host + runtime
   - caret blink and selection highlight on scene **and** frame paths
   - secure field masking stays consistent with selection
2. **Measurement & layout:**
   - prefer native/DirectWrite metrics for Supported `Text` on the default
     scene path
   - document remaining pixel-text / uppercase limitations where still used
3. **Localization:**
   - resolve `Text` / labels through bundle tables with locale override
   - document string catalog expectations for Windows packaging
   - keep environment `locale` flowing into formatters (`DatePicker`,
     `Text(Date,...)`, etc.)
4. **IME / composition:**
   - preserve the separate native `WM_CHAR` text and virtual-key shortcut paths
   - retain the existing WM_IME marked-text / committed-result bridge and
     candidate-window positioning
   - expand host coverage for non-US layouts and complex editor behavior
5. Tests for selection ranges, clipboard round-trip, locale formatting, and
   RTL smoke layouts.

### Exit criteria

- [ ] Supported text inputs: select, copy, cut, paste, select-all work in demo
- [x] Selection binding updates are observable in tests
      (`TextInputSelectionTests.testShiftExtensionAndSelectAllWriteSelectionBinding`)
- [ ] Localized demo strings resolve under a non-default locale override
- [ ] No claim of full Unicode shaping / rich `AttributedString` editing
- [ ] Scene and frame screenshots still generate; text regressions caught by
      existing text/runtime tests

### Validation commands

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Filter WinSwiftUITextTests
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Filter TextSystemTests
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Filter RetainedViewRuntimeTests
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Filter GlyphAtlasTests
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/agent-check.ps1 -Quick
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/demo-screenshot.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/demo-screenshot.ps1 -FrameDebug -OutputPath artifacts/demo-screenshot-frame.png
```

---

## Phase 5 — Multi-window lifecycle

**Goal:** Real multi-window hosting for `WindowGroup` / open-dismiss actions,
with per-window retained runtimes and honest `supportsMultipleWindows`.

### Current state

- Single live `WindowGroup` boot path in `WinSwiftUIWindowHost`.
- `supportsMultipleWindows` defaults **false**.
- `openWindow` / `dismissWindow` / `openSettings` are SwiftUI-shaped **no-ops**
  unless handlers are injected.
- `@SceneStorage` is in-memory and scoped to the current single-window model.
- Scene phase and presentation environment values exist for in-tree sheets /
  covers, not multiple top-level windows.

### Work items

1. Host multiple `Win32Window` instances, each with its own
   `RetainedViewRuntime` and renderer attachment.
2. Implement default `openWindow` / `dismissWindow` routing for id- and
   value-based `WindowGroup` content.
3. Set `supportsMultipleWindows` true when the host actually allows it.
4. Define activation, close, and last-window-quit policy.
5. Isolate `@SceneStorage` (and future restoration keys) per window/scene
   instance.
6. Keep `Settings` / `openSettings` either implemented as a real scene or
   still documented as unsupported (no silent no-op in Supported tier).
7. Tests: open second window, dismiss, focus handoff, independent state.

### Exit criteria

- [x] Demo or gallery can open a second window via `openWindow`
      (settings screen "Open Second Window" button → `openWindow(id:)`;
      `WinSwiftUIWindowCoordinator` spawns an independent host/runtime/
      renderer)
- [x] Closing windows does not tear down unrelated runtimes incorrectly
      (per-window teardown on WM_DESTROY; last-window-quit via coordinator)
- [x] `supportsMultipleWindows` reflects reality
      (true for coordinator-managed hosts, false otherwise — pinned by test)
- [x] Per-window invalidation/render loops remain main-actor safe
- [x] Automated host tests cover open/dismiss; manual multi-monitor smoke
      (`WindowCoordinatorTests` — 11 tests; desktop smoke pending)

### Validation commands

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Filter WinSwiftUIWindowHostTests
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Filter CommandsAndSceneTests
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/build.ps1 -Product swift-windowsui
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/demo-probe.ps1
# Manual: open/dismiss secondary windows in demo/gallery
```

---

## Phase 6 — Frame fallback policy (stabilize presentation resilience)

**Goal:** Treat scene vs frame as an explicit product policy with observable
health, recovery, and documented visual differences—not an accidental
downgrade.

### Current state

- Prefer batch/scene backend; attach/render/resize failures can downgrade to
  frame backend (`docs/GPURenderingPipeline.md`).
- Recovery policy defaults to **two-way recovery** with backoff
  (`BatchBackendRecoveryPolicy.standard`); `.disabled` preserves one-way pin.
- `rendererHealthSnapshot` exposes active backend and selection reason.
- Frame backend command surface remains **`fillRect` + `drawBitmap`** only;
  scene has paths, shadows, glyphs, etc.
- Screenshot tooling can force frame path via `-FrameDebug`.

### Work items

1. Product policy table:
   - when to auto-fallback
   - when to recover
   - what apps may force (`FRAME_DEBUG`, recovery disabled)
2. Ensure Supported controls degrade **readably** on frame path (text as
   bitmaps, simplified chrome) and document what will look wrong (complex
   paths, materials, advanced glyphs).
3. Keep paint-order invariants on scene path; do not “fix” frame gaps by
   breaking `paintOperations` semantics.
4. Expand host tests for failure injection, recovery success/failure, and
   health snapshot fields.
5. Optional: CI compares scene vs frame screenshots structurally (not
   necessarily pixel-identical).
6. Consider metrics counters (fallback count, recovery success) for demo
   probe logs.

### Policy table (mirrors the source-of-truth comment at
### `attachPreferredRenderer` in `Sources/WinSwiftUI/App.swift`)

| Trigger | Policy |
| --- | --- |
| Startup, batch available | Attach batch (scene) backend; reason `.defaultScene` |
| Startup batch attach throws | Downgrade to frame immediately; `.batchAttachFailure`, and schedule recovery like any other downgrade |
| Batch `render(scene:)` throws mid-frame | Render that frame on frame backend, then pin to frame; `.batchRenderFailure` |
| Batch `resize` throws | Downgrade at the new size; `.batchResizeFailure` |
| After downgrade, `.standard` policy | Retry batch attach with exponential backoff (5s → 60s cap); success restores scene (`.batchBackendRecovered`) |
| After downgrade, `.disabled` policy | One-way pin: batch never invoked again this session |
| Frame backend itself throws | Log (rate-limited per failure signature); host session stays alive |
| Neither backend can attach | Bounded attach retry (5 attempts, 0.5s → 8s) on a 250 ms timer, then terminal `.presenterUnavailable`: the host stops requesting frames and `RendererHealthSnapshot.isPresenterUnavailable` reports it. A 0×0 client rect (minimized) defers an attempt instead of spending one |
| Startup probe reports the GPU factory `.unavailable` | Substitute `SoftwareWindowRenderBackendFactory` (CPU raster + `StretchDIBits` blit), never `CPURenderBackendFactory`, which cannot present; a fallback that also cannot present is not substituted, so the row above applies. Recorded in `RendererHealthSnapshot.backendResolution` |

Apps may force: `SWIFT_WINDOWSUI_FRAME_DEBUG=1` (pins frame from startup),
`recoveryPolicy: .disabled`, and observability via `rendererHealthSnapshot`.

Readability contract on the frame path (enforced by
`FramePathDegradationTests` / `FrameFallbackPolicyTests`): text rides
pre-rasterized bitmaps, `fillRect` keeps solid/linear-gradient fills with
uniform corner radii, and vector path commands are CPU-rasterized into
`drawBitmap`s by `FramePathDegradation` inside `D3D11Renderer`. Known
cosmetic gaps vs the scene path (documented, not claimed as parity):
rounded clip shapes degrade to rectangular clips, per-corner radii fall back
to uniform, radial/conic gradients fall back to a solid base color, and soft
shadows render as plain offset fills. Axis-aligned multi-stop linear gradients
preserve their intermediate stops on both live fallback presenters: Direct2D
uses a bounded native gradient-stop collection, while pure D3D11 draws bounded
full-footprint gradient segments.

### Exit criteria

- [x] Written policy in this doc + `docs/GPURenderingPipeline.md` agree
      (table above; mirrors `attachPreferredRenderer` in App.swift)
- [x] Injected batch failure falls back without crashing the host session
      (`FrameFallbackPolicyTests`)
- [x] Recovery restores scene backend under `.standard` when attach succeeds
- [x] `.disabled` remains one-way for the session
- [x] Full agent check still produces both scene and frame artifacts
- [x] README/WinSwiftUI docs do not claim frame ≡ scene visual parity
      (CompatibilityStatus marks the frame path Partial with listed gaps)

### Validation commands

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Filter WinSwiftUIWindowHostTests
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Filter RendererHealthSnapshotTests
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Filter D3D11BatchRendererTests
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/demo-screenshot.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/demo-screenshot.ps1 -FrameDebug -OutputPath artifacts/demo-screenshot-frame.png
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/agent-check.ps1 -Full
```

---

## Phase 7 — Real platform integrations

**Goal:** Replace thin shims and placeholder panels with real Win32-backed
integrations where product value is high; leave the rest explicitly
unsupported.

### Current state (partial integrations)

| Area | Today |
| --- | --- |
| Clipboard | Unicode text + file-URL lists (`CF_HDROP`) via `ClipboardManager`; format enumeration (`hasText`/`hasFileURLs`); `PasteButton` delivers copied files for file-URL and URL content types |
| File dialogs | `FileDialogManager` open/save Win32 common dialogs behind an injectable provider; `allowedContentTypes` map to extension filters (category types approximate) |
| Drag/drop | Explorer file drops (`WM_DROPFILES`) reach retained `onDrop` destinations; OLE drag sessions and text drops remain unsupported |
| Open URL | `Link` / `openURL` dispatch through hardened `ShellExecuteW` routing |
| Undo | Per-window `UndoManager` shim; not fully bridged to edit commands |
| Color picker | Retained palette keyboard UI plus opt-in native `ChooseColorW` dialog |
| Date picker | Retained label/value; not a native calendar control |
| Map / WebView / PDF / AV / charts / tips / Store | **Placeholder panels** |
| Asset catalogs | Not implemented; path/WIC load for common image files |
| Privacy-sensitive capture exclusion | Metadata only |

### Work items (prioritized)

1. **Clipboard formats** beyond plain text (UTF-8, files/URLs as practical).
2. **Save/open panels** wired to SwiftUI-shaped fileImporter/fileExporter
   (or document the Supported subset that already maps).
3. **Shell openURL** and folder reveal hardened with tests where possible.
4. **Native color dialog** optional path behind `ColorPicker` style without
   breaking keyboard palette fallback.
5. **Drag/drop** OS bridge for text/files into retained drop delegates.
6. Explicitly **decline or defer** WebView/Map/AV/Store as separate products;
   keep placeholders out of Supported tier.
7. Wire privacy-sensitive surfaces to OS exclusion APIs only when reliable;
   otherwise document gap.

### Exit criteria

- [ ] Supported integration list published; placeholders excluded
- [x] Clipboard + file dialog paths covered by automated tests where host
      allows (or demo-probe hooks)
      (`FileDialogIntegrationTests`, `ClipboardFileFormatTests`,
      `OpenURLHardeningTests`; real-dialog display still needs manual smoke)
- [ ] No Supported API is a silent no-op for core document workflows
- [ ] Remaining platform gaps listed with “not supported in vX” language

### Validation commands

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Filter ClipboardButtonTests
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Filter WinSwiftUITests
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/build.ps1 -Product swift-windowsui
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/demo-probe.ps1
# Manual: file open/save, clipboard round-trip, openURL
```

---

## Phase 8 — Modularization

**Goal:** Keep package boundaries clean so apps depend on the smallest
correct surface, and optional backends stay replaceable.

### Current state

Targets already exist:

- `SwiftWindowsCore`, `SwiftWindowsGraphics`, `SwiftWindowsLayout`
- `SwiftWindowsPlatform`, `SwiftWindowsUI`, `SwiftWindowsRendererD3D11`
- `WinSwiftUI` (renderer-neutral; depends on UI and renderer-neutral graphics)
- `SwiftWindowsApp`, demo/snapshot/gallery executables
- `SwiftWindowsScene` alternate scene path (not primary demo path)
- `CDirect2DInterop` for native text/graphics interop

Coupling pressure:

- The `swift-windowsui` executable composition root pins the concrete D3D11
  backend through `RenderBackendFactory`; `WinSwiftUI` stays backend-neutral
- Test target aggregates most libraries
- Large `Views.swift` / `Core.swift` / `Runtime.swift` files increase
  merge and compile cost

### Work items

1. Enforce dependency direction: Core → Graphics/Layout → UI → Platform
   host glue → Renderer backend → WinSwiftUI façade.
2. Soften `WinSwiftUI` → D3D11 hard dependency via factory/protocol already
   present (`RenderBackendFactory` / batch backend) so tests can run more
   backend-neutral slices.
3. Split oversized source files by domain only when it reduces compile time
   or ownership boundaries—not cosmetic churn.
4. Keep renderer-neutral contracts in `SwiftWindowsGraphics` in sync with
   CPU rasterizer and D3D11.
5. Do **not** resurrect `FoundationApp` / `SwiftWindowsScene` as primary app
   paths; leave as legacy/secondary with clear labels.
6. Optional future products: `WinSwiftUICore` (no GPU) for logic tests vs
   full Windows product library.

### Exit criteria

- [x] Dependency graph documented and contract-checked where feasible
      (`check-contracts.ps1` Phase 8 rules scan forbidden imports per target)
- [x] App-facing import remains `import WinSwiftUI` on Windows
- [x] Backend selection still defaults to scene/batch with frame fallback
      (WinSwiftUI is renderer-neutral — its own default is the presenting
      `SoftwareWindowRenderBackendFactory`; the `swift-windowsui` composition
      root pins `D3D11RenderBackendFactory`)
- [x] `swift test` and demo products build without circular targets
- [x] No parallel retained-runtime rewrite

### Validation commands

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/agent-check.ps1 -ContractsOnly
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/build.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/build.ps1 -Product swift-windowsui
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/build.ps1 -Product swift-windowsui-snapshot
```

---

## Phase 9 — Release readiness

**Goal:** Ship a versioned toolkit that is honest about scope, validated on
Windows, and usable for dashboard-style apps in the Supported tier.

### Work items

1. **Versioning:** semantic version + changelog; Supported-tier compatibility
   policy (what can break between minors).
2. **Performance budgets:** list virtualization, animation stress, and scene
   primitive bounds tests already in tree become release gates
   (`DynamicListStressTests`, `AnimationStressTests`, memory bounds audits).
3. **Security/reliability:** malformed input tests stay green; no desktop
   capture in tooling; clipboard/file paths don’t trust unvalidated buffers.
4. **Docs package:** README + this roadmap + `WinSwiftUI.md` + `Testing.md` +
   GPU pipeline agree on default path and limits.
5. **Sample apps:** demo + gallery exercise Supported tier only.
6. **Release checklist** ([`docs/ReleaseChecklist.md`](ReleaseChecklist.md))
   signed off on a clean machine and CI.

### Exit criteria

- [ ] Tagged release with matching changelog
      (`CHANGELOG.md` seeded for 0.1.0 — flip `Unreleased` to the tag date)
- [ ] Phase 0 Full CI green on release commit
- [ ] Supported API matrix published for that version
      (matrix maintained in `docs/CompatibilityStatus.md`; publish with tag)
- [x] Known limitations section lists: incomplete SwiftUI parity, UIA level,
      multi-window level, text/IME level, frame visual subset, Windows-only
      package (CHANGELOG.md "Known limitations (0.1.0)")
- [x] No Supported API documented as working when it is placeholder/no-op
- [x] Screenshot artifacts attached to release or CI run for scene + frame
      (Windows CI uploads screenshot + gallery-compare artifacts)

### Validation commands (release gate)

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/with-swift.ps1 -CheckOnly
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/agent-check.ps1 -Full
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/lint.ps1 -AllSwift
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/build.ps1 -Product swift-windowsui
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/build.ps1 -Product swift-windowsui-snapshot
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/build.ps1 -Product swift-windowsui-gallery
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/demo-probe.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/demo-screenshot.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/demo-screenshot.ps1 -FrameDebug -OutputPath artifacts/demo-screenshot-frame.png
```

Manual release smoke (full list with sign-off:
[`docs/ReleaseChecklist.md`](ReleaseChecklist.md)):

- Launch `swift-windowsui`; resize, scroll, keyboard focus, button activate
- Force frame path once (`SWIFT_WINDOWSUI_FRAME_DEBUG=1`) and confirm it runs
- If Phase 2+ landed: Narrator + high contrast quick pass
- If Phase 5 landed: open/dismiss secondary window

---

## Suggested sequencing and dependencies

```text
Phase 0  Green tests/CI
   │
   ├─► Phase 1  Supported API contract  (can overlap late Phase 0)
   │
   ├─► Phase 6  Frame fallback policy   (can overlap; uses host tests)
   │
   ├─► Phase 2  UI Automation           (needs stable tree + focus)
   ├─► Phase 3  System settings / HC    (host settings bridge)
   ├─► Phase 4  Text / l10n / selection (runtime + text system)
   │
   ├─► Phase 5  Multi-window            (after host health is solid)
   ├─► Phase 7  Platform integrations   (after API tiers exist)
   │
   ├─► Phase 8  Modularization          (ongoing; hard cuts after 1 & 6)
   │
   └─► Phase 9  Release readiness       (after 0–1 and chosen 2–7 scope)
```

Minimum credible first release scope:

- Phase 0 + Phase 1 + Phase 6 complete
- Phase 4 selection/clipboard slice for forms
- Phase 2/3/5/7 as explicitly versioned follow-ons if incomplete

---

## Non-goals (until explicitly reopened)

- Full SwiftUI API parity
- AppKit/UIKit or native Win32 control hosting as the primary renderer
- Desktop/`CopyFromScreen` screenshots as validation
- Making `FoundationApp` or `SwiftWindowsScene` the primary demo path
- Shipping Map/WebView/AV/Store-quality placeholders as Supported features
- Cross-compiling the Windows runtime as a macOS package (shared **source**
  only)

---

## Ownership map (for parallel work)

| Phase | Primary code areas |
| --- | --- |
| 0 CI/tests | `scripts/*`, `.github/workflows/*`, `Tests/` |
| 1 API contract | `docs/WinSwiftUI.md`, `Sources/WinSwiftUI/*`, contracts |
| 2 UIA | `SwiftWindowsPlatform`, `Runtime.swift`, accessibility metadata |
| 3 Settings/HC | `Win32Host.swift`, environment in `Core.swift`, chrome colors |
| 4 Text | `PixelText`, `WindowTextSystem`, `NativeText*`, input in runtime/controls |
| 5 Multi-window | `App.swift` host, `Win32Host`, scene storage |
| 6 Fallback | `WinSwiftUI` host, `RendererHealth`, D3D11 backends |
| 7 Platform | `ClipboardManager`, `FileDialogManager`, dialogs, shell |
| 8 Modules | `Package.swift`, target deps, file splits |
| 9 Release | docs, tags, CI artifacts, samples |

---

## Maintenance

Update this roadmap when:

- a phase exit criterion is met (check the box and note the release/version)
- a limit is lifted (e.g. multi-window becomes real—update baseline section)
- validation scripts gain or lose a required gate

Do not update this file to claim support that is not covered by tests,
contracts, or documented manual smoke paths.
