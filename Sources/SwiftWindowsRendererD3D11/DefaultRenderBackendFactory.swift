import Foundation

// MARK: - D3D11 Render Backend Factory

/// Factory that produces D3D11 GPU renderers.  This is the default Windows
/// factory used by the demo app and by ``WinSwiftUI.App`` when no other
/// factory is injected.
import SwiftWindowsGraphics

// MARK: - Legacy Default Factory (deprecated, use D3D11RenderBackendFactory)

@MainActor
public struct D3D11RenderBackendFactory: RenderBackendFactory {
    public init() {}

    public var factoryName: String { "D3D11 GPU" }

    public func makeRenderBackend() -> any RenderBackend {
        D3D11Renderer()
    }

    /// Create a batch-capable renderer, if one is available.
    ///
    /// The scene/batch renderer is the promoted default presenter. The host
    /// keeps the frame renderer attached as an explicit debug/fallback path.
    public func makeBatchRenderBackend() -> (any BatchRenderBackend)? {
        D3D11BatchRenderer()
    }
}
@MainActor
public enum DefaultRenderBackendFactory {
    public static func make() -> any RenderBackend {
        D3D11Renderer()
    }

    public static func makeBatchBackend() -> (any BatchRenderBackend)? {
        D3D11BatchRenderer()
    }
}
