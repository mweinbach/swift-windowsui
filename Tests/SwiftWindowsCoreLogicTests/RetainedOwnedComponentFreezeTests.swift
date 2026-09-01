@preconcurrency import XCTest

@testable import SwiftWindowsUI

/// Native source rosters and construction preparation only. Visit counts do
/// not measure elapsed time, total freeze work, or accepted runtime adoption.
@MainActor
final class RetainedOwnedComponentFreezeTests: XCTestCase {
    func testSourceIndexMatchesStableReferenceWithRepeatedAncestryPayloadsAndFacets() async {
        let child = RetainedOwnedComponentDeclarationOrigin.lazy(component: RetainedLazyListComponentID())
        let ancestor = RetainedOwnedComponentDeclarationOrigin.lazy(component: RetainedLazyListComponentID())
        let firstPayload = RetainedLazyListSourcePayloadID()
        let secondPayload = RetainedLazyListSourcePayloadID()
        let thirdPayload = RetainedLazyListSourcePayloadID()
        let firstFacet = RetainedLazyListSourceFacetID()
        let secondFacet = RetainedLazyListSourceFacetID()
        let thirdFacet = RetainedLazyListSourceFacetID()
        let independentFacet = RetainedLazyListSourceFacetID()
        let sources = [
            RetainedOwnedComponentSource(
                node: nil, payload: firstPayload, facets: [firstFacet, secondFacet, firstFacet],
                components: [child, child, ancestor], deferredRoot: nil),
            RetainedOwnedComponentSource(
                node: nil, payload: firstPayload, facets: [thirdFacet, secondFacet],
                components: [child], deferredRoot: nil),
            RetainedOwnedComponentSource(
                node: nil, payload: secondPayload, facets: [],
                components: [ancestor, child], deferredRoot: nil),
            RetainedOwnedComponentSource(
                node: nil, payload: thirdPayload, facets: [independentFacet],
                components: [ancestor], deferredRoot: nil),
        ]

        for ordered in [sources, Array(sources.reversed())] {
            let index = RetainedOwnedComponentSourceIndex(sources: ordered)

            XCTAssertEqual(index.componentVisits, 7)
            XCTAssertEqual(index.sourceMembershipCount, 6)
            for origin in [child, ancestor] {
                assertOwnedFreezeRoster(index.roster(for: origin, in: ordered), for: origin, in: ordered)
            }
        }

        let childRoster = RetainedOwnedComponentSourceIndex(sources: sources).roster(for: child, in: sources)
        XCTAssertEqual(
            childRoster.payloads.map(ObjectIdentifier.init),
            [firstPayload, secondPayload].map(ObjectIdentifier.init))
        XCTAssertEqual(
            childRoster.facets.map(ObjectIdentifier.init),
            [firstFacet, secondFacet, thirdFacet].map(ObjectIdentifier.init))
    }

