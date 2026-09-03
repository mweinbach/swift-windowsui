import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI

/// SELF replaces the descriptor of an already accepted reader on its original
/// actual node. No test installs a namespace field, reference, or private proof.
@MainActor
final class RetainedOwnedCandidateSelfReconstructionTests: XCTestCase {
    func testTwoIndependentSelfReconstructionsContinueTheSameAcceptedOwner() async throws {
        let fixture = try SelfProofFixture()
        var original = fixture.original
        var previous = fixture.reader.component.receipt
        var receipts = [previous]
        var tokens: [RetainedOwnedCandidateConstruction] = []

        for _ in 0..<2 {
            let epoch = try SelfProofEpoch(original)
            let context = try XCTUnwrap(epoch.context)
            let rebuilt = try epoch.reader(under: context, identity: 10, continuing: previous)
            XCTAssertTrue(rebuilt.context.token === context.token)
            XCTAssertTrue(tokens.allSatisfy { $0 !== context.token })
            tokens.append(context.token)
            XCTAssertFalse(rebuilt.component.receipt === previous)
            XCTAssertTrue(rebuilt.component.receipt.owner === previous.owner)
            XCTAssertTrue(rebuilt.component.receipt.slots.isEmpty)
            XCTAssertTrue(rebuilt.component.receipt.hasDeclaredComponent)
            XCTAssertFalse(rebuilt.component.receipt.hasAcceptedDeclaration)
            let expected = try XCTUnwrap(
                rebuilt.component.attribution.contribution(for: rebuilt.component.group))
            XCTAssertFalse(expected.isActive)
            XCTAssertFalse(expected === original.contribution)
            epoch.begin(sources: [rebuilt.node])

            // The reader's own accepted catalog write may precede replacement
            // of its descriptor. Only this operation's exact successor counts.
            XCTAssertTrue(epoch.journal.applyOwnedCandidateDeferredCatalog(at: fixture.reader.node))
            let result = ComponentHost.adopt(
                source: rebuilt.node, into: fixture.reader.node, lazyJournal: epoch.journal)

            XCTAssertTrue(result.completed)
            XCTAssertTrue(rebuilt.component.receipt.hasAcceptedDeclaration)
            XCTAssertTrue(expected.isActive)
            XCTAssertFalse(original.contribution.isActive)
            XCTAssertTrue(original.actual.isAttached)
            XCTAssertFalse(original.invokeIfAdmitted())
            let current = try SelfProofOriginalContinuation(fixture.reader.node, in: fixture.runtime)
            XCTAssertTrue(current.contribution === expected)
            XCTAssertTrue(current.actual.target === original.actual.target)
            XCTAssertTrue(current.actual.attachment === original.actual.attachment)
            XCTAssertTrue(current.node === fixture.reader.node)
            XCTAssertTrue(current.invokeIfAdmitted())
            receipts.append(rebuilt.component.receipt)
            for receipt in receipts {
                XCTAssertTrue(receipt.owner === fixture.reader.component.receipt.owner)
                XCTAssertTrue(receipt.hasDeclaredComponent)
            }
            XCTAssertTrue(fixture.owner.receipt.hasDeclaredComponent)
            XCTAssertTrue(fixture.reader.node.parent === fixture.boundary)
            _ = epoch.finish()
            XCTAssertTrue(current.invokeIfAdmitted())
            original = current
            previous = rebuilt.component.receipt
        }

        // The receipt chain shares native liveness, rather than keeping an
        // independent declaration alive after the last real boundary departure.
        fixture.runtime.root.setChildren([])
        XCTAssertFalse(fixture.owner.receipt.hasDeclaredComponent)
        for receipt in receipts { XCTAssertFalse(receipt.hasDeclaredComponent) }
        XCTAssertFalse(original.actual.isAttached)
        XCTAssertFalse(original.invokeIfAdmitted())
    }

