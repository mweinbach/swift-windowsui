# Application failure reporting

A Windows application can implement `static func handleFailure(_ failure:
AppFailure) async` on its normal `App` type. No host reference, renderer import,
or polling is required. The default handler calls
`await failure.presentNativeAlert()`.

The immutable, `Sendable` event contains `kind`, `message`, and an optional
`window` value with a per-instance UUID, declared scene ID, and title. A UUID
distinguishes two windows created from the same scene. It is not a native window
handle or a capability to act on the window.

```swift
static func handleFailure(_ failure: AppFailure) async {
    // Write app-specific diagnostics or update an app-owned observable model.
    print("Application failure: \(failure.kind): \(failure.message)")
    await failure.presentNativeAlert()
}
```

The handler runs on the main actor. The native alert uses an ownerless Windows
dialog on a worker, so neither the main actor nor the native window owner blocks
while the user reads it. It needs no functioning retained renderer. It does not
retry graphics work, close unsaved windows, or promise a usable renderer after
dismissal. Apps that replace the default handler are responsible for providing
visible feedback that still works when rendering is unavailable.

## Delivery boundaries

- `presenterUnavailable` follows the existing bounded attach retry budget. It is
  delivered at most once per window lifetime, after native presentation work
  and its actor reply have settled and on a later main-actor turn. New queued
  work delays delivery through the existing drain barrier; closed or recovered
  windows suppress stale events. The host remains owned and closable. This is
  **not** proof that renderer cleanup or native window destruction succeeded.
- `startup` is delivered only after the existing native-owner stop operation
  successfully confirms thread join and the coordinator has no remaining
  windows, starts, preparations, failed rollback hosts, or diagnostics drain.
  The failure handler is awaited before the existing exit status of 1. It must
  return for that exit to proceed.
- A failed owner start, rollback, owner stop, or other fatal ownership failure
  can leave native ownership unproven. Those paths keep their existing print
  and immediate fatal exit policy and **do not** call arbitrary app code or
  delay shutdown for a dialog. Synchronous custom-platform startup and event
  loop errors retain their existing print/return behavior; this API does not
  claim a cleanup guarantee for those paths.
- Directly constructed internal hosts do not gain default dialogs. Only the
  normal `App` composition path installs the app handler.

The focused headless coverage is `AppFailureReportingTests`; the existing
`NativeWindowCoordinatorTests`, `NativeHostPresentationQueueTests`, and
`HostPresenterWedgeTests` continue to protect ownership, drain ordering, and
retry limits. Headless tests do not qualify real Windows alert visibility or
screen-reader behavior; native acceptance remains a separate check.
