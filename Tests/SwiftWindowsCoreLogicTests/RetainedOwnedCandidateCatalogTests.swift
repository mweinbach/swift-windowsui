import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI

/// Catalog-only regressions use existing native admission, publication and
/// navigation cancellation. No private reference or revision is installed here.
@MainActor
final class RetainedOwnedCandidateCatalogTests: XCTestCase {
    func testMatchedReaderCatalogRetiresColdMemberBeforeNavigationCancellation() async throws {
        let graph = try CatalogProofGraph()
        let cold = try graph.makeColdLeaf(in: graph.readerC, identity: 31)
        let originalC = try CatalogProofOriginalContinuation(graph.readerC.node, in: graph.fixture.runtime)
        let pendingC = try XCTUnwrap(originalC.lease())
        defer { pendingC.finish() }
        XCTAssertTrue(pendingC.invokeIfAdmitted())
        let navigation = try graph.prepareNavigation()
        defer { navigation.cancelPreparedNavigation() }
        let replacement = try graph.fixture.body()
        let incoming = try graph.incoming(in: replacement)
        replacement.begin(sources: [incoming.b.node, incoming.sibling.node])
        var cancellations = 0
        var deliveries = 0
        var dismantles = 0
        graph.readerC.node.onDismantlePlatformView = { _ in dismantles += 1 }
        defer { graph.readerC.node.onDismantlePlatformView = nil }
        XCTAssertTrue(
            navigation.schedulePreparedNavigationReplay(
                afterLayout: true, perform: { deliveries += 1 },
                onCancel: {
                    cancellations += 1
                    XCTAssertEqual(dismantles, 0)
                    XCTAssertTrue(graph.readerC.node.parent === graph.readerB.node)
                    XCTAssertTrue(originalC.actual.isAttached)
                    XCTAssertTrue(originalC.contribution.isActive)
                    // A physically installed reader still owns its normal
                    // declaration. Its cold member has only catalog support.
                    XCTAssertTrue(graph.readerC.component.receipt.hasDeclaredComponent)
                    XCTAssertFalse(cold.component.receipt.hasDeclaredComponent)
                    XCTAssertFalse(pendingC.invokeIfAdmitted())
                    XCTAssertFalse(originalC.invokeIfAdmitted())
                    XCTAssertTrue(graph.readerB.component.receipt.hasDeclaredComponent)
                    XCTAssertFalse(navigation.permitsContinuation)
                }))

        // No outer retained callback scope defers this cancellation. The
        // matched B prepass removes navigation before any property/child copy.
        let result = ComponentHost.reconcileChildren(
            of: graph.fixture.reader.node, oldChildren: graph.fixture.reader.node.children,
            newNodes: [incoming.b.node, incoming.sibling.node], lazyJournal: replacement.journal)

        XCTAssertTrue(result.completed)
        XCTAssertEqual(cancellations, 1)
        XCTAssertEqual(deliveries, 0)
        XCTAssertEqual(dismantles, 1)
        XCTAssertNil(graph.readerC.node.parent)
        XCTAssertFalse(cold.component.receipt.hasDeclaredComponent)
        XCTAssertFalse(graph.readerC.component.receipt.hasDeclaredComponent)
        let acceptedB = try CatalogProofOriginalContinuation(graph.readerB.node, in: graph.fixture.runtime)
        XCTAssertTrue(acceptedB.invokeIfAdmitted())
        _ = replacement.finish()
        graph.fixture.assertCurrent()
    }

