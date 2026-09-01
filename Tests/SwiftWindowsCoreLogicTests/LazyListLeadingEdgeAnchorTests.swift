import SwiftWindowsCore
import SwiftWindowsLayout
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Keeps the enclosing scroll view at its leading edge without changing
/// keyed anchoring once the user has scrolled into its content.
@MainActor
final class LazyListLeadingEdgeAnchorTests: XCTestCase {
    func testColdReinsertionAtTheLeadingEdgeBuildsTheNewRowAndRejectsRetiredBindings() async throws {
        let probe = LeadingEdgeAnchorRecordProbe()
        let host = MountedLazyListTestHost { leadingEdgeAnchorRecordContent(probe) }
        defer {
            host.close()
            probe.clear()
        }
        XCTAssertNotNil(host.layout())
        let raw = try XCTUnwrap(probe.raw[0])
        let member = try XCTUnwrap(probe.members[0])
        let element = try XCTUnwrap(probe.elements[0])
        let oldOwner = try XCTUnwrap(probe.owners[0])
        weak var oldPayload = raw.wrappedValue.payload
        try host.scroll(to: 200)

        probe.rows.removeAll { $0.id == 0 }
        host.reload()
        XCTAssertNotNil(host.layout())
        probe.clear(row: 0)
        XCTAssertFalse(oldOwner.isLive)
        XCTAssertNil(host.coordinator.registry.owner(at: oldOwner.identity))
        XCTAssertNotNil(oldPayload, "The three intentionally escaped bindings still own the retired snapshot")

        probe.rows.insert(LeadingEdgeAnchorData(id: 0, seed: 900), at: 0)
        host.reload()
        try host.scroll(to: 0)

        let scroll = try host.scrollContainer()
        XCTAssertEqual(scroll.scrollOffset, 0)
        XCTAssertEqual(scroll.resolvedScrollOffset, 0)
        let replacement = try XCTUnwrap(probe.raw[0])
        let replacementOwner = try XCTUnwrap(probe.owners[0])
        XCTAssertFalse(replacementOwner === oldOwner)
        XCTAssertNotEqual(replacementOwner.generation, oldOwner.generation)
        XCTAssertEqual(replacement.wrappedValue.number, 900)
        let row = try host.rowRoot("leading.record.0")
        assertLeadingRowIsVisible(row, list: try host.list(), scroll: scroll)
        let invalidations = host.events.stateInvalidations

        let rejectedPayload = attemptLeadingEdgeAnchorRetiredRecordReplacement(raw)
        member.wrappedValue = 8_000
        element.wrappedValue = 9_000

        XCTAssertNil(rejectedPayload.value, "A rejected old setter must not retain its proposed replacement")
        XCTAssertEqual(raw.wrappedValue.number, 100)
        XCTAssertEqual(member.wrappedValue, 100)
        XCTAssertEqual(element.wrappedValue, 100)
        XCTAssertEqual(replacement.wrappedValue.number, 900)
        XCTAssertEqual(replacement.wrappedValue.values, [900, 901])
        XCTAssertEqual(host.events.stateInvalidations, invalidations)
        XCTAssertNotNil(oldPayload, "Read handles intentionally remain strong until this test returns")
    }

    func testReorderingAndPrependingAtTheLeadingEdgeKeepVisibleOwnersAndShowTheNewRow() async throws {
        let probe = LeadingEdgeAnchorStateProbe()
        let host = MountedLazyListTestHost(size: Size(width: 120, height: 80)) {
            leadingEdgeAnchorStateContent(probe)
        }
        defer {
            host.close()
            probe.clear()
        }
        XCTAssertNotNil(host.layout())
        let zero = try probe.capture(row: 0, in: host)
        let one = try probe.capture(row: 1, in: host)
        zero.counter.wrappedValue = 41
        one.counter.wrappedValue = 42
        XCTAssertNotNil(host.layout())
        XCTAssertEqual(probe.rows[0].key.description, probe.rows[1].key.description)
        XCTAssertNotEqual(probe.rows[0].key, probe.rows[1].key)
        let zeroRoot = try host.rowRoot("leading.state.0")
        let oneRoot = try host.rowRoot("leading.state.1")

        probe.rows.swapAt(0, 1)
        probe.rows.insert(LeadingEdgeAnchorData(id: 99, seed: 999), at: 0)
        host.reload()
        XCTAssertNotNil(host.layout())

        let scroll = try host.scrollContainer()
        XCTAssertEqual(scroll.scrollOffset, 0)
        XCTAssertEqual(scroll.resolvedScrollOffset, 0)
        XCTAssertTrue(try host.rowRoot("leading.state.0") === zeroRoot)
        XCTAssertTrue(try host.rowRoot("leading.state.1") === oneRoot)
        XCTAssertTrue(try probe.capture(row: 0, in: host).owner === zero.owner)
        XCTAssertTrue(try probe.capture(row: 1, in: host).owner === one.owner)
        XCTAssertEqual(zero.counter.wrappedValue, 41)
        XCTAssertEqual(one.counter.wrappedValue, 42)
        XCTAssertEqual(probe.objectFactoryCalls[0], 1)
        XCTAssertEqual(probe.objectFactoryCalls[1], 1)
        XCTAssertEqual(try probe.capture(row: 99, in: host).counter.wrappedValue, 999)
        let inserted = try host.rowRoot("leading.state.99")
        assertLeadingRowIsVisible(inserted, list: try host.list(), scroll: scroll)
    }

