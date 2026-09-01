import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Native capture tests exercise the same helper used by managed UIA
/// preparation. They do not grant a build or fabricate insertion completion.
/// The separate typed UIA cases cover the real request and its ordinary unwind;
/// the original four-round regression remains unchanged in its own file.
@MainActor
final class LazyListUIAInsertionOriginTests: XCTestCase {
    func testNativeUniverseIncludesOneOriginalPredecessorPerInitialTokenWithinThreeCaps() async throws {
        let fixture = try InsertionOriginNativeFixture()
        defer { fixture.source.close() }
        let initial = try [100, 300, 500, 700].map { try fixture.token($0) }
        let selection = try [10, 20, 30, 40].map { try fixture.token($0) }
        let predecessors = try [99, 299, 499, 699].map { try fixture.token($0) }
        let calls = fixture.provider.calls
        let factories = fixture.probe.factories
        let hashes = fixture.probe.hashes
        let equalities = fixture.probe.equalities

        for _ in 0..<3 {
            let tokens = try XCTUnwrap(fixture.adapter.uiAInsertionOriginTokens(initial: initial, selection: selection))
            XCTAssertEqual(tokens, initial + selection + predecessors)
            XCTAssertEqual(Set(tokens).count, 3 * 4)
            XCTAssertLessThanOrEqual(tokens.count, 3 * 4)
            XCTAssertNil(fixture.adapter.captureUIAInsertionOrigins(initial: initial, selection: selection))
        }

        XCTAssertEqual(fixture.provider.calls, calls, "Native planning cannot enter a provider")
        XCTAssertEqual(fixture.probe.factories, factories)
        XCTAssertEqual(fixture.probe.hashes, hashes)
        XCTAssertEqual(fixture.probe.equalities, equalities)
    }

    func testNativeUniverseRejectsUnknownTokensAndOversizedInputsWithoutProviderWork() async throws {
        let fixture = try InsertionOriginNativeFixture()
        defer { fixture.source.close() }
        let tokens = try [100, 200, 300, 400, 500].map { try fixture.token($0) }
        let foreign = RetainedLazyListDataSource<Int, [ViewNode]>()
        defer { foreign.close() }
        XCTAssertTrue(foreign.replaceData([1], id: \.self) { _ in [] })
        let unknown = try XCTUnwrap(foreign.metadata?.rows.first?.token)
        let calls = fixture.provider.calls
        let factories = fixture.probe.factories
        let hashes = fixture.probe.hashes
        let equalities = fixture.probe.equalities

        XCTAssertNil(fixture.adapter.uiAInsertionOriginTokens(initial: tokens, selection: []))
        XCTAssertNil(fixture.adapter.uiAInsertionOriginTokens(initial: [], selection: tokens))
        XCTAssertNil(fixture.adapter.uiAInsertionOriginTokens(initial: [unknown], selection: []))
        XCTAssertNil(fixture.adapter.uiAInsertionOriginTokens(initial: [], selection: [unknown]))
        let deduplicated = try XCTUnwrap(
            fixture.adapter.uiAInsertionOriginTokens(initial: [tokens[0], tokens[0]], selection: [tokens[0]]))
        XCTAssertEqual(deduplicated.count, 2, "The repeated original and its one unknown predecessor each occur once")
        XCTAssertEqual(deduplicated.first, tokens[0])
        XCTAssertEqual(fixture.provider.calls, calls)
        XCTAssertEqual(fixture.probe.factories, factories)
        XCTAssertEqual(fixture.probe.hashes, hashes)
        XCTAssertEqual(fixture.probe.equalities, equalities)
    }

