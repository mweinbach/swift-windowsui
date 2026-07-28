import Foundation

import SwiftWindowsCore
import SwiftWindowsGraphics

/// Read-only snapshot of the rendering pipeline's current state. Apps that
/// want to log or surface pipeline health (e.g. "we downgraded to the frame
/// backend due to driver glitch X" or "the batch backend is back online")
/// can fetch this without reaching into runtime/renderer internals.
///
/// Updated lazily by `WinSwiftUIWindowHost.rendererHealthSnapshot`; cheap
/// to query (no allocations, no IO).
public struct RendererHealthSnapshot: Equatable, Sendable {
    /// Which backend is presenting frames right now.
    public var activeBackend: PresentationBackendKind
    /// Display scale (logical → device pixels) the runtime is currently
    /// configured for.
    public var displayScale: Double
    /// Minimum render interval enforced by the runtime (frame pacing) in
    /// seconds, or `nil` if unconstrained.
    public var minimumFrameInterval: Double?
    /// `true` when the host has at least one in-flight animation (color
    /// transitions, scroll momentum, rubber-band, keyboard-scroll tween).
    public var hasActiveAnimations: Bool
    /// Whether two-way fallback recovery is enabled for this host.
    public var recoveryPolicyEnabled: Bool
    /// Seconds until the next scheduled batch-backend recovery attempt, or
    /// `nil` when no attempt is scheduled (recovery disabled, or batch is
    /// the active backend).
    public var nextBatchRecoveryInSeconds: Double?
    /// Reason recorded for the most recent backend selection — useful for
    /// distinguishing "default scene" from "downgraded due to error" from
    /// "recovered after failure".
    public var lastBackendSelectionReason: PresentationSelectionReason?
    /// Name string from the active backend (e.g. "D3D11 BATCH",
    /// "FAKE FRAME"). Same as what the user sees in diagnostics overlays.
    public var activeBackendDisplayName: String?
    /// Paint metrics from the most recent scene render. Use
    /// `.gpuPromotionRate` to observe what fraction of paths take the
    /// tessellator's GPU fast lane vs falling through to CPU
    /// rasterization.
    public var lastScenePaintMetrics: ScenePaintMetrics
    /// How the backend classified the failure behind the most recent
    /// downgrade — device loss, a transient glitch, this particular scene,
    /// or a capability this machine does not have. `nil` when no backend has
    /// failed this session. This is the field that distinguishes "the GPU
    /// went away" from "one image will not upload", which the selection
    /// reason's free-text detail cannot.
    public var lastPresentationFailureKind: PresentationFailureKind?
    /// The active backend's last present found the window fully occluded, so
    /// further frames are invisible work.
    public var isPresentationOccluded: Bool

    public init(
        activeBackend: PresentationBackendKind,
        displayScale: Double,
        minimumFrameInterval: Double?,
        hasActiveAnimations: Bool,
        recoveryPolicyEnabled: Bool,
        nextBatchRecoveryInSeconds: Double?,
        lastBackendSelectionReason: PresentationSelectionReason?,
        activeBackendDisplayName: String?,
        lastScenePaintMetrics: ScenePaintMetrics = ScenePaintMetrics(),
        lastPresentationFailureKind: PresentationFailureKind? = nil,
        isPresentationOccluded: Bool = false
    ) {
        self.activeBackend = activeBackend
        self.displayScale = displayScale
        self.minimumFrameInterval = minimumFrameInterval
        self.hasActiveAnimations = hasActiveAnimations
        self.recoveryPolicyEnabled = recoveryPolicyEnabled
        self.nextBatchRecoveryInSeconds = nextBatchRecoveryInSeconds
        self.lastBackendSelectionReason = lastBackendSelectionReason
        self.activeBackendDisplayName = activeBackendDisplayName
        self.lastScenePaintMetrics = lastScenePaintMetrics
        self.lastPresentationFailureKind = lastPresentationFailureKind
        self.isPresentationOccluded = isPresentationOccluded
    }
}
