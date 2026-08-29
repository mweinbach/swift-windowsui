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
start them, and own the event loop. `Win32PlatformHostFactory` also exposes the
explicit `Win32NativePlatformHostFactory` capability. With a native presentation
factory, the default app enters public `dispatchMain()` and runs a separate
Win32 owner thread. The synchronous factory methods remain the legacy and
headless contract; custom factories that do not opt into both capabilities
retain that path. The current retained window host still
requires the factory-created window to be a `Win32Window`, so integrating a
second real platform also requires replacing that concrete host assumption
and providing platform-native text, image, accessibility, dialogs, and
presentation services.

The native owner initializes its COM apartment as STA, creates HWNDs, dispatches
messages, samples native geometry, owns renderer attachments, executes native
dialogs, and releases those resources. It balances successful COM initialization
only after actual native cleanup; fatal parking does not claim that cleanup.
Retained layout, model state, bindings, input actions, and scene construction stay
on MainActor. `NativeWindowKey` separates window identity from the lifetime of a
reusable handle, while a separate surface generation rejects stale rendering
commands. Checked Sendable commands and copied results cross this boundary;
native attachments and UI objects do not.

Input is copied before delivery to an ordered actor queue. Pointer movement and
left-button events retain their captured scale and lifetime/frame identity.
Legacy delegates keep their physical-coordinate payloads and synchronous APIs.
Painting and animation messages request actor work; they do not run a retained
render while waiting on the actor. A settled window does not need a polling
frame loop to service an app task.

The input transport reserves 1,024 queued record slots and accounts at most
16 MiB of queued copied string bytes, URL spellings/array entries, and touch
points per window. At most one record is being delivered outside that queue.
Its fixed ring reuses released slots. Automatic MainActor turns consume at most
32 records and reschedule once; synchronous catch-up captures a finite accepted
boundary. Only the existing paint/animation requests coalesce. These are
transport accounting limits, not hard OS memory caps: they do not measure
Foundation/COW allocation capacity or buffers constructed before admission.
Essential-input overflow revokes the lifetime and fails the native owner
explicitly. A reserved one-shot notification retains the last accepted sequence;
the rejected sequence is never published or committed. Already accepted input
keeps FIFO order, while synchronous queries reject the terminal lifetime even
at an older committed boundary. No new native-to-actor blocking catch-up is
introduced by exhaustion.

The command mailbox admits at most 128 queued ordinary creates/commands. Each
actually owned window lifetime separately reserves 32 queued close requests,
32 queued deferred close wakes, and one final destruction request held through
its terminal reply. One stop marker has its own reservation. All accepted work
remains in the same FIFO with distinct replies; these reserves do not promote,
replace, or silently coalesce commands. For N owned lifetimes the queue has at
most `128 + 65 * N + 1` slots. A command already executing belongs to its native
caller, outside the queued-work count; dequeuing a close request or deferred
wake releases its queued slot, unlike the final destruction reservation.
Start and stop have at most 32 waiters each. Unknown or stale window keys cannot
consume lifecycle reserves, and ordinary saturation does not consume them.
Rejection clears the matching reservation and completes its owned reply outside
locks. These counts scale with authored window count and do not bound arbitrary
authored command payload sizes or allocations made before admission. Timer
policy holds only the latest unsent desired value and one admitted request;
applied state comes from the matching actual reply and native surface
generation, never admission alone. Failed requests do not install a policy or
trigger an automatic retry.

Queued rejection claims every detached batch reply before delivering the first
callback. Commands expose a concrete Core reply capability; the queue captures
that capability and request identity before locking, and only Core claim logic
runs under the queue lock. The lock order is Queue then close Phase, released
before entering Reply. Neither Phase nor Reply enters Queue while locked.
Retained payloads and one-shot deliveries leave the locks before callbacks or
their last captured-object releases. An alias sharing a claimed reply cannot
gain a new native admission or replace that reply's original result. Terminal
claim, callback delivery, actor consumption and actual OS-thread join remain
separate acknowledgements; none proves the next one.

The new, unshipped `NativeWindowOwnerCommand` protocol now requires
`commandReply`, constructed from the same stable `NativeWindowReply` used by
execution. Custom conformers must put queued-rejection cleanup in that reply's
callback. A custom `reject` override remains an execution-error/direct-sink hook;
the mailbox does not invoke it for queued rejection. This source migration does
not change the legacy or headless host APIs. Detached failure batches retain
their payloads until outside-lock delivery; the queue limits are not limits on
arbitrary authored callback recursion or total process memory.

