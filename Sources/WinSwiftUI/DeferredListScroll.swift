import SwiftWindowsCore
import SwiftWindowsUI

/// Only the logical ID table belongs here. Keeping the projection or a row
/// closure in this payload would make a pending scroll retain every row View.
@MainActor
final class DeferredListScrollSource {
    struct Row {
        let implicitID: AnyHashable?
        let providerKey: RetainedViewIdentity.Key
    }

    private enum Marker {}

    private let rows: [Row]
    private let indices: ManagedKeyedMap<RetainedViewIdentity.Key, Int>

    private init(rows: [Row], indices: ManagedKeyedMap<RetainedViewIdentity.Key, Int>) {
        self.rows = rows
        self.indices = indices
    }

    var rowCount: Int { rows.count }

    func row(at index: Int) -> Row? {
        rows.indices.contains(index) ? rows[index] : nil
    }

    /// The caller owns the original source/attachment receipt. Every authored
    /// hash or equality must return through that receipt before another key.
    func index(for target: AnyHashable, isCurrent: () -> Bool) -> Int? {
        let result = indices.value(for: RetainedViewIdentity.Key(target), isCurrent: isCurrent)
        return isCurrent() ? result : nil
    }

    static func attached(to node: ViewNode) -> DeferredListScrollSource? {
        node.retainedPreferenceValues[ObjectIdentifier(Marker.self)] as? DeferredListScrollSource
    }

    @discardableResult
    static func install(
        on node: ViewNode,
        rows suppliedRows: [(implicitID: AnyHashable?, providerKey: RetainedViewIdentity.Key)],
        isCurrent: () -> Bool
    ) -> Bool {
        guard isCurrent() else { return false }
        let rows = suppliedRows.map { Row(implicitID: $0.implicitID, providerKey: $0.providerKey) }
        var indices: ManagedKeyedMap<RetainedViewIdentity.Key, Int> = [:]
        for (index, row) in rows.enumerated() {
            guard isCurrent() else { return false }
            guard let identifier = row.implicitID else { continue }
            let key = RetainedViewIdentity.Key(identifier)
            let previous = indices.value(for: key, isCurrent: isCurrent)
            guard isCurrent() else { return false }
            // Duplicate data IDs retain their first logical occurrence, just
            // as the ordinary reader's preorder traversal does.
            if previous == nil {
                guard indices.setValue(index, for: key, isCurrent: isCurrent), isCurrent() else { return false }
            }
        }
        guard isCurrent() else { return false }
        let source = DeferredListScrollSource(rows: rows, indices: indices)
        node.retainedPreferenceValues[ObjectIdentifier(Marker.self)] = source
        return isCurrent() && attached(to: node) === source
    }
}

/// Neither a weak node nor its textual tag proves an attachment. The logical
/// witness adds the runtime's native source and physical attachment checks.
@MainActor
final class DeferredListScrollAttachment {
    weak var node: ViewNode?
    weak var source: DeferredListScrollSource?
    let treeOrder: Int
    private var witness: RetainedLazyListScrollSearchCursor?

    init(node: ViewNode, source: DeferredListScrollSource, treeOrder: Int) {
        self.node = node
        self.source = source
        self.treeOrder = treeOrder
    }

    func isCurrent(in runtime: RetainedViewRuntime, root: ViewNode, readerIdentifier: String) -> Bool {
        guard runtime.permitsRetainedActionInvocation, let node, let source,
            DeferredListScrollSource.attached(to: node) === source,
            retainedScrollReaderContains(node, root: root, readerIdentifier: readerIdentifier)
        else { return false }
        return witness.map { runtime.isLazyListScrollSourceCurrent($0, in: node) } ?? true
    }

    func captureWitness(in runtime: RetainedViewRuntime) -> Bool {
        guard let node else { return false }
        if let witness { return runtime.isLazyListScrollSourceCurrent(witness, in: node) }
        // A source receipt also exists for an empty List, and it remains valid
        // during the adapter's probe preparation. Item/action membership
        // intentionally denies queries during that scope and is not a source
        // receipt for an earlier exhausted List's absence proof.
        guard let witness = runtime.captureLazyListScrollSource(in: node) else { return false }
        self.witness = witness
        return true
    }
}

@MainActor
struct RetainedScrollTargetSnapshot {
    let explicit: ViewNode?
    let implicit: ViewNode?
    let implicitTreeOrder: Int?
    let lists: [DeferredListScrollAttachment]
}

