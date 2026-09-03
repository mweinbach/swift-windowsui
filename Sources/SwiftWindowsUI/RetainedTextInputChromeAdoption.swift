import SwiftWindowsCore
import SwiftWindowsGraphics
import SwiftWindowsLayout

/// Construction data for the built-in single-line field, never authored nodes.
package struct RetainedTextInputChromeRecipe {
    package enum Segment {
        case text(String, style: PixelTextStyle, background: Color?)
        case caret(Size, Color)
        case selectionTail(Size, Color)
    }

    package let rows: [[Segment]]
    package init(rows: [[Segment]]) { self.rows = rows }
}

@MainActor
fileprivate final class ChromeNodeWitness {
    weak var node: ViewNode?
    let identifier: ObjectIdentifier
    var attachment: RetainedLazyListAttachmentProof
    let identity: RetainedLazyListViewIdentityProof
    let children: [ObjectIdentifier]

    init(_ node: ViewNode) {
        self.node = node
        identifier = ObjectIdentifier(node)
        attachment = node.captureLazyListAttachmentProof()
        identity = node.captureLazyListIdentityProof()
        children = node.children.map(ObjectIdentifier.init)
    }

    var isCurrent: Bool { node != nil && attachment.isCurrent && identity.isCurrent }

    var hasOriginalChildren: Bool {
        guard let node, node.children.count == children.count else { return false }
        return zip(node.children, children).allSatisfy { ObjectIdentifier($0.0) == $0.1 }
    }

    var hasCurrentEdge: Bool {
        guard isCurrent, let node else { return false }
        return node.parent.map { parent in parent.children.contains { $0 === node } } ?? true
    }
}

@MainActor
private func chromeCensus(_ roots: [ViewNode]) -> [ObjectIdentifier: ChromeNodeWitness]? {
    var result: [ObjectIdentifier: ChromeNodeWitness] = [:]
    var work = roots.map { ($0, 0) }
    while let (node, depth) = work.popLast() {
        guard depth < ViewNode.maximumTraversalDepth else { return nil }
        let key = ObjectIdentifier(node)
        guard result[key] == nil else { return nil }
        result[key] = ChromeNodeWitness(node)
        for child in node.children {
            guard child.parent === node else { return nil }
            work.append((child, depth + 1))
        }
    }
    return result
}

@MainActor
private func chromeAncestors(of node: ViewNode) -> [ChromeNodeWitness]? {
    var result: [ChromeNodeWitness] = []
    var seen: Set<ObjectIdentifier> = [ObjectIdentifier(node)]
    var parent = node.parent
    while let current = parent {
        guard result.count < ViewNode.maximumTraversalDepth,
            seen.insert(ObjectIdentifier(current)).inserted
        else { return nil }
        let witness = ChromeNodeWitness(current)
        guard witness.hasCurrentEdge else { return nil }
        result.append(witness)
        parent = current.parent
    }
    return result
}

/// Weak cache evidence only. It cannot arm an adoption or advance its proofs.
@MainActor
package final class RetainedTextInputChromeCache {
    private weak var root: ViewNode?
    private weak var field: ViewNode?
    private weak var controller: (any RetainedTextInputController)?
    private let fieldAttachment: RetainedLazyListAttachmentProof
    private let fieldIdentity: RetainedLazyListViewIdentityProof
    private let children: [ObjectIdentifier]
    private let forest: [ChromeNodeWitness]

    package init?(root: ViewNode, field: ViewNode, controller: any RetainedTextInputController) {
        guard field.textInputController === controller, root.parent === field,
            field.children.contains(where: { $0 === root }), !root.isHidden,
            let census = chromeCensus([root])
        else { return nil }
        self.root = root
        self.field = field
        self.controller = controller
        fieldAttachment = field.captureLazyListAttachmentProof()
        fieldIdentity = field.captureLazyListIdentityProof()
        children = field.children.map(ObjectIdentifier.init)
        forest = Array(census.values)
    }

    fileprivate init(
        root: ViewNode, field: ViewNode, controller: any RetainedTextInputController,
        fieldWitness: ChromeNodeWitness, forest: [ChromeNodeWitness], children: [ObjectIdentifier]
    ) {
        self.root = root
        self.field = field
        self.controller = controller
        fieldAttachment = fieldWitness.attachment
        fieldIdentity = fieldWitness.identity
        self.children = children
        self.forest = forest
    }

    package var isCurrent: Bool {
        guard let root, let field, let controller, field.textInputController === controller,
            fieldAttachment.isCurrent, fieldIdentity.isCurrent, root.parent === field, !root.isHidden,
            field.children.count == children.count,
            zip(field.children, children).allSatisfy({ ObjectIdentifier($0.0) == $0.1 })
        else { return false }
        return forest.allSatisfy { $0.isCurrent && $0.hasOriginalChildren }
    }
}

