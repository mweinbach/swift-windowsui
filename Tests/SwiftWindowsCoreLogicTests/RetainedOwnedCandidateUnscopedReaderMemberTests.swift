import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI

/// A reader outside the namespace replaces its own deferred payload before the
/// fresh selected body publishes. Its old contribution must not be renewed.
@MainActor
final class RetainedOwnedCandidateUnscopedReaderMemberTests: XCTestCase {
    func testFreshMemberSurvivesColdSelectionThenExactDeclarationOmission() async throws {
        let fixture = try UnscopedReaderMemberFixture()
        let local = try UnscopedReaderMemberEpoch(fixture.original)
        let slot = RetainedOwnedSlotGenerationID()
        let primary = try UnscopedReaderMemberTree(
            epoch: local, reader: fixture.reader.receipt, boundary: fixture.boundaryOwner.receipt,
            selectedIdentity: 20, selectedSlots: [slot], width: 600)
        let nextReaderGroup = try XCTUnwrap(primary.reader.attribution.contribution(for: primary.reader.group))
        let primaryGroup = try XCTUnwrap(primary.selected.attribution.contribution(for: primary.selected.group))
        XCTAssertFalse(primary.selected.receipt.hasAcceptedDeclaration)
        XCTAssertFalse(nextReaderGroup.isActive)
        XCTAssertFalse(primaryGroup.isActive)
        local.begin(sources: [primary.source])
        XCTAssertTrue(fixture.original.contribution.isActive)
        XCTAssertTrue(fixture.original.actual.isAttached)

        // The real direct-adoption caller copies A's geometry payload first,
        // then reconciles W and the fresh primary. Do not pre-publish either.
        let result = ComponentHost.adopt(
            source: primary.source, into: fixture.readerNode, lazyJournal: local.journal)
        XCTAssertTrue(result.completed)
        XCTAssertTrue(primary.reader.receipt.hasAcceptedDeclaration)
        XCTAssertTrue(primary.boundaryOwner.receipt.hasAcceptedDeclaration)
        XCTAssertTrue(primary.selected.receipt.hasAcceptedDeclaration)
        XCTAssertTrue(primary.selected.receipt.hasDeclaredComponent)
        XCTAssertTrue(primary.selected.receipt.hasAcceptedOwnership(for: slot))
        XCTAssertTrue(primary.selected.receipt.permitsOwnedWrite(for: slot))
        XCTAssertTrue(primary.reader.receipt.owner === fixture.reader.receipt.owner)
        XCTAssertTrue(primary.boundaryOwner.receipt.owner === fixture.boundaryOwner.receipt.owner)
        XCTAssertTrue(fixture.readerNode.children.first === fixture.boundaryNode)
        XCTAssertTrue(fixture.boundaryNode.children.first === primary.selectedNode)
        XCTAssertTrue(primary.selectedNode.parent === fixture.boundaryNode)
        XCTAssertTrue(primary.selectedNode.isRetainedLazyListAttached(in: fixture.runtime))
        XCTAssertEqual(fixture.readerNode.geometryReaderBuiltSize, Size(width: 600, height: 100))
        // The unchanged general qualification conjoins this ORIGINAL receipt's
        // isActive. This is a source-backed q=false oracle, not a private getter.
        XCTAssertFalse(fixture.original.contribution.isActive)
        XCTAssertTrue(fixture.original.actual.isAttached)
        XCTAssertTrue(nextReaderGroup.isActive)
        XCTAssertTrue(primaryGroup.isActive)
        XCTAssertTrue(
            fixture.readerNode.retainedLazyListActivityStorage?.descriptorDeferredSubtreeAnchor?.contribution
                === nextReaderGroup)
        let nextAnchor = try UnscopedReaderMemberOriginal(fixture.readerNode, in: fixture.runtime)
        XCTAssertTrue(nextAnchor.contribution === nextReaderGroup)
        XCTAssertTrue(nextAnchor.actual.target === fixture.original.actual.target)
        XCTAssertTrue(nextAnchor.actual.attachment === fixture.original.actual.attachment)
        XCTAssertTrue(nextAnchor.admitsUnscopedConstruction())
        _ = local.finish()

        // A new ROOT operation preserves the exact primary receipt through a
        // declaration-only plan while its physical selected output departs.
        let cold = UnscopedReaderMemberEpoch(fixture.runtime)
        let fallback = try UnscopedReaderMemberTree(
            epoch: cold, reader: primary.reader.receipt, boundary: primary.boundaryOwner.receipt,
            selectedIdentity: 10, preserving: [primary.selected.receipt], width: 80)
        let preserved = try XCTUnwrap(fallback.preserved.first)
        XCTAssertTrue(preserved.receipt.owner === primary.selected.receipt.owner)
        XCTAssertTrue(try XCTUnwrap(preserved.receipt.slots.first) === slot)
        XCTAssertFalse(preserved.receipt.hasAcceptedDeclaration)
        cold.begin(sources: [fallback.source])
        let coldResult = ComponentHost.reconcileChildren(
            of: fixture.runtime.root, oldChildren: fixture.runtime.root.children, newNodes: [fallback.source],
            lazyJournal: cold.journal)
        XCTAssertTrue(coldResult.completed)
        XCTAssertTrue(fixture.runtime.root.children.first === fixture.readerNode)
        XCTAssertTrue(fixture.readerNode.children.first === fixture.boundaryNode)
        XCTAssertTrue(fixture.boundaryNode.children.first === fallback.selectedNode)
        XCTAssertNil(primary.selectedNode.parent)
        XCTAssertFalse(primary.selectedNode.isRetainedLazyListAttached(in: fixture.runtime))
        XCTAssertFalse(primaryGroup.isActive)
        XCTAssertTrue(primary.selected.receipt.hasDeclaredComponent)
        XCTAssertTrue(primary.selected.receipt.hasAcceptedOwnership(for: slot))
        XCTAssertTrue(primary.selected.receipt.permitsOwnedWrite(for: slot))
        XCTAssertTrue(preserved.receipt.hasDeclaredComponent)
        XCTAssertTrue(fallback.boundaryOwner.receipt.hasDeclaredComponent)
        XCTAssertTrue(fallback.selected.receipt.hasDeclaredComponent)
        _ = cold.finish()
        XCTAssertTrue(primary.selected.receipt.hasDeclaredComponent)
        XCTAssertTrue(primary.selected.receipt.permitsOwnedWrite(for: slot))
        XCTAssertFalse(fixture.original.contribution.isActive)

        // Omit only that declaration in another independently seeded ROOT.
        // The retained W and selected fallback must remain accepted.
        let omission = UnscopedReaderMemberEpoch(fixture.runtime)
        let omitted = try UnscopedReaderMemberTree(
            epoch: omission, reader: fallback.reader.receipt, boundary: fallback.boundaryOwner.receipt,
            selectedIdentity: 10, selected: fallback.selected.receipt, width: 80)
        XCTAssertTrue(omitted.preserved.isEmpty)
        omission.begin(sources: [omitted.source])
        let omittedResult = ComponentHost.reconcileChildren(
            of: fixture.runtime.root, oldChildren: fixture.runtime.root.children, newNodes: [omitted.source],
            lazyJournal: omission.journal)
        XCTAssertTrue(omittedResult.completed)
        XCTAssertFalse(primary.selected.receipt.hasDeclaredComponent)
        XCTAssertFalse(primary.selected.receipt.hasAcceptedOwnership(for: slot))
        XCTAssertFalse(primary.selected.receipt.permitsOwnedWrite(for: slot))
        XCTAssertFalse(preserved.receipt.hasDeclaredComponent)
        XCTAssertTrue(omitted.reader.receipt.hasDeclaredComponent)
        XCTAssertTrue(omitted.boundaryOwner.receipt.hasDeclaredComponent)
        XCTAssertTrue(omitted.selected.receipt.hasDeclaredComponent)
        XCTAssertTrue(fixture.readerNode.children.first === fixture.boundaryNode)
        XCTAssertTrue(fixture.boundaryNode.children.first === fallback.selectedNode)
        XCTAssertTrue(fixture.boundaryNode.isRetainedLazyListAttached(in: fixture.runtime))
        _ = omission.finish()
        XCTAssertFalse(primary.selected.receipt.permitsOwnedWrite(for: slot))
        fixture.runtime.root.removeChild(fixture.readerNode)
        XCTAssertFalse(omitted.boundaryOwner.receipt.hasDeclaredComponent)
        XCTAssertFalse(omitted.selected.receipt.hasDeclaredComponent)
    }

