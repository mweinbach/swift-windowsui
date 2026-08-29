import SwiftWindowsCore
import SwiftWindowsLayout
import XCTest

@testable import SwiftWindowsUI

/// These exercise Runtime's issued layout receipts, not an adapter LayoutProof.
/// Revocation and validation occur without another render or geometry query.
/// The injected lease does not establish facade state or public List support.
@MainActor
final class RetainedLazyListReceiptRevocationTests: XCTestCase {
    func testUnchangedProviderKeepsItsSettledReceiptCurrentWithoutAnotherPass() async throws {
        let calls = ReceiptRowCalls()
        let source = try makeSource(calls: calls)
        defer { source.close() }
        let provider = ReceiptProviderProbe(source: source)
        let fixture = try ReceiptFixture(provider: provider, calls: calls)
        _ = fixture.runtime.renderFrame()
        let receipt = try fixture.settledReceipt()
        let witnesses = try sourceWitnesses(source)
        XCTAssertTrue(witnesses.generation.isCurrent)
        XCTAssertTrue(witnesses.request.isGenerationCurrent)
        XCTAssertEqual(calls.rows, [0, 1, 2])
        XCTAssertEqual(fixture.list.children.count, 3)
        let activity = fixture.activity

        for _ in 0..<3 {
            XCTAssertTrue(fixture.runtime.isLayoutSettlementReceiptCurrent(receipt))
            guard case .settled = fixture.runtime.layoutSettlementStatus else {
                return XCTFail("Unchanged native source proof must preserve the issued receipt")
            }
        }

        XCTAssertEqual(fixture.activity, activity, "Reading a receipt must not refresh layout or consult the provider")
        XCTAssertTrue(witnesses.generation.isCurrent)
        XCTAssertTrue(witnesses.request.isGenerationCurrent)
        XCTAssertFalse(fixture.adapter.hasUnresolvedWork)
    }

    func testClosingTheProviderOutsideLayoutRejectsItsPreviouslySettledReceipt() async throws {
        let calls = ReceiptRowCalls()
        let source = try makeSource(calls: calls)
        defer { source.close() }
        let provider = ReceiptProviderProbe(source: source)
        let fixture = try ReceiptFixture(provider: provider, calls: calls)
        _ = fixture.runtime.renderFrame()
        let receipt = try fixture.settledReceipt()
        let witnesses = try sourceWitnesses(source)
        XCTAssertTrue(witnesses.generation.isCurrent)
        XCTAssertTrue(witnesses.request.isGenerationCurrent)
        XCTAssertTrue(fixture.runtime.isLayoutSettlementReceiptCurrent(receipt))
        XCTAssertTrue(fixture.runtime.canPrepareLayoutSettlement)
        XCTAssertFalse(fixture.runtime.isLayoutInProgress)
        let activity = fixture.activity

        source.close()

        XCTAssertTrue(source.isClosed)
        XCTAssertFalse(witnesses.generation.isCurrent)
        XCTAssertFalse(witnesses.request.isGenerationCurrent)
        assertRejected(receipt, by: fixture)
        XCTAssertEqual(fixture.activity, activity, "Provider close must revoke the old receipt before another pass")
        XCTAssertEqual(calls.rows, [0, 1, 2])
    }

    func testReplacingTheGenerationOutsideLayoutRejectsItsPreviouslySettledReceipt() async throws {
        let calls = ReceiptRowCalls()
        let source = try makeSource(calls: calls)
        defer { source.close() }
        let provider = ReceiptProviderProbe(source: source)
        let fixture = try ReceiptFixture(provider: provider, calls: calls)
        _ = fixture.runtime.renderFrame()
        let receipt = try fixture.settledReceipt()
        let witnesses = try sourceWitnesses(source)
        XCTAssertTrue(witnesses.generation.isCurrent)
        XCTAssertTrue(witnesses.request.isGenerationCurrent)
        XCTAssertTrue(fixture.runtime.isLayoutSettlementReceiptCurrent(receipt))
        XCTAssertTrue(fixture.runtime.canPrepareLayoutSettlement)
        XCTAssertFalse(fixture.runtime.isLayoutInProgress)
        let activity = fixture.activity

        // Keep every typed ID and eventual row size the same. Only the source
        // generation changes; no retained property or measurement revision is set.
        XCTAssertTrue(replaceRows(in: source, calls: calls))

        let replacement = try sourceWitnesses(source)
        XCTAssertNotEqual(replacement.generation, witnesses.generation)
        XCTAssertTrue(replacement.generation.isCurrent)
        XCTAssertTrue(replacement.request.isGenerationCurrent)
        XCTAssertEqual(replacement.request.token, witnesses.request.token)
        XCTAssertFalse(witnesses.generation.isCurrent)
        XCTAssertFalse(witnesses.request.isGenerationCurrent)
        assertRejected(receipt, by: fixture)
        XCTAssertEqual(fixture.activity, activity, "A new source generation cannot reuse a receipt for the old one")
        XCTAssertEqual(calls.rows, [0, 1, 2], "Replacing metadata must not construct replacement rows")
    }