    func testReorderingAndPrependingPreserveTheKeyedAnchorAtAPositiveOffset() async throws {
        let probe = LeadingEdgeAnchorStateProbe()
        let host = MountedLazyListTestHost { leadingEdgeAnchorStateContent(probe) }
        defer {
            host.close()
            probe.clear()
        }
        XCTAssertNotNil(host.layout())
        try host.scroll(to: 40)
        let scroll = try host.scrollContainer()
        XCTAssertEqual(scroll.scrollOffset, 40)
        XCTAssertEqual(scroll.resolvedScrollOffset, 40)
        let two = try probe.capture(row: 2, in: host)
        let three = try probe.capture(row: 3, in: host)
        let twoRoot = try host.rowRoot("leading.state.2")
        let threeRoot = try host.rowRoot("leading.state.3")
        assertLeadingRowIsVisible(twoRoot, list: try host.list(), scroll: scroll)

        probe.rows.swapAt(0, 1)
        probe.rows.insert(LeadingEdgeAnchorData(id: 99, seed: 999), at: 0)
        host.reload()
        XCTAssertNotNil(host.layout())

        XCTAssertEqual(scroll.scrollOffset, 60)
        XCTAssertEqual(scroll.resolvedScrollOffset, 60)
        XCTAssertTrue(try host.rowRoot("leading.state.2") === twoRoot)
        XCTAssertTrue(try host.rowRoot("leading.state.3") === threeRoot)
        XCTAssertTrue(try probe.capture(row: 2, in: host).owner === two.owner)
        XCTAssertTrue(try probe.capture(row: 3, in: host).owner === three.owner)
        XCTAssertEqual(two.counter.wrappedValue, 102)
        XCTAssertEqual(three.counter.wrappedValue, 103)
        XCTAssertEqual(probe.objectFactoryCalls[2], 1)
        XCTAssertEqual(probe.objectFactoryCalls[3], 1)
        XCTAssertNil(probe.rowFactoryCalls[99])
        XCTAssertNil(host.find("leading.state.99"))
        assertLeadingRowIsVisible(twoRoot, list: try host.list(), scroll: scroll)
    }

    func testAListLocalLeadingEdgeBelowAHeaderStillPreservesItsKeyedAnchor() async throws {
        let fixture = try LeadingEdgeAnchorHeaderFixture()
        defer { fixture.close() }
        XCTAssertNotNil(fixture.runtime.resolvedLayoutFrame(of: fixture.scroll))
        XCTAssertEqual(fixture.probe.factoryCalls, [0])
        fixture.scroll.scrollOffset = 40
        XCTAssertNotNil(fixture.runtime.resolvedLayoutFrame(of: fixture.scroll))
        XCTAssertEqual(fixture.scroll.scrollOffset, 40)
        XCTAssertEqual(fixture.scroll.resolvedScrollOffset, 40)
        XCTAssertEqual(fixture.list.resolvedFrame.minY, 40)
        XCTAssertEqual(fixture.scroll.resolvedScrollOffset - fixture.list.resolvedFrame.minY, 0)
        let zero = try fixture.row(0)
        XCTAssertEqual(zero.resolvedFrame.minY, 0)
        assertLeadingRowIsVisible(zero, list: fixture.list, scroll: fixture.scroll)

        XCTAssertTrue(fixture.replaceValues([99] + Array(0..<32)))
        fixture.list.setRetainedLazyListMeasurementRevisions(content: 1, environment: 0)
        XCTAssertNotNil(fixture.runtime.resolvedLayoutFrame(of: fixture.scroll))

        XCTAssertEqual(fixture.scroll.scrollOffset, 60)
        XCTAssertEqual(fixture.scroll.resolvedScrollOffset, 60)
        XCTAssertEqual(fixture.list.resolvedFrame.minY, 40)
        XCTAssertTrue(try fixture.row(0) === zero)
        XCTAssertEqual(zero.resolvedFrame.minY, 20)
        XCTAssertEqual(fixture.list.children.compactMap(\.dynamicContentIndex), [0, 1, 2])
        XCTAssertEqual(fixture.probe.factoryCalls, [0, 1, 2, 0, 1, 2])
        XCTAssertFalse(fixture.list.children.contains { $0.dynamicContentIndex == 99 })
        assertLeadingRowIsVisible(zero, list: fixture.list, scroll: fixture.scroll)
    }

