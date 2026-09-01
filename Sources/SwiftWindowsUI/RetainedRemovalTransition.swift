import SwiftWindowsCore

/// Assignment identity for the authored removal configuration. Runtime replaces
/// it before releasing old transition/modifier payloads, including equal writes.
final class RetainedRemovalTransitionConfigurationID {}

/// Original native witnesses for one finite departure forest. This grants only
/// pre-retirement evaluation; it is not overlay, callback, or attachment authority
/// after any member leaves. The retirement owner consumes the resolved values.
@MainActor
final class RetainedRemovalTransitionAdmission {
    @MainActor
    private struct Root {
        weak var node: ViewNode?
        let completion: RetainedLazyListAdoptionCompletion
        let configuration: RetainedRemovalTransitionConfigurationID

        var isCurrent: Bool {
            completion.isCurrent && node?.removalTransitionConfigurationID === configuration
        }
    }

    private let nativeCheck: ComponentHost.NodeReconcileAdmission
    private let roots: [Root]
    private var resolvedRoots: Set<ObjectIdentifier> = []

    init?(nativeCheck: ComponentHost.NodeReconcileAdmission, departingRoots: [ViewNode]) {
        guard nativeCheck.isCurrent, !departingRoots.isEmpty else { return nil }
        var roots: [Root] = []
        var identities: Set<ObjectIdentifier> = []
        for node in departingRoots {
            guard identities.insert(ObjectIdentifier(node)).inserted,
                nativeCheck.admission?.permitsMutation(of: node) != false,
                let completion = RetainedLazyListAdoptionCompletion(of: node), completion.isCurrent
            else { return nil }
            roots.append(
                Root(node: node, completion: completion, configuration: node.removalTransitionConfigurationID))
        }
        guard nativeCheck.isCurrent, roots.allSatisfy(\.isCurrent) else { return nil }
        self.nativeCheck = nativeCheck
        self.roots = roots
    }

    var isCurrent: Bool { nativeCheck.isCurrent && roots.allSatisfy(\.isCurrent) }

    /// Never evaluate the same root's authored modifiers twice through this
    /// admission, including a nested call made by a modifier or clock callback.
    fileprivate func beginResolution(of node: ViewNode) -> Bool {
        guard isCurrent, roots.contains(where: { $0.node === node }) else { return false }
        return resolvedRoots.insert(ObjectIdentifier(node)).inserted
    }
}

/// Native values only. In particular, this does not retain a node, transaction
/// modifier, clock, Canvas source, or application cleanup callback.
struct RetainedRemovalTransitionAnimation {
    let initialOpacity: Double
    let initialTransform: Transform2D
    let frame: Rect
    let states: [AnimatableProperty: AnimationState]
    /// Properties actually written by this removal, not inferred from a clock
    /// that an unrelated existing tween may share.
    let removalProperties: Set<AnimatableProperty>
    let resolvedAt: Double

    var earliestStartTime: Double { states.values.map(\.startTime).min() ?? 0 }

    var duration: Double {
        guard let end = states.values.map({ $0.startTime + $0.duration }).max() else { return 0 }
        return max(0, end - earliestStartTime)
    }
}

enum RetainedRemovalTransitionResolution {
    case rejected
    case disabled
    case animated(RetainedRemovalTransitionAnimation)
}

@MainActor
enum RetainedRemovalTransitionResolver {
    /// Call inside the same ancestor transaction scope as actual child removal.
    /// An absent admission evaluates the ordinary rules without freshness
    /// checks. This method only resolves values; it does not start an animation.
    static func resolve(
        node: ViewNode, admission: RetainedRemovalTransitionAdmission? = nil
    ) -> RetainedRemovalTransitionResolution {
        guard admission?.beginResolution(of: node) != false else { return .rejected }
        let result = resolveWithCallbackPayloads(node: node, admission: admission)
        // Modifier snapshots and their captured values have finished unwinding
        // before this native post-check can authorize publication of the result.
        return admission?.isCurrent != false ? result : .rejected
    }

    /// Ordinary removal publishes before releasing modifier captures, matching
    /// the original mutating method. Publishing a pure result in its caller
    /// would overwrite animation changes made by those captures' destruction.
    static func applyOrdinary(node: ViewNode) -> Bool {
        if case .animated = resolveWithCallbackPayloads(node: node, admission: nil, applyOrdinaryAnimations: true) {
            return true
        }
        return false
    }

    /// A mounted Button source keeps its original departure receipt through
    /// callback payload destruction. Animation publication stays inside that
    /// payload scope so destruction cannot be followed by an obsolete write.
    static func applyGuarded(node: ViewNode, sourceDeparture: ButtonActionSourceDeparture? = nil) -> Bool {
        guard sourceDeparture?.owns(node) != false else { return false }
        let result = resolveWithCallbackPayloads(
            node: node, admission: nil, applyOrdinaryAnimations: true, sourceDeparture: sourceDeparture)
        sourceDeparture?.observe()
        guard sourceDeparture?.owns(node) != false else { return false }
        if case .animated = result { return true }
        return false
    }