    func testOriginalCaptureIncludesAppendedPredecessorAndKeepsItsExpiredEvent() async throws {
        let fixture = try InsertionOriginManagedFixture()
        defer { fixture.close() }
        fixture.probe.onNode = { [weak fixture] row, _ in
            guard let fixture, row == 0, fixture.probe.interventions == 0 else { return }
            fixture.probe.interventions += 1
            do {
                let target = try fixture.token(300)
                let predecessor = try fixture.token(299)
                let prefetch = try fixture.token(2)
                let outsideOriginalChoices = try fixture.token(298)
                let original = try XCTUnwrap(fixture.adapter.pendingInsertionEvent(for: predecessor))
                let factories = fixture.probe.factories
                let capture = try XCTUnwrap(
                    fixture.adapter.captureUIAInsertionOrigins(initial: [target], selection: [prefetch]))
                self.assertIntroduction(capture.origin(for: predecessor), is: original)
                XCTAssertTrue(original.isPending)

                original.expireIfPending()

                XCTAssertTrue(capture.isCurrent)
                self.assertIntroduction(capture.origin(for: predecessor), is: original)
                XCTAssertFalse(original.claim(RetainedLazyListInsertionClaimID()))
                XCTAssertNil(
                    capture.origin(for: outsideOriginalChoices), "No recursive predecessor acquires provenance")
                XCTAssertEqual(fixture.probe.factories, factories)
                XCTAssertFalse(factories.contains(299))
                XCTAssertFalse(factories.contains(300))
            } catch {
                XCTFail("The original native event must be available before these factories: \(error)")
            }
        }
        try fixture.introduce(Array(0..<1000))

        XCTAssertNotNil(fixture.host.layout())

        XCTAssertEqual(fixture.probe.interventions, 1)
        XCTAssertFalse(fixture.probe.factories.contains(299))
        XCTAssertFalse(fixture.probe.factories.contains(300))
    }

    func testOriginalSelectionPrefetchKeepsTheSameClaimedEventWithoutReclassification() async throws {
        let fixture = try InsertionOriginManagedFixture()
        defer { fixture.close() }
        fixture.probe.onNode = { [weak fixture] row, _ in
            guard let fixture, row == 0, fixture.probe.interventions == 0 else { return }
            fixture.probe.interventions += 1
            do {
                let target = try fixture.token(300)
                let prefetch = try fixture.token(2)
                let original = try XCTUnwrap(fixture.adapter.pendingInsertionEvent(for: prefetch))
                let capture = try XCTUnwrap(
                    fixture.adapter.captureUIAInsertionOrigins(initial: [target], selection: [prefetch]))
                let factories = fixture.probe.factories
                self.assertIntroduction(capture.origin(for: prefetch), is: original)
                let originalClaim = RetainedLazyListInsertionClaimID()
                XCTAssertTrue(original.claim(originalClaim))

                self.assertIntroduction(capture.origin(for: prefetch), is: original)
                XCTAssertTrue(capture.isCurrent)
                XCTAssertTrue(original.isClaimed(by: originalClaim))
                XCTAssertFalse(original.claim(RetainedLazyListInsertionClaimID()))
                XCTAssertEqual(fixture.probe.factories, factories)
                XCTAssertFalse(factories.contains(2), "The optional row has not run when its origin is captured")
            } catch {
                XCTFail("Selection prefetch must retain its original event: \(error)")
            }
        }
        try fixture.introduce(Array(0..<1000))

        _ = fixture.host.layout()

        XCTAssertEqual(fixture.probe.interventions, 1)
        XCTAssertFalse(fixture.probe.factories.contains(300))
    }

    func testSelectionPrefetchRetainsItsOriginalActualCohortAndRejectsIdentityABA() async throws {
        let fixture = try InsertionOriginManagedFixture(initialRows: Array(0..<1000))
        defer { fixture.close() }
        let target = try fixture.token(300)
        let prefetch = try fixture.token(2)
        let predecessor = try fixture.token(299)
        let node = try XCTUnwrap(fixture.adapter.mountedNodes(for: prefetch)?.first)
        let capture = try XCTUnwrap(
            fixture.adapter.captureUIAInsertionOrigins(initial: [target], selection: [prefetch]))
        let layout = try XCTUnwrap(fixture.adapter.captureLayoutProof())
        let attachment = node.captureLazyListAttachmentProof()
        let factories = fixture.probe.factories
        if case .existingRow? = capture.origin(for: prefetch) {
        } else {
            XCTFail("Expected the accepted prefetch cohort")
        }
        if case .materialization? = capture.origin(for: predecessor) {
        } else {
            XCTFail("Expected an unbuilt predecessor")
        }
        XCTAssertTrue(capture.isCurrent)
        let identity = node.retainedViewIdentity

        node.retainedViewIdentity = identity

        XCTAssertFalse(capture.isCurrent, "An equal assignment still revokes the original cohort")
        XCTAssertNil(capture.origin(for: prefetch))
        XCTAssertNil(
            capture.origin(for: predecessor), "A revoked capture cannot supply another originally classified row")
        XCTAssertTrue(layout.isCurrent)
        XCTAssertTrue(attachment.isCurrent)
        XCTAssertEqual(fixture.probe.factories, factories)
        XCTAssertFalse(factories.contains(299))
        XCTAssertFalse(factories.contains(300))
    }