@MainActor
func retainedScrollReaderContains(_ node: ViewNode, root: ViewNode, readerIdentifier: String) -> Bool {
    var current: ViewNode? = node
    var visited: Set<ObjectIdentifier> = []
    while let candidate = current, visited.insert(ObjectIdentifier(candidate)).inserted {
        guard !candidate.isHidden,
            candidate.scrollReaderID == nil || candidate.scrollReaderID == readerIdentifier
        else { return false }
        if candidate === root { return true }
        guard let parent = candidate.parent, parent.children.contains(where: { $0 === candidate }) else {
            return false
        }
        current = parent
    }
    return false
}

/// The same typed matcher serves mounted targets and doomed probe candidates.
/// It never calls row actions and never crosses another reader's boundary.
@MainActor
func retainedScrollTargetSnapshot(
    for target: RetainedViewIdentity.Key, in roots: [ViewNode], readerIdentifier: String,
    includeImplicit: Bool = true, collectLists: Bool = true, isCurrent: () -> Bool
) -> RetainedScrollTargetSnapshot? {
    var pendingNodes = Array(roots.reversed())
    var visited: Set<ObjectIdentifier> = []
    var implicit: ViewNode?
    var implicitOrder: Int?
    var lists: [DeferredListScrollAttachment] = []
    var treeOrder = 0
    let explicitKey = ObjectIdentifier(ExplicitScrollTargetIdentityMarker.self)
    let implicitKey = ObjectIdentifier(ImplicitScrollTargetIdentityMarker.self)
    while let node = pendingNodes.popLast() {
        guard isCurrent() else { return nil }
        guard visited.insert(ObjectIdentifier(node)).inserted, !node.isHidden,
            node.scrollReaderID == nil || node.scrollReaderID == readerIdentifier
        else { continue }
        treeOrder += 1
        if let identity = node.retainedPreferenceValues[explicitKey] as? RetainedScrollTargetIdentity {
            func identityIsCurrent() -> Bool {
                isCurrent()
                    && (node.retainedPreferenceValues[explicitKey] as? RetainedScrollTargetIdentity)?.generation
                        === identity.generation
            }
            guard let equal = identity.identifier.checkedEquals(target, isCurrent: identityIsCurrent),
                identityIsCurrent()
            else {
                return nil
            }
            if equal {
                return RetainedScrollTargetSnapshot(
                    explicit: node, implicit: implicit, implicitTreeOrder: implicitOrder, lists: lists)
            }
        }
        if includeImplicit, implicit == nil,
            let identity = node.retainedPreferenceValues[implicitKey] as? RetainedScrollTargetIdentity
        {
            func identityIsCurrent() -> Bool {
                isCurrent()
                    && (node.retainedPreferenceValues[implicitKey] as? RetainedScrollTargetIdentity)?.generation
                        === identity.generation
            }
            guard let equal = identity.identifier.checkedEquals(target, isCurrent: identityIsCurrent),
                identityIsCurrent()
            else {
                return nil
            }
            if equal {
                implicit = node
                implicitOrder = treeOrder
            }
        }
        if collectLists, let source = DeferredListScrollSource.attached(to: node) {
            lists.append(DeferredListScrollAttachment(node: node, source: source, treeOrder: treeOrder))
        }
        pendingNodes.append(contentsOf: node.children.reversed())
    }
    guard isCurrent() else { return nil }
    return RetainedScrollTargetSnapshot(
        explicit: nil, implicit: implicit, implicitTreeOrder: implicitOrder, lists: lists)
}

/// One cancellable public request. A search cursor keeps only native tokens
/// and receipts; speculative factories are always abandoned by Runtime before
/// this object can retain a result. An explicit ID anywhere in the reader wins
/// over a logical data key, so an opaque search can require O(data) total work.
/// Each slice shares Runtime's viewport construction budget and yields through
/// the existing reader after-layout callback; there is no separate scheduler.
@MainActor
final class DeferredListScrollResolution {
    enum Result: Equatable {
        case complete
        case pending
        case obsolete
        case unsupported
    }

    private struct LogicalCandidate {
        let attachment: DeferredListScrollAttachment
        let providerKey: RetainedViewIdentity.Key
    }