    func testDataSourceLifetimeExpirationOutsideLayoutRejectsItsPreviouslySettledReceipt() async throws {
        let calls = ReceiptRowCalls()
        var source: RetainedLazyListDataSource<Int, [ViewNode]>? = try makeSource(calls: calls)
        let provider = ReceiptProviderProbe(source: source)
        let fixture = try ReceiptFixture(provider: provider, calls: calls)
        _ = fixture.runtime.renderFrame()
        let receipt = try fixture.settledReceipt()
        let witnesses = try sourceWitnesses(source)
        weak var observedSource = source
        XCTAssertNotNil(observedSource)
        XCTAssertTrue(witnesses.generation.isCurrent)
        XCTAssertTrue(witnesses.request.isGenerationCurrent)
        XCTAssertTrue(fixture.runtime.isLayoutSettlementReceiptCurrent(receipt))
        XCTAssertTrue(fixture.runtime.canPrepareLayoutSettlement)
        XCTAssertFalse(fixture.runtime.isLayoutInProgress)
        let activity = fixture.activity

        // Runtime still owns its adapter and the forwarding provider. Only the
        // concrete data source dies; its real native lifetime proof must expire.
        source = nil

        XCTAssertNil(observedSource, "No fixture, row, request, or receipt may keep the data source alive")
        XCTAssertFalse(witnesses.generation.isCurrent)
        XCTAssertFalse(witnesses.request.isGenerationCurrent)
        assertRejected(receipt, by: fixture)
        XCTAssertEqual(fixture.activity, activity, "Lifetime revocation must be observed without another provider call")
        XCTAssertEqual(calls.rows, [0, 1, 2])
    }

    private func makeSource(calls: ReceiptRowCalls) throws -> RetainedLazyListDataSource<Int, [ViewNode]> {
        let source = RetainedLazyListDataSource<Int, [ViewNode]>()
        guard replaceRows(in: source, calls: calls) else { throw ReceiptFixtureError.configuration }
        return source
    }

    private func replaceRows(
        in source: RetainedLazyListDataSource<Int, [ViewNode]>, calls: ReceiptRowCalls
    ) -> Bool {
        source.replaceData([0, 1, 2], id: \.self, identityRoot: ReceiptFixture.identityRoot) { [calls] value, prefix in
            calls.rows.append(value)
            let row = ViewNode(preferredSize: Size(width: 120, height: 20))
            row.retainedViewIdentity = prefix.appending(.slot(0))
            row.dynamicContentIndex = value
            return [row]
        }
    }

    private func sourceWitnesses(
        _ source: RetainedLazyListDataSource<Int, [ViewNode]>?
    ) throws -> (generation: RetainedLazyListGeneration, request: RetainedLazyListRowRequest) {
        let source = try XCTUnwrap(source)
        let metadata = try XCTUnwrap(source.metadata)
        let row = try XCTUnwrap(metadata.rows.first)
        let request = try XCTUnwrap(source.request(for: row.token))
        return (metadata.generation, request)
    }

    private func assertRejected(
        _ receipt: RetainedLayoutSettlementReceipt, by fixture: ReceiptFixture,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertFalse(fixture.runtime.isLayoutSettlementReceiptCurrent(receipt), file: file, line: line)
        if case .settled = fixture.runtime.layoutSettlementStatus {
            XCTFail("A revoked source cannot leave its previous runtime receipt settled", file: file, line: line)
        }
        XCTAssertTrue(fixture.adapter.hasUnresolvedWork, file: file, line: line)
        XCTAssertTrue(fixture.runtime.canPrepareLayoutSettlement, file: file, line: line)
        XCTAssertFalse(fixture.runtime.hasActiveRetainedBuild, file: file, line: line)
    }
}

private enum ReceiptFixtureError: Error { case configuration, settlement }

@MainActor
private final class ReceiptRowCalls {
    var rows: [Int] = []
}

private struct ReceiptProviderCallCounts: Equatable {
    var metadata = 0
    var request = 0
    var current = 0
    var identity = 0
    var materialization = 0
}

