import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI

@MainActor
final class RetainedOwnedCandidateReaderCustodyRetirementTests: XCTestCase {
    func testContinuedReaderReferenceReleasesOriginalRecordAfterFinalWithdrawal() async throws {
        let probe = try exerciseReaderCustodyAndWithdrawal()
        XCTAssertNil(probe.owner, "The original accepted-reader record must not retain its native owner")
    }
}

/// Keep every receipt, source, anchor, epoch, node and runtime inside this call.
/// Only the weak native ID observation escapes; no facade registry is involved.
@MainActor
@inline(never)
private func exerciseReaderCustodyAndWithdrawal() throws -> ReaderCustodyWeakOwner {
    let runtime = RetainedViewRuntime(root: ViewNode())
    let initial = ReaderCustodyEpoch(runtime)
    let outer = try ReaderCustodyBoundary(epoch: initial)
    let inner = try ReaderCustodyBoundary(epoch: initial, under: outer)
    let reader = try initial.open(under: inner, kind: .deferredSubtree)
    let segment = try XCTUnwrap(
        inner.token.deferredSegment(owner: reader.receipt, attribution: reader.attribution))
    let readerNode = readerCustodyNode(10)
    readerNode.geometryReaderBuild = { _, _ in [] }
    XCTAssertTrue(segment.stageDeferredAnchor(on: readerNode))
    try initial.close(reader, nodes: [readerNode])
    let innerNode = try inner.close(child: readerNode, identity: 2000)
    let outerNode = try outer.close(child: innerNode, identity: 1000)
    initial.begin(source: outerNode)
    for node in [outerNode, innerNode, readerNode] {
        XCTAssertTrue(initial.journal.prepareInsertedNode(from: node))
    }
    runtime.root.addChild(outerNode)
    for node in [outerNode, innerNode, readerNode] {
        XCTAssertTrue(node.isRetainedLazyListAttached(in: runtime))
        _ = initial.journal.recordAcceptedInsertedNode(on: node)
        _ = initial.journal.recordCompletedNode(from: node, to: node)
    }
    initial.finish(completed: true)

    let original = try XCTUnwrap(readerNode.retainedLazyListActivityStorage?.descriptorDeferredSubtreeAnchor)
    XCTAssertTrue(original.actual.node === readerNode)
    XCTAssertTrue(original.actual.isAttached)
    XCTAssertTrue(original.contribution.isActive)
    XCTAssertTrue(readerNode.parent === innerNode)
    XCTAssertTrue(innerNode.parent === outerNode)
    XCTAssertTrue(outerNode.parent === runtime.root)
    XCTAssertTrue(reader.receipt.hasAcceptedDeclaration)
    XCTAssertTrue(reader.receipt.hasDeclaredComponent)
    XCTAssertTrue(reader.receipt.slots.isEmpty)
    // This requires the actual accepted reader record, not just a declaration.
    XCTAssertTrue(
        readerCustodyContinuationIsAdmitted(
            runtime: runtime, contribution: original.contribution, actual: original.actual))
    let probe = ReaderCustodyWeakOwner(reader.receipt.owner)

    let replacement = ReaderCustodyEpoch(runtime)
    let nextOuter = try ReaderCustodyBoundary(epoch: replacement, continuing: outer.owner.receipt)
    let nextInner = try ReaderCustodyBoundary(
        epoch: replacement, continuing: inner.owner.receipt, under: nextOuter)
    let retainedReader = try replacement.open(
        under: nextInner, continuing: reader.receipt, declarationOnly: true)
    try replacement.close(retainedReader, nodes: [])
    let selectedNode = readerCustodyNode(11)
    let selected = try replacement.open(under: nextInner)
    try replacement.close(selected, nodes: [selectedNode])
    let nextInnerNode = try nextInner.close(child: selectedNode, identity: 2001)
    let source = try nextOuter.close(child: nextInnerNode, identity: 1000)
    replacement.begin(source: source)
    let catalog = try XCTUnwrap(
        replacement.journal.prepareOwnedCandidateCatalog(from: source, to: outerNode))
    XCTAssertTrue(replacement.journal.publishOwnedCandidateCatalog(catalog))

    // Publish only W's catalog. Its prepared I is never inserted. The native
    // ordinary O cut for the exact original two-node cohort transfers A's
    // existing normal reference to W before withdrawing I's field.
    let innerDeparture = replacement.journal.recordOrdinaryPhysicalDeparture(
        of: innerNode, cause: .acceptedReplacement)
    let readerDeparture = replacement.journal.recordOrdinaryPhysicalDeparture(
        of: readerNode, cause: .acceptedReplacement)
    outerNode.removeChild(innerNode)
    if let innerDeparture { replacement.journal.finishOrdinaryOwnedDeparture(innerDeparture) }
    if let readerDeparture { replacement.journal.finishOrdinaryOwnedDeparture(readerDeparture) }
    replacement.finish(completed: false)

    XCTAssertTrue(outerNode.children.isEmpty)
    XCTAssertTrue(outerNode.parent === runtime.root)
    XCTAssertTrue(outerNode.isRetainedLazyListAttached(in: runtime))
    XCTAssertNil(innerNode.parent)
    XCTAssertNil(innerNode.retainedLazyListRuntime)
    XCTAssertTrue(readerNode.parent === innerNode)
    XCTAssertNil(readerNode.retainedLazyListRuntime)
    XCTAssertNil(source.parent)
    XCTAssertNil(nextInnerNode.retainedLazyListRuntime)
    XCTAssertFalse(nextInner.owner.receipt.hasAcceptedDeclaration)
    XCTAssertFalse(selected.receipt.hasAcceptedDeclaration)
    XCTAssertTrue(reader.receipt.hasDeclaredComponent, "Actual custody must survive the finished departure epoch")
    XCTAssertFalse(original.actual.isAttached)
    XCTAssertFalse(
        readerCustodyContinuationIsAdmitted(
            runtime: runtime, contribution: original.contribution, actual: original.actual))

    // This is the continued reference's true final withdrawal, not proof-only
    // rotation. This removal publishes no replacement or accepted new reader.
    runtime.root.removeChild(outerNode)
    XCTAssertTrue(runtime.root.children.isEmpty)
    XCTAssertNil(outerNode.parent)
    XCTAssertNil(outerNode.retainedLazyListRuntime)
    XCTAssertFalse(reader.receipt.hasDeclaredComponent)
    return probe
}

