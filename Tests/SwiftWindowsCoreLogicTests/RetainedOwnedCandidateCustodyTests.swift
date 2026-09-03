import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI

/// Custody must be accepted at the original native departure cut. A prepared
/// incoming boundary cannot preserve a member, and an unused transfer proposal
/// cannot leave an extra outer reference that masks a later inner omission.
@MainActor
final class RetainedOwnedCandidateCustodyTests: XCTestCase {
    func testActualInnerReplacementPreservesColdMemberThenInnerOnlyOmissionRetiresIt() async throws {
        let fixture = try CustodyFixture()
        try fixture.makeOriginalCold()
        let oldInner = fixture.innerNode
        var dismantles = 0
        oldInner.onDismantlePlatformView = { departing in
            dismantles += 1
            XCTAssertTrue(departing === oldInner)
            XCTAssertTrue(fixture.original.receipt.hasDeclaredComponent)
            XCTAssertTrue(fixture.original.receipt.hasAcceptedOwnership(for: fixture.originalSlot))
        }
        defer { oldInner.onDismantlePlatformView = nil }
        let replacement = try fixture.plan(
            innerIdentity: fixture.innerIdentity + 1, preserving: [fixture.original.receipt])
        replacement.begin()

        try fixture.adopt(replacement)

        XCTAssertEqual(dismantles, 1)
        XCTAssertNil(oldInner.parent)
        XCTAssertNil(oldInner.retainedLazyListRuntime)
        XCTAssertFalse(fixture.innerNode === oldInner)
        XCTAssertTrue(fixture.innerOwner.receipt.hasAcceptedDeclaration)
        XCTAssertTrue(fixture.original.receipt.hasDeclaredComponent)
        try fixture.omitOriginalThroughInnerCatalogOnly()
        XCTAssertFalse(fixture.original.receipt.permitsOwnedWrite(for: fixture.originalSlot))
    }

    func testRefusedReceiverProofOrHostStillPerformsOriginalNativeDeparture() async throws {
        for revokeHost in [false, true] {
            let fixture = try CustodyFixture()
            try fixture.makeOriginalCold()
            let oldInner = fixture.innerNode
            let originalParent = fixture.innerParent
            let proposed = try fixture.plan(
                innerIdentity: fixture.innerIdentity + 1, preserving: [fixture.original.receipt])
            proposed.begin()
            try proposed.epoch.publishCatalog(from: proposed.source, to: fixture.outerNode)
            XCTAssertTrue(fixture.original.receipt.hasDeclaredComponent)
            let receiverStorage = fixture.outerNode.lazyListActivityStorage()
            let originalReceiverAttachment = receiverStorage.captureActualAttachment(
                of: fixture.outerNode, in: fixture.runtime)
            let originalRootOwner = fixture.runtime.root.lazyListActivityStorage().descriptorOwnerLifetime
            var dismantles = 0
            oldInner.onDismantlePlatformView = { _ in
                dismantles += 1
                XCTAssertFalse(fixture.original.receipt.hasDeclaredComponent)
                XCTAssertFalse(fixture.original.receipt.permitsOwnedWrite(for: fixture.originalSlot))
            }
            defer { oldInner.onDismantlePlatformView = nil }

            if revokeHost {
                fixture.runtime.lazyListLogicalHostLifetime.revoke()
            } else {
                receiverStorage.revokeAttachment()
                XCTAssertFalse(originalReceiverAttachment.isAttached)
                XCTAssertTrue(originalRootOwner.isCurrent)
                // The donor is still accepted: only the prepared receiver proof
                // has expired. Its later real withdrawal must not be skipped.
                XCTAssertTrue(fixture.original.receipt.hasDeclaredComponent)
            }
            proposed.epoch.departOriginalSubtree(oldInner, from: originalParent)

            XCTAssertEqual(dismantles, 1)
            XCTAssertNil(oldInner.parent)
            XCTAssertNil(oldInner.retainedLazyListRuntime)
            XCTAssertFalse(fixture.original.receipt.hasDeclaredComponent)
            XCTAssertFalse(fixture.original.receipt.hasAcceptedOwnership(for: fixture.originalSlot))
            _ = proposed.epoch.finish(completed: false)
        }
    }