    /// Cached native reads only: these assertions must not request another
    /// layout pass to make a missing row or stale offset appear correct.
    private func assertLeadingRowIsVisible(
        _ row: ViewNode, list: ViewNode, scroll: ViewNode,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertTrue(row.parent === list, file: file, line: line)
        XCTAssertTrue(list.parent === scroll, file: file, line: line)
        XCTAssertTrue(list.children.contains { $0 === row }, file: file, line: line)
        XCTAssertGreaterThan(row.resolvedFrame.height, 0, file: file, line: line)
        let visibleTop = list.resolvedFrame.minY + row.resolvedFrame.minY - scroll.resolvedScrollOffset
        XCTAssertEqual(visibleTop, 0, file: file, line: line)
        XCTAssertLessThanOrEqual(
            visibleTop + row.resolvedFrame.height, scroll.resolvedFrame.height, file: file, line: line)
    }
}

private struct LeadingEdgeAnchorKey: Hashable, CustomStringConvertible {
    let value: Int
    var description: String { "same-description" }
}

private struct LeadingEdgeAnchorData {
    let id: Int
    let seed: Int
    var key: LeadingEdgeAnchorKey { LeadingEdgeAnchorKey(value: id) }
}

@MainActor
private struct LeadingEdgeAnchorStateCapture {
    let row: Int
    let owner: StateMountOwner
    let counter: Binding<Int>
    let objectValue: Binding<Int>
    let model: MountedLazyListModel
}

@MainActor
private final class LeadingEdgeAnchorStateProbe {
    var rows = (0..<32).map { LeadingEdgeAnchorData(id: $0, seed: 100 + $0) }
    private(set) var rowFactoryCalls: [Int: Int] = [:]
    private(set) var objectFactoryCalls: [Int: Int] = [:]
    private(set) var captures: [ObjectIdentifier: LeadingEdgeAnchorStateCapture] = [:]
    private(set) var appearances: [Int: Int] = [:]
    private(set) var disappearances: [Int: Int] = [:]
    private(set) var missingOwnerCount = 0
    private var nextObjectSerial = 0

    func makeRow(_ data: LeadingEdgeAnchorData) -> LeadingEdgeAnchorStateRow {
        rowFactoryCalls[data.id, default: 0] += 1
        return LeadingEdgeAnchorStateRow(data: data, probe: self)
    }

    func makeModel(row: Int, seed: Int) -> MountedLazyListModel {
        objectFactoryCalls[row, default: 0] += 1
        nextObjectSerial += 1
        return MountedLazyListModel(value: seed, serial: nextObjectSerial)
    }

    func record(
        row: Int, owner: StateMountOwner?, counter: Binding<Int>,
        objectValue: Binding<Int>, model: MountedLazyListModel
    ) {
        guard let owner else {
            missingOwnerCount += 1
            return
        }
        captures[ObjectIdentifier(owner)] = LeadingEdgeAnchorStateCapture(
            row: row, owner: owner, counter: counter, objectValue: objectValue, model: model)
    }

    func capture(
        row: Int, in host: MountedLazyListTestHost,
        file: StaticString = #filePath, line: UInt = #line
    ) throws -> LeadingEdgeAnchorStateCapture {
        let matches = captures.values.filter {
            $0.row == row && host.coordinator.registry.owner(at: $0.owner.identity) === $0.owner
        }
        XCTAssertEqual(matches.count, 1, "Expected one installed owner for row \(row)", file: file, line: line)
        return try XCTUnwrap(matches.first, file: file, line: line)
    }

