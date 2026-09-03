import SwiftWindowsUI

/// Admission belongs to the accessibility caller. Both checks are synchronous
/// and call-scoped; an editor must not retain them in history or its controller.
@MainActor
struct TextInputAccessibilityValueValidation {
    let mayDispatch: @MainActor () -> Bool
    let isRetainedTargetCurrent: @MainActor () -> Bool
}

struct TextInputAccessibilityValueResult: Sendable {
    /// The original binding write was submitted, not necessarily accepted by
    /// an arbitrary setter. Neither result permits a retry or raw-input fallback.
    let didDispatch: Bool
    /// The original getter observed the requested value, followed by valid
    /// retained ownership at completion. This is not an immutable model receipt
    /// across arbitrary application callbacks or the final display refresh.
    let accepted: Bool

    static let refused = Self(didDispatch: false, accepted: false)
    static let interrupted = Self(didDispatch: true, accepted: false)
}

/// An internal capability of built-in editors, separate from raw key/IME input.
/// Choosing this capability never authorizes a fallback to another text effect.
@MainActor
protocol TextInputAccessibilityValueReplacing: RetainedTextInputController {
    /// Immutable built-in editor configuration, independent of authored traits.
    /// This must not run a Binding getter or any application callback.
    var isSecure: Bool { get }

    /// Stored lifetime only, including manual revocation with an unchanged
    /// node slot. This must not run bindings, layout, or application callbacks.
    var hasCurrentAccessibilityValueOwnership: Bool { get }

    func replaceValueForAccessibility(
        _ value: String,
        validation: TextInputAccessibilityValueValidation
    ) -> TextInputAccessibilityValueResult
}

/// Only retained editor identity is represented here, not Binding provenance.
/// This also protects editors with nil/disabled undo registration. No model,
/// application callback, validation closure, or selection is stored in it.
@MainActor
final class TextInputAccessibilityValueOwner {
    private(set) var isValid = true
    private var generation: UInt64 = 0
    private var activeAttempt: UInt64?
    private(set) var hasStagedSelection = false

    func beginAttempt() -> UInt64? {
        guard isValid, generation < .max else {
            invalidate()
            return nil
        }
        generation += 1
        activeAttempt = generation
        hasStagedSelection = false
        return generation
    }

    func isCurrent(_ attempt: UInt64) -> Bool {
        isValid && activeAttempt == attempt
    }

    func stageSelection(for attempt: UInt64) {
        if isCurrent(attempt) { hasStagedSelection = true }
    }

    func endAttempt(_ attempt: UInt64) {
        if isCurrent(attempt) { supersedeAttempt() }
    }

    func supersedeAttempt() {
        activeAttempt = nil
        hasStagedSelection = false
    }

    func invalidate() {
        isValid = false
        supersedeAttempt()
    }
}