    func testMatchedInnerWithoutDepartureDoesNotAcquireMaskingOuterCustody() async throws {
        let fixture = try CustodyFixture()
        try fixture.makeOriginalCold()
        let oldInner = fixture.innerNode
        let partial = try fixture.plan(preserving: [fixture.original.receipt])
        partial.begin()

        try partial.epoch.publishCatalog(from: partial.source, to: fixture.outerNode)
        _ = partial.epoch.finish(completed: false)

        // The outer catalog was accepted, but this attempt never touched the
        // actual inner node or published its incoming counterpart.
        XCTAssertTrue(fixture.innerNode === oldInner)
        XCTAssertTrue(oldInner.parent === fixture.innerParent)
        XCTAssertTrue(fixture.original.receipt.hasDeclaredComponent)
        try fixture.omitOriginalThroughInnerCatalogOnly()
    }

    func testOverlappingOuterProposalsCannotLeaveMultipleAncestorMasks() async throws {
        for replacesInner in [false, true] {
            let fixture = try CustodyFixture(nested: true)
            try fixture.makeOriginalCold()
            let oldInner = fixture.innerNode
            let middle = try XCTUnwrap(fixture.middleNode)
            var dismantles = 0
            oldInner.onDismantlePlatformView = { _ in
                dismantles += 1
                XCTAssertTrue(fixture.original.receipt.hasDeclaredComponent)
            }
            defer { oldInner.onDismantlePlatformView = nil }
            let proposed = try fixture.plan(
                innerIdentity: fixture.innerIdentity + (replacesInner ? 1 : 0),
                preserving: [fixture.original.receipt])
            proposed.begin()

            if replacesInner {
                try fixture.adopt(proposed)
            } else {
                try proposed.epoch.publishCatalog(from: proposed.source, to: fixture.outerNode)
                try proposed.epoch.publishCatalog(from: try XCTUnwrap(proposed.middleNode), to: middle)
                _ = proposed.epoch.finish(completed: false)
            }

            XCTAssertEqual(dismantles, replacesInner ? 1 : 0)
            XCTAssertTrue(fixture.middleNode === middle)
            XCTAssertTrue(fixture.outerOwner.receipt.hasDeclaredComponent)
            XCTAssertTrue(try XCTUnwrap(fixture.middleOwner).receipt.hasDeclaredComponent)
            XCTAssertTrue(fixture.original.receipt.hasDeclaredComponent)
            // Deliberately do not rewrite either outer catalog here. Any extra
            // accepted copy left in W or M would keep the omitted member alive.
            try fixture.omitOriginalThroughInnerCatalogOnly()
        }
    }

    func testUnselectedFreshNormalCandidateNeverReceivesDepartureCustody() async throws {
        let fixture = try CustodyFixture()
        try fixture.makeOriginalCold()
        let proposed = try fixture.plan(
            innerIdentity: fixture.innerIdentity + 1, preserving: [fixture.original.receipt],
            includesUnselectedFreshCandidate: true)
        let rejected = try XCTUnwrap(proposed.unselectedFresh)
        let rejectedNode = try XCTUnwrap(proposed.unselectedFreshNode)
        proposed.begin()

        try fixture.adopt(proposed)

        XCTAssertNil(rejectedNode.parent)
        XCTAssertNil(rejectedNode.retainedLazyListRuntime)
        XCTAssertFalse(rejected.receipt.hasAcceptedDeclaration)
        XCTAssertFalse(rejected.receipt.hasDeclaredComponent)
        XCTAssertTrue(fixture.original.receipt.hasDeclaredComponent)
        XCTAssertTrue(fixture.selected.receipt.hasDeclaredComponent)
        try fixture.omitOriginalThroughInnerCatalogOnly()
        XCTAssertFalse(rejected.receipt.hasDeclaredComponent)
    }

