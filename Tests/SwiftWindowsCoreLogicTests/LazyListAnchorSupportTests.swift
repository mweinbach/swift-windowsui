import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Native mapping exercises the production capture/selection helpers without
/// granting construction. Public cases use ordinary managed acceptance/layout.
@MainActor
final class LazyListAnchorSupportTests: XCTestCase {
    func testGenericPreparationMeasuresOriginalMountedPrefixBeforeCorrectingAnchor() async throws {
        let fixture = try AnchorSupportPublicFixture()
        defer { fixture.close() }
        let originalFactories = fixture.probe.factories.count
        fixture.stageReplacement()

        let current = try XCTUnwrap(try fixture.prepare())

        XCTAssertEqual(current.token, fixture.original.token)
        XCTAssertTrue(fixture.host.runtime.isLazyListAccessibilityItemCurrent(current))
        XCTAssertFalse(fixture.host.runtime.isLazyListAccessibilityItemCurrent(fixture.original))
        XCTAssertEqual(fixture.scroll.scrollOffset, fixture.originalOffset + 40, accuracy: 0.001)
        XCTAssertEqual(
            try fixture.host.rowRoot(anchorSupportPublicIdentifier(2)).resolvedFrame.height,
            fixture.originalHeight + 40, accuracy: 0.001)
        let third = try fixture.host.rowRoot(anchorSupportPublicIdentifier(3))
        XCTAssertEqual(
            third.resolvedFrame.minY - fixture.scroll.resolvedScrollOffset, fixture.anchorTop, accuracy: 0.001)
        XCTAssertTrue(Set(fixture.probe.factories.dropFirst(originalFactories)).isSuperset(of: [0, 1, 2, 3]))
        XCTAssertFalse(fixture.probe.factories.contains(300))
        XCTAssertLessThanOrEqual(fixture.host.runtime.lastLazyListConsumedElements, 128)
        XCTAssertLessThanOrEqual(fixture.host.runtime.lastLazyListConsumedRounds, 4)
        XCTAssertFalse(fixture.host.runtime.hasPendingLayout)
        XCTAssertFalse(fixture.host.runtime.hasActiveRetainedBuild)
        XCTAssertTrue(fixture.probe.activations.isEmpty)
    }

    func testAcceptedReorderMeasuresNewPredecessorOrderWithoutBorrowingOldHeights() async throws {
        let fixture = try AnchorSupportPublicFixture()
        defer { fixture.close() }
        fixture.probe.rows.swapAt(0, 2)
        fixture.stageReplacement()

        XCTAssertNotNil(try fixture.prepare())

        let moved = try fixture.host.rowRoot(anchorSupportPublicIdentifier(2))
        let later = try fixture.host.rowRoot(anchorSupportPublicIdentifier(0))
        XCTAssertEqual(moved.resolvedFrame.height, fixture.originalHeight + 40, accuracy: 0.001)
        XCTAssertLessThan(moved.resolvedFrame.minY, later.resolvedFrame.minY)
        XCTAssertEqual(fixture.scroll.scrollOffset, fixture.originalOffset + 40, accuracy: 0.001)
        let third = try fixture.host.rowRoot(anchorSupportPublicIdentifier(3))
        XCTAssertEqual(
            third.resolvedFrame.minY - fixture.scroll.resolvedScrollOffset, fixture.anchorTop, accuracy: 0.001)
        XCTAssertFalse(fixture.probe.factories.contains(300))
        XCTAssertLessThanOrEqual(fixture.host.runtime.lastLazyListConsumedElements, 128)
        XCTAssertLessThanOrEqual(fixture.host.runtime.lastLazyListConsumedRounds, 4)
        XCTAssertFalse(fixture.host.runtime.hasPendingLayout)
    }

    func testNativeSelectionUsesNewOrderAndDoesNotEnterAuthoredKeysOrFactories() async throws {
        let fixture = try AnchorSupportManagedFixture()
        defer { fixture.close() }
        let anchor = try fixture.token(2)
        let factories = fixture.probe.factories
        let hashes = fixture.probe.hashes
        let equalities = fixture.probe.equalities
        let original = try XCTUnwrap(fixture.adapter.captureAnchorSupport(preserving: anchor))

        let selected = try XCTUnwrap(try fixture.select(original, order: [4, 1, 2, 0, 3]))

        XCTAssertEqual(selected.tokens, Set(try [4, 1, 2].map { try fixture.token($0) }))
        XCTAssertEqual(original.tokens.count, 5)
        XCTAssertEqual(selected.tokens.count, 3)
        XCTAssertTrue(selected.isCurrent)
        XCTAssertFalse(selected.tokens.contains(try fixture.token(0)))
        XCTAssertFalse(selected.tokens.contains(try fixture.token(3)))
        XCTAssertLessThanOrEqual(original.tokens.count, 8)
        XCTAssertLessThanOrEqual(fixture.adapter.mountedLeafCount, 8)
        XCTAssertEqual(fixture.probe.factories, factories)
        XCTAssertEqual(fixture.probe.hashes, hashes)
        XCTAssertEqual(fixture.probe.equalities, equalities)
    }

