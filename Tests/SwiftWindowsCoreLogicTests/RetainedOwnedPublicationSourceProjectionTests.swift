import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI

@MainActor
final class RetainedOwnedPublicationSourceProjectionTests: XCTestCase {
    func testCompletionSelectsFirstMatchingPayloadInRegisteredOrder() async throws {
        let fixture = try OwnedProjectionFixture()
        defer { fixture.close() }
        let unrelated = ViewNode()
        let source = ViewNode()
        defer { withExtendedLifetime((unrelated, source)) {} }
        try fixture.record([unrelated, source])
        try fixture.record([source])
        let plan = try fixture.begin()
        XCTAssertEqual(plan.sourcePayloads.count, 3)
        let unrelatedPayload = try XCTUnwrap(plan.sourcePayloads.first)
        let firstMatchingPayload = try XCTUnwrap(plan.sourcePayloads.dropFirst().first)
        let laterMatchingPayload = try XCTUnwrap(plan.sourcePayloads.dropFirst(2).first)
        XCTAssertFalse(firstMatchingPayload === laterMatchingPayload)

        fixture.journal.recordCompletedNode(from: source, to: fixture.target)

        let facts = fixture.finish().acceptedOwnedComponents
        XCTAssertEqual(facts.count, 1)
        let fact = try XCTUnwrap(facts.first)
        assertProjectionFact(fact, plan: plan, target: fixture.target)
        XCTAssertTrue(fact.sourcePayload === firstMatchingPayload)
        XCTAssertFalse(fact.sourcePayload === unrelatedPayload)
        XCTAssertFalse(fact.sourcePayload === laterMatchingPayload)
    }

    func testRepeatedSourceRegistrationInOneGroupDoesNotDuplicatePublication() async throws {
        let fixture = try OwnedProjectionFixture()
        defer { fixture.close() }
        let source = ViewNode()
        defer { withExtendedLifetime(source) {} }
        try fixture.record([source, source])
        let plan = try fixture.begin()
        XCTAssertEqual(plan.sourcePayloads.count, 1)
        let payload = try XCTUnwrap(plan.sourcePayloads.first)

        fixture.journal.recordCompletedNode(from: source, to: fixture.target)

        let facts = fixture.finish().acceptedOwnedComponents
        XCTAssertEqual(facts.count, 1)
        let fact = try XCTUnwrap(facts.first)
        assertProjectionFact(fact, plan: plan, target: fixture.target)
        XCTAssertTrue(fact.sourcePayload === payload)
    }

    func testCompletionSkipsExpiredWeakSourceRecord() async throws {
        let fixture = try OwnedProjectionFixture()
        defer { fixture.close() }
        var expiredSource: ViewNode? = ViewNode()
        weak var original = expiredSource
        let source = ViewNode()
        defer { withExtendedLifetime(source) {} }
        try fixture.record([try XCTUnwrap(expiredSource), source])
        let plan = try fixture.begin()
        XCTAssertEqual(plan.sourcePayloads.count, 2)
        let expiredPayload = try XCTUnwrap(plan.sourcePayloads.first)
        let livePayload = try XCTUnwrap(plan.sourcePayloads.dropFirst().first)
        expiredSource = nil
        XCTAssertNil(original)

        fixture.journal.recordCompletedNode(from: source, to: fixture.target)

        let facts = fixture.finish().acceptedOwnedComponents
        XCTAssertEqual(facts.count, 1)
        let fact = try XCTUnwrap(facts.first)
        assertProjectionFact(fact, plan: plan, target: fixture.target)
        XCTAssertTrue(fact.sourcePayload === livePayload)
        XCTAssertFalse(fact.sourcePayload === expiredPayload)
    }

    func testNilSourceDescriptorPublicationDoesNotSelectLiveOrExpiredRecord() async throws {
        let fixture = try OwnedProjectionFixture()
        defer { fixture.close() }
        var expiredSource: ViewNode? = ViewNode()
        weak var original = expiredSource
        let liveSource = ViewNode()
        defer { withExtendedLifetime(liveSource) {} }
        try fixture.record([try XCTUnwrap(expiredSource), liveSource])
        let plan = try fixture.begin()
        XCTAssertEqual(plan.sourcePayloads.count, 2)
        expiredSource = nil
        XCTAssertNil(original)
        let actual = fixture.target.lazyListActivityStorage().captureActualAttachment(
            of: fixture.target, in: fixture.runtime)
        XCTAssertTrue(actual.isAttached)

        XCTAssertTrue(fixture.journal.recordCompletedOwnedDescriptorScope(structuralAnchor: actual))

        let facts = fixture.finish().acceptedOwnedComponents
        XCTAssertEqual(facts.count, 1)
        let fact = try XCTUnwrap(facts.first)
        assertProjectionFact(fact, plan: plan, target: fixture.target, descriptorScope: true)
        XCTAssertNil(fact.sourcePayload)
    }

