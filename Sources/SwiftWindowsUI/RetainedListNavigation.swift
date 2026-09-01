import SwiftWindowsCore

/// One List declaration and the physical node currently carrying it. A new
/// declaration retires escaped callbacks without retiring an action already
/// prepared for the same retained row. No application bindings live here.
@MainActor
package final class RetainedListNavigationOwner {
    @MainActor
    fileprivate final class StandaloneOrigin {
        weak var runtime: RetainedViewRuntime?
        let closeWitness: RetainedLazyListLogicalHostLifetime.CloseWitness

        init(runtime: RetainedViewRuntime) {
            self.runtime = runtime
            closeWitness = runtime.lazyListLogicalHostLifetime.captureNavigationCloseWitness()
        }
    }

    @MainActor
    fileprivate final class Attachment {
        weak var node: ViewNode?
        weak var runtime: RetainedViewRuntime?
        weak var currentAction: RetainedListNavigationReceipt?
        var hasMounted = false
        var hasPreparedAction = false
        var isRevoked = false
        let permitsStandaloneConstruction: Bool
        let standaloneOrigin: StandaloneOrigin?
        var actualAttachment: RetainedLazyListActualAttachment?

        init(permitsStandaloneConstruction: Bool, standaloneOrigin: StandaloneOrigin?) {
            self.permitsStandaloneConstruction = permitsStandaloneConstruction
            self.standaloneOrigin = standaloneOrigin
        }

        func hasSameOriginalHost(as other: Attachment) -> Bool {
            switch (standaloneOrigin, other.standaloneOrigin) {
            case (nil, nil): true
            case (.some(let lhs), .some(let rhs)): lhs.closeWitness === rhs.closeWitness
            default: false
            }
        }

        var canTransport: Bool {
            guard !isRevoked else { return false }
            guard let standaloneOrigin else { return true }
            guard standaloneOrigin.closeWitness.isOpen else { return false }
            return !hasMounted || actualAttachment?.hasCurrentStandaloneNavigationIdentity == true
        }
    }

    fileprivate let scope: RetainedListNavigationOwner?
    fileprivate var attachment: Attachment
    fileprivate var isCurrentDeclaration = true
    private var isAdopting = false

    package init(runtime: RetainedViewRuntime, standalone: Bool = false) {
        scope = nil
        attachment = Attachment(
            permitsStandaloneConstruction: runtime.presentationActionsAreAvailable,
            standaloneOrigin: standalone ? StandaloneOrigin(runtime: runtime) : nil)
    }

    private init(row: ViewNode, scope: RetainedListNavigationOwner) {
        self.scope = scope
        attachment = Attachment(
            permitsStandaloneConstruction: scope.attachment.permitsStandaloneConstruction,
            standaloneOrigin: scope.attachment.standaloneOrigin)
        install(on: row)
    }

    package func install(on node: ViewNode) {
        guard attachment.node == nil, isCurrentDeclaration else { return }
        attachment.node = node
        node.installListNavigationOwner(self)
    }

    package func makeRowOwner(on node: ViewNode) -> RetainedListNavigationOwner {
        RetainedListNavigationOwner(row: node, scope: self)
    }

    package func prepareAction(from source: RetainedListNavigationOwner) -> RetainedListNavigationReceipt? {
        RetainedListNavigationReceipt(scope: self, source: source)
    }

    /// The scope already holds its current action weakly. Layout borrows only
    /// that action's actual endpoints; it creates no row cache or new action
    /// authority. A replacement scope or a finished action yields no roots.
    func currentActionProtectedNodes(in runtime: RetainedViewRuntime) -> [ViewNode] {
        guard scope == nil, isCurrentDeclaration, !isAdopting,
            Self.currentNode(for: attachment, runtime: runtime) != nil
        else { return [] }
        return attachment.currentAction?.protectedNodes(in: runtime) ?? []
    }

    /// The departure prepass runs before any disappearing payload or callback.
    /// Temporary construction parents do not establish a mounted lifetime.
    func revokeForDeparture() {
        if !attachment.hasMounted, let origin = attachment.standaloneOrigin,
            let runtime = attachment.node?.retainedLazyListRuntime, origin.runtime !== runtime
        {
            // A failed foreign candidate can cancel an old construction
            // action, but has never owned this declaration's first mount.
            revokeCurrentActionForDeparture()
            return
        }
        if attachment.hasMounted || attachment.hasPreparedAction { revoke() }
    }

    func revokeForHostClose(in runtime: RetainedViewRuntime) {
        if let origin = attachment.standaloneOrigin, origin.runtime !== runtime { return }
        revoke()
    }

    func revokeForStandaloneAdapterReplacement() {
        if attachment.standaloneOrigin != nil { revoke() }
    }

    var standaloneRetirementRuntime: RetainedViewRuntime? {
        attachment.standaloneOrigin == nil ? nil : attachment.runtime
    }

    func retirementRuntimeWhenReplaced(
        on node: ViewNode, by incoming: RetainedListNavigationOwner?
    ) -> RetainedViewRuntime? {
        guard attachment.node === node, incoming?.attachment !== attachment else { return nil }
        return standaloneRetirementRuntime
    }

    func revokeIfReplaced(on node: ViewNode, by incoming: RetainedListNavigationOwner?) {
        guard attachment.standaloneOrigin != nil, attachment.node === node,
            incoming?.attachment !== attachment
        else { return }
        revoke()
    }

    func revoke() {
        isCurrentDeclaration = false
        attachment.isRevoked = true
        revokeCurrentActionForDeparture()
    }

    private func revokeCurrentActionForDeparture() {
        let actionScope = scope?.attachment ?? attachment
        actionScope.currentAction?.revokeForDeparture(of: attachment)
    }

    func revokeIfRoleIsUnavailable() {
        guard !isAdopting else { return }
        if scope != nil {
            if !hasRowRole { revoke() }
        } else if attachment.node?.scrollAxis != .vertical {
            revoke()
        }
    }

    func prepareForAdoption(of incoming: RetainedListNavigationOwner?) {
        guard incoming !== self else { return }
        isCurrentDeclaration = false
        if incoming == nil || (incoming?.scope == nil) != (scope == nil)
            || incoming?.isCurrentDeclaration != true || (scope != nil && incoming?.hasRowRole != true)
            || incoming?.attachment.hasSameOriginalHost(as: attachment) != true || !attachment.canTransport
        {
            attachment.isRevoked = true
            revokeCurrentActionForDeparture()
        }
    }

    func adopt(from previous: RetainedListNavigationOwner?, onto node: ViewNode, runtime: RetainedViewRuntime?) {
        guard isCurrentDeclaration else { return }
        isAdopting = true
        if let previous, (previous.scope == nil) == (scope == nil),
            previous.attachment.canTransport, previous.attachment.node === node,
            previous.attachment.hasSameOriginalHost(as: attachment)
        {
            // A receipt for the discarded fresh node cannot follow its
            // declaration onto a different physical node.
            attachment.isRevoked = true
            attachment = previous.attachment
        }
        if attachment.standaloneOrigin != nil, attachment.hasMounted, attachment.node !== node {
            revoke()
            return
        }
        attachment.node = node
        if let runtime { didAttach(to: runtime) }
    }

    func finishAdoption() {
        isAdopting = false
        revokeIfRoleIsUnavailable()
    }

    func didAttach(to runtime: RetainedViewRuntime) {
        guard isCurrentDeclaration, !attachment.isRevoked else { return }
        if let origin = attachment.standaloneOrigin {
            guard origin.closeWitness.isOpen else {
                revoke()
                return
            }
            guard origin.runtime === runtime else {
                if attachment.hasMounted { revoke() } else { revokeCurrentActionForDeparture() }
                return
            }
            guard let node = attachment.node, node.listNavigationOwner === self,
                node.isRetainedLazyListAttached(in: runtime)
            else { return }
            // Repeated registration during in-place child publication must
            // neither refresh a stale proof nor retire an unchanged one.
            if attachment.hasMounted { return }
            let actual = node.lazyListActivityStorage().captureActualAttachment(of: node, in: runtime)
            guard actual.isAttached else { return }
            attachment.actualAttachment = actual
        }
        if attachment.hasMounted, attachment.runtime !== runtime {
            revoke()
            return
        }
        attachment.runtime = runtime
        attachment.hasMounted = true
    }

    /// Called beside native membership/owner publication, never by a getter.
    /// Managed/default owners keep their existing attachment path unchanged.
    func didPublishStandaloneAttachment(to runtime: RetainedViewRuntime) {
        if attachment.standaloneOrigin != nil { didAttach(to: runtime) }
    }

    fileprivate var hasRowRole: Bool {
        guard let node = attachment.node else { return false }
        return node.isFocusable && node.isFocusEnabled && node.interceptsVerticalArrowKeys
            && node.accessibilityTraits.contains(.isSelectable)
    }

    fileprivate static func currentNode(
        for attachment: Attachment, runtime: RetainedViewRuntime?, scope: Attachment? = nil
    ) -> ViewNode? {
        guard !attachment.isRevoked, let node = attachment.node,
            let owner = node.listNavigationOwner, owner.isCurrentDeclaration,
            !owner.isAdopting,
            owner.attachment === attachment, node.hasListNavigationRuntime(runtime)
        else { return nil }
        if let origin = attachment.standaloneOrigin {
            guard origin.closeWitness.isOpen else { return nil }
            if let runtime {
                guard origin.runtime === runtime, attachment.hasMounted,
                    attachment.actualAttachment?.isAttached == true
                else { return nil }
            } else {
                guard hasNoRuntimeInAncestry(node) else { return nil }
                if attachment.hasMounted {
                    guard origin.runtime == nil,
                        attachment.actualAttachment?.hasCurrentStandaloneNavigationIdentity == true
                    else { return nil }
                } else {
                    guard attachment.permitsStandaloneConstruction,
                        origin.runtime?.presentationActionsAreAvailable != false
                    else { return nil }
                }
            }
        }
        if let scope {
            guard owner.scope?.attachment === scope, owner.hasRowRole,
                let scopeNode = scope.node, contains(node, in: scopeNode)
            else { return nil }
            if attachment.standaloneOrigin != nil,
                !hasCurrentStandaloneAdapters(from: node, through: scopeNode)
            {
                return nil
            }
        } else {
            guard owner.scope == nil, node.scrollAxis == .vertical else { return nil }
        }
        return node
    }

    private static func hasNoRuntimeInAncestry(_ node: ViewNode) -> Bool {
        var current = node
        var depth = 0
        while depth < ViewNode.maximumTraversalDepth {
            guard current.hasListNavigationRuntime(nil) else { return false }
            guard let parent = current.parent else { return true }
            guard parent.children.contains(where: { $0 === current }) else { return false }
            current = parent
            depth += 1
        }
        return false
    }

    private static func hasCurrentStandaloneAdapters(from node: ViewNode, through scope: ViewNode) -> Bool {
        var current = node
        var depth = 0
        while depth < ViewNode.maximumTraversalDepth {
            guard current.retainedLazyListAdapter?.permitsStandaloneNavigation != false else { return false }
            if current === scope { return true }
            guard let parent = current.parent, parent.children.contains(where: { $0 === current }) else { return false }
            current = parent
            depth += 1
        }
        return false
    }

    fileprivate static func contains(_ node: ViewNode, in ancestor: ViewNode) -> Bool {
        var candidate: ViewNode? = node
        var depth = 0
        while let current = candidate, depth < ViewNode.maximumTraversalDepth {
            guard !current.isHidden, !current.isRemovalOverlay else { return false }
            if current === ancestor { return true }
            candidate = current.parent
            depth += 1
        }
        return false
    }

    fileprivate static func topmostAncestor(of node: ViewNode) -> ViewNode? {
        var current = node
        var depth = 0
        while let parent = current.parent, depth < ViewNode.maximumTraversalDepth {
            current = parent
            depth += 1
        }
        return current.parent == nil ? current : nil
    }
}

