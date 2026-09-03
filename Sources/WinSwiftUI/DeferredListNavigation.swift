import SwiftWindowsCore
import SwiftWindowsUI

/// Only a currently materialized leaf carries this value. Logical metadata
/// keeps model IDs; an authored .tag is learned from the actual row output.
@MainActor
struct DeferredListRowNavigation {
    private enum Marker {}
    let ordinal: Int
    let leaf: Int
    let tag: AnyHashable

    static func install(on node: ViewNode, ordinal: Int, leaf: Int, tag: AnyHashable) {
        node.retainedPreferenceValues[ObjectIdentifier(Marker.self)] = Self(ordinal: ordinal, leaf: leaf, tag: tag)
    }

    static func attached(to node: ViewNode) -> Self? {
        node.retainedPreferenceValues[ObjectIdentifier(Marker.self)] as? Self
    }
}

/// Selection actions retain one pending logical cursor, not a registry of all
/// row owners visited while scrolling. Actual focus still uses the existing
/// List navigation receipt and the adopted row's physical attachment.
@MainActor
final class DeferredListKeyboardNavigation {
    @MainActor
    private final class Request {
        let receipt: RetainedListNavigationReceipt
        let source: DeferredListScrollSource
        let selected: AnyHashable?
        let set: (AnyHashable?) -> Void
        let invalidate: () -> Void
        let transaction: Transaction
        let direction: Int
        var ordinal: Int
        var leaf: Int?
        var ordinaryDestinationLeaf: Int?
        var warmHandoff: RetainedLazyListWarmKeyboardHandoff?
        var item: RetainedLazyListAccessibilityItem?
        var keyboardPreparation: RetainedLazyListKeyboardPreparation?
        var attemptedKeyboardPreparation = false
        var requiresRevealBeforeFocus = false
        var needsSelectionSearch = false
        var needsImplicitSelectionValidation = false
        var selectionCursor: RetainedLazyListScrollSearchCursor?
        var selectionWitness: RetainedLazyListScrollSearchCursor?
        var bindingWasWritten = false

        init(
            receipt: RetainedListNavigationReceipt, source: DeferredListScrollSource, selected: AnyHashable?,
            set: @escaping (AnyHashable?) -> Void, invalidate: @escaping () -> Void,
            direction: Int, ordinal: Int, leaf: Int?
        ) {
            self.receipt = receipt
            self.source = source
            self.selected = selected
            self.set = set
            self.invalidate = invalidate
            self.direction = direction
            self.ordinal = ordinal
            self.leaf = leaf
            var transaction = currentTransaction ?? Transaction()
            if currentTransaction == nil, let animation = currentAnimationTransaction {
                transaction.animation = Animation(duration: animation.duration, easing: animation.easing)
            }
            self.transaction = transaction
        }
    }

    private weak var runtime: RetainedViewRuntime?
    private let containerBinding: RetainedLazyListNavigationContainer
    private let scope: RetainedListNavigationOwner
    private let prefersImplicitSelectionTag: Bool
    private var request: Request?

    init(
        runtime: RetainedViewRuntime, container: RetainedLazyListNavigationContainer,
        scope: RetainedListNavigationOwner,
        prefersImplicitSelectionTag: Bool
    ) {
        self.runtime = runtime
        containerBinding = container
        self.scope = scope
        self.prefersImplicitSelectionTag = prefersImplicitSelectionTag
    }

    private var container: ViewNode? { containerBinding.node }

