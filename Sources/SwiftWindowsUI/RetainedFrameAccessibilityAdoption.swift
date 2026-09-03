/// Keeps frame semantics unavailable while reconciliation can call application
/// code. Declarations are mapped from the original source nodes, never inferred
/// from the child array left behind by a failed or reentrant update.
@MainActor
final class RetainedFrameAccessibilityAdoption {
    @MainActor
    private final class Witness {
        weak var node: ViewNode?
        let declaration: ObjectIdentifier?
        var viewIdentity: RetainedLazyListViewIdentityProof

        init(_ node: ViewNode) {
            self.node = node
            declaration = node.accessibilityDeclaredFrameContent.map(ObjectIdentifier.init)
            viewIdentity = node.captureLazyListIdentityProof()
        }
    }

    @MainActor
    private struct Mapping {
        let source: Witness
        weak var target: ViewNode?
    }

    private let identity = RetainedAccessibilityIdentity()
    private var witnesses: [ObjectIdentifier: Witness] = [:]
    private var sourceIDs: Set<ObjectIdentifier> = []
    private var mappings: [ObjectIdentifier: Mapping] = [:]
    private var targetSources: [ObjectIdentifier: ObjectIdentifier] = [:]
    private var publicationRoots: [Witness] = []
    private var isValid = true
    private var isFinished = false

    init?(retainedRoots: [ViewNode], sourceRoots: [ViewNode]) {
        guard let retained = Self.nodes(in: retainedRoots), let sources = Self.nodes(in: sourceRoots) else {
            isValid = false
            return
        }
        // An inner direct adoption also suspends the frame that declares it.
        // These ancestors retain their original declaration unless they are an
        // explicit source/target pair in this reconciliation.
        var ancestors: [ViewNode] = []
        var seenAncestors = Set<ObjectIdentifier>()
        for root in retainedRoots + sourceRoots {
            var ancestor = root.parent
            var depth = 0
            while let node = ancestor, depth < ViewNode.maximumTraversalDepth,
                seenAncestors.insert(ObjectIdentifier(node)).inserted
            {
                if node.accessibilityDeclaredFrameContent != nil { ancestors.append(node) }
                ancestor = node.parent
                depth += 1
            }
        }
        let nodes = retained + sources + ancestors
        guard
            nodes.contains(where: {
                $0.accessibilityDeclaredFrameContent != nil || $0.accessibilitySemanticElement != nil
                    || $0.accessibilityFrameUpdateIdentity != nil
            })
        else { return nil }
        sourceIDs = Set(sources.map(ObjectIdentifier.init))
        for node in nodes {
            let key = ObjectIdentifier(node)
            if witnesses[key] == nil { witnesses[key] = Witness(node) }
        }
        var rootIDs = Set<ObjectIdentifier>()
        for node in retainedRoots + ancestors where rootIDs.insert(ObjectIdentifier(node)).inserted {
            if let witness = witnesses[ObjectIdentifier(node)] { publicationRoots.append(witness) }
        }
        // No callback or payload release occurs between capturing the original
        // declarations and installing this scope on the whole affected cohort.
        for witness in witnesses.values {
            guard let node = witness.node else { continue }
            node.accessibilityFrameUpdateIdentity = identity
            node.suspendAccessibilityFramePublication()
        }
    }

    var isCurrent: Bool {
        guard !isFinished, isValid else { return false }
        for (key, witness) in witnesses {
            // A departing or discarded source can expire after its existing
            // cleanup. It cannot supply a target or a new declaration mapping.
            guard let node = witness.node else {
                if targetSources[key] != nil { return false }
                continue
            }
            guard node.accessibilityFrameUpdateIdentity === identity, witness.viewIdentity.isCurrent
            else { return false }
            if sourceIDs.contains(key),
                node.accessibilityDeclaredFrameContent.map(ObjectIdentifier.init) != witness.declaration
            {
                return false
            }
        }
        return true
    }