    func testCapturedGraphRejectsForeignSegmentGrowthAndExistingColdTargets() async throws {
        for foreign in [CatalogProofForeignWriter.readerC, .readerB] {
            let graph = try CatalogProofGraph()
            XCTAssertTrue(graph.readerC.node.children.isEmpty)
            let originalB = try CatalogProofOriginalContinuation(graph.readerB.node, in: graph.fixture.runtime)
            let originalC = try CatalogProofOriginalContinuation(graph.readerC.node, in: graph.fixture.runtime)
            let originalSibling = try CatalogProofOriginalContinuation(graph.sibling.node, in: graph.fixture.runtime)
            let savedB = try XCTUnwrap(originalB.lease())
            let savedSibling = try XCTUnwrap(originalSibling.lease())
            defer {
                savedB.finish()
                savedSibling.finish()
            }

            // This A operation freezes its original B/C graph before another
            // independently admitted reader can publish any new member.
            let older = try graph.fixture.body()
            let incoming = try graph.incoming(in: older)
            older.begin(sources: [incoming.b.node, incoming.sibling.node])
            XCTAssertTrue(older.journal.applyOwnedCandidateDeferredCatalog(at: graph.fixture.reader.node))
            XCTAssertTrue(savedB.invokeIfAdmitted())
            XCTAssertTrue(savedSibling.invokeIfAdmitted())

            let changedReader = foreign == .readerC ? graph.readerC : graph.readerB
            let newer = try graph.makeColdLeaf(in: changedReader, identity: 51)
            XCTAssertTrue(newer.component.receipt.hasAcceptedDeclaration)
            XCTAssertTrue(newer.component.receipt.hasDeclaredComponent)
            XCTAssertNil(newer.node.parent)
            XCTAssertTrue(originalB.actual.isAttached)
            XCTAssertTrue(originalC.actual.isAttached)
            XCTAssertTrue(originalC.contribution.isActive)
            if foreign == .readerC {
                // Real C growth leaves B's original segment proof useful.
                // A check of B's revision alone cannot detect this conflict.
                XCTAssertTrue(savedB.invokeIfAdmitted())
            } else {
                XCTAssertFalse(savedB.invokeIfAdmitted())
            }
            XCTAssertTrue(savedSibling.invokeIfAdmitted())

            XCTAssertFalse(older.journal.applyOwnedCandidateCatalog(from: incoming.b.node, to: graph.readerB.node))
            let refused = ComponentHost.adopt(
                source: incoming.b.node, into: graph.readerB.node, lazyJournal: older.journal)
            XCTAssertFalse(refused.completed)
            XCTAssertTrue(graph.readerC.node.parent === graph.readerB.node)
            XCTAssertTrue(newer.component.receipt.hasDeclaredComponent)
            XCTAssertTrue(savedSibling.invokeIfAdmitted())
            XCTAssertTrue(originalSibling.invokeIfAdmitted())
            _ = older.finish(completed: false)
            XCTAssertTrue(newer.component.receipt.hasDeclaredComponent)
            graph.fixture.assertCurrent()
        }

        // Give source/target mismatch its own attempt. No later rejection can
        // pass merely because this check consumed or poisoned a B ticket.
        do {
            let graph = try CatalogProofGraph()
            let attempt = try graph.fixture.body()
            let incoming = try graph.incoming(in: attempt)
            attempt.begin(sources: [incoming.b.node, incoming.sibling.node])
            XCTAssertTrue(attempt.journal.applyOwnedCandidateDeferredCatalog(at: graph.fixture.reader.node))
            XCTAssertFalse(attempt.journal.applyOwnedCandidateCatalog(from: incoming.b.node, to: graph.sibling.node))
            XCTAssertTrue(graph.readerB.component.receipt.hasDeclaredComponent)
            XCTAssertTrue(graph.readerC.component.receipt.hasDeclaredComponent)
            XCTAssertTrue(graph.sibling.component.receipt.hasDeclaredComponent)
            XCTAssertTrue(graph.readerB.node.parent === graph.fixture.reader.node)
            XCTAssertTrue(graph.readerC.node.parent === graph.readerB.node)
            XCTAssertTrue(graph.sibling.node.parent === graph.fixture.reader.node)
            _ = attempt.finish(completed: false)
            graph.fixture.assertCurrent()
        }

        // Existing cold B is neither a fresh declaration nor an unscoped
        // node. Test both a lost original physical proof and an A capture made
        // only after B is already cold, with no original physical B to capture.
        for removalBeforeCapture in [false, true] {
            let graph = try CatalogProofGraph()
            let originalB = try CatalogProofOriginalContinuation(graph.readerB.node, in: graph.fixture.runtime)
            if removalBeforeCapture {
                graph.fixture.reader.node.setChildren([graph.sibling.node])
            }
            let older = try graph.fixture.body()
            let incoming = try graph.incoming(in: older)
            older.begin(sources: [incoming.b.node, incoming.sibling.node])
            if !removalBeforeCapture {
                graph.fixture.reader.node.setChildren([graph.sibling.node])
            }
            XCTAssertNil(graph.readerB.node.parent)
            XCTAssertFalse(originalB.actual.isAttached)
            XCTAssertTrue(graph.readerB.component.receipt.hasAcceptedDeclaration)
            XCTAssertTrue(graph.readerB.component.receipt.hasDeclaredComponent)
            XCTAssertFalse(originalB.invokeIfAdmitted())
            XCTAssertFalse(older.journal.applyOwnedCandidateCatalog(from: incoming.b.node, to: graph.readerB.node))

            let nonoriginalTarget = catalogProofNode(20)
            graph.fixture.reader.node.addChild(nonoriginalTarget)
            XCTAssertTrue(nonoriginalTarget.isRetainedLazyListAttached(in: graph.fixture.runtime))
            XCTAssertFalse(older.journal.applyOwnedCandidateCatalog(from: incoming.b.node, to: nonoriginalTarget))
            let refused = ComponentHost.adopt(
                source: incoming.b.node, into: nonoriginalTarget, lazyJournal: older.journal)
            XCTAssertFalse(refused.completed)
            XCTAssertNil(nonoriginalTarget.retainedLazyListActivityStorage?.descriptorDeferredSubtreeAnchor)
            XCTAssertTrue(graph.readerB.component.receipt.hasDeclaredComponent)
            XCTAssertTrue(graph.sibling.component.receipt.hasDeclaredComponent)
            _ = older.finish(completed: false)
            graph.fixture.assertCurrent()
        }
    }