/// A scalar acknowledgment plus weak observations, never a node/closure handoff.
@MainActor
package final class RetainedTextInputChromeInstallation {
    package fileprivate(set) var isAcknowledged = false
    package fileprivate(set) var cacheObservation: RetainedTextInputChromeCache?
    package var isCurrent: Bool { isAcknowledged && cacheObservation?.isCurrent == true }
}

@MainActor
package final class RetainedTextInputChromeRegistration {
    fileprivate weak var source: ViewNode?
    fileprivate weak var controller: (any RetainedTextInputController)?
    fileprivate weak var label: ViewNode?
    fileprivate let text: String
    fileprivate let style: PixelTextStyle
    fileprivate weak var attempt: ChromeAdoptionAttempt?
    fileprivate var wasClaimed = false

    package init(
        source: ViewNode, controller: any RetainedTextInputController, label: ViewNode,
        text: String, style: PixelTextStyle
    ) {
        self.source = source
        self.controller = controller
        self.label = label
        self.text = text
        self.style = style
    }

    package func stage(recipe: RetainedTextInputChromeRecipe) -> RetainedTextInputChromeInstallation? {
        guard let attempt, attempt.registration === self, attempt.canStage,
            let contribution = RetainedTextInputChromeContribution(attempt: attempt, recipe: recipe)
        else { return nil }
        attempt.contribution = contribution
        return contribution.installation
    }
}

@MainActor
fileprivate final class ChromeAdoptionAttempt {
    weak var scope: RetainedTextInputChromeAdoptionScope?
    weak var registration: RetainedTextInputChromeRegistration?
    let source: ChromeNodeWitness
    let label: ChromeNodeWitness
    let sourceAncestors: [ChromeNodeWitness]
    var target: ChromeNodeWitness?
    var targetAncestors: [ChromeNodeWitness] = []
    var originalTargetChildren: [ChromeNodeWitness] = []
    var contribution: RetainedTextInputChromeContribution?
    var wasBound = false
    var wasRefused = false
    var isClosed = false

    init?(
        registration: RetainedTextInputChromeRegistration,
        source: ChromeNodeWitness, sourceCensus: [ObjectIdentifier: ChromeNodeWitness]
    ) {
        guard let node = source.node, registration.source === node,
            let labelNode = registration.label, let label = sourceCensus[ObjectIdentifier(labelNode)],
            let ancestors = chromeAncestors(of: node)
        else { return nil }
        self.registration = registration
        self.source = source
        self.label = label
        sourceAncestors = ancestors
    }

    var sourceIsCurrent: Bool {
        guard let registration, let sourceNode = source.node, let labelNode = label.node,
            let controller = registration.controller,
            registration.source === sourceNode, registration.label === labelNode,
            sourceNode.textInputChromeRegistration === registration,
            sourceNode.textInputController === controller,
            source.hasCurrentEdge, label.hasCurrentEdge,
            sourceAncestors.allSatisfy({ $0.hasCurrentEdge }),
            sourceNode.children.count == 1, sourceNode.children.first === labelNode,
            labelNode.parent === sourceNode, labelNode.children.isEmpty,
            labelNode.textInputController == nil, !labelNode.isHidden,
            labelNode.text == registration.text, labelNode.textStyle == registration.style
        else { return false }
        return true
    }

    var targetIsCurrent: Bool {
        guard let target, target.hasCurrentEdge,
            targetAncestors.allSatisfy({ $0.hasCurrentEdge })
        else { return false }
        return true
    }

    var canStage: Bool {
        guard wasBound, !wasRefused, !isClosed, contribution == nil,
            scope?.isOpen == true, sourceIsCurrent, targetIsCurrent,
            let controller = registration?.controller, let node = target?.node,
            node.textInputController === controller
        else { return false }
        return true
    }
}

