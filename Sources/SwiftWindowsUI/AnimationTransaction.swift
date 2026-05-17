import SwiftWindowsCore

/// Global animation transaction used by `withAnimation` to propagate
/// animation context to the next property-change reconciliation cycle.
/// Holds the duration and easing to apply when a property changes and no
/// per-property animation state (from `.animation()`) is already present.
@MainActor
public var currentAnimationTransaction: (duration: Double, easing: AnimationEasing)?

/// Full SwiftUI `Transaction` context propagated by `withTransaction`.
/// When present, property-change reconciliation reads `animation` and
/// `disablesAnimations` from this transaction in addition to the legacy
/// `currentAnimationTransaction` tuple.
@MainActor
public var currentTransaction: Transaction?
