@preconcurrency import XCTest

@testable import SwiftWindowsUI

/// These use the native journal's original source records and real attached
/// nodes. No facade lookup, copied owner spelling, or fabricated plan is an
/// acceptance oracle for the dormant-to-physical ownership handoff.
@MainActor
final class RetainedDeclaredMarkerHandoffTests: XCTestCase {
    func testSameAttachmentPropertyPublicationRestoresOnlyTheOriginalSuspendedSlots() async throws {
        let fixture = try DeclaredMarkerHandoffFixture()
        defer { fixture.close() }
        let build = try fixture.successor()
        defer { _ = build.finish() }
        try build.begin()
        try build.removeDeclaration(on: fixture.marker)
        assertWrites(fixture, [false, false])
        XCTAssertTrue(fixture.original.hasDeclaredComponent)

        XCTAssertTrue(build.journal.preparePropertyCopy(from: build.source, to: fixture.marker, keyPath: \.opacity))
        fixture.marker.opacity = build.source.opacity
        _ = build.journal.recordAcceptedProperty(from: build.source, to: fixture.marker, keyPath: \.opacity)

        assertWrites(fixture, [true, true])
        let disposition = build.finish()
        XCTAssertTrue(disposition.retiredOwnedSlots.isEmpty)
        XCTAssertTrue(disposition.retiredOwnedComponents.isEmpty)
        XCTAssertTrue(disposition.acceptedOwnedComponents.contains { $0.plan.receipt === build.receipt })
        assertWrites(fixture, [true, true])
    }

    func testCompletedNormalSourceConsumesTheTicketWithoutRearmingItForALaterDeclaration() async throws {
        let fixture = try DeclaredMarkerHandoffFixture()
        defer { fixture.close() }
        let build = try fixture.successor()
        defer { _ = build.finish() }
        try build.begin()
        try build.removeDeclaration(on: fixture.marker)
        assertWrites(fixture, [false, false])
        _ = build.journal.recordCompletedNode(from: build.source, to: fixture.marker)
        assertWrites(fixture, [true, true])

        // A later independent declaration cannot refresh this original
        // journal's already consumed handoff simply by naming the same owner.
        let later = try fixture.successor(declarationOnly: true, continuing: build.receipt)
        try later.begin()
        try later.publishDormantDeclaration(on: fixture.marker)
        _ = later.finish()
        assertWrites(fixture, [true, true])
        try build.removeDeclaration(on: fixture.marker)

        assertWrites(fixture, [false, false])
        XCTAssertFalse(fixture.original.hasDeclaredComponent)
        XCTAssertFalse(build.journal.preparePropertyCopy(from: build.source, to: fixture.marker, keyPath: \.opacity))
        let disposition = build.finish()
        XCTAssertEqual(disposition.retiredOwnedSlots.count, 2)
        XCTAssertEqual(disposition.retiredOwnedComponents.count, 1)
    }

    func testAcceptedInsertedSourceRestoresTheExactContinuedGeneration() async throws {
        let fixture = try DeclaredMarkerHandoffFixture()
        defer { fixture.close() }
        let build = try fixture.successor()
        defer { _ = build.finish() }
        try build.begin()
        try build.removeDeclaration(on: fixture.marker)
        assertWrites(fixture, [false, false])
        fixture.runtime.root.addChild(build.source)
        XCTAssertTrue(build.journal.prepareInsertedNode(from: build.source))
        assertWrites(fixture, [false, false], "Attachment alone does not publish an owned footprint")

        _ = build.journal.recordAcceptedInsertedNode(on: build.source)

        assertWrites(fixture, [true, true])
        XCTAssertTrue(build.receipt.owner === fixture.original.owner)
        XCTAssertTrue(build.finish().retiredOwnedSlots.isEmpty)
    }

    func testOmittedSlotRetiresImmediatelyWhileItsExactSiblingWaitsForAcceptance() async throws {
        let fixture = try DeclaredMarkerHandoffFixture()
        defer { fixture.close() }
        let build = try fixture.successor(slots: [fixture.slots[0]])
        defer { _ = build.finish() }
        try build.begin()
        try build.removeDeclaration(on: fixture.marker)
        assertWrites(fixture, [false, false])
        XCTAssertTrue(fixture.original.hasDeclaredComponent)
        let refusalScope = RetainedLazyListDescriptorBuildScope(
            origin: .componentHostRoot, hostLifetime: fixture.runtime.lazyListLogicalHostLifetime,
            ownerLifetime: fixture.runtime.root.lazyListActivityStorage().descriptorOwnerLifetime)
        let refusal = try XCTUnwrap(refusalScope.registerOrdinaryComponent())
        XCTAssertNil(
            refusal.registerOwnedComponent(
                owner: fixture.owner, slots: [fixture.slots[1]], continuing: fixture.original),
            "An omitted generation is retired now, not merely suspended until seal")
        refusalScope.finish()
        _ = build.journal.recordCompletedNode(from: build.source, to: fixture.marker)

        assertWrites(fixture, [true, false])
        let disposition = build.finish()
        XCTAssertEqual(disposition.retiredOwnedSlots.map(ObjectIdentifier.init), [ObjectIdentifier(fixture.slots[1])])
        XCTAssertTrue(disposition.retiredOwnedComponents.isEmpty)
    }