    func moveSelection(
        _ mode: ListSelectionMode, from sourceOwner: RetainedListNavigationOwner,
        sourceTag: AnyHashable?, ordinal: Int?, leaf: Int?, delta: Int,
        invalidate: @escaping () -> Void
    ) {
        guard delta != 0, case .single(let get, let set) = mode,
            let container, let source = DeferredListScrollSource.attached(to: container),
            source.rowCount > 0, let receipt = scope.prepareAction(from: sourceOwner)
        else { return }
        cancelPendingRequest()
        guard receipt.permitsBindingWrite else { return }
        let selected = get { receipt.permitsBindingWrite }
        guard receipt.permitsBindingWrite else { return }
        let direction = delta > 0 ? 1 : -1
        var start = direction > 0 ? 0 : source.rowCount - 1
        var requestedLeaf: Int?
        var needsSelectionSearch = false
        var needsImplicitSelectionValidation = false
        if let selected {
            let selectsSource: Bool
            if let sourceTag {
                selectsSource =
                    RetainedViewIdentity.Key(selected).checkedEquals(
                        RetainedViewIdentity.Key(sourceTag), isCurrent: { receipt.permitsBindingWrite }) == true
            } else {
                selectsSource = false
            }
            guard receipt.permitsBindingWrite else { return }
            if prefersImplicitSelectionTag {
                if let selectedIndex = source.index(for: selected, isCurrent: { receipt.permitsBindingWrite }) {
                    start = selectedIndex
                    needsImplicitSelectionValidation = true
                }
            } else if selectsSource, ordinal == 0, leaf == 0 {
                // Only the first projected leaf proves first occurrence
                // without looking at any earlier authored selection tags.
                start = 0
                requestedLeaf = direction
            } else {
                // The selected value may be an authored .tag on an unbuilt
                // row, unrelated to its model ID or the focused source row.
                // A focused later occurrence cannot bypass the first-match
                // rule for another projected leaf carrying the same tag.
                needsSelectionSearch = true
            }
        }
        guard receipt.permitsBindingWrite, DeferredListScrollSource.attached(to: container) === source else { return }
        let next = Request(
            receipt: receipt, source: source, selected: selected, set: set, invalidate: invalidate,
            direction: direction, ordinal: start, leaf: requestedLeaf)
        next.needsSelectionSearch = needsSelectionSearch
        next.needsImplicitSelectionValidation = needsImplicitSelectionValidation
        request = next
        continueRequest(next)
    }

    /// Call only after the source admitted a newer native action. An escaped
    /// old handler must not cancel work that survived an accepted rebuild.
    func cancelPendingRequest() {
        if let request { cancel(request) }
    }

    private func isCurrent(_ request: Request) -> Bool {
        guard self.request === request else { return false }
        if request.bindingWasWritten { return request.receipt.permitsContinuation }
        guard request.receipt.permitsBindingWrite, let container,
            DeferredListScrollSource.attached(to: container) === request.source
        else { return false }
        if let witness = request.selectionWitness {
            return runtime?.isLazyListScrollSourceCurrent(witness, in: container) == true
        }
        return true
    }

    /// The runtime shares one construction budget across this whole walk.
    /// Known empty/disabled leaves can be skipped synchronously, but a long
    /// run yields after 32 records or leaves to the next ordinary layout pass.
    /// A pending item retains just its native logical demand, never its nodes.
    private func continueRequest(_ request: Request) {
        if request.bindingWasWritten {
            finishWrittenRequest(request)
            return
        }
        if let runtime {
            runtime.withLazyListResolutionBudget {
                continueInCurrentBudget(request)
            }
        } else {
            continueInCurrentBudget(request)
        }
    }