    func testReplacementDescriptorCannotRefreshAnEscapedOriginalCapture() async throws {
        let fixture = try InsertionOriginManagedFixture(initialRows: Array(0..<1000))
        defer { fixture.close() }
        let target = try fixture.token(300)
        let prefetch = try fixture.token(2)
        let capture = try XCTUnwrap(
            fixture.adapter.captureUIAInsertionOrigins(initial: [target], selection: [prefetch]))
        let factories = fixture.probe.factories
        XCTAssertTrue(capture.isCurrent)

        fixture.host.reload()

        XCTAssertFalse(capture.isCurrent)
        XCTAssertNil(capture.origin(for: target))
        XCTAssertNil(capture.origin(for: prefetch))
        XCTAssertEqual(fixture.probe.factories, factories, "Descriptor publication itself cannot execute a row factory")
        XCTAssertFalse(fixture.host.runtime.hasActiveRetainedBuild)
    }

    func testOrdinaryNilHintInsertionStillUsesItsAcceptedTransaction() async throws {
        let fixture = try InsertionOriginManagedFixture(prefetchExtent: 0)
        defer { fixture.close() }
        var clocks = 0
        fixture.host.runtime.clock = {
            clocks += 1
            return 12
        }
        try fixture.introduce([1])

        XCTAssertNotNil(fixture.host.layout())

        let row = try XCTUnwrap(fixture.host.find(insertionOriginIdentifier(1)))
        let insertion = try XCTUnwrap(row.animationStates[.opacity])
        XCTAssertEqual(fixture.probe.factories, [1])
        XCTAssertEqual(clocks, 1)
        XCTAssertEqual(insertion.startTime, 12)
        XCTAssertEqual(insertion.duration, 2)
        XCTAssertEqual(insertion.startValue, 0)
        XCTAssertEqual(insertion.endValue, 0.8)
        XCTAssertTrue(row.didPlayInsertionTransition)
        XCTAssertFalse(fixture.host.runtime.hasActiveRetainedBuild)
        try fixture.host.assertCommittedDescriptor()
    }

    func testOriginalCurrentManagedHintFinishesTheTypedRequestWithinItsExplicitAllowance() async throws {
        let fixture = try InsertionOriginUIAFixture()
        defer { fixture.close() }
        let element = try fixture.item(at: 300)
        let start = fixture.probe.factories.count
        XCTAssertFalse(fixture.probe.factories.contains(300))

        let completed = fixture.source.uiaRealizeVirtualizedItem(elementID: element)

        XCTAssertTrue(completed)
        XCTAssertEqual(fixture.source.uiaLogicalItemState(elementID: element), .ordinary)
        XCTAssertEqual(fixture.probe.factories.filter { $0 == 300 }.count, 1)
        XCTAssertLessThan(fixture.probe.factories.count - start, 128)
        XCTAssertLessThanOrEqual(fixture.host.runtime.lastLazyListConsumedElements, 128)
        XCTAssertLessThanOrEqual(fixture.host.runtime.lastLazyListConsumedRounds, 16)
        XCTAssertTrue(fixture.host.runtime.hasCurrentAccessibilityPrepaint)
        XCTAssertFalse(fixture.host.runtime.hasActiveRetainedBuild)
        guard case .settled(let receipt) = fixture.host.runtime.layoutSettlementStatus else {
            return XCTFail("The typed call must finish its own settlement")
        }
        XCTAssertTrue(fixture.host.runtime.isLayoutSettlementReceiptCurrent(receipt))
    }

