# Host Runtime Test Seams

Factual constraints that matter when adding host/runtime validation for this mission.

## DPI / Scale

- `WinSwiftUIWindowHost.window(_:didResizeTo:)` reads `window.scaleFactor` when updating `runtime.displayScale` and logical root size.
- `Win32Window.scaleFactor` is derived from `GetDpiForWindow(hwnd)` in `Sources/SwiftWindowsPlatform/Win32Host.swift`.
- A test that only mutates `SurfaceDescriptor.scaleFactor` does **not** prove the production DPI path; host-facing validation needs a seam that exercises or fakes the real `window.scaleFactor` lookup.

## Refresh Rate / Timer Cadence

- `WinSwiftUIWindowHost.syncAnimationDriver(for:)` reads `window.monitorRefreshRate` directly, then derives both `runtime.minimumFrameInterval` and the animation-timer interval from that value.
- Host tests that only assert recorded timer state without driving a changed `monitorRefreshRate` do **not** prove refresh-rate propagation.
- Validator-visible proof for refresh pacing therefore needs a seam that can vary the production `window.monitorRefreshRate` input.