    private func continueInCurrentBudget(_ request: Request) {
        if request.needsSelectionSearch {
            switch resolveSelectionPosition(request) {
            case .ready:
                break
            case .pending:
                schedule(request)
                return
            case .obsolete:
                cancel(request)
                return
            }
        }
        for _ in 0..<32 {
            guard isCurrent(request), let container, let row = request.source.row(at: request.ordinal) else {
                cancel(request)
                return
            }
            let nodes: [ViewNode]
            if let runtime {
                if request.item == nil {
                    request.item = runtime.lazyListTarget(in: container, key: row.providerKey)
                    if let item = request.item {
                        request.requiresRevealBeforeFocus =
                            request.keyboardPreparation?.originalRequiresRevealBeforeFocus(for: item.token)
                            ?? (runtime.realizedLazyListAccessibilityNodes(for: item) == nil)
                    }
                }
                guard isCurrent(request) else {
                    cancel(request)
                    return
                }
                guard let item = request.item else {
                    cancel(request)
                    return
                }
                if request.needsImplicitSelectionValidation, !request.attemptedKeyboardPreparation {
                    request.attemptedKeyboardPreparation = true
                    let adjacent = request.source.row(at: request.ordinal + request.direction).flatMap {
                        runtime.lazyListTarget(in: container, key: $0.providerKey)
                    }
                    guard isCurrent(request) else {
                        cancel(request)
                        return
                    }
                    request.keyboardPreparation = runtime.beginLazyListKeyboardPreparation(
                        from: item, toward: adjacent, receipt: request.receipt)
                    if let originalPolicy = request.keyboardPreparation?.originalRequiresRevealBeforeFocus(
                        for: item.token)
                    {
                        request.requiresRevealBeforeFocus = originalPolicy
                    }
                }
                let resolution = resolvePhysicalRows(item, request: request, runtime: runtime)
                guard isCurrent(request) else {
                    cancel(request)
                    return
                }
                switch resolution {
                case .accepted(let roots):
                    nodes = roots
                case .pending:
                    schedule(request)
                    return
                case .empty:
                    guard request.ordinaryDestinationLeaf == nil else {
                        cancel(request)
                        return
                    }
                    if request.needsImplicitSelectionValidation {
                        useUnmatchedSelectionBoundary(request)
                    } else {
                        advance(request)
                    }
                    continue
                case .obsolete, .unsupported:
                    cancel(request)
                    return
                }
            } else {
                // Already realized standalone rows remain navigable after
                // their weak runtime expires. Missing rows stay unavailable.
                nodes = container.children.filter {
                    DeferredListRowNavigation.attached(to: $0)?.ordinal == request.ordinal
                }
                guard !nodes.isEmpty else {
                    cancel(request)
                    return
                }
            }
            let rows = nodes.compactMap { node -> (ViewNode, DeferredListRowNavigation)? in
                guard !node.isHidden, !node.isSeparatorRule, node.isFocusEnabled,
                    node.listNavigationOwner != nil,
                    let metadata = DeferredListRowNavigation.attached(to: node), metadata.ordinal == request.ordinal
                else { return nil }
                return (node, metadata)
            }.sorted { $0.1.leaf < $1.1.leaf }
            if request.needsImplicitSelectionValidation {
                guard let first = rows.first else {
                    useUnmatchedSelectionBoundary(request)
                    continue
                }
                // A logical model ID is not proof that it contributed a
                // selectable leaf. Preserve the eager ordered-tag fallback
                // for empty/disabled records and begin from its actual first
                // eligible leaf when it does contribute selection content.
                request.needsImplicitSelectionValidation = false
                request.leaf = first.1.leaf + request.direction
            }
            let target: (ViewNode, DeferredListRowNavigation)?
            if let leaf = request.ordinaryDestinationLeaf {
                target = rows.first(where: { $0.1.leaf == leaf })
            } else if let leaf = request.leaf {
                target =
                    request.direction > 0
                    ? rows.first(where: { $0.1.leaf >= leaf })
                    : rows.last(where: { $0.1.leaf <= leaf })
            } else {
                target = request.direction > 0 ? rows.first : rows.last
            }
            guard let (node, metadata) = target, let owner = node.listNavigationOwner else {
                guard request.ordinaryDestinationLeaf == nil else {
                    cancel(request)
                    return
                }
                advance(request)
                continue
            }
            if let selected = request.selected {
                let isSame = RetainedViewIdentity.Key(selected).checkedEquals(
                    RetainedViewIdentity.Key(metadata.tag), isCurrent: { self.isCurrent(request) })
                guard isCurrent(request) else {
                    cancel(request)
                    return
                }
                if isSame == true {
                    cancel(request)
                    return
                }
            }
            if let runtime, !runtime.canPrepareLayoutSettlement {
                // Current-pass roots are enough for a scroll probe, not for
                // publishing keyboard focus. Reuse the native settlement
                // queue and keep this one demand until layout is truly idle.
                schedule(request, afterLayout: false)
                return
            }
            if let preparation = request.keyboardPreparation, !request.requiresRevealBeforeFocus {
                guard isCurrent(request), let runtime, let item = request.item,
                    let handoff = runtime.prepareOrdinaryLazyListKeyboardTarget(item, using: preparation),
                    isCurrent(request)
                else {
                    cancel(request)
                    return
                }
                // Only the actual destination can leave this construction
                // plan. Keep its exact leaf while the ordinary resolver earns
                // readiness; unwind these row/tag captures before that query.
                request.ordinaryDestinationLeaf = metadata.leaf
                request.warmHandoff = handoff
                request.leaf = metadata.leaf
                finishKeyboardPreparation(request)
                continue
            }
            request.receipt.traceKeyboardFocus(
                request.requiresRevealBeforeFocus ? "target.reveal-first" : "target.focus-first")
            guard isCurrent(request),
                request.receipt.prepareTarget(owner, requiresRevealBeforeFocus: request.requiresRevealBeforeFocus),
                isCurrent(request)
            else {
                cancel(request)
                return
            }
            if let preparation = request.keyboardPreparation {
                guard let runtime, let item = request.item,
                    runtime.prepareLazyListKeyboardSelection(item, using: preparation), isCurrent(request)
                else {
                    cancel(request)
                    return
                }
            }
            // A setter may replace this declaration or admit a newer action.
            // Its one accepted invalidation still runs; only the original
            // native physical receipt may continue toward focus afterward.
            request.bindingWasWritten = true
            request.selectionCursor = nil
            request.selectionWitness = nil
            withTransaction(request.transaction) {
                request.set(metadata.tag)
                request.invalidate()
            }
            finishWrittenRequest(request)
            return
        }
        schedule(request)
    }