    /// Only the reconciler's original checked property write can advance this
    /// one witness. The outgoing value is still pinned, so no destructor has run.
    func recordIdentityWrite(on node: ViewNode) {
        guard !isFinished, isValid, node.accessibilityFrameUpdateIdentity === identity,
            let witness = witnesses[ObjectIdentifier(node)], witness.node === node
        else {
            isValid = false
            return
        }
        witness.viewIdentity = node.captureLazyListIdentityProof()
    }

    /// The actual scalar copy is performed by ComponentHost.copyNodeProperty,
    /// preserving the existing property journal and native admission checks.
    func copyIntent(from source: ViewNode, to target: ViewNode) -> Bool {
        guard isCurrent, witnesses[ObjectIdentifier(source)]?.node === source,
            witnesses[ObjectIdentifier(target)]?.node === target
        else {
            isValid = false
            return false
        }
        return true
    }

    @discardableResult
    func record(source: ViewNode, target: ViewNode) -> Bool {
        guard copyIntent(from: source, to: target), let witness = witnesses[ObjectIdentifier(source)] else {
            return false
        }
        let sourceID = ObjectIdentifier(source)
        let targetID = ObjectIdentifier(target)
        if let existing = mappings[sourceID], existing.target !== target {
            isValid = false
            return false
        }
        if let existing = targetSources[targetID], existing != sourceID {
            isValid = false
            return false
        }
        mappings[sourceID] = Mapping(source: witness, target: target)
        targetSources[targetID] = sourceID
        return true
    }

    func recordUnchangedSubtree(_ root: ViewNode) -> Bool {
        guard let nodes = Self.nodes(in: [root]) else {
            isValid = false
            return false
        }
        for node in nodes {
            guard record(source: node, target: node) else { return false }
        }
        return isCurrent
    }

    /// Called only after the existing Button cleanup has accepted the complete
    /// adoption. This final section performs native writes and no callbacks.
    func finish(
        completed: Bool, check: ComponentHost.NodeReconcileAdmission,
        completion: RetainedLazyListAdoptionCompletion?
    ) -> Bool {
        guard !isFinished else { return false }
        guard completed, isCurrent, check.isCurrentAfterAcceptedButtonCleanup, completion?.isCurrent == true else {
            isFinished = true
            return false
        }
        var declarations: [(ViewNode, ViewNode?)] = []
        for mapping in mappings.values {
            guard let target = mapping.target else {
                isFinished = true
                return false
            }
            if let contentID = mapping.source.declaration {
                guard let content = mappings[contentID]?.target, content.parent === target,
                    target.children.contains(where: { $0 === content })
                else {
                    isFinished = true
                    return false
                }
                declarations.append((target, content))
            } else {
                declarations.append((target, nil))
            }
        }
        // Preflight every mapping before changing one declaration. In
        // particular, never install a detached candidate child on a survivor.
        guard isCurrent, check.isCurrentAfterAcceptedButtonCleanup, completion?.isCurrent == true else {
            isFinished = true
            return false
        }
        for (target, content) in declarations {
            target.replaceAccessibilityFrameDeclaration(content: content)
        }
        for witness in witnesses.values {
            if let node = witness.node, node.accessibilityFrameUpdateIdentity === identity {
                node.accessibilityFrameUpdateIdentity = nil
            }
        }
        isFinished = true
        for root in publicationRoots {
            root.node?.publishAccessibilityFrameSubtree()
        }
        return true
    }

    private static func nodes(in roots: [ViewNode]) -> [ViewNode]? {
        var result: [ViewNode] = []
        var seen = Set<ObjectIdentifier>()
        var pending = roots.map { ($0, 0) }
        while let (node, depth) = pending.popLast() {
            guard depth <= ViewNode.maximumTraversalDepth else { return nil }
            guard seen.insert(ObjectIdentifier(node)).inserted else { continue }
            result.append(node)
            pending.append(contentsOf: node.children.map { ($0, depth + 1) })
        }
        return result
    }
}