@MainActor
private struct ChromeGeneratedShape {
    let text: String?
    let style: PixelTextStyle
    let background: Color?
    let preferredSize: Size?
    let stack: StackLayout?
    let caret: Bool
    let opacity: Double
    let localLayout: RetainedTextInputChromeLocalLayoutWitness

    init(_ node: ViewNode) {
        text = node.text
        style = node.textStyle
        background = node.backgroundColor
        preferredSize = node.preferredSize
        if case .stack(let stack) = node.layoutMode { self.stack = stack } else { self.stack = nil }
        caret = node.isTextInputCaret
        opacity = node.opacity
        localLayout = node.captureTextInputChromeLocalLayoutWitness()
    }

    func matches(_ node: ViewNode, checkingLayout: Bool) -> Bool {
        guard node.hasClosedTextInputChromePayload, node.text == text, node.textStyle == style,
            node.backgroundColor == background, node.preferredSize == preferredSize,
            node.isTextInputCaret == caret, !node.isHitTestVisible,
            caret ? node.opacity.isFinite && (0...1).contains(node.opacity) : node.opacity == opacity,
            !checkingLayout || localLayout.isCurrent
        else { return false }
        switch (stack, node.layoutMode) {
        case (.none, .absolute): return true
        case (.some(let expected), .stack(let actual)): return expected == actual
        default: return false
        }
    }
}

@MainActor
final class RetainedTextInputChromeContribution {
    private enum Phase { case detached, transferring, installed }
    private weak var attempt: ChromeAdoptionAttempt?
    private var constructionRoot: ViewNode?
    private weak var root: ViewNode?
    private weak var base: ViewNode?
    private var baseWitness: ChromeNodeWitness?
    private let forest: [ObjectIdentifier: ChromeNodeWitness]
    private let shapes: [ObjectIdentifier: ChromeGeneratedShape]
    private var phase = Phase.detached
    private var wasRefused = false
    private var layout: RetainedTextInputChromeLayoutPassWitness?
    private var fieldLayout: RetainedTextInputChromeLocalLayoutWitness?
    private var baseLayout: RetainedTextInputChromeLocalLayoutWitness?
    private var pendingWrite: ObjectIdentifier?
    private weak var pendingParent: ViewNode?
    private weak var pendingRuntime: RetainedViewRuntime?
    private var expectsParent = false
    private var expectsRuntime = false
    private var visibilityWasWritten = false
    fileprivate let installation = RetainedTextInputChromeInstallation()

    fileprivate init?(attempt: ChromeAdoptionAttempt, recipe: RetainedTextInputChromeRecipe) {
        guard !recipe.rows.isEmpty, recipe.rows.allSatisfy({ !$0.isEmpty }) else { return nil }
        let rows = recipe.rows.map { segments in
            let children = segments.map { segment -> ViewNode in
                switch segment {
                case .text(let text, let style, let background):
                    let node = ViewNode(text: text, textStyle: style, isHitTestVisible: false)
                    node.backgroundColor = background
                    return node
                case .caret(let size, let color):
                    let node = ViewNode(isHitTestVisible: false)
                    node.preferredSize = size
                    node.backgroundColor = color
                    node.isTextInputCaret = true
                    return node
                case .selectionTail(let size, let color):
                    let node = ViewNode(isHitTestVisible: false)
                    node.preferredSize = size
                    node.backgroundColor = color
                    return node
                }
            }
            return Controls.stackPanel(
                stackLayout: .horizontal(spacing: 0, padding: .zero, alignment: .center),
                isHitTestVisible: false, children: children)
        }
        let root =
            rows.count == 1
            ? rows[0]
            : Controls.stackPanel(
                stackLayout: .vertical(spacing: 0, padding: .zero, alignment: .leading),
                isHitTestVisible: false, children: rows)
        root.isHidden = true
        guard let forest = chromeCensus([root]),
            forest.values.allSatisfy({ $0.node?.hasClosedTextInputChromePayload == true })
        else { return nil }
        self.attempt = attempt
        constructionRoot = root
        self.root = root
        self.forest = forest
        shapes = forest.compactMapValues { $0.node.map(ChromeGeneratedShape.init) }
    }

