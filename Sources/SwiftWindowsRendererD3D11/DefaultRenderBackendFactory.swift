import SwiftWindowsGraphics

@MainActor
public enum DefaultRenderBackendFactory {
    public static func make() -> any RenderBackend {
        D3D11Renderer()
    }

    /// Create a batch-capable renderer, if one is available.
    ///
    /// This factory method is the integration point that downstream code can
    /// call without knowing the concrete batch renderer type.
    public static func makeBatchBackend() -> (any BatchRenderBackend)? {
        D3D11BatchRenderer()
    }
}
