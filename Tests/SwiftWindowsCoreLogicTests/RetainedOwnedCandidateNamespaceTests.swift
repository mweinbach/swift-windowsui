import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI

/// Acceptance comes from the native journal and actual retained nodes.
/// A proposed catalog, weak scope completion, or a fresh attachment query
/// cannot substitute for an accepted candidate namespace field.
@MainActor
final class RetainedOwnedCandidateNamespaceTests: XCTestCase {
    func testAcceptedZeroSlotCandidateSurvivesColdSwitchThenExplicitOmission() async throws {
        let fixture = try CandidateNamespaceFixture()
        XCTAssertTrue(fixture.original.receipt.hasAcceptedDeclaration)
        XCTAssertTrue(fixture.original.receipt.hasDeclaredComponent)

        try fixture.switchToCold()

        XCTAssertNil(fixture.originalNode.parent)
        XCTAssertNil(fixture.originalNode.retainedLazyListRuntime)
        XCTAssertTrue(fixture.original.receipt.hasDeclaredComponent)
        let omission = try CandidateNamespaceUpdate(fixture: fixture, preserving: [])
        let write = try XCTUnwrap(
            omission.epoch.journal.prepareOwnedCandidateCatalog(from: omission.source, to: fixture.boundary))

        XCTAssertTrue(omission.epoch.journal.publishOwnedCandidateCatalog(write))

        XCTAssertFalse(fixture.original.receipt.hasDeclaredComponent)
        XCTAssertTrue(fixture.selected.receipt.hasDeclaredComponent)
        XCTAssertTrue(fixture.boundary.children.first === fixture.selectedNode)
        _ = omission.epoch.finish()
    }

    func testProofOnlyRotationPreservesMembershipButRequiresANewRootQualification() async throws {
        let slot = RetainedOwnedSlotGenerationID()
        let fixture = try CandidateNamespaceFixture(slots: [slot])
        try fixture.switchToCold()
        let originalRootOwner = fixture.runtime.root.lazyListActivityStorage().descriptorOwnerLifetime
        let stale = try CandidateNamespaceUpdate(fixture: fixture, preserving: [])
        let staleWrite = try XCTUnwrap(
            stale.epoch.journal.prepareOwnedCandidateCatalog(from: stale.source, to: fixture.boundary))
        let storage = fixture.boundary.lazyListActivityStorage()
        let originalAttachment = storage.captureActualAttachment(of: fixture.boundary, in: fixture.runtime)

        storage.revokeAttachment()

        XCTAssertFalse(originalAttachment.isAttached)
        XCTAssertTrue(originalRootOwner.isCurrent)
        XCTAssertTrue(fixture.boundaryOwner.receipt.hasDeclaredComponent)
        XCTAssertTrue(fixture.original.receipt.hasAcceptedOwnership(for: slot))
        XCTAssertFalse(stale.epoch.journal.publishOwnedCandidateCatalog(staleWrite))
        XCTAssertTrue(fixture.original.receipt.hasDeclaredComponent)
        _ = stale.epoch.finish()

        let fresh = try CandidateNamespaceUpdate(fixture: fixture, preserving: [])
        let freshWrite = try XCTUnwrap(
            fresh.epoch.journal.prepareOwnedCandidateCatalog(from: fresh.source, to: fixture.boundary))
        XCTAssertTrue(fresh.epoch.journal.publishOwnedCandidateCatalog(freshWrite))
        XCTAssertFalse(fixture.original.receipt.hasDeclaredComponent)
        XCTAssertFalse(fixture.original.receipt.permitsOwnedWrite(for: slot))
        XCTAssertFalse(stale.epoch.journal.publishOwnedCandidateCatalog(staleWrite))
        XCTAssertTrue(fixture.selected.receipt.hasDeclaredComponent)
        _ = fresh.epoch.finish()
    }

