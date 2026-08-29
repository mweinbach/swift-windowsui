# Platform and Rendering Architecture

The project separates three different concerns: reusable UI data and drawing
contracts, the native platform that supplies windows and input, and the engine
that turns retained scenes into pixels. These boundaries are real, but they do
not imply that the complete Windows retained UI stack already runs everywhere.

## Portability matrix

| Component | Windows | macOS | Linux | Boundary |
| --- | --- | --- | --- | --- |
| `SwiftWindowsCore` | Supported | Portable product | Portable product | Geometry, input, surfaces, host contracts, clipboard protocol, monotonic clock |
| `SwiftWindowsGraphics` | Supported | Portable product | Portable product | Renderer-neutral scenes, frame commands, backend factories, CPU rasterizer |
| `SwiftWindowsLayout` | Supported | Portable product | Portable product | Renderer- and platform-neutral layout primitives |
| `SwiftWindowsScene` | Supported | Portable product | Portable product | Secondary renderer-neutral scene abstraction |
| Shared demo source | `WinSwiftUI` retained engine | Native Apple `SwiftUI` engine | Not provided | Same app/view source, different UI implementation |
| `SwiftWindowsPlatform` | Win32 implementation | Not provided | Not provided | Implements the neutral platform-window/event contract |
| `WinSwiftUI` / `SwiftWindowsUI` | Supported | Not provided | Not provided | Still depends on Win32 host integration and Windows text/image services |
| D3D11 window renderer | Supported | Not provided | Not provided | Concrete graphics-device backend |
| CPU reference renderer | Offscreen | Offscreen | Offscreen | Portable scene/frame rasterization, not a window presenter |
| CPU software presenter | Win32 window | Not provided | Not provided | Portable rasterization plus a Windows-specific native blit |

The macOS demo uses Apple's SwiftUI. It does not run the Windows retained
runtime, Win32 event loop, Windows accessibility implementation, or D3D11.
Portable clients use `SwiftWindowsCore.Size` alongside Foundation's own
`CGSize` without a naming collision; the Windows `WinSwiftUI` compatibility
facade continues to provide its SwiftUI-shaped `CGSize` alias.

## Platform boundary

`SwiftWindowsCore` defines portable main-actor interfaces:

- `PlatformWindowConfiguration`: requested title, client size, size limits,
  placement, and window behavior.
- `PlatformWindow`: lifecycle, opaque native surface, display scale, refresh
  rate, invalidation, animation timing, and coordinate conversion.
- `PlatformWindowHost`: platform-neutral lifecycle/input event receiver.
- `PlatformWindowEvent`: keyboard, pointer, scrolling, text, IME, touch,
  accessibility-relevant lifecycle, display, and file-drop events.
- `PlatformHostFactory`: native window construction and event-loop ownership.
- `PlatformClock`: monotonic timestamps shared consistently by host and runtime.
- `ClipboardTextStore`: injectable Unicode text clipboard service.

`Win32PlatformHostFactory` and `Win32Window` implement the current native
adapter. A different platform can implement these same protocols without
importing WinSDK, and the contract tests exercise an independent fake host.
`WinSwiftUI.App.platformHostFactory()` injects that platform decision into the
real window coordinator, which asks the selected factory to create windows,
start them, and own the event loop. The current retained window host still
requires the factory-created window to be a `Win32Window`, so integrating a
second real platform also requires replacing that concrete host assumption
and providing platform-native text, image, accessibility, dialogs, and
presentation services.

The native pointer-move and left-button delivery paths copy coordinates and
effective display scale before entering the retained host. Their package-only
context binds that value to the originating window lifetime and one synchronous
delivery frame; nested callbacks keep their own context, and the retained host
consumes each frame before invoking runtime callbacks. Public legacy and neutral
delegates keep their synchronous API and physical-coordinate payloads. Other
input families still use their existing callbacks. This boundary does not move
HWND ownership, change the message pump, or service queued MainActor tasks;
UI Automation, IME caret queries, modal dialogs, rendering, and close teardown
retain their existing ownership and synchronous result requirements.

## Rendering-engine boundary

`RenderBackendFactory` creates renderer-neutral implementations of:

- `RenderBackend` for retained `RenderFrame` commands.
- `BatchRenderBackend` for presentation-ordered `GPUIScene` primitives.
- `RenderBackendCapabilities` for truthful frame/scene support, native-window
  versus offscreen targets, execution model, capture, and presentation pacing.

`RenderSurfaceTarget.window` carries an opaque `NativeWindowHandle`.
`RenderSurfaceTarget.offscreen` contains no handle, so
`SurfaceDescriptor.windowHandle` is optional and existing callers that read
its properties must unwrap it or switch on `target`. The CPU reference backend
genuinely renders offscreen and rejects native-window attachment; native D3D11
and Win32 software presenters reject offscreen attachment because they require
an actual window. The software presenter composes those two capabilities by
rasterizing into a genuine offscreen surface and then blitting the resulting
bitmap to its separately owned native window.

The composition root defaults to D3D11 and can select a complete CPU software
window presenter without changing the app, views, layout, retained runtime,
scene ordering, or accessibility tree:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run-demo.ps1 -Backend d3d11
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run-demo.ps1 -Backend software
```

The equivalent explicit override is `SWIFT_WINDOWSUI_RENDER_BACKEND=software`.
The dashboard derives its displayed renderer name and component identity from
the selected engine. A factory that can produce only offscreen pixels is not a
valid live-window presenter and falls back to a genuinely presenting factory.

Adding Metal, Vulkan, WebGPU, or another GPU renderer still requires writing a
real backend, shaders, resource/atlas uploads, presentation integration,
recovery policy, and parity tests. A neutral interface does not manufacture
those platform-specific implementations automatically.

## What remains before a second retained-runtime platform

1. Make the existing `WinSwiftUI.App` / `WindowCoordinator` factory-injection
   path accept a platform-neutral window host rather than requiring the
   factory-created window to be a `Win32Window`.
2. Extract DirectWrite/GDI text shaping and WIC image decoding behind portable
   services with native implementations for the target platform.
3. Move platform appearance sampling, accessibility bridges, native dialogs,
   shell integration, and input-method composition behind corresponding
   platform-owned adapters.
4. Supply a real window-presenting renderer for that platform, or bridge the
   CPU rasterizer to its native surface.
5. Verify the same retained app through the portable host, backend conformance,
   pixel-parity, accessibility, and lifecycle suites on the target OS.

## Verification

Portable products and tests:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-portable.ps1 -BuildProducts
```

```bash
swift build --target SwiftWindowsCore
swift build --target SwiftWindowsGraphics
swift build --target SwiftWindowsLayout
swift build --target SwiftWindowsScene
swift test --filter SwiftWindowsPortableTests
```

`.github/workflows/portable-ci.yml` runs this matrix on Ubuntu and macOS; the
macOS job also builds the same-source native SwiftUI demo. Windows Quick and
Full checks run the independent portable tests alongside platform-host,
offscreen-surface, renderer-interchangeability, modal-isolation, clipboard, and
demo renderer-identity regressions.
