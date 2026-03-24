import SwiftWindowsGraphics

@MainActor
public enum DefaultRenderBackendFactory {
    public static func make() -> any RenderBackend {
        D3D11Renderer()
    }

    /// Create a batch-capable renderer, if one is available.
    ///
    /// Returns `nil` until a concrete ``BatchRenderBackend`` implementation
    /// (e.g. D3D11BatchRenderer from Unit 7) is merged. This factory method
    /// is the integration point that downstream code can call without knowing
    /// the concrete type.
    public static func makeBatchBackend() -> (any BatchRenderBackend)? {
        // The real D3D11BatchRenderer will be wired in when its PR is merged.
        return nil
    }
}