    func testForeignFirstRetirementCannotQualifyTheOlderReaderMemberAttempt() async throws {
        let fixture = try UnscopedReaderMemberFixture()
        let older = try UnscopedReaderMemberEpoch(fixture.original)
        let slot = RetainedOwnedSlotGenerationID()
        let proposed = try UnscopedReaderMemberTree(
            epoch: older, reader: fixture.reader.receipt, boundary: fixture.boundaryOwner.receipt,
            selectedIdentity: 20, selectedSlots: [slot], width: 600)
        let proposedReaderGroup = try XCTUnwrap(proposed.reader.attribution.contribution(for: proposed.reader.group))
        older.begin(sources: [proposed.source])
        XCTAssertTrue(older.scope.canPublishDescriptors)
        XCTAssertTrue(older.journal.canContinueAdoption)
        XCTAssertTrue(fixture.original.contribution.isActive)
        let originalSelected = try XCTUnwrap(fixture.boundaryNode.children.first)

        // A distinct real ordinary property publication retires the original A
        // receipt before the older operation reaches its own pre-copy entry.
        // It does not install an owned plan, candidate token or namespace fact.
        let foreign = UnscopedReaderMemberEpoch(fixture.runtime)
        let attribution = try XCTUnwrap(foreign.scope.registerOrdinaryComponent())
        let group = try XCTUnwrap(attribution.registerGroup(kind: .observation))
        let source = unscopedReaderMemberNode(100)
        source.geometryReaderBuild = { _, _ in [] }
        XCTAssertTrue(attribution.recordSourceOutput(source, group: group))
        _ = try XCTUnwrap(attribution.closeGroup(group))
        foreign.begin(sources: [source])
        XCTAssertTrue(foreign.copyGeometryOnly(from: source, to: fixture.readerNode))
        _ = foreign.finish(completed: false)
        XCTAssertFalse(fixture.original.contribution.isActive)
        XCTAssertTrue(fixture.original.actual.isAttached)
        XCTAssertTrue(fixture.readerNode.children.first === fixture.boundaryNode)
        XCTAssertTrue(fixture.boundaryNode.children.first === originalSelected)
        XCTAssertTrue(fixture.boundaryOwner.receipt.hasDeclaredComponent)
        XCTAssertFalse(older.scope.canPublishDescriptors)
        XCTAssertFalse(older.journal.canContinueAdoption)

        // Preserve the ordinary admission refusal. Never force a manufactured
        // pending property/absence to reach a later member join.
        let result = ComponentHost.adopt(
            source: proposed.source, into: fixture.readerNode, lazyJournal: older.journal)
        XCTAssertFalse(result.completed)
        XCTAssertFalse(proposed.selected.receipt.hasAcceptedDeclaration)
        XCTAssertFalse(proposed.selected.receipt.hasDeclaredComponent)
        XCTAssertFalse(proposedReaderGroup.isActive)
        XCTAssertFalse(proposed.selectedNode.isRetainedLazyListAttached(in: fixture.runtime))
        XCTAssertTrue(fixture.boundaryNode.children.first === originalSelected)
        XCTAssertTrue(fixture.boundaryOwner.receipt.hasDeclaredComponent)
        _ = older.finish(completed: false)
        XCTAssertFalse(proposed.selected.receipt.hasDeclaredComponent)
        XCTAssertFalse(proposed.selected.receipt.permitsOwnedWrite(for: slot))
        XCTAssertFalse(fixture.original.contribution.isActive)
        fixture.runtime.root.removeChild(fixture.readerNode)
        XCTAssertFalse(fixture.boundaryOwner.receipt.hasDeclaredComponent)
    }
}

