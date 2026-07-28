import Foundation

import SwiftWindowsGraphics

import WinSDK
import WinSDK.DirectX

// MARK: - Present Outcome

/// What a `Present` HRESULT actually means, as opposed to "negative, so
/// throw".
///
/// The two swap-chain owners in this module used to disagree: the frame
/// renderer recognised two device-lost HRESULTs, logged them and returned
/// *success*; the batch renderer classified nothing and threw on any negative
/// value. Neither noticed `DXGI_STATUS_OCCLUDED`, which is positive and so
/// read as a clean present even though flip-model `Present` returns from it
/// immediately instead of blocking on vsync.
public enum PresentOutcome: String, Equatable, Sendable {
    /// The frame reached the screen.
    case presented
    /// The window is fully occluded. Not an error, but not vsync-paced
    /// either: every frame drawn in this state is invisible work.
    case occluded
    /// The device was removed, reset or hung. Recoverable by rebuilding the
    /// device — never by switching backends, since the next backend would
    /// create its device on the same dead adapter.
    case deviceLost
    /// A real failure that is not device loss.
    case failed
}

// MARK: - Device Lost Policy

/// Pure HRESULT classification plus the recovery schedule both D3D11
/// renderers follow.
///
/// Deliberately free of renderer state so it is unit-testable without a GPU:
/// every decision the recovery path makes is a function from an HRESULT and
/// an attempt number to a value here.
///
/// The recovery *shape* mirrors GPUI's (`extern/zed/crates/gpui_windows`):
/// unbind the render targets, `ClearState`, `Flush`, release every device
/// object, wait briefly ("if we don't wait, the final drawing result will be
/// blank"), recreate with a bounded number of attempts, then skip one frame.
public enum DeviceLostPolicy {

    // MARK: HRESULTs
    //
    // Spelled out here rather than imported: the Swift WinSDK overlay does
    // not surface the DXGI error constants, and both renderers previously
    // kept their own private copies of the two they happened to know about.

    /// `DXGI_ERROR_DEVICE_REMOVED` — adapter removed, TDR, driver update.
    public static let deviceRemoved: HRESULT = HRESULT(bitPattern: 0x887A_0005)
    /// `DXGI_ERROR_DEVICE_HUNG` — the app's own command list wedged the GPU.
    public static let deviceHung: HRESULT = HRESULT(bitPattern: 0x887A_0006)
    /// `DXGI_ERROR_DEVICE_RESET` — the device failed for a non-app reason.
    public static let deviceReset: HRESULT = HRESULT(bitPattern: 0x887A_0007)
    /// `DXGI_ERROR_DRIVER_INTERNAL_ERROR` — driver bug; the device is gone.
    public static let driverInternalError: HRESULT = HRESULT(bitPattern: 0x887A_0020)
    /// `DXGI_STATUS_OCCLUDED` — a *success* code (positive) that means the
    /// window is not visible.
    public static let statusOccluded: HRESULT = HRESULT(bitPattern: 0x087A_0001)
    /// `DXGI_ERROR_WAS_STILL_DRAWING` — the GPU is busy; retry later.
    public static let wasStillDrawing: HRESULT = HRESULT(bitPattern: 0x887A_000A)
    /// `E_OUTOFMEMORY`.
    public static let outOfMemory: HRESULT = HRESULT(bitPattern: 0x8007_000E)
    /// `DXGI_ERROR_UNSUPPORTED` — this machine cannot do it.
    public static let unsupported: HRESULT = HRESULT(bitPattern: 0x887A_0004)
    /// `DXGI_ERROR_NOT_CURRENTLY_AVAILABLE`.
    public static let notCurrentlyAvailable: HRESULT = HRESULT(bitPattern: 0x887A_0022)
    /// `E_NOINTERFACE`.
    public static let noInterface: HRESULT = HRESULT(bitPattern: 0x8000_4002)
    /// `E_NOTIMPL`.
    public static let notImplemented: HRESULT = HRESULT(bitPattern: 0x8000_4001)

    // MARK: Recovery schedule

    /// How many consecutive device rebuilds to attempt before giving up and
    /// letting the failure reach the host as `.deviceLost`. The counter is
    /// cleared by any present that reaches the screen, so this bounds a
    /// *storm*, not a session.
    public static let maxRecoveryAttempts = 3

    /// True when this HRESULT means "your device is gone", from any D3D11 or
    /// DXGI call — not just `Present`.
    public static func isDeviceLost(_ hresult: HRESULT) -> Bool {
        hresult == deviceRemoved
            || hresult == deviceReset
            || hresult == deviceHung
            || hresult == driverInternalError
    }

    /// Classifies a `Present` (or `PresentTest`) HRESULT.
    public static func outcome(forPresent hresult: HRESULT) -> PresentOutcome {
        if hresult == statusOccluded {
            return .occluded
        }
        if isDeviceLost(hresult) {
            return .deviceLost
        }
        return hresult >= 0 ? .presented : .failed
    }

    /// The recovery classification the host's policy switches on, for any
    /// HRESULT a backend is about to throw.
    ///
    /// Failures that depend on *what is being drawn* rather than on the
    /// HRESULT — an image that will not upload, a missing glyph atlas —
    /// cannot be recognised here; those sites pass
    /// ``PresentationFailureKind/sceneContent`` explicitly.
    public static func failureKind(for hresult: HRESULT) -> PresentationFailureKind {
        if isDeviceLost(hresult) {
            return .deviceLost
        }
        switch hresult {
        case unsupported, notCurrentlyAvailable, noInterface, notImplemented:
            return .permanent
        default:
            return .transient
        }
    }

    /// How long to wait before rebuilding the device on `attempt` (1-based).
    ///
    /// GPUI sleeps ~350 ms before recreating and escalates across retries;
    /// the wait is what keeps the first frame after recovery from coming
    /// back blank. Capped so a wedged adapter cannot stall the UI thread for
    /// more than a beat per attempt.
    public static func backoffSeconds(forAttempt attempt: Int) -> Double {
        let step = 0.35
        let clampedAttempt = max(1, attempt)
        return min(step * Double(clampedAttempt), 1.5)
    }

    // MARK: Diagnostics

    /// `GetDeviceRemovedReason` for logging. Returns `S_OK` when there is no
    /// device to ask, which reads as "no reason recorded".
    public static func removedReason(of device: UnsafeMutablePointer<ID3D11Device>?) -> HRESULT {
        guard let device else {
            return 0
        }
        return device.pointee.lpVtbl.pointee.GetDeviceRemovedReason(device)
    }

    /// Uppercase hex rendering of an HRESULT for log lines.
    public static func describe(_ hresult: HRESULT) -> String {
        "0x" + String(UInt32(bitPattern: hresult), radix: 16, uppercase: true)
    }
}
