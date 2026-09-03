import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI

@MainActor
final class RetainedOwnedCandidateUncapturedTargetDirectAdoptionTests: XCTestCase {
    func testUnscopedDirectCopyIgnoresReaderNamespaceInstalledAfterOriginalCapture() async throws {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let root = runtime.root
        let rootStorage = root.lazyListActivityStorage()
        let originalOwner = rootStorage.descriptorOwnerLifetime
        let originalRoot = rootStorage.captureActualAttachment(of: root, in: runtime)
        let scope = RetainedLazyListDescriptorBuildScope(
            origin: .componentHostRoot, hostLifetime: runtime.lazyListLogicalHostLifetime,
            ownerLifetime: originalOwner)
        let journal = RetainedLazyListAdoptionJournal(
            descriptorScope: scope, transaction: RetainedBuildTransaction())
        defer {
            _ = journal.seal(completedCheckedAdoption: false)
            journal.releaseUnadoptedTransport()
            scope.finish()
        }

        // Capture the original operation while neither W nor A exists.
        XCTAssertTrue(root.children.isEmpty)
        XCTAssertTrue(originalRoot.isAttached)
        XCTAssertTrue(journal.seedOwnedCandidateOrigins(at: root))
        journal.seedExistingContributions(from: root.children)
        let attribution = try XCTUnwrap(scope.registerOrdinaryComponent())
        switch attribution.ownedCandidateContinuation() {
        case .unscoped:
            break
        case .admitted, .rejected:
            XCTFail("The original empty root must have an unscoped continuation")
        }
        let source = ViewNode()
        source.opacity = 0.75
        XCTAssertNil(source.retainedLazyListActivityStorage)
        XCTAssertTrue(journal.registerSourceDescriptors(in: [source]))
        XCTAssertNil(source.retainedLazyListActivityStorage)
        XCTAssertFalse(source.containsRejectedRetainedSource)

        // An independent real native operation now publishes W -> A. Its
        // accepted reader continuation is not an original of the old journal.
        let fixture = try UncapturedTargetReaderFixture(in: runtime)
        let target = fixture.reader
        XCTAssertTrue(runtime.root === root)
        XCTAssertTrue(rootStorage.descriptorOwnerLifetime === originalOwner)
        XCTAssertTrue(originalRoot.node === root)
        XCTAssertTrue(originalRoot.isAttached)
        XCTAssertTrue(scope.canConstructDescriptors)
        XCTAssertEqual(root.children.count, 1)
        XCTAssertTrue(root.children.first === fixture.boundary)
        XCTAssertTrue(fixture.boundary.parent === root)
        XCTAssertEqual(fixture.boundary.children.count, 1)
        XCTAssertTrue(fixture.boundary.children.first === target)
        XCTAssertTrue(target.parent === fixture.boundary)
        XCTAssertTrue(target.isRetainedLazyListAttached(in: runtime))
        XCTAssertTrue(target.children.isEmpty)
        XCTAssertNotNil(target.geometryReaderBuild)
        XCTAssertEqual(target.opacity, 0.25)
        XCTAssertTrue(try fixture.hasAdmittedReaderContinuation())
        switch attribution.ownedCandidateContinuation() {
        case .unscoped:
            break
        case .admitted, .rejected:
            XCTFail("Installing another operation's namespace must not rebind the original continuation")
        }

        // Make only the old descriptor metadata unavailable. The actual root
        // and independently accepted A are still live.
        scope.finish()
        XCTAssertFalse(scope.canConstructDescriptors)
        XCTAssertFalse(journal.beginOrdinaryAdoption())
        XCTAssertTrue(journal.isOrdinaryAdoption)
        XCTAssertFalse(scope.canPublishDescriptors)
        XCTAssertFalse(journal.canContinueAdoption)
        XCTAssertFalse(journal.markMutationStarted())
        XCTAssertFalse(journal.preparePropertyCopy(from: source, to: target, keyPath: \ViewNode.opacity))
        XCTAssertTrue(originalRoot.isAttached)
        XCTAssertTrue(target.isRetainedLazyListAttached(in: runtime))
        XCTAssertFalse(source.containsRejectedRetainedSource)
        XCTAssertTrue(try fixture.hasAdmittedReaderContinuation())

        // No namespace reference is requested by this plain direct copy.
        // A namespace discovered only on the current target cannot choose
        // a candidate route that was absent from the original operation.
        let result = ComponentHost.adopt(source: source, into: target, lazyJournal: journal)

        XCTAssertTrue(result.completed)
        XCTAssertEqual(target.opacity, 0.75)
        XCTAssertTrue(runtime.root === root)
        XCTAssertTrue(root.children.first === fixture.boundary)
        XCTAssertTrue(fixture.boundary.children.first === target)
        XCTAssertTrue(target.parent === fixture.boundary)
        XCTAssertTrue(target.isRetainedLazyListAttached(in: runtime))
        XCTAssertTrue(originalRoot.isAttached)
        XCTAssertNil(source.parent)
        XCTAssertNil(source.retainedLazyListRuntime)
        XCTAssertFalse(source.containsRejectedRetainedSource)
        XCTAssertTrue(journal.isOrdinaryAdoption)
        XCTAssertFalse(journal.canContinueAdoption)
        XCTAssertFalse(scope.canPublishDescriptors)
    }
}

/// The fresh W -> A subset of the separately frozen native segment fixture.
/// Every receipt and anchor comes from real preparation, attachment, and
/// successful native publication. This helper never assigns a namespace field.
@MainActor
private final class UncapturedTargetReaderFixture {
    let boundary: ViewNode
    let reader: ViewNode
    private let runtime: RetainedViewRuntime
    private let contribution: RetainedDescriptorContributionReceipt
    private let actual: RetainedLazyListActualAttachment

