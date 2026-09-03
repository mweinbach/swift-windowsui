import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI

/// A fresh reader's own body must use its actual accepted reader chain after
/// SELF has retired the original A contribution. No private proof is injected.
@MainActor
final class RetainedOwnedCandidateSelfChildBodyTests: XCTestCase {
    func testFreshReaderBodyMemberSurvivesPhysicalRemovalUntilItsOwnIndependentOmission() async throws {
        let fixture = try SelfChildBodyProofFixture()
        let epoch = try fixture.body()
        let context = try XCTUnwrap(epoch.context)
        let rebuilt = try epoch.reader(
            under: context, identity: 10, continuing: fixture.reader.component.receipt)
        XCTAssertTrue(rebuilt.context.token === context.token)
        let reader = try epoch.reader(under: rebuilt.context, identity: 20)
        let member = try epoch.openComponent(under: reader.context)
        let memberNode = selfChildBodyProofNode(30)
        try epoch.close(member, node: memberNode)
        reader.node.addChild(memberNode)
        rebuilt.node.addChild(reader.node)
        let expectedA = try XCTUnwrap(rebuilt.component.attribution.contribution(for: rebuilt.component.group))
        let expectedB = try XCTUnwrap(reader.component.attribution.contribution(for: reader.component.group))
        let expectedMember = try XCTUnwrap(member.attribution.contribution(for: member.group))
        XCTAssertFalse(reader.component.receipt.hasAcceptedDeclaration)
        XCTAssertFalse(member.receipt.hasAcceptedDeclaration)
        XCTAssertFalse(expectedA.isActive)
        XCTAssertFalse(expectedB.isActive)
        XCTAssertFalse(expectedMember.isActive)
        epoch.begin(sources: [rebuilt.node])
        XCTAssertTrue(epoch.journal.applyOwnedCandidateDeferredCatalog(at: fixture.reader.node))

        let result = ComponentHost.adopt(
            source: rebuilt.node, into: fixture.reader.node, lazyJournal: epoch.journal)
        XCTAssertTrue(result.completed)
        XCTAssertTrue(rebuilt.component.receipt.hasAcceptedDeclaration)
        XCTAssertTrue(rebuilt.component.receipt.owner === fixture.reader.component.receipt.owner)
        XCTAssertTrue(reader.component.receipt.hasAcceptedDeclaration)
        XCTAssertTrue(member.receipt.hasAcceptedDeclaration)
        XCTAssertTrue(member.receipt.slots.isEmpty)
        XCTAssertFalse(fixture.original.contribution.isActive)
        XCTAssertFalse(context.token.canConstruct)
        XCTAssertTrue(expectedA.isActive)
        XCTAssertTrue(expectedB.isActive)
        XCTAssertTrue(expectedMember.isActive)
        XCTAssertTrue(fixture.owner.receipt.hasDeclaredComponent)
        XCTAssertTrue(rebuilt.component.receipt.hasDeclaredComponent)
        XCTAssertTrue(reader.component.receipt.hasDeclaredComponent)
        XCTAssertTrue(member.receipt.hasDeclaredComponent)
        XCTAssertTrue(reader.node.parent === fixture.reader.node)
        XCTAssertTrue(memberNode.parent === reader.node)
        let currentA = try SelfChildBodyProofOriginalContinuation(fixture.reader.node, in: fixture.runtime)
        let currentB = try SelfChildBodyProofOriginalContinuation(reader.node, in: fixture.runtime)
        XCTAssertTrue(currentA.contribution === expectedA)
        XCTAssertTrue(currentB.contribution === expectedB)
        XCTAssertTrue(currentA.actual.target === fixture.original.actual.target)
        XCTAssertTrue(currentA.actual.attachment === fixture.original.actual.attachment)
        XCTAssertTrue(currentA.invokeIfAdmitted())
        XCTAssertTrue(currentB.invokeIfAdmitted())
        _ = epoch.finish()
        XCTAssertTrue(currentA.invokeIfAdmitted())
        XCTAssertTrue(currentB.invokeIfAdmitted())

        // Retire the leaf's physical contribution, leaving B installed. Its
        // zero-slot component must still be declared by B's accepted body.
        reader.node.setChildren([])
        XCTAssertNil(memberNode.parent)
        XCTAssertFalse(memberNode.isRetainedLazyListAttached(in: fixture.runtime))
        XCTAssertFalse(expectedMember.isActive)
        XCTAssertTrue(member.receipt.hasDeclaredComponent)
        XCTAssertTrue(fixture.owner.receipt.hasDeclaredComponent)
        XCTAssertTrue(rebuilt.component.receipt.hasDeclaredComponent)
        XCTAssertTrue(reader.component.receipt.hasDeclaredComponent)
        XCTAssertTrue(expectedA.isActive)
        XCTAssertTrue(expectedB.isActive)
        XCTAssertTrue(currentA.actual.isAttached)
        XCTAssertTrue(currentB.actual.isAttached)
        XCTAssertTrue(currentA.invokeIfAdmitted())
        XCTAssertTrue(currentB.invokeIfAdmitted())

        // This independently admitted B operation omits only B's body member;
        // it does not rebuild W/A or replace B's own descriptor.
        let omission = try SelfChildBodyProofEpoch(currentB)
        let omissionContext = try XCTUnwrap(omission.context)
        XCTAssertTrue(omissionContext.token !== reader.context.token)
        XCTAssertTrue(omissionContext.token.canConstruct)
        omission.begin(sources: [])
        XCTAssertTrue(omission.journal.applyOwnedCandidateDeferredCatalog(at: reader.node))
        XCTAssertFalse(member.receipt.hasDeclaredComponent)
        XCTAssertTrue(fixture.owner.receipt.hasDeclaredComponent)
        XCTAssertTrue(fixture.reader.component.receipt.hasDeclaredComponent)
        XCTAssertTrue(rebuilt.component.receipt.hasDeclaredComponent)
        XCTAssertTrue(reader.component.receipt.hasDeclaredComponent)
        XCTAssertTrue(expectedA.isActive)
        XCTAssertTrue(expectedB.isActive)
        XCTAssertTrue(currentA.actual.isAttached)
        XCTAssertTrue(currentB.actual.isAttached)
        XCTAssertTrue(currentA.invokeIfAdmitted())
        XCTAssertTrue(currentB.invokeIfAdmitted())
        _ = omission.finish()
        XCTAssertFalse(member.receipt.hasDeclaredComponent)
        XCTAssertTrue(currentA.invokeIfAdmitted())
        XCTAssertTrue(currentB.invokeIfAdmitted())

        fixture.runtime.root.setChildren([])
        XCTAssertFalse(fixture.owner.receipt.hasDeclaredComponent)
        XCTAssertFalse(fixture.reader.component.receipt.hasDeclaredComponent)
        XCTAssertFalse(rebuilt.component.receipt.hasDeclaredComponent)
        XCTAssertFalse(reader.component.receipt.hasDeclaredComponent)
        XCTAssertFalse(member.receipt.hasDeclaredComponent)
        XCTAssertFalse(expectedA.isActive)
        XCTAssertFalse(expectedB.isActive)
        XCTAssertFalse(currentA.actual.isAttached)
        XCTAssertFalse(currentB.actual.isAttached)
        XCTAssertFalse(currentA.invokeIfAdmitted())
        XCTAssertFalse(currentB.invokeIfAdmitted())
    }
}

