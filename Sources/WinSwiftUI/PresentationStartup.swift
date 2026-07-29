import Foundation

import SwiftWindowsCore
import SwiftWindowsGraphics

/// What the composition root learned about this machine's graphics stack when
/// it resolved the app's `RenderBackendFactory`.
///
/// Carried into `RendererHealthSnapshot` so "this session was substituted onto
/// the software presenter" and "this window is running on WARP" are
/// distinguishable from a healthy hardware session. Without it the probe's
/// answer only ever reached a log line.
public struct RenderBackendResolution: Equatable, Sendable {
    /// Name of the factory the app asked for.
    public var requestedFactoryName: String
    /// Name of the factory whose backends are actually attached.
    public var resolvedFactoryName: String
    /// What the requested factory reported about this machine.
    public var availability: RenderBackendAvailability

    public init(
        requestedFactoryName: String,
        resolvedFactoryName: String,
        availability: RenderBackendAvailability
    ) {
        self.requestedFactoryName = requestedFactoryName
        self.resolvedFactoryName = resolvedFactoryName
        self.availability = availability
    }

    /// The composition root swapped the app's factory for a different one.
    public var isSubstituted: Bool {
        requestedFactoryName != resolvedFactoryName
    }

    /// Presentation is not running at full capability: either the requested
    /// factory was substituted, or it reported `.degraded` — which for the
    /// D3D11 factory is precisely "no usable hardware adapter; this window
    /// presents through the WARP software rasterizer".
    public var isDegradedPresentation: Bool {
        if isSubstituted {
            return true
        }
        if case .degraded = availability {
            return true
        }
        return false
    }
}

/// Startup-time selection between render backend factories.
///
/// A factory is asked whether this machine can present with it *before* any
/// window exists. Discovering it at `attach` instead leaves the window on
/// screen with nothing in it and no presenter ever attached — the blank-window
/// state `RendererHealthSnapshot.isPresenterUnavailable` reports, which a user
/// cannot distinguish from a hang.
///
/// The substitute must be a factory whose backends actually present to an
/// HWND. `CPURenderBackendFactory` is not one: its backends rasterize into
/// `lastRenderedBitmap` and stop, so substituting it turned "no GPU" into a
/// blank window that reported itself healthy — strictly worse than the
/// observable `.presenterUnavailable` terminal state. The default fallback is
/// `SoftwareWindowRenderBackendFactory`, which blits what it rasterizes; a
/// fallback that reports it cannot present here is not substituted at all, so
/// the bounded attach retry can reach its terminal state instead.
@MainActor
enum RenderBackendFactoryResolution {
    /// Picks the factory to build backends from and records why, for health.
    static func resolve(
        _ factory: RenderBackendFactory,
        fallback: RenderBackendFactory = SoftwareWindowRenderBackendFactory(),
        report: (String) -> Void = { print("[WinSwiftUI] \($0)") }
    ) -> (factory: RenderBackendFactory, resolution: RenderBackendResolution) {
        let availability = factory.probeAvailability()

        func resolved(_ chosen: RenderBackendFactory) -> (RenderBackendFactory, RenderBackendResolution) {
            (
                chosen,
                RenderBackendResolution(
                    requestedFactoryName: factory.factoryName,
                    resolvedFactoryName: chosen.factoryName,
                    availability: availability
                )
            )
        }

        switch availability {
        case .available:
            return resolved(factory)
        case .degraded(let reason):
            // Still presents. A slow window is the better answer here, and the
            // reduced capability belongs in the log and in the health snapshot
            // rather than in a silent switch to a different renderer.
            report("\(factory.factoryName) is degraded: \(reason)")
            return resolved(factory)
        case .unavailable(let reason):
            guard fallback.probeAvailability().canPresent else {
                report(
                    "\(factory.factoryName) is unavailable on this machine: \(reason) "
                        + "\(fallback.factoryName) cannot present here either; the window will report "
                        + "RendererHealthSnapshot.isPresenterUnavailable rather than show nothing silently."
                )
                return resolved(factory)
            }

            report(
                "\(factory.factoryName) is unavailable on this machine: \(reason) "
                    + "Falling back to \(fallback.factoryName)."
            )
            return resolved(fallback)
        }
    }
}

enum StartupPresentationMode: Equatable {
    case automatic
    case frameDebug