    private func finishWrittenRequest(_ request: Request) {
        guard isCurrent(request) else {
            request.receipt.traceKeyboardFocus("written.obsolete")
            cancel(request)
            return
        }
        if let runtime, !runtime.canPrepareLayoutSettlement {
            request.receipt.traceKeyboardFocus("written.layout-blocked")
            schedule(request, afterLayout: false)
            return
        }
        withTransaction(request.transaction) {
            switch request.receipt.settlePreparedTarget() {
            case .ready:
                request.receipt.traceKeyboardFocus("settle.ready")
                guard isCurrent(request) else {
                    cancel(request)
                    return
                }
                self.request = nil
                let finished = request.receipt.finishNavigation()
                request.receipt.traceKeyboardFocus(finished ? "finish.true" : "finish.false")
                finishKeyboardPreparation(request)
                releaseItem(request)
            case .pending:
                request.receipt.traceKeyboardFocus("settle.pending")
                schedule(request)
            case .obsolete:
                request.receipt.traceKeyboardFocus("settle.obsolete")
                cancel(request)
            }
        }
    }

    private enum SelectionSearchResult { case ready, pending, obsolete }

    /// Matching an opaque selection tag may require O(data) total work. It
    /// borrows the same bounded doomed-build route as opaque scroll IDs; probes
    /// never appear, start tasks, or become a retained row cache.
    private func resolveSelectionPosition(_ request: Request) -> SelectionSearchResult {
        guard isCurrent(request), let runtime, let container, let selected = request.selected else { return .obsolete }
        if request.selectionWitness == nil {
            guard let witness = runtime.captureLazyListScrollSource(in: container) else { return .pending }
            request.selectionWitness = witness
        }
        guard isCurrent(request) else { return .obsolete }
        var mountedMatch: (ordinal: Int, leaf: Int)?
        for node in container.children {
            guard isCurrent(request) else { return .obsolete }
            guard !node.isHidden, node.isFocusEnabled, node.listNavigationOwner != nil,
                let metadata = DeferredListRowNavigation.attached(to: node)
            else { continue }
            let equal = RetainedViewIdentity.Key(metadata.tag).checkedEquals(
                RetainedViewIdentity.Key(selected), isCurrent: { self.isCurrent(request) })
            guard isCurrent(request) else { return .obsolete }
            if equal == true,
                mountedMatch == nil || metadata.ordinal < mountedMatch!.ordinal
                    || (metadata.ordinal == mountedMatch!.ordinal && metadata.leaf < mountedMatch!.leaf)
            {
                mountedMatch = (metadata.ordinal, metadata.leaf)
            }
        }
        var found: (ordinal: Int, leaf: Int)?
        let result = runtime.probeLazyListScrollTarget(
            in: container, after: request.selectionCursor, requestIsCurrent: { self.isCurrent(request) },
            matches: { nodes in
                for node in nodes {
                    guard self.isCurrent(request) else { return false }
                    guard !node.isHidden, node.isFocusEnabled, node.listNavigationOwner != nil,
                        let metadata = DeferredListRowNavigation.attached(to: node)
                    else { continue }
                    if let mountedMatch, metadata.ordinal > mountedMatch.ordinal {
                        // Native probing is ordered and skips mounted records.
                        // Crossing this ordinal proves the earlier mounted match.
                        found = mountedMatch
                        return true
                    }
                    let equal = RetainedViewIdentity.Key(metadata.tag).checkedEquals(
                        RetainedViewIdentity.Key(selected), isCurrent: { self.isCurrent(request) })
                    guard self.isCurrent(request) else { return false }
                    if equal == true {
                        found = (metadata.ordinal, metadata.leaf)
                        return true
                    }
                }
                return false
            })
        guard isCurrent(request) else { return .obsolete }
        switch result {
        case .more(let cursor):
            request.selectionCursor = cursor
            return .pending
        case .deferred:
            return .pending
        case .obsolete:
            return .obsolete
        case .found:
            guard let found else { return .obsolete }
            request.ordinal = found.ordinal
            request.leaf = found.leaf + request.direction
        case .notFound:
            if let mountedMatch {
                request.ordinal = mountedMatch.ordinal
                request.leaf = mountedMatch.leaf + request.direction
            } else {
                request.ordinal = request.direction > 0 ? 0 : request.source.rowCount - 1
                request.leaf = nil
            }
        }
        request.selectionCursor = nil
        request.needsSelectionSearch = false
        return .ready
    }

