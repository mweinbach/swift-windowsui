# Application template catalog

The eight templates in [goal.md](../goal.md#7-reusable-ui-templates-and-reference-applications)
remain the required catalog. The current demo is a shared-source application
foundation, not eight completed templates. Its view code imports Apple SwiftUI
on macOS and WinSwiftUI on Windows; platform and renderer selection remain in
the executable composition root.

| Required template | Current implementation and remaining work |
| --- | --- |
| Application shell | Dashboard/settings/data/gallery navigation, responsive chrome, command palette, shortcuts, and coordinator-managed windows. Settings now has a separate scene. Complete command menus, restoration, and all scene lifecycles still need qualification. |
| Dashboard | Cards, metrics, component detail panels, and the existing interactive chart now include a bounded local JSON loading/empty/error/Retry/Cancel workflow. The initial chart is an explicit preview; see [Dashboard data loading](DashboardDataLoading.md) for source limits and pending runtime/visual/platform qualification. |
| Settings and forms | Shared form, input validation, dirty state, explicit save/reset, theme and text-size controls, injectable persistence, and restart/error tests as detailed below. Audio/telemetry flags are sample configuration; native accessibility and macOS workflow qualification remain open. |
| Data browser | Search, sorting, filters, pagination, selection, and detail inspector. Viewport-bounded row construction and a complete large-data template remain open. |
| Document or editor | Shared `DemoDocumentScene` and a strict UTF-8 value document now exercise typed per-window sessions, writable configuration, real regular-file open/save, one model undo authority, saved checkpoints, and Save/Discard/Cancel intent through an explicit headless host. TextEditor shares shaped visual lines for navigation and its own keyboard caret reveal. Default/native DocumentGroup activation remains disabled until final close approval and an owned deferred wake are integrated. Decision UI, application commands, full wheel/UIA scrolling, and the complete native workflow still require qualification; see [DocumentSessions.md](DocumentSessions.md). |
| Media or file browser | Image loading and file-drop primitives provide building blocks; the complete thumbnail, failure/retry, selection, preview, and drag/drop workflow remains open. |
| Navigation and presentations | Navigation and presentation examples exist in the gallery. A complete master/detail application with all competing-input and focus-restoration flows remains required. |
| Animation and drawing lab | Gallery primitives and motion examples exist. The complete interruptible transitions, matched geometry, keyframe, effects, and gesture lab remains required. |

## Document stage and activation gate

`DemoDocumentScene` uses `configuration.$document` and a mounted selection
binding through public SwiftUI-shaped source. Its internal Windows host stage
owns a real session before the first build and keeps that session across
reconciliation. Headless routing decodes actual `.txt` files within a 16 MiB
synchronous input ceiling, and Save returns success only after atomic file
replacement. Model history mixes direct document writes and accepted editor
edits without registering duplicate inverses. Errors and cancelled operations
preserve the current editor, model, and previous saved checkpoint.

This scene is not registered in the default executable. Native
`DocumentGroup` activation fails before model creation or file access. The
session's close intent and final reservation are exercised with injected
headless ownership; native participant/finalization and deferred delivery must
be integrated and tested before any live unsaved-close workflow is enabled.
The existing `windowDismissBehavior(.disabled)` veto and retained
`interactiveDismissDisabled` remain separate policies. Neither establishes a
completed document decision UI or licenses destruction after a stale save.

## Run and inspect the current application

On Windows, use the normal serial validation and build entrypoints:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/build.ps1 -Product swift-windowsui
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run-demo.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/demo-screenshot.ps1 -Screen settings
```

The application executable opts into a per-user local settings file. The
snapshot executable uses an isolated in-memory store, so user preferences do
not change regression images. Raw screenshots continue through the retained
snapshot renderer; no desktop capture is involved.

Ordinary WindowGroup windows now construct independent root view values.
`DemoRootView` owns a window-local `DemoWindowState` above its tabs and passes
it through the standard environment. Scroll offsets, visibility, and phase
readouts therefore belong to that window's viewport; a newly opened window
does not reset another one's readouts. The bright-preview choice remains in
the shared gallery model, while a remounted viewport samples fresh geometry
and starts with an idle phase. This explicit owner does not establish general
nested State/StateObject lifetime conformance in WinSwiftUI.

The same application sources build on macOS with `swift build --product
swift-windowsui`. A native build and behavior run at the pinned reference
revision are still required; Windows tests do not establish that result.
See [Testing.md](Testing.md) for toolchains and the full validation ladder.

## Settings and forms extension points

- [DemoSettingsTemplate](../Sources/SwiftWindowsDemo/DemoSettingsTemplate.swift)
  exposes the existing settings view for a standalone `Settings` scene. It
  uses the same observed model as the settings tab, including theme, tint,
  text scale, validation, and dirty state.
- [DemoDashboardModel](../Sources/SwiftWindowsDemo/DemoDashboard.swift)
  owns editable and last-saved values. Reset changes the editable values; it
  does not silently write defaults to disk or hide a persistence error.
- [DemoSettingsStore](../Sources/SwiftWindowsDemo/DemoSettingsStore.swift)
  accepts load/save closures, an explicit file URL, an isolated memory store,
  or the application store. This adapter is shared Foundation code and does
  not expose retained nodes or renderer APIs.
- [AppEntry](../Sources/swift-windowsui/AppEntry.swift) registers the ordinary
  `WindowGroup` and `Settings` scene and supplies `.application` storage.
  Windows keeps its D3D11 factory at this composition root. Ctrl+, opens or
  reactivates the Settings window; Ctrl+S saves the visible form. The same
  source uses the platform's command modifier on macOS.

The settings file is `SwiftWindowsUI/Demo/settings.json` beneath Foundation's
per-user Application Support directory. Failure to locate that directory is
reported; the application never substitutes a temporary file while claiming
to save persistently. Tests use temporary directories or explicit injected
stores and must not touch the real application file.

The version-1 JSON schema stores display name, theme, page size, motion/audio/
usage flags, font scale, and resolved accent components. It accepts names up
to 200 characters, page sizes 1–100, font scale 0.8–1.4, finite extended RGB
components within -16–16, and opacity 0–1. Reads are bounded to 64 KiB plus an
overflow byte. Unsupported schema versions, malformed data, invalid values,
and unavailable files produce a visible warning and leave the source file
untouched. Explicit Save replaces the file atomically only after the complete
record validates and encodes. There is no automatic schema migration.

A write failure preserves the previous saved record, the current edits, and
dirty state. The form does not report success; pressing Save again retries.
Reset also preserves the failure warning until a successful save. The
bounded store is synchronous; asynchronous storage and multi-process conflict
resolution are not implemented by this template slice.

The audio and usage-sharing flags currently persist as example configuration.
They do not play audio or transmit telemetry. Do not describe those toggles
as completed integrations. The theme, accent, font scale, and page size feed
the existing application controls and data view.

## Reproducible checks

`DemoSettingsPersistenceTests` covers restart round trips for all saved fields,
Unicode names, unsaved edits, isolated snapshot defaults, malformed/oversized/
unsupported data, real filesystem failures, atomic replacement, retry, reset,
validation, the keyboard save path, and visible errors. `SettingsSceneHostingTests`
covers scene collection, availability composition, environment propagation,
singleton activation requests, close/reopen behavior, failure cleanup, and
scene-storage isolation. Native foreground activation remains subject to
Windows policy and is not guaranteed by a successful routing result.

These tests support the template requirements; they do not replace real
keyboard, Narrator, display-scale, macOS, or clean-machine qualification.
