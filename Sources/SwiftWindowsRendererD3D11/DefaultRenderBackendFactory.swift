import SwiftWindowsGraphics

@MainActor
public enum DefaultRenderBackendFactory {
    public static func make() -> any RenderBackend {
        D3D11Renderer()
    }

    /// Create a batch-capable renderer, if one is available.
    ///
    /// The active WinSwiftUI host prefers this scene/batch renderer when it is
    /// available. Callers can still pass `nil` to stay on the `RenderFrame`
    /// fallback path explicitly.
    public static func makeBatchBackend() -> (any BatchRenderBackend)? {
        D3D11BatchRenderer()
    }
}