    func testZeroSlotComponentPresenceSurvivesOnlyItsOriginalAcceptedNormalPublication() async throws {
        let fixture = try DeclaredMarkerHandoffFixture(slotCount: 0)
        defer { fixture.close() }
        let build = try fixture.successor()
        defer { _ = build.finish() }
        try build.begin()
        try build.removeDeclaration(on: fixture.marker)
        XCTAssertTrue(fixture.original.hasDeclaredComponent)

        _ = build.journal.recordCompletedNode(from: build.source, to: fixture.marker)

        XCTAssertTrue(build.receipt.hasDeclaredComponent)
        XCTAssertTrue(build.finish().retiredOwnedComponents.isEmpty)
        XCTAssertTrue(fixture.original.hasDeclaredComponent)
    }

    func testUnselectedRejectedAndEmptyNormalSourcesCannotPostponeDeclaredRetirement() async throws {
        for refusal in DeclaredMarkerSourceRefusal.allCases {
            let fixture = try DeclaredMarkerHandoffFixture()
            defer { fixture.close() }
            let build = try fixture.successor(hasSource: refusal != .empty)
            defer { _ = build.finish() }
            if refusal == .rejected { build.attribution.rejectConstruction() }
            try build.begin(selectOwned: refusal != .unselected)
            try build.removeDeclaration(on: fixture.marker)

            assertWrites(fixture, [false, false])
            XCTAssertFalse(fixture.original.hasDeclaredComponent, "Refused source: \(refusal)")
            let disposition = build.finish()
            XCTAssertEqual(disposition.retiredOwnedSlots.count, 2)
            XCTAssertEqual(disposition.retiredOwnedComponents.count, 1)
        }
    }

    func testForeignAttemptWithTheSameOwnerCannotConsumeTheOriginalSuspension() async throws {
        let fixture = try DeclaredMarkerHandoffFixture()
        defer { fixture.close() }
        let build = try fixture.successor()
        defer { _ = build.finish() }
        try build.begin()
        try build.removeDeclaration(on: fixture.marker)
        assertWrites(fixture, [false, false])
        let foreign = try fixture.successor(continuing: build.receipt)
        defer { _ = foreign.finish() }
        try foreign.begin()
        XCTAssertFalse(foreign.journal.attempt === build.journal.attempt)
        XCTAssertTrue(foreign.receipt.owner === build.receipt.owner)
        XCTAssertFalse(foreign.receipt.hasAcceptedDeclaration)
        _ = build.journal.recordCompletedNode(from: foreign.source, to: fixture.marker)
        assertWrites(fixture, [false, false], "A foreign source is not in the original frozen roster")

        XCTAssertTrue(foreign.journal.preparePropertyCopy(from: foreign.source, to: fixture.marker, keyPath: \.opacity))
        fixture.marker.opacity = foreign.source.opacity
        _ = foreign.journal.recordAcceptedProperty(from: foreign.source, to: fixture.marker, keyPath: \.opacity)
        XCTAssertTrue(foreign.receipt.hasAcceptedDeclaration)
        assertWrites(fixture, [false, false], "A later publication cannot consume an earlier attempt's ticket")

        _ = build.journal.recordCompletedNode(from: build.source, to: fixture.marker)
        assertWrites(fixture, [true, true])
        XCTAssertTrue(build.finish().retiredOwnedSlots.isEmpty)
    }

    func testChangedPropertyTargetAttachmentRejectsTheOriginalPreparedPublication() async throws {
        let fixture = try DeclaredMarkerHandoffFixture()
        defer { fixture.close() }
        let build = try fixture.successor()
        defer { _ = build.finish() }
        try build.begin()
        try build.removeDeclaration(on: fixture.marker)
        XCTAssertTrue(build.journal.preparePropertyCopy(from: build.source, to: fixture.marker, keyPath: \.opacity))
        fixture.marker.lazyListActivityStorage().revokeAttachment()
        _ = build.journal.recordAcceptedProperty(from: build.source, to: fixture.marker, keyPath: \.opacity)

        assertWrites(fixture, [false, false])
        let disposition = build.finish()
        XCTAssertFalse(disposition.acceptedOwnedComponents.contains { $0.plan.receipt === build.receipt })
        XCTAssertEqual(disposition.retiredOwnedSlots.count, 2)
        XCTAssertFalse(fixture.original.hasDeclaredComponent)
    }

