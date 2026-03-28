# Architecture

How the system works at a high level for this mission.

**What belongs here:** major components, ownership boundaries, data flow, architectural invariants.
**What does NOT belong here:** per-feature checklists or detailed worker procedures.

---

## Current End-to-End Path

The active demo path is:

`AppEntry.swift` -> `WinSwiftUI.App` / `WindowGroup` -> `WinSwiftUIWindowHost` -> `Win32Window` callbacks -> `RetainedViewRuntime` -> `RenderFrame` -> `D3D11Renderer`

The experimental path replaces the final stage with:

`RetainedViewRuntime` -> `GPUIScene` -> `D3D11BatchRenderer`

## Mission Target

The mission does **not** replace the retained runtime or `WinSwiftUI`. Instead it upgrades the render engine around them so the runtime can safely produce a near-full GPUI-style typed scene and eventually present that scene by default.

The target architecture is:

1. **Retained runtime remains the source of UI truth**
   - `ViewNode` mutation, layout resolution, hit testing, focus traversal, and deferred paint routing stay owned by `RetainedViewRuntime`.
   - SwiftUI-shaped compatibility remains in `WinSwiftUI`.

2. **Backend-neutral scene contract becomes the primary render contract**
   - `SwiftWindowsGraphics` owns typed primitive families, draw-order metadata, replay records, and batch iteration.
   - D3D11-specific concerns stay below that layer.

3. **Frame and scene paths coexist until parity is proven**
   - `RenderFrame -> D3D11Renderer` remains the fallback and reference path.
   - `GPUIScene -> D3D11BatchRenderer` graduates from experimental to default only after parity, text, image, and downgrade validation are green.

4. **Prepaint and paint remain distinct**
   - Prepaint owns interaction metadata, ancestor routing, focus targeting, and deferred payload bookkeeping.
   - Paint emits frame commands or scene primitives.

5. **Text ownership moves upward**
   - Logical layout, glyph identity, atlas dirtiness, and replay discipline belong to the runtime/text system layers.
   - The renderer consumes already-decided glyph/image primitives and atlas snapshots.

## Primary Component Boundaries

### WinSwiftUI / Host Layer

- `WinSwiftUIWindowHost` owns:
  - window lifecycle,
  - presenter selection,
  - fallback from batch to frame,
  - refresh/timer policy,
  - observed-object reload coalescing.

### Runtime Layer

- `RetainedViewRuntime` owns:
  - retained tree state,
  - layout and measurement reuse,
  - prepaint interaction metadata,
  - deferred subtree replay bookkeeping,
  - frame/scene cache invalidation boundaries.

### Graphics Contract Layer

- `SwiftWindowsGraphics` owns:
  - typed primitive families,
  - paint/replay records,
  - clip/mask semantics,
  - layer/scoped-layer ordering,
  - batch iteration order.

### Text / Atlas Layer

- `WindowTextSystem`, glyph atlases, and native/pixel text helpers own:
  - logical text layout reuse,
  - glyph identity and atlas mapping,
  - atlas dirty-region discipline,
  - fallback behavior when native text is unavailable.

### Renderer Layer

- `D3D11Renderer` remains the fallback frame presenter.
- `D3D11BatchRenderer` is responsible only for consuming finished scenes:
  - uploading atlas and image resources,
  - drawing ordered family batches,
  - honoring clip and opacity semantics from the scene contract.

## Implementation Map

- **Host / presenter policy**
  - `Sources/WinSwiftUI/App.swift`
  - `Sources/SwiftWindowsPlatform/Win32Host.swift`
- **Retained runtime / replay / prepaint**
  - `Sources/SwiftWindowsUI/Runtime.swift`
  - `Sources/SwiftWindowsUI/ScenePainter.swift`
- **Backend-neutral scene contract**
  - `Sources/SwiftWindowsGraphics/GPUIScene.swift`
  - `Sources/SwiftWindowsGraphics/GPUIPrimitives.swift`
  - `Sources/SwiftWindowsGraphics/GPUISceneBridge.swift`
  - `Sources/SwiftWindowsGraphics/RenderGraph.swift`
- **Text / atlas ownership**
  - `Sources/SwiftWindowsUI/WindowTextSystem.swift`
  - `Sources/SwiftWindowsUI/NativeTextLayout.swift`
  - `Sources/SwiftWindowsUI/NativeGlyphAtlas.swift`
  - `Sources/SwiftWindowsUI/GlyphAtlas.swift`
  - `Sources/SwiftWindowsUI/PixelText.swift`
- **Renderer implementation**
  - `Sources/SwiftWindowsRendererD3D11/D3D11Renderer.swift`
  - `Sources/SwiftWindowsRendererD3D11/D3D11BatchRenderer.swift`
  - `Sources/SwiftWindowsRendererD3D11/BatchShaders.swift`

## Presenter Policy

- Frame presentation remains the default presenter until scene-path parity and downgrade safety are proven.
- Batch presentation remains opt-in until the contract gates for ordering, text, image handling, downgrade behavior, and launch probes are green.
- Presenter downgrade is owned by `WinSwiftUIWindowHost` and must remain same-session. Renderer failures must not strand the window lifecycle.

## Milestone Map

- **Milestone 1 — Scene Contract Foundation**
  - `SwiftWindowsGraphics`, bridge semantics, ordering, replay.
- **Milestone 2 — Frame/Scene Parity Harness**
  - `RetainedViewRuntime`, `ScenePainter`, parity-focused tests.
- **Milestone 3 — Runtime / Host Integration**
  - `WinSwiftUIWindowHost`, `Win32Host`, host-focused test harnesses.
- **Milestone 4 — Text System and Atlas**
  - `WindowTextSystem`, glyph atlases, clip/opacity/fallback behavior.
- **Milestone 5 — Batch Renderer Capability**
  - `D3D11BatchRenderer`, atlas/image resource handling, launch-probe observability.
- **Milestone 6 — Default Promotion and Hardening**
  - presenter-default policy, downgrade correctness, final parity hardening.

## Invariants to Preserve

- `WinSwiftUI` API shape and same-source demo intent stay intact.
- Backend-neutral render semantics must not leak D3D11-specific details into `SwiftWindowsGraphics`.
- Deferred overlay ordering and ancestor-routing metadata must remain correct across frame/scene switching.
- Cached scene replay must never require re-uploading atlas data unless text actually becomes dirty.
- Unsupported scene/bridge features must fail softly and predictably until implemented fully.
- The Zed checkout is reference material only; port mechanics, not Rust-specific API shapes.

## Out of Scope / Do Not Change

- Do not replace `RetainedViewRuntime` with a Rust-shaped entity system.
- Do not replace `WinSwiftUI` with a different public surface.
- Do not add `extern/zed` to the Swift package graph or runtime.
- Do not let D3D11-specific resource or shader concerns leak into `SwiftWindowsGraphics`.
