import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Native visit counts and admission guards, not elapsed-time or interaction
/// coverage. Every query returns before an assertion, mutation, or cleanup.
@MainActor
final class RetainedDescriptorOwnerAttachmentQueryTests: XCTestCase {
    func testBothOwnerAuthorizationEdgesShareOneAttachmentTraversal() async throws {
        let fixture = try DescriptorOwnerQueryFixture(depth: 12, leaves: 16, wrappers: 8)
        defer { fixture.registry.close() }

        let result = fixture.validate()

        XCTAssertTrue(result.isCurrent)
        XCTAssertEqual(result.authorizationChecks, 2, "Both original native checks must still execute")
        XCTAssertEqual(result.ancestorVisits, 12 + 1 + 16)
        XCTAssertEqual(result.childLinkVisits, 12 + 16)
        XCTAssertTrue(fixture.epoch.descriptorOwnerIsCurrent(fixture.owner, attribution: fixture.attribution))
    }

    func testIndependentOwnerInvocationsStartWithFreshVisitCounts() async throws {
        let fixture = try DescriptorOwnerQueryFixture(depth: 3, leaves: 4)
        defer { fixture.registry.close() }

        for _ in 0..<2 {
            let result = fixture.validate()
            XCTAssertTrue(result.isCurrent)
            XCTAssertEqual(result.authorizationChecks, 2)
            XCTAssertEqual(result.ancestorVisits, 3 + 1 + 4)
            XCTAssertEqual(result.childLinkVisits, 3 + 4)
        }

        fixture.scope.noteSupersedingRequest()
        let obsolete = fixture.validate()
        XCTAssertFalse(obsolete.isCurrent)
        XCTAssertEqual(obsolete.authorizationChecks, 1)
        XCTAssertEqual(obsolete.ancestorVisits, 0)
        XCTAssertEqual(obsolete.childLinkVisits, 0)
    }

    func testExactOwnerAttributionAndAttemptGuardsRemainIndependent() async throws {
        let fixture = try DescriptorOwnerQueryFixture(depth: 2, leaves: 3)
        defer { fixture.registry.close() }
        let otherAttribution = try XCTUnwrap(fixture.scope.registerOrdinaryComponent())
        let ordinaryOwner = try XCTUnwrap(fixture.epoch.owner(at: .init(segments: [.slot(1)])))

        let wrongAttribution = fixture.epoch.descriptorOwnerValidation(
            fixture.owner, attribution: otherAttribution)
        let wrongOwner = fixture.epoch.descriptorOwnerValidation(
            ordinaryOwner, attribution: fixture.attribution)
        XCTAssertFalse(wrongAttribution.isCurrent)
        XCTAssertFalse(wrongOwner.isCurrent)
        XCTAssertEqual(wrongAttribution.authorizationChecks, 1)
        XCTAssertEqual(wrongOwner.authorizationChecks, 1)

        let otherScope = descriptorOwnerQueryScope(in: fixture.runtime)
        let foreign = try XCTUnwrap(otherScope.registerOrdinaryComponent())
        XCTAssertTrue(foreign.canConstruct)
        let wrongAttempt = fixture.epoch.descriptorOwnerValidation(fixture.owner, attribution: foreign)
        XCTAssertFalse(wrongAttempt.isCurrent)
        XCTAssertEqual(wrongAttempt.authorizationChecks, 0)
        XCTAssertEqual(wrongAttempt.ancestorVisits, 0)
        XCTAssertEqual(wrongAttempt.childLinkVisits, 0)
        XCTAssertTrue(fixture.validate().isCurrent)
    }

    func testMoveDetachAndReturnDoNotReviveTheOriginalAttachment() async throws {
        let fixture = try DescriptorOwnerQueryFixture(depth: 2, leaves: 2)
        defer { fixture.registry.close() }
        XCTAssertTrue(fixture.validate().isCurrent)
        let node = try XCTUnwrap(fixture.leaves.first)
        let otherParent = ViewNode()
        fixture.runtime.root.addChild(otherParent)

        otherParent.addChild(node)
        let moved = fixture.validate()
        XCTAssertFalse(moved.isCurrent)
        XCTAssertEqual(moved.authorizationChecks, 1)

        node.removeFromParent()
        XCTAssertFalse(fixture.validate().isCurrent)
        fixture.branch.addChild(node)
        let returned = fixture.validate()
        XCTAssertFalse(returned.isCurrent)
        XCTAssertEqual(returned.authorizationChecks, 1)
    }

