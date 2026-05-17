import SwiftWindowsGraphics

import SwiftWindowsRendererD3D11

import SwiftWindowsUI

@MainActor
extension FoundationApp {
    /// Create using the default D3D11 GPU renderer.
    public convenience init() {
        self.init(factory: D3D11RenderBackendFactory())
    }

    /// Create using an arbitrary render backend factory.
    /// Use ``CPURenderBackendFactory`` for headless or cross-platform runs.
    public convenience init(factory: RenderBackendFactory) {
        self.init(renderer: factory.makeRenderBackend())
    }
}