    func testNormalFactAloneAndWrongGroupCannotAdmitSelfContinuation() async throws {
        do {
            let fixture = try SelfProofFixture()
            let epoch = try fixture.body()
            let context = try XCTUnwrap(epoch.context)
            let rebuilt = try epoch.reader(
                under: context, identity: 10, continuing: fixture.reader.component.receipt)
            XCTAssertTrue(rebuilt.context.token === context.token)
            let expected = try XCTUnwrap(
                rebuilt.component.attribution.contribution(for: rebuilt.component.group))
            epoch.begin(sources: [rebuilt.node])
            XCTAssertTrue(epoch.journal.applyOwnedCandidateDeferredCatalog(at: fixture.reader.node))

            // This is the prepared native property write, not group completion.
            // It accepts the normal owner and retires the original descriptor,
            // but supplies neither the new attachment nor completion fact.
            XCTAssertTrue(epoch.journal.applyOwnedCandidateCatalog(from: rebuilt.node, to: fixture.reader.node))
            XCTAssertTrue(epoch.copyGeometryOnly(from: rebuilt.node, to: fixture.reader.node))
            XCTAssertTrue(rebuilt.component.receipt.hasAcceptedDeclaration)
            XCTAssertTrue(rebuilt.component.receipt.hasDeclaredComponent)
            XCTAssertFalse(expected.isActive)
            XCTAssertFalse(fixture.original.contribution.isActive)
            XCTAssertTrue(fixture.original.actual.isAttached)
            XCTAssertNil(fixture.reader.node.retainedLazyListActivityStorage?.descriptorDeferredSubtreeAnchor)
            XCTAssertNil(rebuilt.node.retainedLazyListActivityStorage?.descriptorDeferredSubtreeAnchor)
            XCTAssertFalse(fixture.original.invokeIfAdmitted())
            XCTAssertTrue(fixture.reader.component.receipt.hasDeclaredComponent)
            XCTAssertTrue(fixture.owner.receipt.hasDeclaredComponent)
            XCTAssertTrue(fixture.reader.node.parent === fixture.boundary)
            _ = epoch.finish(completed: false)
            XCTAssertFalse(expected.isActive)
            XCTAssertNil(fixture.reader.node.retainedLazyListActivityStorage?.descriptorDeferredSubtreeAnchor)
        }

        do {
            let fixture = try SelfProofFixture()
            let epoch = try fixture.body()
            let context = try XCTUnwrap(epoch.context)
            let component = try epoch.openComponent(
                under: context, kind: .observation, continuing: fixture.reader.component.receipt)
            let source = selfProofNode(10)
            source.geometryReaderBuild = { _, _ in [] }

            // The exact deferred group is missing. Refusal may occur before
            // preparation; do not require a made-up internal rejection step.
            let rebound = context.token.deferredSegment(owner: component.receipt, attribution: component.attribution)
            if let rebound { XCTAssertTrue(rebound === context.token) }
            let staged = rebound?.stageDeferredAnchor(on: source) ?? false
            let recorded = component.attribution.recordSourceOutput(source, group: component.group)
            let closed = component.attribution.closeGroup(component.group) != nil
            let registered = recorded && closed && epoch.journal.registerSourceDescriptors(in: [source])
            let began = registered && epoch.journal.beginOrdinaryAdoption()
            XCTAssertFalse(
                staged && registered && began,
                "A SELF source with only an observation group must not complete SELF preparation")
            XCTAssertFalse(component.receipt.hasAcceptedDeclaration)
            XCTAssertFalse(component.attribution.contribution(for: component.group)?.isActive == true)
            XCTAssertNil(source.retainedLazyListActivityStorage?.descriptorDeferredSubtreeAnchor)
            XCTAssertTrue(
                fixture.reader.node.retainedLazyListActivityStorage?.descriptorDeferredSubtreeAnchor?.contribution
                    === fixture.original.contribution)
            XCTAssertTrue(fixture.original.contribution.isActive)
            XCTAssertTrue(fixture.original.invokeIfAdmitted())
            XCTAssertTrue(fixture.reader.component.receipt.hasDeclaredComponent)
            XCTAssertTrue(fixture.owner.receipt.hasDeclaredComponent)
            _ = epoch.finish(completed: false)
        }
    }