@MainActor
private struct UnscopedReaderMemberComponent {
    let attribution: RetainedDescriptorComponentAttribution
    let receipt: RetainedOwnedComponentReceipt
    let group: RetainedDescriptorGroupID
}

@MainActor
private final class UnscopedReaderMemberOriginal {
    let runtime: RetainedViewRuntime
    let node: ViewNode
    let contribution: RetainedDescriptorContributionReceipt
    let actual: RetainedLazyListActualAttachment

    init(_ node: ViewNode, in runtime: RetainedViewRuntime) throws {
        let anchor = try XCTUnwrap(node.retainedLazyListActivityStorage?.descriptorDeferredSubtreeAnchor)
        self.runtime = runtime
        self.node = node
        contribution = anchor.contribution
        actual = anchor.actual
        XCTAssertTrue(actual.node === node)
        XCTAssertTrue(actual.isAttached)
        XCTAssertTrue(contribution.isActive)
    }

    func admittedScope() -> RetainedLazyListDescriptorBuildScope? {
        let bootstrap = RetainedLazyListDescriptorBuildScope(
            origin: .managedSubtree, hostLifetime: runtime.lazyListLogicalHostLifetime,
            ownerLifetime: runtime.root.lazyListActivityStorage().descriptorOwnerLifetime)
        return bootstrap.withAdmittedOrdinaryDeferredSubtree(
            originalActivity: contribution, originalAttachment: actual)
    }

