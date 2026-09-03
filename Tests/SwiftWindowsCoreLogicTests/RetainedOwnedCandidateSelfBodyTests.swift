import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI

/// Exercises fresh body consumers after the original SELF contribution has
/// retired, using native publication and physical removal rather than proof hooks.
@MainActor
final class RetainedOwnedCandidateSelfBodyTests: XCTestCase {
    func testSelfBodyPreservesPlainAndReaderMembersUntilTheNextIndependentOmission() async throws {
        for isReader in [false, true] {
            let fixture = try SelfBodyProofFixture()
            let epoch = try fixture.body()
            let context = try XCTUnwrap(epoch.context)
            XCTAssertTrue(context.token.canConstruct)
            let rebuilt = try epoch.reader(
                under: context, identity: 10, continuing: fixture.reader.component.receipt)
            XCTAssertTrue(rebuilt.context.token === context.token)
            let member: SelfBodyProofComponent
            let memberNode: ViewNode
            if isReader {
                let reader = try epoch.reader(under: rebuilt.context, identity: 20)
                member = reader.component
                memberNode = reader.node
            } else {
                member = try epoch.openComponent(under: rebuilt.context)
                memberNode = selfBodyProofNode(20)
                try epoch.close(member, node: memberNode)
            }
            rebuilt.node.addChild(memberNode)
            let expectedReader = try XCTUnwrap(
                rebuilt.component.attribution.contribution(for: rebuilt.component.group))
            let expectedMember = try XCTUnwrap(member.attribution.contribution(for: member.group))
            XCTAssertFalse(member.receipt.hasAcceptedDeclaration)
            XCTAssertFalse(expectedReader.isActive)
            XCTAssertFalse(expectedMember.isActive)
            epoch.begin(sources: [rebuilt.node])
            XCTAssertTrue(epoch.journal.applyOwnedCandidateDeferredCatalog(at: fixture.reader.node))

            let result = ComponentHost.adopt(
                source: rebuilt.node, into: fixture.reader.node, lazyJournal: epoch.journal)
            XCTAssertTrue(result.completed)
            XCTAssertTrue(rebuilt.component.receipt.hasAcceptedDeclaration)
            XCTAssertTrue(rebuilt.component.receipt.owner === fixture.reader.component.receipt.owner)
            XCTAssertFalse(fixture.original.contribution.isActive)
            XCTAssertFalse(context.token.canConstruct)
            XCTAssertTrue(expectedReader.isActive)
            XCTAssertTrue(member.receipt.hasAcceptedDeclaration)
            XCTAssertTrue(member.receipt.hasDeclaredComponent)
            XCTAssertTrue(member.receipt.slots.isEmpty)
            XCTAssertTrue(expectedMember.isActive)
            XCTAssertTrue(memberNode.parent === fixture.reader.node)
            XCTAssertTrue(memberNode.isRetainedLazyListAttached(in: fixture.runtime))
            let current = try SelfBodyProofOriginalContinuation(fixture.reader.node, in: fixture.runtime)
            XCTAssertTrue(current.contribution === expectedReader)
            XCTAssertTrue(current.actual.target === fixture.original.actual.target)
            XCTAssertTrue(current.actual.attachment === fixture.original.actual.attachment)
            XCTAssertTrue(current.invokeIfAdmitted())
            if isReader {
                // A's completed join must also permit the fresh B normal/group
                // consumer to establish its own actual deferred continuation.
                let child = try SelfBodyProofOriginalContinuation(memberNode, in: fixture.runtime)
                XCTAssertTrue(child.contribution === expectedMember)
                XCTAssertTrue(child.invokeIfAdmitted())
            }
            _ = epoch.finish()
            XCTAssertTrue(current.invokeIfAdmitted())

            fixture.reader.node.setChildren([])
            XCTAssertNil(memberNode.parent)
            XCTAssertFalse(memberNode.isRetainedLazyListAttached(in: fixture.runtime))
            XCTAssertFalse(expectedMember.isActive)
            XCTAssertTrue(member.receipt.hasDeclaredComponent)
            XCTAssertTrue(fixture.reader.component.receipt.hasDeclaredComponent)
            XCTAssertTrue(fixture.owner.receipt.hasDeclaredComponent)

            // Only a new operation admitted from the new exact A descriptor
            // removes the namespace-only zero-slot member.
            let omission = try SelfBodyProofEpoch(current)
            XCTAssertTrue(try XCTUnwrap(omission.context).token !== context.token)
            omission.begin(sources: [])
            XCTAssertTrue(omission.journal.applyOwnedCandidateDeferredCatalog(at: fixture.reader.node))
            XCTAssertFalse(member.receipt.hasDeclaredComponent)
            XCTAssertTrue(expectedReader.isActive)
            XCTAssertTrue(rebuilt.component.receipt.hasDeclaredComponent)
            XCTAssertTrue(fixture.owner.receipt.hasDeclaredComponent)
            XCTAssertTrue(current.actual.isAttached)
            XCTAssertTrue(current.invokeIfAdmitted())
            _ = omission.finish()
            XCTAssertFalse(member.receipt.hasDeclaredComponent)
        }
    }