    func testSourceIndexKeepsOrdinaryLazyUnownedAndAbsentSourcesSeparate() async {
        let lazy = RetainedOwnedComponentDeclarationOrigin.lazy(component: RetainedLazyListComponentID())
        let ordinary = RetainedOwnedComponentDeclarationOrigin.descriptor(component: RetainedDescriptorComponentID())
        let absentLazy = RetainedOwnedComponentDeclarationOrigin.lazy(component: RetainedLazyListComponentID())
        let absentOrdinary = RetainedOwnedComponentDeclarationOrigin.descriptor(
            component: RetainedDescriptorComponentID())
        let lazyPayload = RetainedLazyListSourcePayloadID()
        let ordinaryPayload = RetainedLazyListSourcePayloadID()
        let zeroFacetPayload = RetainedLazyListSourcePayloadID()
        let lazyFacet = RetainedLazyListSourceFacetID()
        let ordinaryFacet = RetainedLazyListSourceFacetID()
        let sources = [
            RetainedOwnedComponentSource(
                node: nil, payload: lazyPayload, facets: [lazyFacet], components: [lazy], deferredRoot: nil),
            RetainedOwnedComponentSource(
                node: nil, payload: ordinaryPayload, facets: [ordinaryFacet],
                components: [ordinary], deferredRoot: nil),
            RetainedOwnedComponentSource(
                node: nil, payload: zeroFacetPayload, facets: [], components: [lazy], deferredRoot: nil),
            RetainedOwnedComponentSource(
                node: nil, payload: RetainedLazyListSourcePayloadID(), facets: [RetainedLazyListSourceFacetID()],
                components: [], deferredRoot: nil),
        ]
        let index = RetainedOwnedComponentSourceIndex(sources: sources)

        XCTAssertEqual(index.componentVisits, 3)
        XCTAssertEqual(index.sourceMembershipCount, 3)
        for origin in [lazy, ordinary, absentLazy, absentOrdinary] {
            assertOwnedFreezeRoster(index.roster(for: origin, in: sources), for: origin, in: sources)
        }
        XCTAssertEqual(
            index.roster(for: lazy, in: sources).payloads.map(ObjectIdentifier.init),
            [lazyPayload, zeroFacetPayload].map(ObjectIdentifier.init))
        XCTAssertTrue(index.roster(for: ordinary, in: sources).payloads.first === ordinaryPayload)

        let empty = RetainedOwnedComponentSourceIndex(sources: [])
        XCTAssertEqual(empty.componentVisits, 0)
        XCTAssertEqual(empty.sourceMembershipCount, 0)
        assertOwnedFreezeRoster(empty.roster(for: lazy, in: []), for: lazy, in: [])
    }

    func testSourceIndexKeepsNativeMetadataWhenItsWeakSourceNodeExpires() async {
        var node: ViewNode? = ViewNode()
        weak var observedNode = node
        let origin = RetainedOwnedComponentDeclarationOrigin.lazy(component: RetainedLazyListComponentID())
        let payload = RetainedLazyListSourcePayloadID()
        let facet = RetainedLazyListSourceFacetID()
        let sources = [
            RetainedOwnedComponentSource(
                node: node, payload: payload, facets: [facet], components: [origin], deferredRoot: nil)
        ]
        let index = RetainedOwnedComponentSourceIndex(sources: sources)

        node = nil

        XCTAssertNil(observedNode)
        XCTAssertNil(sources[0].node)
        let roster = index.roster(for: origin, in: sources)
        assertOwnedFreezeRoster(roster, for: origin, in: sources)
        XCTAssertTrue(roster.payloads.first === payload)
        XCTAssertTrue(roster.facets.first === facet)
    }

    func testSourceIndexDoesNotRetainSourceNodesOrNativeTokens() async {
        let probe = OwnedFreezeWeakProbe()
        let index = makeEphemeralOwnedFreezeIndex(probe: probe)

        withExtendedLifetime(index) {
            XCTAssertEqual(index.componentVisits, 1)
            XCTAssertEqual(index.sourceMembershipCount, 1)
            XCTAssertNil(probe.node)
            XCTAssertNil(probe.payload)
            XCTAssertNil(probe.facet)
            XCTAssertNil(probe.component)
        }
    }

