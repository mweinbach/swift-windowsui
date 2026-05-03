import Foundation
import SwiftWindowsGraphics

@MainActor
public enum DefaultRenderBackendFactory {
    public enum RendererPreference: Equatable, Sendable {
        case automatic
        case defaultD3D11
        case batchD3D11

        public init(environmentValue: String?) {
            switch environmentValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "batch", "batch-d3d11", "d3d11-batch":
                self = .batchD3D11
            case "default", "d3d11", "frame", "frame-d3d11":
                self = .defaultD3D11
            default:
                self = .automatic
            }
        }
    }

    public static func make() -> any RenderBackend {
        make(preference: RendererPreference(
            environmentValue: ProcessInfo.processInfo.environment["SWIFT_WINDOWSUI_RENDERER"]
        ))
    }

    public static func make(preference: RendererPreference) -> any RenderBackend {
        switch preference {
        case .automatic, .defaultD3D11:
            D3D11Renderer()
        case .batchD3D11:
            D3D11BatchRenderer()
        }
    }

    public static func makeDefaultBackend() -> any RenderBackend {
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