    private let target: AnyHashable
    private let targetKey: RetainedViewIdentity.Key
    private let readerIdentifier: String
    private let lists: [DeferredListScrollAttachment]
    private weak var implicitNode: ViewNode?
    private let implicitTreeOrder: Int?
    private var logicalCandidate: LogicalCandidate?
    private var resolvedLogicalCandidate = false
    private var searchIndex = 0
    private var searchCursor: RetainedLazyListScrollSearchCursor?
    private var selectedItem: RetainedLazyListAccessibilityItem?
    private var selectedIsExplicit = false
    private var hasUnsearchedNestedSource = false
    private var wasInvalidatedDuringMatch = false
    private var isCancelled = false

    init(target: AnyHashable, readerIdentifier: String, snapshot: RetainedScrollTargetSnapshot) {
        self.target = target
        self.targetKey = RetainedViewIdentity.Key(target)
        self.readerIdentifier = readerIdentifier
        self.lists = snapshot.lists
        self.implicitNode = snapshot.implicit
        self.implicitTreeOrder = snapshot.implicitTreeOrder
    }

    func cancel(in runtime: RetainedViewRuntime?) {
        isCancelled = true
        let item = selectedItem
        selectedItem = nil
        searchCursor = nil
        logicalCandidate = nil
        if let item { runtime?.releaseLazyListTarget(item) }
    }

