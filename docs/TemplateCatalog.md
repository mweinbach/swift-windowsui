# Application template catalog

The eight templates in [goal.md](../goal.md#7-reusable-ui-templates-and-reference-applications)
remain the required catalog. The current demo is a shared-source application
foundation, not eight completed templates. Its view code imports Apple SwiftUI
on macOS and WinSwiftUI on Windows; platform and renderer selection remain in
the executable composition root.

| Required template | Current implementation and remaining work |
| --- | --- |
| Application shell | Dashboard/settings/data/gallery navigation, responsive chrome, command palette, shortcuts, and coordinator-managed windows. Settings now has a separate scene. Complete command menus, restoration, and all scene lifecycles still need qualification. |
| Dashboard | Cards, metrics, deterministic local model changes, and component detail panels. A full chart integration and complete asynchronous loading/failure workflows remain open. |
| Settings and forms | Shared form, input validation, dirty state, explicit save/reset, theme and text-size controls, injectable persistence, and restart/error tests as detailed below. Audio/telemetry flags are sample configuration; native accessibility and macOS workflow qualification remain open. |
| Data browser | Search, sorting, filters, pagination, selection, and detail inspector. Viewport-bounded row construction and a complete large-data template remain open. |
| Document or editor | Native file services and editable controls provide building blocks; a complete open/edit/undo/save/unsaved-change/document-window template is still required. |
| Media or file browser | Image loading and file-drop primitives provide building blocks; the complete thumbnail, failure/retry, selection, preview, and drag/drop workflow remains open. |
| Navigation and presentations | Navigation and presentation examples exist in the gallery. A complete master/detail application with all competing-input and focus-restoration flows remains required. |
| Animation and drawing lab | Gallery primitives and motion examples exist. The complete interruptible transitions, matched geometry, keyframe, effects, and gesture lab remains required. |

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
