import Foundation
import SwiftWindowsGraphics

@MainActor
public enum DefaultRenderBackendFactory {
    public static func make() -> any RenderBackend {
        D3D11Renderer()
    }

    /// Create a batch-capable renderer, if one is available.
    ///
    /// The scene/batch renderer remains opt-in until paint ordering and
    /// shaped native text are ported all the way over. Set
    /// `SWIFT_WINDOWSUI_EXPERIMENTAL_BATCH=1` to force the demo onto the
    /// experimental scene path.
    public static func makeBatchBackend() -> (any BatchRenderBackend)? {
        guard ProcessInfo.processInfo.environment["SWIFT_WINDOWSUI_EXPERIMENTAL_BATCH"] == "1" else {
            return nil
        }

        return D3D11BatchRenderer()
    }
}