    func testCommonAncestorSourceQueriesVisitOnlyTheirRecordedMemberships() async {
        for count in [4, 16, 64] {
            let ancestor = RetainedOwnedComponentDeclarationOrigin.lazy(component: RetainedLazyListComponentID())
            let leaves = (0..<count).map { _ in
                RetainedOwnedComponentDeclarationOrigin.lazy(component: RetainedLazyListComponentID())
            }
            let sharedFacet = RetainedLazyListSourceFacetID()
            let sources = leaves.map { leaf in
                let facet = RetainedLazyListSourceFacetID()
                return RetainedOwnedComponentSource(
                    node: nil, payload: RetainedLazyListSourcePayloadID(), facets: [facet, sharedFacet, facet],
                    components: [leaf, ancestor], deferredRoot: nil)
            }
            let index = RetainedOwnedComponentSourceIndex(sources: sources)
            XCTAssertEqual(index.componentVisits, 2 * count)
            XCTAssertEqual(index.sourceMembershipCount, 2 * count)
            let common = index.roster(for: ancestor, in: sources)
            var oldWork = assertOwnedFreezeRoster(common, for: ancestor, in: sources)
            XCTAssertEqual(oldWork.facetComparisons, count * count + 4 * count - 3)
            XCTAssertEqual(common.payloads.count, count)
            XCTAssertEqual(common.facets.count, count + 1)
            var sourceVisits = common.sourceVisits
            var payloadChecks = common.payloadMembershipChecks
            var facetChecks = common.facetMembershipChecks

            for leaf in leaves {
                let roster = index.roster(for: leaf, in: sources)
                let referenceWork = assertOwnedFreezeRoster(roster, for: leaf, in: sources)
                oldWork.componentComparisons += referenceWork.componentComparisons
                oldWork.payloadComparisons += referenceWork.payloadComparisons
                oldWork.facetComparisons += referenceWork.facetComparisons
                XCTAssertEqual(roster.sourceVisits, 1)
                sourceVisits += roster.sourceVisits
                payloadChecks += roster.payloadMembershipChecks
                facetChecks += roster.facetMembershipChecks
            }

            // Separate original linear-scan comparisons from new native set
            // membership attempts; neither counts hash probes or all freeze work.
            XCTAssertEqual(sourceVisits, 2 * count)
            XCTAssertEqual(payloadChecks, 2 * count)
            XCTAssertEqual(facetChecks, 6 * count)
            XCTAssertEqual(oldWork.componentComparisons, 2 * count * count + count)
            XCTAssertEqual(oldWork.payloadComparisons, count * (count - 1) / 2)
            XCTAssertEqual(oldWork.facetComparisons, count * count + 6 * count - 3)
        }
    }

    func testNestedSourceQueriesCountTheActualAncestorAssociationFootprint() async {
        for count in [4, 8, 16] {
            let ancestors = (0..<count).map { _ in
                RetainedOwnedComponentDeclarationOrigin.descriptor(component: RetainedDescriptorComponentID())
            }
            let sources = (0..<count).map { position in
                RetainedOwnedComponentSource(
                    node: nil, payload: RetainedLazyListSourcePayloadID(), facets: [RetainedLazyListSourceFacetID()],
                    components: Array(ancestors.prefix(position + 1).reversed()), deferredRoot: nil)
            }
            let index = RetainedOwnedComponentSourceIndex(sources: sources)
            let associations = count * (count + 1) / 2
            XCTAssertEqual(index.componentVisits, associations)
            XCTAssertEqual(index.sourceMembershipCount, associations)
            var sourceVisits = 0
            var facetChecks = 0
            var oldWork = OwnedFreezeReferenceWork()

            for (position, ancestor) in ancestors.enumerated() {
                let roster = index.roster(for: ancestor, in: sources)
                let referenceWork = assertOwnedFreezeRoster(roster, for: ancestor, in: sources)
                oldWork.componentComparisons += referenceWork.componentComparisons
                oldWork.payloadComparisons += referenceWork.payloadComparisons
                oldWork.facetComparisons += referenceWork.facetComparisons
                XCTAssertEqual(roster.sourceVisits, count - position)
                sourceVisits += roster.sourceVisits
                facetChecks += roster.facetMembershipChecks
            }

            // Nested owners have a triangular output footprint; the index
            // must not claim that all freeze work is linear in source count.
            XCTAssertEqual(sourceVisits, associations)
            XCTAssertEqual(facetChecks, associations)
            XCTAssertEqual(oldWork.componentComparisons, count * (count + 1) * (2 * count + 1) / 6)
            XCTAssertEqual(oldWork.payloadComparisons, count * (count + 1) * (count - 1) / 6)
            XCTAssertEqual(oldWork.facetComparisons, count * (count + 1) * (count - 1) / 6)
        }
    }