@MainActor
private func selfChildBodyProofNode(_ identity: Int) -> ViewNode {
    let node = ViewNode()
    node.retainedViewIdentity = RetainedViewIdentity().appending(.slot(identity))
    return node
}

@MainActor
private struct SelfChildBodyProofComponent {
    let attribution: RetainedDescriptorComponentAttribution
    let receipt: RetainedOwnedComponentReceipt
    let group: RetainedDescriptorGroupID
}

@MainActor
private struct SelfChildBodyProofContext {
    let attribution: RetainedDescriptorComponentAttribution
    let token: RetainedOwnedCandidateConstruction
}

@MainActor
private struct SelfChildBodyProofReader {
    let node: ViewNode
    let component: SelfChildBodyProofComponent
    let context: SelfChildBodyProofContext
}

@MainActor
private final class SelfChildBodyProofOriginalContinuation {
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

    func lease() -> SelfChildBodyProofLease? {
        guard let scope = admittedScope(), let attribution = scope.registerOrdinaryComponent() else { return nil }
        return SelfChildBodyProofLease(scope: scope, attribution: attribution)
    }

    func invokeIfAdmitted(_ body: @MainActor () -> Void = {}) -> Bool {
        guard let lease = lease() else { return false }
        defer { lease.finish() }
        return lease.invokeIfAdmitted(body)
    }
}

