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

The D3D11 fallback path activates per-command blend states for `.normal`, `.additive`, `.multiply`, and `.screen` on `fillRect` and `drawBitmap`. `.overlay` is still mapped to normal blending until the renderer has shader/effect composition for it, and the Direct2D path currently uses normal source-over blending.

For a quick console smoke check, run:

```powershell
swift run swift-windowsui-inspect
```

The inspector builds a small retained tree, reports backend/text capabilities, prints `RenderFrame`, `GPUIScene`, and `ScenePainter` primitive counts, and includes a clip-stack probe without opening a window.

Current important limit: the default `D3D11Renderer` still renders only the established `fillRect` and `drawBitmap` command paths. Newer renderer-neutral commands such as paths, blur, and first-class text need backend implementation before they can be considered active visual features on the default renderer; clip-stack support is currently rectangular/bounds-based rather than full vector masking.