    func testManagedHintStopsAfterFactoryRevokesAndRestoresScrollIntent() async throws {
        let fixture = try InsertionOriginUIAFixture()
        defer { fixture.close() }
        let element = try fixture.item(at: 300)
        let scroll = try fixture.host.scrollContainer()
        let start = fixture.probe.factories.count
        fixture.probe.onFactory = { [weak fixture, weak scroll] id in
            guard let fixture, let scroll, id == 300 else { return }
            fixture.probe.interventions += 1
            let original = scroll.scrollOffset
            scroll.scrollOffset = original + 1
            scroll.scrollOffset = original
        }

        let completed = fixture.source.uiaRealizeVirtualizedItem(elementID: element)

        XCTAssertFalse(completed)
        XCTAssertEqual(fixture.probe.interventions, 1)
        XCTAssertEqual(Array(fixture.probe.factories.dropFirst(start)), [300])
        XCTAssertEqual(scroll.scrollOffset, 0)
        XCTAssertFalse(
            fixture.probe.factories.contains(299), "The revoked operation cannot enter its later predecessor")
        XCTAssertFalse(fixture.probe.bodies.contains(300), "Revocation also stops the returned authored body")
        XCTAssertFalse(fixture.host.runtime.hasActiveRetainedBuild)
        XCTAssertEqual(fixture.source.uiaLogicalItemState(elementID: element), .placeholder)
    }

    func testManagedHintHostCloseStillFinishesTheStartedBuildAndEpoch() async throws {
        let fixture = try InsertionOriginUIAFixture()
        defer { fixture.close() }
        let element = try fixture.item(at: 300)
        let start = fixture.probe.factories.count
        fixture.probe.onBody = { [weak fixture] id in
            guard let fixture, id == 300 else { return }
            fixture.probe.interventions += 1
            fixture.probe.closingEpoch = ViewBuildContextScope.current?.viewIdentity.installedEpoch
            XCTAssertNotNil(fixture.probe.closingEpoch)
            XCTAssertTrue(fixture.host.runtime.hasActiveRetainedBuild)
            fixture.host.close()
        }

        let completed = fixture.source.uiaRealizeVirtualizedItem(elementID: element)

        XCTAssertFalse(completed)
        XCTAssertEqual(fixture.probe.interventions, 1)
        XCTAssertEqual(Array(fixture.probe.factories.dropFirst(start)), [300])
        XCTAssertEqual(fixture.probe.bodies.filter { $0 == 300 }.count, 1)
        XCTAssertTrue(fixture.host.isClosed)
        XCTAssertTrue(fixture.host.coordinator.registry.isClosed)
        XCTAssertFalse(fixture.host.runtime.hasActiveRetainedBuild)
        XCTAssertEqual(fixture.host.coordinator.registry.liveOwnerCount, 0)
        XCTAssertEqual(fixture.host.coordinator.registry.retiringOwnerCount, 0)
        XCTAssertNil(fixture.probe.closingEpoch, "Ordinary finishAfterCallbacks must run after authority is revoked")
    }

    private func assertIntroduction(
        _ origin: RetainedLazyListInsertionOrigin?, is event: RetainedLazyListInsertionEvent,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        guard case .logicalIntroduction(let captured)? = origin else {
            return XCTFail("Expected the original logical introduction, not materialization", file: file, line: line)
        }
        XCTAssertTrue(captured === event, file: file, line: line)
    }
}

@MainActor
private final class InsertionOriginNativeProbe {
    var factories: [Int] = []
    var hashes = 0
    var equalities = 0
}

private struct InsertionOriginNativeKey: Hashable {
    let value: Int
    let probe: InsertionOriginNativeProbe

    static func == (lhs: Self, rhs: Self) -> Bool {
        MainActor.assumeIsolated { lhs.probe.equalities += 1 }
        return lhs.value == rhs.value
    }

    func hash(into hasher: inout Hasher) {
        MainActor.assumeIsolated { probe.hashes += 1 }
        hasher.combine(value)
    }
}

@MainActor
private final class InsertionOriginNativeProvider: RetainedLazyListProvider {
    typealias RowContent = [ViewNode]
    let source: RetainedLazyListDataSource<InsertionOriginNativeKey, [ViewNode]>
    var calls: [String] = []

    init(_ source: RetainedLazyListDataSource<InsertionOriginNativeKey, [ViewNode]>) { self.source = source }

    var metadata: RetainedLazyListMetadata? {
        calls.append("metadata")
        return source.metadata
    }