    func testForeignOriginalRetirementDeniesAnOlderPreparedSelfOperation() async throws {
        let fixture = try SelfProofFixture()
        let older = try fixture.body()
        let context = try XCTUnwrap(older.context)
        let rebuilt = try older.reader(
            under: context, identity: 10, continuing: fixture.reader.component.receipt)
        XCTAssertTrue(rebuilt.context.token === context.token)
        older.begin(sources: [rebuilt.node])
        XCTAssertTrue(older.scope.canPublishDescriptors)
        XCTAssertTrue(older.journal.canContinueAdoption)
        XCTAssertTrue(fixture.original.contribution.isActive)

        // A separate ordinary native publication removes the original deferred
        // payload. It registers no owned declaration or candidate continuation.
        let foreign = SelfProofEpoch(fixture.runtime)
        let attribution = try XCTUnwrap(foreign.scope.registerOrdinaryComponent())
        let group = try XCTUnwrap(attribution.registerGroup(kind: .observation))
        let source = selfProofNode(10)
        source.geometryReaderBuild = { _, _ in [] }
        XCTAssertTrue(attribution.recordSourceOutput(source, group: group))
        _ = try XCTUnwrap(attribution.closeGroup(group))
        foreign.begin(sources: [source])
        XCTAssertTrue(foreign.copyGeometryOnly(from: source, to: fixture.reader.node))
        _ = foreign.finish(completed: false)

        XCTAssertFalse(fixture.original.contribution.isActive)
        XCTAssertTrue(fixture.original.actual.isAttached)
        XCTAssertTrue(fixture.reader.node.parent === fixture.boundary)
        XCTAssertTrue(fixture.reader.node.isRetainedLazyListAttached(in: fixture.runtime))
        XCTAssertTrue(fixture.reader.component.receipt.hasDeclaredComponent)
        XCTAssertTrue(fixture.owner.receipt.hasDeclaredComponent)
        XCTAssertFalse(older.scope.canPublishDescriptors)
        XCTAssertFalse(older.journal.canContinueAdoption)

        // The real ordinary admission guard stops this stale operation. Do not
        // force a stale pending property through recordAcceptedProperty merely
        // to reach the later generic acceptedOriginalRetirements ID-set path.
        let result = ComponentHost.adopt(
            source: rebuilt.node, into: fixture.reader.node, lazyJournal: older.journal)
        XCTAssertFalse(result.completed)
        XCTAssertFalse(rebuilt.component.receipt.hasAcceptedDeclaration)
        XCTAssertNil(fixture.reader.node.retainedLazyListActivityStorage?.descriptorDeferredSubtreeAnchor)
        XCTAssertFalse(fixture.original.invokeIfAdmitted())
        _ = older.finish(completed: false)
        XCTAssertTrue(fixture.reader.component.receipt.hasDeclaredComponent)
        XCTAssertTrue(fixture.owner.receipt.hasDeclaredComponent)
        XCTAssertTrue(fixture.original.actual.isAttached)
    }