    private func advance(_ request: Request) {
        releaseItem(request)
        request.requiresRevealBeforeFocus = false
        request.ordinal += request.direction
        request.leaf = nil
    }

    private func useUnmatchedSelectionBoundary(_ request: Request) {
        releaseItem(request)
        request.needsImplicitSelectionValidation = false
        request.requiresRevealBeforeFocus = false
        request.ordinal = request.direction > 0 ? 0 : request.source.rowCount - 1
        request.leaf = nil
    }

    private func releaseItem(_ request: Request) {
        if request.keyboardPreparation == nil, let item = request.item { runtime?.releaseLazyListTarget(item) }
        request.item = nil
    }

    private func finishKeyboardPreparation(_ request: Request) {
        if let preparation = request.keyboardPreparation { runtime?.endLazyListKeyboardPreparation(preparation) }
        request.keyboardPreparation = nil
    }

    /// The new result describes physical eligibility only. Ordinary callers
    /// still obtain the stronger ready result from the unchanged resolver.
    private func resolvePhysicalRows(
        _ item: RetainedLazyListAccessibilityItem, request: Request, runtime: RetainedViewRuntime
    ) -> RetainedLazyListKeyboardEligibility {
        if let preparation = request.keyboardPreparation {
            let result = runtime.prepareLazyListKeyboardItem(item, using: preparation)
            if case .unsupported = result {
                // An accepted skip can leave the finite cohort. Release its
                // owed protection and continue the existing walk, under the
                // same original binding and event budget. Obsolete/pending
                // preparation never reaches this fallback or another batch.
                finishKeyboardPreparation(request)
                guard isCurrent(request), runtime.isLazyListAccessibilityItemCurrent(item) else { return .obsolete }
            } else {
                return result
            }
        }
        let resolution: RetainedLazyListTargetResolution
        if request.ordinaryDestinationLeaf != nil {
            guard let handoff = request.warmHandoff else { return .obsolete }
            resolution = runtime.resolveOrdinaryLazyListKeyboardTarget(item, using: handoff)
        } else {
            resolution = runtime.resolveLazyListTarget(item)
        }
        switch resolution {
        case .ready(let roots): return .accepted(roots)
        case .empty: return .empty
        case .pending: return .pending
        case .obsolete: return .obsolete
        case .unsupported: return .unsupported
        }
    }

    private func cancel(_ request: Request) {
        if self.request === request { self.request = nil }
        request.receipt.cancelPreparedNavigation()
        finishKeyboardPreparation(request)
        releaseItem(request)
        request.selectionCursor = nil
        request.selectionWitness = nil
    }

    private func schedule(_ request: Request, afterLayout: Bool = true) {
        // The inside-cohort warm handoff may use only its original operation's
        // remaining budget. Pending ordinary work cannot create a later replay;
        // any already accepted binding write still keeps its normal cleanup.
        guard request.ordinaryDestinationLeaf == nil else {
            cancel(request)
            return
        }
        guard isCurrent(request), request.bindingWasWritten || request.source.row(at: request.ordinal) != nil
        else {
            cancel(request)
            return
        }
        // One native scope slot keeps this controller and request alive when
        // an accepted rebuild replaces the old row handlers. Supersession or
        // departure removes that slot; neither object owns the runtime or nodes.
        guard
            request.receipt.schedulePreparedNavigationReplay(
                afterLayout: afterLayout, keyboardPreparation: request.keyboardPreparation,
                perform: { [self, request] in
                    guard self.isCurrent(request) else {
                        self.cancel(request)
                        return
                    }
                    self.continueRequest(request)
                },
                onCancel: { [self, request] in self.cancel(request) })
        else {
            cancel(request)
            return
        }
    }
}
