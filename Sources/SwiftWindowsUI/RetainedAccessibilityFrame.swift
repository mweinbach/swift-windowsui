import SwiftWindowsCore

/// A factory names its actual layout operand. This is never inferred from a
/// descendant's role, label, or the current number of children.
@MainActor
final class RetainedAccessibilityFrameContent {
    weak var node: ViewNode?
    init(_ node: ViewNode) { self.node = node }
}

@MainActor
final class RetainedAccessibilityFrameIntentStorage {
    var value: RetainedFrameAccessibilityIntent
    init(_ value: RetainedFrameAccessibilityIntent) { self.value = value }
}

package enum RetainedAccessibilityFrameProjectionRole: Equatable {
    case ordinary
    case transparent
    case unavailable
}

@MainActor
final class RetainedAccessibilityFramePublication {
    let metadata: RetainedAccessibilitySemanticMetadata
    private(set) var isCurrent = true

    init(metadata: RetainedAccessibilitySemanticMetadata) { self.metadata = metadata }
    func revoke() { isCurrent = false }
}

/// Durable physical element identity. Metadata publications and action payload
/// revisions can change without replacing this identity. Every node is weak;
/// a saved provider does not keep a discarded factory or controller alive.
@MainActor
package final class RetainedAccessibilitySemanticElement {
    private struct Link {
        weak var node: ViewNode?
        weak var declaredContent: ViewNode?
        let wasFrame: Bool
        let selectedRole: RetainedSelectedContentRole?
    }
    private struct SelectedOwner {
        weak var node: ViewNode?
        weak var selected: ViewNode?
        let role: RetainedSelectedContentRole
    }

    private weak var runtime: RetainedViewRuntime?
    private let attachment: RetainedAccessibilityTarget
    private let links: [Link]
    private let selectedOwners: [SelectedOwner]
    private var isRetired = false
    private var publication: RetainedAccessibilityFramePublication?
    private var lastAcceptedTraits: RetainedAccessibilityTraits = []
    package private(set) weak var semanticNode: ViewNode?

    init?(nodes: [ViewNode], runtime: RetainedViewRuntime) {
        guard let semantic = nodes.last, let attachment = runtime.accessibilityTarget(for: semantic) else { return nil }
        self.runtime = runtime
        self.attachment = attachment
        self.semanticNode = semantic
        self.links = nodes.enumerated().map { index, node in
            Link(
                node: node, declaredContent: index + 1 < nodes.count ? nodes[index + 1] : nil,
                wasFrame: index + 1 < nodes.count && node.selectedContentRole == nil,
                selectedRole: index + 1 < nodes.count ? node.selectedContentRole : nil)
        }
        var owners: [SelectedOwner] = []
        var ancestry = Set<ObjectIdentifier>()
        var current: ViewNode? = semantic
        while let node = current, ancestry.count < ViewNode.maximumTraversalDepth {
            guard ancestry.insert(ObjectIdentifier(node)).inserted else { return nil }
            if let role = node.selectedContentRole {
                guard let path = node.captureSelectedContentPath(in: runtime), path.isInstalled(in: runtime),
                    let selected = path.selectedNode, ancestry.contains(ObjectIdentifier(selected))
                else { return nil }
                owners.append(SelectedOwner(node: node, selected: selected, role: role))
            }
            if node === runtime.root { break }
            current = node.parent
        }
        self.selectedOwners = owners
    }

    package func isStructurallyCurrent(in runtime: RetainedViewRuntime) -> Bool {
        guard !isRetired, self.runtime === runtime,
            runtime.isAccessibilityAttachmentCurrent(attachment), semanticNode === links.last?.node
        else { return false }
        for link in links {
            guard let node = link.node, node.accessibilitySemanticElement === self else { return false }
            if link.wasFrame {
                guard !node.hasAccessibilityFrameBoundary, let content = link.declaredContent,
                    node.accessibilityDeclaredFrameContent === content, content.parent === node,
                    node.children.contains(where: { $0 === content })
                else { return false }
            } else if let role = link.selectedRole {
                guard node.selectedContentRole == role, let content = link.declaredContent,
                    node.children.count == 1, node.children.first === content, content.parent === node
                else { return false }
            }
        }
        return true
    }

    package var isAvailable: Bool {
        guard let runtime, isStructurallyCurrent(in: runtime), publication?.isCurrent == true else { return false }
        return links.allSatisfy { $0.node?.accessibilityFrameUpdateIdentity == nil }
    }

    func matches(_ nodes: [ViewNode]) -> Bool {
        guard nodes.count == links.count else { return false }
        return zip(nodes, links).allSatisfy { $0.0 === $0.1.node }
    }

    func contains(_ node: ViewNode) -> Bool { links.contains { $0.node === node } }
    func isSelectedHop(_ node: ViewNode) -> Bool {
        links.contains { $0.node === node && $0.selectedRole != nil }
    }

    func retire() {
        isRetired = true
        suspendPublication()
    }

    func suspendPublication() {
        publication?.revoke()
        publication = nil
        runtime?.invalidateAccessibilityFrameModalCandidates()
    }

    func publish() {
        guard let runtime, isStructurallyCurrent(in: runtime), let semanticNode,
            links.allSatisfy({
                $0.node?.accessibilityFrameUpdateIdentity == nil
                    && $0.node?.accessibilityFrameMetadataMutationDepth == 0
            })
        else { return }
        var metadata = RetainedAccessibilitySemanticMetadata(node: semanticNode)
        for link in links.dropLast().reversed() where link.wasFrame {
            guard let frame = link.node else { return }
            metadata = frame.accessibilityFrameIntent.applying(to: metadata)
        }
        publication?.revoke()
        publication = RetainedAccessibilityFramePublication(metadata: metadata)
        lastAcceptedTraits = metadata.traits
        runtime.invalidateAccessibilityFrameModalCandidates()
    }

    var metadata: RetainedAccessibilitySemanticMetadata? { isAvailable ? publication?.metadata : nil }

    /// Suspending a publication cannot admit an outside action by erasing the
    /// last accepted modal restriction during cleanup. This scalar grants no
    /// action or disclosure authority and changes only at accepted publication.
    var modalTraits: RetainedAccessibilityTraits { lastAcceptedTraits }

    func request() -> RetainedAccessibilitySemanticRequest? {
        guard isAvailable, let publication, let runtime else { return nil }
        var selectedPaths: [RetainedSelectedContentPath] = []
        for owner in selectedOwners {
            guard let node = owner.node, node.selectedContentRole == owner.role,
                let path = node.captureSelectedContentPath(in: runtime), path.isInstalled(in: runtime),
                path.selectedNode === owner.selected
            else { return nil }
            selectedPaths.append(path)
        }
        var actions: [RetainedAccessibilitySemanticAction] = []
        for link in links.reversed() where link.selectedRole == nil {
            guard let owner = link.node else { return nil }
            let count = owner.accessibilityActions.count
            guard count > 0 else { continue }
            guard let mutation = owner.accessibilityActionMutationIdentity else { return nil }
            for index in 0..<count {
                let action = owner.accessibilityActions[index]
                actions.append(
                    RetainedAccessibilitySemanticAction(
                        owner: owner, element: self, index: index, count: count,
                        name: action.name, kind: action.kind, mutation: mutation))
            }
        }
        return RetainedAccessibilitySemanticRequest(
            element: self, publication: publication, actions: actions, selectedPaths: selectedPaths)
    }

    fileprivate func isCurrent(_ publication: RetainedAccessibilityFramePublication) -> Bool {
        isAvailable && self.publication === publication && publication.isCurrent
    }
}

