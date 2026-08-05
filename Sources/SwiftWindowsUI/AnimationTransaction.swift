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

/// Full SwiftUI `Transaction` context propagated by `withTransaction`.
/// When present, property-change reconciliation reads `animation` and
/// `disablesAnimations` from this transaction in addition to the legacy
/// `currentAnimationTransaction` tuple.
@MainActor
public var currentTransaction: Transaction?