    func testNonmatchingSourceDoesNotPublishRegisteredComponent() async throws {
        let fixture = try OwnedProjectionFixture()
        defer { fixture.close() }
        let registeredSource = ViewNode()
        let unrelatedSource = ViewNode()
        defer { withExtendedLifetime((registeredSource, unrelatedSource)) {} }
        try fixture.record([registeredSource])
        let plan = try fixture.begin()
        XCTAssertEqual(plan.sourcePayloads.count, 1)

        fixture.journal.recordCompletedNode(from: unrelatedSource, to: fixture.target)

        XCTAssertFalse(fixture.owned.hasAcceptedDeclaration)
        XCTAssertTrue(fixture.finish().acceptedOwnedComponents.isEmpty)
        XCTAssertFalse(fixture.owned.hasAcceptedDeclaration)
    }

    func testLaterCompletionReadsWeakSourcesAgainWithoutRetainingFirstSource() async throws {
        let fixture = try OwnedProjectionFixture()
        defer { fixture.close() }
        let releases = OwnedProjectionSourceReleases()
        var firstSource: ViewNode? = projectionSourceWithPayload(releases)
        weak var original = firstSource
        let secondSource = ViewNode()
        defer { withExtendedLifetime(secondSource) {} }
        let secondTarget = ViewNode()
        fixture.runtime.root.addChild(secondTarget)
        try fixture.record([try XCTUnwrap(firstSource), secondSource])
        let plan = try fixture.begin()
        XCTAssertEqual(plan.sourcePayloads.count, 2)
        let firstPayload = try XCTUnwrap(plan.sourcePayloads.first)
        let secondPayload = try XCTUnwrap(plan.sourcePayloads.dropFirst().first)

        fixture.journal.recordCompletedNode(from: try XCTUnwrap(firstSource), to: fixture.target)
        XCTAssertTrue(fixture.owned.hasAcceptedDeclaration)
        XCTAssertNotNil(original)
        XCTAssertEqual(releases.count, 0)
        firstSource = nil
        XCTAssertNil(original)
        XCTAssertEqual(releases.count, 1)
        fixture.journal.recordCompletedNode(from: secondSource, to: secondTarget)

        let facts = fixture.finish().acceptedOwnedComponents
        XCTAssertEqual(facts.count, 2)
        let first = try XCTUnwrap(facts.first)
        let second = try XCTUnwrap(facts.dropFirst().first)
        assertProjectionFact(first, plan: plan, target: fixture.target)
        assertProjectionFact(second, plan: plan, target: secondTarget)
        XCTAssertTrue(first.sourcePayload === firstPayload)
        XCTAssertTrue(second.sourcePayload === secondPayload)
        XCTAssertFalse(second.sourcePayload === firstPayload)
        XCTAssertNil(original)
        XCTAssertEqual(releases.count, 1)
    }

    func testEmptySourceRosterPublishesOnlyDescriptorScopeFact() async throws {
        let fixture = try OwnedProjectionFixture()
        defer { fixture.close() }
        let plan = try fixture.begin()
        XCTAssertTrue(plan.sourcePayloads.isEmpty)
        let unrelatedSource = ViewNode()

        fixture.journal.recordCompletedNode(from: unrelatedSource, to: fixture.target)
        XCTAssertFalse(fixture.owned.hasAcceptedDeclaration)
        let actual = fixture.target.lazyListActivityStorage().captureActualAttachment(
            of: fixture.target, in: fixture.runtime)
        XCTAssertTrue(actual.isAttached)
        XCTAssertTrue(fixture.journal.recordCompletedOwnedDescriptorScope(structuralAnchor: actual))

        let facts = fixture.finish().acceptedOwnedComponents
        XCTAssertEqual(facts.count, 1)
        let fact = try XCTUnwrap(facts.first)
        assertProjectionFact(fact, plan: plan, target: fixture.target, descriptorScope: true)
        XCTAssertNil(fact.sourcePayload)
    }
}