    func contains(_ node: ViewNode) -> Bool { forest[ObjectIdentifier(node)]?.node === node }

    func belongs(to buttonActions: RetainedButtonActionAdoption) -> Bool {
        attempt?.scope?.belongs(to: buttonActions) == true
    }

    func matchesContext(
        admission: RetainedLazyListAdoptionAdmission?, lazyJournal: RetainedLazyListAdoptionJournal?,
        taskAdoption: RetainedTaskAdoptionContext?,
        buttonActions: RetainedButtonActionAdoption?, uiaAuthority: RetainedLazyListUIAContinuationAuthority?
    ) -> Bool {
        attempt?.scope?.matchesContext(
            admission: admission, lazyJournal: lazyJournal, taskAdoption: taskAdoption, buttonActions: buttonActions,
            uiaAuthority: uiaAuthority) == true
    }

    private var originalIsCurrent: Bool {
        guard !wasRefused, let attempt, !attempt.wasRefused, attempt.sourceIsCurrent, attempt.targetIsCurrent,
            let controller = attempt.registration?.controller, attempt.target?.node?.textInputController === controller
        else { return false }
        return true
    }

    private func forestIsCurrent(checkingLayout: Bool = false) -> Bool {
        guard shapes.count == forest.count else { return false }
        return forest.allSatisfy { key, witness in
            guard let node = witness.node, witness.isCurrent, witness.hasOriginalChildren,
                shapes[key]?.matches(node, checkingLayout: checkingLayout) == true
            else { return false }
            return node === root || !node.isHidden
        }
    }

    var isCurrent: Bool {
        guard originalIsCurrent, pendingWrite == nil, forestIsCurrent(), let root else { return false }
        if phase == .detached { return root.parent == nil && root.retainedLazyListRuntime == nil }
        guard let field = attempt?.target?.node, let base, let baseWitness,
            baseWitness.isCurrent, base.parent === field
        else { return false }
        if phase == .transferring { return root.parent == nil || root.parent === field }
        return root.parent === field && field.children.count == 2
            && field.children[0] === base && field.children[1] === root
    }

    func validatedDetachedNodes() -> [ViewNode]? {
        guard phase == .detached, isCurrent, forestIsCurrent(checkingLayout: true),
            let root, root.isHidden
        else { return nil }
        let nodes = forest.values.compactMap(\.node)
        guard nodes.count == forest.count, nodes.allSatisfy({ $0.retainedLazyListRuntime == nil }) else { return nil }
        return nodes
    }

    fileprivate func prepareInsertion(base: ViewNode) -> ViewNode? {
        guard phase == .detached, isCurrent, let attempt, let field = attempt.target?.node,
            let registration = attempt.registration, let root,
            let originalBase = attempt.originalTargetChildren.first(where: { $0.node === base }),
            originalBase.hasCurrentEdge, base.parent === field, base.children.isEmpty,
            base.textInputController == nil, !base.isHidden,
            base.text == registration.text, base.textStyle == registration.style,
            let runtime = field.retainedLazyListRuntime
        else { return nil }
        self.base = base
        baseWitness = originalBase
        fieldLayout = field.captureTextInputChromeLocalLayoutWitness()
        baseLayout = base.captureTextInputChromeLocalLayoutWitness()
        layout = runtime.captureTextInputChromeLayoutPassWitness()
        phase = .transferring
        return root
    }

    func beginAttachmentWrite(on node: ViewNode, parent: ViewNode?, runtime: RetainedViewRuntime?) -> Bool {
        guard contains(node) else { return isCurrent }
        guard originalIsCurrent, pendingWrite == nil, forestIsCurrent(), phase == .transferring else {
            wasRefused = true
            return false
        }
        pendingWrite = ObjectIdentifier(node)
        pendingParent = parent
        pendingRuntime = runtime
        expectsParent = parent != nil
        expectsRuntime = runtime != nil
        return true
    }