    func testLateForeignRootCatalogDeniesQueuedSelfBodyMemberAfterOwnOriginalRetirement() async throws {
        let fixture = try SelfBodyProofFixture()
        let epoch = try fixture.body()
        let context = try XCTUnwrap(epoch.context)
        let rebuilt = try epoch.reader(
            under: context, identity: 10, continuing: fixture.reader.component.receipt)
        XCTAssertTrue(rebuilt.context.token === context.token)
        let member = try epoch.openComponent(under: rebuilt.context)
        let memberNode = selfBodyProofNode(20)
        try epoch.close(member, node: memberNode)
        rebuilt.node.addChild(memberNode)
        let sourceIdentity = rebuilt.node.captureLazyListIdentityProof()
        let sourceAttachment = rebuilt.node.captureLazyListAttachmentProof()
        let expectedReader = try XCTUnwrap(
            rebuilt.component.attribution.contribution(for: rebuilt.component.group))
        let expectedMember = try XCTUnwrap(member.attribution.contribution(for: member.group))
        epoch.begin(sources: [rebuilt.node])
        XCTAssertTrue(epoch.journal.applyOwnedCandidateDeferredCatalog(at: fixture.reader.node))
        XCTAssertTrue(epoch.journal.applyOwnedCandidateCatalog(from: rebuilt.node, to: fixture.reader.node))

        // Accept A's normal property fact and drain its own original descriptor,
        // but do not supply A's attachment/completion facts yet.
        XCTAssertTrue(epoch.copyGeometryOnly(from: rebuilt.node, to: fixture.reader.node))
        XCTAssertTrue(rebuilt.component.receipt.hasAcceptedDeclaration)
        XCTAssertFalse(fixture.original.contribution.isActive)
        XCTAssertFalse(context.token.canConstruct)
        XCTAssertFalse(expectedReader.isActive)
        XCTAssertNil(fixture.reader.node.retainedLazyListActivityStorage?.descriptorDeferredSubtreeAnchor)
        XCTAssertTrue(epoch.scope.canPublishDescriptors)
        XCTAssertTrue(epoch.journal.canContinueAdoption)

        // The leaf now has real native normal/group facts while the expected A
        // group is still incomplete. It is not merely a planned fresh member.
        epoch.installTree(memberNode, under: fixture.reader.node)
        XCTAssertTrue(member.receipt.hasAcceptedDeclaration)
        XCTAssertTrue(member.receipt.hasDeclaredComponent)
        XCTAssertTrue(member.receipt.slots.isEmpty)
        XCTAssertTrue(expectedMember.isActive)
        XCTAssertFalse(expectedReader.isActive)
        XCTAssertTrue(memberNode.parent === fixture.reader.node)
        XCTAssertTrue(sourceIdentity.isCurrent)
        XCTAssertTrue(sourceAttachment.isCurrent)

        // This independent root operation continues W and declares existing A.
        // Its actual catalog write changes W's original field revision without
        // adopting its source or changing A, the leaf, or the older SELF source.
        let foreign = SelfBodyProofEpoch(fixture.runtime)
        let owner = try foreign.openComponent(continuing: fixture.owner.receipt)
        let token = try XCTUnwrap(owner.attribution.beginOwnedCandidateConstruction(owner: owner.receipt))
        let attribution = try XCTUnwrap(owner.attribution.registerChildComponent())
        let preservedReader = try XCTUnwrap(
            attribution.registerOwnedComponent(
                owner: rebuilt.component.receipt.owner, slots: rebuilt.component.receipt.slots,
                continuing: rebuilt.component.receipt, declarationOnly: true, candidateConstruction: token))
        let group = try XCTUnwrap(attribution.registerGroup(kind: .structure))
        _ = try XCTUnwrap(attribution.closeGroup(group))
        let source = ViewNode.selectedContentBoundary(role: .viewThatFits, child: selfBodyProofNode(30))
        source.retainedViewIdentity = RetainedViewIdentity().appending(.slot(1000))
        XCTAssertTrue(token.stageBoundary(on: source))
        try foreign.close(owner, node: source)
        foreign.begin(sources: [source])
        let write = try XCTUnwrap(foreign.journal.prepareOwnedCandidateCatalog(from: source, to: fixture.boundary))
        XCTAssertTrue(foreign.journal.publishOwnedCandidateCatalog(write))
        XCTAssertFalse(owner.receipt.hasAcceptedDeclaration)
        XCTAssertTrue(preservedReader.hasDeclaredComponent)
        _ = foreign.finish(completed: false)

        XCTAssertTrue(fixture.owner.receipt.hasDeclaredComponent)
        XCTAssertTrue(fixture.reader.component.receipt.hasDeclaredComponent)
        XCTAssertTrue(fixture.original.actual.isAttached)
        XCTAssertTrue(fixture.reader.node.parent === fixture.boundary)
        XCTAssertTrue(memberNode.parent === fixture.reader.node)
        XCTAssertTrue(sourceIdentity.isCurrent)
        XCTAssertTrue(sourceAttachment.isCurrent)
        XCTAssertFalse(rebuilt.node.containsRejectedRetainedSource)
        XCTAssertFalse(expectedReader.isActive)
        XCTAssertTrue(epoch.scope.canPublishDescriptors)
        XCTAssertTrue(epoch.journal.canContinueAdoption)

        // These remain honest ordinary native facts. The stale original
        // namespace observation must still deny the SELF/body association.
        _ = epoch.journal.recordAcceptedAttachment(from: rebuilt.node, to: fixture.reader.node)
        _ = epoch.journal.recordCompletedNode(from: rebuilt.node, to: fixture.reader.node)
        XCTAssertTrue(expectedReader.isActive)
        XCTAssertTrue(expectedMember.isActive)
        XCTAssertTrue(rebuilt.component.receipt.hasAcceptedDeclaration)
        XCTAssertTrue(member.receipt.hasAcceptedDeclaration)
        XCTAssertFalse(fixture.original.contribution.isActive)
        let current = try SelfBodyProofOriginalContinuation(fixture.reader.node, in: fixture.runtime)
        XCTAssertTrue(current.contribution === expectedReader)
        XCTAssertTrue(current.actual.target === fixture.original.actual.target)
        XCTAssertTrue(current.actual.attachment === fixture.original.actual.attachment)
        XCTAssertFalse(current.invokeIfAdmitted())
        _ = epoch.finish(completed: false)

        fixture.reader.node.setChildren([])
        XCTAssertNil(memberNode.parent)
        XCTAssertFalse(memberNode.isRetainedLazyListAttached(in: fixture.runtime))
        XCTAssertFalse(expectedMember.isActive)
        XCTAssertFalse(member.receipt.hasDeclaredComponent)
        XCTAssertTrue(expectedReader.isActive)
        XCTAssertTrue(rebuilt.component.receipt.hasDeclaredComponent)
        XCTAssertTrue(fixture.owner.receipt.hasDeclaredComponent)
        XCTAssertTrue(current.actual.isAttached)
        XCTAssertFalse(current.invokeIfAdmitted())
    }
}

