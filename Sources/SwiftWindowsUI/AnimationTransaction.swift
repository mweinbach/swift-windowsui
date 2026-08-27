import SwiftWindowsCore

/// Global animation transaction used by `withAnimation` to propagate
/// animation context to the next property-change reconciliation cycle.
/// Holds the duration and easing to apply when a property changes and no
/// per-property animation state (from `.animation()`) is already present.
@MainActor
public var currentAnimationTransaction: (duration: Double, easing: AnimationEasing)?

/// A duration/easing pair a node carries for its own property changes,
/// independent of any ambient `withAnimation`. See
/// `ViewNode.implicitReconcileAnimation`.
public struct AnimationTransaction: Sendable, Equatable {
    public var duration: Double
    public var easing: AnimationEasing

    public init(duration: Double, easing: AnimationEasing) {
        self.duration = duration
        self.easing = easing
    }
}

/// A view's animation or transaction modifier, evaluated against the
/// transaction inherited by a reconciliation. Configuration is separate from
/// `AnimationState`: installing a modifier does not start an animation.
@MainActor
public struct RetainedAnimationModifier {
    private let trigger: Any?
    private let matchesTrigger: ((Any) -> Bool)?
    private let transform: (inout Transaction) -> Void

    public init(animation: Animation?) {
        trigger = nil
        matchesTrigger = nil
        transform = { transaction in
            guard !transaction.disablesAnimations else { return }
            transaction.animation = animation
        }
    }

    public init<Value: Equatable>(animation: Animation?, value: Value) {
        trigger = value as Any
        matchesTrigger = { ($0 as? Value) == value }
        transform = { transaction in
            guard !transaction.disablesAnimations else { return }
            transaction.animation = animation
        }
    }

    public init(transaction transform: @escaping (inout Transaction) -> Void) {
        trigger = nil
        matchesTrigger = nil
        self.transform = transform
    }

    /// Returns whether this modifier participated. A value modifier's first
    /// build only establishes its trigger; subsequent equal values inherit
    /// the parent transaction without replacing it.
    func apply(to transaction: inout Transaction, previous: RetainedAnimationModifier?) -> Bool {
        if let matchesTrigger {
            guard let previousTrigger = previous?.trigger, !matchesTrigger(previousTrigger) else {
                return false
            }
        }
        transform(&transaction)
        return true
    }
}

/// Allocated only for nodes with animation modifiers or a pending insertion
/// transaction. Ordinary nodes do not carry closure arrays or transactions.
@MainActor
final class RetainedAnimationModifierStorage {
    var modifiers: [RetainedAnimationModifier] = []
    var insertionTransaction: Transaction?
}

/// Full SwiftUI `Transaction` context propagated by `withTransaction`.
/// When present, property-change reconciliation reads `animation` and
/// `disablesAnimations` from this transaction in addition to the legacy
/// `currentAnimationTransaction` tuple.
@MainActor
public var currentTransaction: Transaction?