/// One accepted metadata and operation read. This is not an eligibility grant:
/// callers retain the existing layout, focus, controller, modal and role guards.
@MainActor
package struct RetainedAccessibilitySemanticRequest {
    package let element: RetainedAccessibilitySemanticElement
    private let publication: RetainedAccessibilityFramePublication
    private let selectedPaths: [RetainedSelectedContentPath]
    package let metadata: RetainedAccessibilitySemanticMetadata
    package let actions: [RetainedAccessibilitySemanticAction]
    package var semanticNode: ViewNode? { element.semanticNode }

    fileprivate init(
        element: RetainedAccessibilitySemanticElement, publication: RetainedAccessibilityFramePublication,
        actions: [RetainedAccessibilitySemanticAction], selectedPaths: [RetainedSelectedContentPath]
    ) {
        self.element = element
        self.publication = publication
        self.metadata = publication.metadata
        self.actions = actions
        self.selectedPaths = selectedPaths
    }

    package var isCurrent: Bool {
        element.isCurrent(publication) && selectedPaths.allSatisfy(\.isCurrent)
    }
    package func isCurrent(in runtime: RetainedViewRuntime) -> Bool {
        isCurrent && element.isStructurallyCurrent(in: runtime)
    }
    package func isStructurallyCurrent(in runtime: RetainedViewRuntime) -> Bool {
        element.isStructurallyCurrent(in: runtime) && element.isAvailable
            && selectedPaths.allSatisfy { $0.isCurrent && $0.isInstalled(in: runtime) }
    }
    package func isSelectedContentHop(_ node: ViewNode) -> Bool { element.isSelectedHop(node) }
    package func containsPhysicalNode(_ node: ViewNode?) -> Bool {
        guard let node else { return false }
        return element.contains(node)
    }
}

