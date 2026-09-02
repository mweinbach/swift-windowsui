import XCTest

@testable import SwiftWindowsUI

/// Native planning/publication controls. The existing public successor and
/// one-round fixtures separately exercise Runtime's actual retained adoption.
@MainActor
final class LazyListAnchorScalarStageTests: XCTestCase {
    func testFactorySourceRevocationRestoresCoordinatesWithoutACandidate() async throws {
        let fixture = try AnchorScalarStageFixture()
        defer { fixture.close() }
        try fixture.replace()
        let start = fixture.probe.factories.count
        fixture.provider.onMaterialize = { [weak source = fixture.source] in source?.close() }

        guard case .obsolete = fixture.prepare() else { return XCTFail("Expected revoked source preparation") }

        XCTAssertEqual(Array(fixture.probe.factories.dropFirst(start)), [0])
        XCTAssertEqual(fixture.adapter.captureAnchor(at: 95), fixture.originalAnchor)
        XCTAssertEqual(fixture.adapter.contentExtent, 123, accuracy: 0.001)
        XCTAssertEqual(fixture.adapter.mountedRecordCount, 4)
        XCTAssertFalse(fixture.originalProof.isCurrent)
        XCTAssertFalse(fixture.adapter.hasCurrentLogicalSnapshot)
        XCTAssertNil(fixture.adapter.captureLayoutProof())
        XCTAssertTrue(fixture.adapter.hasUnresolvedWork)
    }

    func testExplicitRevocationInsideFactoryRestoresOnlyScalarGeometry() async throws {
        let fixture = try AnchorScalarStageFixture()
        defer { fixture.close() }
        try fixture.replace()
        let start = fixture.probe.factories.count
        fixture.provider.onMaterialize = { [weak adapter = fixture.adapter] in adapter?.revokePendingCandidate() }

        guard case .obsolete = fixture.prepare() else { return XCTFail("Expected revoked attempt") }

        XCTAssertEqual(Array(fixture.probe.factories.dropFirst(start)), [0])
        XCTAssertEqual(fixture.adapter.captureAnchor(at: 95), fixture.originalAnchor)
        XCTAssertEqual(fixture.adapter.contentExtent, 123, accuracy: 0.001)
        XCTAssertNotNil(fixture.source.metadata, "Restoring geometry must not close the current source")
        XCTAssertFalse(fixture.originalProof.isCurrent)
        XCTAssertFalse(fixture.adapter.hasCurrentLogicalSnapshot)
        XCTAssertNil(fixture.adapter.captureLayoutProof())
        XCTAssertTrue(fixture.adapter.hasUnresolvedWork)
    }

    func testDiscardedReadyCandidateRestoresOriginalTokenOrder() async throws {
        let fixture = try AnchorScalarStageFixture()
        defer { fixture.close() }
        let offsets = [15.0, 45, 75, 105]
        let originals = offsets.map { fixture.adapter.captureAnchor(at: $0) }
        try fixture.replace(order: [3, 0, 1, 2])
        let candidate = try fixture.ready()
        XCTAssertTrue(candidate.isCurrent)

        candidate.discardBuiltContent()

        XCTAssertEqual(offsets.map { fixture.adapter.captureAnchor(at: $0) }, originals)
        XCTAssertEqual(fixture.adapter.contentExtent, 123, accuracy: 0.001)
        XCTAssertFalse(candidate.isCurrent)
        XCTAssertFalse(fixture.originalProof.isCurrent)
        XCTAssertFalse(fixture.adapter.hasCurrentLogicalSnapshot)
        XCTAssertNil(fixture.adapter.captureLayoutProof())
        XCTAssertEqual(fixture.adapter.mountedRecordCount, 4)
    }

    func testOlderCandidateCleanupCannotOverwriteANewerPendingStage() async throws {
        let fixture = try AnchorScalarStageFixture()
        defer { fixture.close() }
        try fixture.replace()
        let older = try fixture.ready()
        fixture.adapter.revokePendingCandidate()
        XCTAssertEqual(fixture.adapter.captureAnchor(at: 95), fixture.originalAnchor)
        try fixture.replace()
        let newer = try fixture.ready()

        older.discardBuiltContent()

        XCTAssertTrue(newer.isCurrent)
        XCTAssertEqual(fixture.adapter.contentExtent, 124, accuracy: 0.001)
        XCTAssertEqual(try fixture.resolveOriginal(), 96, accuracy: 0.001)
        XCTAssertTrue(fixture.adapter.complete(candidate: newer, adoptedChildren: newer.children))
        newer.discardBuiltContent()
        let proof = try XCTUnwrap(fixture.adapter.captureLayoutProof())
        XCTAssertTrue(proof.isCurrent)
        XCTAssertEqual(try fixture.resolveOriginal(), 96, accuracy: 0.001)
        XCTAssertFalse(fixture.originalProof.isCurrent)
    }