    func recordAttachmentWrite(on node: ViewNode) -> Bool {
        guard contains(node) else { return isCurrent }
        let key = ObjectIdentifier(node)
        guard pendingWrite == key, let witness = forest[key], witness.node === node,
            originalIsCurrent, witness.identity.isCurrent, witness.hasOriginalChildren,
            shapes[key]?.matches(node, checkingLayout: false) == true,
            expectsParent ? pendingParent != nil && node.parent === pendingParent : node.parent == nil,
            expectsRuntime
                ? pendingRuntime != nil && node.retainedLazyListRuntime === pendingRuntime
                : node.retainedLazyListRuntime == nil
        else {
            wasRefused = true
            return false
        }
        // Only the adjacent recorded native write may advance this one token.
        witness.attachment = node.captureLazyListAttachmentProof()
        pendingWrite = nil
        pendingParent = nil
        pendingRuntime = nil
        return originalIsCurrent && forestIsCurrent()
    }

    func recordFinalChildrenWrite(on field: ViewNode) -> Bool {
        guard phase == .transferring, attempt?.target?.node === field,
            let root, let base, originalIsCurrent, pendingWrite == nil, forestIsCurrent(),
            baseWitness?.isCurrent == true, base.parent === field, root.parent === field,
            root.retainedLazyListRuntime === field.retainedLazyListRuntime,
            field.children.count == 2, field.children[0] === base, field.children[1] === root
        else {
            wasRefused = true
            return false
        }
        phase = .installed
        return isCurrent
    }

    fileprivate var canActivate: Bool {
        guard phase == .installed, isCurrent, !visibilityWasWritten,
            let root, root.isHidden, let base, !base.isHidden,
            let field = attempt?.target?.node, let runtime = field.retainedLazyListRuntime,
            let layout, layout.isCurrent, fieldLayout?.isCurrent == true, baseLayout?.isCurrent == true,
            forestIsCurrent(checkingLayout: true)
        else { return false }
        return runtime.canChangeTextInputChromeVisibility(field: field, base: base, root: root, layoutWitness: layout)
    }

    fileprivate func activationIdentifiers() -> [ObjectIdentifier]? {
        guard canActivate, let base else { return nil }
        return [ObjectIdentifier(base)] + Array(forest.keys)
    }

    /// The caller's whole-batch preflight and final checks contain no callouts.
    fileprivate func writeVisibility() -> Bool {
        guard canActivate, let root, let base else { return false }
        root.isHidden = false
        base.isHidden = true
        visibilityWasWritten = true
        return true
    }

    fileprivate func restoreVisibility() {
        guard visibilityWasWritten else { return }
        // No authored code or attachment mutation may run between these phases.
        if let root, let base, let field = attempt?.target?.node,
            root.parent === field, base.parent === field,
            field.children.count == 2, field.children[0] === base, field.children[1] === root,
            forest.values.allSatisfy({ $0.isCurrent && $0.hasOriginalChildren }),
            baseWitness?.isCurrent == true, attempt?.target?.isCurrent == true,
            let controller = attempt?.registration?.controller, field.textInputController === controller
        {
            base.isHidden = false
            root.isHidden = true
        }
        visibilityWasWritten = false
    }

    fileprivate func acknowledge() {
        guard visibilityWasWritten, isCurrent, let root, !root.isHidden, let base, base.isHidden,
            let attempt, let fieldWitness = attempt.target, let field = fieldWitness.node,
            let controller = attempt.registration?.controller
        else { return }
        installation.cacheObservation = RetainedTextInputChromeCache(
            root: root, field: field, controller: controller, fieldWitness: fieldWitness,
            forest: Array(forest.values), children: [ObjectIdentifier(base), ObjectIdentifier(root)])
        installation.isAcknowledged = true
        visibilityWasWritten = false
    }

    @inline(never)
    fileprivate func releaseConstruction() { constructionRoot = nil }
}