    func testRejectedSelectedSourceCannotPreserveAnUnacceptedFreshOwner() async throws {
        let fixture = try CustodyFixture()
        try fixture.makeOriginalCold()
        let proposed = try fixture.plan(
            innerIdentity: fixture.innerIdentity + 1, preserving: [fixture.original.receipt],
            selectsFreshCandidate: true, rejectsSelectedSource: true)
        XCTAssertTrue(proposed.source.containsRejectedRetainedSource)
        XCTAssertFalse(proposed.epoch.journal.registerSourceDescriptors(in: [proposed.source]))
        XCTAssertFalse(proposed.epoch.journal.beginOrdinaryAdoption())

        let result = ComponentHost.adopt(
            source: proposed.source, into: fixture.outerNode, lazyJournal: proposed.epoch.journal)

        XCTAssertFalse(result.completed)
        XCTAssertFalse(proposed.selected.receipt.hasAcceptedDeclaration)
        XCTAssertFalse(proposed.selected.receipt.hasDeclaredComponent)
        XCTAssertTrue(fixture.original.receipt.hasDeclaredComponent)
        fixture.innerParent.removeChild(fixture.innerNode)
        XCTAssertFalse(fixture.original.receipt.hasDeclaredComponent)
        XCTAssertFalse(proposed.selected.receipt.hasDeclaredComponent)
        _ = proposed.epoch.finish(completed: false)
    }

    func testRevisionCapacityUsesCheckedArithmeticWithoutMutatingNativeFields() async throws {
        // This freezes arithmetic behavior, not a claim that a native field was
        // driven through UInt64.max revisions or that any authority was granted.
        let cases: [(UInt64, UInt64, Bool)] = [
            (0, 0, true), (0, 1, true), (0, .max, true),
            (.max, 0, true), (.max, 1, false), (.max, .max, false),
            (.max - 1, 1, true), (.max - 1, 2, false), (1, .max, false),
        ]
        for (current, additional, expected) in cases {
            XCTAssertEqual(
                RetainedOwnedCandidateRevisionCapacity.permits(current: current, additional: additional), expected,
                "current=\(current), additional=\(additional)")
        }
    }
}

@MainActor
private func custodyNode(_ identity: Int) -> ViewNode {
    let node = ViewNode()
    node.retainedViewIdentity = RetainedViewIdentity().appending(.slot(identity))
    return node
}

@MainActor
private struct CustodyComponent {
    let attribution: RetainedDescriptorComponentAttribution
    let receipt: RetainedOwnedComponentReceipt
    let group: RetainedDescriptorGroupID
}

@MainActor
private final class CustodyEpoch {
    let runtime: RetainedViewRuntime
    let scope: RetainedLazyListDescriptorBuildScope
    let journal: RetainedLazyListAdoptionJournal

    init(_ runtime: RetainedViewRuntime) {
        self.runtime = runtime
        scope = RetainedLazyListDescriptorBuildScope(
            origin: .componentHostRoot, hostLifetime: runtime.lazyListLogicalHostLifetime,
            ownerLifetime: runtime.root.lazyListActivityStorage().descriptorOwnerLifetime)
        journal = RetainedLazyListAdoptionJournal(descriptorScope: scope, transaction: RetainedBuildTransaction())
        XCTAssertTrue(journal.seedOwnedCandidateOrigins(at: runtime.root))
        journal.seedExistingContributions(from: runtime.root.children)
    }

    func openComponent(
        slots: [RetainedOwnedSlotGenerationID] = [], continuing: RetainedOwnedComponentReceipt? = nil,
        under boundary: CustodyBoundary? = nil, declarationOnly: Bool = false
    ) throws -> CustodyComponent {
        let attribution: RetainedDescriptorComponentAttribution
        if let boundary {
            attribution = try XCTUnwrap(boundary.owner.attribution.registerChildComponent())
        } else {
            attribution = try XCTUnwrap(scope.registerOrdinaryComponent())
        }
        let receipt = try XCTUnwrap(
            attribution.registerOwnedComponent(
                owner: continuing?.owner ?? RetainedOwnedComponentID(), slots: slots, continuing: continuing,
                declarationOnly: declarationOnly, candidateConstruction: boundary?.token))
        let group = try XCTUnwrap(attribution.registerGroup(kind: declarationOnly ? .structure : .observation))
        return CustodyComponent(attribution: attribution, receipt: receipt, group: group)
    }