/// Explicit action provenance, without a copied handler. Array replacement
/// invalidates the original witness even when every visible slot is identical.
@MainActor
package struct RetainedAccessibilitySemanticAction {
    package private(set) weak var owner: ViewNode?
    private weak var element: RetainedAccessibilitySemanticElement?
    package let index: Int
    package let count: Int
    package let name: String?
    package let kind: RetainedAccessibilityActionKind?
    private let mutation: RetainedAccessibilityIdentity

    fileprivate init(
        owner: ViewNode, element: RetainedAccessibilitySemanticElement, index: Int, count: Int,
        name: String?, kind: RetainedAccessibilityActionKind?, mutation: RetainedAccessibilityIdentity
    ) {
        self.owner = owner
        self.element = element
        self.index = index
        self.count = count
        self.name = name
        self.kind = kind
        self.mutation = mutation
    }

    package var isCurrent: Bool {
        guard let owner, element?.isAvailable == true,
            owner.accessibilityActionMutationIdentity === mutation,
            owner.accessibilityActions.count == count, owner.accessibilityActions.indices.contains(index)
        else { return false }
        let action = owner.accessibilityActions[index]
        return action.name == name && action.kind == kind
    }

    package func invokeIfCurrent() -> Bool {
        guard isCurrent, let owner else { return false }
        let action = owner.accessibilityActions[index]
        action.handler()
        return true
    }
}

extension ViewNode {
    package var accessibilityDeclaredFrameContent: ViewNode? { accessibilityFrameContentStorage?.node }

    package func declareAccessibilityFrameContent(_ content: ViewNode) {
        replaceAccessibilityFrameDeclaration(content: content)
    }

    func replaceAccessibilityFrameDeclaration(content: ViewNode?) {
        guard accessibilityDeclaredFrameContent !== content else { return }
        accessibilitySemanticElement?.retire()
        accessibilityFrameContentStorage = content.map(RetainedAccessibilityFrameContent.init)
    }

    package func recordAccessibilityFrameOverride<Value>(
        _ keyPath: WritableKeyPath<RetainedFrameAccessibilityIntent, RetainedAccessibilityOverride<Value>>, value: Value
    ) {
        guard accessibilityFrameContentStorage != nil else { return }
        accessibilityFrameIntent[keyPath: keyPath] = .set(value)
        if accessibilityFrameUpdateIdentity == nil { accessibilitySemanticElement?.publish() }
    }

    package func recordAccessibilityFrameTraits(adding traits: RetainedAccessibilityTraits) {
        guard accessibilityFrameContentStorage != nil else { return }
        accessibilityFrameIntent.addTraits(traits)
        if accessibilityFrameUpdateIdentity == nil { accessibilitySemanticElement?.publish() }
    }

    package func recordAccessibilityFrameTraits(removing traits: RetainedAccessibilityTraits) {
        guard accessibilityFrameContentStorage != nil else { return }
        accessibilityFrameIntent.removeTraits(traits)
        if accessibilityFrameUpdateIdentity == nil { accessibilitySemanticElement?.publish() }
    }

    var hasAccessibilityFrameBoundary: Bool {
        accessibilityChildBehavior != nil || accessibilityRepresentationChildren != nil
    }

