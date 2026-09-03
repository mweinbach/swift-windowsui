import CUIAInterop
import SwiftWindowsCore
import SwiftWindowsPlatform
import SwiftWindowsUI

// UI Automation projection adapter (Stabilization Roadmap, Phase 2).
//
// Maps the retained runtime's `AccessibilityProjection` output onto the
// platform-neutral `UIAElementTreeSource` consumed by `UIAProviderBridge`
// (in SwiftWindowsPlatform). All tree truth comes from live re-projection of
// the retained `ViewNode` tree. Stable element-id metadata and a bounded native
// receipt cache let logical List items be found without retaining row views,
// state owners, or a second accessibility tree.

@MainActor
final class RuntimeUIAElementTreeSource: UIAItemContainerSource {
    private final class WeakNode {
        weak var node: ViewNode?

        init(_ node: ViewNode) {
            self.node = node
        }
    }

    /// Root ID zero is a window endpoint. Its selected node is captured once
    /// for an operation; ordinary provider IDs still identify their own node.
    @MainActor
    private struct RetainedNodeRequest {
        weak var node: ViewNode?
        let selectedPath: RetainedSelectedContentPath?

        func isCurrent(in runtime: RetainedViewRuntime) -> Bool {
            guard let node else { return false }
            return RuntimeUIAElementTreeSource.selectedPathIsCurrent(selectedPath, for: node, in: runtime)
        }
    }

    /// A receipt retains only native logical identity, not a row factory, a
    /// View, state storage, or a physical node. The queried-identity cache is
    /// bounded independently of the number of logical data records.
    private final class LogicalItem {
        let target: RetainedLazyListAccessibilityItem
        weak var node: ViewNode?

        init(target: RetainedLazyListAccessibilityItem, node: ViewNode? = nil) {
            self.target = target
            self.node = node
        }
    }

    /// Every queried token shares its container's original attachment witness.
    /// The per-item identity map is O(queried data), while physical nodes remain
    /// weak and the reconstructible per-item receipts are bounded separately.
    private final class LogicalContainer {
        let witness: RetainedLazyListAccessibilityItem
        var generation: RetainedLazyListGeneration
        var idsByToken: [RetainedLazyListRowToken: UInt64] = [:]

        init(witness: RetainedLazyListAccessibilityItem, generation: RetainedLazyListGeneration) {
            self.witness = witness
            self.generation = generation
        }
    }

    private struct LogicalIdentity {
        let token: RetainedLazyListRowToken
        let container: LogicalContainer
    }

    /// The action has already run. Only native identity and weak attachment
    /// proofs leave its dispatch frame; no action or row payload is retained.
    private struct InvocationCompletion {
        let identity: LogicalIdentity
        let item: RetainedLazyListAccessibilityItem
        let target: RetainedAccessibilityTarget
        let mutationRevision: UInt64
    }

    /// The effect is already finished when this leaves the dispatch frame.
    /// No editor or application capture is kept alive by this receipt.
    private struct ValueCompletion {
        let result: TextInputAccessibilityValueResult
        let target: RetainedAccessibilityTarget
        let selectedPath: RetainedSelectedContentPath?
        weak var controller: (any RetainedTextInputController)?
        let focusRevision: UInt64
        let mutationRevision: UInt64
    }

    // The host owns its runtime. An accessibility bridge may outlive that
    // owner, so keep the projection source without keeping the view tree alive.
    private weak var runtime: RetainedViewRuntime?
    /// Copied host metadata, never retained-node label or text authority.
    private let windowName: String?
    /// Legacy/headless mapping. Production native requests supply their copied
    /// geometry explicitly and never call this potentially effectful closure.
    private let screenBoundsMapper: (Rect) -> Rect
    private var idsByNode: [ObjectIdentifier: UInt64] = [:]
    private var nodesByID: [UInt64: WeakNode] = [:]
    private var nextID: UInt64 = 1
    private static let logicalIDBoundary: UInt64 = 1 << 63
    static let logicalItemReceiptLimit = 128
    private var nextLogicalID = RuntimeUIAElementTreeSource.logicalIDBoundary
    private var logicalContainers: [ObjectIdentifier: LogicalContainer] = [:]
    private var logicalIdentitiesByID: [UInt64: LogicalIdentity] = [:]
    private var logicalItemsByID: [UInt64: LogicalItem] = [:]
    private var logicalItemRecency: [UInt64] = []
    private var projectedLogicalIDs: Set<UInt64> = []
    var logicalItemReceiptCount: Int { logicalItemsByID.count }
    var logicalItemIdentityCount: Int { logicalIdentitiesByID.count }

    init(
        runtime: RetainedViewRuntime, windowName: String? = nil,
        screenBoundsMapper: @escaping (Rect) -> Rect = { $0 }
    ) {
        self.runtime = runtime
        self.windowName = windowName
        self.screenBoundsMapper = screenBoundsMapper
    }

    // MARK: - UIAElementTreeSource

    func uiaElementSnapshots() -> [UIAElementSnapshot] {
        elementSnapshots(screenBoundsMapper: screenBoundsMapper)
    }

    func uiaElementSnapshots(geometry: NativeWindowGeometry) throws -> [UIAElementSnapshot] {
        try elementSnapshots { bounds in
            guard let mapped = geometry.clientRectToScreen(bounds) else {
                throw UIAProviderRequestFailure.invalidGeometry
            }
            return mapped
        }
    }

