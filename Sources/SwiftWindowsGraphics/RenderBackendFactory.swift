import Foundation
import SwiftWindowsCore

// MARK: - RenderBackendFactory

/// Abstract factory for creating renderer backends.
///
/// This protocol decouples app bootstrapping from concrete renderer
/// implementations.  Different platforms provide different factories:
///
/// - **Windows**: ``D3D11RenderBackendFactory`` (in `SwiftWindowsRendererD3D11`)
///   produces a D3D11 GPU backend.
/// - **Any platform**: ``CPURenderBackendFactory`` (below) produces a pure
///   software backend that works without a GPU or windowing system.
///
/// By injecting a factory at app launch, the same ``WinSwiftUI.App`` and
/// ``SwiftWindowsApp`` code can run on Windows (GPU), Linux (software), or
/// macOS (future Metal factory) without modification.
@MainActor
public protocol RenderBackendFactory {
    /// Human-readable name for debugging and startup probes.
    var factoryName: String { get }

    /// Create a frame-path renderer.
    func makeRenderBackend() -> any RenderBackend

    /// Create a batch/scene-path renderer, if supported.
    /// Returns `nil` when the factory does not support batch rendering.
    func makeBatchRenderBackend() -> (any BatchRenderBackend)?
}

// MARK: - CPU Reference Factory

/// A factory that produces pure-software renderers.
///
/// This is the portable fallback: it requires no GPU, no HWND, and no
/// platform-specific graphics APIs.  It is suitable for:
///
/// - Headless CI testing
/// - Platforms without D3D11/Metal/Vulkan
/// - Pixel-perfect reference images for GPU backend validation
@MainActor
public struct CPURenderBackendFactory: RenderBackendFactory {
    public init() {}

    public var factoryName: String { "CPU Reference" }

    public func makeRenderBackend() -> any RenderBackend {
        CPUBatchRenderer()
    }

    public func makeBatchRenderBackend() -> (any BatchRenderBackend)? {
        CPUBatchRenderer()
    }
}
