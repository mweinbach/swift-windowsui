import Foundation
import SwiftWindowsGraphics

@MainActor
public enum DefaultRenderBackendFactory {
    public static func make() -> any RenderBackend {
        D3D11Renderer()
    }

    /// Create a batch-capable renderer, if one is available.
    ///
    /// The scene/batch renderer is the promoted default presenter. The host
    /// keeps the frame renderer attached as an explicit debug/fallback path.
    public static func makeBatchBackend() -> (any BatchRenderBackend)? {
        return D3D11BatchRenderer()
    }
}