    package var isAccessibilityFrameWindowEndpoint: Bool {
        retainedLazyListRuntime?.root === self && accessibilityFrameContentStorage != nil
            && !hasAccessibilityFrameBoundary
    }

    package var accessibilityFrameProjectionRole: RetainedAccessibilityFrameProjectionRole {
        if accessibilityFrameUpdateIdentity != nil { return .unavailable }
        if let element = accessibilitySemanticElement, !element.isAvailable { return .unavailable }
        guard accessibilityFrameContentStorage != nil, !hasAccessibilityFrameBoundary else { return .ordinary }
        // Detached factory data has not acquired a retained association. Preserve
        // ordinary detached projection; installed/revoked data cannot fall back.
        guard retainedLazyListRuntime != nil else {
            return accessibilitySemanticElement == nil ? .ordinary : .unavailable
        }
        return currentAccessibilitySemanticRequest != nil ? .transparent : .unavailable
    }

    package var currentAccessibilitySemanticRequest: RetainedAccessibilitySemanticRequest? {
        guard accessibilityFrameUpdateIdentity == nil else { return nil }
        return accessibilitySemanticElement?.request()
    }

    package var effectiveAccessibilityMetadata: RetainedAccessibilitySemanticMetadata? {
        guard accessibilityFrameUpdateIdentity == nil else { return nil }
        if let element = accessibilitySemanticElement { return element.metadata }
        if accessibilityFrameContentStorage != nil, !hasAccessibilityFrameBoundary, retainedLazyListRuntime != nil {
            return nil
        }
        return RetainedAccessibilitySemanticMetadata(node: self)
    }

    package var effectiveAccessibilityIsHidden: Bool {
        if accessibilitySemanticElement == nil && accessibilityFrameUpdateIdentity == nil {
            return isAccessibilityHidden
        }
        return effectiveAccessibilityMetadata?.isHidden ?? true
    }
    package var effectiveAccessibilityRespondsToUserInteraction: Bool? {
        if accessibilitySemanticElement == nil && accessibilityFrameUpdateIdentity == nil {
            return accessibilityRespondsToUserInteraction
        }
        guard let metadata = effectiveAccessibilityMetadata else { return false }
        return metadata.respondsToUserInteraction
    }
    package var effectiveAccessibilityTraits: RetainedAccessibilityTraits {
        if accessibilitySemanticElement == nil && accessibilityFrameUpdateIdentity == nil { return accessibilityTraits }
        return effectiveAccessibilityMetadata?.traits ?? []
    }

    /// AX trait modality belongs to the terminal semantic owner, not each
    /// physical frame. Blocking presentation chrome remains on its real node.
    var accessibilityFrameModalTraits: RetainedAccessibilityTraits {
        if let element = accessibilitySemanticElement {
            return element.semanticNode === self ? element.modalTraits : []
        }
        return accessibilityTraits
    }

    func suspendAccessibilityFramePublication() { accessibilitySemanticElement?.suspendPublication() }

    func beginAccessibilityFrameMetadataMutation() {
        guard accessibilitySemanticElement != nil else { return }
        if accessibilityFrameMetadataMutationDepth == 0 {
            accessibilityFrameMetadataMutationElement = accessibilitySemanticElement
        }
        accessibilityFrameMetadataMutationDepth += 1
        accessibilitySemanticElement?.suspendPublication()
    }

    func endAccessibilityFrameMetadataMutation() {
        guard accessibilityFrameMetadataMutationDepth > 0 else { return }
        accessibilityFrameMetadataMutationDepth -= 1
        guard accessibilityFrameMetadataMutationDepth == 0 else { return }
        let original = accessibilityFrameMetadataMutationElement
        accessibilityFrameMetadataMutationElement = nil
        guard accessibilityFrameUpdateIdentity == nil, original === accessibilitySemanticElement else { return }
        original?.publish()
    }

    func retireAccessibilityFrameStructure() { accessibilitySemanticElement?.retire() }