    func testAcceptedCatalogRepeatAndReentrantFailureCannotGrantOrUndoNativeFacts() async throws {
        let graph = try CatalogProofGraph()
        let cold = try graph.makeColdLeaf(in: graph.readerC, identity: 31)
        let originalC = try CatalogProofOriginalContinuation(graph.readerC.node, in: graph.fixture.runtime)
        let navigation = try graph.prepareNavigation()
        defer { navigation.cancelPreparedNavigation() }
        let older = try graph.fixture.body()
        let incoming = try graph.incoming(in: older)
        let pending = try older.reader(under: incoming.b.context, identity: 40)
        incoming.b.node.addChild(pending.node)
        let pendingTask = try older.stagePendingTask(on: pending)
        older.begin(sources: [incoming.b.node, incoming.sibling.node])
        let originalSourceProof = incoming.b.node.captureLazyListAttachmentProof()
        var cancellations = 0
        var deliveries = 0
        var newerMember: CatalogProofLeaf?
        var reentryError: Error?
        XCTAssertTrue(
            navigation.schedulePreparedNavigationReplay(
                afterLayout: true, perform: { deliveries += 1 },
                onCancel: {
                    cancellations += 1
                    XCTAssertTrue(graph.readerC.node.parent === graph.readerB.node)
                    XCTAssertTrue(originalC.actual.isAttached)
                    XCTAssertTrue(graph.readerC.component.receipt.hasDeclaredComponent)
                    XCTAssertFalse(cold.component.receipt.hasDeclaredComponent)
                    XCTAssertFalse(originalC.invokeIfAdmitted())

                    // These are observations of the SAME accepted B source/
                    // target write, not new successful normal publications.
                    for _ in 0..<2 {
                        XCTAssertTrue(
                            older.journal.applyOwnedCandidateCatalog(
                                from: incoming.b.node, to: graph.readerB.node))
                        XCTAssertFalse(pending.component.receipt.hasAcceptedDeclaration)
                        XCTAssertFalse(pending.component.receipt.hasDeclaredComponent)
                        XCTAssertNil(pending.node.retainedLazyListActivityStorage?.descriptorDeferredSubtreeAnchor)
                        XCTAssertFalse(pendingTask.canCommit)
                        XCTAssertTrue(older.journal.takeAcceptedDescriptorTaskGroups().isEmpty)
                    }
                    // Fresh D has no accepted original reader/cohort. This
                    // classified awaiting-facts no-op grants no catalog receipt.
                    XCTAssertTrue(
                        older.journal.applyOwnedCandidateCatalog(from: pending.node, to: pending.node))
                    XCTAssertFalse(pending.component.receipt.hasAcceptedDeclaration)
                    XCTAssertFalse(pending.component.receipt.hasDeclaredComponent)
                    XCTAssertNil(pending.node.retainedLazyListActivityStorage?.descriptorDeferredSubtreeAnchor)
                    XCTAssertFalse(pendingTask.canCommit)
                    XCTAssertTrue(older.journal.takeAcceptedDescriptorTaskGroups().isEmpty)

                    do {
                        // Start a NEW actual A admission. Do not refresh the
                        // old B lease after its accepted catalog changed.
                        let currentA = try graph.fixture.body()
                        let fresh = try graph.incoming(in: currentA)
                        let member = try currentA.leaf(under: fresh.b.context, identity: 52)
                        fresh.b.node.addChild(member.node)
                        currentA.begin(sources: [fresh.b.node, fresh.sibling.node])
                        let accepted = ComponentHost.reconcileChildren(
                            of: graph.fixture.reader.node, oldChildren: graph.fixture.reader.node.children,
                            newNodes: [fresh.b.node, fresh.sibling.node], lazyJournal: currentA.journal)
                        XCTAssertTrue(accepted.completed)
                        guard accepted.completed else {
                            _ = currentA.finish(completed: false)
                            return
                        }
                        XCTAssertTrue(member.component.receipt.hasAcceptedDeclaration)
                        XCTAssertTrue(member.component.receipt.hasDeclaredComponent)
                        // Only the independently completed normal reader plus
                        // its real descriptor fact authorizes this continuation.
                        let acceptedB = try CatalogProofOriginalContinuation(
                            graph.readerB.node, in: graph.fixture.runtime)
                        XCTAssertTrue(acceptedB.invokeIfAdmitted())
                        _ = currentA.finish()
                        graph.readerB.node.setChildren([])
                        XCTAssertNil(member.node.parent)
                        XCTAssertTrue(member.component.receipt.hasDeclaredComponent)
                        newerMember = member

                        // This later loss is observable application reentry.
                        // It does not inject a fault inside raw-store/afterimage.
                        incoming.b.node.lazyListActivityStorage().revokeAttachment()
                        XCTAssertFalse(originalSourceProof.isCurrent)
                        XCTAssertFalse(
                            older.journal.applyOwnedCandidateCatalog(
                                from: incoming.b.node, to: graph.readerB.node))
                        XCTAssertTrue(member.component.receipt.hasDeclaredComponent)
                        XCTAssertFalse(cold.component.receipt.hasDeclaredComponent)
                    } catch {
                        reentryError = error
                    }
                }))

        let refused = ComponentHost.reconcileChildren(
            of: graph.fixture.reader.node, oldChildren: graph.fixture.reader.node.children,
            newNodes: [incoming.b.node, incoming.sibling.node], lazyJournal: older.journal)

        XCTAssertFalse(refused.completed)
        XCTAssertEqual(cancellations, 1)
        XCTAssertEqual(deliveries, 0)
        XCTAssertNil(reentryError)
        let member = try XCTUnwrap(newerMember)
        XCTAssertFalse(originalSourceProof.isCurrent)
        XCTAssertNil(graph.readerC.node.parent)
        XCTAssertFalse(graph.readerC.component.receipt.hasDeclaredComponent)
        XCTAssertFalse(cold.component.receipt.hasDeclaredComponent)
        XCTAssertTrue(member.component.receipt.hasDeclaredComponent)
        XCTAssertFalse(pending.component.receipt.hasDeclaredComponent)
        XCTAssertNil(pending.node.retainedLazyListActivityStorage?.descriptorDeferredSubtreeAnchor)
        XCTAssertFalse(pendingTask.canCommit)
        XCTAssertTrue(older.journal.takeAcceptedDescriptorTaskGroups().isEmpty)
        _ = older.finish(completed: false)
        XCTAssertTrue(member.component.receipt.hasDeclaredComponent)
        XCTAssertFalse(cold.component.receipt.hasDeclaredComponent)
        graph.fixture.assertCurrent()
        let sibling = try CatalogProofOriginalContinuation(graph.sibling.node, in: graph.fixture.runtime)
        XCTAssertTrue(sibling.invokeIfAdmitted())

        // No stale ancestor copy may mask the newer member's later omission.
        let acceptedB = try CatalogProofOriginalContinuation(graph.readerB.node, in: graph.fixture.runtime)
        let omission = try CatalogProofEpoch(acceptedB)
        omission.begin(sources: [])
        XCTAssertTrue(omission.journal.applyOwnedCandidateDeferredCatalog(at: graph.readerB.node))
        XCTAssertFalse(member.component.receipt.hasDeclaredComponent)
        XCTAssertTrue(graph.readerB.component.receipt.hasDeclaredComponent)
        XCTAssertTrue(sibling.invokeIfAdmitted())
        _ = omission.finish(completed: false)
    }
}

