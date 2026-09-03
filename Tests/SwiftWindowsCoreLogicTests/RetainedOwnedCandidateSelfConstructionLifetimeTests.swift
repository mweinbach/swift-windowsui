import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI

/// The only value returned from the isolated native lifecycle is a weak box.
/// The test cannot keep its source, registration, receipt, node or scope alive.
@MainActor
final class RetainedOwnedCandidateSelfConstructionLifetimeTests: XCTestCase {
    func testAcceptedSelfConstructionReleasesAfterFinishAndWholeBoundaryWithdrawal() async throws {
        let reference = try selfCycleProofReleasedConstruction()
        XCTAssertNil(reference.value, "Finished SELF construction must not retain itself through its registration")
    }
}

@MainActor
private final class SelfCycleProofWeakConstruction {
    weak var value: RetainedOwnedCandidateConstruction?

    init(_ value: RetainedOwnedCandidateConstruction) { self.value = value }
}

@inline(never)
@MainActor
private func selfCycleProofReleasedConstruction() throws -> SelfCycleProofWeakConstruction {
    let fixture = try SelfCycleProofFixture()
    let epoch = try fixture.body()
    let context = try XCTUnwrap(epoch.context)
    let reference = SelfCycleProofWeakConstruction(context.token)
    XCTAssertTrue(context.token.canConstruct)
    let rebuilt = try epoch.reader(
        under: context, identity: 10, continuing: fixture.reader.component.receipt)
    XCTAssertTrue(rebuilt.context.token === context.token)
    XCTAssertTrue(reference.value === context.token)
    XCTAssertFalse(rebuilt.component.receipt === fixture.reader.component.receipt)
    XCTAssertTrue(rebuilt.component.receipt.owner === fixture.reader.component.receipt.owner)
    XCTAssertTrue(rebuilt.component.receipt.slots.isEmpty)
    XCTAssertFalse(rebuilt.component.receipt.hasAcceptedDeclaration)
    let expected = try XCTUnwrap(rebuilt.component.attribution.contribution(for: rebuilt.component.group))
    XCTAssertFalse(expected.isActive)
    epoch.begin(sources: [rebuilt.node])
    XCTAssertTrue(epoch.journal.applyOwnedCandidateDeferredCatalog(at: fixture.reader.node))

    let result = ComponentHost.adopt(
        source: rebuilt.node, into: fixture.reader.node, lazyJournal: epoch.journal)
    XCTAssertTrue(result.completed)
    XCTAssertTrue(rebuilt.component.receipt.hasAcceptedDeclaration)
    XCTAssertTrue(expected.isActive)
    XCTAssertFalse(fixture.original.contribution.isActive)
    let current = try SelfCycleProofOriginalContinuation(fixture.reader.node, in: fixture.runtime)
    XCTAssertTrue(current.contribution === expected)
    XCTAssertTrue(current.actual.target === fixture.original.actual.target)
    XCTAssertTrue(current.actual.attachment === fixture.original.actual.attachment)
    XCTAssertTrue(current.invokeIfAdmitted())
    _ = epoch.finish()
    XCTAssertFalse(context.token.canConstruct)
    XCTAssertTrue(expected.isActive)
    XCTAssertTrue(current.invokeIfAdmitted())

    // Finish first, then withdraw the entire actual namespace boundary. Leave
    // every source/receipt/scope/runtime local inside this non-inlined helper.
    fixture.runtime.root.setChildren([])
    XCTAssertTrue(fixture.runtime.root.children.isEmpty)
    XCTAssertNil(fixture.boundary.parent)
    XCTAssertFalse(fixture.owner.receipt.hasDeclaredComponent)
    XCTAssertFalse(fixture.reader.component.receipt.hasDeclaredComponent)
    XCTAssertFalse(rebuilt.component.receipt.hasDeclaredComponent)
    XCTAssertFalse(expected.isActive)
    XCTAssertFalse(fixture.original.actual.isAttached)
    XCTAssertFalse(current.actual.isAttached)
    XCTAssertFalse(current.invokeIfAdmitted())
    return reference
}

@MainActor
private func selfCycleProofNode(_ identity: Int) -> ViewNode {
    let node = ViewNode()
    node.retainedViewIdentity = RetainedViewIdentity().appending(.slot(identity))
    return node
}

@MainActor
private struct SelfCycleProofComponent {
    let attribution: RetainedDescriptorComponentAttribution
    let receipt: RetainedOwnedComponentReceipt
    let group: RetainedDescriptorGroupID
}

@MainActor
private struct SelfCycleProofContext {
    let attribution: RetainedDescriptorComponentAttribution
    let token: RetainedOwnedCandidateConstruction
}

@MainActor
private struct SelfCycleProofReader {
    let node: ViewNode
    let component: SelfCycleProofComponent
    let context: SelfCycleProofContext
}