    func testStaleAndReplayedCatalogWritesCannotEraseNewerAcceptedMembership() async throws {
        let fixture = try CandidateNamespaceFixture()
        try fixture.switchToCold()
        let second = fixture.selected.receipt
        let stale = try CandidateNamespaceUpdate(fixture: fixture, preserving: [])
        let staleWrite = try XCTUnwrap(
            stale.epoch.journal.prepareOwnedCandidateCatalog(from: stale.source, to: fixture.boundary))
        let newer = try CandidateNamespaceUpdate(
            fixture: fixture, selected: nil, identity: 3, preserving: [fixture.original.receipt, second])

        try fixture.adopt(newer)

        XCTAssertTrue(fixture.original.receipt.hasDeclaredComponent)
        XCTAssertTrue(second.hasDeclaredComponent)
        XCTAssertFalse(stale.epoch.journal.publishOwnedCandidateCatalog(staleWrite))
        XCTAssertFalse(stale.epoch.journal.publishOwnedCandidateCatalog(staleWrite))
        XCTAssertTrue(fixture.original.receipt.hasDeclaredComponent)
        XCTAssertTrue(second.hasDeclaredComponent)
        XCTAssertTrue(fixture.selected.receipt.hasDeclaredComponent)
        _ = stale.epoch.finish()

        let omission = try CandidateNamespaceUpdate(fixture: fixture, preserving: [second])
        let write = try XCTUnwrap(
            omission.epoch.journal.prepareOwnedCandidateCatalog(from: omission.source, to: fixture.boundary))
        XCTAssertTrue(omission.epoch.journal.publishOwnedCandidateCatalog(write))
        XCTAssertFalse(fixture.original.receipt.hasDeclaredComponent)
        XCTAssertFalse(omission.epoch.journal.publishOwnedCandidateCatalog(write))
        XCTAssertTrue(second.hasDeclaredComponent)
        XCTAssertTrue(fixture.selected.receipt.hasDeclaredComponent)
        _ = omission.epoch.finish()
    }

    func testHostAndNativeOwnerRevocationDenyPreparedCatalogWrites() async throws {
        for revokeHost in [false, true] {
            let fixture = try CandidateNamespaceFixture()
            try fixture.switchToCold()
            let pending = try CandidateNamespaceUpdate(fixture: fixture, preserving: [])
            let write = try XCTUnwrap(
                pending.epoch.journal.prepareOwnedCandidateCatalog(from: pending.source, to: fixture.boundary))

            if revokeHost {
                fixture.runtime.lazyListLogicalHostLifetime.revoke()
            } else {
                fixture.runtime.root.lazyListActivityStorage().descriptorOwnerLifetime.revoke()
            }

            XCTAssertFalse(pending.epoch.journal.publishOwnedCandidateCatalog(write))
            XCTAssertFalse(fixture.original.receipt.hasDeclaredComponent)
            XCTAssertFalse(fixture.boundaryOwner.receipt.hasDeclaredComponent)
            _ = pending.epoch.finish()
        }
    }

    func testFreshRejectedCandidateNeverAcquiresAcceptedNamespaceMembership() async throws {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let epoch = CandidateNamespaceEpoch(runtime)
        let builder = try CandidateNamespaceBoundary(epoch: epoch)
        let rejectedNode = candidateNamespaceNode(1)
        let rejected = try epoch.component(nodes: [rejectedNode], under: builder)
        let selectedNode = candidateNamespaceNode(2)
        let selected = try epoch.component(nodes: [selectedNode], under: builder)
        // The first candidate was constructed but rejected by selection. Its
        // source is never attached or passed to an accepted publication.
        let boundary = try builder.close(child: selectedNode)
        epoch.begin(sources: [boundary])
        epoch.publishTree(boundary)
        _ = epoch.finish()

        XCTAssertNil(rejectedNode.parent)
        XCTAssertFalse(rejected.receipt.hasAcceptedDeclaration)
        XCTAssertFalse(rejected.receipt.hasDeclaredComponent)
        XCTAssertTrue(selected.receipt.hasDeclaredComponent)

        let later = CandidateNamespaceEpoch(runtime)
        let nextBoundary = try CandidateNamespaceBoundary(epoch: later, continuing: builder.owner.receipt)
        let attemptedPreservation = try XCTUnwrap(nextBoundary.owner.attribution.registerChildComponent())
        XCTAssertNil(
            attemptedPreservation.registerOwnedComponent(
                owner: rejected.receipt.owner, slots: rejected.receipt.slots, continuing: rejected.receipt,
                declarationOnly: true, candidateConstruction: nextBoundary.token))
        _ = later.finish(completed: false)
        XCTAssertTrue(selected.receipt.hasDeclaredComponent)
    }