private enum CatalogProofForeignWriter: Equatable {
    case readerB, readerC
}

@MainActor
private func catalogProofNode(_ identity: Int) -> ViewNode {
    let node = ViewNode()
    node.retainedViewIdentity = RetainedViewIdentity().appending(.slot(identity))
    return node
}

@MainActor
private struct CatalogProofComponent {
    let attribution: RetainedDescriptorComponentAttribution
    let receipt: RetainedOwnedComponentReceipt
    let group: RetainedDescriptorGroupID
}

@MainActor
private struct CatalogProofContext {
    let attribution: RetainedDescriptorComponentAttribution
    let token: RetainedOwnedCandidateConstruction
}

@MainActor
private struct CatalogProofReader {
    let node: ViewNode
    let component: CatalogProofComponent
    let context: CatalogProofContext
}

@MainActor
private final class CatalogProofOriginalContinuation {
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

    func lease() -> CatalogProofLease? {
        guard let scope = admittedScope(), let attribution = scope.registerOrdinaryComponent() else { return nil }
        return CatalogProofLease(scope: scope, attribution: attribution)
    }

    func invokeIfAdmitted(_ body: @MainActor () -> Void = {}) -> Bool {
        guard let lease = lease() else { return false }
        defer { lease.finish() }
        return lease.invokeIfAdmitted(body)
    }
}

