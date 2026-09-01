import SwiftWindowsCore

/// A native identity remains alive with its claim, so a later candidate cannot
/// impersonate a finished one by reusing its allocation address.
final class RetainedLazyListInsertionClaimID {}

/// One logical row's introduction. Accepted descriptor continuations move this
/// object, not a transaction or authority to build from an obsolete descriptor.
@MainActor
final class RetainedLazyListInsertionEvent {
    let declaration: RetainedLazyListLogicalDeclarationID
    private enum State {
        case pending
        case claimed(RetainedLazyListInsertionClaimID)
        case expired
    }
    private var state: State = .pending

    init(declaration: RetainedLazyListLogicalDeclarationID) { self.declaration = declaration }

    var isPending: Bool {
        if case .pending = state { return true }
        return false
    }

    @discardableResult
    func claim(_ identity: RetainedLazyListInsertionClaimID) -> Bool {
        switch state {
        case .pending:
            state = .claimed(identity)
            return true
        case .claimed(let previous):
            return previous === identity
        case .expired:
            return false
        }
    }

    func isClaimed(by identity: RetainedLazyListInsertionClaimID) -> Bool {
        if case .claimed(let previous) = state { return previous === identity }
        return false
    }

    func expireIfPending() {
        if case .pending = state { state = .expired }
    }
}

@MainActor
enum RetainedLazyListInsertionOrigin {
    case materialization
    case existingRow
    case logicalIntroduction(RetainedLazyListInsertionEvent)
}

/// Temporary inputs from the already bounded selected-record table. The plan
/// retains nodes and activity only weakly after indexing the returned forest.
@MainActor
struct RetainedLazyListInsertionRow {
    let token: RetainedLazyListRowToken
    let roots: [ViewNode]
    let activity: RetainedLazyListMaterializedRowActivity?
    let origin: RetainedLazyListInsertionOrigin
}

/// Native transport for a single candidate. Preparation is not arrival:
/// exact journal publications claim events before their outgoing payloads or
/// attachment controllers can call out. Only completed adoption may deliver.
@MainActor
final class RetainedLazyListInsertionPlan {
    @MainActor
    private final class Row {
        let token: RetainedLazyListRowToken
        weak var activity: RetainedLazyListMaterializedRowActivity?
        let origin: RetainedLazyListInsertionOrigin
        var hasCompletedTable = false

        init(_ row: RetainedLazyListInsertionRow) {
            token = row.token
            activity = row.activity
            origin = row.origin
        }

        var isLogicalIntroduction: Bool {
            if case .logicalIntroduction = origin { return true }
            return false
        }

        func claim(_ identity: RetainedLazyListInsertionClaimID) -> Bool {
            if case .logicalIntroduction(let event) = origin { return event.claim(identity) }
            return true
        }

        func permitsDelivery(_ identity: RetainedLazyListInsertionClaimID) -> Bool {
            guard hasCompletedTable, let activity, activity.logicalMembership.isDeclared,
                activity.physical.state == .active
            else { return false }
            if case .logicalIntroduction(let event) = origin { return event.isClaimed(by: identity) }
            return true
        }
    }

    @MainActor
    private final class Source {
        weak var node: ViewNode?
        let row: Row
        let identity: RetainedLazyListViewIdentityProof
        let configuration: RetainedRemovalTransitionConfigurationID

        init(node: ViewNode, row: Row) {
            self.node = node
            self.row = row
            identity = node.captureLazyListIdentityProof()
            configuration = node.removalTransitionConfigurationID
        }

        var isCurrent: Bool {
            guard let node else { return false }
            return identity.isCurrent && node.removalTransitionConfigurationID === configuration
        }
    }

    private struct Recipe {
        let transition: RetainedTransition
        let opacity: Double
        let transform: Transform2D
        let implicitAnimation: AnimationTransaction?
        let transaction: RetainedBuildTransaction

        init(source: ViewNode, transaction: RetainedBuildTransaction) {
            transition = source.transition.insertion
            opacity = source.opacity
            transform = source.transform
            implicitAnimation = source.implicitReconcileAnimation
            self.transaction = transaction
        }