@MainActor
private func selfBodyProofNode(_ identity: Int) -> ViewNode {
    let node = ViewNode()
    node.retainedViewIdentity = RetainedViewIdentity().appending(.slot(identity))
    return node
}

@MainActor
private struct SelfBodyProofComponent {
    let attribution: RetainedDescriptorComponentAttribution
    let receipt: RetainedOwnedComponentReceipt
    let group: RetainedDescriptorGroupID
}

@MainActor
private struct SelfBodyProofContext {
    let attribution: RetainedDescriptorComponentAttribution
    let token: RetainedOwnedCandidateConstruction
}

@MainActor
private struct SelfBodyProofReader {
    let node: ViewNode
    let component: SelfBodyProofComponent
    let context: SelfBodyProofContext
}

@MainActor
private final class SelfBodyProofOriginalContinuation {
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

    func lease() -> SelfBodyProofLease? {
        guard let scope = admittedScope(), let attribution = scope.registerOrdinaryComponent() else { return nil }
        return SelfBodyProofLease(scope: scope, attribution: attribution)
    }

    func invokeIfAdmitted(_ body: @MainActor () -> Void = {}) -> Bool {
        guard let lease = lease() else { return false }
        defer { lease.finish() }
        return lease.invokeIfAdmitted(body)
    }
}

@MainActor
private final class SelfBodyProofLease {
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
private final class SelfBodyProofEpoch {
    let runtime: RetainedViewRuntime
    let scope: RetainedLazyListDescriptorBuildScope
    let journal: RetainedLazyListAdoptionJournal
    let context: SelfBodyProofContext?

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