    static func fromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> StartupPresentationMode {
        environment["SWIFT_WINDOWSUI_FRAME_DEBUG"].isTruthyEnvironmentValue ? .frameDebug : .automatic
    }
}
public enum PresentationBackendKind: String, Equatable, Sendable {
    case frame
    case scene
}
public enum PresentationSelectionReason: Equatable, Sendable {
    case defaultScene
    case frameDebugOverride
    case batchRendererUnavailable
    case batchAttachFailure(String)
    case batchResizeFailure(String)
    case batchRenderFailure(String)
    case batchBackendRecovered
    /// Neither backend could be attached within the bounded retry budget: the
    /// window has no presenter at all and has stopped requesting frames.
    case presenterUnavailable(String)

    public var probeCode: String {
        switch self {
        case .defaultScene:
            return "default-scene"
        case .frameDebugOverride:
            return "frame-debug-override"
        case .batchRendererUnavailable:
            return "batch-renderer-unavailable"
        case .batchAttachFailure:
            return "batch-attach-failure"
        case .batchResizeFailure:
            return "batch-resize-failure"
        case .batchRenderFailure:
            return "batch-render-failure"
        case .batchBackendRecovered:
            return "batch-backend-recovered"
        case .presenterUnavailable:
            return "presenter-unavailable"
        }
    }

    public var detail: String? {
        switch self {
        case .batchAttachFailure(let detail),
            .batchResizeFailure(let detail),
            .batchRenderFailure(let detail),
            .presenterUnavailable(let detail):
            return detail
        case .defaultScene,
            .frameDebugOverride,
            .batchRendererUnavailable,
            .batchBackendRecovered:
            return nil
        }
    }
}

/// Policy that controls whether the host attempts to re-attach the batch
/// backend after a downgrade. The framework now defaults to `.standard`
/// (recovery enabled, 5s → 60s backoff) so transient driver glitches don't
/// permanently strand apps on the slower frame backend. Tests and callers
/// that need the historical one-way pin can pass `.disabled` explicitly.
public struct BatchBackendRecoveryPolicy: Equatable, Sendable {
    public var isEnabled: Bool
    public var initialRetryInterval: Double
    public var maxRetryInterval: Double
    public var backoffMultiplier: Double

    public init(
        isEnabled: Bool = false,
        initialRetryInterval: Double = 5.0,
        maxRetryInterval: Double = 60.0,
        backoffMultiplier: Double = 2.0
    ) {
        self.isEnabled = isEnabled
        self.initialRetryInterval = max(0.1, initialRetryInterval)
        self.maxRetryInterval = max(initialRetryInterval, maxRetryInterval)
        self.backoffMultiplier = max(1.0, backoffMultiplier)
    }

    /// Default: one-way fallback (no recovery attempts).
    public static let disabled = BatchBackendRecoveryPolicy(isEnabled: false)

    /// Aggressive: try every 5s, doubling up to 60s.
    public static let standard = BatchBackendRecoveryPolicy(
        isEnabled: true, initialRetryInterval: 5, maxRetryInterval: 60, backoffMultiplier: 2)
}
struct PresentationSelection: Equatable {
    var presenter: PresentationBackendKind
    var reason: PresentationSelectionReason
    var frameBackend: String
    var sceneBackend: String?

    func startupProbePayload(logicalRootSize: IntSize, displayScale: Double) -> String {
        var lines = [
            "presenter=\(presenter.rawValue)",
            "reason=\(reason.probeCode)",
            "frame_backend=\(frameBackend)",
            "logical_root_size=\(logicalRootSize.width)x\(logicalRootSize.height)",
            String(format: "display_scale=%.3f", displayScale),
        ]

        if let sceneBackend {
            lines.append("scene_backend=\(sceneBackend)")
        }

        if let detail = reason.detail?.sanitizedProbeValue {
            lines.append("detail=\(detail)")
        }

        return lines.joined(separator: "\n") + "\n"
    }
}
struct StartupProbeConfiguration: Equatable {
    var path: String
    var shouldExitAfterProbe: Bool

    static func fromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> StartupProbeConfiguration? {
        guard
            let path = environment["SWIFT_WINDOWSUI_STARTUP_PROBE_PATH"]?.trimmingCharacters(
                in: .whitespacesAndNewlines),
            !path.isEmpty
        else {
            return nil
        }

        return StartupProbeConfiguration(
            path: path,
            shouldExitAfterProbe: environment["SWIFT_WINDOWSUI_STARTUP_PROBE_EXIT"].isTruthyEnvironmentValue
        )
    }
}
extension Optional where Wrapped == String {
    fileprivate var isTruthyEnvironmentValue: Bool {
        guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return false
        }

        return value == "1" || value == "true" || value == "yes" || value == "on"
    }
}
extension String {
    fileprivate var sanitizedProbeValue: String {
        replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "=", with: ":")
    }
}
