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

Current important limit: the default `D3D11Renderer` still renders only the established `fillRect` and `drawBitmap` command paths. Newer renderer-neutral commands such as paths, blur, first-class text, and clip-stack commands need backend implementation before they can be considered active visual features on the default renderer.
