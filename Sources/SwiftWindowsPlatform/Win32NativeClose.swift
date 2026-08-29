import Foundation
import SwiftWindowsCore

/// A value identifying one actor-approved close. The actor control retains the
/// actual authority, participants and commit lease; none cross to the HWND owner.
package struct Win32NativeCloseReservation: Equatable, Sendable {
    package let windowKey: NativeWindowKey
    package let requestID: NativeWindowRequestID
    package let attemptID: Foundation.UUID
    package let reservationID: Foundation.UUID
    package let expectedHandle: UInt

    init(
        windowKey: NativeWindowKey, requestID: NativeWindowRequestID, attemptID: Foundation.UUID,
        reservationID: Foundation.UUID = Foundation.UUID(), expectedHandle: UInt
    ) {
        self.windowKey = windowKey
        self.requestID = requestID
        self.attemptID = attemptID
        self.reservationID = reservationID
        self.expectedHandle = expectedHandle
    }
}

@MainActor
package enum Win32NativeClosePreparation {
    case reserved(Win32NativeCloseReservation)
    case completed(Win32CloseAttemptOutcome)
}

/// The owner sends this only after the actual DestroyWindow call. Observation
/// of WM_NCDESTROY and unwind of enclosing native dispatch are separate facts:
/// an API success or a nested destruction message alone cannot finish a close.
package struct Win32NativeCloseDestruction: Equatable, Sendable {
    package let nativeResult: Win32CloseNativeResult
    package let didObserveNonClientDestruction: Bool
    package let didUnwindNativeDispatch: Bool

    package init(
        nativeResult: Win32CloseNativeResult,
        didObserveNonClientDestruction: Bool,
        didUnwindNativeDispatch: Bool
    ) {
        self.nativeResult = nativeResult
        self.didObserveNonClientDestruction = didObserveNonClientDestruction
        self.didUnwindNativeDispatch = didUnwindNativeDispatch
    }
}