@MainActor
private final class SelfCycleProofOriginalContinuation {
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

    func lease() -> SelfCycleProofLease? {
        guard let scope = admittedScope(), let attribution = scope.registerOrdinaryComponent() else { return nil }
        return SelfCycleProofLease(scope: scope, attribution: attribution)
    }

    func invokeIfAdmitted(_ body: @MainActor () -> Void = {}) -> Bool {
        guard let lease = lease() else { return false }
        defer { lease.finish() }
        return lease.invokeIfAdmitted(body)
    }
}

@MainActor
private final class SelfCycleProofLease {
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
private final class SelfCycleProofEpoch {
    let runtime: RetainedViewRuntime
    let scope: RetainedLazyListDescriptorBuildScope
    let journal: RetainedLazyListAdoptionJournal
    let context: SelfCycleProofContext?

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

    init(_ original: SelfCycleProofOriginalContinuation) throws {
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
        let context = SelfCycleProofContext(
            attribution: attribution, token: try XCTUnwrap(token, "Expected the original accepted reader continuation"))
        runtime = original.runtime
        self.scope = scope
        self.journal = journal
        self.context = context
    }

    func openComponent(
        under parent: SelfCycleProofContext? = nil, kind: RetainedLazyListContributionKind = .observation,
        continuing: RetainedOwnedComponentReceipt? = nil
    ) throws -> SelfCycleProofComponent {
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
        return SelfCycleProofComponent(attribution: attribution, receipt: receipt, group: group)
    }

    func close(_ component: SelfCycleProofComponent, node: ViewNode) throws {
        XCTAssertTrue(component.attribution.recordSourceOutput(node, group: component.group))
        _ = try XCTUnwrap(component.attribution.closeGroup(component.group))
    }

    func reader(
        under parent: SelfCycleProofContext, identity: Int, continuing: RetainedOwnedComponentReceipt? = nil
    ) throws -> SelfCycleProofReader {
        let component = try openComponent(under: parent, kind: .deferredSubtree, continuing: continuing)
        let token = try XCTUnwrap(
            parent.token.deferredSegment(owner: component.receipt, attribution: component.attribution))
        let node = selfCycleProofNode(identity)
        node.geometryReaderBuild = { _, _ in [] }
        XCTAssertTrue(token.stageDeferredAnchor(on: node))
        try close(component, node: node)
        return SelfCycleProofReader(
            node: node, component: component,
            context: SelfCycleProofContext(attribution: component.attribution, token: token))
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
private final class SelfCycleProofBoundary {
    let epoch: SelfCycleProofEpoch
    let component: SelfCycleProofComponent
    let context: SelfCycleProofContext

    init(epoch: SelfCycleProofEpoch, under parent: SelfCycleProofContext? = nil) throws {
        let component = try epoch.openComponent(under: parent)
        let token = try XCTUnwrap(component.attribution.beginOwnedCandidateConstruction(owner: component.receipt))
        self.epoch = epoch
        self.component = component
        context = SelfCycleProofContext(attribution: component.attribution, token: token)
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
private final class SelfCycleProofFixture {
    let runtime: RetainedViewRuntime
    let boundary: ViewNode
    let owner: SelfCycleProofComponent
    let reader: SelfCycleProofReader
    let original: SelfCycleProofOriginalContinuation

    init() throws {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let epoch = SelfCycleProofEpoch(runtime)
        let construction = try SelfCycleProofBoundary(epoch: epoch)
        let reader = try epoch.reader(under: construction.context, identity: 10)
        let boundary = try construction.close(child: reader.node, identity: 1000)
        epoch.begin(sources: [boundary])
        epoch.installTree(boundary, under: runtime.root)
        _ = epoch.finish()
        self.runtime = runtime
        owner = construction.component
        self.reader = reader
        self.boundary = boundary
        original = try SelfCycleProofOriginalContinuation(reader.node, in: runtime)
        XCTAssertTrue(owner.receipt.hasAcceptedDeclaration)
        XCTAssertTrue(reader.component.receipt.hasAcceptedDeclaration)
        assertCurrent()
    }

    func body() throws -> SelfCycleProofEpoch { try SelfCycleProofEpoch(original) }

    func assertCurrent(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(owner.receipt.hasDeclaredComponent, file: file, line: line)
        XCTAssertTrue(reader.component.receipt.hasDeclaredComponent, file: file, line: line)
        XCTAssertTrue(boundary.isRetainedLazyListAttached(in: runtime), file: file, line: line)
        XCTAssertTrue(reader.node.parent === boundary, file: file, line: line)
        XCTAssertTrue(original.invokeIfAdmitted(), file: file, line: line)
    }
}

@MainActor
extension SelfCycleProofEpoch {
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