    func testOrdinaryPreparationPreservesAncestorSiblingEmptyAndRejectedOwnedPlans() async throws {
        let fixture = try OwnedFreezeConstructionFixture()
        defer { fixture.finish() }
        let root = try XCTUnwrap(fixture.scope.registerOrdinaryComponent())
        let child = try XCTUnwrap(root.registerChildComponent())
        let sibling = try XCTUnwrap(fixture.scope.registerOrdinaryComponent())
        let empty = try XCTUnwrap(fixture.scope.registerOrdinaryComponent())
        let rejected = try XCTUnwrap(root.registerChildComponent())
        let rootSlot = RetainedOwnedSlotGenerationID()
        let childSlot = RetainedOwnedSlotGenerationID()
        let rootReceipt = try XCTUnwrap(
            root.registerOwnedComponent(owner: RetainedOwnedComponentID(), slots: [rootSlot]))
        let childReceipt = try XCTUnwrap(
            child.registerOwnedComponent(owner: RetainedOwnedComponentID(), slots: [childSlot]))
        let siblingReceipt = try XCTUnwrap(
            sibling.registerOwnedComponent(owner: RetainedOwnedComponentID(), slots: [RetainedOwnedSlotGenerationID()]))
        let emptyReceipt = try XCTUnwrap(empty.registerOwnedComponent(owner: RetainedOwnedComponentID(), slots: []))
        let rejectedReceipt = try XCTUnwrap(
            rejected.registerOwnedComponent(
                owner: RetainedOwnedComponentID(), slots: [RetainedOwnedSlotGenerationID()]))
        let childSources = [ViewNode(), ViewNode()]
        let siblingSource = ViewNode()
        defer { withExtendedLifetime((childSources, siblingSource)) {} }
        let childGroup = try XCTUnwrap(child.registerGroup(kind: .structure))
        for source in childSources { XCTAssertTrue(child.recordSourceOutput(source, group: childGroup)) }
        let childProposal = try XCTUnwrap(child.closeGroup(childGroup))
        let siblingGroup = try XCTUnwrap(sibling.registerGroup(kind: .structure))
        XCTAssertTrue(sibling.recordSourceOutput(siblingSource, group: siblingGroup))
        let siblingProposal = try XCTUnwrap(sibling.closeGroup(siblingGroup))
        rejected.rejectConstruction()

        let preparation = try XCTUnwrap(fixture.journal.preparation())

        XCTAssertEqual(preparation.ownedComponentDeclarations.count, 4)
        XCTAssertFalse(preparation.ownedComponentDeclarations.contains { $0.receipt === rejectedReceipt })
        let rootPlan = try ownedFreezePlan(for: rootReceipt, in: preparation)
        let childPlan = try ownedFreezePlan(for: childReceipt, in: preparation)
        let siblingPlan = try ownedFreezePlan(for: siblingReceipt, in: preparation)
        let emptyPlan = try ownedFreezePlan(for: emptyReceipt, in: preparation)
        XCTAssertTrue(ownedFreezeOriginsMatch(rootPlan.origin, .descriptor(component: root.component)))
        XCTAssertEqual(
            rootPlan.sourcePayloads.map(ObjectIdentifier.init), childPlan.sourcePayloads.map(ObjectIdentifier.init))
        XCTAssertEqual(
            rootPlan.sourceFacets.map(ObjectIdentifier.init), childPlan.sourceFacets.map(ObjectIdentifier.init))
        XCTAssertEqual(childPlan.sourcePayloads.count, childSources.count)
        XCTAssertEqual(
            Set(childPlan.sourceFacets.map(ObjectIdentifier.init)),
            Set(childProposal.requiredFacets.map(ObjectIdentifier.init)))
        XCTAssertEqual(childPlan.sourceFacets.count, childProposal.requiredFacets.count)
        XCTAssertEqual(siblingPlan.sourcePayloads.count, 1)
        XCTAssertEqual(
            Set(siblingPlan.sourceFacets.map(ObjectIdentifier.init)),
            Set(siblingProposal.requiredFacets.map(ObjectIdentifier.init)))
        XCTAssertTrue(
            Set(rootPlan.sourcePayloads.map(ObjectIdentifier.init)).isDisjoint(
                with: siblingPlan.sourcePayloads.map(ObjectIdentifier.init)))
        XCTAssertEqual(rootPlan.introduced.map(ObjectIdentifier.init), [ObjectIdentifier(rootSlot)])
        XCTAssertEqual(childPlan.introduced.map(ObjectIdentifier.init), [ObjectIdentifier(childSlot)])
        XCTAssertTrue(rootPlan.retained.isEmpty)
        XCTAssertTrue(rootPlan.departed.isEmpty)
        XCTAssertTrue(emptyPlan.sourcePayloads.isEmpty)
        XCTAssertTrue(emptyPlan.sourceFacets.isEmpty)
        XCTAssertFalse(emptyReceipt.hasAcceptedDeclaration)
        XCTAssertTrue(try XCTUnwrap(fixture.journal.preparation()) === preparation)
        XCTAssertNil(empty.registerOwnedComponent(owner: RetainedOwnedComponentID(), slots: []))
    }

