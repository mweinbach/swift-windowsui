import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI

/// These tests enter through real descriptor admission and successful native
/// publication. They never install a namespace field, reader proof, or reference.
@MainActor
final class RetainedOwnedCandidateSegmentAdmissionTests: XCTestCase {
    func testEmptyNestedReaderLosesAdmissionAtParentCatalogOmissionWhileStillPhysical() async throws {
        let fixture = try SegmentProofFixture()
        let body = try fixture.body()
        let reader = try body.reader(under: try XCTUnwrap(body.context), identity: 20)
        body.begin(sources: [reader.node])
        XCTAssertTrue(body.journal.applyOwnedCandidateDeferredCatalog(at: fixture.reader.node))
        body.installTree(reader.node, under: fixture.reader.node)
        _ = body.finish()
        let original = try SegmentProofOriginalContinuation(reader.node, in: fixture.runtime)
        let pending = try XCTUnwrap(original.lease())
        defer { pending.finish() }
        var callbacks = 0
        XCTAssertTrue(pending.invokeIfAdmitted { callbacks += 1 })
        XCTAssertEqual(callbacks, 1)
        XCTAssertTrue(reader.node.children.isEmpty)
        XCTAssertTrue(reader.component.receipt.slots.isEmpty)
        XCTAssertTrue(reader.component.receipt.hasDeclaredComponent)
        var dismantles = 0
        reader.node.onDismantlePlatformView = { _ in dismantles += 1 }
        defer { reader.node.onDismantlePlatformView = nil }

        // Only the accepted A segment is written. B's empty segment has no
        // member removal whose revision could incidentally deny its old proof.
        let omission = try fixture.body()
        omission.begin(sources: [])
        XCTAssertTrue(omission.journal.applyOwnedCandidateDeferredCatalog(at: fixture.reader.node))

        XCTAssertEqual(dismantles, 0)
        XCTAssertTrue(reader.node.parent === fixture.reader.node)
        XCTAssertTrue(reader.node.isRetainedLazyListAttached(in: fixture.runtime))
        XCTAssertTrue(original.actual.isAttached)
        XCTAssertTrue(original.contribution.isActive)
        XCTAssertTrue(reader.component.receipt.hasDeclaredComponent)
        XCTAssertFalse(pending.invokeIfAdmitted { callbacks += 1 })
        XCTAssertFalse(original.invokeIfAdmitted { callbacks += 1 })
        XCTAssertEqual(callbacks, 1)
        fixture.assertCurrent()
        _ = omission.finish(completed: false)
    }

    func testRejectedNestedReaderCannotSeedNativeContinuation() async throws {
        let fixture = try SegmentProofFixture()
        let body = try fixture.body()
        let reader = try body.reader(under: try XCTUnwrap(body.context), identity: 20)
        reader.component.attribution.rejectComponent()

        XCTAssertTrue(reader.node.containsRejectedRetainedSource)
        XCTAssertFalse(body.journal.registerSourceDescriptors(in: [reader.node]))
        XCTAssertFalse(body.journal.beginOrdinaryAdoption())
        XCTAssertFalse(reader.context.token.canConstruct)
        switch reader.component.attribution.ownedCandidateContinuation() {
        case .rejected:
            break
        case .unscoped, .admitted:
            XCTFail("A rejected reader must not obtain a candidate continuation")
        }

        XCTAssertNil(reader.node.parent)
        XCTAssertNil(reader.node.retainedLazyListRuntime)
        XCTAssertNil(reader.node.retainedLazyListActivityStorage?.descriptorDeferredSubtreeAnchor)
        XCTAssertFalse(reader.component.receipt.hasAcceptedDeclaration)
        XCTAssertFalse(reader.component.receipt.hasDeclaredComponent)
        XCTAssertTrue(fixture.reader.node.children.isEmpty)
        fixture.assertCurrent()
        _ = body.finish(completed: false)
    }

