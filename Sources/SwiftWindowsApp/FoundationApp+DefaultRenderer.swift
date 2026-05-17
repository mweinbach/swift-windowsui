import SwiftWindowsUI
import SwiftWindowsGraphics
import SwiftWindowsRendererD3D11

@MainActor
public extension FoundationApp {
    /// Create using the default D3D11 GPU renderer.
    convenience init() {
        self.init(factory: D3D11RenderBackendFactory())
    }

    /// Create using an arbitrary render backend factory.
    /// Use ``CPURenderBackendFactory`` for headless or cross-platform runs.
    convenience init(factory: RenderBackendFactory) {
        self.init(renderer: factory.makeRenderBackend())
    }
}
