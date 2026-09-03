import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI

/// Real native preparation/publication must retain the original reader identity
/// and exactly one deferred group. No test creates a private namespace proof.
@MainActor
final class RetainedOwnedCandidateReaderProofTests: XCTestCase {
    func testFreshReaderIdentityProofSurvivesCleanInsertionButRejectsIdentityABA() async throws {
        for changesIdentity in [false, true] {
            let fixture = try ReaderIdentityProofFixture()
            let body = try fixture.body()
            let reader = try body.reader(under: try XCTUnwrap(body.context), identity: 20)
            body.begin(sources: [reader.node])
            XCTAssertTrue(body.journal.applyOwnedCandidateDeferredCatalog(at: fixture.reader.node))
            let identity = try XCTUnwrap(reader.node.retainedViewIdentity)
            let identityProof = reader.node.captureLazyListIdentityProof()
            XCTAssertTrue(identityProof.isCurrent)
            body.prepareTree(reader.node)

            if changesIdentity {
                reader.node.retainedViewIdentity = RetainedViewIdentity().appending(.slot(200))
                reader.node.retainedViewIdentity = identity
                XCTAssertEqual(reader.node.retainedViewIdentity, identity)
                XCTAssertFalse(identityProof.isCurrent)
            } else {
                XCTAssertTrue(identityProof.isCurrent)
            }
            XCTAssertFalse(reader.node.containsRejectedRetainedSource)
            fixture.reader.node.addChild(reader.node)
            body.acceptPreparedTree(reader.node)

            // Both paths publish through the real ordinary normal/group cuts.
            // Only namespace association is refused after the original ABA.
            let original = try ReaderIdentityProofOriginalContinuation(reader.node, in: fixture.runtime)
            XCTAssertTrue(original.actual.isAttached)
            XCTAssertTrue(original.contribution.isActive)
            XCTAssertTrue(reader.component.receipt.hasAcceptedDeclaration)
            XCTAssertTrue(reader.component.receipt.hasDeclaredComponent)
            XCTAssertTrue(reader.component.receipt.slots.isEmpty)
            XCTAssertTrue(reader.node.parent === fixture.reader.node)
            XCTAssertEqual(identityProof.isCurrent, !changesIdentity)
            if changesIdentity {
                XCTAssertFalse(original.invokeIfAdmitted())
            } else {
                XCTAssertTrue(original.invokeIfAdmitted())
            }
            _ = body.finish()
            if changesIdentity {
                XCTAssertFalse(original.invokeIfAdmitted())
            } else {
                XCTAssertTrue(original.invokeIfAdmitted())
            }
            fixture.assertCurrent()
        }
    }

    func testTwoDeferredGroupsForTheSameReaderSourceRefuseNamespacePreparation() async throws {
        let fixture = try ReaderIdentityProofFixture()
        let body = try fixture.body()
        let reader = try body.reader(under: try XCTUnwrap(body.context), identity: 20)
        let duplicate = try XCTUnwrap(reader.component.attribution.registerGroup(kind: .deferredSubtree))
        XCTAssertFalse(duplicate === reader.component.group)
        XCTAssertTrue(reader.component.attribution.recordSourceOutput(reader.node, group: duplicate))
        _ = try XCTUnwrap(reader.component.attribution.closeGroup(duplicate))

        // These are two genuine closed groups from the same native component
        // for the same source. Neither is a unique frozen expected reader group.
        let registered = body.journal.registerSourceDescriptors(in: [reader.node])
        let began = registered && body.journal.beginOrdinaryAdoption()
        XCTAssertFalse(registered && began)
        XCTAssertFalse(reader.component.receipt.hasAcceptedDeclaration)
        XCTAssertFalse(reader.component.receipt.hasDeclaredComponent)
        XCTAssertFalse(reader.component.attribution.contribution(for: reader.component.group)?.isActive == true)
        XCTAssertFalse(reader.component.attribution.contribution(for: duplicate)?.isActive == true)
        XCTAssertNil(reader.node.parent)
        XCTAssertNil(reader.node.retainedLazyListActivityStorage?.descriptorDeferredSubtreeAnchor)
        XCTAssertTrue(fixture.reader.node.children.isEmpty)
        fixture.assertCurrent()
        _ = body.finish(completed: false)
    }
}

@MainActor
private func readerIdentityProofNode(_ identity: Int) -> ViewNode {
    let node = ViewNode()
    node.retainedViewIdentity = RetainedViewIdentity().appending(.slot(identity))
    return node
}