    func testNestedReaderCannotUseOuterNamespaceBeforeItsOwnBoundaryPublishes() async throws {
        let fixture = try SegmentProofFixture()
        let body = try fixture.body()
        let boundary = try SegmentProofBoundary(epoch: body, under: try XCTUnwrap(body.context))
        let reader = try body.reader(under: boundary.context, identity: 30)
        let source = try boundary.close(child: reader.node, identity: 2000)
        body.begin(sources: [source])
        XCTAssertTrue(body.journal.applyOwnedCandidateDeferredCatalog(at: fixture.reader.node))
        body.prepareTree(source)
        fixture.reader.node.addChild(source)

        // B's actual owner and descriptor facts do not publish the designated
        // I boundary node. A's accepted namespace cannot stand in for I's.
        body.acceptPreparedTree(reader.node)
        let original = try SegmentProofOriginalContinuation(reader.node, in: fixture.runtime)
        let earlier = try XCTUnwrap(original.lease())
        defer { earlier.finish() }
        var callbacks = 0
        XCTAssertTrue(original.actual.isAttached)
        XCTAssertTrue(original.contribution.isActive)
        XCTAssertTrue(reader.component.receipt.hasAcceptedDeclaration)
        XCTAssertTrue(reader.component.receipt.hasDeclaredComponent)
        XCTAssertFalse(earlier.invokeIfAdmitted { callbacks += 1 })
        XCTAssertEqual(callbacks, 0)
        fixture.assertCurrent()

        // This is the actual prepared source/target publication on I. Only a
        // fresh admission may use the newly accepted inner namespace.
        body.acceptPreparedNode(source)
        XCTAssertFalse(earlier.invokeIfAdmitted { callbacks += 1 })
        XCTAssertTrue(original.invokeIfAdmitted { callbacks += 1 })
        XCTAssertEqual(callbacks, 1)
        XCTAssertTrue(source.parent === fixture.reader.node)
        XCTAssertTrue(reader.node.parent === source)
        fixture.assertCurrent()
        _ = body.finish()
    }