    func testAcceptedPartialTableCommitsEstimatesBeforeSettlement() async throws {
        let fixture = try AnchorScalarStageFixture()
        defer { fixture.close() }
        try fixture.replace()
        let start = fixture.probe.factories.count
        let budget = try XCTUnwrap(RetainedLazyListWorkBudget(elementLimit: 1, roundLimit: 1))
        let candidate = try fixture.ready(budget: budget)
        XCTAssertEqual(candidate.recordLeafCounts, [1])

        XCTAssertTrue(fixture.adapter.complete(candidate: candidate, adoptedChildren: candidate.children))

        let proof = try XCTUnwrap(fixture.adapter.captureLayoutProof())
        XCTAssertTrue(proof.isCurrent)
        XCTAssertTrue(fixture.adapter.hasUnresolvedWork)
        XCTAssertEqual(fixture.adapter.mountedRecordCount, 1)
        XCTAssertEqual(Array(fixture.probe.factories.dropFirst(start)), [0])
        XCTAssertEqual(budget.remainingElements, 0)
        XCTAssertEqual(budget.remainingRounds, 1, "Only Runtime consumes rounds")
        XCTAssertEqual(try fixture.resolveOriginal(), 96, accuracy: 0.001)
        candidate.discardBuiltContent()
        fixture.adapter.revokePendingCandidate()
        XCTAssertEqual(try fixture.resolveOriginal(), 96, accuracy: 0.001)
        XCTAssertEqual(fixture.adapter.captureAnchor(at: 96), fixture.originalAnchor)
        XCTAssertFalse(proof.isCurrent)
        XCTAssertFalse(fixture.adapter.hasCurrentLogicalSnapshot)
    }

    func testPublicationCleanupRevocationDoesNotRollbackThePublishedTable() async throws {
        let fixture = try AnchorScalarStageFixture()
        defer { fixture.close() }
        try fixture.replace()
        let candidate = try fixture.ready()
        var revoked = 0
        fixture.probe.onRelease = { [weak adapter = fixture.adapter] version in
            guard version == 0 else { return }
            revoked += 1
            adapter?.revokePendingCandidate()
        }

        XCTAssertFalse(fixture.adapter.complete(candidate: candidate, adoptedChildren: candidate.children))

        XCTAssertEqual(revoked, 1, "The old row payload must unwind after native publication")
        XCTAssertEqual(fixture.adapter.mountedRecordCount, 4)
        XCTAssertEqual(fixture.adapter.contentExtent, 124, accuracy: 0.001)
        XCTAssertEqual(try fixture.resolveOriginal(), 96, accuracy: 0.001)
        candidate.discardBuiltContent()
        XCTAssertEqual(try fixture.resolveOriginal(), 96, accuracy: 0.001)
        XCTAssertFalse(fixture.adapter.hasCurrentLogicalSnapshot)
        XCTAssertNil(fixture.adapter.captureLayoutProof())
        XCTAssertFalse(fixture.originalProof.isCurrent)
    }

    func testDiscardCleanupCanPublishANewerTableWithoutLateRollback() async throws {
        let fixture = try AnchorScalarStageFixture()
        defer { fixture.close() }
        try fixture.replace()
        let obsolete = try fixture.ready()
        var completions = 0
        fixture.probe.onRelease = { [weak fixture] version in
            guard version == 1, let fixture else { return }
            fixture.probe.onRelease = nil
            do {
                try fixture.replace()
                let newer = try fixture.ready()
                XCTAssertTrue(fixture.adapter.complete(candidate: newer, adoptedChildren: newer.children))
                newer.discardBuiltContent()
                completions += 1
            } catch {
                XCTFail("Cleanup must publish its independently prepared table: \(error)")
            }
        }

        obsolete.discardBuiltContent()

        XCTAssertEqual(completions, 1)
        XCTAssertEqual(fixture.adapter.mountedRecordCount, 4)
        XCTAssertEqual(fixture.adapter.contentExtent, 124, accuracy: 0.001)
        XCTAssertEqual(try fixture.resolveOriginal(), 96, accuracy: 0.001)
        let proof = try XCTUnwrap(fixture.adapter.captureLayoutProof())
        XCTAssertTrue(proof.isCurrent)
        XCTAssertFalse(obsolete.isCurrent)
        XCTAssertFalse(fixture.originalProof.isCurrent)
    }
}

@MainActor
private final class AnchorScalarStageFixture {
    typealias Adapter = RetainedLazyListRuntimeAdapter
    let probe: AnchorScalarStageProbe
    let source: RetainedLazyListDataSource<Int, [ViewNode]>
    let provider: AnchorScalarStageProvider
    let adapter: Adapter
    let viewport: Adapter.Viewport
    let originalAnchor: RetainedLazyListAnchor
    let originalProof: Adapter.LayoutProof

