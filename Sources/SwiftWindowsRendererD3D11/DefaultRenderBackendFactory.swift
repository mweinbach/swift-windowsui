import SwiftWindowsGraphics

@MainActor
public enum DefaultRenderBackendFactory {
    public static func make() -> any RenderBackend {
        D3D11Renderer()
    }
}