    init(in runtime: RetainedViewRuntime) throws {
        let scope = RetainedLazyListDescriptorBuildScope(
            origin: .componentHostRoot, hostLifetime: runtime.lazyListLogicalHostLifetime,
            ownerLifetime: runtime.root.lazyListActivityStorage().descriptorOwnerLifetime)
        let journal = RetainedLazyListAdoptionJournal(
            descriptorScope: scope, transaction: RetainedBuildTransaction())
        var didFinish = false
        defer {
            if !didFinish {
                _ = journal.seal(completedCheckedAdoption: false)
                journal.releaseUnadoptedTransport()
                scope.finish()
            }
        }
        XCTAssertTrue(runtime.root.children.isEmpty)
        XCTAssertTrue(journal.seedOwnedCandidateOrigins(at: runtime.root))
        journal.seedExistingContributions(from: runtime.root.children)

        let boundaryAttribution = try XCTUnwrap(scope.registerOrdinaryComponent())
        let boundaryOwner = try XCTUnwrap(
            boundaryAttribution.registerOwnedComponent(
                owner: RetainedOwnedComponentID(), slots: [], continuing: nil, candidateConstruction: nil))
        let boundaryGroup = try XCTUnwrap(boundaryAttribution.registerGroup(kind: .observation))
        let boundaryToken = try XCTUnwrap(
            boundaryAttribution.beginOwnedCandidateConstruction(owner: boundaryOwner))
        let readerAttribution = try XCTUnwrap(boundaryAttribution.registerChildComponent())
        let readerOwner = try XCTUnwrap(
            readerAttribution.registerOwnedComponent(
                owner: RetainedOwnedComponentID(), slots: [], continuing: nil,
                candidateConstruction: boundaryToken))
        let readerGroup = try XCTUnwrap(readerAttribution.registerGroup(kind: .deferredSubtree))
        let readerToken = try XCTUnwrap(
            boundaryToken.deferredSegment(owner: readerOwner, attribution: readerAttribution))
        let reader = ViewNode()
        reader.retainedViewIdentity = RetainedViewIdentity().appending(.slot(10))
        reader.opacity = 0.25
        reader.geometryReaderBuild = { _, _ in [] }
        XCTAssertTrue(readerToken.stageDeferredAnchor(on: reader))
        XCTAssertTrue(readerAttribution.recordSourceOutput(reader, group: readerGroup))
        _ = try XCTUnwrap(readerAttribution.closeGroup(readerGroup))
        let boundary = ViewNode.selectedContentBoundary(role: .viewThatFits, child: reader)
        boundary.retainedViewIdentity = RetainedViewIdentity().appending(.slot(1000))
        XCTAssertTrue(boundaryToken.stageBoundary(on: boundary))
        XCTAssertTrue(boundaryAttribution.recordSourceOutput(boundary, group: boundaryGroup))
        _ = try XCTUnwrap(boundaryAttribution.closeGroup(boundaryGroup))

        XCTAssertTrue(journal.registerSourceDescriptors(in: [boundary]))
        XCTAssertTrue(journal.beginOrdinaryAdoption())
        XCTAssertTrue(journal.markMutationStarted())
        XCTAssertTrue(journal.prepareInsertedNode(from: boundary))
        XCTAssertTrue(journal.prepareInsertedNode(from: reader))
        runtime.root.addChild(boundary)
        XCTAssertTrue(boundary.parent === runtime.root)
        XCTAssertTrue(reader.parent === boundary)
        XCTAssertTrue(boundary.isRetainedLazyListAttached(in: runtime))
        _ = journal.recordAcceptedInsertedNode(on: boundary)
        XCTAssertTrue(reader.isRetainedLazyListAttached(in: runtime))
        _ = journal.recordAcceptedInsertedNode(on: reader)
        _ = journal.recordCompletedNode(from: reader, to: reader)
        _ = journal.recordCompletedNode(from: boundary, to: boundary)
        _ = journal.seal(completedCheckedAdoption: true)
        journal.releaseUnadoptedTransport()
        scope.finish()
        didFinish = true

        let anchor = try XCTUnwrap(reader.retainedLazyListActivityStorage?.descriptorDeferredSubtreeAnchor)
        self.runtime = runtime
        self.reader = reader
        self.boundary = boundary
        contribution = anchor.contribution
        actual = anchor.actual
        XCTAssertTrue(actual.node === reader)
        XCTAssertTrue(actual.isAttached)
        XCTAssertTrue(contribution.isActive)
        XCTAssertTrue(boundaryOwner.hasAcceptedDeclaration)
        XCTAssertTrue(readerOwner.hasAcceptedDeclaration)
        XCTAssertTrue(boundaryOwner.hasDeclaredComponent)
        XCTAssertTrue(readerOwner.hasDeclaredComponent)
        XCTAssertTrue(boundaryOwner.slots.isEmpty)
        XCTAssertTrue(readerOwner.slots.isEmpty)
    }

    func hasAdmittedReaderContinuation() throws -> Bool {
        let bootstrap = RetainedLazyListDescriptorBuildScope(
            origin: .managedSubtree, hostLifetime: runtime.lazyListLogicalHostLifetime,
            ownerLifetime: runtime.root.lazyListActivityStorage().descriptorOwnerLifetime)
        let scope = try XCTUnwrap(
            bootstrap.withAdmittedOrdinaryDeferredSubtree(
                originalActivity: contribution, originalAttachment: actual))
        defer { scope.finish() }
        let attribution = try XCTUnwrap(scope.registerOrdinaryComponent())
        switch attribution.ownedCandidateContinuation() {
        case .admitted(let token):
            return token.canConstruct
        case .unscoped, .rejected:
            return false
        }
    }
}