        var timing: AnimationTransaction? {
            if let full = transaction.transaction, full.disablesAnimations || full.animation == nil { return nil }
            let timing =
                transaction.transaction?.animation.map {
                    AnimationTransaction(duration: $0.duration, easing: $0.easing)
                }
                ?? transaction.animation.map { AnimationTransaction(duration: $0.duration, easing: $0.easing) }
                ?? implicitAnimation ?? AnimationTransaction(duration: 0.35, easing: .easeInOut)
            return timing.duration.isFinite && timing.duration > 0 ? timing : nil
        }
    }

    @MainActor
    private final class Target {
        let source: Source
        weak var node: ViewNode?
        let isFresh: Bool
        let identity: RetainedLazyListViewIdentityProof
        let originalAttachment: RetainedLazyListAttachmentProof?
        var configuration: RetainedRemovalTransitionConfigurationID
        var publication: RetainedLazyListActualAttachment?
        var recipe: Recipe?
        var deliveredSourceOpacity: Double?
        var deliveredSourceTransform: Transform2D?

        init(source: Source, node: ViewNode, isFresh: Bool) {
            self.source = source
            self.node = node
            self.isFresh = isFresh
            identity = node.captureLazyListIdentityProof()
            originalAttachment = isFresh ? nil : node.captureLazyListAttachmentProof()
            configuration = node.removalTransitionConfigurationID
        }

        var isCurrent: Bool {
            guard source.isCurrent, let node, identity.isCurrent,
                originalAttachment?.isCurrent != false, publication?.isAttached != false
            else { return false }
            if let recipe {
                guard let declared = source.node,
                    declared.opacity.bitPattern == (deliveredSourceOpacity ?? recipe.opacity).bitPattern,
                    declared.transform == (deliveredSourceTransform ?? recipe.transform)
                else { return false }
            }
            return node.removalTransitionConfigurationID === configuration
        }

        var isEligible: Bool {
            switch source.row.origin {
            case .materialization: return false
            case .existingRow: return isFresh
            case .logicalIntroduction: return true
            }
        }
    }

    @MainActor
    private struct Presentation {
        let target: Target
        let sourceOpacity: Double
        let sourceTransform: Transform2D
        let opacity: Double
        let transform: Transform2D
        let frame: Rect
        let states: [AnimatableProperty: AnimationState]
        let recipe: Recipe
        let timing: AnimationTransaction

        init?(target: Target) {
            guard let node = target.node, let source = target.source.node,
                let recipe = target.recipe, recipe.transition.kind != .identity, let timing = recipe.timing,
                source.opacity.bitPattern == recipe.opacity.bitPattern, source.transform == recipe.transform
            else { return nil }
            self.target = target
            sourceOpacity = source.opacity
            sourceTransform = source.transform
            opacity = node.opacity
            transform = node.transform
            frame = node.resolvedFrame
            states = node.animationStates
            self.recipe = recipe
            self.timing = timing
        }

        var isCurrent: Bool {
            guard target.isCurrent, let node = target.node, let source = target.source.node else { return false }
            return source.opacity.bitPattern == sourceOpacity.bitPattern && source.transform == sourceTransform
                && node.opacity.bitPattern == opacity.bitPattern && node.transform == transform
                && node.resolvedFrame == frame
                && Self.sameStates(node.animationStates, states)
        }

        private static func sameStates(
            _ first: [AnimatableProperty: AnimationState], _ second: [AnimatableProperty: AnimationState]
        ) -> Bool {
            guard first.count == second.count else { return false }
            return first.allSatisfy { property, value in
                guard let other = second[property] else { return false }
                return value.startValue.bitPattern == other.startValue.bitPattern
                    && value.endValue.bitPattern == other.endValue.bitPattern
                    && value.startTime.bitPattern == other.startTime.bitPattern
                    && value.duration.bitPattern == other.duration.bitPattern && value.easing == other.easing
            }
        }