    @inline(never)
    private static func resolveWithCallbackPayloads(
        node: ViewNode, admission: RetainedRemovalTransitionAdmission?, applyOrdinaryAnimations: Bool = false,
        sourceDeparture: ButtonActionSourceDeparture? = nil
    ) -> RetainedRemovalTransitionResolution {
        guard admission?.isCurrent != false, sourceDeparture?.owns(node) != false else { return .rejected }
        let removal = node.transition.removal
        guard removal.kind != .identity else { return .disabled }

        var fullTransaction =
            currentTransaction
            ?? currentAnimationTransaction.map {
                Transaction(animation: Animation(duration: $0.duration, easing: $0.easing))
            }
        let modifiers = node.reconcileAnimationModifiers
        defer { withExtendedLifetime(modifiers) {} }
        for modifier in modifiers.reversed() {
            guard admission?.isCurrent != false, sourceDeparture?.owns(node) != false else { return .rejected }
            var transaction = fullTransaction ?? Transaction()
            if modifier.apply(
                to: &transaction, previous: modifier, removalAdmission: admission,
                sourceDeparture: sourceDeparture, sourceDepartureNode: node)
            {
                fullTransaction = transaction
            }
            guard admission?.isCurrent != false, sourceDeparture?.owns(node) != false else { return .rejected }
        }
        if let fullTransaction,
            fullTransaction.disablesAnimations || fullTransaction.animation == nil
        {
            return .disabled
        }

        let transaction: (duration: Double, easing: AnimationEasing)? =
            fullTransaction?.animation.map { ($0.duration, $0.easing) }
            ?? currentAnimationTransaction ?? node.implicitReconcileAnimation.map { ($0.duration, $0.easing) }
        let duration = transaction?.duration ?? 0.35
        let easing = transaction?.easing ?? .easeInOut
        guard duration > 0 else { return .disabled }
        guard admission?.isCurrent != false, sourceDeparture?.owns(node) != false else { return .rejected }
        let now = node.animationClockNow
        guard admission?.isCurrent != false, sourceDeparture?.owns(node) != false else { return .rejected }

        // The ordinary path reads its starting pose after the clock callback.
        // Retain unrelated existing animations, just as direct removal did.
        let initialOpacity = node.opacity
        let initialTransform = node.transform
        let frame = node.resolvedFrame
        var states = node.animationStates
        var removalProperties: Set<AnimatableProperty> = []
        func record(_ property: AnimatableProperty, from start: Double, to end: Double) {
            states[property] = AnimationState(
                startValue: start, endValue: end, startTime: now, duration: duration, easing: easing)
            removalProperties.insert(property)
        }

        // A value transition cannot contain cycles. The worklist preserves the
        // original first-then-second overwrite order without recursive frames.
        var pending = [removal]
        while let transition = pending.popLast() {
            switch transition.kind {
            case .identity, .asymmetric, .modifier:
                break
            case .opacity:
                record(.opacity, from: initialOpacity, to: 0)
            case .scale(let x, let y, _, _):
                record(.transformScaleX, from: initialTransform.scaleX, to: x)
                record(.transformScaleY, from: initialTransform.scaleY, to: y)
            case .offset(let x, let y):
                record(.transformTranslationX, from: initialTransform.translationX, to: x)
                record(.transformTranslationY, from: initialTransform.translationY, to: y)
            case .move(let edge):
                let x: Double
                let y: Double
                switch edge {
                case .leading:
                    x = -frame.size.width
                    y = 0
                case .trailing:
                    x = frame.size.width
                    y = 0
                case .top:
                    x = 0
                    y = -frame.size.height
                case .bottom:
                    x = 0
                    y = frame.size.height
                }
                record(.transformTranslationX, from: initialTransform.translationX, to: x)
                record(.transformTranslationY, from: initialTransform.translationY, to: y)
            case .slide:
                record(.transformTranslationX, from: initialTransform.translationX, to: frame.size.width)
            case .push:
                record(.transformTranslationX, from: initialTransform.translationX, to: frame.size.width * 0.5)
                record(.transformScaleX, from: initialTransform.scaleX, to: 0.85)
            case .combined(let first, let second):
                pending.append(second)
                pending.append(first)
            }
        }
        guard !states.isEmpty else { return .disabled }
        if applyOrdinaryAnimations { node.animationStates = states }
        return .animated(
            RetainedRemovalTransitionAnimation(
                initialOpacity: initialOpacity, initialTransform: initialTransform, frame: frame, states: states,
                removalProperties: removalProperties, resolvedAt: now))
    }
}