    func testChangedInsertedAttachmentRejectsTheOriginalPreparedPublication() async throws {
        let fixture = try DeclaredMarkerHandoffFixture()
        defer { fixture.close() }
        let build = try fixture.successor()
        defer { _ = build.finish() }
        try build.begin()
        try build.removeDeclaration(on: fixture.marker)
        fixture.runtime.root.addChild(build.source)
        XCTAssertTrue(build.journal.prepareInsertedNode(from: build.source))
        build.source.lazyListActivityStorage().revokeAttachment()
        _ = build.journal.recordAcceptedInsertedNode(on: build.source)

        assertWrites(fixture, [false, false])
        XCTAssertEqual(build.finish().retiredOwnedSlots.count, 2)
        XCTAssertFalse(fixture.original.hasDeclaredComponent)
    }

    func testSealAndAbandonRetireUnfulfilledTicketsOnce() async throws {
        for abandons in [false, true] {
            let fixture = try DeclaredMarkerHandoffFixture()
            defer { fixture.close() }
            let build = try fixture.successor()
            defer { _ = build.finish() }
            try build.begin()
            try build.removeDeclaration(on: fixture.marker)
            assertWrites(fixture, [false, false])
            XCTAssertTrue(fixture.original.hasDeclaredComponent)
            if abandons {
                build.journal.revokeBeforeAbandon()
                build.journal.revokeBeforeAbandon()
                XCTAssertFalse(fixture.original.hasDeclaredComponent)
            }

            let disposition = build.finish()

            XCTAssertEqual(
                Set(disposition.retiredOwnedSlots.map(ObjectIdentifier.init)),
                Set(fixture.slots.map(ObjectIdentifier.init)))
            XCTAssertEqual(disposition.retiredOwnedSlots.count, 2)
            XCTAssertEqual(
                disposition.retiredOwnedComponents.map(ObjectIdentifier.init), [ObjectIdentifier(fixture.owner)])
            XCTAssertFalse(fixture.original.hasDeclaredComponent)
            assertWrites(fixture, [false, false])
            XCTAssertEqual(build.finish().retiredOwnedSlots.count, 2)
        }
    }

    func testHostRevocationPreventsADeferredMemberFromRegainingWrites() async throws {
        let fixture = try DeclaredMarkerHandoffFixture()
        defer { fixture.close() }
        let build = try fixture.successor()
        defer { _ = build.finish() }
        try build.begin()
        try build.removeDeclaration(on: fixture.marker)
        fixture.runtime.lazyListLogicalHostLifetime.revoke()

        XCTAssertFalse(build.journal.preparePropertyCopy(from: build.source, to: fixture.marker, keyPath: \.opacity))
        assertWrites(fixture, [false, false])
        XCTAssertFalse(fixture.original.hasDeclaredComponent)
        XCTAssertEqual(build.finish().retiredOwnedSlots.count, 2)
    }

    private func assertWrites(
        _ fixture: DeclaredMarkerHandoffFixture, _ expected: [Bool], _ message: String = "",
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let permissions = fixture.slots.map { fixture.original.permitsOwnedWrite(for: $0) }
        XCTAssertEqual(permissions, expected, message, file: file, line: line)
    }
}

private enum DeclaredMarkerSourceRefusal: CaseIterable { case unselected, rejected, empty }

@MainActor
private final class DeclaredMarkerHandoffFixture {
    let runtime: RetainedViewRuntime
    let marker: ViewNode
    let owner: RetainedOwnedComponentID
    let slots: [RetainedOwnedSlotGenerationID]
    let original: RetainedOwnedComponentReceipt

    init(slotCount: Int = 2) throws {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let marker = ViewNode()
        runtime.root.addChild(marker)
        let owner = RetainedOwnedComponentID()
        let slots = (0..<slotCount).map { _ in RetainedOwnedSlotGenerationID() }
        let initial = try DeclaredMarkerHandoffBuild(runtime: runtime, owner: owner, slots: slots)
        try initial.begin()
        _ = initial.journal.recordCompletedNode(from: initial.source, to: marker)
        let original = initial.receipt
        XCTAssertTrue(original.hasDeclaredComponent)
        XCTAssertTrue(slots.allSatisfy { original.permitsOwnedWrite(for: $0) })
        _ = initial.finish()
        let dormant = try DeclaredMarkerHandoffBuild(
            runtime: runtime, owner: owner, slots: slots, continuing: original, declarationOnly: true)
        try dormant.begin()
        try dormant.publishDormantDeclaration(on: marker)
        _ = dormant.finish()
        XCTAssertTrue(original.hasDeclaredComponent)
        XCTAssertTrue(slots.allSatisfy { original.permitsOwnedWrite(for: $0) })
        self.runtime = runtime
        self.marker = marker
        self.owner = owner
        self.slots = slots
        self.original = original
    }