    func testLazyPreparationPreservesSourceIdentitiesAndSharesOnlyAncestorOwnedPlans() async throws {
        let fixture = try OwnedFreezeConstructionFixture()
        defer { fixture.finish() }
        let root = fixture.lazyRoot
        let child = try XCTUnwrap(root.registerChildComponent())
        let sibling = try XCTUnwrap(root.registerChildComponent())
        let empty = try XCTUnwrap(root.registerChildComponent())
        let rejected = try XCTUnwrap(root.registerChildComponent())
        let rootReceipt = try XCTUnwrap(
            root.registerOwnedComponent(owner: RetainedOwnedComponentID(), slots: [RetainedOwnedSlotGenerationID()]))
        let childSlot = RetainedOwnedSlotGenerationID()
        let childReceipt = try XCTUnwrap(
            child.registerOwnedComponent(owner: RetainedOwnedComponentID(), slots: [childSlot]))
        let siblingReceipt = try XCTUnwrap(
            sibling.registerOwnedComponent(owner: RetainedOwnedComponentID(), slots: [RetainedOwnedSlotGenerationID()]))
        let emptyReceipt = try XCTUnwrap(empty.registerOwnedComponent(owner: RetainedOwnedComponentID(), slots: []))
        let rejectedReceipt = try XCTUnwrap(
            rejected.registerOwnedComponent(owner: RetainedOwnedComponentID(), slots: []))
        let childSources = [ViewNode(), ViewNode()]
        let siblingSource = ViewNode()
        defer { withExtendedLifetime((childSources, siblingSource)) {} }
        let childGroup = try XCTUnwrap(child.registerGroup(kind: .structure))
        let payloads = try childSources.map { source in
            try XCTUnwrap(child.recordSourceOutput(source, group: childGroup))
        }
        let childProposal = try XCTUnwrap(child.closeGroup(childGroup))
        let siblingGroup = try XCTUnwrap(sibling.registerGroup(kind: .structure))
        let siblingPayload = try XCTUnwrap(sibling.recordSourceOutput(siblingSource, group: siblingGroup))
        let siblingProposal = try XCTUnwrap(sibling.closeGroup(siblingGroup))
        rejected.rejectConstruction()

        let preparation = try XCTUnwrap(fixture.journal.preparation())

        XCTAssertEqual(preparation.ownedComponentDeclarations.count, 4)
        XCTAssertFalse(preparation.ownedComponentDeclarations.contains { $0.receipt === rejectedReceipt })
        let rootPlan = try ownedFreezePlan(for: rootReceipt, in: preparation)
        let childPlan = try ownedFreezePlan(for: childReceipt, in: preparation)
        let siblingPlan = try ownedFreezePlan(for: siblingReceipt, in: preparation)
        let emptyPlan = try ownedFreezePlan(for: emptyReceipt, in: preparation)
        XCTAssertTrue(ownedFreezeOriginsMatch(childPlan.origin, .lazy(component: child.component)))
        XCTAssertEqual(childPlan.sourcePayloads.map(ObjectIdentifier.init), payloads.map(ObjectIdentifier.init))
        XCTAssertEqual(siblingPlan.sourcePayloads.map(ObjectIdentifier.init), [ObjectIdentifier(siblingPayload)])
        XCTAssertEqual(
            Set(rootPlan.sourcePayloads.map(ObjectIdentifier.init)),
            Set((payloads + [siblingPayload]).map(ObjectIdentifier.init)))
        XCTAssertEqual(rootPlan.sourcePayloads.count, payloads.count + 1)
        XCTAssertEqual(
            Set(childPlan.sourceFacets.map(ObjectIdentifier.init)),
            Set(childProposal.requiredFacets.map(ObjectIdentifier.init)))
        XCTAssertEqual(childPlan.sourceFacets.count, childProposal.requiredFacets.count)
        XCTAssertEqual(
            Set(rootPlan.sourceFacets.map(ObjectIdentifier.init)),
            Set((childProposal.requiredFacets + siblingProposal.requiredFacets).map(ObjectIdentifier.init)))
        XCTAssertEqual(childPlan.introduced.map(ObjectIdentifier.init), [ObjectIdentifier(childSlot)])
        XCTAssertTrue(childPlan.retained.isEmpty)
        XCTAssertTrue(childPlan.departed.isEmpty)
        XCTAssertTrue(emptyPlan.sourcePayloads.isEmpty)
        XCTAssertTrue(emptyPlan.sourceFacets.isEmpty)
        XCTAssertTrue(emptyPlan.receipt.belongs(to: fixture.membership))
        XCTAssertFalse(fixture.membership.isDeclared)
        XCTAssertFalse(childReceipt.hasAcceptedDeclaration)
        XCTAssertTrue(try XCTUnwrap(fixture.journal.preparation()) === preparation)
        XCTAssertNil(empty.registerOwnedComponent(owner: RetainedOwnedComponentID(), slots: []))
    }
}