    private func elementSnapshots(
        screenBoundsMapper: (Rect) throws -> Rect
    ) rethrows -> [UIAElementSnapshot] {
        guard let runtime else {
            for (key, group) in logicalContainers { retireLogicalContainer(group, key: key) }
            return []
        }
        defer { withExtendedLifetime(runtime) {} }
        let rootRequest: RetainedNodeRequest?
        if runtime.root.selectedContentRole != nil {
            guard let captured = retainedNodeRequest(for: UIAProviderBridge.rootElementID, in: runtime) else {
                return []
            }
            rootRequest = captured
        } else {
            rootRequest = nil
        }
        pruneDeadNodes()
        synchronizeLogicalContainers(in: runtime)
        guard let root = AccessibilityProjection.project(runtime: runtime) else {
            return []
        }
        if let rootRequest {
            guard rootRequest.isCurrent(in: runtime), root.sourceNode === rootRequest.node else { return [] }
        }
        // Decide from this projection before either effectful bounds-mapper call.
        let rootName = fallbackWindowRootName(for: root, in: runtime)
        let passwordElements = Self.capturePasswordElements(in: root)
        refreshLogicalItems(using: root, in: runtime)
        guard rootRequest?.isCurrent(in: runtime) != false else { return [] }
        var snapshots: [UIAElementSnapshot] = []
        let rootBounds = try screenBoundsMapper(root.bounds)
        guard rootRequest?.isCurrent(in: runtime) != false else { return [] }
        try appendSnapshots(
            for: root, parentID: nil, rootBounds: rootBounds, into: &snapshots,
            runtime: runtime, rootRequest: rootRequest, passwordElements: passwordElements,
            rootName: rootName, screenBoundsMapper: screenBoundsMapper)
        guard rootRequest?.isCurrent(in: runtime) != false else { return [] }
        // Transparent retained containers are flattened by the accessibility
        // projection, so the nearest projected parent is the honest UIA
        // Selection container even when it is the window's root pane.
        let selectionParentIDs = Set(
            snapshots.compactMap { snapshot in
                snapshot.isSelected != nil ? snapshot.parentID : nil
            }
        )
        for index in snapshots.indices where selectionParentIDs.contains(snapshots[index].id) {
            snapshots[index].supportsSelection = true
        }
        return snapshots
    }

    private func fallbackWindowRootName(
        for element: AccessibilityElementProjection, in runtime: RetainedViewRuntime
    ) -> String? {
        guard let windowName, element.name.isEmpty,
            let node = element.sourceNode, node === runtime.root,
            node.selectedContentRole == nil, node.accessibilityLabel == nil,
            node.text == nil, node.accessibilityChildBehavior == nil
        else { return nil }
        return windowName
    }

    // MARK: - Logical data items

    func uiaFindItem(containerID: UInt64, afterElementID: UInt64?) -> UIAItemContainerResult {
        findItem(containerID: containerID, afterElementID: afterElementID) { uiaElementSnapshots() }
    }

    func uiaFindItem(
        containerID: UInt64, afterElementID: UInt64?, geometry: NativeWindowGeometry
    ) throws -> UIAItemContainerResult {
        try findItem(containerID: containerID, afterElementID: afterElementID) {
            try uiaElementSnapshots(geometry: geometry)
        }
    }

    private func findItem(
        containerID: UInt64, afterElementID: UInt64?, captureSnapshots: () throws -> [UIAElementSnapshot]
    ) rethrows -> UIAItemContainerResult {
        guard let runtime, runtime.permitsRetainedActionInvocation else { return .unavailable }
        defer { withExtendedLifetime(runtime) {} }
        let needsRoot =
            containerID == UIAProviderBridge.rootElementID
            || afterElementID == UIAProviderBridge.rootElementID
        let rootRequest = needsRoot ? retainedNodeRequest(for: UIAProviderBridge.rootElementID, in: runtime) : nil
        guard !needsRoot || rootRequest?.isCurrent(in: runtime) == true else { return .unavailable }
        let snapshots = try captureSnapshots()
        let containerRequest =
            containerID == UIAProviderBridge.rootElementID
            ? rootRequest : retainedNodeRequest(for: containerID, in: runtime)
        guard rootRequest?.isCurrent(in: runtime) != false,
            snapshots.contains(where: { $0.id == containerID && $0.supportsItemContainer }),
            let containerRequest, let container = containerRequest.node, containerRequest.isCurrent(in: runtime),
            runtime.supportsLazyListAccessibilityItems(in: container), containerRequest.isCurrent(in: runtime)
        else { return .unavailable }

        let after: RetainedLazyListAccessibilityItem?
        if let afterElementID {
            if logicalIdentitiesByID[afterElementID] != nil {
                guard let item = logicalItem(for: afterElementID, in: runtime) else { return .unavailable }
                guard item.target.container === container else { return .invalidStart }
                after = item.target
            } else {
                guard afterElementID < Self.logicalIDBoundary else { return .unavailable }
                let afterRequest =
                    afterElementID == UIAProviderBridge.rootElementID
                    ? rootRequest : retainedNodeRequest(for: afterElementID, in: runtime)
                guard let afterRequest, let node = afterRequest.node, afterRequest.isCurrent(in: runtime),
                    let item = runtime.lazyListAccessibilityItem(in: container, containing: node)
                else { return .invalidStart }
                guard afterRequest.isCurrent(in: runtime) else { return .unavailable }
                after = item
            }
        } else {
            after = nil
        }
        guard rootRequest?.isCurrent(in: runtime) != false, containerRequest.isCurrent(in: runtime) else {
            return .unavailable
        }
        let target = runtime.lazyListAccessibilityItem(in: container, after: after)
        guard rootRequest?.isCurrent(in: runtime) != false, containerRequest.isCurrent(in: runtime) else {
            return .unavailable
        }
        guard let target else { return .end }
        guard let group = logicalContainer(for: target, in: runtime),
            rootRequest?.isCurrent(in: runtime) != false, containerRequest.isCurrent(in: runtime)
        else { return .unavailable }
        if let id = group.idsByToken[target.token], logicalItem(for: id, in: runtime) != nil {
            guard rootRequest?.isCurrent(in: runtime) != false, containerRequest.isCurrent(in: runtime) else {
                return .unavailable
            }
            return .item(id)
        }

        let node = runtime.realizedLazyListAccessibilityNodes(for: target).flatMap { roots in
            snapshots.lazy
                .filter { !$0.isVirtualizedPlaceholder }
                .compactMap { self.nodesByID[$0.id]?.node }
                .first { node in
                    Self.isInsideLogicalRoots(node, roots: roots)
                }
        }
        guard rootRequest?.isCurrent(in: runtime) != false, containerRequest.isCurrent(in: runtime) else {
            return .unavailable
        }
        let id: UInt64
        if let node {
            id = stableID(for: node)
        } else {
            guard nextLogicalID != UInt64.max else { return .unavailable }
            id = nextLogicalID
            nextLogicalID += 1
        }
        logicalIdentitiesByID[id] = LogicalIdentity(token: target.token, container: group)
        group.idsByToken[target.token] = id
        cacheLogicalItem(id, target: target, node: node)
        if node != nil { projectedLogicalIDs.insert(id) }
        return .item(id)
    }