/// A single action's source and destination, captured before its binding write.
/// It never resolves a tag again or takes a new declaration's binding. All
/// references back to the tree/runtime stay weak, including deferred reveal.
package enum RetainedListNavigationReadiness {
    case ready
    case pending
    case obsolete
}

@MainActor
package final class RetainedListNavigationReceipt {
    private enum Phase {
        case prepared
        case preparingLayout
        case revealingBeforeFocus
        case awaitingRevealLayout
        case focusing
        case focused
        case finished
    }

    private let scopeDeclaration: RetainedListNavigationOwner
    private let sourceDeclaration: RetainedListNavigationOwner
    private let scope: RetainedListNavigationOwner.Attachment
    private let source: RetainedListNavigationOwner.Attachment
    private var target: RetainedListNavigationOwner.Attachment?
    private var targetRequiresRevealBeforeFocus = false
    private weak var runtime: RetainedViewRuntime?
    private weak var root: ViewNode?
    private let hasRuntime: Bool
    private let originalFocus: ObjectIdentifier?
    private let originalModal: ObjectIdentifier?
    private let originalFocusRevision: UInt64?
    private var revealFocusRevision: UInt64?
    private var preparedLayoutSettlement: RetainedLayoutSettlementReceipt?
    private var terminalRevealSettlement: RetainedLayoutSettlementReceipt?
    private weak var revealContinuation: RetainedListNavigationRevealContinuation?
    private var hasAcceptedRevealContinuation = false
    private var isRevealCancelled = false
    private var phase = Phase.prepared
    private(set) var geometryRevision: UInt64?

    fileprivate init?(scope: RetainedListNavigationOwner, source: RetainedListNavigationOwner) {
        guard scope.scope == nil, source.scope === scope,
            scope.isCurrentDeclaration, source.isCurrentDeclaration
        else { return nil }
        let scopeAttachment = scope.attachment
        let sourceAttachment = source.attachment
        let runtime = scopeAttachment.runtime
        guard sourceAttachment.runtime === runtime,
            let scopeNode = RetainedListNavigationOwner.currentNode(for: scopeAttachment, runtime: runtime),
            RetainedListNavigationOwner.currentNode(
                for: sourceAttachment, runtime: runtime, scope: scopeAttachment) != nil,
            let root = runtime?.root ?? RetainedListNavigationOwner.topmostAncestor(of: scopeNode),
            RetainedListNavigationOwner.contains(scopeNode, in: root)
        else { return nil }
        if let runtime {
            guard runtime.presentationActionsAreAvailable,
                runtime.presentationFocusRevision != UInt64.max,
                runtime.presentationModalSnapshot.map({ RetainedListNavigationOwner.contains(scopeNode, in: $0) })
                    ?? true
            else { return nil }
        } else {
            guard scopeAttachment.hasMounted || scopeAttachment.permitsStandaloneConstruction,
                sourceAttachment.hasMounted || sourceAttachment.permitsStandaloneConstruction
            else { return nil }
        }
        scopeDeclaration = scope
        sourceDeclaration = source
        self.scope = scopeAttachment
        self.source = sourceAttachment
        self.runtime = runtime
        self.root = root
        hasRuntime = runtime != nil
        originalFocus = runtime?.focusedNode.map(ObjectIdentifier.init)
        originalModal = runtime?.presentationModalSnapshot.map(ObjectIdentifier.init)
        originalFocusRevision = runtime?.presentationFocusRevision
        scopeAttachment.hasPreparedAction = true
        sourceAttachment.hasPreparedAction = true
        scopeAttachment.currentAction = self
        // This new action owns the stable scope slot before old callback
        // captures can retire and synchronously reenter another action.
        runtime?.cancelPreparedListNavigationReplay(owner: scopeAttachment)
        guard permitsBindingWrite else { return nil }
        runtime?.didPrepareListNavigationAction(self)
        guard permitsBindingWrite else { return nil }
    }

    /// Getters (and Hashable operations) may replace a declaration. Until the
    /// destination has been prepared, that cancels before entering its setter.
    package var permitsBindingWrite: Bool {
        phase == .prepared && scopeDeclaration.isCurrentDeclaration
            && sourceDeclaration.isCurrentDeclaration && permitsContinuation
    }

    package func prepareTarget(
        _ owner: RetainedListNavigationOwner, requiresRevealBeforeFocus: Bool = false
    ) -> Bool {
        guard permitsBindingWrite, owner.isCurrentDeclaration, owner.scope === scopeDeclaration,
            RetainedListNavigationOwner.currentNode(for: owner.attachment, runtime: runtime, scope: scope) != nil
        else { return false }
        owner.attachment.hasPreparedAction = true
        target = owner.attachment
        targetRequiresRevealBeforeFocus = requiresRevealBeforeFocus
        return true
    }

    /// A synchronous setter/invalidation may adopt new declarations onto the
    /// same physical nodes. It may not replace, detach, reparent, or disable
    /// either endpoint, replace the List, or admit a newer focus intent.
    package var permitsContinuation: Bool {
        guard !isRevealCancelled, phase != .finished, hasCurrentNodes else { return false }
        guard hasRuntime else { return true }
        guard let runtime, runtime.permitsRetainedActionInvocation,
            runtime.presentationFocusRevision == originalFocusRevision,
            runtime.presentationFocusRevision != UInt64.max,
            runtime.focusedNode.map(ObjectIdentifier.init) == originalFocus,
            runtime.presentationModalSnapshot.map(ObjectIdentifier.init) == originalModal
        else { return false }
        return true
    }

    /// A public lazy List may already have accepted its one binding write,
    /// while that write's bounded row rebuild still needs another layout.
    /// Keep the prepared phase and original weak endpoints until real geometry
    /// settles; this never resolves the selection again or repeats its setter.
    package func settlePreparedTarget() -> RetainedListNavigationReadiness {
        guard phase == .prepared, permitsContinuation, let node = target?.node else { return .obsolete }
        guard hasRuntime else { return .ready }
        guard let runtime else { return .obsolete }
        return runtime.settlePreparedListNavigationTarget(node, receipt: self)
    }

    /// Cancellation before finishNavigation ends only this preparation's
    /// physical protection. It does not undo an accepted focus or animation.
    package func cancelPreparedNavigation() {
        guard phase == .prepared else { return }
        phase = .finished
        cancelReveal()
        if scope.currentAction === self { runtime?.cancelPreparedListNavigationReplay(owner: scope) }
    }

    /// One stable native scope slot owns the callback strongly while a public
    /// controller waits. The callback may retain its request/controller, whose
    /// runtime and nodes are weak. Nothing is stored back on this attachment.
    /// A terminal slot cancellation notifies the exact request after native
    /// revocation; moving this receipt between the two queues does not cancel it.
    @discardableResult
    package func schedulePreparedNavigationReplay(
        afterLayout: Bool, perform action: @escaping @MainActor () -> Void,
        onCancel: @escaping @MainActor () -> Void
    ) -> Bool {
        guard permitsPreparedNavigationReplay, let runtime else { return false }
        runtime.schedulePreparedListNavigationReplay(
            owner: scope, receipt: self, afterLayout: afterLayout, perform: action, onCancel: onCancel)
        // Registration may deliver immediately when already idle. Completion
        // or supersession after that is not permission to repeat the action.
        return true
    }

    var permitsPreparedNavigationReplay: Bool { phase == .prepared && permitsContinuation }

    fileprivate func revokeForDeparture(of attachment: RetainedListNavigationOwner.Attachment) {
        guard scope.currentAction === self,
            attachment === scope || attachment === source || attachment === target
        else { return }
        phase = .finished
        cancelReveal()
        runtime?.cancelPreparedListNavigationReplay(owner: scope)
    }

    private var hasCurrentNodes: Bool {
        guard scope.currentAction === self, let root, !hasRuntime || runtime != nil,
            !hasRuntime || runtime?.root === root,
            let scopeNode = RetainedListNavigationOwner.currentNode(for: scope, runtime: runtime),
            RetainedListNavigationOwner.contains(scopeNode, in: root),
            RetainedListNavigationOwner.currentNode(for: source, runtime: runtime, scope: scope) != nil
        else { return false }
        if let target {
            return RetainedListNavigationOwner.currentNode(for: target, runtime: runtime, scope: scope) != nil
        }
        return true
    }

    /// Viewport retention is a finite obligation of the already prepared
    /// action. It may keep its source even when the handler was invoked without
    /// focus, but cannot revive a detached, disabled, or replaced endpoint.
    fileprivate func protectedNodes(in runtime: RetainedViewRuntime) -> [ViewNode] {
        guard hasRuntime, self.runtime === runtime, !isRevealCancelled, phase != .finished,
            hasCurrentNodes, runtime.permitsRetainedActionInvocation,
            runtime.presentationModalSnapshot.map(ObjectIdentifier.init) == originalModal
        else { return [] }
        switch phase {
        case .focused:
            guard let targetNode = target?.node, let revealFocusRevision,
                revealFocusRevision != UInt64.max,
                runtime.presentationFocusRevision == revealFocusRevision,
                runtime.focusedNode === targetNode, targetNode.isFocused
            else { return [] }
        case .focusing:
            // The focus mutation can query layout between publishing its
            // revision and publishing the focused node. This synchronous
            // action still owns both current attachments until it unwinds.
            break
        case .prepared, .preparingLayout, .revealingBeforeFocus:
            guard permitsContinuation else { return [] }
        case .awaitingRevealLayout:
            guard let revealContinuation, permitsContinuation,
                runtime.isListNavigationRevealCurrent(revealContinuation)
            else { return [] }
        case .finished:
            return []
        }
        return [source.node, target?.node].compactMap { $0 }
    }

    /// False may follow an accepted selection or scroll. It is not permission
    /// to repeat the binding write, retry this receipt, or undo a newer action.
    @discardableResult
    package func finishNavigation() -> Bool {
        guard phase == .prepared else { return false }
        phase = .preparingLayout
        defer {
            if phase != .focused && phase != .awaitingRevealLayout { phase = .finished }
        }
        guard permitsContinuation, let targetNode = target?.node else { return false }
        guard hasRuntime else {
            // Preserve already-placed standalone trees after their weak
            // runtime expires; this path does not invent a focus authority.
            return targetNode.scrollIntoView()
        }
        guard let runtime, let revision = originalFocusRevision else { return false }
        // One exact-target query accepts normal setter rebuilds and refreshes
        // modal admission. Refusal never searches for another row or retries.
        guard runtime.prepareListNavigationTarget(targetNode, receipt: self), permitsContinuation else { return false }
        let (nextRevision, overflow) = revision.addingReportingOverflow(1)
        // At max the private checked focus authority may already be exhausted
        // without its numeric value changing again. Equality is not proof.
        guard !overflow, nextRevision != UInt64.max else { return false }

        // A logical destination can be physically laid out by the time the
        // selection setter runs while still lying outside the viewport. Keep
        // that provenance separate from actual layout-deferred state.
        let needsRealization = targetRequiresRevealBeforeFocus || runtime.isListNavigationTargetDeferred(targetNode)
        if needsRealization {
            phase = .revealingBeforeFocus
            guard runtime.revealListNavigationTarget(targetNode, receipt: self),
                let revealContinuation,
                runtime.armListNavigationReveal(revealContinuation, target: targetNode, receipt: self)
            else {
                cancelReveal()
                return false
            }
            // The initial scroll is accepted exactly once. The native slot
            // owns only this receipt while its viewport or authored tween
            // settles; the public binding/controller need not remain alive.
            phase = .awaitingRevealLayout
            return runtime.completeListNavigationRevealIfReady(revealContinuation, queryingLayout: true)
        }

        phase = .focusing
        guard runtime.requestListNavigationFocus(targetNode, receipt: self) else { return false }
        revealFocusRevision = nextRevision
        phase = .focused
        guard permitsReveal(in: runtime, target: targetNode) else { return false }
        if runtime.revealListNavigationTarget(targetNode, receipt: self) {
            return permitsReveal(in: runtime, target: targetNode)
        }
        if permitsReveal(in: runtime, target: targetNode) {
            let key = "list.selection.\(ObjectIdentifier(scope))"
            runtime.scheduleListNavigationReveal(key: key, target: targetNode, receipt: self)
        }
        return false
    }

    var canRegisterRevealContinuation: Bool {
        phase == .revealingBeforeFocus && !hasAcceptedRevealContinuation && permitsContinuation
    }

    var hasNativeRevealContinuation: Bool { hasAcceptedRevealContinuation }

    func registerRevealContinuation(_ continuation: RetainedListNavigationRevealContinuation) -> Bool {
        guard canRegisterRevealContinuation, continuation.receipt === self else { return false }
        hasAcceptedRevealContinuation = true
        revealContinuation = continuation
        return true
    }

    func ownsRevealContinuation(_ continuation: RetainedListNavigationRevealContinuation) -> Bool {
        hasAcceptedRevealContinuation && revealContinuation === continuation && continuation.receipt === self
    }

    func permitsPendingRevealContinuation(_ continuation: RetainedListNavigationRevealContinuation) -> Bool {
        phase == .awaitingRevealLayout && ownsRevealContinuation(continuation) && permitsContinuation
    }

    /// Consume a fresh terminal geometry proof for the original action. No
    /// selection getter/setter, scroll attempt, or layout query occurs here.
    func finishPendingRevealFocus(
        _ continuation: RetainedListNavigationRevealContinuation, target node: ViewNode,
        in runtime: RetainedViewRuntime, settlement: RetainedLayoutSettlementReceipt
    ) -> Bool {
        guard permitsPendingRevealContinuation(continuation), continuation.state == .consuming,
            target?.node === node, self.runtime === runtime,
            runtime.isListNavigationRevealCurrent(continuation),
            runtime.isLayoutSettlementReceiptCurrent(settlement),
            !runtime.isListNavigationTargetDeferred(node), let revision = originalFocusRevision
        else { return false }
        let (nextRevision, overflow) = revision.addingReportingOverflow(1)
        guard !overflow, nextRevision != UInt64.max else { return false }
        terminalRevealSettlement = settlement
        phase = .focusing
        defer {
            terminalRevealSettlement = nil
            if phase != .focused { phase = .finished }
        }
        guard runtime.requestListNavigationFocus(node, receipt: self) else { return false }
        revealFocusRevision = nextRevision
        phase = .focused
        return permitsReveal(in: runtime, target: node)
    }

    /// List ownership is an additional condition on ordinary focus, not UIA
    /// authority. Geometry cancellation may stop the later reveal while an
    /// already admitted ordinary focus transition finishes normally.
    func permitsFocusOwnership(in runtime: RetainedViewRuntime, target node: ViewNode) -> Bool {
        phase == .focusing && hasRuntime && self.runtime === runtime && target?.node === node
            && hasCurrentNodes && runtime.permitsRetainedActionInvocation
            && runtime.presentationModalSnapshot.map(ObjectIdentifier.init) == originalModal
            && (!hasAcceptedRevealContinuation
                || (!isRevealCancelled && revealContinuation?.state == .consuming
                    && revealContinuation.map(runtime.isListNavigationRevealFocusCurrent) == true))
    }

    func permitsFocusEntry(in runtime: RetainedViewRuntime, target node: ViewNode) -> Bool {
        guard permitsContinuation, permitsFocusOwnership(in: runtime, target: node),
            runtime.isListNavigationGeometryCurrent(self)
        else { return false }
        if hasAcceptedRevealContinuation {
            guard let terminalRevealSettlement else { return false }
            return runtime.isLayoutSettlementReceiptCurrent(terminalRevealSettlement)
        }
        return true
    }

    /// Stored-only validation used inside the scroll path after its clock and
    /// pointer-cancellation callbacks. It never queries layout or user code.
    func permitsReveal(in runtime: RetainedViewRuntime, target node: ViewNode) -> Bool {
        guard !isRevealCancelled, hasRuntime, self.runtime === runtime, target?.node === node, hasCurrentNodes,
            runtime.isListNavigationGeometryCurrent(self), runtime.permitsRetainedActionInvocation,
            runtime.presentationModalSnapshot.map(ObjectIdentifier.init) == originalModal
        else { return false }
        if phase == .revealingBeforeFocus { return permitsContinuation }
        return phase == .focused && revealFocusRevision != nil && revealFocusRevision != UInt64.max
            && runtime.presentationFocusRevision == revealFocusRevision
            && runtime.focusedNode === node && node.isFocused
    }

    /// A layout-only query can settle geometry while retaining render dirty
    /// flags. Only the original preparation proof may admit a deferred row's
    /// pre-focus reveal through that pending-layout state.
    func permitsPreparedLayoutReveal(in runtime: RetainedViewRuntime, target node: ViewNode) -> Bool {
        guard phase == .revealingBeforeFocus, let preparedLayoutSettlement,
            permitsReveal(in: runtime, target: node)
        else { return false }
        return runtime.isLayoutSettlementReceiptCurrent(preparedLayoutSettlement)
    }

    func recordPreparedLayoutSettlement(_ settlement: RetainedLayoutSettlementReceipt) -> Bool {
        guard phase == .preparingLayout else { return false }
        if case .some = preparedLayoutSettlement { return false }
        preparedLayoutSettlement = settlement
        return true
    }

    func consumePreparedLayoutSettlement() {
        preparedLayoutSettlement = nil
    }

    func cancelReveal() {
        isRevealCancelled = true
        revealFocusRevision = nil
        preparedLayoutSettlement = nil
        terminalRevealSettlement = nil
        if let revealContinuation { runtime?.cancelListNavigationReveal(revealContinuation) }
    }

    func recordGeometryRevision(_ revision: UInt64) {
        geometryRevision = revision
    }
}