@MainActor
private struct ReaderIdentityProofComponent {
    let attribution: RetainedDescriptorComponentAttribution
    let receipt: RetainedOwnedComponentReceipt
    let group: RetainedDescriptorGroupID
}

@MainActor
private struct ReaderIdentityProofContext {
    let attribution: RetainedDescriptorComponentAttribution
    let token: RetainedOwnedCandidateConstruction
}

@MainActor
private struct ReaderIdentityProofReader {
    let node: ViewNode
    let component: ReaderIdentityProofComponent
    let context: ReaderIdentityProofContext
}

@MainActor
private final class ReaderIdentityProofOriginalContinuation {
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

    func lease() -> ReaderIdentityProofLease? {
        guard let scope = admittedScope(), let attribution = scope.registerOrdinaryComponent() else { return nil }
        return ReaderIdentityProofLease(scope: scope, attribution: attribution)
    }

    func invokeIfAdmitted(_ body: @MainActor () -> Void = {}) -> Bool {
        guard let lease = lease() else { return false }
        defer { lease.finish() }
        return lease.invokeIfAdmitted(body)
    }
}

@MainActor
private final class ReaderIdentityProofLease {
    let scope: RetainedLazyListDescriptorBuildScope
    let attribution: RetainedDescriptorComponentAttribution

    init(scope: RetainedLazyListDescriptorBuildScope, attribution: RetainedDescriptorComponentAttribution) {
        self.scope = scope
        self.attribution = attribution
    }

    func invokeIfAdmitted(_ body: @MainActor () -> Void = {}) -> Bool {
        guard case .admitted(let token) = attribution.ownedCandidateContinuation(), token.canConstruct else {
            return false
        }
        body()
        return true
    }

    func finish() { scope.finish() }
}

@MainActor
private final class ReaderIdentityProofEpoch {
    let runtime: RetainedViewRuntime
    let scope: RetainedLazyListDescriptorBuildScope
    let journal: RetainedLazyListAdoptionJournal
    let context: ReaderIdentityProofContext?

    init(_ runtime: RetainedViewRuntime) {
        self.runtime = runtime
        scope = RetainedLazyListDescriptorBuildScope(
            origin: .componentHostRoot, hostLifetime: runtime.lazyListLogicalHostLifetime,
            ownerLifetime: runtime.root.lazyListActivityStorage().descriptorOwnerLifetime)
        journal = RetainedLazyListAdoptionJournal(descriptorScope: scope, transaction: RetainedBuildTransaction())
        context = nil
        XCTAssertTrue(journal.seedOwnedCandidateOrigins(at: runtime.root))
        journal.seedExistingContributions(from: runtime.root.children)
    }

    init(_ original: ReaderIdentityProofOriginalContinuation) throws {
        let scope = try XCTUnwrap(original.admittedScope())
        let journal = RetainedLazyListAdoptionJournal(descriptorScope: scope, transaction: RetainedBuildTransaction())
        journal.seedExistingContributions(from: original.node.children)
        let attribution = try XCTUnwrap(scope.registerOrdinaryComponent())
        let token: RetainedOwnedCandidateConstruction?
        switch attribution.ownedCandidateContinuation() {
        case .admitted(let accepted):
            token = accepted
        case .unscoped, .rejected:
            token = nil
        }
        let context = ReaderIdentityProofContext(
            attribution: attribution, token: try XCTUnwrap(token, "Expected the original accepted reader continuation"))
        runtime = original.runtime
        self.scope = scope
        self.journal = journal
        self.context = context
    }

    func openComponent(
        under parent: ReaderIdentityProofContext? = nil, kind: RetainedLazyListContributionKind = .observation,
        continuing: RetainedOwnedComponentReceipt? = nil
    ) throws -> ReaderIdentityProofComponent {
        let attribution: RetainedDescriptorComponentAttribution
        if let parent {
            attribution = try XCTUnwrap(parent.attribution.registerChildComponent())
        } else {
            attribution = try XCTUnwrap(scope.registerOrdinaryComponent())
        }
        let receipt = try XCTUnwrap(
            attribution.registerOwnedComponent(
                owner: continuing?.owner ?? RetainedOwnedComponentID(), slots: continuing?.slots ?? [],
                continuing: continuing, candidateConstruction: parent?.token))
        let group = try XCTUnwrap(attribution.registerGroup(kind: kind))
        return ReaderIdentityProofComponent(attribution: attribution, receipt: receipt, group: group)
    }