@MainActor
private func ownedFreezeOriginsMatch(
    _ lhs: RetainedOwnedComponentDeclarationOrigin, _ rhs: RetainedOwnedComponentDeclarationOrigin
) -> Bool {
    switch (lhs, rhs) {
    case (.lazy(let left), .lazy(let right)): return left === right
    case (.descriptor(let left), .descriptor(let right)): return left === right
    case (.lazy, .descriptor), (.descriptor, .lazy): return false
    }
}

private struct OwnedFreezeReferenceWork {
    var componentComparisons = 0
    var payloadComparisons = 0
    var facetComparisons = 0
}

/// Keep the original filter plus identity-array membership as an independent
/// bounded oracle. Do not use the production index or a Set to compute it.
@discardableResult
@MainActor
private func assertOwnedFreezeRoster(
    _ actual: RetainedOwnedComponentSourceRoster,
    for origin: RetainedOwnedComponentDeclarationOrigin, in sources: [RetainedOwnedComponentSource],
    file: StaticString = #filePath, line: UInt = #line
) -> OwnedFreezeReferenceWork {
    var work = OwnedFreezeReferenceWork()
    let matching = sources.filter { source in
        source.components.contains {
            work.componentComparisons += 1
            return ownedFreezeOriginsMatch($0, origin)
        }
    }
    var payloads: [RetainedLazyListSourcePayloadID] = []
    var facets: [RetainedLazyListSourceFacetID] = []
    for source in matching {
        if !payloads.contains(where: {
            work.payloadComparisons += 1
            return $0 === source.payload
        }) {
            payloads.append(source.payload)
        }
        for facet in source.facets {
            if !facets.contains(where: {
                work.facetComparisons += 1
                return $0 === facet
            }) {
                facets.append(facet)
            }
        }
    }
    XCTAssertEqual(
        actual.payloads.map(ObjectIdentifier.init), payloads.map(ObjectIdentifier.init), file: file, line: line)
    XCTAssertEqual(actual.facets.map(ObjectIdentifier.init), facets.map(ObjectIdentifier.init), file: file, line: line)
    XCTAssertEqual(actual.sourceVisits, matching.count, file: file, line: line)
    XCTAssertEqual(actual.payloadMembershipChecks, matching.count, file: file, line: line)
    XCTAssertEqual(actual.facetMembershipChecks, matching.reduce(0) { $0 + $1.facets.count }, file: file, line: line)
    return work
}