    func admitsUnscopedConstruction() -> Bool {
        guard let scope = admittedScope() else { return false }
        defer { scope.finish() }
        guard let attribution = scope.registerOrdinaryComponent() else { return false }
        if case .unscoped = attribution.ownedCandidateContinuation() { return true }
        return false
    }
}

@MainActor
private final class UnscopedReaderMemberEpoch {
    let runtime: RetainedViewRuntime
    let scope: RetainedLazyListDescriptorBuildScope
    let journal: RetainedLazyListAdoptionJournal
    let receiver: RetainedDescriptorComponentAttribution?

    init(_ runtime: RetainedViewRuntime) {
        self.runtime = runtime
        scope = RetainedLazyListDescriptorBuildScope(
            origin: .componentHostRoot, hostLifetime: runtime.lazyListLogicalHostLifetime,
            ownerLifetime: runtime.root.lazyListActivityStorage().descriptorOwnerLifetime)
        journal = RetainedLazyListAdoptionJournal(descriptorScope: scope, transaction: RetainedBuildTransaction())
        receiver = nil
        XCTAssertTrue(journal.seedOwnedCandidateOrigins(at: runtime.root))
        journal.seedExistingContributions(from: runtime.root.children)
    }

    init(_ original: UnscopedReaderMemberOriginal) throws {
        let scope = try XCTUnwrap(original.admittedScope())
        let journal = RetainedLazyListAdoptionJournal(descriptorScope: scope, transaction: RetainedBuildTransaction())
        journal.seedExistingContributions(from: original.node.children)
        let receiver = try XCTUnwrap(scope.registerOrdinaryComponent())
        guard case .unscoped = receiver.ownedCandidateContinuation() else {
            XCTFail("The outer reader must not receive a SELF or candidate-segment token")
            throw UnscopedReaderMemberFixtureError.scopedOuterReader
        }
        runtime = original.runtime
        self.scope = scope
        self.journal = journal
        self.receiver = receiver
    }

    func open(
        parent: RetainedDescriptorComponentAttribution? = nil,
        kind: RetainedLazyListContributionKind = .observation,
        slots: [RetainedOwnedSlotGenerationID] = [], continuing: RetainedOwnedComponentReceipt? = nil,
        token: RetainedOwnedCandidateConstruction? = nil, declarationOnly: Bool = false
    ) throws -> UnscopedReaderMemberComponent {
        let attribution: RetainedDescriptorComponentAttribution
        if let parent {
            attribution = try XCTUnwrap(parent.registerChildComponent())
        } else {
            attribution = try XCTUnwrap(scope.registerOrdinaryComponent())
        }
        let receipt = try XCTUnwrap(
            attribution.registerOwnedComponent(
                owner: continuing?.owner ?? RetainedOwnedComponentID(), slots: slots, continuing: continuing,
                declarationOnly: declarationOnly, candidateConstruction: token))
        let group = try XCTUnwrap(attribution.registerGroup(kind: kind))
        return UnscopedReaderMemberComponent(attribution: attribution, receipt: receipt, group: group)
    }

