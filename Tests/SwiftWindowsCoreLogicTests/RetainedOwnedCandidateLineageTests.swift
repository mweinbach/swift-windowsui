import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI

/// W and M stay mounted while I departs. Cold members held by W still belong
/// to the original M-to-I declaration lineage; an M-only omission must retire
/// them without waiting for I to return or for W's catalog to be rewritten.
@MainActor
final class RetainedOwnedCandidateLineageTests: XCTestCase {
    func testIntermediateOnlyOmissionRetiresAcceptedColdCustodyBeforeDismantle() async throws {
        for hasStateSlot in [false, true] {
            let fixture = try LineageFixture(hasStateSlot: hasStateSlot)
            try fixture.makeOriginalCold()
            let proposed = try fixture.plan(includesInner: true, preservesOriginal: true)
            proposed.begin()
            try proposed.epoch.publishCatalog(from: proposed.source, to: fixture.outerNode)
            var innerDismantles = 0
            fixture.innerNode.onDismantlePlatformView = { _ in
                innerDismantles += 1
                fixture.assertOriginalAlive()
                fixture.assertOuterNamespacesCurrent()
            }
            defer { fixture.innerNode.onDismantlePlatformView = nil }

            // No M catalog or incoming I node is accepted in this attempt.
            // Original I's real O cut must acquire custody in accepted W before
            // the following physical removal reaches its dismantle callback.
            proposed.epoch.departOriginalSubtree(fixture.innerNode, from: fixture.panelNode)
            _ = proposed.epoch.finish(completed: false)

            XCTAssertEqual(innerDismantles, 1)
            XCTAssertNil(fixture.innerNode.parent)
            XCTAssertNil(fixture.innerNode.retainedLazyListRuntime)
            XCTAssertTrue(fixture.panelNode.parent === fixture.middleNode)
            XCTAssertTrue(fixture.panelNode.children.isEmpty)
            fixture.assertOriginalAlive()
            fixture.assertOuterNamespacesCurrent()
            let omission = try fixture.plan(
                includesInner: false, preservesOriginal: false, panelIdentity: 4001)
            omission.begin()
            var panelDismantles = 0
            fixture.panelNode.onDismantlePlatformView = { oldPanel in
                panelDismantles += 1
                XCTAssertTrue(oldPanel === fixture.panelNode)
                XCTAssertTrue(oldPanel.parent === fixture.middleNode)
                fixture.assertOriginalRetired()
                fixture.assertOuterNamespacesCurrent()
            }
            defer { fixture.panelNode.onDismantlePlatformView = nil }

            // Only M is reconciled. W's native catalog is not rewritten, and
            // no incoming I publication can opportunistically drain its copies.
            let result = ComponentHost.adopt(
                source: omission.middleNode, into: fixture.middleNode, lazyJournal: omission.epoch.journal)

            XCTAssertTrue(result.completed)
            XCTAssertEqual(panelDismantles, 1)
            XCTAssertNil(fixture.panelNode.parent)
            XCTAssertTrue(fixture.middleNode.children.first === omission.panelNode)
            fixture.assertOriginalRetired()
            fixture.assertOuterNamespacesCurrent()
            _ = omission.epoch.finish()
        }
    }

    func testForeignIntermediateOmissionDeniesPendingOriginalLineageAtDeparture() async throws {
        for hasStateSlot in [false, true] {
            let fixture = try LineageFixture(hasStateSlot: hasStateSlot)
            try fixture.makeOriginalCold()
            let pending = try fixture.plan(includesInner: true, preservesOriginal: true)
            pending.begin()
            try pending.epoch.publishCatalog(from: pending.source, to: fixture.outerNode)
            let donorAttachment = fixture.innerNode.lazyListActivityStorage().captureActualAttachment(
                of: fixture.innerNode, in: fixture.runtime)
            let receiverAttachment = fixture.outerNode.lazyListActivityStorage().captureActualAttachment(
                of: fixture.outerNode, in: fixture.runtime)
            let foreign = try fixture.plan(
                includesInner: false, preservesOriginal: false, panelIdentity: 4001)
            foreign.begin()

            // This accepted field write omits M's I declaration but does not
            // change the physical panel or I. Donor/receiver attachment queries
            // therefore cannot stand in for the original intermediate link.
            try foreign.epoch.publishCatalog(from: foreign.middleNode, to: fixture.middleNode)
            _ = foreign.epoch.finish(completed: false)

            XCTAssertTrue(donorAttachment.isAttached)
            XCTAssertTrue(receiverAttachment.isAttached)
            XCTAssertTrue(fixture.innerNode.parent === fixture.panelNode)
            XCTAssertTrue(fixture.innerOwner.receipt.hasDeclaredComponent)
            fixture.assertOriginalAlive()
            fixture.assertOuterNamespacesCurrent()
            var dismantles = 0
            fixture.innerNode.onDismantlePlatformView = { _ in
                dismantles += 1
                fixture.assertOriginalRetired()
                fixture.assertOuterNamespacesCurrent()
            }
            defer { fixture.innerNode.onDismantlePlatformView = nil }

            pending.epoch.departOriginalSubtree(fixture.innerNode, from: fixture.panelNode)

            XCTAssertEqual(dismantles, 1)
            XCTAssertNil(fixture.innerNode.parent)
            XCTAssertTrue(fixture.panelNode.children.isEmpty)
            fixture.assertOriginalRetired()
            fixture.assertOuterNamespacesCurrent()
            _ = pending.epoch.finish(completed: false)
        }
    }
}