    /// Called by native providers before/after publishing logical properties.
    /// This does not project the tree, settle layout, or call authored code.
    func uiaLogicalItemState(elementID: UInt64) -> UIALogicalItemState {
        guard let identity = logicalIdentitiesByID[elementID] else {
            return elementID >= Self.logicalIDBoundary ? .unavailable : .ordinary
        }
        guard let runtime,
            runtime.isLazyListAccessibilityTokenCurrent(identity.token, in: identity.container.witness)
        else { return .unavailable }
        // A surviving token can be known before its accepted adapter has a
        // prepared physical snapshot. Keep RuntimeId/Realize available without
        // inventing geometry or reviving the predecessor's actionable receipt.
        guard let item = logicalItem(for: elementID, in: runtime) else { return .placeholder }
        guard projectedLogicalIDs.contains(elementID), let node = item.node,
            let container = item.target.container,
            runtime.lazyListAccessibilityItem(in: container, containing: node)?.token == item.target.token,
            runtime.accessibilityTarget(for: node) != nil,
            nodesByID[elementID]?.node === node
        else { return .placeholder }
        // Dirty geometry does not turn an attached row back into logical data.
        // Let its ordinary snapshot query settle layout and produce real bounds;
        // the native caller checks this receipt again after that query returns.
        return .ordinary
    }

    private func refreshLogicalItems(
        using projection: AccessibilityElementProjection, in runtime: RetainedViewRuntime
    ) {
        synchronizeLogicalContainers(in: runtime)
        let elements = projection.flattened()
        projectedLogicalIDs.removeAll(keepingCapacity: true)
        var visitedTokens: Set<RetainedLazyListRowToken> = []
        for element in elements where !element.isVirtualizedPlaceholder {
            guard let node = element.sourceNode else { continue }
            var ancestor: ViewNode? = node
            var visited: Set<ObjectIdentifier> = []
            while let candidate = ancestor, visited.insert(ObjectIdentifier(candidate)).inserted {
                if let group = logicalContainers[ObjectIdentifier(candidate)],
                    let target = runtime.lazyListAccessibilityItem(in: candidate, containing: node),
                    let id = group.idsByToken[target.token]
                {
                    if visitedTokens.insert(target.token).inserted {
                        cacheLogicalItem(id, target: target, node: nil)
                        bindLogicalItem(id, to: node)
                    }
                    break
                }
                ancestor = candidate.parent
            }
        }
        for (id, item) in logicalItemsByID where !projectedLogicalIDs.contains(id) {
            item.node = nil
        }
    }

    private func logicalContainer(
        for target: RetainedLazyListAccessibilityItem, in runtime: RetainedViewRuntime
    ) -> LogicalContainer? {
        guard let container = target.container,
            let generation = runtime.lazyListAccessibilityGeneration(for: target)
        else { return nil }
        let key = ObjectIdentifier(container)
        if let group = logicalContainers[key], runtime.isLazyListAccessibilityContainerCurrent(group.witness) {
            return group
        }
        if let previous = logicalContainers[key] { retireLogicalContainer(previous, key: key) }
        let group = LogicalContainer(witness: target, generation: generation)
        logicalContainers[key] = group
        return group
    }

    /// Cache misses recreate an equivalent native receipt only while the
    /// original container attachment and row token are both still current.
    private func logicalItem(for id: UInt64, in runtime: RetainedViewRuntime) -> LogicalItem? {
        guard let identity = logicalIdentitiesByID[id],
            runtime.isLazyListAccessibilityContainerCurrent(identity.container.witness)
        else { return nil }
        if let item = logicalItemsByID[id], runtime.isLazyListAccessibilityItemCurrent(item.target) {
            touchLogicalItem(id)
            return item
        }
        guard let container = identity.container.witness.container,
            let target = runtime.lazyListTarget(in: container, token: identity.token)
        else { return nil }
        cacheLogicalItem(
            id, target: target, node: projectedLogicalIDs.contains(id) ? nodesByID[id]?.node : nil)
        return logicalItemsByID[id]
    }

    private func cacheLogicalItem(_ id: UInt64, target: RetainedLazyListAccessibilityItem, node: ViewNode?) {
        logicalItemsByID[id] = LogicalItem(target: target, node: node)
        touchLogicalItem(id)
        while logicalItemRecency.count > Self.logicalItemReceiptLimit {
            let oldest = logicalItemRecency.removeFirst()
            logicalItemsByID.removeValue(forKey: oldest)
        }
    }

    private func synchronizeLogicalContainers(in runtime: RetainedViewRuntime) {
        for (key, group) in logicalContainers {
            guard let container = group.witness.container,
                runtime.isLazyListAccessibilityContainerCurrent(group.witness)
            else {
                retireLogicalContainer(group, key: key)
                continue
            }
            // Accepted membership can outlive one adapter's prepared snapshot.
            // A query before the successor's first layout is not a departure;
            // wait for its metadata instead of losing every queried logical ID.
            guard let generation = runtime.lazyListAccessibilityGeneration(for: group.witness) else { continue }
            guard group.generation != generation else { continue }
            group.generation = generation
            // Only actual metadata replacement needs a pass over queried IDs.
            // Unchanged snapshot queries visit retained nodes, never all data.
            for (token, id) in group.idsByToken where runtime.lazyListTarget(in: container, token: token) == nil {
                retireLogicalIdentity(id)
            }
        }
    }

    private static func firstProjectedNode(
        in roots: [ViewNode], elements: [AccessibilityElementProjection]
    ) -> ViewNode? {
        for element in elements where !element.isVirtualizedPlaceholder {
            if let node = element.sourceNode, isInsideLogicalRoots(node, roots: roots) { return node }
        }
        return nil
    }

    private static func isInsideLogicalRoots(_ node: ViewNode, roots: [ViewNode]) -> Bool {
        let rootIDs = Set(roots.map(ObjectIdentifier.init))
        var ancestor: ViewNode? = node
        var visited: Set<ObjectIdentifier> = []
        while let candidate = ancestor {
            let identity = ObjectIdentifier(candidate)
            guard visited.insert(identity).inserted else { return false }
            if rootIDs.contains(identity) { return true }
            ancestor = candidate.parent
        }
        return false
    }

    private func bindLogicalItem(_ id: UInt64, to node: ViewNode) {
        guard let item = logicalItemsByID[id] else { return }
        let key = ObjectIdentifier(node)
        // Enumeration reuses a mounted leaf's existing id. A deferred receipt
        // may claim a newly constructed leaf, but never steals another live
        // provider's identity if reentrant code already projected that leaf.
        if let prior = idsByNode[key], prior != id, nodesByID[prior]?.node === node {
            item.node = nil
            return
        }
        if let previous = nodesByID[id]?.node, previous !== node, idsByNode[ObjectIdentifier(previous)] == id {
            idsByNode.removeValue(forKey: ObjectIdentifier(previous))
        }
        item.node = node
        idsByNode[key] = id
        nodesByID[id] = WeakNode(node)
        projectedLogicalIDs.insert(id)
    }