    func close(_ component: UnscopedReaderMemberComponent, nodes: [ViewNode]) throws {
        for node in nodes { XCTAssertTrue(component.attribution.recordSourceOutput(node, group: component.group)) }
        _ = try XCTUnwrap(component.attribution.closeGroup(component.group))
    }

    func begin(sources: [ViewNode]) {
        XCTAssertTrue(journal.registerSourceDescriptors(in: sources))
        XCTAssertTrue(journal.beginOrdinaryAdoption())
        XCTAssertTrue(journal.markMutationStarted())
    }

    func prepareTree(_ node: ViewNode) {
        XCTAssertTrue(journal.prepareInsertedNode(from: node))
        for child in node.children { prepareTree(child) }
    }

    func acceptTree(_ node: ViewNode) {
        XCTAssertTrue(node.isRetainedLazyListAttached(in: runtime))
        _ = journal.recordAcceptedInsertedNode(on: node)
        for child in node.children { acceptTree(child) }
        _ = journal.recordCompletedNode(from: node, to: node)
    }

    func copyGeometryOnly(from source: ViewNode, to target: ViewNode) -> Bool {
        guard journal.preparePropertyCopy(from: source, to: target, keyPath: \ViewNode.geometryReaderBuild) else {
            return false
        }
        let previous = target.geometryReaderBuild
        target.geometryReaderBuild = source.geometryReaderBuild
        _ = journal.recordAcceptedProperty(from: source, to: target, keyPath: \ViewNode.geometryReaderBuild)
        withExtendedLifetime(previous) {}
        return true
    }

    @discardableResult
    func finish(completed: Bool = true) -> RetainedLazyListAdoptionDisposition {
        let result = journal.seal(completedCheckedAdoption: completed)
        journal.releaseUnadoptedTransport()
        scope.finish()
        return result
    }
}

private enum UnscopedReaderMemberFixtureError: Error {
    case scopedOuterReader
}

@MainActor
private final class UnscopedReaderMemberTree {
    let source: ViewNode
    let reader: UnscopedReaderMemberComponent
    let boundaryNode: ViewNode
    let boundaryOwner: UnscopedReaderMemberComponent
    let token: RetainedOwnedCandidateConstruction
    let selected: UnscopedReaderMemberComponent
    let selectedNode: ViewNode
    let preserved: [UnscopedReaderMemberComponent]

    init(
        epoch: UnscopedReaderMemberEpoch,
        reader previousReader: RetainedOwnedComponentReceipt? = nil,
        boundary previousBoundary: RetainedOwnedComponentReceipt? = nil,
        selectedIdentity: Int, selected previousSelected: RetainedOwnedComponentReceipt? = nil,
        selectedSlots: [RetainedOwnedSlotGenerationID] = [],
        preserving: [RetainedOwnedComponentReceipt] = [], width: Double
    ) throws {
        let reader = try epoch.open(
            parent: epoch.receiver, kind: .deferredSubtree, continuing: previousReader)
        let boundaryOwner = try epoch.open(parent: reader.attribution, continuing: previousBoundary)
        let token = try XCTUnwrap(
            boundaryOwner.attribution.beginOwnedCandidateConstruction(owner: boundaryOwner.receipt))
        let selected = try epoch.open(
            parent: boundaryOwner.attribution, slots: previousSelected?.slots ?? selectedSlots,
            continuing: previousSelected, token: token)
        let selectedNode = unscopedReaderMemberNode(selectedIdentity)
        try epoch.close(selected, nodes: [selectedNode])
        var preserved: [UnscopedReaderMemberComponent] = []
        for receipt in preserving {
            let declaration = try epoch.open(
                parent: boundaryOwner.attribution, kind: .structure, slots: receipt.slots,
                continuing: receipt, token: token, declarationOnly: true)
            try epoch.close(declaration, nodes: [])
            preserved.append(declaration)
        }
        let boundaryNode = ViewNode.selectedContentBoundary(role: .viewThatFits, child: selectedNode)
        boundaryNode.retainedViewIdentity = RetainedViewIdentity().appending(.slot(1000))
        XCTAssertTrue(token.stageBoundary(on: boundaryNode))
        try epoch.close(boundaryOwner, nodes: [boundaryNode])
        let source = unscopedReaderMemberNode(100)
        source.geometryReaderBuild = { _, _ in [] }
        source.geometryReaderBuiltSize = Size(width: width, height: 100)
        source.addChild(boundaryNode)
        // A deliberately has no stageDeferredAnchor candidate call/token.
        // Its ordinary deferred group is nevertheless real and includes W.
        try epoch.close(reader, nodes: [source])
        self.source = source
        self.reader = reader
        self.boundaryNode = boundaryNode
        self.boundaryOwner = boundaryOwner
        self.token = token
        self.selected = selected
        self.selectedNode = selectedNode
        self.preserved = preserved
    }
}