    func didAppear(_ row: Int) { appearances[row, default: 0] += 1 }
    func didDisappear(_ row: Int) { disappearances[row, default: 0] += 1 }
    func clear() { captures.removeAll() }
}

@MainActor
private struct LeadingEdgeAnchorStateRow: View {
    @State private var counter: Int
    @StateObject private var model: MountedLazyListModel
    let row: Int
    let probe: LeadingEdgeAnchorStateProbe

    init(data: LeadingEdgeAnchorData, probe: LeadingEdgeAnchorStateProbe) {
        row = data.id
        self.probe = probe
        _counter = State(initialValue: data.seed)
        _model = StateObject(wrappedValue: probe.makeModel(row: data.id, seed: data.seed))
    }

    var body: some View {
        let row = self.row
        let probe = self.probe
        probe.record(
            row: row, owner: ViewBuildContextScope.current?.viewIdentity.installedOwner,
            counter: $counter, objectValue: $model.value, model: model)
        return Color.blue.frame(width: 120, height: 20)
            .accessibilityIdentifier("leading.state.\(row)")
            .onAppear { [weak probe] in probe?.didAppear(row) }
            .onDisappear { [weak probe] in probe?.didDisappear(row) }
    }
}

@MainActor
private func leadingEdgeAnchorStateContent(_ probe: LeadingEdgeAnchorStateProbe) -> some View {
    ManagedLazyListContent(
        probe.rows, id: \.key, estimatedExtent: 20, prefetchExtent: 0,
        maximumMountedRecords: 8, maximumMountedLeaves: 16, maximumProtectedRecords: 2
    ) { data in probe.makeRow(data) }
}

private final class LeadingEdgeAnchorPayload {
    let number: Int
    init(_ number: Int) { self.number = number }
}

private struct LeadingEdgeAnchorRecord {
    var number: Int
    var values: [Int]
    var payload: LeadingEdgeAnchorPayload
}

@MainActor
private final class LeadingEdgeAnchorWeakPayload {
    weak var value: LeadingEdgeAnchorPayload?
    init(_ value: LeadingEdgeAnchorPayload) { self.value = value }
}

@MainActor
private final class LeadingEdgeAnchorRecordProbe {
    var rows = (0..<32).map { LeadingEdgeAnchorData(id: $0, seed: 100 + $0) }
    var raw: [Int: Binding<LeadingEdgeAnchorRecord>] = [:]
    var members: [Int: Binding<Int>] = [:]
    var elements: [Int: Binding<Int>] = [:]
    var owners: [Int: StateMountOwner] = [:]

    func clear(row: Int) {
        raw.removeValue(forKey: row)
        members.removeValue(forKey: row)
        elements.removeValue(forKey: row)
        owners.removeValue(forKey: row)
    }

    func clear() {
        raw.removeAll()
        members.removeAll()
        elements.removeAll()
        owners.removeAll()
    }
}

@MainActor
private struct LeadingEdgeAnchorRecordRow: View {
    @State private var record: LeadingEdgeAnchorRecord
    let row: Int
    let probe: LeadingEdgeAnchorRecordProbe

    init(data: LeadingEdgeAnchorData, probe: LeadingEdgeAnchorRecordProbe) {
        row = data.id
        self.probe = probe
        _record = State(
            initialValue: LeadingEdgeAnchorRecord(
                number: data.seed, values: [data.seed, data.seed + 1], payload: LeadingEdgeAnchorPayload(data.seed)))
    }

    var body: some View {
        probe.raw[row] = $record
        probe.members[row] = $record.number
        probe.elements[row] = $record.values[0]
        probe.owners[row] = ViewBuildContextScope.current?.viewIdentity.installedOwner
        return Color.green.frame(width: 120, height: 20)
            .accessibilityIdentifier("leading.record.\(row)")
    }
}

@MainActor
private func leadingEdgeAnchorRecordContent(_ probe: LeadingEdgeAnchorRecordProbe) -> some View {
    ManagedLazyListContent(
        probe.rows, id: \.key, estimatedExtent: 20, prefetchExtent: 0,
        maximumMountedRecords: 8, maximumMountedLeaves: 16, maximumProtectedRecords: 2
    ) { data in LeadingEdgeAnchorRecordRow(data: data, probe: probe) }
}