    func close(_ component: CustodyComponent, nodes: [ViewNode]) throws {
        for node in nodes { XCTAssertTrue(component.attribution.recordSourceOutput(node, group: component.group)) }
        _ = try XCTUnwrap(component.attribution.closeGroup(component.group))
    }

    func component(
        nodes: [ViewNode], slots: [RetainedOwnedSlotGenerationID] = [],
        continuing: RetainedOwnedComponentReceipt? = nil, under boundary: CustodyBoundary,
        declarationOnly: Bool = false
    ) throws -> CustodyComponent {
        let result = try openComponent(
            slots: slots, continuing: continuing, under: boundary, declarationOnly: declarationOnly)
        try close(result, nodes: nodes)
        return result
    }

    func begin(source: ViewNode) {
        XCTAssertTrue(journal.registerSourceDescriptors(in: [source]))
        XCTAssertTrue(journal.beginOrdinaryAdoption())
        XCTAssertTrue(journal.markMutationStarted())
    }

    func publishTree(_ node: ViewNode) {
        prepareTree(node)
        runtime.root.addChild(node)
        publishPreparedTree(node)
    }

    private func prepareTree(_ node: ViewNode) {
        XCTAssertTrue(journal.prepareInsertedNode(from: node))
        for child in node.children { prepareTree(child) }
    }

    private func publishPreparedTree(_ node: ViewNode) {
        XCTAssertTrue(node.isRetainedLazyListAttached(in: runtime))
        _ = journal.recordAcceptedInsertedNode(on: node)
        _ = journal.recordCompletedNode(from: node, to: node)
        for child in node.children { publishPreparedTree(child) }
    }

    func publishCatalog(from source: ViewNode, to target: ViewNode) throws {
        let write = try XCTUnwrap(journal.prepareOwnedCandidateCatalog(from: source, to: target))
        XCTAssertTrue(journal.publishOwnedCandidateCatalog(write))
    }

    func departOriginalSubtree(_ root: ViewNode, from parent: ViewNode) {
        XCTAssertTrue(root.parent === parent)
        XCTAssertTrue(root.isRetainedLazyListAttached(in: runtime))
        // Mirror the ordinary setter's finite original cohort and O cut before
        // the real child removal. These are native journal calls, not fabricated
        // namespace references, replacement publications, or Task claims.
        var original: [ViewNode] = []
        var pending = [root]
        while let node = pending.popLast() {
            original.append(node)
            pending.append(contentsOf: node.children.reversed())
        }
        var departures: [RetainedOrdinaryOwnedDeparture] = []
        for node in original {
            if let departure = journal.recordOrdinaryPhysicalDeparture(of: node, cause: .acceptedReplacement) {
                departures.append(departure)
            }
        }
        parent.removeChild(root)
        for departure in departures { journal.finishOrdinaryOwnedDeparture(departure) }
    }

    @discardableResult
    func finish(completed: Bool = true) -> RetainedLazyListAdoptionDisposition {
        let result = journal.seal(completedCheckedAdoption: completed)
        journal.releaseUnadoptedTransport()
        scope.finish()
        return result
    }
}

@MainActor
private final class CustodyBoundary {
    let epoch: CustodyEpoch
    let owner: CustodyComponent
    let token: RetainedOwnedCandidateConstruction

    init(
        epoch: CustodyEpoch, continuing: RetainedOwnedComponentReceipt? = nil,
        under parent: CustodyBoundary? = nil
    ) throws {
        self.epoch = epoch
        owner = try epoch.openComponent(continuing: continuing, under: parent)
        token = try XCTUnwrap(owner.attribution.beginOwnedCandidateConstruction(owner: owner.receipt))
    }