    private func unbindLogicalItem(_ id: UInt64) {
        logicalItemsByID[id]?.node = nil
        projectedLogicalIDs.remove(id)
        if let node = nodesByID[id]?.node, idsByNode[ObjectIdentifier(node)] == id {
            idsByNode.removeValue(forKey: ObjectIdentifier(node))
        }
        nodesByID.removeValue(forKey: id)
    }

    private func touchLogicalItem(_ id: UInt64) {
        logicalItemRecency.removeAll { $0 == id }
        logicalItemRecency.append(id)
    }

    private func retireLogicalIdentity(_ id: UInt64) {
        guard let identity = logicalIdentitiesByID.removeValue(forKey: id) else { return }
        identity.container.idsByToken.removeValue(forKey: identity.token)
        logicalItemsByID.removeValue(forKey: id)
        logicalItemRecency.removeAll { $0 == id }
        unbindLogicalItem(id)
    }

    private func retireLogicalContainer(_ group: LogicalContainer, key: ObjectIdentifier) {
        for id in group.idsByToken.values { retireLogicalIdentity(id) }
        if logicalContainers[key] === group { logicalContainers.removeValue(forKey: key) }
    }

    @discardableResult
    func uiaInvokeDefaultAction(elementID: UInt64) -> Bool {
        withMutation { runtime, mutation in
            if logicalIdentitiesByID[elementID] != nil {
                return runtime.withLazyListResolutionBudget {
                    invokeLogicalDefaultAction(elementID: elementID, in: runtime, during: mutation)
                }
            }
            return invokeDefaultAction(elementID: elementID, in: runtime, intent: .invoke)
        }
    }

    func uiaSetFocus(elementID: UInt64) {
        _ = uiaSetFocusResult(elementID: elementID)
    }

    /// The legacy source/COM callback remains Void. This internal result is
    /// true only when the guarded retained transition is still qualified;
    /// false does not imply its earlier focus callbacks had no effects.
    func uiaSetFocusResult(elementID: UInt64) -> Bool {
        withMutation { runtime, _ in
            setFocusResult(elementID: elementID, in: runtime)
        }
    }

    @inline(never)
    private func setFocusResult(elementID: UInt64, in runtime: RetainedViewRuntime) -> Bool {
        guard runtime.permitsRetainedActionInvocation,
            let request = retainedNodeRequest(for: elementID, in: runtime), let node = request.node,
            request.isCurrent(in: runtime)
        else { return false }
        return runtime.requestAccessibilityFocus(node, selectedPath: request.selectedPath)
    }

    @discardableResult
    func uiaSetValue(elementID: UInt64, value: String) -> Bool {
        withMutation { runtime, mutation in
            setValue(elementID: elementID, value: value, in: runtime, during: mutation)
        }
    }

    @discardableResult
    func uiaToggle(elementID: UInt64) -> Bool {
        withMutation { runtime, _ in
            invokeDefaultAction(elementID: elementID, in: runtime, intent: .toggle)
        }
    }

    @discardableResult
    func uiaSelect(elementID: UInt64) -> Bool {
        withMutation { runtime, _ in
            invokeDefaultAction(elementID: elementID, in: runtime, intent: .select)
        }
    }

    @discardableResult
    func uiaAddToSelection(elementID: UInt64) -> Bool {
        uiaSelect(elementID: elementID)
    }

    @discardableResult
    func uiaRemoveFromSelection(elementID: UInt64) -> Bool {
        withMutation { runtime, _ in
            invokeDefaultAction(elementID: elementID, in: runtime, intent: .removeFromSelection)
        }
    }

    @discardableResult
    func uiaRealizeVirtualizedItem(elementID: UInt64) -> Bool {
        withMutation { runtime, mutation in
            realize(elementID: elementID, in: runtime, during: mutation)
        }
    }

    @inline(never)
    private func withMutation(
        _ perform: (RetainedViewRuntime, RetainedAccessibilityMutation) -> Bool
    ) -> Bool {
        guard let runtime, let mutation = runtime.beginAccessibilityMutation() else { return false }
        defer {
            runtime.endAccessibilityMutation(mutation)
            withExtendedLifetime(runtime) {}
        }
        // Inner helpers release callback captures before admission is opened
        // again. A false result after an effect never schedules another attempt.
        return perform(runtime, mutation)
    }

    @inline(never)
    private func realize(
        elementID: UInt64, in runtime: RetainedViewRuntime, during mutation: RetainedAccessibilityMutation
    ) -> Bool {
        if let identity = logicalIdentitiesByID[elementID] {
            // Preparing an accepted replacement and realizing the requested
            // target borrow one allowance. A nested preparation cannot reset
            // the budget or transfer the request to a same-key reinsertion.
            return runtime.withLazyListResolutionBudget {
                guard
                    let request = runtime.prepareLazyListUIARequest(
                        token: identity.token, in: identity.container.witness, during: mutation)
                else { return false }
                defer { runtime.finishLazyListUIARequest(request) }
                let item = request.item
                guard
                    let currentIdentity = logicalIdentitiesByID[elementID],
                    currentIdentity.container === identity.container, currentIdentity.token == identity.token,
                    runtime.isLazyListAccessibilityItemCurrent(item)
                else { return false }
                cacheLogicalItem(
                    elementID, target: item,
                    node: projectedLogicalIDs.contains(elementID) ? nodesByID[elementID]?.node : nil)
                guard let roots = runtime.resolveLazyListUIARequest(request),
                    runtime.isAccessibilityMutationCurrent(mutation),
                    let projection = AccessibilityProjection.project(root: runtime.root),
                    let node = Self.firstProjectedNode(in: roots, elements: projection.flattened()),
                    let target = runtime.accessibilityTarget(for: node),
                    runtime.isAccessibilityTargetCurrent(target, during: mutation),
                    runtime.isLazyListAccessibilityItemCurrent(item),
                    runtime.isResolvedLazyListUIARequestCurrent(request)
                else { return false }
                bindLogicalItem(elementID, to: node)
                return runtime.realizedLazyListAccessibilityNodes(for: item) != nil
                    && uiaLogicalItemState(elementID: elementID) == .ordinary
                    && runtime.isAccessibilityTargetCurrent(target, during: mutation)
                    && runtime.isResolvedLazyListUIARequestCurrent(request)
            }
        }
        guard elementID < Self.logicalIDBoundary else { return false }
        guard let request = retainedNodeRequest(for: elementID, in: runtime), let node = request.node,
            request.isCurrent(in: runtime), let target = runtime.accessibilityTarget(for: node)
        else { return false }
        // A forced root projection is not a virtualized placeholder. Do not
        // enter realization with an alias path that its internal scroll
        // continuation cannot validate. Ordinary provider realization is unchanged.
        guard request.selectedPath == nil else { return false }
        return runtime.realizeAccessibilityTarget(target, during: mutation)
    }