        /// Value-only planning and publication. No application code runs while
        /// these scalar poses/states replace the just-validated presentation.
        func apply(at timestamp: Double) {
            guard let node = target.node else { return }
            var nextOpacity = opacity
            var nextTransform = transform
            var nextStates = states
            func record(_ property: AnimatableProperty, from start: Double, to end: Double) {
                nextStates[property] = AnimationState(
                    startValue: start, endValue: end, startTime: timestamp,
                    duration: timing.duration, easing: timing.easing)
            }
            func translate(x: Double, y: Double) {
                nextTransform.translationX = x
                nextTransform.translationY = y
                record(.transformTranslationX, from: x, to: recipe.transform.translationX)
                record(.transformTranslationY, from: y, to: recipe.transform.translationY)
            }
            var pending = [recipe.transition]
            while let transition = pending.popLast() {
                switch transition.kind {
                case .identity, .asymmetric, .modifier:
                    break
                case .opacity:
                    nextOpacity = 0
                    record(.opacity, from: 0, to: recipe.opacity)
                case .scale(let x, let y, _, _):
                    nextTransform.scaleX = x
                    nextTransform.scaleY = y
                    record(.transformScaleX, from: x, to: recipe.transform.scaleX)
                    record(.transformScaleY, from: y, to: recipe.transform.scaleY)
                case .offset(let x, let y):
                    translate(x: x, y: y)
                case .move(let edge):
                    switch edge {
                    case .leading: translate(x: -frame.size.width, y: 0)
                    case .trailing: translate(x: frame.size.width, y: 0)
                    case .top: translate(x: 0, y: -frame.size.height)
                    case .bottom: translate(x: 0, y: frame.size.height)
                    }
                case .slide:
                    nextTransform.translationX = frame.size.width
                    record(.transformTranslationX, from: frame.size.width, to: recipe.transform.translationX)
                case .push:
                    nextTransform.translationX = frame.size.width * 0.5
                    nextTransform.scaleX = 0.85
                    record(.transformTranslationX, from: frame.size.width * 0.5, to: recipe.transform.translationX)
                    record(.transformScaleX, from: 0.85, to: recipe.transform.scaleX)
                case .combined(let first, let second):
                    pending.append(second)
                    pending.append(first)
                }
            }
            if node.opacity != nextOpacity { node.opacity = nextOpacity }
            if node.transform != nextTransform { node.transform = nextTransform }
            node.animationStates = nextStates
            if target.source.node === node {
                // Only the fresh source which is itself the actual target has
                // changed its declared pose through these exact native writes.
                target.deliveredSourceOpacity = nextOpacity
                target.deliveredSourceTransform = nextTransform
            }
        }
    }

    private enum Phase { case preparing, resolving, completed, discarded }
    private var phase: Phase = .preparing
    private let claim = RetainedLazyListInsertionClaimID()
    private let rows: [RetainedLazyListRowToken: Row]
    private let sources: [ObjectIdentifier: Source]
    private var targets: [ObjectIdentifier: Target] = [:]
    private var targetSources: [ObjectIdentifier: ObjectIdentifier] = [:]

    init?(rows input: [RetainedLazyListInsertionRow]) {
        var rows: [RetainedLazyListRowToken: Row] = [:]
        var sources: [ObjectIdentifier: Source] = [:]
        for inputRow in input {
            guard rows[inputRow.token] == nil else { return nil }
            let row = Row(inputRow)
            rows[inputRow.token] = row
            var pending = inputRow.roots.map { (node: $0, depth: 0) }
            while let entry = pending.popLast() {
                let identity = ObjectIdentifier(entry.node)
                guard entry.depth <= ViewNode.maximumTraversalDepth, sources[identity] == nil else { return nil }
                sources[identity] = Source(node: entry.node, row: row)
                for child in entry.node.children {
                    guard child.parent === entry.node else { return nil }
                    pending.append((child, entry.depth + 1))
                }
            }
        }
        self.rows = rows
        self.sources = sources
    }

    var isCurrent: Bool {
        switch phase {
        case .discarded: return false
        case .preparing, .resolving, .completed:
            return sources.values.allSatisfy(\.isCurrent) && targets.values.allSatisfy(\.isCurrent)
        }
    }

    func isLogicalIntroduction(of source: ViewNode) -> Bool {
        guard let entry = sources[ObjectIdentifier(source)], entry.node === source else { return false }
        return entry.row.isLogicalIntroduction
    }

    /// Begin before modifier callbacks. Only exact accepted framework copies
    /// can advance this original target configuration witness afterwards.
    func beginNode(source: ViewNode, target: ViewNode, isFresh: Bool) -> Bool {
        guard phase == .preparing, isCurrent,
            let entry = sources[ObjectIdentifier(source)], entry.node === source
        else { return false }
        let key = ObjectIdentifier(source)
        if let previous = targets[key] { return previous.node === target && previous.isFresh == isFresh }
        let actualKey = ObjectIdentifier(target)
        guard targetSources[actualKey] == nil else { return false }
        targets[key] = Target(source: entry, node: target, isFresh: isFresh)
        targetSources[actualKey] = key
        return isCurrent
    }