    func resolve(
        in runtime: RetainedViewRuntime, root: ViewNode, anchor: UnitPoint?, transaction: Transaction,
        requestIsCurrent: @escaping @MainActor () -> Bool
    ) -> Result {
        func isCurrent() -> Bool {
            !isCancelled && !wasInvalidatedDuringMatch && requestIsCurrent() && runtime.permitsRetainedActionInvocation
                && lists.allSatisfy {
                    $0.isCurrent(in: runtime, root: root, readerIdentifier: readerIdentifier)
                }
        }
        guard isCurrent() else { return .obsolete }
        guard runtime.hasCompletedLayout, !runtime.isLayoutInProgress, !runtime.hasPendingLayout else {
            return .pending
        }
        // Runtime skips mounted records while probing. Recheck the live tree
        // on every slice: ordinary viewport work can mount a matching row
        // between two cursors without replacing the logical source.
        let mounted = retainedScrollTargetSnapshot(
            for: targetKey, in: [root], readerIdentifier: readerIdentifier,
            includeImplicit: false, isCurrent: isCurrent)
        guard let mounted, isCurrent() else { return .obsolete }
        if let target = mounted.explicit {
            return completeScroll(
                to: target, in: runtime, root: root, anchor: anchor, transaction: transaction, isCurrent: isCurrent)
        }
        for nested in mounted.lists {
            if !lists.contains(where: { $0.node === nested.node && $0.source === nested.source }) {
                hasUnsearchedNestedSource = true
            }
        }
        for list in lists {
            guard isCurrent() else { return .obsolete }
            guard list.captureWitness(in: runtime) else { return isCurrent() ? .pending : .obsolete }
        }

        if !resolvedLogicalCandidate {
            var candidate: LogicalCandidate?
            for list in lists {
                guard isCurrent(), let source = list.source else { return .obsolete }
                if let implicitTreeOrder, list.treeOrder >= implicitTreeOrder { break }
                let index = source.index(for: target, isCurrent: isCurrent)
                guard isCurrent() else { return .obsolete }
                if let index, let row = source.row(at: index) {
                    candidate = LogicalCandidate(attachment: list, providerKey: row.providerKey)
                    break
                }
            }
            guard isCurrent() else { return .obsolete }
            logicalCandidate = candidate
            resolvedLogicalCandidate = true
        }

        while selectedItem == nil, searchIndex < lists.count {
            guard isCurrent(), let node = lists[searchIndex].node else { return .obsolete }
            let result = runtime.probeLazyListScrollTarget(
                in: node, after: searchCursor, requestIsCurrent: isCurrent,
                matches: { nodes in
                    let match = retainedScrollTargetSnapshot(
                        for: self.targetKey, in: nodes, readerIdentifier: self.readerIdentifier,
                        includeImplicit: false, isCurrent: isCurrent)
                    guard let match, isCurrent() else {
                        self.wasInvalidatedDuringMatch = true
                        return false
                    }
                    if match.lists.contains(where: { ($0.source?.rowCount ?? 0) > 0 }) {
                        // A nested lazy adapter built only for this doomed
                        // probe has no actual attachment to search. Its hidden
                        // IDs are unknown, not evidence that no explicit ID
                        // can shadow an implicit candidate in the outer List.
                        self.hasUnsearchedNestedSource = true
                    }
                    return isCurrent() && match.explicit != nil
                })
            guard isCurrent() else { return .obsolete }
            switch result {
            case .found(let token):
                let item = runtime.lazyListTarget(in: node, token: token)
                guard isCurrent(), let item, runtime.isLazyListAccessibilityItemCurrent(item) else {
                    return .obsolete
                }
                selectedItem = item
                selectedIsExplicit = true
                searchCursor = nil
            case .more(let cursor):
                searchCursor = cursor
                return .pending
            case .notFound:
                searchIndex += 1
                searchCursor = nil
            case .deferred:
                return .pending
            case .obsolete:
                return .obsolete
            }
        }

        if selectedItem == nil, hasUnsearchedNestedSource { return .unsupported }

        if selectedItem == nil, let logicalCandidate {
            guard isCurrent(), let node = logicalCandidate.attachment.node else { return .obsolete }
            let item = runtime.lazyListTarget(in: node, key: logicalCandidate.providerKey)
            guard isCurrent(), let item, runtime.isLazyListAccessibilityItemCurrent(item) else {
                return .obsolete
            }
            selectedItem = item
            selectedIsExplicit = false
        }

        guard let item = selectedItem else {
            guard let implicitNode,
                retainedScrollReaderContains(implicitNode, root: root, readerIdentifier: readerIdentifier)
            else { return .complete }
            return completeScroll(
                to: implicitNode, in: runtime, root: root, anchor: anchor, transaction: transaction,
                isCurrent: isCurrent)
        }

        guard isCurrent(), runtime.isLazyListAccessibilityItemCurrent(item) else { return .obsolete }
        let resolution = runtime.resolveLazyListTarget(item)
        guard isCurrent(), runtime.isLazyListAccessibilityItemCurrent(item) else { return .obsolete }
        let nodes: [ViewNode]
        switch resolution {
        case .ready(let actualNodes):
            nodes = actualNodes
        case .pending:
            return .pending
        case .empty:
            return .complete
        case .unsupported:
            return .unsupported
        case .obsolete:
            return .obsolete
        }
        let targetNode: ViewNode?
        if selectedIsExplicit {
            // A factory can branch on application state. A speculative match
            // never licenses scrolling a different accepted row after replay.
            let match = retainedScrollTargetSnapshot(
                for: targetKey, in: nodes, readerIdentifier: readerIdentifier,
                includeImplicit: false, collectLists: false, isCurrent: isCurrent)
            guard let match, isCurrent() else { return .obsolete }
            targetNode = match.explicit
        } else {
            let match = retainedScrollTargetSnapshot(
                for: targetKey, in: nodes, readerIdentifier: readerIdentifier,
                collectLists: false, isCurrent: isCurrent)
            guard let match, isCurrent() else { return .obsolete }
            targetNode = match.explicit ?? match.implicit ?? nodes.first(where: { !$0.isHidden })
        }
        guard let targetNode else { return .complete }
        guard retainedScrollReaderContains(targetNode, root: root, readerIdentifier: readerIdentifier), isCurrent()
        else { return .obsolete }
        return completeScroll(
            to: targetNode, in: runtime, root: root, anchor: anchor, transaction: transaction, isCurrent: isCurrent)
    }

    private func completeScroll(
        to target: ViewNode, in runtime: RetainedViewRuntime, root: ViewNode, anchor: UnitPoint?,
        transaction: Transaction, isCurrent: () -> Bool
    ) -> Result {
        guard isCurrent() else { return .obsolete }
        var current: ViewNode? = target
        var visited: Set<ObjectIdentifier> = []
        var hasContainer = false
        while let node = current, visited.insert(ObjectIdentifier(node)).inserted {
            if node.scrollAxis != nil {
                hasContainer = true
                break
            }
            if node === root { break }
            current = node.parent
        }
        guard hasContainer else { return .complete }
        let moved = runtime.scrollToDescendant(
            target, anchorX: anchor?.x, anchorY: anchor?.y, transaction: transaction)
        guard isCurrent() else { return .obsolete }
        if moved { return .complete }
        return !runtime.hasCompletedLayout || runtime.isLayoutInProgress || runtime.hasPendingLayout
            ? .pending : .complete
    }
}
