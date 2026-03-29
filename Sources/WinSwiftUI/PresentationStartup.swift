import Foundation
import SwiftWindowsCore

enum StartupPresentationMode: Equatable {
    case automatic
    case frameDebug

    static func fromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> StartupPresentationMode {
        environment["SWIFT_WINDOWSUI_FRAME_DEBUG"].isTruthyEnvironmentValue ? .frameDebug : .automatic
    }
}

enum PresentationBackendKind: String, Equatable {
    case frame
    case scene
}

enum PresentationSelectionReason: Equatable {
    case defaultScene
    case frameDebugOverride
    case batchRendererUnavailable
    case batchAttachFailure(String)
    case batchResizeFailure(String)
    case batchRenderFailure(String)

    var probeCode: String {
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
        }
    }

    var detail: String? {
        switch self {
        case .batchAttachFailure(let detail),
             .batchResizeFailure(let detail),
             .batchRenderFailure(let detail):
            return detail
        case .defaultScene,
             .frameDebugOverride,
             .batchRendererUnavailable:
            return nil
        }
    }
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
        guard let path = environment["SWIFT_WINDOWSUI_STARTUP_PROBE_PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else {
            return nil
        }

        return StartupProbeConfiguration(
            path: path,
            shouldExitAfterProbe: environment["SWIFT_WINDOWSUI_STARTUP_PROBE_EXIT"].isTruthyEnvironmentValue
        )
    }
}

private extension Optional where Wrapped == String {
    var isTruthyEnvironmentValue: Bool {
        guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return false
        }

        return value == "1" || value == "true" || value == "yes" || value == "on"
    }
}

private extension String {
    var sanitizedProbeValue: String {
        replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "=", with: ":")
    }
}