    func testChildAcceptanceCannotMintAFieldBeforeTheDesignatedBoundaryPublishes() async throws {
        for publishBoundary in [false, true] {
            let runtime = RetainedViewRuntime(root: ViewNode())
            let epoch = CandidateNamespaceEpoch(runtime)
            let builder = try CandidateNamespaceBoundary(epoch: epoch)
            let child = candidateNamespaceNode(1)
            let member = try epoch.component(nodes: [child], under: builder)
            let ownerSupport = candidateNamespaceNode(90)
            let boundary = try builder.close(child: child, otherOwnerOutputs: [ownerSupport])
            epoch.begin(sources: [boundary, ownerSupport])
            epoch.prepareTree(boundary)
            epoch.prepareTree(ownerSupport)
            runtime.root.addChild(boundary)
            runtime.root.addChild(ownerSupport)
            epoch.publishPrepared(ownerSupport)
            epoch.publishPrepared(child)
            XCTAssertTrue(member.receipt.hasDeclaredComponent)
            XCTAssertTrue(builder.owner.receipt.hasDeclaredComponent)

            if publishBoundary { epoch.publishPrepared(boundary) }
            boundary.removeChild(child)

            // Owner presence remains alive through a different, genuinely
            // published output. Only publication on the staged boundary may
            // preserve this now physically absent candidate.
            XCTAssertTrue(builder.owner.receipt.hasDeclaredComponent)
            XCTAssertEqual(member.receipt.hasDeclaredComponent, publishBoundary)
            XCTAssertNil(child.parent)
            _ = epoch.finish()
        }
    }

    func testClosedEmptyAcceptanceUsesTheActualSubsetNotWeakScopeCompletion() async throws {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let slot = RetainedOwnedSlotGenerationID()
        let epoch = CandidateNamespaceEpoch(runtime)
        let builder = try CandidateNamespaceBoundary(epoch: epoch)
        // These are actual closed native groups with no source outputs, not
        // an EmptyView represented by an otherwise ordinary source node.
        let acceptedEmpty = try epoch.component(nodes: [], slots: [slot], under: builder, structure: true)
        let weakOnly = try epoch.component(nodes: [], under: builder, structure: true)
        let emptyAnchorNode = candidateNamespaceNode(10)
        let boundary = try builder.close(child: emptyAnchorNode)
        epoch.begin(sources: [boundary])
        epoch.publishTree(boundary)
        XCTAssertFalse(acceptedEmpty.receipt.hasAcceptedDeclaration)
        XCTAssertFalse(weakOnly.receipt.hasAcceptedDeclaration)
        let emptyAnchor = emptyAnchorNode.lazyListActivityStorage().captureActualAttachment(
            of: emptyAnchorNode, in: runtime)
        let facts = epoch.journal.recordAcceptedOrdinaryEmptyGroups(
            structuralAnchor: emptyAnchor, groups: [acceptedEmpty.group])
        XCTAssertEqual(facts.count, 1)
        XCTAssertTrue(try XCTUnwrap(facts.first).structuralAnchor === emptyAnchor)
        XCTAssertTrue(acceptedEmpty.receipt.hasAcceptedOwnership(for: slot))
        XCTAssertFalse(weakOnly.receipt.hasAcceptedDeclaration)

        let rootAnchor = runtime.root.lazyListActivityStorage().captureActualAttachment(of: runtime.root, in: runtime)
        XCTAssertTrue(epoch.journal.recordCompletedOwnedDescriptorScope(structuralAnchor: rootAnchor))
        XCTAssertTrue(weakOnly.receipt.hasAcceptedDeclaration)
        _ = epoch.finish()
        boundary.removeChild(emptyAnchorNode)
        XCTAssertTrue(acceptedEmpty.receipt.hasAcceptedOwnership(for: slot))

        // Give the weak-only declaration one real physical reference in a
        // later unscoped publication, then remove it while the boundary lives.
        // A namespace reference incorrectly granted by weak completion would
        // keep this zero-slot owner alive and fail the following assertion.
        let probeEpoch = CandidateNamespaceEpoch(runtime)
        let probeNode = candidateNamespaceNode(20)
        let probe = try probeEpoch.component(
            nodes: [probeNode], continuing: weakOnly.receipt)
        probeEpoch.begin(sources: [probeNode])
        probeEpoch.publishTree(probeNode)
        XCTAssertTrue(probe.receipt.hasDeclaredComponent)
        runtime.root.removeChild(probeNode)

        XCTAssertFalse(weakOnly.receipt.hasDeclaredComponent)
        XCTAssertFalse(probe.receipt.hasDeclaredComponent)
        XCTAssertTrue(acceptedEmpty.receipt.hasDeclaredComponent)
        runtime.root.removeChild(boundary)
        XCTAssertFalse(acceptedEmpty.receipt.hasDeclaredComponent)
        XCTAssertFalse(acceptedEmpty.receipt.permitsOwnedWrite(for: slot))
        _ = probeEpoch.finish()
    }

