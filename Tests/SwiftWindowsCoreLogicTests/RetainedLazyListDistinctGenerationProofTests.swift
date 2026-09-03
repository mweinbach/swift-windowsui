import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI

/// Native proof metadata and adapter planning only; no runtime or window.
@MainActor
final class RetainedLazyListDistinctGenerationProofTests: XCTestCase {
    private typealias Source = RetainedLazyListDataSource<Int, [ViewNode]>
    private typealias Adapter = RetainedLazyListRuntimeAdapter

    func testEmptyRequestRosterHasNoDistinctProofs() async {
        let requests: [RetainedLazyListRowRequest] = []
        let indices = RetainedLazyListRowRequest.distinctGenerationProofIndices(in: requests)
        XCTAssertTrue(indices.isEmpty)
        XCTAssertTrue(indexedCurrent(requests, indices))
        XCTAssertTrue(requests.allSatisfy(\.isGenerationCurrent))
    }

    func testThousandRequestsUseOneOriginalIndexWithoutDroppingRequests() async throws {
        let source = makeSource(Array(0..<1000))
        defer { withExtendedLifetime(source) {} }
        let requests = try requests(source)
        let original = requests
        let indices = RetainedLazyListRowRequest.distinctGenerationProofIndices(in: requests)
        XCTAssertEqual(indices, [0])
        XCTAssertEqual(requests.count, 1000)
        XCTAssertEqual(requests, original)
        XCTAssertEqual(requests.map(\.sourceIndex), Array(0..<1000))
        XCTAssertTrue(indexedCurrent(requests, indices))
        XCTAssertTrue(requests.allSatisfy(\.isGenerationCurrent))
    }

    func testMixedProvidersKeepFirstOccurrenceOrderForEveryDistinctProof() async throws {
        let sources = [makeSource([0, 1]), makeSource([0, 1]), makeSource([0, 1])]
        let first = try requests(sources[0])
        let second = try requests(sources[1])
        let third = try requests(sources[2])
        let requests = [second[1], first[0], second[0], third[1], first[1], third[0]]
        let indices = RetainedLazyListRowRequest.distinctGenerationProofIndices(in: requests)
        XCTAssertEqual(indices, [0, 1, 3])
        XCTAssertTrue(indexedCurrent(requests, indices))
        XCTAssertTrue(requests.allSatisfy(\.isGenerationCurrent))
        withExtendedLifetime(sources) {}
    }

    func testReplacementDoesNotRefreshOrDiscardTheOriginalRevokedProof() async throws {
        let source = makeSource([0, 1, 2])
        defer { withExtendedLifetime(source) {} }
        let original = try requests(source)
        let indices = RetainedLazyListRowRequest.distinctGenerationProofIndices(in: original)
        XCTAssertEqual(indices, [0])
        XCTAssertTrue(indexedCurrent(original, indices))
        XCTAssertTrue(source.replaceData([0, 1, 2], id: \.self) { _ in [ViewNode()] })
        let replacement = try requests(source)
        XCTAssertFalse(indexedCurrent(original, indices))
        XCTAssertFalse(original.allSatisfy(\.isGenerationCurrent))
        XCTAssertTrue(replacement.allSatisfy(\.isGenerationCurrent))
        let mixed = original + replacement + original
        let mixedIndices = RetainedLazyListRowRequest.distinctGenerationProofIndices(in: mixed)
        XCTAssertEqual(mixedIndices, [0, 3])
        XCTAssertFalse(indexedCurrent(mixed, mixedIndices), "A stale proof is retained, never filtered away")
    }

    func testEveryDistinctProofCanRevokeAfterTheIndexRosterIsCaptured() async throws {
        for revoked in 0..<3 {
            let sources = [makeSource([0, 1]), makeSource([0, 1]), makeSource([0, 1])]
            let first = try requests(sources[0])
            let second = try requests(sources[1])
            let third = try requests(sources[2])
            let requests = [first[0], second[0], first[1], third[0], second[1], third[1]]
            let indices = RetainedLazyListRowRequest.distinctGenerationProofIndices(in: requests)
            XCTAssertEqual(indices, [0, 1, 3])
            XCTAssertTrue(indexedCurrent(requests, indices))
            sources[revoked].close()
            XCTAssertFalse(indexedCurrent(requests, indices), "generation \(revoked)")
            XCTAssertEqual(indexedCurrent(requests, indices), requests.allSatisfy(\.isGenerationCurrent))
            for index in 0..<3 where index != revoked {
                XCTAssertTrue(try self.requests(sources[index]).allSatisfy(\.isGenerationCurrent))
            }
        }
    }