/// Adapter owns this provider strongly. It deliberately forwards weakly to a
/// concrete data source so the lifetime test can release that source while
/// retaining the same runtime, attachment, and issued receipt.
@MainActor
private final class ReceiptProviderProbe: RetainedLazyListProvider {
    typealias RowContent = [ViewNode]
    private weak var source: RetainedLazyListDataSource<Int, [ViewNode]>?
    private(set) var calls = ReceiptProviderCallCounts()

    init(source: RetainedLazyListDataSource<Int, [ViewNode]>?) { self.source = source }

    var metadata: RetainedLazyListMetadata? {
        calls.metadata += 1
        return source?.metadata
    }

    func request(for token: RetainedLazyListRowToken) -> RetainedLazyListRowRequest? {
        calls.request += 1
        return source?.request(for: token)
    }

    func isCurrent(_ request: RetainedLazyListRowRequest) -> Bool {
        calls.current += 1
        return source?.isCurrent(request) == true
    }

    func identityPrefix(for request: RetainedLazyListRowRequest) -> RetainedViewIdentity? {
        calls.identity += 1
        return source?.identityPrefix(for: request)
    }

    func materialize(
        _ request: RetainedLazyListRowRequest, budget: RetainedLazyListWorkBudget
    ) -> RetainedLazyListMaterialization<[ViewNode]> {
        calls.materialization += 1
        return source?.materialize(request, budget: budget) ?? .obsolete
    }
}

private struct ReceiptActivity: Equatable {
    let layoutPass: UInt64
    let rowResolutions: Int
    let leaseBegins: Int
    let providerCalls: ReceiptProviderCallCounts
    let rowCalls: [Int]
    let retainedRows: [ObjectIdentifier]
}

@MainActor
private final class ReceiptFixture {
    static let identityRoot = RetainedViewIdentity(segments: [.role(.content), .slot(0)])
    let provider: ReceiptProviderProbe
    let calls: ReceiptRowCalls
    let adapter: RetainedLazyListRuntimeAdapter
    let lease: ReceiptBuildLease
    let list: ViewNode
    let runtime: RetainedViewRuntime

    init(provider: ReceiptProviderProbe, calls: ReceiptRowCalls) throws {
        let adapter = try XCTUnwrap(
            RetainedLazyListRuntimeAdapter(
                provider: provider, estimatedExtent: 20, prefetchExtent: 0,
                maximumMountedRecords: 4, maximumMountedLeaves: 4, maximumProtectedRecords: 1))
        let lease = ReceiptBuildLease()
        let list = ViewNode(layoutMode: .lazyStack(.vertical(spacing: 0, alignment: .stretch)))
        list.retainedLazyListAdapter = adapter
        list.retainedSubtreeBuildLease = lease
        let scroll = ViewNode(
            frame: Rect(x: 0, y: 0, width: 120, height: 60), clipsToBounds: true,
            layoutMode: .stack(.vertical(spacing: 0, alignment: .stretch)), scrollAxis: .vertical,
            children: [list])
        let runtime = RetainedViewRuntime(root: scroll)
        runtime.clock = { 0 }
        self.provider = provider
        self.calls = calls
        self.adapter = adapter
        self.lease = lease
        self.list = list
        self.runtime = runtime
    }

    var activity: ReceiptActivity {
        ReceiptActivity(
            layoutPass: runtime.layoutPassID, rowResolutions: runtime.lazyListResolveCount,
            leaseBegins: lease.beginCount, providerCalls: provider.calls, rowCalls: calls.rows,
            retainedRows: list.children.map(ObjectIdentifier.init))
    }

    func settledReceipt() throws -> RetainedLayoutSettlementReceipt {
        XCTAssertFalse(adapter.hasUnresolvedWork)
        XCTAssertEqual(runtime.lastLazyListWorkCompletion, .complete)
        XCTAssertFalse(runtime.hasActiveRetainedBuild)
        guard case .settled(let receipt) = runtime.layoutSettlementStatus else {
            XCTFail("The initial actual retained layout must settle before the source is revoked")
            throw ReceiptFixtureError.settlement
        }
        return receipt
    }
}

@MainActor
private final class ReceiptBuildLease: RetainedSubtreeBuildLease {
    private(set) var beginCount = 0
    var canBuild: Bool { true }

    func beginBuild() -> (any RetainedBuildEpoch)? {
        beginCount += 1
        return ReceiptBuildEpoch()
    }
}

@MainActor
private final class ReceiptBuildEpoch: RetainedBuildEpoch {
    private var prepared = false
    private var superseded = false
    var canAdopt: Bool { !prepared && !superseded }

    func supersede() {
        if !prepared { superseded = true }
    }

    func willAdopt() -> Bool {
        guard !prepared, !superseded else { return false }
        prepared = true
        return true
    }

    func commit() {}
    func abandon() {}
    func finishAfterCallbacks() {}
}