    func testMissingOriginalPredecessorDeclinesTheWholePrefixWithoutNewWork() async throws {
        let fixture = try AnchorSupportManagedFixture()
        defer { fixture.close() }
        let original = try XCTUnwrap(fixture.adapter.captureAnchorSupport(preserving: try fixture.token(2)))
        let factories = fixture.probe.factories
        let hashes = fixture.probe.hashes
        let equalities = fixture.probe.equalities

        XCTAssertNil(try fixture.select(original, order: [0, 5, 2, 1, 3, 4]))
        XCTAssertNil(fixture.adapter.captureAnchorSupport(preserving: try fixture.token(300)))

        XCTAssertTrue(original.isCurrent)
        XCTAssertEqual(original.tokens, Set(try [0, 1, 2, 3, 4].map { try fixture.token($0) }))
        XCTAssertFalse(original.tokens.contains(try fixture.token(5)))
        XCTAssertEqual(fixture.probe.factories, factories)
        XCTAssertEqual(fixture.probe.hashes, hashes)
        XCTAssertEqual(fixture.probe.equalities, equalities)
    }

    func testOrdinalOutsideFrozenCohortCountCannotGrowThePrefixAllowance() async throws {
        let fixture = try AnchorSupportManagedFixture()
        defer { fixture.close() }
        let anchor = try fixture.token(2)
        let original = try XCTUnwrap(fixture.adapter.captureAnchorSupport(preserving: anchor))
        let factories = fixture.probe.factories

        XCTAssertNil(try fixture.select(original, order: [0, 1, 3, 4, 5, 2]))
        XCTAssertNil(original.selectingPrefix(tokens: [anchor], positions: [anchor: Int.max]))
        XCTAssertNil(original.selectingPrefix(tokens: [anchor], positions: [anchor: -1]))

        XCTAssertEqual(original.tokens.count, 5)
        XCTAssertTrue(original.isCurrent)
        XCTAssertEqual(fixture.probe.factories, factories)
    }

    func testInitiallyInvalidDependencyDeclinesWithoutRejectingAnIndependentPrefix() async throws {
        let fixture = try AnchorSupportManagedFixture()
        defer { fixture.close() }
        let invalid = try fixture.node(0)
        let identity = invalid.retainedViewIdentity
        invalid.retainedViewIdentity = identity
        let original = try XCTUnwrap(fixture.adapter.captureAnchorSupport(preserving: try fixture.token(2)))
        let factories = fixture.probe.factories

        XCTAssertNil(try fixture.select(original, order: [0, 1, 2, 3, 4]))
        let independent = try XCTUnwrap(try fixture.select(original, order: [2, 1, 0, 3, 4]))

        XCTAssertFalse(original.tokens.contains(try fixture.token(0)))
        XCTAssertEqual(independent.tokens, [try fixture.token(2)])
        XCTAssertTrue(independent.isCurrent)
        XCTAssertEqual(fixture.probe.factories, factories)
    }

    func testSelectedOriginalIdentityABARemainsObsoleteInsteadOfBeingRecaptured() async throws {
        let fixture = try AnchorSupportManagedFixture()
        defer { fixture.close() }
        let original = try XCTUnwrap(fixture.adapter.captureAnchorSupport(preserving: try fixture.token(2)))
        let invalid = try fixture.node(0)
        let layout = try XCTUnwrap(fixture.adapter.captureLayoutProof())
        let attachment = invalid.captureLazyListAttachmentProof()
        let factories = fixture.probe.factories
        let identity = invalid.retainedViewIdentity

        invalid.retainedViewIdentity = identity

        let selected = try XCTUnwrap(try fixture.select(original, order: [0, 1, 2, 3, 4]))
        XCTAssertEqual(selected.tokens, Set(try [0, 1, 2].map { try fixture.token($0) }))
        XCTAssertFalse(selected.isCurrent, "A lost selected original is obsolete, not an initially missing prefix")
        XCTAssertFalse(original.isCurrent)
        XCTAssertTrue(layout.isCurrent)
        XCTAssertTrue(attachment.isCurrent)
        XCTAssertEqual(fixture.probe.factories, factories)
    }

