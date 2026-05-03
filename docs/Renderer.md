# Renderer Notes

`swift-windowsui` currently has two renderer-facing frame shapes:

- `RenderFrame` is the active default path. `RetainedViewRuntime.renderFrame()` emits ordered `RenderCommand` values, and `DefaultRenderBackendFactory.make()` returns `D3D11Renderer`.
- `GPUIScene` is the batch-oriented path. It groups primitives into typed layer arrays for instanced rendering, and `DefaultRenderBackendFactory.makeBatchBackend()` returns `D3D11BatchRenderer` for tools or callers that want to exercise that path explicitly.

The batch scene types expose lightweight inspection helpers:

- `GPUILayer.primitiveCount`
- `GPUILayer.isEmpty`
- `GPUIScene.primitiveCount`
- `GPUIScene.totalPrimitiveCount`
- `QuadPrimitive.clipRect`

Use these helpers in tests and diagnostics when checking primitive emission, layer splitting, clipping, and batch renderer readiness.

`RenderClipStack` is the shared clip resolver for renderers that currently expose rectangular scissor-style clipping. `pushClip` and `popClip` are honored by the `RenderFrame -> GPUIScene` bridge and by the default `D3D11Renderer`/Direct2D frame path for rect clips, ellipse bounds, and path bounds. Rounded, elliptical, and arbitrary path clips are approximated to rectangular bounds until the backend grows a true mask/stencil clip path.

Retained-node opacity is resolved in `RetainedViewRuntime.renderFrame()` before commands reach a backend. Fill colors, gradient stops, path/text colors, bitmap opacity, and scroll-indicator fills inherit parent opacity in the renderer-neutral command stream; zero-opacity nodes still lay out but skip command emission.

Retained controls can emit local vector paths through `Controls.path`, which lowers to `fillPath` and optional `strokePath` commands translated into the node's resolved frame. When a path node is inside clipped retained content, the runtime wraps those path commands in `pushClip`/`popClip` so Direct2D-backed rendering and diagnostics see the same bounds-aware frame contract.

The D3D11 fallback path activates per-command blend states for `.normal`, `.additive`, `.multiply`, and `.screen` on `fillRect` and `drawBitmap`. `.overlay` is still mapped to normal blending until the renderer has shader/effect composition for it, and the Direct2D path currently uses normal source-over blending.

When Direct2D interop is active, the default renderer also translates `fillPath` and `strokePath` commands into native Direct2D path geometries with per-primitive antialiasing. Path fills currently use a solid color; path gradients fall back to the first gradient stop. Stroke width, dash pattern, cap, and join are forwarded to Direct2D. The pure D3D11 shader fallback still skips path commands.

When Direct2D interop is active, `drawText` commands are rendered through DirectWrite directly into the Direct2D target with grayscale text antialiasing. The retained UI still normally emits text as bitmap commands through `NativeTextRenderer`; `drawText` is available for renderer-neutral callers and future GPU text work. The pure D3D11 shader fallback still skips `drawText`.

When Direct2D interop is active, `applyBlur` snapshots the requested target region into a temporary bitmap, applies the native Direct2D Gaussian blur effect, and draws the blurred image back over that region. The pure D3D11 shader fallback still skips `applyBlur`.

For a quick console smoke check, run:

```powershell
swift run swift-windowsui-inspect
swift run swift-windowsui-inspect -- --verify
swift run swift-windowsui-inspect -- --json --verify
```

The inspector builds small retained and `WinSwiftUI` declarative trees, reports backend/text capabilities, prints `RenderFrame`, `GPUIScene`, and `ScenePainter` primitive counts, and includes path, text, blur, retained-control, `WinSwiftUI`, text-input, scroll-stress, and clip-stack probes without opening a window.
Use `--verify` to turn those probes into a smoke gate; it exits nonzero if command emission, retained-control focusability, `WinSwiftUI` tree generation, text input, scroll culling, or clip resolution regresses. Add `--json` to emit the same diagnostics as structured JSON for scripts or CI dashboards.

Current important limit: the default `D3D11Renderer` still renders only the established `fillRect` and `drawBitmap` command paths on the pure shader fallback, while Direct2D interop additionally covers `fillPath`, `strokePath`, `drawText`, and `applyBlur`. Clip-stack support is currently rectangular/bounds-based rather than full vector masking.