    func close(child: ViewNode, identity: Int) throws -> ViewNode {
        let node = ViewNode.selectedContentBoundary(role: .viewThatFits, child: child)
        node.retainedViewIdentity = RetainedViewIdentity().appending(.slot(identity))
        XCTAssertTrue(token.stageBoundary(on: node))
        try epoch.close(owner, nodes: [node])
        return node
    }
}

@MainActor
private final class CustodyPlan {
    let epoch: CustodyEpoch
    let outer: CustodyBoundary
    let middle: CustodyBoundary?
    let inner: CustodyBoundary
    let source: ViewNode
    let middleNode: ViewNode?
    let innerNode: ViewNode
    let innerIdentity: Int
    let selected: CustodyComponent
    let selectedNode: ViewNode
    let selectedIdentity: Int
    let unselectedFresh: CustodyComponent?
    let unselectedFreshNode: ViewNode?

    init(
        runtime: RetainedViewRuntime, continuing fixture: CustodyFixture?, nested: Bool,
        innerIdentity: Int, selectedReceipt: RetainedOwnedComponentReceipt?, selectedIdentity: Int,
        selectedSlots: [RetainedOwnedSlotGenerationID], preserving: [RetainedOwnedComponentReceipt],
        includesUnselectedFreshCandidate: Bool = false, rejectsSelectedSource: Bool = false
    ) throws {
        epoch = CustodyEpoch(runtime)
        outer = try CustodyBoundary(epoch: epoch, continuing: fixture?.outerOwner.receipt)
        if nested {
            middle = try CustodyBoundary(
                epoch: epoch, continuing: fixture?.middleOwner?.receipt, under: outer)
        } else {
            middle = nil
        }
        inner = try CustodyBoundary(
            epoch: epoch, continuing: fixture?.innerOwner.receipt, under: middle ?? outer)
        self.innerIdentity = innerIdentity
        self.selectedIdentity = selectedIdentity
        if includesUnselectedFreshCandidate {
            let unused = custodyNode(90)
            unselectedFreshNode = unused
            unselectedFresh = try epoch.component(nodes: [unused], under: inner)
        } else {
            unselectedFreshNode = nil
            unselectedFresh = nil
        }
        selectedNode = custodyNode(selectedIdentity)
        selected = try epoch.component(
            nodes: [selectedNode], slots: selectedSlots, continuing: selectedReceipt, under: inner)
        for receipt in preserving {
            _ = try epoch.component(
                nodes: [], slots: receipt.slots, continuing: receipt, under: inner, declarationOnly: true)
        }
        innerNode = try inner.close(child: selectedNode, identity: innerIdentity)
        if let middle {
            let node = try middle.close(child: innerNode, identity: 2000)
            middleNode = node
            source = try outer.close(child: node, identity: 1000)
        } else {
            middleNode = nil
            source = try outer.close(child: innerNode, identity: 1000)
        }
        if rejectsSelectedSource { selected.attribution.rejectComponent() }
    }

    func begin() { epoch.begin(source: source) }
}

@MainActor
private final class CustodyFixture {
    let runtime: RetainedViewRuntime
    let outerNode: ViewNode
    let originalNode: ViewNode
    let original: CustodyComponent
    let originalSlot: RetainedOwnedSlotGenerationID
    private(set) var outerOwner: CustodyComponent
    private(set) var middleOwner: CustodyComponent?
    private(set) var innerOwner: CustodyComponent
    private(set) var middleNode: ViewNode?
    private(set) var innerNode: ViewNode
    private(set) var innerIdentity: Int
    private(set) var selected: CustodyComponent
    private(set) var selectedIdentity: Int

    var innerParent: ViewNode { middleNode ?? outerNode }