Fatal exhaustion is observable without waiting for a native dialog or command to
return. Queued ordinary work and uncommitted lifecycle waiters fail; an executing
ordinary operation or committed destruction keeps its real reply if it returns.
The actor's process-fatal exit may instead terminate that operation
before its outcome is known. This resource-exhaustion policy is not graceful
close, successful native cleanup, or a claim of normal-load qualification.

Every synchronous native-to-actor query must finish without further native-owner
progress. UI Automation and IME use explicit value requests; their actor bodies
cannot await native commands. Built-in dialogs and system URL effects use separate
command completions. Provider payloads and transport HRESULTs stay separate, so a failed
hop or revoked lifetime cannot become a successful false/empty action result.
A heap UIA call lease spans queued actor work and the remaining C marshalling.
COM identity methods remain callable independently of live-window admission.

External COM calls read an immutable owner-published geometry revision instead
of queueing a refresh on a native thread that may itself be inside outbound COM.
The actor rejects reentry and mismatched surface generations before consulting
the retained source. This is not a fresh OS geometry sample for every query, nor
does it change the retained host's existing live-resize layout coalescing policy.
`UiaHostProviderFromHwnd` still runs on its COM caller under the full-call lease;
ownership of the HWND does not imply that every COM method executes on its thread.
Legacy UIA callbacks keep the dispatch-context marker and `MainActor` assertion.

Startup creates a hidden window, installs the native dialog/accessibility and
presentation state, activates it, then awaits the initial presentation result.
During the gap before native dialog ownership, retained presentation requests
remain pending rather than falling through to a synchronous legacy dialog.
Readiness comes from a successful current view build, so superseding the initial
bind reload cannot strand those requests. A dialog session submits its next
request only after the previous native result and actor completion/reset have
finished, rechecking each deferred request's retained lifetime before submission.
Window construction reserves actor admission before authored content/factory
callbacks and rechecks it afterward. Reentrant construction fails explicitly;
closing the last window prevents a callback from admitting a replacement after
termination has been reserved.

Normal close keeps the prepared actor policy/participant lease until the native
result is known. The native owner stops new callback admission, waits for complete
admitted calls and native operations to drain, detaches presentation resources,
then destroys the HWND. A successful close requires `WM_NCDESTROY`, native dispatch
unwind, completion of the actor lease, and actor consumption of any in-flight
presentation reply. The coordinator also waits for the matching diagnostics task
and actual thread join before normal exit. A cleanup
failure retains its resource ownership and error; it is not a synthetic close.
The legacy synchronous path still checks the current window list before quit;
an earlier host's release callback may open a replacement before that check.
An unrecoverable owner-loop failure with live resources reports a fatal error
and parks the failed owner for process termination, without claiming graceful
destruction or a successful join.

These ownership changes require compilation and native UIA, IME, modal, rendering,
input, failure and idle-wake qualification. Source checks and controlled headless
tests are not proof that those native gates have passed. Arbitrary authored code
that calls native APIs synchronously is not automatically made safe by this split.
Built-in Link/Help system launches use the native command path; directly calling
the public synchronous `OpenURLAction.system` from authored code retains its
legacy synchronous result and is not covered by that adaptation.
Clipboard stores and authored paste callbacks also remain synchronous. There is
no owner-command wait in that source path, but external delayed clipboard data
and clipboard-manager reentry need native UIA/IME qualification.
The existing native `DocumentGroup` admission restriction remains in place.

## Rendering-engine boundary

`RenderBackendFactory` creates renderer-neutral implementations of:

- `RenderBackend` for retained `RenderFrame` commands.
- `BatchRenderBackend` for presentation-ordered `GPUIScene` primitives.
- `RenderBackendCapabilities` for truthful frame/scene support, native-window
  versus offscreen targets, execution model, capture, and presentation pacing.
- `makeNativePresentationFactory()` opts into constructing non-Sendable backend
  state on the native owner. The default is nil for existing custom factories;
  D3D11 and the software window presenter supply this capability. Their public
  MainActor renderer APIs remain available for legacy callers.

Native presentation commands retain real attach, resize, render, capture,
configuration and teardown results. Command admission is not a submitted frame;
an occluded, skipped, failed or stale-generation result cannot advance the host's
presented content revision. Final renderer snapshots and cancelled GPU timing
results are handed back before native teardown acknowledgement.

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
