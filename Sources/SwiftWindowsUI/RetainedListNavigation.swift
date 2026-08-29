import SwiftWindowsCore

/// One List declaration and the physical node currently carrying it. A new
/// declaration retires escaped callbacks without retiring an action already
/// prepared for the same retained row. No application bindings live here.
@MainActor
package final class RetainedListNavigationOwner {
    @MainActor
    fileprivate final class Attachment {
        weak var node: ViewNode?
        weak var runtime: RetainedViewRuntime?
        weak var currentAction: RetainedListNavigationReceipt?
        var hasMounted = false
        var hasPreparedAction = false
        var isRevoked = false
        let permitsStandaloneConstruction: Bool

        init(permitsStandaloneConstruction: Bool) {
            self.permitsStandaloneConstruction = permitsStandaloneConstruction
        }
    }

    fileprivate let scope: RetainedListNavigationOwner?
    fileprivate var attachment: Attachment
    fileprivate var isCurrentDeclaration = true
    private var isAdopting = false

    package init(runtime: RetainedViewRuntime) {
        scope = nil
        attachment = Attachment(permitsStandaloneConstruction: runtime.presentationActionsAreAvailable)
    }

    private init(row: ViewNode, scope: RetainedListNavigationOwner) {
        self.scope = scope
        attachment = Attachment(permitsStandaloneConstruction: scope.attachment.permitsStandaloneConstruction)
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

    /// The departure prepass runs before any disappearing payload or callback.
    /// Temporary construction parents do not establish a mounted lifetime.
    func revokeForDeparture() {
        if attachment.hasMounted || attachment.hasPreparedAction { revoke() }
    }

    func revoke() {
        isCurrentDeclaration = false
        attachment.isRevoked = true
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
        {
            attachment.isRevoked = true
        }
    }

    func adopt(from previous: RetainedListNavigationOwner?, onto node: ViewNode, runtime: RetainedViewRuntime?) {
        guard isCurrentDeclaration else { return }
        isAdopting = true
        if let previous, (previous.scope == nil) == (scope == nil),
            !previous.attachment.isRevoked, previous.attachment.node === node
        {
            // A receipt for the discarded fresh node cannot follow its
            // declaration onto a different physical node.
            attachment.isRevoked = true
            attachment = previous.attachment
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
        if attachment.hasMounted, attachment.runtime !== runtime {
            revoke()
            return
        }
        attachment.runtime = runtime
        attachment.hasMounted = true
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
        if let scope {
            guard owner.scope?.attachment === scope, owner.hasRowRole,
                let scopeNode = scope.node, contains(node, in: scopeNode)
            else { return nil }
        } else {
            guard owner.scope == nil, node.scrollAxis == .vertical else { return nil }
        }
        return node
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
@MainActor
package final class RetainedListNavigationReceipt {
    private enum Phase {
        case prepared
        case preparingLayout
        case revealingBeforeFocus
        case focusing
        case focused
        case finished
    }

    private let scopeDeclaration: RetainedListNavigationOwner
    private let sourceDeclaration: RetainedListNavigationOwner
    private let scope: RetainedListNavigationOwner.Attachment
    private let source: RetainedListNavigationOwner.Attachment
    private var target: RetainedListNavigationOwner.Attachment?
    private weak var runtime: RetainedViewRuntime?
    private weak var root: ViewNode?
    private let hasRuntime: Bool
    private let originalFocus: ObjectIdentifier?
    private let originalModal: ObjectIdentifier?
    private let originalFocusRevision: UInt64?
    private var revealFocusRevision: UInt64?
    private var preparedLayoutSettlement: RetainedLayoutSettlementReceipt?
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
    }

    /// Getters (and Hashable operations) may replace a declaration. Until the
    /// destination has been prepared, that cancels before entering its setter.
    package var permitsBindingWrite: Bool {
        phase == .prepared && scopeDeclaration.isCurrentDeclaration
            && sourceDeclaration.isCurrentDeclaration && permitsContinuation
    }

    package func prepareTarget(_ owner: RetainedListNavigationOwner) -> Bool {
        guard permitsBindingWrite, owner.isCurrentDeclaration, owner.scope === scopeDeclaration,
            RetainedListNavigationOwner.currentNode(for: owner.attachment, runtime: runtime, scope: scope) != nil
        else { return false }
        owner.attachment.hasPreparedAction = true
        target = owner.attachment
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

    /// False may follow an accepted selection or scroll. It is not permission
    /// to repeat the binding write, retry this receipt, or undo a newer action.
    @discardableResult
    package func finishNavigation() -> Bool {
        guard phase == .prepared else { return false }
        phase = .preparingLayout
        defer {
            if phase != .focused { phase = .finished }
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

        let needsRealization = runtime.isListNavigationTargetDeferred(targetNode)
        if needsRealization {
            phase = .revealingBeforeFocus
            guard runtime.revealListNavigationTarget(targetNode, receipt: self),
                runtime.settleRevealedListNavigationTarget(targetNode, receipt: self)
            else {
                // An accepted animated scroll can still leave this row
                // deferred. Keep that scroll intent, but do not manufacture
                // focus eligibility or enqueue an unbounded focus retry.
                cancelReveal()
                return false
            }
        }

        phase = .focusing
        guard runtime.requestListNavigationFocus(targetNode, receipt: self) else { return false }
        revealFocusRevision = nextRevision
        phase = .focused
        guard permitsReveal(in: runtime, target: targetNode) else { return false }
        if needsRealization { return true }
        if runtime.revealListNavigationTarget(targetNode, receipt: self) {
            return permitsReveal(in: runtime, target: targetNode)
        }
        if permitsReveal(in: runtime, target: targetNode) {
            let key = "list.selection.\(ObjectIdentifier(scope))"
            runtime.scheduleListNavigationReveal(key: key, target: targetNode, receipt: self)
        }
        return false
    }

    /// List ownership is an additional condition on ordinary focus, not UIA
    /// authority. Geometry cancellation may stop the later reveal while an
    /// already admitted ordinary focus transition finishes normally.
    func permitsFocusOwnership(in runtime: RetainedViewRuntime, target node: ViewNode) -> Bool {
        phase == .focusing && hasRuntime && self.runtime === runtime && target?.node === node
            && hasCurrentNodes && runtime.permitsRetainedActionInvocation
            && runtime.presentationModalSnapshot.map(ObjectIdentifier.init) == originalModal
    }

    func permitsFocusEntry(in runtime: RetainedViewRuntime, target node: ViewNode) -> Bool {
        permitsContinuation && permitsFocusOwnership(in: runtime, target: node)
            && runtime.isListNavigationGeometryCurrent(self)
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
    }

    func recordGeometryRevision(_ revision: UInt64) {
        geometryRevision = revision
    }
}