@MainActor
private final class UnscopedReaderMemberFixture {
    let runtime: RetainedViewRuntime
    let readerNode: ViewNode
    let reader: UnscopedReaderMemberComponent
    let boundaryNode: ViewNode
    let boundaryOwner: UnscopedReaderMemberComponent
    let original: UnscopedReaderMemberOriginal

    init() throws {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let epoch = UnscopedReaderMemberEpoch(runtime)
        let tree = try UnscopedReaderMemberTree(epoch: epoch, selectedIdentity: 10, width: 80)
        epoch.begin(sources: [tree.source])
        epoch.prepareTree(tree.source)
        runtime.root.addChild(tree.source)
        epoch.acceptTree(tree.source)
        _ = epoch.finish()
        self.runtime = runtime
        readerNode = tree.source
        reader = tree.reader
        boundaryNode = tree.boundaryNode
        boundaryOwner = tree.boundaryOwner
        original = try UnscopedReaderMemberOriginal(tree.source, in: runtime)
        XCTAssertTrue(reader.receipt.hasAcceptedDeclaration)
        XCTAssertTrue(boundaryOwner.receipt.hasAcceptedDeclaration)
        XCTAssertTrue(tree.selected.receipt.hasDeclaredComponent)
        XCTAssertTrue(readerNode.children.first === boundaryNode)
        XCTAssertTrue(boundaryNode.children.first === tree.selectedNode)
        XCTAssertTrue(original.admitsUnscopedConstruction())
    }
}

@MainActor
private func unscopedReaderMemberNode(_ identity: Int) -> ViewNode {
    let node = ViewNode()
    node.retainedViewIdentity = RetainedViewIdentity().appending(.slot(identity))
    return node
}