    func testRawStorageWithdrawalCannotBeRearmedByRestoringTheSameStorage() async throws {
        let fixture = try CandidateNamespaceFixture()
        try fixture.switchToCold()
        let pending = try CandidateNamespaceUpdate(fixture: fixture, preserving: [])
        let write = try XCTUnwrap(
            pending.epoch.journal.prepareOwnedCandidateCatalog(from: pending.source, to: fixture.boundary))
        let storage = fixture.boundary.lazyListActivityStorage()
        let oldAttachment = storage.captureActualAttachment(of: fixture.boundary, in: fixture.runtime)

        fixture.boundary.retainedLazyListActivityStorage = nil

        XCTAssertFalse(fixture.original.receipt.hasDeclaredComponent)
        fixture.boundary.retainedLazyListActivityStorage = storage
        XCTAssertTrue(oldAttachment.isAttached)
        XCTAssertFalse(pending.epoch.journal.publishOwnedCandidateCatalog(write))
        XCTAssertFalse(fixture.original.receipt.hasDeclaredComponent)
        _ = pending.epoch.finish()
    }

    func testPhysicalRemovalRetiresColdMembersBeforeDismantleCallback() async throws {
        let slot = RetainedOwnedSlotGenerationID()
        let fixture = try CandidateNamespaceFixture(slots: [slot])
        try fixture.switchToCold()
        var callbacks = 0
        fixture.boundary.onDismantlePlatformView = { departing in
            callbacks += 1
            XCTAssertNotNil(departing.parent)
            XCTAssertFalse(fixture.original.receipt.hasDeclaredComponent)
            XCTAssertFalse(fixture.original.receipt.permitsOwnedWrite(for: slot))
        }
        defer { fixture.boundary.onDismantlePlatformView = nil }

        fixture.runtime.root.removeChild(fixture.boundary)

        XCTAssertEqual(callbacks, 1)
        XCTAssertNil(fixture.boundary.parent)
        XCTAssertFalse(fixture.original.receipt.hasDeclaredComponent)
        XCTAssertFalse(fixture.selected.receipt.hasDeclaredComponent)
    }
}

@MainActor
private func candidateNamespaceNode(_ identity: Int) -> ViewNode {
    let node = ViewNode()
    node.retainedViewIdentity = RetainedViewIdentity().appending(.slot(identity))
    return node
}

@MainActor
private struct CandidateNamespaceComponent {
    let attribution: RetainedDescriptorComponentAttribution
    let receipt: RetainedOwnedComponentReceipt
    let group: RetainedDescriptorGroupID
}

@MainActor
private final class CandidateNamespaceEpoch {
    let runtime: RetainedViewRuntime
    let scope: RetainedLazyListDescriptorBuildScope
    let journal: RetainedLazyListAdoptionJournal