    func testForeignBodyGrowthDeniesOldSelfWhileOriginalReaderAndNewMemberStayCurrent() async throws {
        let fixture = try SelfProofFixture()
        let older = try fixture.body()
        let context = try XCTUnwrap(older.context)
        let rebuilt = try older.reader(
            under: context, identity: 10, continuing: fixture.reader.component.receipt)
        XCTAssertTrue(rebuilt.context.token === context.token)
        older.begin(sources: [rebuilt.node])

        // This independently admitted A-body writer grows the selected segment.
        // A's original normal owner, descriptor and physical node are unchanged.
        let newer = try fixture.body()
        let leaf = try newer.openComponent(under: try XCTUnwrap(newer.context))
        let leafNode = selfProofNode(20)
        try newer.close(leaf, node: leafNode)
        newer.begin(sources: [leafNode])
        XCTAssertTrue(newer.journal.applyOwnedCandidateDeferredCatalog(at: fixture.reader.node))
        newer.installTree(leafNode, under: fixture.reader.node)
        _ = newer.finish()
        XCTAssertTrue(leaf.receipt.hasAcceptedDeclaration)
        XCTAssertTrue(leaf.receipt.slots.isEmpty)

        fixture.reader.node.setChildren([])
        XCTAssertNil(leafNode.parent)
        XCTAssertFalse(leafNode.isRetainedLazyListAttached(in: fixture.runtime))
        XCTAssertTrue(leaf.receipt.hasDeclaredComponent)
        XCTAssertTrue(fixture.original.contribution.isActive)
        XCTAssertTrue(fixture.original.actual.isAttached)
        XCTAssertTrue(fixture.reader.component.receipt.hasDeclaredComponent)
        XCTAssertTrue(fixture.owner.receipt.hasDeclaredComponent)
        XCTAssertTrue(older.scope.canPublishDescriptors)
        XCTAssertTrue(older.journal.canContinueAdoption)
        let current = try SelfProofOriginalContinuation(fixture.reader.node, in: fixture.runtime)
        XCTAssertTrue(current.contribution === fixture.original.contribution)
        XCTAssertTrue(current.invokeIfAdmitted())

        // Ordinary permission still holds. The older original namespace
        // segment observation must independently refuse this SELF replacement.
        let result = ComponentHost.adopt(
            source: rebuilt.node, into: fixture.reader.node, lazyJournal: older.journal)
        XCTAssertFalse(result.completed)
        XCTAssertFalse(rebuilt.component.receipt.hasAcceptedDeclaration)
        XCTAssertTrue(leaf.receipt.hasDeclaredComponent)
        XCTAssertTrue(fixture.original.contribution.isActive)
        XCTAssertTrue(fixture.original.actual.isAttached)
        XCTAssertTrue(current.invokeIfAdmitted())
        _ = older.finish(completed: false)
        XCTAssertTrue(leaf.receipt.hasDeclaredComponent)
        XCTAssertTrue(fixture.reader.component.receipt.hasDeclaredComponent)
        XCTAssertTrue(fixture.owner.receipt.hasDeclaredComponent)
        XCTAssertTrue(current.invokeIfAdmitted())
    }
}

@MainActor
private func selfProofNode(_ identity: Int) -> ViewNode {
    let node = ViewNode()
    node.retainedViewIdentity = RetainedViewIdentity().appending(.slot(identity))
    return node
}

@MainActor
private struct SelfProofComponent {
    let attribution: RetainedDescriptorComponentAttribution
    let receipt: RetainedOwnedComponentReceipt
    let group: RetainedDescriptorGroupID
}

@MainActor
private struct SelfProofContext {
    let attribution: RetainedDescriptorComponentAttribution
    let token: RetainedOwnedCandidateConstruction
}

@MainActor
private struct SelfProofReader {
    let node: ViewNode
    let component: SelfProofComponent
    let context: SelfProofContext
}

@MainActor
private final class SelfProofOriginalContinuation {
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

    func lease() -> SelfProofLease? {
        guard let scope = admittedScope(), let attribution = scope.registerOrdinaryComponent() else { return nil }
        return SelfProofLease(scope: scope, attribution: attribution)
    }

    func invokeIfAdmitted(_ body: @MainActor () -> Void = {}) -> Bool {
        guard let lease = lease() else { return false }
        defer { lease.finish() }
        return lease.invokeIfAdmitted(body)
    }
}