@MainActor
final class RetainedTextInputChromeAdoptionScope {
    private let retained: [ObjectIdentifier: ChromeNodeWitness]
    private var attempts: [ObjectIdentifier: ChromeAdoptionAttempt] = [:]
    fileprivate private(set) var isOpen = true
    private var wasAssociated = false
    private weak var originalAdmission: RetainedLazyListAdoptionAdmission?
    private weak var originalJournal: RetainedLazyListAdoptionJournal?
    private weak var originalTask: RetainedTaskAdoptionContext?
    private weak var originalButton: RetainedButtonActionAdoption?
    private weak var originalUIA: RetainedLazyListUIAContinuationAuthority?
    private var hadAdmission = false
    private var hadJournal = false
    private var hadTask = false
    private var hadButton = false
    private var hadUIA = false
    private var activation: [RetainedTextInputChromeContribution] = []

    init?(retainedRoots: [ViewNode], sourceRoots: [ViewNode]) {
        guard let sources = chromeCensus(sourceRoots),
            sources.values.contains(where: { $0.node?.textInputChromeRegistration != nil }),
            var retained = chromeCensus(retainedRoots)
        else { return nil }
        for root in retainedRoots {
            guard let ancestors = chromeAncestors(of: root) else { return nil }
            for ancestor in ancestors where retained[ancestor.identifier] == nil {
                retained[ancestor.identifier] = ancestor
            }
        }
        self.retained = retained
        for (key, source) in sources {
            guard let registration = source.node?.textInputChromeRegistration,
                let attempt = ChromeAdoptionAttempt(registration: registration, source: source, sourceCensus: sources)
            else { continue }
            attempts[key] = attempt
            attempt.scope = self
        }
        if attempts.isEmpty { return nil }
    }

    func associateOriginalContext(
        admission: RetainedLazyListAdoptionAdmission?, lazyJournal: RetainedLazyListAdoptionJournal?,
        taskAdoption: RetainedTaskAdoptionContext?,
        buttonActions: RetainedButtonActionAdoption?, uiaAuthority: RetainedLazyListUIAContinuationAuthority?
    ) {
        guard !wasAssociated else { return }
        wasAssociated = true
        originalAdmission = admission
        originalJournal = lazyJournal
        originalTask = taskAdoption
        originalButton = buttonActions
        originalUIA = uiaAuthority
        hadAdmission = admission != nil
        hadJournal = lazyJournal != nil
        hadTask = taskAdoption != nil
        hadButton = buttonActions != nil
        hadUIA = uiaAuthority != nil
    }

    fileprivate func belongs(to buttonActions: RetainedButtonActionAdoption) -> Bool {
        wasAssociated && hadButton && originalButton === buttonActions
    }

    fileprivate func matchesContext(
        admission: RetainedLazyListAdoptionAdmission?, lazyJournal: RetainedLazyListAdoptionJournal?,
        taskAdoption: RetainedTaskAdoptionContext?,
        buttonActions: RetainedButtonActionAdoption?, uiaAuthority: RetainedLazyListUIAContinuationAuthority?
    ) -> Bool {
        wasAssociated
            && (hadAdmission ? originalAdmission != nil && originalAdmission === admission : admission == nil)
            && (hadJournal ? originalJournal != nil && originalJournal === lazyJournal : lazyJournal == nil)
            && (hadTask ? originalTask != nil && originalTask === taskAdoption : taskAdoption == nil)
            && (hadButton ? originalButton != nil && originalButton === buttonActions : buttonActions == nil)
            && (hadUIA ? originalUIA != nil && originalUIA === uiaAuthority : uiaAuthority == nil)
    }

    func permitsContinuation(strict: Bool) -> Bool {
        guard strict else { return true }
        return attempts.values.allSatisfy { attempt in
            guard attempt.wasBound else { return true }
            return !attempt.wasRefused && attempt.sourceIsCurrent && attempt.targetIsCurrent
                && attempt.contribution?.isCurrent != false
        }
    }

