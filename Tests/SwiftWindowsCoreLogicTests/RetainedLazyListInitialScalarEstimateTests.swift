import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI

@MainActor
final class RetainedLazyListInitialScalarEstimateTests: XCTestCase {
    private typealias Source = RetainedLazyListDataSource<Int, [ViewNode]>
    private typealias Adapter = RetainedLazyListRuntimeAdapter

    func testColdBudgetExhaustionPreservesEstimatesWithoutLayoutAuthority() async throws {
        var calls = 0
        let source = try makeSource([0, 1, 2]) { _ in
            calls += 1
            return []
        }
        let adapter = try makeAdapter(source)
        defer {
            source.close()
            adapter.releaseMountedRecords()
        }
        let viewport = try viewport()

        guard
            case .workRemaining = adapter.prepare(
                viewport: viewport, protectedRoots: [], budget: try budget(0))
        else { return XCTFail("The initial snapshot must not spend an unavailable element") }

        XCTAssertEqual(calls, 0)
        XCTAssertEqual(adapter.contentExtent, 60)
        XCTAssertEqual(adapter.logicalRecordCount, 3)
        XCTAssertEqual(adapter.layoutPlan(viewport: viewport).contentExtent, 60)
        assertUnaccepted(adapter, viewport: viewport)
    }

    func testDiscardingInitialEmptyCandidateCannotCertifyZeroExtent() async throws {
        let source = try makeSource([0]) { _ in [] }
        let adapter = try makeAdapter(source)
        defer {
            source.close()
            adapter.releaseMountedRecords()
        }
        let viewport = try viewport()
        let discarded = try ready(adapter, viewport: viewport)
        XCTAssertEqual(discarded.recordLeafCounts, [0])
        XCTAssertEqual(adapter.contentExtent, 20)

        discarded.discardBuiltContent()

        XCTAssertFalse(discarded.isCurrent)
        XCTAssertEqual(adapter.contentExtent, 20)
        assertUnaccepted(adapter, viewport: viewport)
        let accepted = try ready(adapter, viewport: viewport)
        XCTAssertTrue(adapter.complete(candidate: accepted, adoptedChildren: []))
        accepted.discardBuiltContent()
        XCTAssertEqual(adapter.contentExtent, 0)
        XCTAssertTrue(adapter.hasCurrentLogicalSnapshot)
        XCTAssertNotNil(adapter.captureLayoutProof())
    }

    func testAcceptedEmptyIndexStillRestoresBeforeReplacementAcceptance() async throws {
        let source = try makeSource([0]) { _ in [] }
        let adapter = try makeAdapter(source)
        defer {
            source.close()
            adapter.releaseMountedRecords()
        }
        let viewport = try viewport()
        let initial = try ready(adapter, viewport: viewport)
        XCTAssertTrue(adapter.complete(candidate: initial, adoptedChildren: []))
        initial.discardBuiltContent()
        let originalProof = try XCTUnwrap(adapter.captureLayoutProof())
        XCTAssertEqual(adapter.contentExtent, 0)
        XCTAssertTrue(source.replaceData([0, 1], id: \.self) { _ in [ViewNode()] })

        guard
            case .workRemaining = adapter.prepare(
                viewport: viewport, protectedRoots: [], budget: try budget(0))
        else { return XCTFail("Replacement must remain pending without an element") }

        XCTAssertEqual(adapter.contentExtent, 0, "A nonnil empty index is still the prior coordinate basis")
        XCTAssertEqual(adapter.logicalRecordCount, 1)
        XCTAssertFalse(originalProof.isCurrent)
        assertUnaccepted(adapter, viewport: viewport)
    }

    func testInitialFactoryTeardownKeepsEstimatesWithoutRevivingItsAttempt() async throws {
        let source = Source()
        weak var weakAdapter: Adapter?
        var calls = 0
        XCTAssertTrue(
            source.replaceData([0], id: \.self) { _ in
                calls += 1
                weakAdapter?.releaseMountedRecords()
                return [ViewNode()]
            })
        let adapter = try makeAdapter(source)
        weakAdapter = adapter
        defer {
            source.close()
            adapter.releaseMountedRecords()
        }
        let viewport = try viewport()

        guard
            case .obsolete = adapter.prepare(
                viewport: viewport, protectedRoots: [], budget: try budget(1))
        else { return XCTFail("Teardown during the factory must revoke the original attempt") }

        XCTAssertEqual(calls, 1)
        XCTAssertEqual(adapter.contentExtent, 20)
        XCTAssertNotNil(source.metadata)
        assertUnaccepted(adapter, viewport: viewport)
    }