    @inline(never)
    private func setValue(
        elementID: UInt64, value: String, in runtime: RetainedViewRuntime,
        during mutation: RetainedAccessibilityMutation
    ) -> Bool {
        let completion = dispatchValue(elementID: elementID, value: value, in: runtime, during: mutation)
        // Retired original controllers can release arbitrary Binding captures
        // when dispatchValue returns. Admission is still held here. Do not
        // absorb effects of those destructors into the completed operation.
        guard let completion, completion.result.didDispatch, completion.result.accepted,
            completion.mutationRevision == mutation.revision,
            let controller = completion.controller,
            completion.target.node?.textInputController === controller
        else { return false }
        return Self.valueTargetIsCurrent(
            completion.target, in: runtime, during: mutation, focusRevision: completion.focusRevision,
            selectedPath: completion.selectedPath)
    }

    @inline(never)
    private func dispatchValue(
        elementID: UInt64, value: String, in runtime: RetainedViewRuntime,
        during mutation: RetainedAccessibilityMutation
    ) -> ValueCompletion? {
        guard let request = retainedNodeRequest(for: elementID, in: runtime), let node = request.node,
            request.isCurrent(in: runtime), let target = runtime.accessibilityTarget(for: node),
            let original = node.textInputController as? any TextInputAccessibilityValueReplacing,
            Self.isWritableValueNode(node), request.isCurrent(in: runtime)
        else { return nil }
        defer { withExtendedLifetime(original) {} }
        // The capability is the selected handler. Keep that exact controller
        // before any focus/layout callback; a replacement may not inherit the
        // request. Raw key and IME handlers are never a fallback.
        guard runtime.requestAccessibilityFocus(node, selectedPath: request.selectedPath),
            runtime.isAccessibilityTargetCurrent(target, during: mutation),
            node.textInputController === original, request.isCurrent(in: runtime)
        else { return nil }
        let focusRevision = runtime.presentationFocusRevision
        guard
            Self.valueTargetIsCurrent(
                target, in: runtime, during: mutation, focusRevision: focusRevision, selectedPath: request.selectedPath)
        else { return nil }
        let result = original.replaceValueForAccessibility(
            value,
            validation: TextInputAccessibilityValueValidation(
                mayDispatch: {
                    node.textInputController === original
                        && Self.valueTargetIsCurrent(
                            target, in: runtime, during: mutation, focusRevision: focusRevision,
                            selectedPath: request.selectedPath)
                },
                isRetainedTargetCurrent: {
                    Self.valueTargetIsCurrent(
                        target, in: runtime, during: mutation, focusRevision: focusRevision,
                        selectedPath: request.selectedPath)
                }))
        // A compatible setter rebuild can replace the controller while the
        // capability preserves the accepted edit. Publish that completion's
        // weak identity before releasing the original controller's captures.
        return ValueCompletion(
            result: result, target: target, selectedPath: request.selectedPath, controller: node.textInputController,
            focusRevision: focusRevision, mutationRevision: mutation.revision)
    }

    private static func isWritableValueNode(_ node: ViewNode) -> Bool {
        guard AccessibilityProjection.resolveControlType(for: node) == .edit,
            !node.accessibilityTraits.contains(.isSecureTextInput),
            let controller = node.textInputController as? any TextInputAccessibilityValueReplacing,
            !controller.isSecure
        else { return false }
        return controller.hasCurrentAccessibilityValueOwnership
    }

    /// Only stored retained state is read. Normal editor completion deliberately
    /// dirties layout, so an earlier settled/prepaint receipt cannot authorize
    /// or reject this semantic check. It never supplies geometry to UIA.
    private static func valueTargetIsCurrent(
        _ target: RetainedAccessibilityTarget, in runtime: RetainedViewRuntime,
        during mutation: RetainedAccessibilityMutation, focusRevision: UInt64,
        selectedPath: RetainedSelectedContentPath? = nil
    ) -> Bool {
        guard selectedPathIsCurrent(selectedPath, for: target.node, in: runtime),
            runtime.isAccessibilityTargetCurrent(target, during: mutation), let node = target.node,
            runtime.focusedNode === node, node.isFocused, node.isFocusable,
            runtime.presentationFocusRevision == focusRevision, isWritableValueNode(node),
            runtime.permitsConservativeAccessibilityValueTarget(node),
            let element = AccessibilityProjection.project(root: runtime.root)?.flattened().first(where: {
                $0.sourceNode === node
            }),
            element.controlType == .edit, element.isEnabled, element.permitsModalActions,
            !element.isVirtualizedPlaceholder, !element.traits.contains(.isSecureTextInput)
        else { return false }
        return selectedPathIsCurrent(selectedPath, for: node, in: runtime)
    }

    private static func selectedPathIsCurrent(
        _ path: RetainedSelectedContentPath?, for node: ViewNode?, in runtime: RetainedViewRuntime
    ) -> Bool {
        guard let path else { return true }
        guard let node else { return false }
        return path.isCurrent && path.isInstalled(in: runtime) && path.physicalRoot === runtime.root
            && path.selectedNode === node
    }

    private func retainedNodeRequest(
        for elementID: UInt64, in runtime: RetainedViewRuntime
    ) -> RetainedNodeRequest? {
        if elementID == UIAProviderBridge.rootElementID {
            guard runtime.root.selectedContentRole != nil else {
                return RetainedNodeRequest(node: runtime.root, selectedPath: nil)
            }
            guard let path = runtime.root.captureSelectedContentPath(in: runtime), let node = path.selectedNode,
                Self.selectedPathIsCurrent(path, for: node, in: runtime)
            else { return nil }
            return RetainedNodeRequest(node: node, selectedPath: path)
        }
        guard let node = retainedNode(for: elementID, in: runtime) else { return nil }
        return RetainedNodeRequest(node: node, selectedPath: nil)
    }