    func successor(
        slots: [RetainedOwnedSlotGenerationID]? = nil, declarationOnly: Bool = false,
        continuing: RetainedOwnedComponentReceipt? = nil, hasSource: Bool = true
    ) throws -> DeclaredMarkerHandoffBuild {
        try DeclaredMarkerHandoffBuild(
            runtime: runtime, owner: owner, slots: slots ?? self.slots, continuing: continuing ?? original,
            declarationOnly: declarationOnly, hasSource: hasSource)
    }

    func close() {
        runtime.lazyListLogicalHostLifetime.revoke()
        runtime.root.removeAllChildren()
    }
}

@MainActor
private final class DeclaredMarkerHandoffBuild {
    let scope: RetainedLazyListDescriptorBuildScope
    let journal: RetainedLazyListAdoptionJournal
    let attribution: RetainedDescriptorComponentAttribution
    let receipt: RetainedOwnedComponentReceipt
    let source: ViewNode
    let markerSource: ViewNode

    init(
        runtime: RetainedViewRuntime, owner: RetainedOwnedComponentID, slots: [RetainedOwnedSlotGenerationID],
        continuing: RetainedOwnedComponentReceipt? = nil, declarationOnly: Bool = false, hasSource: Bool = true
    ) throws {
        let scope = RetainedLazyListDescriptorBuildScope(
            origin: .componentHostRoot, hostLifetime: runtime.lazyListLogicalHostLifetime,
            ownerLifetime: runtime.root.lazyListActivityStorage().descriptorOwnerLifetime)
        let journal = RetainedLazyListAdoptionJournal(descriptorScope: scope, transaction: RetainedBuildTransaction())
        let source = ViewNode()
        let markerSource = ViewNode()
        let markerAttribution = try XCTUnwrap(scope.registerOrdinaryComponent())
        let markerGroup = try XCTUnwrap(markerAttribution.registerGroup(kind: .structure))
        XCTAssertTrue(markerAttribution.recordSourceOutput(markerSource, group: markerGroup))
        XCTAssertNotNil(markerAttribution.closeGroup(markerGroup))
        let attribution = try XCTUnwrap(scope.registerOrdinaryComponent())
        let receipt = try XCTUnwrap(
            attribution.registerOwnedComponent(
                owner: owner, slots: slots, continuing: continuing, declarationOnly: declarationOnly))
        if hasSource {
            let group = try XCTUnwrap(attribution.registerGroup(kind: .structure))
            XCTAssertTrue(attribution.recordSourceOutput(source, group: group))
            XCTAssertNotNil(attribution.closeGroup(group))
        }
        self.scope = scope
        self.journal = journal
        self.attribution = attribution
        self.receipt = receipt
        self.source = source
        self.markerSource = markerSource
    }

    func begin(selectOwned: Bool = true) throws {
        let preparation = try XCTUnwrap(journal.preparation())
        XCTAssertTrue(
            journal.beginAdoption(
                preparation,
                preparedActivity: RetainedLazyListPreparedActivity(
                    preparation: preparation, logicalMembershipPlans: [],
                    ownedComponentPlans: selectOwned ? preparation.ownedComponentDeclarations : [])))
        XCTAssertTrue(journal.markMutationStarted())
    }

    func removeDeclaration(on target: ViewNode) throws {
        XCTAssertTrue(journal.prepareOwnedStructuralDeclaration(from: markerSource, to: target))
        journal.recordAcceptedOwnedStructuralDeclaration(from: markerSource, to: target)
    }

    func publishDormantDeclaration(on target: ViewNode) throws {
        XCTAssertTrue(journal.prepareOwnedStructuralDeclaration(from: source, to: target))
        journal.recordAcceptedOwnedStructuralDeclaration(from: source, to: target)
        _ = journal.recordCompletedNode(from: source, to: target)
    }

    @discardableResult
    func finish() -> RetainedLazyListAdoptionDisposition {
        let disposition = journal.seal()
        journal.releaseUnadoptedTransport()
        scope.finish()
        return disposition
    }
}