    func close(_ component: ReaderIdentityProofComponent, node: ViewNode) throws {
        XCTAssertTrue(component.attribution.recordSourceOutput(node, group: component.group))
        _ = try XCTUnwrap(component.attribution.closeGroup(component.group))
    }

    func reader(
        under parent: ReaderIdentityProofContext, identity: Int, continuing: RetainedOwnedComponentReceipt? = nil
    ) throws -> ReaderIdentityProofReader {
        let component = try openComponent(under: parent, kind: .deferredSubtree, continuing: continuing)
        let token = try XCTUnwrap(
            parent.token.deferredSegment(owner: component.receipt, attribution: component.attribution))
        let node = readerIdentityProofNode(identity)
        node.geometryReaderBuild = { _, _ in [] }
        XCTAssertTrue(token.stageDeferredAnchor(on: node))
        try close(component, node: node)
        return ReaderIdentityProofReader(
            node: node, component: component,
            context: ReaderIdentityProofContext(attribution: component.attribution, token: token))
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

    func installTree(_ node: ViewNode, under parent: ViewNode) {
        prepareTree(node)
        parent.addChild(node)
        XCTAssertTrue(node.parent === parent)
        acceptPreparedTree(node)
    }

    func acceptPreparedTree(_ node: ViewNode) {
        XCTAssertTrue(node.isRetainedLazyListAttached(in: runtime))
        _ = journal.recordAcceptedInsertedNode(on: node)
        for child in node.children { acceptPreparedTree(child) }
        _ = journal.recordCompletedNode(from: node, to: node)
    }

    func acceptPreparedNode(_ node: ViewNode) {
        XCTAssertTrue(node.isRetainedLazyListAttached(in: runtime))
        _ = journal.recordAcceptedInsertedNode(on: node)
        _ = journal.recordCompletedNode(from: node, to: node)
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
private final class ReaderIdentityProofBoundary {
    let epoch: ReaderIdentityProofEpoch
    let component: ReaderIdentityProofComponent
    let context: ReaderIdentityProofContext

    init(epoch: ReaderIdentityProofEpoch, under parent: ReaderIdentityProofContext? = nil) throws {
        let component = try epoch.openComponent(under: parent)
        let token = try XCTUnwrap(component.attribution.beginOwnedCandidateConstruction(owner: component.receipt))
        self.epoch = epoch
        self.component = component
        context = ReaderIdentityProofContext(attribution: component.attribution, token: token)
    }

    func close(child: ViewNode, identity: Int) throws -> ViewNode {
        let node = ViewNode.selectedContentBoundary(role: .viewThatFits, child: child)
        node.retainedViewIdentity = RetainedViewIdentity().appending(.slot(identity))
        XCTAssertTrue(context.token.stageBoundary(on: node))
        try epoch.close(component, node: node)
        return node
    }
}

@MainActor
private final class ReaderIdentityProofFixture {
    let runtime: RetainedViewRuntime
    let boundary: ViewNode
    let owner: ReaderIdentityProofComponent
    let reader: ReaderIdentityProofReader
    let original: ReaderIdentityProofOriginalContinuation

    init() throws {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let epoch = ReaderIdentityProofEpoch(runtime)
        let construction = try ReaderIdentityProofBoundary(epoch: epoch)
        let reader = try epoch.reader(under: construction.context, identity: 10)
        let boundary = try construction.close(child: reader.node, identity: 1000)
        epoch.begin(sources: [boundary])
        epoch.installTree(boundary, under: runtime.root)
        _ = epoch.finish()
        self.runtime = runtime
        owner = construction.component
        self.reader = reader
        self.boundary = boundary
        original = try ReaderIdentityProofOriginalContinuation(reader.node, in: runtime)
        XCTAssertTrue(owner.receipt.hasAcceptedDeclaration)
        XCTAssertTrue(reader.component.receipt.hasAcceptedDeclaration)
        assertCurrent()
    }

    func body() throws -> ReaderIdentityProofEpoch { try ReaderIdentityProofEpoch(original) }

    func assertCurrent(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(owner.receipt.hasDeclaredComponent, file: file, line: line)
        XCTAssertTrue(reader.component.receipt.hasDeclaredComponent, file: file, line: line)
        XCTAssertTrue(boundary.isRetainedLazyListAttached(in: runtime), file: file, line: line)
        XCTAssertTrue(reader.node.parent === boundary, file: file, line: line)
        XCTAssertTrue(original.invokeIfAdmitted(), file: file, line: line)
    }
}