    init(_ runtime: RetainedViewRuntime) {
        self.runtime = runtime
        scope = RetainedLazyListDescriptorBuildScope(
            origin: .componentHostRoot, hostLifetime: runtime.lazyListLogicalHostLifetime,
            ownerLifetime: runtime.root.lazyListActivityStorage().descriptorOwnerLifetime)
        journal = RetainedLazyListAdoptionJournal(descriptorScope: scope, transaction: RetainedBuildTransaction())
        // Both original captures precede every component/body registration.
        // Never refresh either capture after a callback or a physical rotation.
        XCTAssertTrue(journal.seedOwnedCandidateOrigins(at: runtime.root))
        journal.seedExistingContributions(from: runtime.root.children)
    }

    func openComponent(
        slots: [RetainedOwnedSlotGenerationID] = [], continuing: RetainedOwnedComponentReceipt? = nil,
        parent: RetainedDescriptorComponentAttribution? = nil,
        candidateConstruction: RetainedOwnedCandidateConstruction? = nil,
        declarationOnly: Bool = false, structure: Bool = false
    ) throws -> CandidateNamespaceComponent {
        let attribution: RetainedDescriptorComponentAttribution
        if let parent {
            attribution = try XCTUnwrap(parent.registerChildComponent())
        } else {
            attribution = try XCTUnwrap(scope.registerOrdinaryComponent())
        }
        let receipt = try XCTUnwrap(
            attribution.registerOwnedComponent(
                owner: continuing?.owner ?? RetainedOwnedComponentID(), slots: slots, continuing: continuing,
                declarationOnly: declarationOnly, candidateConstruction: candidateConstruction))
        let group = try XCTUnwrap(attribution.registerGroup(kind: structure ? .structure : .observation))
        return CandidateNamespaceComponent(attribution: attribution, receipt: receipt, group: group)
    }

    func close(_ component: CandidateNamespaceComponent, nodes: [ViewNode]) throws {
        for node in nodes { XCTAssertTrue(component.attribution.recordSourceOutput(node, group: component.group)) }
        _ = try XCTUnwrap(component.attribution.closeGroup(component.group))
    }

    func component(
        nodes: [ViewNode], slots: [RetainedOwnedSlotGenerationID] = [],
        continuing: RetainedOwnedComponentReceipt? = nil, under boundary: CandidateNamespaceBoundary? = nil,
        declarationOnly: Bool = false, structure: Bool = false
    ) throws -> CandidateNamespaceComponent {
        let component = try openComponent(
            slots: slots, continuing: continuing, parent: boundary?.owner.attribution,
            candidateConstruction: boundary?.token, declarationOnly: declarationOnly, structure: structure)
        try close(component, nodes: nodes)
        return component
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

    func publishPrepared(_ node: ViewNode) {
        XCTAssertTrue(node.isRetainedLazyListAttached(in: runtime))
        _ = journal.recordAcceptedInsertedNode(on: node)
        _ = journal.recordCompletedNode(from: node, to: node)
    }

    func publishTree(_ node: ViewNode) {
        prepareTree(node)
        runtime.root.addChild(node)
        publishPreparedTree(node)
    }

    private func publishPreparedTree(_ node: ViewNode) {
        publishPrepared(node)
        for child in node.children { publishPreparedTree(child) }
    }

    @discardableResult
    func finish(completed: Bool = true) -> RetainedLazyListAdoptionDisposition {
        let disposition = journal.seal(completedCheckedAdoption: completed)
        journal.releaseUnadoptedTransport()
        scope.finish()
        return disposition
    }
}

@MainActor
private final class CandidateNamespaceBoundary {
    let epoch: CandidateNamespaceEpoch
    let owner: CandidateNamespaceComponent
    let token: RetainedOwnedCandidateConstruction

    init(epoch: CandidateNamespaceEpoch, continuing: RetainedOwnedComponentReceipt? = nil) throws {
        self.epoch = epoch
        owner = try epoch.openComponent(continuing: continuing)
        token = try XCTUnwrap(owner.attribution.beginOwnedCandidateConstruction(owner: owner.receipt))
    }

