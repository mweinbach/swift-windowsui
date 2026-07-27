# Changelog

All notable changes to `swift-windowsui` are documented here. The format is
based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the
project follows the versioning policy below.

Entries are written for app authors: feature-level, not commit-level. Every
status claim traces back to [`docs/CompatibilityStatus.md`](docs/CompatibilityStatus.md)
or a named test suite.

## Versioning and compatibility policy

This project uses [Semantic Versioning](https://semver.org/):

- **Patch** releases (`0.1.x`) contain only bug fixes and documentation
  changes. No Supported-tier API is removed or changed in observable
  behavior, except where the previous behavior was a defect.
- **Minor** releases (`0.x.0`) may add APIs and extend the Supported tier.
  **Source compatibility is guaranteed for Supported-tier APIs**: app code
  written against the Supported tier of the previous minor still compiles
  and keeps its documented behavior. Any intentional behavior change in the
  Supported tier requires a changelog entry under `Changed`.
- While the major version is `0`, the **Accepted (shim)** and **Placeholder**
  tiers may change behavior — or gain real implementations — in any minor
  release without a deprecation window. Those tiers are source-compatibility
  conveniences, not behavioral contracts. Do not depend on them for shipped
  behavior; see the tier definitions in
  [`docs/CompatibilityStatus.md`](docs/CompatibilityStatus.md).
- APIs not listed in the compatibility matrix at all carry no guarantee.

The first major release (`1.0.0`) is planned once the Phase 9 exit criteria
in [`docs/StabilizationRoadmap.md`](docs/StabilizationRoadmap.md) are fully
met, including a green hosted-CI release run and the manual release smoke in
[`docs/ReleaseChecklist.md`](docs/ReleaseChecklist.md).

## [0.1.0] — Unreleased

First tagged release. This version is labeled `0.1.0` rather than `1.0.0-rc1`
because a large part of the SwiftUI-shaped surface is still Partial or shim
tier, advanced UI Automation patterns are missing, and the Supported-tier
freeze policy above only takes full effect from `1.0.0`. Dashboard- and
settings-style apps on the Supported tier are the intended audience.

### Added

**Hosting and presentation**

- SwiftUI-shaped app hosting: `App`, `Scene`, `WindowGroup` boot through
  `WinSwiftUIWindowHost` into the retained runtime
  (`RetainedViewRuntime` / `ViewNode`).
- Default presentation path `GPUIScene` → `D3D11BatchRenderer` with
  presentation-order `paintOperations`, typed primitives (quads, glyphs,
  paths, shadows, images), and a CPU rasterizer used for offscreen
  screenshot validation (`GPUISceneTests`, `SceneRasterizerTests`,
  `D3D11BatchRendererTests`).
- Automatic same-session fallback to the `RenderFrame` → `D3D11Renderer`
  path on batch attach/render/resize failure, with two-way recovery under
  `BatchBackendRecoveryPolicy.standard` (backoff 5s → 60s), a `.disabled`
  one-way pin option, `rendererHealthSnapshot` observability, and a
  `SWIFT_WINDOWSUI_FRAME_DEBUG=1` / `-FrameDebug` debug override
  (`FrameFallbackPolicyTests`, `FramePathDegradationTests`,
  `RendererHealthSnapshotTests`).
- Multi-window hosting: `WinSwiftUIWindowCoordinator` opens independent
  windows (own host/runtime/renderer each) through default `openWindow` /
  `dismissWindow` routing for id- and value-based `WindowGroup`s;
  `supportsMultipleWindows` reports true for coordinator-managed hosts
  (`WindowCoordinatorTests`).

**Views, controls, and drawing**

- Layout containers (stacks, lazy stacks, `Grid`, `ScrollView`, `List`,
  `Form`, `Section`, split views, `TabView`, navigation stack/split) and
  the common control set (`Button`, `Toggle`, `Picker`, `Slider`, `Stepper`,
  `ProgressView`, `Gauge`, `Menu`, `TextField`, `SecureField`, `TextEditor`,
  `DatePicker`, `ColorPicker`) with retained chrome, keyboard focus, and
  arrow-key list navigation with scroll-into-view.
- `Canvas` with a SwiftUI-shaped `GraphicsContext` (fills, strokes, opacity,
  transform stack, clipping, draw layers), `Path.contains(_:eoFill:)`, and
  gradient stops with preserved locations.
- Frosted materials (`.regularMaterial` etc.) with true separable-Gaussian
  backdrop blur on both the D3D11 and CPU paths
  (`MaterialBackdropBlurTests`, `D3D11BackdropBlurTests`).
- Per-corner radii end to end, including `UnevenRoundedRectangle` and
  per-corner-aware clipping (`PerCornerRadiiTests`, `PerCornerClipTests`).
- GPU tessellation for rect/triangle/convex/concave-simple fills and all
  stroked paths, with rotated-quad support
  (`PathToQuadTessellatorTests`, `RotatedQuadRasterTests`).
- System icons rendered as real Segoe Fluent/MDL2 glyphs with a
  drawn-vector fallback for ~40 mapped SF Symbol names.

**Text and input**

- DirectWrite glyph-run text with a native glyph atlas and runtime-owned
  logical text layout cache on the default scene path (`GlyphAtlasTests`,
  `TextSystemTests`).
- Text-field editing: caret movement, highlighted selection, shift-extend,
  select-all, mouse-drag selection, and clipboard shortcuts
  (Ctrl+C/X/V/A; secure fields block copy/cut).
- IME composition: WM_IME_* messages produce marked (underlined)
  composition text, commit on completion, and a candidate window positioned
  at the caret (`TextInputIMECompositionTests`).

**Accessibility**

- UI Automation projection of the retained tree (`CUIAInterop` +
  `UIAProviderBridge`): fragment tree via `WM_GETOBJECT`, trait-derived
  control types, live bounds with DPI + ClientToScreen, InvokePattern
  activation of stored accessibility actions, and focus/structure events
  (`AccessibilityProjection` tests, `scripts/demo-uia-probe.ps1`).
- Default accessibility traits on Supported controls.

**Platform integrations**

- Real Win32 open/save dialogs behind `fileImporter` / `fileExporter`,
  with `allowedContentTypes` mapped to extension filters
  (`FileDialogIntegrationTests`).
- Clipboard support for Unicode text and file-URL lists (`CF_HDROP`),
  including `ShareLink` copying real file references
  (`ClipboardFileFormatTests`, `ClipboardButtonTests`).
- OS file drops (`WM_DROPFILES`) delivered to `onDrop` destinations as
  file URLs.
- Opt-in native `ChooseColorW` dialog for `ColorPicker` via
  `\.colorPickerUsesNativeDialog` (keyboard palette remains the default).
- `Link` / `openURL` shell-open URLs via `ShellExecuteW`
  (`OpenURLHardeningTests`).
- System appearance sampling: light/dark preference, Windows high contrast,
  and reduce motion sampled at startup and on
  `WM_SETTINGCHANGE` / `WM_SYSCOLORCHANGE`, with app overrides taking
  precedence; hierarchical greys snap to a legible high-contrast ramp
  (`SystemAppearanceTests`).

**Validation tooling**

- Serial validation ladder (`scripts/agent-check.ps1` `-ContractsOnly` /
  `-Quick` / `-Full`) with machine-checked architecture contracts
  (`scripts/check-contracts.ps1`).
- Gallery visual regression gate: 25 Supported-tier baselines compared with
  bounded per-entry diffs (`scripts/gallery-compare.ps1`, runs in `-Full`
  and Windows CI).
- Raw offscreen screenshot tooling for scene and frame paths
  (`scripts/demo-screenshot.ps1`, `swift-windowsui-snapshot`) — never
  desktop capture.
- Windows CI workflow: contracts on every change, Quick on PRs, Full plus
  screenshot upload on main (`.github/workflows/windows-ci.yml`).
- Machine-checkable macOS design and animation parity constants
  (`docs/MacOSDesignParity.md`, `docs/AnimationParity.md` and their parity
  tests).

### Changed

Relative to the untagged prototype checkouts earlier on `main`:

- The default presentation path is `GPUIScene` → `D3D11BatchRenderer`; the
  `RenderFrame` → `D3D11Renderer` path is now a fallback and explicit debug
  override instead of the primary renderer.
- Batch-backend failure recovery defaults to two-way with exponential
  backoff (`BatchBackendRecoveryPolicy.standard`); pass
  `recoveryPolicy: .disabled` for the historical one-way pin.
- `openWindow` / `dismissWindow` default actions are live coordinator
  routing instead of no-op shims.
- `colorSchemeContrast` is derived from Windows high contrast instead of
  being an override-only value.
- Default control chrome moved to macOS-pinned design constants (dimensions,
  colors, materials) locked by the parity test suites.

### Fixed

Relative to the untagged prototype checkouts earlier on `main`:

- Tessellator rejects non-finite path coordinates instead of producing
  corrupt GPU output.
- Glyph atlas LRU exhaustion always recovers without dropping inserts.
- DirectWrite single-line layout no longer mis-centers glyph origins
  (which had silently forced PixelText fallback).
- Track-style controls (slider, progress bar, circular progress, toggle
  thumb) re-resolve geometry on layout and no longer clip at compact
  widths (`ControlGeometryTests`).
- Menu, sheet, popover, alert, and context-menu overlays clamp to the
  canvas, dismiss via scrim/Escape, and restore focus.

### Known limitations (0.1.0)

- **Not full SwiftUI parity.** The SwiftUI-shaped surface is wide, but much
  of it is Partial or source-compatibility shims; the
  [`docs/CompatibilityStatus.md`](docs/CompatibilityStatus.md) matrix is
  the authority on what is safe.
- **Windows-only package.** Runtime, host, and renderer depend on Win32 and
  D3D11. The same-source story is shared app *source* (`import WinSwiftUI`
  vs `import SwiftUI`), not a cross-platform package.
- **UI Automation level:** fragment tree, properties, InvokePattern, and
  focus/structure events only. No Value/Text/Selection/Toggle patterns, no
  live regions, coarse structure-changed events, `IsOffscreen` not
  provided.
- **Multi-window level:** coordinator-hosted independent windows for
  `WindowGroup` scenes. `Settings` / `openSettings` and `DocumentGroup`
  remain unsupported shims; per-window `@SceneStorage` is in-memory.
- **Text/IME level:** DirectWrite glyph runs and WM_IME composition are in,
  but there is no full shaped-run text engine, no rich `AttributedString`
  editing, no localization table lookup (`LocalizedStringKey` resolves to
  plain strings), and no RTL auto-mirroring of custom drawing.
- **Frame fallback visual subset:** the fallback path executes a reduced
  command set. Rounded clip shapes degrade to rectangular clips, per-corner
  radii fall back to uniform, radial/conic gradients fall back to a solid
  base color, and soft shadows render as plain offset fills (documented in
  [`docs/GPURenderingPipeline.md`](docs/GPURenderingPipeline.md) and the
  roadmap Phase 6 policy table).
- **Placeholder panels** (`Map`, `WebView`, `VideoPlayer`, `Chart`, PDF,
  camera, StoreKit/TipKit surfaces, …) are non-interactive labeled panels,
  not product features.
- Manual release-smoke items (live CJK IME, Narrator pass, high-contrast
  theme toggle, real dialogs, hardware materials) are checklist-verified
  per release rather than automated; see
  [`docs/ReleaseChecklist.md`](docs/ReleaseChecklist.md).