    func testFreshInvocationsRecheckViewIdentityAndAttachmentTokens() async throws {
        for replaceIdentity in [true, false] {
            let fixture = try DescriptorOwnerQueryFixture(depth: 2, leaves: 2)
            defer { fixture.registry.close() }
            XCTAssertTrue(fixture.validate().isCurrent)
            let node = try XCTUnwrap(fixture.leaves.first)

            if replaceIdentity {
                node.retainedViewIdentity = nil
            } else {
                node.lazyListActivityStorage().revokeAttachment()
            }

            let result = fixture.validate()
            XCTAssertFalse(result.isCurrent)
            XCTAssertEqual(result.authorizationChecks, 1)
        }
    }

    func testScopeAndContributionDenialStillPrecedeAttachmentTraversal() async throws {
        for change in DescriptorOwnerScopeChange.allCases {
            let fixture = try DescriptorOwnerQueryFixture()
            defer { fixture.registry.close() }
            XCTAssertTrue(fixture.validate().isCurrent)

            switch change {
            case .hostClose: fixture.runtime.lazyListLogicalHostLifetime.revoke()
            case .ownerClose: fixture.runtime.root.lazyListActivityStorage().descriptorOwnerLifetime.revoke()
            case .superseded: fixture.scope.noteSupersedingRequest()
            case .prepared: fixture.scope.preparationDidSucceed()
            case .revoked: fixture.scope.revoke()
            case .contributionRevoked: fixture.accepted.receipt.revoke()
            }

            let result = fixture.validate()
            XCTAssertFalse(result.isCurrent)
            XCTAssertEqual(result.authorizationChecks, 1)
            XCTAssertEqual(result.ancestorVisits, 0)
            XCTAssertEqual(result.childLinkVisits, 0)
        }
    }

    func testEpochDenialStillPrecedesBothNativeAuthorizationEdges() async throws {
        for change in DescriptorOwnerEpochChange.allCases {
            let fixture = try DescriptorOwnerQueryFixture()
            defer { fixture.registry.close() }
            XCTAssertTrue(fixture.validate().isCurrent)

            switch change {
            case .registryClose: fixture.registry.close()
            case .superseded: fixture.epoch.supersede()
            case .aborted: fixture.epoch.abort()
            }

            let result = fixture.validate()
            XCTAssertFalse(result.isCurrent)
            XCTAssertEqual(result.authorizationChecks, 0)
            XCTAssertEqual(result.ancestorVisits, 0)
            XCTAssertEqual(result.childLinkVisits, 0)
        }
    }

    func testUnavailableOwnerStopsBeforeReceiptWithoutLatchingItsRejection() async throws {
        let fixture = try DescriptorOwnerQueryFixture()
        defer { fixture.registry.close() }
        XCTAssertTrue(fixture.validate().isCurrent)

        fixture.owner.lazyLifetime.retire()
        let unavailable = fixture.validate()
        XCTAssertFalse(unavailable.isCurrent)
        XCTAssertEqual(unavailable.authorizationChecks, 1)

        fixture.owner.lazyLifetime.cancelRetirement()
        let restored = fixture.validate()
        XCTAssertTrue(restored.isCurrent)
        XCTAssertEqual(restored.authorizationChecks, 2)
    }

    func testReceiptNativeDenialRemainsLatchedAcrossFreshQueries() async throws {
        let fixture = try DescriptorOwnerQueryFixture()
        defer { fixture.registry.close() }
        let receipt = try XCTUnwrap(DescriptorResolutionReceipt(epoch: fixture.epoch, native: fixture.attribution))
        XCTAssertTrue(checkDescriptorOwnerReceipt(receipt).isCurrent)
        fixture.attribution.rejectConstruction()

        let first = checkDescriptorOwnerReceipt(receipt)
        let repeated = checkDescriptorOwnerReceipt(receipt)

        XCTAssertFalse(first.isCurrent)
        XCTAssertEqual(first.authorizationChecks, 1)
        XCTAssertFalse(repeated.isCurrent)
        XCTAssertEqual(repeated.authorizationChecks, 0, "The receipt's rejection guard must still short-circuit")
        XCTAssertEqual(repeated.ancestorVisits, 0)
        XCTAssertEqual(repeated.childLinkVisits, 0)
        XCTAssertNil(receipt.beginLookup())
    }