    private func retainedNode(for elementID: UInt64, in runtime: RetainedViewRuntime) -> ViewNode? {
        // Only the operation-scoped resolver above may interpret root ID zero.
        guard elementID != UIAProviderBridge.rootElementID else { return nil }
        if logicalIdentitiesByID[elementID] != nil {
            guard uiaLogicalItemState(elementID: elementID) == .ordinary else { return nil }
        } else if elementID >= Self.logicalIDBoundary {
            return nil
        }
        return nodesByID[elementID]?.node
    }

    @inline(never)
    private func invokeLogicalDefaultAction(
        elementID: UInt64, in runtime: RetainedViewRuntime, during mutation: RetainedAccessibilityMutation
    ) -> Bool {
        // Dispatch returns before any completion query, so retired action or
        // node captures cannot release application code inside that query.
        guard let completion = dispatchLogicalInvocation(elementID: elementID, in: runtime, during: mutation),
            completion.mutationRevision == mutation.revision,
            isLogicalInvocationCurrent(completion, elementID: elementID, in: runtime, during: mutation)
        else { return false }
        // A still-ordinary row keeps the original action behavior. In particular,
        // action-authored queued work does not buy an extra layout query.
        if uiaLogicalItemState(elementID: elementID) == .ordinary { return true }
        guard
            let item = runtime.prepareLazyListAccessibilityInvocationCompletion(
                token: completion.identity.token, in: completion.identity.container.witness,
                replacing: completion.item, target: completion.target, during: mutation),
            isLogicalInvocationCurrent(completion, elementID: elementID, in: runtime, during: mutation),
            let roots = runtime.realizedLazyListAccessibilityNodes(for: item),
            let projection = AccessibilityProjection.project(root: runtime.root),
            let node = completion.target.node, Self.isInsideLogicalRoots(node, roots: roots),
            projection.flattened().contains(where: { !$0.isVirtualizedPlaceholder && $0.sourceNode === node })
        else { return false }
        cacheLogicalItem(elementID, target: item, node: nil)
        bindLogicalItem(elementID, to: node)
        return isLogicalInvocationCurrent(completion, elementID: elementID, in: runtime, during: mutation)
            && runtime.realizedLazyListAccessibilityNodes(for: item) != nil
            && uiaLogicalItemState(elementID: elementID) == .ordinary
    }

    @inline(never)
    private func dispatchLogicalInvocation(
        elementID: UInt64, in runtime: RetainedViewRuntime, during mutation: RetainedAccessibilityMutation
    ) -> InvocationCompletion? {
        guard runtime.permitsRetainedActionInvocation,
            let identity = logicalIdentitiesByID[elementID],
            let node = retainedNode(for: elementID, in: runtime),
            let item = logicalItem(for: elementID, in: runtime),
            let target = runtime.accessibilityTarget(for: node),
            runtime.isAccessibilityTargetCurrent(target, during: mutation)
        else { return nil }
        defer { withExtendedLifetime(node) {} }
        guard AccessibilityProjection.invokeDefaultAction(on: node, in: runtime, intent: .invoke) else { return nil }
        return InvocationCompletion(
            identity: identity, item: item.target, target: target, mutationRevision: mutation.revision)
    }

    private func isLogicalInvocationCurrent(
        _ completion: InvocationCompletion, elementID: UInt64, in runtime: RetainedViewRuntime,
        during mutation: RetainedAccessibilityMutation
    ) -> Bool {
        guard let identity = logicalIdentitiesByID[elementID],
            identity.container === completion.identity.container, identity.token == completion.identity.token,
            runtime.isLazyListAccessibilityTokenCurrent(identity.token, in: completion.identity.container.witness),
            runtime.isAccessibilityTargetCurrent(completion.target, during: mutation)
        else { return false }
        return true
    }

    @inline(never)
    private func invokeDefaultAction(
        elementID: UInt64, in runtime: RetainedViewRuntime, intent: AccessibilityDefaultActionIntent
    ) -> Bool {
        guard runtime.permitsRetainedActionInvocation,
            let request = retainedNodeRequest(for: elementID, in: runtime), let node = request.node,
            request.isCurrent(in: runtime)
        else { return false }
        // Role, selection state, and the handler belong to one post-query
        // element. A pre-query predicate must not authorize a different role
        // or an obsolete selection transition after layout callbacks run.
        return AccessibilityProjection.invokeDefaultAction(
            on: node, in: runtime, intent: intent, selectedPath: request.selectedPath)
    }

    // MARK: - Focus event support

    /// Stable element id for the nearest projected element at or above
    /// `node`. Focus can land on a node that is not itself an accessibility
    /// element (e.g. a control's interactive root with no metadata); UIA
    /// focus events then target the nearest projected ancestor instead.
    func projectedElementID(forNodeOrAncestor node: ViewNode) -> UInt64? {
        guard let runtime else { return nil }
        defer { withExtendedLifetime(runtime) {} }
        let rootRequest: RetainedNodeRequest?
        if runtime.root.selectedContentRole != nil {
            guard let captured = retainedNodeRequest(for: UIAProviderBridge.rootElementID, in: runtime) else {
                return nil
            }
            rootRequest = captured
        } else {
            rootRequest = nil
        }
        guard let root = AccessibilityProjection.project(runtime: runtime) else { return nil }
        if let rootRequest {
            guard rootRequest.isCurrent(in: runtime), root.sourceNode === rootRequest.node else { return nil }
        }
        let flattened = root.flattened()
        var current: ViewNode? = node
        while let candidate = current {
            guard rootRequest?.isCurrent(in: runtime) != false else { return nil }
            if flattened.contains(where: { $0.sourceNode === candidate }) {
                if candidate === root.sourceNode {
                    return UIAProviderBridge.rootElementID
                }
                return stableID(for: candidate)
            }
            current = candidate.parent
        }
        return nil
    }

    // MARK: - Snapshot flattening

    /// Remember disclosure restrictions before logical refresh or bounds mapping
    /// can replace an editor. Projection identities retain neither nodes nor
    /// controllers, and only suppress this projection's already copied values.
    private static func capturePasswordElements(in root: AccessibilityElementProjection) -> Set<ObjectIdentifier> {
        var result: Set<ObjectIdentifier> = []
        for element in root.flattened() {
            if element.traits.contains(.isSecureTextInput)
                || (element.sourceNode?.textInputController as? any TextInputAccessibilityValueReplacing)?.isSecure
                    == true
            {
                result.insert(ObjectIdentifier(element))
            }
        }
        return result
    }

