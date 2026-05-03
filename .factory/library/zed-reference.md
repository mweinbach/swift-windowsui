# Zed Reference

Mission-specific summary of GPUI patterns to preserve in Swift-native form.

**What belongs here:** durable architectural patterns taken from the local `extern/zed` checkout.
**What does NOT belong here:** Rust API details that we do not intend to mirror directly.

---

## Preserve These Patterns

- Typed scene primitive families instead of one opaque draw-command enum.
- Per-window frame state with replayable paint output and deferred draw metadata.
- Separation between prepaint/interactivity metadata and paint submission.
- Bounds-based draw ordering plus explicit layer/scoped-layer regions.
- Text layout caches separated from glyph atlas caches.
- Atlas-backed glyph/image submission owned by renderers, not by view code.
- Soft-failure behavior for unsupported features while the renderer is incomplete.

## Do Not Mirror These Directly

- Rust entity/context borrow model.
- Trait-object-heavy view APIs.
- Macro-driven ergonomics.
- Rust-specific effect queue patterns.

## Best Fit For This Repo

- Keep the retained `ViewNode` runtime.
- Port GPUI render mechanics into `SwiftWindowsGraphics`, `SwiftWindowsUI`, and `SwiftWindowsRendererD3D11`.
- Use Zed’s architecture to guide scene structure, replay, text/atlas policy, and downgrade behavior, not to replace `WinSwiftUI`.