// This positive control uses supported source co-location. It is not a
// reproducer of a bound outer-replacement witness intercepting a reader.
extension RetainedOwnedCandidateUnscopedReaderMemberTests {
    func testSharedSourceWithDistinctClosedOuterGroupKeepsLegacyReaderDispatch() async throws {
        let fixture = try UnscopedReaderMemberFixture()
        let local = try UnscopedReaderMemberEpoch(fixture.original)
        let shared = unscopedReaderMemberNode(200)
        shared.geometryReaderBuild = { _, _ in [] }
        shared.geometryReaderBuiltSize = Size(width: 600, height: 100)

        // Close A before constructing W/B. B cannot propagate this shared source
        // into the closed group and replace its original constructionComponent.
        let outer = try local.open(
            parent: local.receiver, kind: .deferredSubtree, continuing: fixture.reader.receipt)
        try local.close(outer, nodes: [shared])
        let outerGroup = try XCTUnwrap(outer.attribution.contribution(for: outer.group))
        let boundary = try local.open(
            parent: outer.attribution, continuing: fixture.boundaryOwner.receipt)
        let namespace = try XCTUnwrap(
            boundary.attribution.beginOwnedCandidateConstruction(owner: boundary.receipt))
        let reader = try local.open(
            parent: boundary.attribution, kind: .deferredSubtree, token: namespace)
        let readerToken = try XCTUnwrap(
            namespace.deferredSegment(owner: reader.receipt, attribution: reader.attribution))
        XCTAssertTrue(readerToken.stageDeferredAnchor(on: shared))
        try local.close(reader, nodes: [shared])
        let readerGroup = try XCTUnwrap(reader.attribution.contribution(for: reader.group))
        XCTAssertFalse(outerGroup === readerGroup)
        XCTAssertFalse(outer.receipt === reader.receipt)
        XCTAssertFalse(reader.receipt.hasAcceptedDeclaration)
        XCTAssertFalse(readerGroup.isActive)
        XCTAssertFalse(outerGroup.isActive)

        let boundarySource = ViewNode.selectedContentBoundary(role: .viewThatFits, child: shared)
        boundarySource.retainedViewIdentity = RetainedViewIdentity().appending(.slot(1000))
        XCTAssertTrue(namespace.stageBoundary(on: boundarySource))
        try local.close(boundary, nodes: [boundarySource])
        local.begin(sources: [boundarySource])
        XCTAssertTrue(fixture.original.contribution.isActive)
        XCTAssertTrue(fixture.original.actual.isAttached)

        // Keep physical A and its original geometry payload. Fresh B is inserted
        // under the retained W, so its normal fact carries the real insertion
        // input; no test manufactures a candidate fact, reference or anchor.
        let result = ComponentHost.reconcileChildren(
            of: fixture.readerNode, oldChildren: fixture.readerNode.children,
            newNodes: [boundarySource], lazyJournal: local.journal)
        XCTAssertTrue(result.completed)
        XCTAssertTrue(fixture.runtime.root.children.first === fixture.readerNode)
        XCTAssertTrue(fixture.readerNode.children.first === fixture.boundaryNode)
        XCTAssertTrue(fixture.boundaryNode.children.first === shared)
        XCTAssertTrue(shared.parent === fixture.boundaryNode)
        XCTAssertTrue(shared.isRetainedLazyListAttached(in: fixture.runtime))
        XCTAssertEqual(fixture.readerNode.geometryReaderBuiltSize, Size(width: 80, height: 100))
        XCTAssertTrue(fixture.original.contribution.isActive)
        XCTAssertTrue(fixture.original.actual.isAttached)
        XCTAssertTrue(outer.receipt.hasAcceptedDeclaration)
        XCTAssertTrue(boundary.receipt.hasAcceptedDeclaration)
        XCTAssertTrue(reader.receipt.hasAcceptedDeclaration)
        XCTAssertTrue(reader.receipt.hasDeclaredComponent)
        XCTAssertTrue(outerGroup.isActive)
        XCTAssertTrue(readerGroup.isActive)
        XCTAssertTrue(
            shared.retainedLazyListActivityStorage?.descriptorDeferredSubtreeAnchor?.contribution === readerGroup)
        _ = local.finish()

        // Native B completion must yield a fresh independent candidate admission,
        // not merely an active ordinary descriptor receipt or no optional witness.
        let originalB = try UnscopedReaderMemberOriginal(shared, in: fixture.runtime)
        XCTAssertTrue(originalB.contribution === readerGroup)
        let freshScope = try XCTUnwrap(originalB.admittedScope())
        let receiver = try XCTUnwrap(freshScope.registerOrdinaryComponent())
        let freshToken: RetainedOwnedCandidateConstruction?
        switch receiver.ownedCandidateContinuation() {
        case .admitted(let token): freshToken = token
        case .unscoped, .rejected: freshToken = nil
        }
        let admitted = try XCTUnwrap(freshToken, "The co-located B reader must complete its legacy native join")
        XCTAssertTrue(admitted.canConstruct)
        freshScope.finish()
        XCTAssertFalse(admitted.canConstruct)
        XCTAssertTrue(readerGroup.isActive)
        XCTAssertTrue(fixture.original.contribution.isActive)

        fixture.runtime.root.removeChild(fixture.readerNode)
        XCTAssertFalse(reader.receipt.hasDeclaredComponent)
        XCTAssertFalse(boundary.receipt.hasDeclaredComponent)
        XCTAssertFalse(readerGroup.isActive)
        XCTAssertFalse(outerGroup.isActive)
        XCTAssertFalse(fixture.original.contribution.isActive)
        XCTAssertFalse(originalB.actual.isAttached)
    }
}