@MainActor
private func attemptLeadingEdgeAnchorRetiredRecordReplacement(
    _ binding: Binding<LeadingEdgeAnchorRecord>
) -> LeadingEdgeAnchorWeakPayload {
    let payload = LeadingEdgeAnchorPayload(7_000)
    let weakPayload = LeadingEdgeAnchorWeakPayload(payload)
    binding.wrappedValue = LeadingEdgeAnchorRecord(number: 7_000, values: [7_000], payload: payload)
    return weakPayload
}

private enum LeadingEdgeAnchorFixtureError: Error { case source }

/// The header control needs only native geometry. Its provider and checked
/// adopter are unchanged; the test lease supplies the ordinary build scope.
@MainActor
private final class LeadingEdgeAnchorHeaderFixture {
    static let identityRoot = RetainedViewIdentity(segments: [.role(.content), .slot(0)])
    let source: RetainedLazyListDataSource<Int, [ViewNode]>
    let adapter: RetainedLazyListRuntimeAdapter
    let list: ViewNode
    let scroll: ViewNode
    let runtime: RetainedViewRuntime
    let probe: LeadingEdgeAnchorNativeProbe

    init() throws {
        let source = RetainedLazyListDataSource<Int, [ViewNode]>()
        let probe = LeadingEdgeAnchorNativeProbe()
        guard Self.replace(Array(0..<32), in: source, probe: probe) else {
            throw LeadingEdgeAnchorFixtureError.source
        }
        let adapter = try XCTUnwrap(
            RetainedLazyListRuntimeAdapter(
                provider: source, estimatedExtent: 20, prefetchExtent: 0,
                maximumMountedRecords: 8, maximumMountedLeaves: 16, maximumProtectedRecords: 2))
        let list = ViewNode(layoutMode: .lazyStack(.vertical(spacing: 0, alignment: .stretch)))
        list.retainedLazyListAdapter = adapter
        list.retainedSubtreeBuildLease = LeadingEdgeAnchorLease()
        let header = ViewNode(preferredSize: Size(width: 120, height: 40))
        let scroll = ViewNode(
            frame: Rect(x: 0, y: 0, width: 120, height: 60), clipsToBounds: true,
            layoutMode: .stack(.vertical(spacing: 0, alignment: .stretch)), scrollAxis: .vertical,
            children: [header, list])
        let runtime = RetainedViewRuntime(root: scroll)
        runtime.clock = { 0 }
        self.source = source
        self.adapter = adapter
        self.list = list
        self.scroll = scroll
        self.runtime = runtime
        self.probe = probe
    }

    func row(_ id: Int) throws -> ViewNode {
        try XCTUnwrap(list.children.first { $0.dynamicContentIndex == id })
    }

    func replaceValues(_ values: [Int]) -> Bool {
        Self.replace(values, in: source, probe: probe)
    }

    func close() { source.close() }

    private static func replace(
        _ values: [Int], in source: RetainedLazyListDataSource<Int, [ViewNode]>,
        probe: LeadingEdgeAnchorNativeProbe
    ) -> Bool {
        source.replaceData(values, id: \.self, identityRoot: identityRoot) { [probe] value, prefix in
            probe.makeNode(value, prefix: prefix)
        }
    }
}

@MainActor
private final class LeadingEdgeAnchorNativeProbe {
    private(set) var factoryCalls: [Int] = []

    func makeNode(_ value: Int, prefix: RetainedViewIdentity) -> [ViewNode] {
        factoryCalls.append(value)
        let node = ViewNode(preferredSize: Size(width: 120, height: 20))
        node.retainedViewIdentity = prefix.appending(.slot(0))
        node.dynamicContentIndex = value
        node.accessibilityIdentifier = "leading.header.\(value)"
        return [node]
    }
}

@MainActor
private final class LeadingEdgeAnchorLease: RetainedSubtreeBuildLease {
    var canBuild: Bool { true }

    func beginBuild() -> (any RetainedBuildEpoch)? { LeadingEdgeAnchorEpoch() }
}

@MainActor
private final class LeadingEdgeAnchorEpoch: RetainedBuildEpoch {
    private var leftConstruction = false
    private var wasSuperseded = false

    var canAdopt: Bool { !leftConstruction && !wasSuperseded }
    var canComplete: Bool { true }

    func supersede() {
        if !leftConstruction { wasSuperseded = true }
    }

    func willAdopt() -> Bool {
        guard canAdopt else { return false }
        leftConstruction = true
        return true
    }

    func commit() {}
    func abandon() {}
    func finishAfterCallbacks() {}
}