@MainActor
private final class CatalogProofLease {
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
private final class CatalogProofEpoch {
    let runtime: RetainedViewRuntime
    let scope: RetainedLazyListDescriptorBuildScope
    let journal: RetainedLazyListAdoptionJournal
    let context: CatalogProofContext?

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

    init(_ original: CatalogProofOriginalContinuation) throws {
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
        let context = CatalogProofContext(
            attribution: attribution, token: try XCTUnwrap(token, "Expected the original accepted reader continuation"))
        runtime = original.runtime
        self.scope = scope
        self.journal = journal
        self.context = context
    }

    func openComponent(
        under parent: CatalogProofContext? = nil, kind: RetainedLazyListContributionKind = .observation,
        continuing: RetainedOwnedComponentReceipt? = nil
    ) throws -> CatalogProofComponent {
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
        return CatalogProofComponent(attribution: attribution, receipt: receipt, group: group)
    }

    func close(_ component: CatalogProofComponent, node: ViewNode) throws {
        XCTAssertTrue(component.attribution.recordSourceOutput(node, group: component.group))
        _ = try XCTUnwrap(component.attribution.closeGroup(component.group))
    }

    func reader(
        under parent: CatalogProofContext, identity: Int, continuing: RetainedOwnedComponentReceipt? = nil
    ) throws -> CatalogProofReader {
        let component = try openComponent(under: parent, kind: .deferredSubtree, continuing: continuing)
        let token = try XCTUnwrap(
            parent.token.deferredSegment(owner: component.receipt, attribution: component.attribution))
        let node = catalogProofNode(identity)
        node.geometryReaderBuild = { _, _ in [] }
        XCTAssertTrue(token.stageDeferredAnchor(on: node))
        try close(component, node: node)
        return CatalogProofReader(
            node: node, component: component,
            context: CatalogProofContext(attribution: component.attribution, token: token))
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
private final class CatalogProofBoundary {
    let epoch: CatalogProofEpoch
    let component: CatalogProofComponent
    let context: CatalogProofContext

    init(epoch: CatalogProofEpoch, under parent: CatalogProofContext? = nil) throws {
        let component = try epoch.openComponent(under: parent)
        let token = try XCTUnwrap(component.attribution.beginOwnedCandidateConstruction(owner: component.receipt))
        self.epoch = epoch
        self.component = component
        context = CatalogProofContext(attribution: component.attribution, token: token)
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
private final class CatalogProofFixture {
    let runtime: RetainedViewRuntime
    let boundary: ViewNode
    let owner: CatalogProofComponent
    let reader: CatalogProofReader
    let original: CatalogProofOriginalContinuation

    init() throws {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let epoch = CatalogProofEpoch(runtime)
        let construction = try CatalogProofBoundary(epoch: epoch)
        let reader = try epoch.reader(under: construction.context, identity: 10)
        let boundary = try construction.close(child: reader.node, identity: 1000)
        epoch.begin(sources: [boundary])
        epoch.installTree(boundary, under: runtime.root)
        _ = epoch.finish()
        self.runtime = runtime
        owner = construction.component
        self.reader = reader
        self.boundary = boundary
        original = try CatalogProofOriginalContinuation(reader.node, in: runtime)
        XCTAssertTrue(owner.receipt.hasAcceptedDeclaration)
        XCTAssertTrue(reader.component.receipt.hasAcceptedDeclaration)
        assertCurrent()
    }

    func body() throws -> CatalogProofEpoch { try CatalogProofEpoch(original) }

    func assertCurrent(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(owner.receipt.hasDeclaredComponent, file: file, line: line)
        XCTAssertTrue(reader.component.receipt.hasDeclaredComponent, file: file, line: line)
        XCTAssertTrue(boundary.isRetainedLazyListAttached(in: runtime), file: file, line: line)
        XCTAssertTrue(reader.node.parent === boundary, file: file, line: line)
        XCTAssertTrue(original.invokeIfAdmitted(), file: file, line: line)
    }
}

@MainActor
private struct CatalogProofLeaf {
    let node: ViewNode
    let component: CatalogProofComponent
}

extension CatalogProofEpoch {
    fileprivate func leaf(under parent: CatalogProofContext, identity: Int) throws -> CatalogProofLeaf {
        let component = try openComponent(under: parent)
        let node = catalogProofNode(identity)
        try close(component, node: node)
        return CatalogProofLeaf(node: node, component: component)
    }

    fileprivate func stagePendingTask(on reader: CatalogProofReader) throws -> RetainedTaskDeclaration {
        let group = try XCTUnwrap(reader.component.attribution.registerGroup(kind: .scopedTask))
        let task = RetainedTaskDeclaration(
            mount: RetainedTaskMountToken(), priority: .userInitiated, action: {},
            isMember: { true }, isCurrentProposal: { true })
        XCTAssertTrue(
            task.stage(
                groupSources: [reader.node], in: runtime,
                descriptorAttribution: reader.component.attribution, group: group))
        _ = try XCTUnwrap(reader.component.attribution.closeGroup(group))
        XCTAssertFalse(task.canCommit)
        return task
    }
}

@MainActor
private final class CatalogProofGraph {
    let fixture: CatalogProofFixture
    let readerB: CatalogProofReader
    let readerC: CatalogProofReader
    let sibling: CatalogProofReader

    init() throws {
        let fixture = try CatalogProofFixture()
        let body = try fixture.body()
        let context = try XCTUnwrap(body.context)
        let readerB = try body.reader(under: context, identity: 20)
        let readerC = try body.reader(under: readerB.context, identity: 30)
        let sibling = try body.reader(under: context, identity: 60)
        readerB.node.addChild(readerC.node)
        body.begin(sources: [readerB.node, sibling.node])
        XCTAssertTrue(body.journal.applyOwnedCandidateDeferredCatalog(at: fixture.reader.node))
        body.installTree(readerB.node, under: fixture.reader.node)
        body.installTree(sibling.node, under: fixture.reader.node)
        _ = body.finish()
        self.fixture = fixture
        self.readerB = readerB
        self.readerC = readerC
        self.sibling = sibling
        XCTAssertTrue(readerB.component.receipt.hasDeclaredComponent)
        XCTAssertTrue(readerC.component.receipt.hasDeclaredComponent)
        XCTAssertTrue(sibling.component.receipt.hasDeclaredComponent)
    }

    func incoming(in epoch: CatalogProofEpoch) throws -> (b: CatalogProofReader, sibling: CatalogProofReader) {
        let context = try XCTUnwrap(epoch.context)
        return (
            try epoch.reader(under: context, identity: 20, continuing: readerB.component.receipt),
            try epoch.reader(under: context, identity: 60, continuing: sibling.component.receipt)
        )
    }

    func makeColdLeaf(in reader: CatalogProofReader, identity: Int) throws -> CatalogProofLeaf {
        let original = try CatalogProofOriginalContinuation(reader.node, in: fixture.runtime)
        let body = try CatalogProofEpoch(original)
        let leaf = try body.leaf(under: try XCTUnwrap(body.context), identity: identity)
        body.begin(sources: [leaf.node])
        XCTAssertTrue(body.journal.applyOwnedCandidateDeferredCatalog(at: reader.node))
        body.installTree(leaf.node, under: reader.node)
        _ = body.finish()
        XCTAssertTrue(leaf.component.receipt.slots.isEmpty)
        XCTAssertTrue(leaf.component.receipt.hasAcceptedDeclaration)
        XCTAssertTrue(leaf.component.receipt.hasDeclaredComponent)
        reader.node.setChildren(reader.node.children.filter { $0 !== leaf.node })
        XCTAssertNil(leaf.node.parent)
        XCTAssertTrue(leaf.component.receipt.hasDeclaredComponent)
        return leaf
    }

    func prepareNavigation() throws -> RetainedListNavigationReceipt {
        fixture.reader.node.scrollAxis = .vertical
        readerB.node.isFocusable = true
        readerB.node.isFocusEnabled = true
        readerB.node.interceptsVerticalArrowKeys = true
        readerB.node.accessibilityTraits = [.isSelectable]
        let scope = RetainedListNavigationOwner(runtime: fixture.runtime)
        scope.install(on: fixture.reader.node)
        let row = scope.makeRowOwner(on: readerB.node)
        return try XCTUnwrap(scope.prepareAction(from: row))
    }
}