    init() throws {
        let probe = AnchorScalarStageProbe()
        let source = RetainedLazyListDataSource<Int, [ViewNode]>()
        XCTAssertTrue(source.replaceData([0, 1, 2, 3], id: \.self) { probe.makeRow($0) })
        let provider = AnchorScalarStageProvider(source)
        let adapter = try XCTUnwrap(
            Adapter(
                provider: provider, estimatedExtent: 31, prefetchExtent: 0,
                maximumMountedRecords: 8, maximumMountedLeaves: 8, maximumProtectedRecords: 1))
        let context = try XCTUnwrap(
            RetainedLazyListMeasurementContext(width: 120, displayScale: 1, contentRevision: 0, environmentRevision: 0))
        let viewport = try XCTUnwrap(Adapter.Viewport(context: context, offset: 0, extent: 200))
        let budget = try XCTUnwrap(RetainedLazyListWorkBudget(elementLimit: 8, roundLimit: 1))
        guard case .ready(let initial) = adapter.prepare(viewport: viewport, protectedRoots: [], budget: budget) else {
            throw AnchorScalarStageFixtureError.notReady
        }
        XCTAssertTrue(adapter.complete(candidate: initial, adoptedChildren: initial.children))
        initial.discardBuiltContent()
        let measurements = adapter.layoutPlan(viewport: viewport).placements.map {
            Adapter.Measurement(token: $0.token, leafIndex: $0.leafIndex, node: $0.node, extent: $0.node.frame.height)
        }
        XCTAssertNotNil(adapter.recordMeasurements(measurements, viewport: viewport))
        self.probe = probe
        self.source = source
        self.provider = provider
        self.adapter = adapter
        self.viewport = viewport
        originalAnchor = try XCTUnwrap(adapter.captureAnchor(at: 95))
        originalProof = try XCTUnwrap(adapter.captureLayoutProof())
        XCTAssertEqual(originalAnchor.offsetWithinRecord, 3, accuracy: 0.001)
        XCTAssertEqual(adapter.contentExtent, 123, accuracy: 0.001)
        XCTAssertEqual(probe.factories, [0, 1, 2, 3])
        XCTAssertTrue(originalProof.isCurrent)
    }

    func replace(order: [Int] = [0, 1, 2, 3]) throws {
        probe.version += 1
        XCTAssertTrue(source.replaceData(order, id: \.self) { [probe] in probe.makeRow($0) })
    }

    func prepare(budget: RetainedLazyListWorkBudget? = nil) -> Adapter.Preparation {
        guard let supplied = budget ?? RetainedLazyListWorkBudget(elementLimit: 8, roundLimit: 1) else {
            XCTFail("Expected a finite native budget")
            return .unsupported
        }
        return adapter.prepare(viewport: viewport, protectedRoots: [], budget: supplied)
    }

    func ready(budget: RetainedLazyListWorkBudget? = nil) throws -> Adapter.Candidate {
        guard case .ready(let candidate) = prepare(budget: budget) else {
            throw AnchorScalarStageFixtureError.notReady
        }
        return candidate
    }

    func resolveOriginal() throws -> Double {
        try XCTUnwrap(adapter.resolveAnchor(originalAnchor, viewportExtent: 0))
    }

    func close() {
        provider.onMaterialize = nil
        probe.onRelease = nil
        source.close()
        adapter.releaseMountedRecords()
    }
}

private enum AnchorScalarStageFixtureError: Error { case notReady }

@MainActor
private final class AnchorScalarStageProbe {
    var version = 0
    var factories: [Int] = []
    var onRelease: (@MainActor (Int) -> Void)?

    func makeRow(_ value: Int) -> [ViewNode] {
        factories.append(value)
        let node = ViewNode(frame: Rect(x: 0, y: 0, width: 120, height: value == 0 ? 30 : 31))
        if value == 0 {
            let payload = AnchorScalarStagePayload(version: version) { [weak self] in self?.onRelease?($0) }
            node.onPointerEnter = { [payload] in withExtendedLifetime(payload) {} }
        }
        return [node]
    }
}

@MainActor
private final class AnchorScalarStagePayload {
    let version: Int
    let onRelease: @MainActor (Int) -> Void

    init(version: Int, onRelease: @escaping @MainActor (Int) -> Void) {
        self.version = version
        self.onRelease = onRelease
    }

    isolated deinit { onRelease(version) }
}

@MainActor
private final class AnchorScalarStageProvider: RetainedLazyListProvider {
    typealias RowContent = [ViewNode]
    let source: RetainedLazyListDataSource<Int, [ViewNode]>
    var onMaterialize: (@MainActor () -> Void)?

    init(_ source: RetainedLazyListDataSource<Int, [ViewNode]>) { self.source = source }

    var metadata: RetainedLazyListMetadata? { source.metadata }

    func request(for token: RetainedLazyListRowToken) -> RetainedLazyListRowRequest? { source.request(for: token) }

    func isCurrent(_ request: RetainedLazyListRowRequest) -> Bool { source.isCurrent(request) }

    func materialize(
        _ request: RetainedLazyListRowRequest, budget: RetainedLazyListWorkBudget
    ) -> RetainedLazyListMaterialization<[ViewNode]> {
        let result = source.materialize(request, budget: budget)
        onMaterialize?()
        return result
    }
}