    func testUnselectedDeletedOriginalDoesNotRejectTheCompleteSurvivingPrefix() async throws {
        let fixture = try AnchorSupportManagedFixture()
        defer { fixture.close() }
        let original = try XCTUnwrap(fixture.adapter.captureAnchorSupport(preserving: try fixture.token(2)))
        let factories = fixture.probe.factories
        fixture.probe.rows.removeAll { $0.value == 4 }

        fixture.host.reload()

        let selected = try XCTUnwrap(try fixture.select(original, order: [0, 1, 2, 3]))
        XCTAssertTrue(original.tokens.contains(try fixture.token(4)))
        XCTAssertFalse(original.isCurrent)
        XCTAssertEqual(selected.tokens, Set(try [0, 1, 2].map { try fixture.token($0) }))
        XCTAssertTrue(selected.isCurrent)
        XCTAssertEqual(fixture.probe.factories, factories, "Descriptor publication cannot evaluate row factories")
        XCTAssertFalse(fixture.host.runtime.hasActiveRetainedBuild)
    }

    func testCapturedProofsDoNotRetainClosedPhysicalRows() async throws {
        let fixture = try AnchorSupportManagedFixture()
        defer { fixture.close() }
        let original = try XCTUnwrap(fixture.adapter.captureAnchorSupport(preserving: try fixture.token(2)))
        let selected = try XCTUnwrap(try fixture.select(original, order: [0, 1, 2, 3, 4]))
        weak var actual = try fixture.node(0)

        fixture.close()

        XCTAssertNil(actual)
        XCTAssertFalse(original.isCurrent)
        XCTAssertFalse(selected.isCurrent)
        XCTAssertEqual(fixture.adapter.mountedRecordCount, 0)
        XCTAssertEqual(fixture.adapter.mountedLeafCount, 0)
    }

    func testRevocationInFirstRefreshFactoryStopsLaterSupportWorkAndRunsCleanup() async throws {
        let fixture = try AnchorSupportPublicFixture()
        defer { fixture.close() }
        fixture.stageReplacement()
        let start = fixture.probe.factories.count
        var interventions = 0
        fixture.probe.onFactory = { [weak host = fixture.host] _ in
            guard interventions == 0 else { return }
            interventions += 1
            host?.close()
        }

        XCTAssertNil(try fixture.prepare())

        XCTAssertEqual(interventions, 1)
        XCTAssertEqual(Array(fixture.probe.factories.dropFirst(start)), [0])
        XCTAssertTrue(fixture.host.isClosed)
        XCTAssertTrue(fixture.host.coordinator.registry.isClosed)
        XCTAssertFalse(fixture.host.runtime.hasActiveRetainedBuild)
        XCTAssertEqual(fixture.scroll.scrollOffset, fixture.originalOffset, accuracy: 0.001)
        XCTAssertFalse(fixture.probe.factories.contains(300))
    }

    func testOneElementOneRoundCannotBorrowOldPredecessorMeasurements() async throws {
        let fixture = try AnchorSupportPublicFixture()
        defer { fixture.close() }
        fixture.stageReplacement()
        XCTAssertTrue(fixture.host.runtime.configureLazyListResolutionBudget(elementLimit: 1, roundLimit: 1))
        let start = fixture.probe.factories.count

        XCTAssertNil(try fixture.prepare())

        XCTAssertEqual(Array(fixture.probe.factories.dropFirst(start)), [0])
        XCTAssertEqual(fixture.host.runtime.lastLazyListConsumedElements, 1)
        XCTAssertEqual(fixture.host.runtime.lastLazyListConsumedRounds, 1)
        XCTAssertEqual(fixture.scroll.scrollOffset, fixture.originalOffset, accuracy: 0.001)
        XCTAssertEqual(
            try fixture.host.rowRoot(anchorSupportPublicIdentifier(2)).resolvedFrame.height,
            fixture.originalHeight, accuracy: 0.001)
        let adapter = try XCTUnwrap(try fixture.host.list().retainedLazyListAdapter)
        XCTAssertTrue(adapter.hasUnresolvedWork)
        XCTAssertLessThanOrEqual(adapter.mountedRecordCount, 512)
        XCTAssertLessThanOrEqual(adapter.mountedLeafCount, 4096)
        XCTAssertFalse(fixture.probe.factories.contains(300))
        XCTAssertFalse(fixture.host.runtime.hasActiveRetainedBuild)
    }