    func testCompletedOwnerQueryDoesNotKeepRuntimeOrNodesAlive() async throws {
        let released = try makeReleasedDescriptorOwnerQueryFixture()
        defer { released.registry.close() }
        XCTAssertTrue(released.prior.isCurrent)
        XCTAssertEqual(released.prior.authorizationChecks, 2)
        XCTAssertNil(released.runtime)
        XCTAssertNil(released.node)

        let result = released.epoch.descriptorOwnerValidation(released.owner, attribution: released.attribution)
        XCTAssertFalse(result.isCurrent)
        XCTAssertEqual(result.authorizationChecks, 1)
        XCTAssertEqual(result.ancestorVisits, 0)
        XCTAssertEqual(result.childLinkVisits, 0)
    }

    func testExpiredScopeAndLedgerAreRecheckedByTheNativeQueryEntry() async throws {
        let fixture = try DescriptorOwnerQueryFixture()
        defer { fixture.registry.close() }
        let attribution = try makeReleasedDescriptorQueryAttribution(in: fixture.runtime)

        let result = checkDescriptorOwnerAttribution(attribution)

        XCTAssertFalse(result.isCurrent)
        XCTAssertEqual(result.authorizationChecks, 1)
        XCTAssertEqual(result.ancestorVisits, 0)
        XCTAssertEqual(result.childLinkVisits, 0)
    }
}

private enum DescriptorOwnerScopeChange: CaseIterable {
    case hostClose, ownerClose, superseded, prepared, revoked, contributionRevoked
}

private enum DescriptorOwnerEpochChange: CaseIterable {
    case registryClose, superseded, aborted
}

@MainActor
private final class DescriptorOwnerQueryFixture {
    let runtime: RetainedViewRuntime
    let branch: ViewNode
    let leaves: [ViewNode]
    let registry: StateMountRegistry
    let epoch: StateMountEpoch
    let scope: RetainedLazyListDescriptorBuildScope
    let accepted: RetainedDescriptorAcceptedGroup
    let attribution: RetainedDescriptorComponentAttribution
    let owner: StateMountOwner

    init(depth: Int = 3, leaves count: Int = 4, wrappers: Int = 2) throws {
        let runtime = RetainedViewRuntime(root: ViewNode())
        var branch = runtime.root
        for _ in 0..<depth {
            let child = ViewNode()
            branch.addChild(child)
            branch = child
        }
        let leaves = (0..<count).map { _ in ViewNode() }
        for leaf in leaves { branch.addChild(leaf) }
        let accepted = try acceptDescriptorOwnerQueryGroup(on: leaves, in: runtime)
        let actual = try XCTUnwrap(accepted.acceptedFacets.first?.actual)
        var scope = descriptorOwnerQueryScope(in: runtime)
        for _ in 0..<wrappers {
            scope = try XCTUnwrap(
                scope.withAdmittedOrdinaryDeferredSubtree(
                    originalActivity: accepted.receipt, originalAttachment: actual))
        }
        let registry = StateMountRegistry()
        let epoch = try XCTUnwrap(registry.beginRootBuild())
        XCTAssertTrue(epoch.bindNativeDescriptorScope(scope))
        let attribution = try XCTUnwrap(scope.registerOrdinaryComponent())
        let owner = try XCTUnwrap(epoch.descriptorOwner(at: .init(), attribution: attribution))
        self.runtime = runtime
        self.branch = branch
        self.leaves = leaves
        self.registry = registry
        self.epoch = epoch
        self.scope = scope
        self.accepted = accepted
        self.attribution = attribution
        self.owner = owner
    }

    func validate() -> DescriptorOwnerConstructionValidation {
        epoch.descriptorOwnerValidation(owner, attribution: attribution)
    }
}

@MainActor
private func descriptorOwnerQueryScope(
    in runtime: RetainedViewRuntime, origin: RetainedLazyListDescriptorBuildOrigin = .managedSubtree
) -> RetainedLazyListDescriptorBuildScope {
    RetainedLazyListDescriptorBuildScope(
        origin: origin, hostLifetime: runtime.lazyListLogicalHostLifetime,
        ownerLifetime: runtime.root.lazyListActivityStorage().descriptorOwnerLifetime)
}