    init(nested: Bool = false) throws {
        let runtime = RetainedViewRuntime(root: ViewNode())
        self.runtime = runtime
        let slot = RetainedOwnedSlotGenerationID()
        originalSlot = slot
        let first = try CustodyPlan(
            runtime: runtime, continuing: nil, nested: nested, innerIdentity: 3000,
            selectedReceipt: nil, selectedIdentity: 1, selectedSlots: [slot], preserving: [])
        outerNode = first.source
        outerOwner = first.outer.owner
        middleOwner = first.middle?.owner
        middleNode = first.middleNode
        innerOwner = first.inner.owner
        innerNode = first.innerNode
        innerIdentity = first.innerIdentity
        original = first.selected
        originalNode = first.selectedNode
        selected = first.selected
        selectedIdentity = first.selectedIdentity
        first.begin()
        first.epoch.publishTree(first.source)
        _ = first.epoch.finish()
        XCTAssertTrue(outerOwner.receipt.hasAcceptedDeclaration)
        XCTAssertTrue(innerOwner.receipt.hasAcceptedDeclaration)
        XCTAssertTrue(original.receipt.hasAcceptedOwnership(for: slot))
    }

    func makeOriginalCold() throws {
        let next = try plan(preserving: [original.receipt], selectsFreshCandidate: true)
        next.begin()
        try adopt(next)
        XCTAssertNil(originalNode.parent)
        XCTAssertNil(originalNode.retainedLazyListRuntime)
        XCTAssertTrue(original.receipt.hasDeclaredComponent)
        XCTAssertTrue(original.receipt.hasAcceptedOwnership(for: originalSlot))
    }

    func plan(
        innerIdentity: Int? = nil, preserving: [RetainedOwnedComponentReceipt],
        includesUnselectedFreshCandidate: Bool = false, selectsFreshCandidate: Bool = false,
        rejectsSelectedSource: Bool = false
    ) throws -> CustodyPlan {
        try CustodyPlan(
            runtime: runtime, continuing: self, nested: middleNode != nil,
            innerIdentity: innerIdentity ?? self.innerIdentity,
            selectedReceipt: selectsFreshCandidate ? nil : selected.receipt,
            selectedIdentity: selectsFreshCandidate ? selectedIdentity + 1 : selectedIdentity,
            selectedSlots: selectsFreshCandidate ? [] : selected.receipt.slots, preserving: preserving,
            includesUnselectedFreshCandidate: includesUnselectedFreshCandidate,
            rejectsSelectedSource: rejectsSelectedSource)
    }

    func adopt(_ plan: CustodyPlan) throws {
        let result = ComponentHost.adopt(source: plan.source, into: outerNode, lazyJournal: plan.epoch.journal)
        _ = try XCTUnwrap(result.completed ? result : nil, "Expected complete native namespace reconciliation")
        outerOwner = plan.outer.owner
        middleOwner = plan.middle?.owner
        if plan.middle != nil { middleNode = try XCTUnwrap(outerNode.children.first) }
        innerNode = try XCTUnwrap(innerParent.children.first)
        innerOwner = plan.inner.owner
        innerIdentity = plan.innerIdentity
        selected = plan.selected
        selectedIdentity = plan.selectedIdentity
        _ = plan.epoch.finish()
        XCTAssertTrue(innerNode.parent === innerParent)
        XCTAssertTrue(innerNode.retainedLazyListRuntime === runtime)
        XCTAssertTrue(innerOwner.receipt.hasAcceptedDeclaration)
        XCTAssertTrue(selected.receipt.hasDeclaredComponent)
    }

    func omitOriginalThroughInnerCatalogOnly() throws {
        let oldInner = innerNode
        let oldOuter = outerNode
        let omission = try plan(preserving: [])
        omission.begin()
        try omission.epoch.publishCatalog(from: omission.innerNode, to: innerNode)
        XCTAssertFalse(original.receipt.hasDeclaredComponent)
        XCTAssertFalse(original.receipt.hasAcceptedOwnership(for: originalSlot))
        XCTAssertTrue(selected.receipt.hasDeclaredComponent)
        XCTAssertTrue(innerNode === oldInner)
        XCTAssertTrue(outerNode === oldOuter)
        XCTAssertTrue(innerNode.parent === innerParent)
        XCTAssertTrue(outerOwner.receipt.hasDeclaredComponent)
        _ = omission.epoch.finish(completed: false)
    }
}