    func prepareNode(source: ViewNode, target: ViewNode, transaction: RetainedBuildTransaction) -> Bool {
        guard phase == .preparing, isCurrent, let entry = targets[ObjectIdentifier(source)],
            entry.node === target, entry.recipe == nil
        else { return false }
        entry.recipe = Recipe(source: source, transaction: transaction)
        return true
    }

    /// Called only with an already accepted exact native journal publication.
    /// Claiming historical acceptance deliberately does not reacquire today's
    /// adapter or whole-admission authority. It cannot authorize an animation.
    func recordAcceptedPublication(
        from source: ViewNode, to target: ViewNode, actual: RetainedLazyListActualAttachment,
        copiedConfiguration: Bool = false, inserted: Bool = false
    ) {
        guard phase == .preparing, let entry = targets[ObjectIdentifier(source)],
            entry.source.node === source, entry.node === target, actual.node === target
        else { return }
        if copiedConfiguration { entry.configuration = target.removalTransitionConfigurationID }
        guard entry.recipe != nil else { return }
        // The scalar claim persists even if later callbacks reject this row.
        guard entry.source.row.claim(claim) else { return }
        if entry.publication == nil { entry.publication = actual }
        if inserted && entry.isFresh {
            let initial: Bool
            if case .materialization = entry.source.row.origin { initial = true } else { initial = false }
            target.consumeManagedInsertionArrival(initial: initial)
        } else if entry.source.row.isLogicalIntroduction {
            target.consumeManagedInsertionArrival(initial: false)
        }
    }

    func recordCompletedRow(_ activity: RetainedLazyListMaterializedRowActivity) {
        // The adapter publishes a zero-root table after the completed nonempty
        // delivery pass. That is still this candidate's first actual acceptance.
        guard phase == .preparing || phase == .completed,
            let row = rows[activity.request.token], row.activity === activity
        else { return }
        _ = row.claim(claim)
        row.hasCompletedTable = true
    }

    func discard() { phase = .discarded }

    func deliver(
        in runtime: RetainedViewRuntime, admission: RetainedLazyListAdoptionAdmission,
        completion: RetainedLazyListAdoptionCompletion, journal: RetainedLazyListAdoptionJournal
    ) -> Bool {
        guard phase == .preparing, admission.isCurrent, completion.isCurrent, journal.canContinueAdoption else {
            return false
        }
        phase = .resolving
        let eligible = targets.values.filter { $0.isEligible && $0.publication != nil }
        guard eligible.allSatisfy({ $0.source.row.permitsDelivery(claim) && $0.isCurrent }) else { return false }
        let presentations = eligible.compactMap(Presentation.init)
        guard presentations.allSatisfy(\.isCurrent), admission.isCurrent, completion.isCurrent,
            journal.canContinueAdoption
        else { return false }
        let timestamp: Double
        if presentations.isEmpty {
            timestamp = 0
        } else {
            guard let sampled = Self.sampleClock(in: runtime) else { return false }
            timestamp = sampled
        }
        // The injected clock and its captures have unwound before these
        // original proofs admit the first scalar presentation write.
        guard admission.isCurrent, completion.isCurrent, journal.canContinueAdoption,
            eligible.allSatisfy({ $0.source.row.permitsDelivery(claim) && $0.isCurrent }),
            presentations.allSatisfy(\.isCurrent)
        else { return false }
        // Fresh sources are also actual targets. Advance only our controlled
        // scalar pose witnesses beside the writes, preserving tree/config proof.
        phase = .completed
        for presentation in presentations { presentation.apply(at: timestamp) }
        return admission.isCurrent && completion.isCurrent && journal.canContinueAdoption
    }

    @inline(never)
    private static func sampleClock(in runtime: RetainedViewRuntime) -> Double? {
        let clock = runtime.clock
        let timestamp = clock()
        withExtendedLifetime(clock) {}
        return timestamp.isFinite ? timestamp : nil
    }
}