    private func appendSnapshots(
        for element: AccessibilityElementProjection,
        parentID: UInt64?,
        rootBounds: Rect,
        into list: inout [UIAElementSnapshot],
        runtime: RetainedViewRuntime,
        rootRequest: RetainedNodeRequest?,
        passwordElements: Set<ObjectIdentifier>,
        rootName: String? = nil,
        screenBoundsMapper: (Rect) throws -> Rect
    ) rethrows {
        guard rootRequest?.isCurrent(in: runtime) != false else { return }
        let id: UInt64
        if parentID == nil {
            id = UIAProviderBridge.rootElementID
        } else if let node = element.sourceNode {
            id = stableID(for: node)
        } else {
            // Projections always carry a source node; this is a defensive
            // fallback that keeps the tree navigable if one ever does not.
            id = nextEphemeralID()
        }

        let screenBounds = try screenBoundsMapper(element.bounds)
        guard rootRequest?.isCurrent(in: runtime) != false else { return }
        // Mapping may retire the original controller or install a secure one.
        // Neither change can downgrade protection of this copied projection.
        let isPassword =
            passwordElements.contains(ObjectIdentifier(element))
            || element.traits.contains(.isSecureTextInput)
            || (element.sourceNode?.textInputController as? any TextInputAccessibilityValueReplacing)?.isSecure == true
        let supportsValue = element.controlType == .edit && !isPassword
        let isSelected: Bool? = element.traits.contains(.isSelectable) ? element.isSelected : nil
        let hasWritableCapability: Bool
        if let node = element.sourceNode {
            hasWritableCapability = Self.isWritableValueNode(node)
        } else {
            hasWritableCapability = false
        }
        guard rootRequest?.isCurrent(in: runtime) != false else { return }

        list.append(
            UIAElementSnapshot(
                id: id,
                parentID: parentID,
                name: parentID == nil ? (rootName ?? element.name) : element.name,
                value: isPassword ? nil : element.value,
                helpText: element.hint,
                automationID: element.identifier,
                controlType: Self.controlTypeID(for: element.controlType),
                bounds: screenBounds,
                isEnabled: element.isEnabled,
                hasKeyboardFocus: element.isFocused,
                isKeyboardFocusable: element.sourceNode?.isFocusable ?? false,
                isOffscreen: element.isVirtualizedPlaceholder || screenBounds.intersected(with: rootBounds) == nil,
                hasDefaultAction: element.permitsModalActions
                    && (!element.actions.isEmpty || element.sourceNode?.onActivate != nil),
                isPassword: isPassword,
                supportsValue: supportsValue,
                isReadOnly: isPassword || !element.isEnabled || !hasWritableCapability,
                toggleState: element.controlType == .checkBox ? (element.isSelected ? .on : .off) : nil,
                isSelected: isSelected,
                isVirtualizedPlaceholder: element.isVirtualizedPlaceholder,
                supportsItemContainer: element.sourceNode.map {
                    element.permitsModalActions && $0.retainedLazyListAdapter != nil
                        && runtime.supportsLazyListAccessibilityItems(in: $0)
                } ?? false
            )
        )

        guard rootRequest?.isCurrent(in: runtime) != false else { return }
        for child in element.children {
            try appendSnapshots(
                for: child, parentID: id, rootBounds: rootBounds, into: &list,
                runtime: runtime, rootRequest: rootRequest, passwordElements: passwordElements,
                screenBoundsMapper: screenBoundsMapper)
        }
    }

    // MARK: - Stable element ids

    private func stableID(for node: ViewNode) -> UInt64 {
        let key = ObjectIdentifier(node)
        if let existing = idsByNode[key], nodesByID[existing]?.node === node {
            // A reused allocation address must not retarget an old UIA id.
            // Only the exact still-live node keeps its previous identity.
            return existing
        }
        let id = nextID
        precondition(id < Self.logicalIDBoundary)
        nextID += 1
        idsByNode[key] = id
        nodesByID[id] = WeakNode(node)
        return id
    }

    private func nextEphemeralID() -> UInt64 {
        let id = nextID
        precondition(id < Self.logicalIDBoundary)
        nextID += 1
        return id
    }

    private func pruneDeadNodes() {
        let deadIDs = nodesByID.filter { $0.value.node == nil }.map(\.key)
        guard !deadIDs.isEmpty else {
            return
        }
        for id in deadIDs {
            nodesByID.removeValue(forKey: id)
        }
        let liveIDs = Set(nodesByID.keys)
        idsByNode = idsByNode.filter { liveIDs.contains($0.value) }
    }

    // MARK: - Control type mapping

    /// `AccessibilityControlType` → UIA control type id (constants mirrored
    /// and static-asserted in CUIAInterop).
    static func controlTypeID(for controlType: AccessibilityControlType) -> Int32 {
        switch controlType {
        case .button: return Int32(SWU_UIA_CONTROL_TYPE_BUTTON)
        case .text: return Int32(SWU_UIA_CONTROL_TYPE_TEXT)
        case .edit: return Int32(SWU_UIA_CONTROL_TYPE_EDIT)
        case .checkBox: return Int32(SWU_UIA_CONTROL_TYPE_CHECK_BOX)
        case .header: return Int32(SWU_UIA_CONTROL_TYPE_HEADER)
        case .hyperlink: return Int32(SWU_UIA_CONTROL_TYPE_HYPERLINK)
        case .image: return Int32(SWU_UIA_CONTROL_TYPE_IMAGE)
        case .slider: return Int32(SWU_UIA_CONTROL_TYPE_SLIDER)
        case .progressBar: return Int32(SWU_UIA_CONTROL_TYPE_PROGRESS_BAR)
        case .list: return Int32(SWU_UIA_CONTROL_TYPE_LIST)
        case .listItem: return Int32(SWU_UIA_CONTROL_TYPE_LIST_ITEM)
        case .tab: return Int32(SWU_UIA_CONTROL_TYPE_TAB)
        case .tabItem: return Int32(SWU_UIA_CONTROL_TYPE_TAB_ITEM)
        case .group: return Int32(SWU_UIA_CONTROL_TYPE_GROUP)
        case .pane: return Int32(SWU_UIA_CONTROL_TYPE_PANE)
        case .window: return Int32(SWU_UIA_CONTROL_TYPE_WINDOW)
        case .custom: return Int32(SWU_UIA_CONTROL_TYPE_CUSTOM)
        }
    }
}