    func token(for key: RetainedViewIdentity.Key, occurrence: Int) -> RetainedLazyListRowToken? {
        calls.append("token")
        return source.token(for: key, occurrence: occurrence)
    }

    func request(for token: RetainedLazyListRowToken) -> RetainedLazyListRowRequest? {
        calls.append("request")
        return source.request(for: token)
    }

    func isCurrent(_ request: RetainedLazyListRowRequest) -> Bool {
        calls.append("current")
        return source.isCurrent(request)
    }

    func identityPrefix(for request: RetainedLazyListRowRequest) -> RetainedViewIdentity? {
        calls.append("identity")
        return source.identityPrefix(for: request)
    }

    func materialize(
        _ request: RetainedLazyListRowRequest, budget: RetainedLazyListWorkBudget
    ) -> RetainedLazyListMaterialization<[ViewNode]> {
        calls.append("materialize")
        return source.materialize(request, budget: budget)
    }
}

@MainActor
private final class InsertionOriginNativeFixture {
    let probe: InsertionOriginNativeProbe
    let source: RetainedLazyListDataSource<InsertionOriginNativeKey, [ViewNode]>
    let provider: InsertionOriginNativeProvider
    let adapter: RetainedLazyListRuntimeAdapter

    init() throws {
        let probe = InsertionOriginNativeProbe()
        let source = RetainedLazyListDataSource<InsertionOriginNativeKey, [ViewNode]>()
        self.probe = probe
        self.source = source
        XCTAssertTrue(
            source.replaceData((0..<1000).map { InsertionOriginNativeKey(value: $0, probe: probe) }, id: \.self) {
                key in
                probe.factories.append(key.value)
                return [ViewNode(frame: Rect(x: 0, y: 0, width: 120, height: 20))]
            })
        let provider = InsertionOriginNativeProvider(source)
        self.provider = provider
        adapter = try XCTUnwrap(
            RetainedLazyListRuntimeAdapter(
                provider: provider, estimatedExtent: 20, prefetchExtent: 0,
                maximumMountedRecords: 4, maximumMountedLeaves: 4, maximumProtectedRecords: 2))
        let context = try XCTUnwrap(
            RetainedLazyListMeasurementContext(width: 120, displayScale: 1, contentRevision: 0, environmentRevision: 0))
        let viewport = try XCTUnwrap(RetainedLazyListRuntimeAdapter.Viewport(context: context, offset: 0, extent: 40))
        let budget = try XCTUnwrap(RetainedLazyListWorkBudget(elementLimit: 32, roundLimit: 4))
        let result = adapter.prepare(viewport: viewport, protectedRoots: [], budget: budget)
        var prepared: RetainedLazyListRuntimeAdapter.Candidate?
        if case .ready(let candidate) = result { prepared = candidate }
        let candidate = try XCTUnwrap(prepared, "Expected the original ordinary raw preparation")
        XCTAssertTrue(adapter.complete(candidate: candidate, adoptedChildren: candidate.children))
        let measurements = adapter.layoutPlan(viewport: viewport).placements.map {
            RetainedLazyListRuntimeAdapter.Measurement(
                token: $0.token, leafIndex: $0.leafIndex, node: $0.node, extent: 20)
        }
        _ = try XCTUnwrap(adapter.recordMeasurements(measurements, viewport: viewport))
        XCTAssertEqual(probe.factories, [0, 1])
    }

    func token(_ index: Int) throws -> RetainedLazyListRowToken {
        try XCTUnwrap(source.metadata?.rows[index].token)
    }
}

@MainActor
private final class InsertionOriginManagedProbe {
    var rows: [Int]
    var factories: [Int] = []
    var interventions = 0
    var onNode: (@MainActor (Int, ViewBuildContext) -> Void)?

    init(rows: [Int]) { self.rows = rows }

    func makeNode(_ id: Int, context: ViewBuildContext) -> ViewNode {
        factories.append(id)
        let node = ViewNode(frame: Rect(x: 0, y: 0, width: 120, height: 20))
        node.accessibilityIdentifier = insertionOriginIdentifier(id)
        node.opacity = 0.8
        node.transition = RetainedTransition(kind: .asymmetric(insertion: .init(kind: .opacity), removal: .identity))
        onNode?(id, context)
        return node
    }
}