    /// Binds the existing match to receipts captured before the first callback.
    func bind(source: ViewNode, target: ViewNode, strict: Bool) -> Bool {
        guard let attempt = attempts[ObjectIdentifier(source)] else { return true }
        guard isOpen, wasAssociated, !attempt.wasBound, !attempt.wasRefused,
            attempt.sourceIsCurrent, let originalTarget = retained[ObjectIdentifier(target)],
            originalTarget.node === target, originalTarget.hasCurrentEdge, originalTarget.hasOriginalChildren,
            let ancestors = chromeAncestorsFromOriginal(target)
        else {
            attempt.wasRefused = true
            return !strict
        }
        guard let registration = attempt.registration, !registration.wasClaimed else {
            // Reentering with the same construction cannot replace and later
            // restore the original receipt, even if all node pointers agree.
            attempt.registration?.attempt?.wasRefused = true
            attempt.wasRefused = true
            return !strict
        }
        let children = originalTarget.children.compactMap { retained[$0] }
        guard children.count == originalTarget.children.count, children.allSatisfy({ $0.hasCurrentEdge }) else {
            attempt.wasRefused = true
            return !strict
        }
        attempt.target = originalTarget
        attempt.targetAncestors = ancestors
        attempt.originalTargetChildren = children
        attempt.wasBound = true
        registration.wasClaimed = true
        registration.attempt = attempt
        return true
    }

    private func chromeAncestorsFromOriginal(_ node: ViewNode) -> [ChromeNodeWitness]? {
        var result: [ChromeNodeWitness] = []
        var current = node.parent
        var seen: Set<ObjectIdentifier> = [ObjectIdentifier(node)]
        while let parent = current {
            guard result.count < ViewNode.maximumTraversalDepth,
                seen.insert(ObjectIdentifier(parent)).inserted,
                let witness = retained[ObjectIdentifier(parent)], witness.hasCurrentEdge
            else { return nil }
            result.append(witness)
            current = parent.parent
        }
        return result
    }

    func contribution(
        for source: ViewNode?, target: ViewNode, reconciledChildren: [ViewNode],
        buttonActions: RetainedButtonActionAdoption?
    ) -> (root: ViewNode, contribution: RetainedTextInputChromeContribution)? {
        guard isOpen, let source, let attempt = attempts[ObjectIdentifier(source)],
            attempt.target?.node === target, let contribution = attempt.contribution,
            reconciledChildren.count == 1,
            buttonActions?.admitGeneratedForest(contribution) != false,
            let root = contribution.prepareInsertion(base: reconciledChildren[0])
        else { return nil }
        return (root, contribution)
    }

    /// Must return before final checks: an installed forest may have acquired
    /// an authored capture before a callback removed its last real owner.
    @inline(never)
    func closeAndReleaseConstruction() {
        guard isOpen else { return }
        isOpen = false
        for attempt in attempts.values {
            attempt.isClosed = true
            if attempt.registration?.attempt === attempt { attempt.registration?.attempt = nil }
        }
        for attempt in attempts.values { attempt.contribution?.releaseConstruction() }
    }

    func beginActivation(
        check: ComponentHost.NodeReconcileAdmission, completion: RetainedLazyListAdoptionCompletion?,
        requiringCompletion: Bool
    ) -> Bool {
        guard !isOpen, check.isCurrent, !requiringCompletion || completion?.isCurrent == true else { return false }
        let proposed = attempts.values.compactMap(\.contribution).filter(\.canActivate)
        var seen = Set<ObjectIdentifier>()
        for contribution in proposed {
            guard let identifiers = contribution.activationIdentifiers() else { return false }
            // Each contribution includes its root in its fixed forest already.
            for identifier in Set(identifiers) {
                guard seen.insert(identifier).inserted else { return false }
            }
        }
        activation = proposed
        for contribution in proposed {
            guard contribution.writeVisibility() else {
                finishActivation(accepted: false)
                return false
            }
        }
        guard check.isCurrent, !requiringCompletion || completion?.isCurrent == true,
            proposed.allSatisfy(\.isCurrent)
        else {
            finishActivation(accepted: false)
            return false
        }
        return true
    }

    func finishActivation(accepted: Bool) {
        if accepted {
            for contribution in activation { contribution.acknowledge() }
        } else {
            for contribution in activation.reversed() { contribution.restoreVisibility() }
        }
        activation.removeAll()
    }
}