extension RuntimeUIAElementTreeSource: UIATextSnapshotSource {
    /// Only copied Core values and original weak witnesses leave the capture
    /// frame. In particular, neither a node nor a projection is retained here.
    private struct TextSnapshotCompletion {
        weak var runtime: RetainedViewRuntime?
        let target: RetainedAccessibilityTarget
        let snapshot: TextRangeSnapshot
    }

    func uiaTextSnapshot(elementID: UInt64) -> TextRangeSnapshot? {
        guard let completion = captureTextSnapshot(elementID: elementID) else { return nil }
        // The capture frame has returned and released its temporary runtime,
        // node, and projection references. Recheck the original weak path;
        // obtaining a replacement witness here would accept a new attachment.
        guard let runtime, runtime === completion.runtime,
            runtime.isAccessibilityTextReadTargetCurrent(completion.target),
            let currentText = completion.target.node?.text,
            currentText.utf16.elementsEqual(completion.snapshot.text.utf16)
        else { return nil }
        return completion.snapshot
    }

    @inline(never)
    private func captureTextSnapshot(elementID: UInt64) -> TextSnapshotCompletion? {
        // Do not reconstruct logical receipts, refresh identity metadata, or
        // realize a row. Some logical identities reuse a physical ID, so the
        // logical-identity table is checked as well as the reserved ID range.
        guard elementID < Self.logicalIDBoundary, logicalIdentitiesByID[elementID] == nil,
            let runtime,
            let node = elementID == UIAProviderBridge.rootElementID ? runtime.root : nodesByID[elementID]?.node,
            let target = runtime.accessibilityTarget(for: node),
            runtime.isAccessibilityTextReadTargetCurrent(target),
            let element = AccessibilityProjection.project(runtime: runtime)?.flattened().first(where: {
                $0.sourceNode === node
            }), element.controlType == .text, !element.isVirtualizedPlaceholder, element.permitsModalActions,
            let text = node.text, let snapshot = TextRangeSnapshot(text)
        else { return nil }
        return TextSnapshotCompletion(runtime: runtime, target: target, snapshot: snapshot)
    }
}

extension RuntimeUIAElementTreeSource: UIATextDocumentSource {
    /// All retained runtime/node references are weak, including both original
    /// paths. The separate content token is never reconstructed during a read.
    private final class TextDocumentAuthority: UIATextDocumentAuthority {
        weak var source: RuntimeUIAElementTreeSource?
        weak var runtime: RetainedViewRuntime?
        let elementID: UInt64
        let target: RetainedAccessibilityTarget
        let selectedPath: RetainedSelectedContentPath
        let contentIdentity: RetainedAccessibilityIdentity

        init(
            source: RuntimeUIAElementTreeSource, runtime: RetainedViewRuntime,
            elementID: UInt64, target: RetainedAccessibilityTarget,
            selectedPath: RetainedSelectedContentPath, contentIdentity: RetainedAccessibilityIdentity
        ) {
            self.source = source
            self.runtime = runtime
            self.elementID = elementID
            self.target = target
            self.selectedPath = selectedPath
            self.contentIdentity = contentIdentity
        }

        func isCurrent() -> Bool {
            // The projection's temporary strong captures are gone before the
            // final check of the same original physical/selection/content proof.
            guard projectionIsCurrent() else { return false }
            return originalWitnessesAreCurrent()
        }

        func matchesOriginalDocument(_ other: any UIATextDocumentAuthority) -> Bool {
            guard let other = other as? TextDocumentAuthority,
                isCurrent(), other.isCurrent(), matchesOriginalWitnesses(other)
            else { return false }
            // No strong source/runtime/node capture from the comparison frame
            // survives this final validation of both original weak paths.
            return isCurrent() && other.isCurrent() && isCurrent()
        }

        @inline(never)
        private func matchesOriginalWitnesses(_ other: TextDocumentAuthority) -> Bool {
            guard let source, let otherSource = other.source, source === otherSource,
                let runtime, let otherRuntime = other.runtime, runtime === otherRuntime,
                let node = target.node, let otherNode = other.target.node, node === otherNode,
                contentIdentity === other.contentIdentity
            else { return false }
            return true
        }

        private func originalWitnessesAreCurrent() -> Bool {
            guard let source, let runtime, source.runtime === runtime,
                source.logicalIdentitiesByID[elementID] == nil,
                runtime.isAccessibilityTextReadTargetCurrent(target), let node = target.node,
                selectedPath.physicalRoot === node, selectedPath.selectedNode === node,
                selectedPath.isInstalled(in: runtime), node.hasAccessibilityTextContentIdentity(contentIdentity)
            else { return false }
            if elementID == UIAProviderBridge.rootElementID { return node === runtime.root }
            return elementID < RuntimeUIAElementTreeSource.logicalIDBoundary
                && source.nodesByID[elementID]?.node === node
        }

        @inline(never)
        private func projectionIsCurrent() -> Bool {
            guard originalWitnessesAreCurrent(), let runtime, let node = target.node,
                let element = AccessibilityProjection.project(runtime: runtime)?.flattened().first(where: {
                    $0.sourceNode === node
                }), element.controlType == .text, !element.isVirtualizedPlaceholder, element.permitsModalActions
            else { return false }
            return true
        }
    }

    func uiaTextDocument(elementID: UInt64) -> UIATextDocument? {
        guard let document = captureTextDocument(elementID: elementID), document.isCurrent else { return nil }
        return document
    }

    @inline(never)
    private func captureTextDocument(elementID: UInt64) -> UIATextDocument? {
        guard elementID < Self.logicalIDBoundary, logicalIdentitiesByID[elementID] == nil,
            let runtime,
            let node = elementID == UIAProviderBridge.rootElementID ? runtime.root : nodesByID[elementID]?.node,
            let target = runtime.accessibilityTarget(for: node),
            runtime.isAccessibilityTextReadTargetCurrent(target),
            let selectedPath = node.captureSelectedContentPath(in: runtime),
            selectedPath.physicalRoot === node, selectedPath.selectedNode === node,
            selectedPath.isInstalled(in: runtime),
            let text = node.text, let snapshot = TextRangeSnapshot(text)
        else { return nil }
        let authority = TextDocumentAuthority(
            source: self, runtime: runtime, elementID: elementID, target: target,
            selectedPath: selectedPath, contentIdentity: node.captureAccessibilityTextContentIdentity())
        return UIATextDocument(snapshot: snapshot, authority: authority)
    }
}