@MainActor
private struct InsertionOriginManagedLeaf: View {
    typealias Body = Never
    let id: Int
    let probe: InsertionOriginManagedProbe
    var body: Never { fatalError("Primitive") }

    func makeComponent(context: ViewBuildContext) -> Component {
        Component { _ in probe.makeNode(id, context: context) }
    }
}

@MainActor
private final class InsertionOriginManagedFixture {
    let probe: InsertionOriginManagedProbe
    let host: MountedLazyListTestHost
    private(set) var adapter: RetainedLazyListRuntimeAdapter

    init(initialRows: [Int] = [], prefetchExtent: Double = 40) throws {
        let probe = InsertionOriginManagedProbe(rows: initialRows)
        self.probe = probe
        let host = MountedLazyListTestHost(size: Size(width: 120, height: 40)) {
            ManagedLazyListContent(
                probe.rows, id: \.self, estimatedExtent: 20, prefetchExtent: prefetchExtent,
                maximumMountedRecords: 8, maximumMountedLeaves: 8, maximumProtectedRecords: 2
            ) { row in
                InsertionOriginManagedLeaf(id: row, probe: probe)
            }
        }
        self.host = host
        XCTAssertNotNil(host.layout())
        adapter = try XCTUnwrap(try host.list().retainedLazyListAdapter)
    }

    func token(_ id: Int) throws -> RetainedLazyListRowToken {
        try XCTUnwrap(adapter.token(for: RetainedViewIdentity.Key(id)))
    }

    func introduce(_ rows: [Int]) throws {
        probe.rows = rows
        withAnimation(.linear(duration: 2)) { host.reload() }
        adapter = try XCTUnwrap(try host.list().retainedLazyListAdapter)
        XCTAssertTrue(probe.factories.isEmpty)
    }

    func close() {
        probe.onNode = nil
        host.runtime.clock = { 0 }
        host.close()
    }
}

private func insertionOriginIdentifier(_ id: Int) -> String { "uia.insertion.origin.\(id)" }

@MainActor
private final class InsertionOriginUIAProbe {
    var factories: [Int] = []
    var bodies: [Int] = []
    var interventions = 0
    var onFactory: (@MainActor (Int) -> Void)?
    var onBody: (@MainActor (Int) -> Void)?
    weak var closingEpoch: StateMountEpoch?

    func makeRows(_ id: Int) -> [AnyView] {
        factories.append(id)
        onFactory?(id)
        return [AnyView(InsertionOriginUIARow(id: id, probe: self))]
    }

    func recordBody(_ id: Int) {
        bodies.append(id)
        onBody?(id)
    }
}

@MainActor
private struct InsertionOriginUIARow: View {
    let id: Int
    let probe: InsertionOriginUIAProbe

    var body: some View {
        probe.recordBody(id)
        return Text("Row \(id)").frame(height: 24)
    }
}

@MainActor
private final class InsertionOriginUIAFixture {
    let probe = InsertionOriginUIAProbe()
    let host: MountedLazyListTestHost
    let source: RuntimeUIAElementTreeSource
    let containerID: UInt64

    init() throws {
        let probe = probe
        host = MountedLazyListTestHost(size: Size(width: 320, height: 80)) {
            List(Array(0..<1000), id: \.self) { probe.makeRows($0) }.listStyle(.plain)
        }
        source = RuntimeUIAElementTreeSource(runtime: host.runtime)
        XCTAssertTrue(host.runtime.configureLazyListResolutionBudget(elementLimit: 128, roundLimit: 16))
        do {
            XCTAssertNotNil(host.layout())
            containerID = try XCTUnwrap(source.uiaElementSnapshots().first(where: \.supportsItemContainer)?.id)
        } catch {
            host.close()
            throw error
        }
    }

    func item(at index: Int) throws -> UInt64 {
        var previous: UInt64?
        for _ in 0...index {
            let result = source.uiaFindItem(containerID: containerID, afterElementID: previous)
            guard case .item(let id) = result else {
                XCTFail("Expected the next current logical item, got \(result)")
                return try XCTUnwrap(nil as UInt64?)
            }
            previous = id
        }
        return try XCTUnwrap(previous)
    }

    func close() {
        probe.onFactory = nil
        probe.onBody = nil
        host.close()
    }
}