    func testInitialCandidateCleanupCannotOverwriteNewerContextPublication() async throws {
        var onRelease: (@MainActor () -> Void)?
        let source = try makeSource([0]) { _ in
            let payload = InitialScalarEstimatePayload { onRelease?() }
            let node = ViewNode()
            node.onPointerEnter = { [payload] in withExtendedLifetime(payload) {} }
            return [node]
        }
        let adapter = try makeAdapter(source)
        defer {
            onRelease = nil
            source.close()
            adapter.releaseMountedRecords()
        }
        let originalViewport = try viewport()
        let newerViewport = try viewport(width: 240)
        let original = try ready(adapter, viewport: originalViewport)
        var publications = 0
        onRelease = { [weak source, weak adapter] in
            onRelease = nil
            guard let source, let adapter else { return XCTFail("The test still owns both live inputs") }
            do {
                XCTAssertTrue(source.replaceData([0, 1], id: \.self) { _ in [ViewNode()] })
                let newer = try self.ready(adapter, viewport: newerViewport)
                XCTAssertTrue(adapter.complete(candidate: newer, adoptedChildren: newer.children))
                newer.discardBuiltContent()
                let measurements = adapter.layoutPlan(viewport: newerViewport).placements.enumerated().map {
                    Adapter.Measurement(
                        token: $0.element.token, leafIndex: $0.element.leafIndex, node: $0.element.node,
                        extent: $0.offset == 0 ? 31 : 47)
                }
                XCTAssertEqual(measurements.count, 2)
                XCTAssertNotNil(adapter.recordMeasurements(measurements, viewport: newerViewport))
                publications += 1
            } catch {
                XCTFail("Cleanup must be allowed to finish its independently prepared table: \(error)")
            }
        }

        original.discardBuiltContent()

        XCTAssertEqual(publications, 1)
        XCTAssertFalse(original.isCurrent)
        XCTAssertEqual(adapter.contentExtent, 78)
        XCTAssertTrue(adapter.hasCurrentLogicalSnapshot)
        XCTAssertTrue(try XCTUnwrap(adapter.captureLayoutProof()).isCurrent)
        XCTAssertEqual(adapter.layoutPlan(viewport: newerViewport).placements.count, 2)
        XCTAssertTrue(adapter.layoutPlan(viewport: originalViewport).placements.isEmpty)
        XCTAssertEqual(adapter.contentExtent, 78)
    }

    private func assertUnaccepted(_ adapter: Adapter, viewport: Adapter.Viewport) {
        let plan = adapter.layoutPlan(viewport: viewport)
        XCTAssertTrue(plan.placements.isEmpty)
        XCTAssertTrue(plan.requiresResolution)
        XCTAssertTrue(adapter.hasUnresolvedWork)
        XCTAssertFalse(adapter.hasCurrentLogicalSnapshot)
        XCTAssertNil(adapter.currentLogicalGeneration)
        XCTAssertNil(adapter.captureLayoutProof())
        XCTAssertNil(adapter.captureUIAActualRecordsProof())
        XCTAssertNil(adapter.captureRenderMeasurementProof())
        XCTAssertNil(adapter.recordMeasurements([], viewport: viewport))
        XCTAssertEqual(adapter.mountedRecordCount, 0)
        XCTAssertEqual(adapter.mountedLeafCount, 0)
    }

    private func makeSource(
        _ values: [Int], content: @escaping @MainActor (Int) -> [ViewNode]
    ) throws -> Source {
        let source = Source()
        XCTAssertTrue(source.replaceData(values, id: \.self, rowContent: content))
        return source
    }

    private func makeAdapter(_ source: Source) throws -> Adapter {
        try XCTUnwrap(
            Adapter(
                provider: source, estimatedExtent: 20, prefetchExtent: 0,
                maximumMountedRecords: 8, maximumMountedLeaves: 8, maximumProtectedRecords: 1))
    }

    private func viewport(width: Double = 120) throws -> Adapter.Viewport {
        let context = try XCTUnwrap(
            RetainedLazyListMeasurementContext(
                width: width, displayScale: 1, contentRevision: 0, environmentRevision: 0))
        return try XCTUnwrap(Adapter.Viewport(context: context, offset: 0, extent: 100))
    }

    private func budget(_ elements: Int) throws -> RetainedLazyListWorkBudget {
        try XCTUnwrap(RetainedLazyListWorkBudget(elementLimit: elements, roundLimit: 1))
    }

    private func ready(_ adapter: Adapter, viewport: Adapter.Viewport) throws -> Adapter.Candidate {
        guard
            case .ready(let candidate) = adapter.prepare(
                viewport: viewport, protectedRoots: [], budget: try budget(8))
        else { throw InitialScalarEstimateError.notReady }
        return candidate
    }
}

private enum InitialScalarEstimateError: Error { case notReady }

@MainActor
private final class InitialScalarEstimatePayload {
    let onRelease: @MainActor () -> Void
    init(_ onRelease: @escaping @MainActor () -> Void) { self.onRelease = onRelease }
    isolated deinit { onRelease() }
}