    func testOriginalRequestsAndIndicesDoNotRetainProviderOrFactoryPayload() async throws {
        var source: Source? = Source()
        var payload: DistinctGenerationPayload? = DistinctGenerationPayload()
        weak var weakSource = source
        weak var weakPayload = payload
        XCTAssertTrue(
            source?.replaceData([0, 1], id: \.self) { [payload] _ in
                withExtendedLifetime(payload) { [ViewNode()] }
            } == true)
        let requests = try requests(try XCTUnwrap(source))
        let indices = RetainedLazyListRowRequest.distinctGenerationProofIndices(in: requests)
        XCTAssertEqual(indices, [0])
        XCTAssertTrue(indexedCurrent(requests, indices))
        payload = nil
        XCTAssertNotNil(weakPayload)
        source = nil
        XCTAssertNil(weakSource)
        XCTAssertNil(weakPayload)
        XCTAssertFalse(indexedCurrent(requests, indices))
        XCTAssertFalse(requests.allSatisfy(\.isGenerationCurrent))
    }

    func testCandidateStillReadsNativeProofsWithoutProviderCallsAndRejectsRevocation() async throws {
        for mode in ["replace", "close", "adapter"] {
            let source = makeSource(Array(0..<8))
            let probe = DistinctGenerationProviderProbe(source)
            let adapter = try XCTUnwrap(
                Adapter(
                    provider: probe, estimatedExtent: 20, prefetchExtent: 20,
                    maximumMountedRecords: 16, maximumMountedLeaves: 16, maximumProtectedRecords: 4))
            let context = try XCTUnwrap(
                RetainedLazyListMeasurementContext(
                    width: 120, displayScale: 1, contentRevision: 0, environmentRevision: 0))
            let viewport = try XCTUnwrap(Adapter.Viewport(context: context, offset: 0, extent: 60))
            let budget = try XCTUnwrap(RetainedLazyListWorkBudget(elementLimit: 16, roundLimit: 4))
            guard case .ready(let candidate) = adapter.prepare(viewport: viewport, protectedRoots: [], budget: budget)
            else { return XCTFail("Expected a bounded candidate") }
            XCTAssertGreaterThan(candidate.recordLeafCounts.count, 1)
            let calls = probe.calls
            for _ in 0..<8 { XCTAssertTrue(candidate.isCurrent) }
            XCTAssertEqual(probe.calls, calls)
            switch mode {
            case "replace":
                XCTAssertTrue(source.replaceData(Array(0..<8), id: \.self) { _ in [ViewNode()] })
            case "close":
                source.close()
            default:
                adapter.revokePendingCandidate()
            }
            XCTAssertFalse(candidate.isCurrent, mode)
            XCTAssertEqual(probe.calls, calls)
        }
    }

    private func makeSource(_ values: [Int]) -> Source {
        let source = Source()
        XCTAssertTrue(source.replaceData(values, id: \.self) { _ in [ViewNode()] })
        return source
    }

    private func requests(_ source: Source) throws -> [RetainedLazyListRowRequest] {
        let metadata = try XCTUnwrap(source.metadata)
        return try metadata.rows.map { try XCTUnwrap(source.request(for: $0.token)) }
    }

    private func indexedCurrent(_ requests: [RetainedLazyListRowRequest], _ indices: [Int]) -> Bool {
        indices.allSatisfy { requests[$0].isGenerationCurrent }
    }
}

private final class DistinctGenerationPayload {}

@MainActor
private final class DistinctGenerationProviderProbe: RetainedLazyListProvider {
    typealias RowContent = [ViewNode]
    let source: RetainedLazyListDataSource<Int, [ViewNode]>
    var calls = 0

    init(_ source: RetainedLazyListDataSource<Int, [ViewNode]>) { self.source = source }

    var metadata: RetainedLazyListMetadata? {
        calls += 1
        return source.metadata
    }

    func token(for key: RetainedViewIdentity.Key, occurrence: Int) -> RetainedLazyListRowToken? {
        calls += 1
        return source.token(for: key, occurrence: occurrence)
    }

    func request(for token: RetainedLazyListRowToken) -> RetainedLazyListRowRequest? {
        calls += 1
        return source.request(for: token)
    }

    func isCurrent(_ request: RetainedLazyListRowRequest) -> Bool {
        calls += 1
        return source.isCurrent(request)
    }

    func identityPrefix(for request: RetainedLazyListRowRequest) -> RetainedViewIdentity? {
        calls += 1
        return source.identityPrefix(for: request)
    }

    func materialize(
        _ request: RetainedLazyListRowRequest, budget: RetainedLazyListWorkBudget
    ) -> RetainedLazyListMaterialization<[ViewNode]> {
        calls += 1
        return source.materialize(request, budget: budget)
    }
}