@MainActor
private func ownedFreezePlan(
    for receipt: RetainedOwnedComponentReceipt, in preparation: RetainedLazyListAdoptionPreparation,
    file: StaticString = #filePath, line: UInt = #line
) throws -> RetainedOwnedComponentDeclarationPlan {
    let matches = preparation.ownedComponentDeclarations.filter { $0.receipt === receipt }
    XCTAssertEqual(matches.count, 1, file: file, line: line)
    return try XCTUnwrap(matches.first, file: file, line: line)
}

@MainActor
private final class OwnedFreezeWeakProbe {
    weak var node: ViewNode?
    weak var payload: RetainedLazyListSourcePayloadID?
    weak var facet: RetainedLazyListSourceFacetID?
    weak var component: RetainedLazyListComponentID?
}

@MainActor
@inline(never)
private func makeEphemeralOwnedFreezeIndex(probe: OwnedFreezeWeakProbe) -> RetainedOwnedComponentSourceIndex {
    let node = ViewNode()
    let payload = RetainedLazyListSourcePayloadID()
    let facet = RetainedLazyListSourceFacetID()
    let component = RetainedLazyListComponentID()
    probe.node = node
    probe.payload = payload
    probe.facet = facet
    probe.component = component
    return RetainedOwnedComponentSourceIndex(sources: [
        RetainedOwnedComponentSource(
            node: node, payload: payload, facets: [facet],
            components: [.lazy(component: component)], deferredRoot: component)
    ])
}

/// Proposed membership is sufficient for construction preparation. This
/// fixture deliberately does not publish a descriptor or adopt any nodes.
@MainActor
private final class OwnedFreezeConstructionFixture {
    let hostLifetime: RetainedLazyListLogicalHostLifetime
    let ownerLifetime: RetainedLazyListDescriptorOwnerLifetime
    let scope: RetainedLazyListDescriptorBuildScope
    let provider: RetainedLazyListDataSource<Int, [ViewNode]>
    let membership: RetainedLazyListLogicalMembershipReceipt
    let journal: RetainedLazyListAdoptionJournal
    let lazyRoot: RetainedLazyListBuildAttribution

    init() throws {
        let hostLifetime = RetainedLazyListLogicalHostLifetime()
        let ownerLifetime = RetainedLazyListDescriptorOwnerLifetime(
            target: RetainedLazyListTargetID(), attachment: RetainedLazyListAttachmentID())
        let scope = RetainedLazyListDescriptorBuildScope(
            origin: .componentHostRoot, hostLifetime: hostLifetime, ownerLifetime: ownerLifetime)
        let journal = RetainedLazyListAdoptionJournal(descriptorScope: scope, transaction: RetainedBuildTransaction())
        let logical = try XCTUnwrap(RetainedLazyListLogicalMembershipScope(in: scope, parentRow: nil))
        let membership = try XCTUnwrap(logical.proposeMembership(id: RetainedLazyListMembershipID()))
        let provider = RetainedLazyListDataSource<Int, [ViewNode]>()
        guard provider.replaceData([0], id: \.self, rowContent: { _ in [] }) else {
            throw OwnedFreezeFixtureError.provider
        }
        let token = try XCTUnwrap(provider.metadata?.rows.first?.token)
        let request = try XCTUnwrap(provider.request(for: token))
        self.hostLifetime = hostLifetime
        self.ownerLifetime = ownerLifetime
        self.scope = scope
        self.provider = provider
        self.membership = membership
        self.journal = journal
        lazyRoot = RetainedLazyListBuildAttribution(
            journal: journal, rowRequest: request, logicalMembership: membership,
            physical: RetainedLazyListPhysicalActivityReceipt(membership: membership.id),
            component: RetainedLazyListComponentID(), resolutionID: RetainedLazyListRowResolutionID(),
            origin: .selectedRow)
    }

    func finish() {
        provider.close()
        scope.finish()
    }
}

private enum OwnedFreezeFixtureError: Error { case provider }