@MainActor
private final class ReaderCustodyWeakOwner {
    weak var owner: RetainedOwnedComponentID?

    init(_ owner: RetainedOwnedComponentID) { self.owner = owner }
}

@MainActor
private struct ReaderCustodyComponent {
    let attribution: RetainedDescriptorComponentAttribution
    let receipt: RetainedOwnedComponentReceipt
    let group: RetainedDescriptorGroupID
}

@MainActor
private final class ReaderCustodyEpoch {
    let scope: RetainedLazyListDescriptorBuildScope
    let journal: RetainedLazyListAdoptionJournal

    init(_ runtime: RetainedViewRuntime) {
        scope = RetainedLazyListDescriptorBuildScope(
            origin: .componentHostRoot, hostLifetime: runtime.lazyListLogicalHostLifetime,
            ownerLifetime: runtime.root.lazyListActivityStorage().descriptorOwnerLifetime)
        journal = RetainedLazyListAdoptionJournal(descriptorScope: scope, transaction: RetainedBuildTransaction())
        XCTAssertTrue(journal.seedOwnedCandidateOrigins(at: runtime.root))
        journal.seedExistingContributions(from: runtime.root.children)
    }

    func open(
        under boundary: ReaderCustodyBoundary? = nil,
        kind: RetainedLazyListContributionKind = .observation,
        continuing: RetainedOwnedComponentReceipt? = nil, declarationOnly: Bool = false
    ) throws -> ReaderCustodyComponent {
        let attribution: RetainedDescriptorComponentAttribution
        if let boundary {
            attribution = try XCTUnwrap(boundary.owner.attribution.registerChildComponent())
        } else {
            attribution = try XCTUnwrap(scope.registerOrdinaryComponent())
        }
        let receipt = try XCTUnwrap(
            attribution.registerOwnedComponent(
                owner: continuing?.owner ?? RetainedOwnedComponentID(), slots: [], continuing: continuing,
                declarationOnly: declarationOnly, candidateConstruction: boundary?.token))
        let group = try XCTUnwrap(attribution.registerGroup(kind: declarationOnly ? .structure : kind))
        return ReaderCustodyComponent(attribution: attribution, receipt: receipt, group: group)
    }

    func close(_ component: ReaderCustodyComponent, nodes: [ViewNode]) throws {
        for node in nodes { XCTAssertTrue(component.attribution.recordSourceOutput(node, group: component.group)) }
        _ = try XCTUnwrap(component.attribution.closeGroup(component.group))
    }

    func begin(source: ViewNode) {
        XCTAssertTrue(journal.registerSourceDescriptors(in: [source]))
        XCTAssertTrue(journal.beginOrdinaryAdoption())
        XCTAssertTrue(journal.markMutationStarted())
    }

    func finish(completed: Bool) {
        _ = journal.seal(completedCheckedAdoption: completed)
        journal.releaseUnadoptedTransport()
        scope.finish()
    }
}

@MainActor
private final class ReaderCustodyBoundary {
    let epoch: ReaderCustodyEpoch
    let owner: ReaderCustodyComponent
    let token: RetainedOwnedCandidateConstruction

    init(
        epoch: ReaderCustodyEpoch, continuing: RetainedOwnedComponentReceipt? = nil,
        under parent: ReaderCustodyBoundary? = nil
    ) throws {
        self.epoch = epoch
        owner = try epoch.open(under: parent, continuing: continuing)
        token = try XCTUnwrap(owner.attribution.beginOwnedCandidateConstruction(owner: owner.receipt))
    }

    func close(child: ViewNode, identity: Int) throws -> ViewNode {
        let node = ViewNode.selectedContentBoundary(role: .viewThatFits, child: child)
        node.retainedViewIdentity = RetainedViewIdentity().appending(.slot(identity))
        XCTAssertTrue(token.stageBoundary(on: node))
        try epoch.close(owner, nodes: [node])
        return node
    }
}

@MainActor
private func readerCustodyNode(_ identity: Int) -> ViewNode {
    let node = ViewNode()
    node.retainedViewIdentity = RetainedViewIdentity().appending(.slot(identity))
    return node
}

@MainActor
private func readerCustodyContinuationIsAdmitted(
    runtime: RetainedViewRuntime, contribution: RetainedDescriptorContributionReceipt,
    actual: RetainedLazyListActualAttachment
) -> Bool {
    let bootstrap = RetainedLazyListDescriptorBuildScope(
        origin: .managedSubtree, hostLifetime: runtime.lazyListLogicalHostLifetime,
        ownerLifetime: runtime.root.lazyListActivityStorage().descriptorOwnerLifetime)
    defer { bootstrap.finish() }
    guard
        let scope = bootstrap.withAdmittedOrdinaryDeferredSubtree(
            originalActivity: contribution, originalAttachment: actual)
    else { return false }
    defer { scope.finish() }
    guard let attribution = scope.registerOrdinaryComponent(),
        case .admitted(let token) = attribution.ownedCandidateContinuation()
    else { return false }
    return token.canConstruct
}