@MainActor
private final class SelfProofLease {
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
private final class SelfProofEpoch {
    let runtime: RetainedViewRuntime
    let scope: RetainedLazyListDescriptorBuildScope
    let journal: RetainedLazyListAdoptionJournal
    let context: SelfProofContext?

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

    init(_ original: SelfProofOriginalContinuation) throws {
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
        let context = SelfProofContext(
            attribution: attribution, token: try XCTUnwrap(token, "Expected the original accepted reader continuation"))
        runtime = original.runtime
        self.scope = scope
        self.journal = journal
        self.context = context
    }

    func openComponent(
        under parent: SelfProofContext? = nil, kind: RetainedLazyListContributionKind = .observation,
        continuing: RetainedOwnedComponentReceipt? = nil
    ) throws -> SelfProofComponent {
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
        return SelfProofComponent(attribution: attribution, receipt: receipt, group: group)
    }

    func close(_ component: SelfProofComponent, node: ViewNode) throws {
        XCTAssertTrue(component.attribution.recordSourceOutput(node, group: component.group))
        _ = try XCTUnwrap(component.attribution.closeGroup(component.group))
    }

    func reader(
        under parent: SelfProofContext, identity: Int, continuing: RetainedOwnedComponentReceipt? = nil
    ) throws -> SelfProofReader {
        let component = try openComponent(under: parent, kind: .deferredSubtree, continuing: continuing)
        let token = try XCTUnwrap(
            parent.token.deferredSegment(owner: component.receipt, attribution: component.attribution))
        let node = selfProofNode(identity)
        node.geometryReaderBuild = { _, _ in [] }
        XCTAssertTrue(token.stageDeferredAnchor(on: node))
        try close(component, node: node)
        return SelfProofReader(
            node: node, component: component,
            context: SelfProofContext(attribution: component.attribution, token: token))
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
private final class SelfProofBoundary {
    let epoch: SelfProofEpoch
    let component: SelfProofComponent
    let context: SelfProofContext

    init(epoch: SelfProofEpoch, under parent: SelfProofContext? = nil) throws {
        let component = try epoch.openComponent(under: parent)
        let token = try XCTUnwrap(component.attribution.beginOwnedCandidateConstruction(owner: component.receipt))
        self.epoch = epoch
        self.component = component
        context = SelfProofContext(attribution: component.attribution, token: token)
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
private final class SelfProofFixture {
    let runtime: RetainedViewRuntime
    let boundary: ViewNode
    let owner: SelfProofComponent
    let reader: SelfProofReader
    let original: SelfProofOriginalContinuation

    init() throws {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let epoch = SelfProofEpoch(runtime)
        let construction = try SelfProofBoundary(epoch: epoch)
        let reader = try epoch.reader(under: construction.context, identity: 10)
        let boundary = try construction.close(child: reader.node, identity: 1000)
        epoch.begin(sources: [boundary])
        epoch.installTree(boundary, under: runtime.root)
        _ = epoch.finish()
        self.runtime = runtime
        owner = construction.component
        self.reader = reader
        self.boundary = boundary
        original = try SelfProofOriginalContinuation(reader.node, in: runtime)
        XCTAssertTrue(owner.receipt.hasAcceptedDeclaration)
        XCTAssertTrue(reader.component.receipt.hasAcceptedDeclaration)
        assertCurrent()
    }

    func body() throws -> SelfProofEpoch { try SelfProofEpoch(original) }

    func assertCurrent(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(owner.receipt.hasDeclaredComponent, file: file, line: line)
        XCTAssertTrue(reader.component.receipt.hasDeclaredComponent, file: file, line: line)
        XCTAssertTrue(boundary.isRetainedLazyListAttached(in: runtime), file: file, line: line)
        XCTAssertTrue(reader.node.parent === boundary, file: file, line: line)
        XCTAssertTrue(original.invokeIfAdmitted(), file: file, line: line)
    }
}

@MainActor
extension SelfProofEpoch {
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
