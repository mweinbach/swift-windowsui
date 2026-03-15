import SwiftWindowsUI
import SwiftWindowsRendererD3D11

@MainActor
public extension FoundationApp {
    convenience init() {
        self.init(renderer: DefaultRenderBackendFactory.make())
    }
}