    init(_ original: SelfBodyProofOriginalContinuation) throws {
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
        let context = SelfBodyProofContext(
            attribution: attribution, token: try XCTUnwrap(token, "Expected the original accepted reader continuation"))
        runtime = original.runtime
        self.scope = scope
        self.journal = journal
        self.context = context
    }

    func openComponent(
        under parent: SelfBodyProofContext? = nil, kind: RetainedLazyListContributionKind = .observation,
        continuing: RetainedOwnedComponentReceipt? = nil
    ) throws -> SelfBodyProofComponent {
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
        return SelfBodyProofComponent(attribution: attribution, receipt: receipt, group: group)
    }

    func close(_ component: SelfBodyProofComponent, node: ViewNode) throws {
        XCTAssertTrue(component.attribution.recordSourceOutput(node, group: component.group))
        _ = try XCTUnwrap(component.attribution.closeGroup(component.group))
    }

    func reader(
        under parent: SelfBodyProofContext, identity: Int, continuing: RetainedOwnedComponentReceipt? = nil
    ) throws -> SelfBodyProofReader {
        let component = try openComponent(under: parent, kind: .deferredSubtree, continuing: continuing)
        let token = try XCTUnwrap(
            parent.token.deferredSegment(owner: component.receipt, attribution: component.attribution))
        let node = selfBodyProofNode(identity)
        node.geometryReaderBuild = { _, _ in [] }
        XCTAssertTrue(token.stageDeferredAnchor(on: node))
        try close(component, node: node)
        return SelfBodyProofReader(
            node: node, component: component,
            context: SelfBodyProofContext(attribution: component.attribution, token: token))
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
private final class SelfBodyProofBoundary {
    let epoch: SelfBodyProofEpoch
    let component: SelfBodyProofComponent
    let context: SelfBodyProofContext

    init(epoch: SelfBodyProofEpoch, under parent: SelfBodyProofContext? = nil) throws {
        let component = try epoch.openComponent(under: parent)
        let token = try XCTUnwrap(component.attribution.beginOwnedCandidateConstruction(owner: component.receipt))
        self.epoch = epoch
        self.component = component
        context = SelfBodyProofContext(attribution: component.attribution, token: token)
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
private final class SelfBodyProofFixture {
    let runtime: RetainedViewRuntime
    let boundary: ViewNode
    let owner: SelfBodyProofComponent
    let reader: SelfBodyProofReader
    let original: SelfBodyProofOriginalContinuation

    init() throws {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let epoch = SelfBodyProofEpoch(runtime)
        let construction = try SelfBodyProofBoundary(epoch: epoch)
        let reader = try epoch.reader(under: construction.context, identity: 10)
        let boundary = try construction.close(child: reader.node, identity: 1000)
        epoch.begin(sources: [boundary])
        epoch.installTree(boundary, under: runtime.root)
        _ = epoch.finish()
        self.runtime = runtime
        owner = construction.component
        self.reader = reader
        self.boundary = boundary
        original = try SelfBodyProofOriginalContinuation(reader.node, in: runtime)
        XCTAssertTrue(owner.receipt.hasAcceptedDeclaration)
        XCTAssertTrue(reader.component.receipt.hasAcceptedDeclaration)
        assertCurrent()
    }

    func body() throws -> SelfBodyProofEpoch { try SelfBodyProofEpoch(original) }

    func assertCurrent(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(owner.receipt.hasDeclaredComponent, file: file, line: line)
        XCTAssertTrue(reader.component.receipt.hasDeclaredComponent, file: file, line: line)
        XCTAssertTrue(boundary.isRetainedLazyListAttached(in: runtime), file: file, line: line)
        XCTAssertTrue(reader.node.parent === boundary, file: file, line: line)
        XCTAssertTrue(original.invokeIfAdmitted(), file: file, line: line)
    }
}

@MainActor
extension SelfBodyProofEpoch {
    /// Mirrors the geometry-property cut without publishing attachment or
    /// completion. Pin the old closure through the native fact publication.
    fileprivate func copyGeometryOnly(from source: ViewNode, to target: ViewNode) -> Bool {
        guard journal.preparePropertyCopy(from: source, to: target, keyPath: \ViewNode.geometryReaderBuild) else {
            return false
        }
        let previous = target.geometryReaderBuild
        target.geometryReaderBuild = source.geometryReaderBuild
        _ = journal.recordAcceptedProperty(from: source, to: target, keyPath: \ViewNode.geometryReaderBuild)
        withExtendedLifetime(previous) {}
        return true
    }
}