@MainActor
private final class SelfChildBodyProofLease {
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
private final class SelfChildBodyProofEpoch {
    let runtime: RetainedViewRuntime
    let scope: RetainedLazyListDescriptorBuildScope
    let journal: RetainedLazyListAdoptionJournal
    let context: SelfChildBodyProofContext?

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

    init(_ original: SelfChildBodyProofOriginalContinuation) throws {
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
        let context = SelfChildBodyProofContext(
            attribution: attribution, token: try XCTUnwrap(token, "Expected the original accepted reader continuation"))
        runtime = original.runtime
        self.scope = scope
        self.journal = journal
        self.context = context
    }

    func openComponent(
        under parent: SelfChildBodyProofContext? = nil, kind: RetainedLazyListContributionKind = .observation,
        continuing: RetainedOwnedComponentReceipt? = nil
    ) throws -> SelfChildBodyProofComponent {
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
        return SelfChildBodyProofComponent(attribution: attribution, receipt: receipt, group: group)
    }

    func close(_ component: SelfChildBodyProofComponent, node: ViewNode) throws {
        XCTAssertTrue(component.attribution.recordSourceOutput(node, group: component.group))
        _ = try XCTUnwrap(component.attribution.closeGroup(component.group))
    }

    func reader(
        under parent: SelfChildBodyProofContext, identity: Int, continuing: RetainedOwnedComponentReceipt? = nil
    ) throws -> SelfChildBodyProofReader {
        let component = try openComponent(under: parent, kind: .deferredSubtree, continuing: continuing)
        let token = try XCTUnwrap(
            parent.token.deferredSegment(owner: component.receipt, attribution: component.attribution))
        let node = selfChildBodyProofNode(identity)
        node.geometryReaderBuild = { _, _ in [] }
        XCTAssertTrue(token.stageDeferredAnchor(on: node))
        try close(component, node: node)
        return SelfChildBodyProofReader(
            node: node, component: component,
            context: SelfChildBodyProofContext(attribution: component.attribution, token: token))
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
private final class SelfChildBodyProofBoundary {
    let epoch: SelfChildBodyProofEpoch
    let component: SelfChildBodyProofComponent
    let context: SelfChildBodyProofContext

    init(epoch: SelfChildBodyProofEpoch, under parent: SelfChildBodyProofContext? = nil) throws {
        let component = try epoch.openComponent(under: parent)
        let token = try XCTUnwrap(component.attribution.beginOwnedCandidateConstruction(owner: component.receipt))
        self.epoch = epoch
        self.component = component
        context = SelfChildBodyProofContext(attribution: component.attribution, token: token)
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
private final class SelfChildBodyProofFixture {
    let runtime: RetainedViewRuntime
    let boundary: ViewNode
    let owner: SelfChildBodyProofComponent
    let reader: SelfChildBodyProofReader
    let original: SelfChildBodyProofOriginalContinuation

    init() throws {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let epoch = SelfChildBodyProofEpoch(runtime)
        let construction = try SelfChildBodyProofBoundary(epoch: epoch)
        let reader = try epoch.reader(under: construction.context, identity: 10)
        let boundary = try construction.close(child: reader.node, identity: 1000)
        epoch.begin(sources: [boundary])
        epoch.installTree(boundary, under: runtime.root)
        _ = epoch.finish()
        self.runtime = runtime
        owner = construction.component
        self.reader = reader
        self.boundary = boundary
        original = try SelfChildBodyProofOriginalContinuation(reader.node, in: runtime)
        XCTAssertTrue(owner.receipt.hasAcceptedDeclaration)
        XCTAssertTrue(reader.component.receipt.hasAcceptedDeclaration)
        assertCurrent()
    }

    func body() throws -> SelfChildBodyProofEpoch { try SelfChildBodyProofEpoch(original) }

    func assertCurrent(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(owner.receipt.hasDeclaredComponent, file: file, line: line)
        XCTAssertTrue(reader.component.receipt.hasDeclaredComponent, file: file, line: line)
        XCTAssertTrue(boundary.isRetainedLazyListAttached(in: runtime), file: file, line: line)
        XCTAssertTrue(reader.node.parent === boundary, file: file, line: line)
        XCTAssertTrue(original.invokeIfAdmitted(), file: file, line: line)
    }
}

@MainActor
extension SelfChildBodyProofEpoch {
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
