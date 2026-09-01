@preconcurrency import XCTest

@testable import SwiftWindowsUI

/// Native preparation must distinguish a list descriptor lease from a reader's
/// single owned child region. These exercise the real owned ledger with actual
/// source nodes; no attachment, reader callback, or State publication is needed
/// to reject a malformed region.
@MainActor
final class RetainedDeferredLeaseSourceTests: XCTestCase {
    func testGeometryReaderLeaseRejectsAMissingReaderSourceBeforeMutation() async throws {
        try assertPreparation(kind: .deferredSubtree, readers: 0, isAdmitted: false)
    }

    func testGeometryReaderLeaseRejectsTwoReaderSourcesForOneOwnedRegion() async throws {
        try assertPreparation(kind: .deferredSubtree, readers: 2, isAdmitted: false)
    }

    func testGeometryReaderLeaseAdmitsItsSingleReaderSource() async throws {
        try assertPreparation(kind: .deferredSubtree, readers: 1, isAdmitted: true)
    }

    func testListLeaseAdmitsANonReaderSourceWithoutAReaderRegion() async throws {
        try assertPreparation(kind: .lazyList, readers: 0, isAdmitted: true)
    }

    private func assertPreparation(
        kind: RetainedLazyListContributionKind, readers: Int, isAdmitted: Bool,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let fixture = try DeferredLeaseSourceFixture(kind: kind, readers: readers)
        defer { fixture.finish() }
        let preparation = try XCTUnwrap(fixture.journal.preparation(), file: file, line: line)
        let plan = try XCTUnwrap(preparation.ownedComponentDeclarations.first, file: file, line: line)
        XCTAssertEqual(preparation.ownedComponentDeclarations.count, 1, file: file, line: line)
        XCTAssertTrue(plan.receipt === fixture.receipt, file: file, line: line)
        XCTAssertTrue(plan.receipt.slots.isEmpty, "A zero-slot owner still declares a region", file: file, line: line)
        XCTAssertEqual(plan.sourcePayloads.count, fixture.nodes.count, file: file, line: line)
        XCTAssertEqual(preparation.groups.map(\.kind), [kind], file: file, line: line)
        XCTAssertEqual(fixture.nodes.filter { $0.geometryReaderBuild != nil }.count, readers, file: file, line: line)
        XCTAssertFalse(fixture.journal.canContinueAdoption, file: file, line: line)

        let admitted = fixture.journal.beginAdoption(
            preparation,
            preparedActivity: RetainedLazyListPreparedActivity(
                preparation: preparation, logicalMembershipPlans: [],
                ownedComponentPlans: preparation.ownedComponentDeclarations))

        XCTAssertEqual(admitted, isAdmitted, file: file, line: line)
        XCTAssertEqual(fixture.journal.canContinueAdoption, isAdmitted, file: file, line: line)
        XCTAssertEqual(fixture.journal.markMutationStarted(), isAdmitted, file: file, line: line)
        XCTAssertFalse(fixture.journal.hasAcceptedContributions, file: file, line: line)
        XCTAssertFalse(fixture.receipt.hasAcceptedDeclaration, file: file, line: line)
        XCTAssertFalse(fixture.receipt.hasDeclaredComponent, file: file, line: line)
        XCTAssertTrue(fixture.nodes.allSatisfy { $0.parent == nil }, file: file, line: line)
        XCTAssertEqual(fixture.probe.readerCalls, 0, file: file, line: line)
        XCTAssertEqual(fixture.probe.factoryCalls, 0, file: file, line: line)
    }
}

@MainActor
private final class DeferredLeaseSourceProbe {
    var readerCalls = 0
    var factoryCalls = 0
}

@MainActor
private final class DeferredLeaseSourceFixture {
    let hostLifetime: RetainedLazyListLogicalHostLifetime
    let ownerLifetime: RetainedLazyListDescriptorOwnerLifetime
    let scope: RetainedLazyListDescriptorBuildScope
    let provider: RetainedLazyListDataSource<Int, [ViewNode]>
    let journal: RetainedLazyListAdoptionJournal
    let receipt: RetainedOwnedComponentReceipt
    let nodes: [ViewNode]
    let probe: DeferredLeaseSourceProbe

    init(kind: RetainedLazyListContributionKind, readers: Int) throws {
        let hostLifetime = RetainedLazyListLogicalHostLifetime()
        let ownerLifetime = RetainedLazyListDescriptorOwnerLifetime(
            target: RetainedLazyListTargetID(), attachment: RetainedLazyListAttachmentID())
        let scope = RetainedLazyListDescriptorBuildScope(
            origin: .componentHostRoot, hostLifetime: hostLifetime, ownerLifetime: ownerLifetime)
        let journal = RetainedLazyListAdoptionJournal(descriptorScope: scope, transaction: RetainedBuildTransaction())
        let logical = try XCTUnwrap(RetainedLazyListLogicalMembershipScope(in: scope, parentRow: nil))
        let membership = try XCTUnwrap(logical.proposeMembership(id: RetainedLazyListMembershipID()))
        let probe = DeferredLeaseSourceProbe()
        let provider = RetainedLazyListDataSource<Int, [ViewNode]>()
        XCTAssertTrue(
            provider.replaceData([0], id: \.self) { _ in
                probe.factoryCalls += 1
                return []
            })
        let token = try XCTUnwrap(provider.metadata?.rows.first?.token)
        let request = try XCTUnwrap(provider.request(for: token))
        let attribution = RetainedLazyListBuildAttribution(
            journal: journal, rowRequest: request, logicalMembership: membership,
            physical: RetainedLazyListPhysicalActivityReceipt(membership: membership.id),
            component: RetainedLazyListComponentID(), resolutionID: RetainedLazyListRowResolutionID(),
            origin: .selectedRow)
        let receipt = try XCTUnwrap(attribution.registerOwnedComponent(owner: RetainedOwnedComponentID(), slots: []))
        let group = try XCTUnwrap(attribution.registerGroup(kind: kind))
        let nodes = (0..<max(1, readers)).map { _ in ViewNode() }
        for node in nodes {
            if readers > 0 {
                node.geometryReaderBuild = { _, _ in
                    probe.readerCalls += 1
                    return []
                }
            }
            XCTAssertNotNil(attribution.recordSourceOutput(node, group: group))
        }
        XCTAssertNotNil(attribution.closeGroup(group))
        self.hostLifetime = hostLifetime
        self.ownerLifetime = ownerLifetime
        self.scope = scope
        self.provider = provider
        self.journal = journal
        self.receipt = receipt
        self.nodes = nodes
        self.probe = probe
    }

    func finish() {
        _ = journal.seal()
        provider.close()
        scope.finish()
    }
}