@MainActor
private func lineageNode(_ identity: Int) -> ViewNode {
    let node = ViewNode()
    node.retainedViewIdentity = RetainedViewIdentity().appending(.slot(identity))
    return node
}

@MainActor
private struct LineageComponent {
    let attribution: RetainedDescriptorComponentAttribution
    let receipt: RetainedOwnedComponentReceipt
    let group: RetainedDescriptorGroupID
}

@MainActor
private final class LineageEpoch {
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
        under boundary: LineageBoundary? = nil, declarationOnly: Bool = false
    ) throws -> LineageComponent {
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
        return LineageComponent(attribution: attribution, receipt: receipt, group: group)
    }

    func close(_ component: LineageComponent, nodes: [ViewNode]) throws {
        for node in nodes { XCTAssertTrue(component.attribution.recordSourceOutput(node, group: component.group)) }
        _ = try XCTUnwrap(component.attribution.closeGroup(component.group))
    }

    func component(
        nodes: [ViewNode], slots: [RetainedOwnedSlotGenerationID] = [],
        continuing: RetainedOwnedComponentReceipt? = nil, under boundary: LineageBoundary,
        declarationOnly: Bool = false
    ) throws -> LineageComponent {
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
        var original: [ViewNode] = []
        var pending = [root]
        while let node = pending.popLast() {
            original.append(node)
            pending.append(contentsOf: node.children.reversed())
        }
        // The ordinary native O cut precedes real child removal. No namespace
        // reference, field revision, or replacement acceptance is forged here.
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
private final class LineageBoundary {
    let epoch: LineageEpoch
    let owner: LineageComponent
    let token: RetainedOwnedCandidateConstruction

    init(
        epoch: LineageEpoch, continuing: RetainedOwnedComponentReceipt? = nil,
        under parent: LineageBoundary? = nil
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
private final class LineagePlan {
    let epoch: LineageEpoch
    let outer: LineageBoundary
    let middle: LineageBoundary
    let inner: LineageBoundary?
    let source: ViewNode
    let middleNode: ViewNode
    let panelNode: ViewNode
    let innerNode: ViewNode?
    let selected: LineageComponent?
    let selectedNode: ViewNode?
    let selectedIdentity: Int

    init(
        runtime: RetainedViewRuntime, continuing fixture: LineageFixture?, includesInner: Bool,
        selectedReceipt: RetainedOwnedComponentReceipt?, selectedIdentity: Int,
        selectedSlots: [RetainedOwnedSlotGenerationID], preserving: [RetainedOwnedComponentReceipt],
        panelIdentity: Int = 4000
    ) throws {
        epoch = LineageEpoch(runtime)
        outer = try LineageBoundary(epoch: epoch, continuing: fixture?.outerOwner.receipt)
        middle = try LineageBoundary(epoch: epoch, continuing: fixture?.middleOwner.receipt, under: outer)
        self.selectedIdentity = selectedIdentity
        panelNode = lineageNode(panelIdentity)
        if includesInner {
            let boundary = try LineageBoundary(epoch: epoch, continuing: fixture?.innerOwner.receipt, under: middle)
            inner = boundary
            let child = lineageNode(selectedIdentity)
            selectedNode = child
            selected = try epoch.component(
                nodes: [child], slots: selectedSlots, continuing: selectedReceipt, under: boundary)
            for receipt in preserving {
                _ = try epoch.component(
                    nodes: [], slots: receipt.slots, continuing: receipt, under: boundary, declarationOnly: true)
            }
            let node = try boundary.close(child: child, identity: 3000)
            innerNode = node
            panelNode.addChild(node)
        } else {
            inner = nil
            innerNode = nil
            selected = nil
            selectedNode = nil
        }
        middleNode = try middle.close(child: panelNode, identity: 2000)
        source = try outer.close(child: middleNode, identity: 1000)
    }

    func begin() { epoch.begin(source: source) }
}

@MainActor
private final class LineageFixture {
    let runtime: RetainedViewRuntime
    let outerNode: ViewNode
    let middleNode: ViewNode
    let panelNode: ViewNode
    let innerNode: ViewNode
    let originalNode: ViewNode
    let original: LineageComponent
    let originalSlot: RetainedOwnedSlotGenerationID?
    private(set) var outerOwner: LineageComponent
    private(set) var middleOwner: LineageComponent
    private(set) var innerOwner: LineageComponent
    private(set) var selected: LineageComponent
    private(set) var selectedIdentity: Int

    init(hasStateSlot: Bool) throws {
        let runtime = RetainedViewRuntime(root: ViewNode())
        self.runtime = runtime
        let slot = hasStateSlot ? RetainedOwnedSlotGenerationID() : nil
        originalSlot = slot
        let first = try LineagePlan(
            runtime: runtime, continuing: nil, includesInner: true,
            selectedReceipt: nil, selectedIdentity: 1, selectedSlots: slot.map { [$0] } ?? [], preserving: [])
        outerNode = first.source
        middleNode = first.middleNode
        panelNode = first.panelNode
        innerNode = try XCTUnwrap(first.innerNode)
        outerOwner = first.outer.owner
        middleOwner = first.middle.owner
        innerOwner = try XCTUnwrap(first.inner).owner
        original = try XCTUnwrap(first.selected)
        originalNode = try XCTUnwrap(first.selectedNode)
        selected = original
        selectedIdentity = first.selectedIdentity
        first.begin()
        first.epoch.publishTree(first.source)
        _ = first.epoch.finish()
        XCTAssertTrue(original.receipt.hasAcceptedDeclaration)
        assertOriginalAlive()
        assertOuterNamespacesCurrent()
    }

    func makeOriginalCold() throws {
        let next = try LineagePlan(
            runtime: runtime, continuing: self, includesInner: true,
            selectedReceipt: nil, selectedIdentity: selectedIdentity + 1, selectedSlots: [],
            preserving: [original.receipt])
        next.begin()
        let result = ComponentHost.adopt(source: next.source, into: outerNode, lazyJournal: next.epoch.journal)
        _ = try XCTUnwrap(result.completed ? result : nil, "Expected complete native cold-candidate selection")
        outerOwner = next.outer.owner
        middleOwner = next.middle.owner
        innerOwner = try XCTUnwrap(next.inner).owner
        selected = try XCTUnwrap(next.selected)
        selectedIdentity = next.selectedIdentity
        _ = next.epoch.finish()
        XCTAssertTrue(outerNode.children.first === middleNode)
        XCTAssertTrue(middleNode.children.first === panelNode)
        XCTAssertTrue(panelNode.children.first === innerNode)
        XCTAssertNil(originalNode.parent)
        XCTAssertNil(originalNode.retainedLazyListRuntime)
        assertOriginalAlive()
    }

    func plan(
        includesInner: Bool, preservesOriginal: Bool, panelIdentity: Int = 4000
    ) throws -> LineagePlan {
        try LineagePlan(
            runtime: runtime, continuing: self, includesInner: includesInner,
            selectedReceipt: includesInner ? selected.receipt : nil, selectedIdentity: selectedIdentity,
            selectedSlots: includesInner ? selected.receipt.slots : [],
            preserving: preservesOriginal ? [original.receipt] : [], panelIdentity: panelIdentity)
    }

    func assertOriginalAlive(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(original.receipt.hasDeclaredComponent, file: file, line: line)
        if let originalSlot {
            XCTAssertTrue(original.receipt.hasAcceptedOwnership(for: originalSlot), file: file, line: line)
            XCTAssertTrue(original.receipt.permitsOwnedWrite(for: originalSlot), file: file, line: line)
        }
    }

    func assertOriginalRetired(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(original.receipt.hasDeclaredComponent, file: file, line: line)
        if let originalSlot {
            XCTAssertFalse(original.receipt.hasAcceptedOwnership(for: originalSlot), file: file, line: line)
            XCTAssertFalse(original.receipt.permitsOwnedWrite(for: originalSlot), file: file, line: line)
        }
    }

    func assertOuterNamespacesCurrent(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(outerOwner.receipt.hasDeclaredComponent, file: file, line: line)
        XCTAssertTrue(middleOwner.receipt.hasDeclaredComponent, file: file, line: line)
        XCTAssertTrue(outerNode.isRetainedLazyListAttached(in: runtime), file: file, line: line)
        XCTAssertTrue(middleNode.isRetainedLazyListAttached(in: runtime), file: file, line: line)
        XCTAssertTrue(middleNode.parent === outerNode, file: file, line: line)
    }
}