    func testRecursiveSameNamespaceContinuationsRejectOmissionAndOriginalProofRotation() async throws {
        for mutation in [
            SegmentProofRecursiveMutation.omitB, .retainBOmitC, .rotateCProof,
        ] {
            let fixture = try SegmentProofFixture()
            let body = try fixture.body()
            let readerB = try body.reader(under: try XCTUnwrap(body.context), identity: 20)
            let readerC = try body.reader(under: readerB.context, identity: 30)
            readerB.node.addChild(readerC.node)
            body.begin(sources: [readerB.node])
            XCTAssertTrue(body.journal.applyOwnedCandidateDeferredCatalog(at: fixture.reader.node))
            body.installTree(readerB.node, under: fixture.reader.node)
            _ = body.finish()
            let originalB = try SegmentProofOriginalContinuation(readerB.node, in: fixture.runtime)
            let originalC = try SegmentProofOriginalContinuation(readerC.node, in: fixture.runtime)
            let pendingB = try XCTUnwrap(originalB.lease())
            let pendingC = try XCTUnwrap(originalC.lease())
            defer {
                pendingB.finish()
                pendingC.finish()
            }
            var callbacks = 0
            XCTAssertTrue(pendingB.invokeIfAdmitted { callbacks += 1 })
            XCTAssertTrue(pendingC.invokeIfAdmitted { callbacks += 1 })
            XCTAssertEqual(callbacks, 2)
            XCTAssertTrue(readerC.node.children.isEmpty)
            XCTAssertTrue(readerB.component.receipt.slots.isEmpty)
            XCTAssertTrue(readerC.component.receipt.slots.isEmpty)

            switch mutation {
            case .rotateCProof:
                readerC.node.lazyListActivityStorage().revokeAttachment()

                XCTAssertFalse(originalC.actual.isAttached)
                XCTAssertTrue(originalB.actual.isAttached)
                XCTAssertTrue(readerC.node.isRetainedLazyListAttached(in: fixture.runtime))
                XCTAssertTrue(readerB.component.receipt.hasDeclaredComponent)
                XCTAssertTrue(readerC.component.receipt.hasDeclaredComponent)
                XCTAssertTrue(pendingB.invokeIfAdmitted())
                XCTAssertFalse(pendingC.invokeIfAdmitted { callbacks += 1 })
                XCTAssertFalse(originalC.invokeIfAdmitted { callbacks += 1 })
            case .omitB:
                let omission = try fixture.body()
                omission.begin(sources: [])
                XCTAssertTrue(omission.journal.applyOwnedCandidateDeferredCatalog(at: fixture.reader.node))

                XCTAssertTrue(originalB.actual.isAttached)
                XCTAssertTrue(originalC.actual.isAttached)
                XCTAssertTrue(originalB.contribution.isActive)
                XCTAssertTrue(originalC.contribution.isActive)
                XCTAssertTrue(readerB.component.receipt.hasDeclaredComponent)
                XCTAssertTrue(readerC.component.receipt.hasDeclaredComponent)
                XCTAssertFalse(pendingB.invokeIfAdmitted { callbacks += 1 })
                XCTAssertFalse(pendingC.invokeIfAdmitted { callbacks += 1 })
                XCTAssertFalse(originalB.invokeIfAdmitted { callbacks += 1 })
                XCTAssertFalse(originalC.invokeIfAdmitted { callbacks += 1 })
                _ = omission.finish(completed: false)
            case .retainBOmitC:
                let replacement = try fixture.body()
                let replacementB = try replacement.reader(
                    under: try XCTUnwrap(replacement.context), identity: 20,
                    continuing: readerB.component.receipt)
                replacement.begin(sources: [replacementB.node])
                var dismantles = 0
                readerC.node.onDismantlePlatformView = { departing in
                    dismantles += 1
                    XCTAssertTrue(departing === readerC.node)
                    XCTAssertFalse(readerC.component.receipt.hasDeclaredComponent)
                    XCTAssertFalse(pendingC.invokeIfAdmitted { callbacks += 1 })
                    XCTAssertTrue(readerB.component.receipt.hasDeclaredComponent)
                }
                defer { readerC.node.onDismantlePlatformView = nil }

                // A retains B. The real matched-node traversal must write B's
                // omitted C catalog before the original C physical departure.
                let result = ComponentHost.reconcileChildren(
                    of: fixture.reader.node, oldChildren: fixture.reader.node.children,
                    newNodes: [replacementB.node], lazyJournal: replacement.journal)

                XCTAssertTrue(result.completed)
                XCTAssertEqual(dismantles, 1)
                XCTAssertTrue(fixture.reader.node.children.first === readerB.node)
                XCTAssertTrue(readerB.node.children.isEmpty)
                XCTAssertNil(readerC.node.parent)
                XCTAssertFalse(readerC.component.receipt.hasDeclaredComponent)
                XCTAssertTrue(replacementB.component.receipt.hasDeclaredComponent)
                let currentB = try SegmentProofOriginalContinuation(readerB.node, in: fixture.runtime)
                XCTAssertTrue(currentB.invokeIfAdmitted())
                _ = replacement.finish()
            }

            XCTAssertEqual(callbacks, 2)
            XCTAssertTrue(readerB.node.parent === fixture.reader.node)
            if mutation == .retainBOmitC {
                XCTAssertNil(readerC.node.parent)
            } else {
                XCTAssertTrue(readerC.node.parent === readerB.node)
            }
            fixture.assertCurrent()
        }
    }
}

private enum SegmentProofRecursiveMutation: Equatable {
    case omitB, retainBOmitC, rotateCProof
}

@MainActor
private func segmentProofNode(_ identity: Int) -> ViewNode {
    let node = ViewNode()
    node.retainedViewIdentity = RetainedViewIdentity().appending(.slot(identity))
    return node
}

@MainActor
private struct SegmentProofComponent {
    let attribution: RetainedDescriptorComponentAttribution
    let receipt: RetainedOwnedComponentReceipt
    let group: RetainedDescriptorGroupID
}

@MainActor
private struct SegmentProofContext {
    let attribution: RetainedDescriptorComponentAttribution
    let token: RetainedOwnedCandidateConstruction
}

@MainActor
private struct SegmentProofReader {
    let node: ViewNode
    let component: SegmentProofComponent
    let context: SegmentProofContext
}

@MainActor
private final class SegmentProofOriginalContinuation {
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

    func lease() -> SegmentProofLease? {
        guard let scope = admittedScope(), let attribution = scope.registerOrdinaryComponent() else { return nil }
        return SegmentProofLease(scope: scope, attribution: attribution)
    }