@MainActor
private func assertProjectionFact(
    _ fact: RetainedOwnedComponentDeclarationFact,
    plan: RetainedOwnedComponentDeclarationPlan, target: ViewNode, descriptorScope: Bool = false,
    file: StaticString = #filePath, line: UInt = #line
) {
    XCTAssertTrue(fact.plan === plan, file: file, line: line)
    XCTAssertTrue(fact.actual.node === target, file: file, line: line)
    XCTAssertTrue(fact.actual.isAttached, file: file, line: line)
    XCTAssertTrue(plan.receipt.hasAcceptedDeclaration, file: file, line: line)
    XCTAssertNil(fact.sourceFacet, file: file, line: line)
    switch (fact.kind, descriptorScope) {
    case (.structuralEntry, false), (.descriptorDeclarationTable, true): break
    default: XCTFail("Unexpected owned publication kind", file: file, line: line)
    }
}

/// Keeps construction metadata and attached targets alive, never source nodes.
@MainActor
private final class OwnedProjectionFixture {
    let runtime: RetainedViewRuntime
    let target: ViewNode
    let scope: RetainedLazyListDescriptorBuildScope
    let journal: RetainedLazyListAdoptionJournal
    let component: RetainedDescriptorComponentAttribution
    let owned: RetainedOwnedComponentReceipt
    private var disposition: RetainedLazyListAdoptionDisposition?

    init() throws {
        let target = ViewNode()
        let runtime = RetainedViewRuntime(root: ViewNode(children: [target]))
        let scope = RetainedLazyListDescriptorBuildScope(
            origin: .componentHostRoot, hostLifetime: runtime.lazyListLogicalHostLifetime,
            ownerLifetime: runtime.root.lazyListActivityStorage().descriptorOwnerLifetime)
        let journal = RetainedLazyListAdoptionJournal(descriptorScope: scope, transaction: RetainedBuildTransaction())
        let component = try XCTUnwrap(scope.registerOrdinaryComponent())
        let owned = try XCTUnwrap(
            component.registerOwnedComponent(
                owner: RetainedOwnedComponentID(), slots: [RetainedOwnedSlotGenerationID()],
                continuing: nil, declarationOnly: false))
        self.runtime = runtime
        self.target = target
        self.scope = scope
        self.journal = journal
        self.component = component
        self.owned = owned
    }

    func record(_ sources: [ViewNode]) throws {
        let group = try XCTUnwrap(component.registerGroup(kind: .observation))
        for source in sources { XCTAssertTrue(component.recordSourceOutput(source, group: group)) }
        _ = try XCTUnwrap(component.closeGroup(group))
    }

    func begin() throws -> RetainedOwnedComponentDeclarationPlan {
        let preparation = try XCTUnwrap(journal.preparation())
        XCTAssertEqual(preparation.ownedComponentDeclarations.count, 1)
        let plan = try XCTUnwrap(preparation.ownedComponentDeclarations.first { $0.receipt === owned })
        XCTAssertTrue(journal.beginOrdinaryAdoption())
        XCTAssertTrue(journal.markMutationStarted())
        XCTAssertTrue(journal.canContinueAdoption)
        return plan
    }

    @discardableResult
    func finish() -> RetainedLazyListAdoptionDisposition {
        if let disposition { return disposition }
        let result = journal.seal(completedCheckedAdoption: true)
        journal.releaseUnadoptedTransport()
        scope.finish()
        disposition = result
        return result
    }

    func close() {
        finish()
        runtime.stopRenderLifecycleCallbacks()
        runtime.cancelRenderLifecycleTasks()
    }
}

@MainActor
private final class OwnedProjectionSourceReleases {
    var count = 0
}

@MainActor
private final class OwnedProjectionSourcePayload {
    let releases: OwnedProjectionSourceReleases

    init(_ releases: OwnedProjectionSourceReleases) { self.releases = releases }
    isolated deinit { releases.count += 1 }
}

@MainActor
@inline(never)
private func projectionSourceWithPayload(_ releases: OwnedProjectionSourceReleases) -> ViewNode {
    let payload = OwnedProjectionSourcePayload(releases)
    let node = ViewNode()
    node.onAppear = { withExtendedLifetime(payload) {} }
    return node
}