    /// Selection hops are recognized only through their factory role and exact
    /// native path. They can connect two declared frames, never an arbitrary group.
    private func highestDeclaredAccessibilityFrameOwner() -> ViewNode {
        var current = self
        var owner = self
        var seen = Set<ObjectIdentifier>()
        while let parent = current.parent, seen.count < Self.maximumTraversalDepth,
            seen.insert(ObjectIdentifier(parent)).inserted
        {
            if parent.accessibilityDeclaredFrameContent === current && !parent.hasAccessibilityFrameBoundary {
                owner = parent
                current = parent
            } else if parent.selectedContentRole != nil, let runtime = parent.retainedLazyListRuntime,
                let path = parent.captureSelectedContentPath(in: runtime), path.isInstalled(in: runtime),
                path.nextPhysicalChild === current
            {
                current = parent
            } else {
                break
            }
        }
        return owner
    }

    /// A native attachment/accepted reconciliation publication, never a getter.
    /// Walk only explicit declarations; physical layout and parentage stay intact.
    func publishAccessibilityFrameSubtree() {
        guard let runtime = retainedLazyListRuntime else { return }
        let publicationRoot = highestDeclaredAccessibilityFrameOwner()
        var work: [(ViewNode, Int)] = [(publicationRoot, 0)]
        var seen = Set<ObjectIdentifier>()
        var nodes: [ViewNode] = []
        while let (node, depth) = work.popLast() {
            guard depth < Self.maximumTraversalDepth, seen.insert(ObjectIdentifier(node)).inserted else { continue }
            nodes.append(node)
            for child in node.children { work.append((child, depth + 1)) }
        }
        // Only this explicit publication boundary clears a retired association.
        // Getters continue to refuse it; old providers retain its retired identity.
        for node in nodes where node.accessibilityFrameUpdateIdentity == nil {
            if let element = node.accessibilitySemanticElement, !element.isStructurallyCurrent(in: runtime) {
                element.retire()
                node.accessibilitySemanticElement = nil
            }
        }
        for node in nodes {
            guard node.accessibilityFrameUpdateIdentity == nil,
                node.accessibilityFrameContentStorage != nil, !node.hasAccessibilityFrameBoundary
            else { continue }
            guard node.highestDeclaredAccessibilityFrameOwner() === node else { continue }
            var chain: [ViewNode] = [node]
            var cursor = node
            var valid = true
            while true {
                let content: ViewNode
                if cursor.accessibilityFrameContentStorage != nil && !cursor.hasAccessibilityFrameBoundary {
                    guard let declared = cursor.accessibilityDeclaredFrameContent, declared.parent === cursor,
                        cursor.children.contains(where: { $0 === declared })
                    else {
                        valid = false
                        break
                    }
                    content = declared
                } else if cursor.selectedContentRole != nil {
                    // A declared selection supplies its own immutable current
                    // path. Ordinary groups never receive this transparent role.
                    guard let path = cursor.captureSelectedContentPath(in: runtime), path.isInstalled(in: runtime),
                        let selectedChild = path.nextPhysicalChild
                    else {
                        valid = false
                        break
                    }
                    content = selectedChild
                } else {
                    break
                }
                guard chain.count < Self.maximumTraversalDepth, !chain.contains(where: { $0 === content })
                else {
                    valid = false
                    break
                }
                chain.append(content)
                cursor = content
            }
            guard valid,
                chain.allSatisfy({
                    $0.retainedLazyListRuntime === runtime
                        && $0.accessibilityFrameUpdateIdentity == nil
                })
            else { continue }
            let element: RetainedAccessibilitySemanticElement
            if let existing = node.accessibilitySemanticElement, existing.matches(chain),
                existing.isStructurallyCurrent(in: runtime)
            {
                element = existing
            } else {
                for member in chain { member.accessibilitySemanticElement?.retire() }
                guard let fresh = RetainedAccessibilitySemanticElement(nodes: chain, runtime: runtime) else { continue }
                element = fresh
                for member in chain { member.accessibilitySemanticElement = element }
            }
            element.publish()
        }
    }
}

extension RetainedViewRuntime {
    /// Stored metadata inspection only. Hidden and noninteractive elements may
    /// be inspected; no layout, binding getter or capability admission occurs.
    package func accessibilitySemanticRequest(for node: ViewNode) -> RetainedAccessibilitySemanticRequest? {
        guard let request = node.currentAccessibilitySemanticRequest, request.isCurrent(in: self) else { return nil }
        return request
    }
}