    func testManagedNilAnchorKeepsOnlyOriginalRequirementsUnderOneElementBudget() async throws {
        let fixture = try AnchorSupportManagedFixture()
        defer { fixture.close() }
        XCTAssertEqual(try fixture.host.scrollContainer().scrollOffset, 0)
        XCTAssertEqual(fixture.adapter.mountedRecordCount, 5)
        fixture.host.reload()
        XCTAssertTrue(fixture.host.runtime.configureLazyListResolutionBudget(elementLimit: 1, roundLimit: 1))
        let start = fixture.probe.factories.count

        _ = fixture.host.layout()

        let successor = try XCTUnwrap(try fixture.host.list().retainedLazyListAdapter)
        XCTAssertEqual(Array(fixture.probe.factories.dropFirst(start)), [0])
        XCTAssertEqual(successor.mountedRecordCount, 2)
        XCTAssertEqual(successor.mountedLeafCount, 2)
        XCTAssertTrue(successor.hasUnresolvedWork)
        XCTAssertEqual(fixture.host.runtime.lastLazyListConsumedElements, 1)
        XCTAssertEqual(fixture.host.runtime.lastLazyListConsumedRounds, 1)
        XCTAssertFalse(fixture.host.runtime.hasActiveRetainedBuild)
    }

    func testRawPreparationDoesNotAcquireManagedAnchorSupport() async throws {
        let source = RetainedLazyListDataSource<Int, [ViewNode]>()
        defer { source.close() }
        var factories: [Int] = []
        XCTAssertTrue(
            source.replaceData(Array(0..<1000), id: \.self) { id in
                factories.append(id)
                return [ViewNode(frame: Rect(x: 0, y: 0, width: 120, height: 20))]
            })
        let adapter = try XCTUnwrap(
            RetainedLazyListRuntimeAdapter(
                provider: source, estimatedExtent: 20, prefetchExtent: 0,
                maximumMountedRecords: 4, maximumMountedLeaves: 4, maximumProtectedRecords: 1))
        let context = try XCTUnwrap(
            RetainedLazyListMeasurementContext(width: 120, displayScale: 1, contentRevision: 0, environmentRevision: 0))
        let viewport = try XCTUnwrap(RetainedLazyListRuntimeAdapter.Viewport(context: context, offset: 0, extent: 40))
        let budget = try XCTUnwrap(RetainedLazyListWorkBudget(elementLimit: 4, roundLimit: 1))
        guard
            case .ready(let candidate) = adapter.prepare(
                viewport: viewport, protectedRoots: [], budget: budget)
        else {
            return XCTFail("Expected the unchanged raw preparation")
        }
        XCTAssertTrue(adapter.complete(candidate: candidate, adoptedChildren: candidate.children))
        let anchor = try XCTUnwrap(adapter.captureAnchor(at: 21))

        XCTAssertNil(adapter.captureAnchorSupport(preserving: anchor.token))

        XCTAssertEqual(factories, [0, 1])
        XCTAssertEqual(adapter.mountedRecordCount, 2)
        XCTAssertEqual(adapter.mountedLeafCount, 2)
        XCTAssertEqual(budget.remainingElements, 2)
        XCTAssertEqual(budget.remainingRounds, 1, "Only Runtime consumes convergence rounds")
    }
}

private struct AnchorSupportKey: Hashable {
    let value: Int
    let probe: AnchorSupportManagedProbe

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
private final class AnchorSupportManagedProbe {
    var rows: [AnchorSupportKey] = []
    var factories: [Int] = []
    var hashes = 0
    var equalities = 0
}

@MainActor
private struct AnchorSupportManagedLeaf: View {
    typealias Body = Never
    let id: Int
    let probe: AnchorSupportManagedProbe
    var body: Never { fatalError("Primitive") }

    func makeComponent(context: ViewBuildContext) -> Component {
        Component { _ in
            probe.factories.append(id)
            let node = ViewNode(frame: Rect(x: 0, y: 0, width: 120, height: 20))
            node.accessibilityIdentifier = "anchor.support.managed.\(id)"
            return node
        }
    }
}

@MainActor
private final class AnchorSupportManagedFixture {
    let probe: AnchorSupportManagedProbe
    let host: MountedLazyListTestHost
    let adapter: RetainedLazyListRuntimeAdapter
    private let tokensByID: [Int: RetainedLazyListRowToken]