    func invokeIfAdmitted(_ body: @MainActor () -> Void = {}) -> Bool {
        guard let lease = lease() else { return false }
        defer { lease.finish() }
        return lease.invokeIfAdmitted(body)
    }
}

@MainActor
private final class SegmentProofLease {
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
private final class SegmentProofEpoch {
    let runtime: RetainedViewRuntime
    let scope: RetainedLazyListDescriptorBuildScope
    let journal: RetainedLazyListAdoptionJournal
    let context: SegmentProofContext?

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

    init(_ original: SegmentProofOriginalContinuation) throws {
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
        let context = SegmentProofContext(
            attribution: attribution, token: try XCTUnwrap(token, "Expected the original accepted reader continuation"))
        runtime = original.runtime
        self.scope = scope
        self.journal = journal
        self.context = context
    }

    func openComponent(
        under parent: SegmentProofContext? = nil, kind: RetainedLazyListContributionKind = .observation,
        continuing: RetainedOwnedComponentReceipt? = nil
    ) throws -> SegmentProofComponent {
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
        return SegmentProofComponent(attribution: attribution, receipt: receipt, group: group)
    }

    func close(_ component: SegmentProofComponent, node: ViewNode) throws {
        XCTAssertTrue(component.attribution.recordSourceOutput(node, group: component.group))
        _ = try XCTUnwrap(component.attribution.closeGroup(component.group))
    }

    func reader(
        under parent: SegmentProofContext, identity: Int, continuing: RetainedOwnedComponentReceipt? = nil
    ) throws -> SegmentProofReader {
        let component = try openComponent(under: parent, kind: .deferredSubtree, continuing: continuing)
        let token = try XCTUnwrap(
            parent.token.deferredSegment(owner: component.receipt, attribution: component.attribution))
        let node = segmentProofNode(identity)
        node.geometryReaderBuild = { _, _ in [] }
        XCTAssertTrue(token.stageDeferredAnchor(on: node))
        try close(component, node: node)
        return SegmentProofReader(
            node: node, component: component,
            context: SegmentProofContext(attribution: component.attribution, token: token))
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
private final class SegmentProofBoundary {
    let epoch: SegmentProofEpoch
    let component: SegmentProofComponent
    let context: SegmentProofContext

    init(epoch: SegmentProofEpoch, under parent: SegmentProofContext? = nil) throws {
        let component = try epoch.openComponent(under: parent)
        let token = try XCTUnwrap(component.attribution.beginOwnedCandidateConstruction(owner: component.receipt))
        self.epoch = epoch
        self.component = component
        context = SegmentProofContext(attribution: component.attribution, token: token)
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
private final class SegmentProofFixture {
    let runtime: RetainedViewRuntime
    let boundary: ViewNode
    let owner: SegmentProofComponent
    let reader: SegmentProofReader
    let original: SegmentProofOriginalContinuation

    init() throws {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let epoch = SegmentProofEpoch(runtime)
        let construction = try SegmentProofBoundary(epoch: epoch)
        let reader = try epoch.reader(under: construction.context, identity: 10)
        let boundary = try construction.close(child: reader.node, identity: 1000)
        epoch.begin(sources: [boundary])
        epoch.installTree(boundary, under: runtime.root)
        _ = epoch.finish()
        self.runtime = runtime
        owner = construction.component
        self.reader = reader
        self.boundary = boundary
        original = try SegmentProofOriginalContinuation(reader.node, in: runtime)
        XCTAssertTrue(owner.receipt.hasAcceptedDeclaration)
        XCTAssertTrue(reader.component.receipt.hasAcceptedDeclaration)
        assertCurrent()
    }

    func body() throws -> SegmentProofEpoch { try SegmentProofEpoch(original) }

    func assertCurrent(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(owner.receipt.hasDeclaredComponent, file: file, line: line)
        XCTAssertTrue(reader.component.receipt.hasDeclaredComponent, file: file, line: line)
        XCTAssertTrue(boundary.isRetainedLazyListAttached(in: runtime), file: file, line: line)
        XCTAssertTrue(reader.node.parent === boundary, file: file, line: line)
        XCTAssertTrue(original.invokeIfAdmitted(), file: file, line: line)
    }
}