    func close(child: ViewNode, otherOwnerOutputs: [ViewNode] = []) throws -> ViewNode {
        let boundary = ViewNode.selectedContentBoundary(role: .viewThatFits, child: child)
        boundary.retainedViewIdentity = RetainedViewIdentity().appending(.slot(100))
        XCTAssertTrue(token.stageBoundary(on: boundary))
        try epoch.close(owner, nodes: [boundary] + otherOwnerOutputs)
        return boundary
    }
}

@MainActor
private final class CandidateNamespaceFixture {
    let runtime: RetainedViewRuntime
    let boundary: ViewNode
    let originalNode: ViewNode
    let original: CandidateNamespaceComponent
    private(set) var boundaryOwner: CandidateNamespaceComponent
    private(set) var selected: CandidateNamespaceComponent
    private(set) var selectedNode: ViewNode
    private(set) var selectedIdentity = 1

    init(slots: [RetainedOwnedSlotGenerationID] = []) throws {
        let runtime = RetainedViewRuntime(root: ViewNode())
        self.runtime = runtime
        let epoch = CandidateNamespaceEpoch(runtime)
        let builder = try CandidateNamespaceBoundary(epoch: epoch)
        let node = candidateNamespaceNode(1)
        let member = try epoch.component(nodes: [node], slots: slots, under: builder)
        originalNode = node
        original = member
        selectedNode = node
        selected = member
        boundaryOwner = builder.owner
        boundary = try builder.close(child: node)
        epoch.begin(sources: [boundary])
        epoch.publishTree(boundary)
        _ = epoch.finish()
        XCTAssertTrue(builder.owner.receipt.hasAcceptedDeclaration)
        XCTAssertTrue(member.receipt.hasAcceptedDeclaration)
        XCTAssertTrue(member.receipt.hasDeclaredComponent)
    }

    func switchToCold() throws {
        let update = try CandidateNamespaceUpdate(
            fixture: self, selected: nil, identity: 2, preserving: [original.receipt])
        try adopt(update)
        XCTAssertNil(originalNode.parent)
        XCTAssertTrue(original.receipt.hasDeclaredComponent)
    }

    func adopt(_ update: CandidateNamespaceUpdate) throws {
        let result = ComponentHost.adopt(source: update.source, into: boundary, lazyJournal: update.epoch.journal)
        _ = try XCTUnwrap(result.completed ? result : nil, "Expected complete native boundary reconciliation")
        boundaryOwner = update.builder.owner
        selected = update.selected
        selectedNode = update.selectedNode
        selectedIdentity = update.selectedIdentity
        _ = update.epoch.finish()
        XCTAssertTrue(selected.receipt.hasAcceptedDeclaration)
        XCTAssertTrue(selected.receipt.hasDeclaredComponent)
        XCTAssertTrue(boundary.children.first === selectedNode)
    }
}

@MainActor
private final class CandidateNamespaceUpdate {
    let epoch: CandidateNamespaceEpoch
    let builder: CandidateNamespaceBoundary
    let source: ViewNode
    let selected: CandidateNamespaceComponent
    let selectedNode: ViewNode
    let selectedIdentity: Int

    convenience init(fixture: CandidateNamespaceFixture, preserving: [RetainedOwnedComponentReceipt]) throws {
        try self.init(
            fixture: fixture, selected: fixture.selected.receipt, identity: fixture.selectedIdentity,
            preserving: preserving)
    }

    init(
        fixture: CandidateNamespaceFixture, selected continuing: RetainedOwnedComponentReceipt?,
        identity: Int, preserving: [RetainedOwnedComponentReceipt]
    ) throws {
        epoch = CandidateNamespaceEpoch(fixture.runtime)
        builder = try CandidateNamespaceBoundary(epoch: epoch, continuing: fixture.boundaryOwner.receipt)
        selectedIdentity = identity
        selectedNode = candidateNamespaceNode(identity)
        selected = try epoch.component(
            nodes: [selectedNode], slots: continuing?.slots ?? [], continuing: continuing, under: builder)
        for receipt in preserving {
            _ = try epoch.component(
                nodes: [], slots: receipt.slots, continuing: receipt, under: builder, declarationOnly: true,
                structure: true)
        }
        source = try builder.close(child: selectedNode)
        epoch.begin(sources: [source])
    }
}