    init() throws {
        let probe = AnchorSupportManagedProbe()
        probe.rows = (0..<1000).map { AnchorSupportKey(value: $0, probe: probe) }
        self.probe = probe
        let host = MountedLazyListTestHost {
            ManagedLazyListContent(
                probe.rows, id: \.self, estimatedExtent: 20, prefetchExtent: 60,
                maximumMountedRecords: 8, maximumMountedLeaves: 8, maximumProtectedRecords: 2
            ) { row in
                AnchorSupportManagedLeaf(id: row.value, probe: probe)
            }
        }
        self.host = host
        XCTAssertNotNil(host.layout())
        let adapter = try XCTUnwrap(try host.list().retainedLazyListAdapter)
        self.adapter = adapter
        let source = try XCTUnwrap(adapter.dataSource(for: AnchorSupportKey.self))
        let metadata = try XCTUnwrap(source.metadata)
        var tokens: [Int: RetainedLazyListRowToken] = [:]
        for (key, row) in zip(probe.rows, metadata.rows) { tokens[key.value] = row.token }
        tokensByID = tokens
        XCTAssertEqual(probe.factories, [0, 1, 2, 3, 4])
    }

    func token(_ id: Int) throws -> RetainedLazyListRowToken {
        try XCTUnwrap(tokensByID[id])
    }

    func node(_ id: Int) throws -> ViewNode {
        try XCTUnwrap(adapter.mountedNodes(for: try token(id))?.first)
    }

    func select(
        _ original: RetainedLazyListRuntimeAdapter.AnchorSupport, order: [Int]
    ) throws -> RetainedLazyListRuntimeAdapter.AnchorSupport? {
        let tokens = try order.map { try token($0) }
        let positions = Dictionary(uniqueKeysWithValues: tokens.enumerated().map { ($0.element, $0.offset) })
        return original.selectingPrefix(tokens: tokens, positions: positions)
    }

    func close() {
        host.close()
        probe.rows = []
    }
}

@MainActor
private final class AnchorSupportPublicProbe {
    var rows = Array(0..<1000)
    var heights: [Int: Double] = [:]
    var factories: [Int] = []
    var activations: [Int] = []
    var onFactory: (@MainActor (Int) -> Void)?

    func makeRows(_ id: Int) -> [AnyView] {
        factories.append(id)
        onFactory?(id)
        return [
            AnyView(
                Button("Row \(id)") { [weak self] in self?.activations.append(id) }
                    .accessibilityIdentifier(anchorSupportPublicIdentifier(id))
                    .frame(height: heights[id] ?? 24))
        ]
    }
}

@MainActor
private final class AnchorSupportPublicFixture {
    let probe: AnchorSupportPublicProbe
    let host: MountedLazyListTestHost
    let scroll: ViewNode
    let original: RetainedLazyListAccessibilityItem
    let originalHeight: Double
    let originalOffset: Double
    let anchorTop: Double

    init() throws {
        let probe = AnchorSupportPublicProbe()
        self.probe = probe
        let host = MountedLazyListTestHost(size: Size(width: 320, height: 80)) {
            List(probe.rows, id: \.self) { id in probe.makeRows(id) }.listStyle(.plain)
        }
        self.host = host
        XCTAssertNotNil(host.layout())
        let third = try host.rowRoot(anchorSupportPublicIdentifier(3))
        try host.scroll(to: third.resolvedFrame.minY + 2)
        let predecessor = try host.rowRoot(anchorSupportPublicIdentifier(2))
        originalHeight = predecessor.resolvedFrame.height
        let scroll = try host.scrollContainer()
        self.scroll = scroll
        originalOffset = scroll.scrollOffset
        anchorTop = try host.rowRoot(anchorSupportPublicIdentifier(3)).resolvedFrame.minY - scroll.resolvedScrollOffset
        let container = try host.list()
        let source = try XCTUnwrap(DeferredListScrollSource.attached(to: container))
        let metadata = try XCTUnwrap(source.row(at: 300))
        original = try XCTUnwrap(host.runtime.lazyListTarget(in: container, key: metadata.providerKey))
        XCTAssertEqual(originalHeight, 30, accuracy: 0.001)
        XCTAssertFalse(probe.factories.contains(300))
    }

    func stageReplacement() {
        probe.heights[2] = originalHeight + 40
        host.reload()
    }

    func prepare() throws -> RetainedLazyListAccessibilityItem? {
        let mutation = try XCTUnwrap(host.runtime.beginAccessibilityMutation())
        defer { host.runtime.endAccessibilityMutation(mutation) }
        return host.runtime.withLazyListResolutionBudget {
            host.runtime.prepareLazyListAccessibilityTarget(token: original.token, in: original, during: mutation)
        }
    }

    func close() {
        probe.onFactory = nil
        host.close()
    }
}

private func anchorSupportPublicIdentifier(_ id: Int) -> String { "anchor.support.public.\(id)" }
