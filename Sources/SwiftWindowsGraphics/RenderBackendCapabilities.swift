import SwiftWindowsCore

/// Surface kinds a renderer can genuinely render or present to.
///
/// A CPU reference renderer can produce an offscreen bitmap but cannot put
/// pixels into a native window. A window presenter has the opposite contract
/// unless it also exposes a real offscreen attachment path. Keeping these
/// claims separate prevents a successfully created renderer from being
/// mistaken for a presenter.
public struct RenderBackendPresentationTargets: OptionSet, Hashable, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    /// The renderer can present pixels to a native window surface.
    public static let window = Self(rawValue: 1 << 0)

    /// The renderer can attach to a handle-free surface and produce pixels.
    public static let offscreen = Self(rawValue: 1 << 1)
}

/// How a renderer performs its drawing, independent of the host platform.
public enum RenderBackendExecutionModel: String, Equatable, Sendable {
    /// A legacy or third-party factory has not described its implementation.
    case unspecified

    /// The renderer executes its rasterization directly on the CPU.
    case software

    /// The renderer submits its work through a graphics-device API.
    ///
    /// This does not promise hardware acceleration: a graphics device may be
    /// backed by a software adapter such as WARP. Inspect the factory's
    /// availability and the active backend's adapter diagnostics to determine
    /// whether the selected device actually runs on dedicated hardware.
    case graphicsDevice
}

/// A renderer factory's portable feature and presentation contract.
///
/// These are implementation capabilities, not availability guarantees. A
/// factory may support window presentation but report itself unavailable when
/// no compatible graphics device can be created. Similarly, a graphics-device
/// execution model does not distinguish a physical GPU from a software adapter.
public struct RenderBackendCapabilities: Equatable, Sendable {
    /// Whether the factory can consume a renderer-neutral `RenderFrame`.
    public var supportsFrameRendering: Bool

    /// Whether the factory can consume the retained runtime's `GPUIScene`.
    public var supportsSceneRendering: Bool

    /// The surface kinds the factory's renderers can actually fulfill.
    public var supportedPresentationTargets: RenderBackendPresentationTargets

    /// Whether an active scene backend can capture frames it genuinely presents.
    public var supportsPresentedFrameCapture: Bool

    /// Whether an active scene backend can control display-synchronized presents.
    public var supportsVSyncControl: Bool

    /// Whether drawing runs directly on the CPU or through a graphics device.
    public var executionModel: RenderBackendExecutionModel

    public init(
        supportsFrameRendering: Bool = true,
        supportsSceneRendering: Bool = false,
        supportedPresentationTargets: RenderBackendPresentationTargets = [],
        supportsPresentedFrameCapture: Bool = false,
        supportsVSyncControl: Bool = false,
        executionModel: RenderBackendExecutionModel = .unspecified
    ) {
        self.supportsFrameRendering = supportsFrameRendering
        self.supportsSceneRendering = supportsSceneRendering
        self.supportedPresentationTargets = supportedPresentationTargets
        self.supportsPresentedFrameCapture = supportsPresentedFrameCapture
        self.supportsVSyncControl = supportsVSyncControl
        self.executionModel = executionModel
    }

    /// Existing factories remain source-compatible without claiming features
    /// or presentation targets their implementations have not verified.
    public static let conservative = Self()

    /// The portable CPU reference backend produces bitmaps without a window.
    public static let cpuOffscreen = Self(
        supportsSceneRendering: true,
        supportedPresentationTargets: [.offscreen],
        executionModel: .software
    )

    /// A CPU renderer paired with a native window bitmap presenter.
    public static let softwareWindow = Self(
        supportsSceneRendering: true,
        supportedPresentationTargets: [.window],
        executionModel: .software
    )

    /// A graphics-device renderer attached to a native presentation surface.
    /// The selected adapter can still be software; see `executionModel`.
    public static let graphicsDeviceWindow = Self(
        supportsSceneRendering: true,
        supportedPresentationTargets: [.window],
        supportsPresentedFrameCapture: true,
        supportsVSyncControl: true,
        executionModel: .graphicsDevice
    )

    /// Whether the renderer can genuinely present into a native window.
    public var supportsWindowPresentation: Bool {
        supportedPresentationTargets.contains(.window)
    }

    /// Whether the renderer can attach and rasterize without a native handle.
    public var supportsOffscreenRendering: Bool {
        supportedPresentationTargets.contains(.offscreen)
    }

    /// Whether the implementation can fulfill an actual surface descriptor's
    /// destination without manufacturing a native window handle.
    public func supports(_ target: RenderSurfaceTarget) -> Bool {
        switch target {
        case .window:
            return supportsWindowPresentation
        case .offscreen:
            return supportsOffscreenRendering
        }
    }
}