/// Uses the same real journal/adoption seam as RetainedDescriptorAttachmentQueryTests.
@MainActor
private func acceptDescriptorOwnerQueryGroup(
    on targets: [ViewNode], in runtime: RetainedViewRuntime
) throws -> RetainedDescriptorAcceptedGroup {
    let scope = descriptorOwnerQueryScope(in: runtime, origin: .componentHostRoot)
    let journal = RetainedLazyListAdoptionJournal(descriptorScope: scope, transaction: RetainedBuildTransaction())
    let attribution = try XCTUnwrap(scope.registerOrdinaryComponent())
    let group = try XCTUnwrap(attribution.registerGroup(kind: .deferredSubtree))
    let sources = targets.map { _ in ViewNode() }
    for source in sources { XCTAssertTrue(attribution.recordSourceOutput(source, group: group)) }
    _ = try XCTUnwrap(attribution.closeGroup(group))
    XCTAssertTrue(journal.beginOrdinaryAdoption())
    XCTAssertTrue(journal.markMutationStarted())
    for (source, target) in zip(sources, targets) {
        _ = journal.recordAcceptedAttachment(from: source, to: target)
        _ = journal.recordCompletedNode(from: source, to: target)
    }
    let disposition = journal.seal(completedCheckedAdoption: true)
    let accepted = try XCTUnwrap(disposition.acceptedOrdinaryGroups.first { $0.proposal.group === group })
    XCTAssertTrue(accepted.receipt.isActive)
    scope.finish()
    return accepted
}

/// Queries do not escape these callback-free checks; only scalar observations return.
@MainActor
private func checkDescriptorOwnerReceipt(_ receipt: DescriptorResolutionReceipt)
    -> DescriptorOwnerConstructionValidation
{
    var query = RetainedDescriptorAttachmentQuery()
    let isCurrent = receipt.isCurrent(using: &query)
    return DescriptorOwnerConstructionValidation(
        isCurrent: isCurrent, authorizationChecks: query.authorizationChecks,
        ancestorVisits: query.ancestorVisits, childLinkVisits: query.childLinkVisits)
}

@MainActor
private func checkDescriptorOwnerAttribution(
    _ attribution: RetainedDescriptorComponentAttribution
) -> DescriptorOwnerConstructionValidation {
    var query = RetainedDescriptorAttachmentQuery()
    let isCurrent = attribution.canConstruct(using: &query)
    return DescriptorOwnerConstructionValidation(
        isCurrent: isCurrent, authorizationChecks: query.authorizationChecks,
        ancestorVisits: query.ancestorVisits, childLinkVisits: query.childLinkVisits)
}

@MainActor
private final class ReleasedDescriptorOwnerQueryFixture {
    let registry: StateMountRegistry
    let epoch: StateMountEpoch
    let scope: RetainedLazyListDescriptorBuildScope
    let attribution: RetainedDescriptorComponentAttribution
    let owner: StateMountOwner
    let prior: DescriptorOwnerConstructionValidation
    weak var runtime: RetainedViewRuntime?
    weak var node: ViewNode?

    init(_ fixture: DescriptorOwnerQueryFixture, prior: DescriptorOwnerConstructionValidation) {
        registry = fixture.registry
        epoch = fixture.epoch
        scope = fixture.scope
        attribution = fixture.attribution
        owner = fixture.owner
        self.prior = prior
        runtime = fixture.runtime
        node = fixture.leaves.first
    }
}

@MainActor
private func makeReleasedDescriptorOwnerQueryFixture() throws -> ReleasedDescriptorOwnerQueryFixture {
    let fixture = try DescriptorOwnerQueryFixture()
    return ReleasedDescriptorOwnerQueryFixture(fixture, prior: fixture.validate())
}

@MainActor
private func makeReleasedDescriptorQueryAttribution(
    in runtime: RetainedViewRuntime
) throws -> RetainedDescriptorComponentAttribution {
    let scope = descriptorOwnerQueryScope(in: runtime)
    let attribution = try XCTUnwrap(scope.registerOrdinaryComponent())
    XCTAssertTrue(checkDescriptorOwnerAttribution(attribution).isCurrent)
    return attribution
}
