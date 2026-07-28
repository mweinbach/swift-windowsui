import Foundation

import SwiftWindowsCore
import SwiftWindowsGraphics

/// Startup-time selection between render backend factories.
///
/// A factory is asked whether this machine can present with it *before* any
/// window exists. Discovering it at `attach` instead leaves the window on
/// screen with nothing in it and no presenter ever attached — the blank-window
/// state `RendererHealthSnapshot.isPresenterUnavailable` reports, which a user
/// cannot distinguish from a hang.
@MainActor
enum RenderBackendFactoryResolution {
    static func presentableFactory(
        _ factory: RenderBackendFactory,
        fallback: RenderBackendFactory = CPURenderBackendFactory(),
        report: (String) -> Void = { print("[WinSwiftUI] \($0)") }
    ) -> RenderBackendFactory {
        switch factory.probeAvailability() {
        case .available:
            return factory
        case .degraded(let reason):
            // Still presents. A slow window is the better answer here, and the
            // reduced capability belongs in the log rather than in a silent
            // switch to a different renderer.
            report("\(factory.factoryName) is degraded: \(reason)")
            return factory
        case .unavailable(let reason):
            report(
                "\(factory.factoryName) is unavailable on this machine: \(reason) "
                    + "Falling back to \(fallback.factoryName)."
            )
            return fallback
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
