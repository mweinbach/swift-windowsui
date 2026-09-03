import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI

@MainActor
final class RetainedOwnedCandidateDirectAdoptionGateTests: XCTestCase {
    func testUnscopedDirectCopySurvivesUnavailableOrdinaryDescriptorMetadata() async throws {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let target = ViewNode()
        target.opacity = 0.25
        runtime.root.addChild(target)
        let source = ViewNode()
        source.opacity = 0.75
        let scope = RetainedLazyListDescriptorBuildScope(
            origin: .componentHostRoot, hostLifetime: runtime.lazyListLogicalHostLifetime,
            ownerLifetime: runtime.root.lazyListActivityStorage().descriptorOwnerLifetime)
        let journal = RetainedLazyListAdoptionJournal(
            descriptorScope: scope, transaction: RetainedBuildTransaction())
        defer {
            _ = journal.seal(completedCheckedAdoption: false)
            journal.releaseUnadoptedTransport()
            scope.finish()
        }
        XCTAssertTrue(journal.seedOwnedCandidateOrigins(at: runtime.root))
        journal.seedExistingContributions(from: runtime.root.children)
        let attribution = try XCTUnwrap(scope.registerOrdinaryComponent())
        switch attribution.ownedCandidateContinuation() {
        case .unscoped:
            break
        case .admitted, .rejected:
            XCTFail("A plain ordinary root has no captured candidate continuation")
        }
        XCTAssertTrue(journal.registerSourceDescriptors(in: [source]))

        // Closing only the descriptor scope is a real lifecycle operation.
        // It neither rejects the source nor closes the actual runtime/owner.
        scope.finish()
        XCTAssertFalse(scope.canConstructDescriptors)
        XCTAssertFalse(journal.beginOrdinaryAdoption())
        XCTAssertTrue(journal.isOrdinaryAdoption)
        XCTAssertFalse(scope.canPublishDescriptors)
        XCTAssertFalse(journal.canContinueAdoption)
        XCTAssertFalse(journal.markMutationStarted())
        XCTAssertFalse(journal.preparePropertyCopy(from: source, to: target, keyPath: \ViewNode.opacity))
        XCTAssertFalse(source.containsRejectedRetainedSource)
        XCTAssertTrue(target.isRetainedLazyListAttached(in: runtime))
        XCTAssertTrue(target.parent === runtime.root)
        XCTAssertEqual(target.opacity, 0.25)

        // The existing ordinary direct path intentionally tolerates metadata
        // failure. An absent candidate original must keep that same behavior.
        let result = ComponentHost.adopt(source: source, into: target, lazyJournal: journal)

        XCTAssertTrue(result.completed)
        XCTAssertEqual(target.opacity, 0.75)
        XCTAssertTrue(runtime.root.children.first === target)
        XCTAssertTrue(target.parent === runtime.root)
        XCTAssertTrue(target.isRetainedLazyListAttached(in: runtime))
        XCTAssertNil(source.parent)
        XCTAssertFalse(source.containsRejectedRetainedSource)
        XCTAssertTrue(journal.isOrdinaryAdoption)
        XCTAssertFalse(journal.canContinueAdoption)
        XCTAssertNil(target.retainedLazyListActivityStorage?.descriptorDeferredSubtreeAnchor)
    }
}
