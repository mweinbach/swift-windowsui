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
- Accessibility modifiers store retained metadata; **native UI Automation is
  not implemented**.
- `EnvironmentValues.colorSchemeContrast` exists; **Windows high-contrast /
  system-settings wiring is not implemented**.
- `EnvironmentValues.supportsMultipleWindows` defaults to `false`;
  `openWindow` / `dismissWindow` are **no-ops** unless injected. One live
  `WindowGroup` is the current host model.
- Local validation scripts are strong. `.github/workflows/windows-ci.yml` now
  runs contracts on every change, Quick on pull requests / branch pushes, and
  Full plus screenshot upload on main, schedule, and manual dispatch. Hosted
  runner results still need to be monitored for toolchain drift.
- Shared demo source aims for import-swappable macOS SwiftUI compatibility;
  the package itself remains **Windows-only** for runtime/host/renderer.

Architecture invariants that every phase must preserve:

- App path: `WinSwiftUI.App` / `WindowGroup` → `WinSwiftUIWindowHost` →
  `Win32Window` → `RetainedViewRuntime` → `GPUIScene` → `D3D11BatchRenderer`
- `GPUIScene.paintOperations` is presentation-order source of truth
- Screenshots stay raw retained-runtime rasterization (no `CopyFromScreen`)
- Same-source demo contract (`import WinSwiftUI` / `import SwiftUI`)
- Main-actor UI surface; `Runtime.swift` remains layout/focus/animation truth

---

## Immediate next wave — Product UI polish

The stabilization baseline is now locally green: all 73 test targets pass,
the demo builds, scene and frame screenshots generate, and the 84-entry gallery
renders. The next work should deepen visible quality instead of adding more
source-only API surface.

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

- [ ] Reviewed gallery baselines fail CI on meaningful visual regressions
- [ ] Supported controls render without clipping at documented minimum widths
- [ ] Text fields support selection, clipboard, caret, and IME smoke flows
- [ ] Lists/forms support mouse and keyboard navigation with stable row chrome
- [ ] Demo includes at least three product-style screens and resize snapshots
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
  `matchedGeometryEffect` interpolation, programmatic `ScrollViewProxy`
  scrolling, multi-window actions, Settings scene, full grid semantics,
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

- [ ] Published Supported / Accepted / Placeholder matrix for app-facing APIs
- [ ] Every Supported control/modifier has at least one automated test or
      screenshot-backed demo usage
- [ ] Placeholder panels remain clearly non-functional (no accidental
      “works” claims)
- [ ] Same-source demo still builds against the documented subset
- [ ] Contract script still passes; no second parallel UI abstraction

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
- Docs explicitly state: **native Win32 UI Automation exposure is not
  implemented yet**.
- Focus traversal, hit testing, and keyboard activation exist in
  `RetainedViewRuntime` but are not projected as a UIA tree.

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
6. Document remaining gaps (live regions, full text patterns, virtualized
   lists) honestly.

### Exit criteria

- [ ] Narrator (or equivalent UIA client) can read labels for primary demo
      controls and activate default button actions
- [ ] Focus changes update UIA focus; bounds track layout after resize
- [ ] Hidden / `accessibilityHidden` nodes omitted or marked correctly
- [ ] Mapping unit tests green; contracts still pass
- [ ] Docs state remaining UIA pattern gaps

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
- Increased contrast brightens some semantic `.secondary` foregrounds.
- **Not wired** to Windows high-contrast themes or a full semantic color
  system (`docs/WinSwiftUI.md`).
- `Win32Host` already handles some `WM_SETTINGCHANGE` traffic; luminance /
  capture / reduced-motion style environment values are mostly overrideable
  defaults, not OS-derived.

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
- [ ] Supported demo controls remain legible in high contrast
- [ ] Semantic colors do not hard-code low-contrast greys when HC is on
- [ ] Unit tests cover mapping tables; screenshot optional HC fixture
- [ ] Docs describe precedence: app override > system > toolkit default

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
- Inputs: `TextField` / `SecureField` / `TextEditor` support basic insertion,
  delete, caret left/right/home/end; `TextSelection` types and selection
  bindings exist; selection UX is incomplete relative to desktop editors.
- Localization: `LocalizedStringKey`, tables, `LocalizedStringResource`,
  locale/calendar/timeZone environment values partially used (e.g.
  `DatePicker`); not a complete resource catalog / pluralization story.
- Clipboard: `ClipboardManager` supports Unicode text copy/paste; multi-format
  is thin.
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
4. **IME / composition (stretch within phase if host allows):**
   - at least document current WM_CHAR / virtual-key limits
   - plan WM_IME composition path without blocking earlier selection work
5. Tests for selection ranges, clipboard round-trip, locale formatting, and
   RTL smoke layouts.

### Exit criteria

- [ ] Supported text inputs: select, copy, cut, paste, select-all work in demo
- [ ] Selection binding updates are observable in tests
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

- [ ] Demo or gallery can open a second window via `openWindow`
- [ ] Closing windows does not tear down unrelated runtimes incorrectly
- [ ] `supportsMultipleWindows` reflects reality
- [ ] Per-window invalidation/render loops remain main-actor safe
- [ ] Automated host tests cover open/dismiss; manual multi-monitor smoke

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

### Exit criteria

- [ ] Written policy in this doc + `docs/GPURenderingPipeline.md` agree
- [ ] Injected batch failure falls back without crashing the host session
- [ ] Recovery restores scene backend under `.standard` when attach succeeds
- [ ] `.disabled` remains one-way for the session
- [ ] Full agent check still produces both scene and frame artifacts
- [ ] README/WinSwiftUI docs do not claim frame ≡ scene visual parity

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
| Clipboard | Unicode text copy/paste via `ClipboardManager` |
| File dialogs | `FileDialogManager` open (and related) Win32 common dialogs |
| Drag/drop | SwiftUI-shaped APIs + retained metadata; limited OS formats |
| Open URL | Compatibility helper present; verify shell execute path |
| Undo | Per-window `UndoManager` shim; not fully bridged to edit commands |
| Color picker | Retained palette keyboard UI; **no** native color dialog |
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
- [ ] Clipboard + file dialog paths covered by automated tests where host
      allows (or demo-probe hooks)
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
- `WinSwiftUI` (depends on UI + **D3D11** today)
- `SwiftWindowsApp`, demo/snapshot/gallery executables
- `SwiftWindowsScene` alternate scene path (not primary demo path)
- `CDirect2DInterop` for native text/graphics interop

Coupling pressure:

- `WinSwiftUI` links `SwiftWindowsRendererD3D11` directly
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

- [ ] Dependency graph documented and contract-checked where feasible
- [ ] App-facing import remains `import WinSwiftUI` on Windows
- [ ] Backend selection still defaults to scene/batch with frame fallback
- [ ] `swift test` and demo products build without circular targets
- [ ] No parallel retained-runtime rewrite

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
6. **Release checklist** (below) signed off on a clean machine and CI.

### Exit criteria

- [ ] Tagged release with matching changelog
- [ ] Phase 0 Full CI green on release commit
- [ ] Supported API matrix published for that version
- [ ] Known limitations section lists: incomplete SwiftUI parity, UIA level,
      multi-window level, text/IME level, frame visual subset, Windows-only
      package
- [ ] No Supported API documented as working when it is placeholder/no-op
- [ ] Screenshot artifacts attached to release or CI run for scene + frame

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

Manual release smoke:

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
