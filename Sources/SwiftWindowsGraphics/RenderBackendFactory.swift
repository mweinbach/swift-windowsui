import Foundation
import SwiftWindowsCore

// MARK: - RenderBackendFactory

/// Abstract factory for creating renderer backends.
///
/// This protocol decouples app bootstrapping from concrete renderer
/// implementations. Different implementations provide different factories:
///
/// - **Windows**: ``D3D11RenderBackendFactory`` (in `SwiftWindowsRendererD3D11`)
///   produces a D3D11 GPU backend.
/// - **Offscreen rendering**: ``CPURenderBackendFactory`` (below) produces a
///   pure software backend that works without a GPU or windowing system.
///
/// Injecting a factory lets the retained runtime and its renderer-neutral scene
/// swap drawing engines without importing a concrete GPU backend. This does not
/// make the current application host portable: window creation, input, text,
/// accessibility, and software window presentation still require their own
/// platform implementations.
@MainActor
public protocol RenderBackendFactory {
    /// Human-readable name for debugging and startup probes.
    var factoryName: String { get }

    /// Renderer-neutral feature, execution, and presentation-target support.
    ///
    /// Unlike ``probeAvailability()``, this describes the implementation's
    /// contract rather than whether the current machine can instantiate it.
    /// Existing factories inherit a conservative, source-compatible default.
    var capabilities: RenderBackendCapabilities { get }

    /// Create a frame-path renderer.
    func makeRenderBackend() -> any RenderBackend

    /// Create a batch/scene-path renderer, if supported.
    /// Returns `nil` when the factory does not support batch rendering.
    func makeBatchRenderBackend() -> (any BatchRenderBackend)?

    /// Opts into the split native host. The returned value constructs its
    /// resources on the native owner; it must not capture an actor backend.
    /// Legacy/custom factories keep their existing actor path by returning nil.
    func makeNativePresentationFactory() -> (any NativePresentationBackendFactory)?

    /// Whether this machine can actually run the factory's backends, asked
    /// *before* a window exists to attach one to.
    ///
    /// Without this, a machine where device creation fails — no hardware
    /// adapter, a driver mid-upgrade, a session that cannot reach the GPU —
    /// only discovers the problem at `attach`, by which point the window is
    /// already on screen with nothing in it. A composition root that asks
    /// first can pick a different factory instead.
    func probeAvailability() -> RenderBackendAvailability
}

/// What a `RenderBackendFactory` reports about the machine it was asked on.
public enum RenderBackendAvailability: Equatable, Sendable {
    /// The factory's backends can be created as intended.
    case available
    /// The backends can be created, but only in a reduced configuration (a
    /// software adapter, a lower feature level). Usable; callers may still
    /// prefer another factory on performance grounds.
    case degraded(reason: String)
    /// No backend of this kind can be created on this machine right now.
    case unavailable(reason: String)

    /// Whether a window attached to this factory's backends can present at
    /// all. `degraded` still can — slowly — and is preferred over a window
    /// that shows nothing.
    public var canPresent: Bool {
        switch self {
        case .available, .degraded:
            return true
        case .unavailable:
            return false
        }
    }

    /// Explanation for the reduced or missing capability, for diagnostics.
    public var reason: String? {
        switch self {
        case .available:
            return nil
        case .degraded(let reason), .unavailable(let reason):
            return reason
        }
    }
}

extension RenderBackendFactory {
    public func makeNativePresentationFactory() -> (any NativePresentationBackendFactory)? { nil }

    /// A legacy factory is known to produce frame renderers, but nothing else
    /// about its scene support, execution model, or presentation targets can
    /// be assumed until the implementation declares those capabilities.
    public var capabilities: RenderBackendCapabilities {
        .conservative
    }

    /// Factories whose backends own no platform device — the CPU reference
    /// path, test fakes — cannot fail this probe.
    public func probeAvailability() -> RenderBackendAvailability {
        .available
    }
}

// MARK: - CPU Reference Factory

/// A factory that produces pure-software renderers.
///
/// This is the portable offscreen reference: it requires no GPU, no HWND, and no
/// platform-specific graphics APIs.  It is suitable for:
///
/// - Headless CI testing
/// - Pixel-perfect reference images for GPU backend validation
/// - Alternate platform hosts that provide their own bitmap presentation
///
/// The factory does not present into a window by itself. A platform host must
/// pair its output with a real presenter instead of treating successful
/// offscreen rasterization as proof that an on-screen window was updated.
@MainActor
public struct CPURenderBackendFactory: RenderBackendFactory {
    public init() {}

    public var factoryName: String { "CPU Reference" }

    public var capabilities: RenderBackendCapabilities { .cpuOffscreen }

    public func makeRenderBackend() -> any RenderBackend {
        CPUBatchRenderer()
    }

    public func makeBatchRenderBackend() -> (any BatchRenderBackend)? {
        CPUBatchRenderer()
    }
}
